import Foundation
import NinhoCore

struct CompactBackupStatus: Sendable {
    var local: CompactBackupInfo?
    var cloudMessage = ""
    var cloudRecoveryAvailable = false
    var cloudAvailable = false
    var cloudEnabled = false
}

struct CloudSnapshotListing: Sendable {
    var urls: [URL]
    var complete: Bool
}

actor CompactBackupCoordinator {
    let local: CompactBackupStore
    private let cloudContainer: @Sendable () -> URL?
    private let discover: @Sendable (URL) async -> CloudSnapshotListing
    private let preference: URL
    private let recoveryRequirement: URL
    private let usesCloud: Bool
    private var enabled: Bool?
    private var lastCloudRotationDay: String?

    init(localDirectory: URL, usesCloud: Bool, cloudContainer: (@Sendable () -> URL?)? = nil,
         discover: @escaping @Sendable (URL) async -> CloudSnapshotListing = { await ICloudSnapshotDiscovery.find(in: $0) }) {
        local = CompactBackupStore(directory: localDirectory)
        preference = localDirectory.appendingPathComponent("cloud-preference.json")
        recoveryRequirement = localDirectory.appendingPathComponent("cloud-recovery-required.json")
        let identifier = Bundle.main.object(forInfoDictionaryKey: "NinhoICloudContainer") as? String
        self.cloudContainer = cloudContainer ?? {
            guard let identifier, !identifier.isEmpty, !identifier.contains("$(") else { return nil }
            return FileManager.default.url(forUbiquityContainerIdentifier: identifier)
        }
        self.discover = discover
        self.usesCloud = usesCloud
    }
    func cloudEnabled() -> Bool {
        cloudRequested() && cloudAvailable()
    }
    func cloudAvailable() -> Bool { cloudDirectory() != nil }
    private func cloudRequested() -> Bool {
        if let enabled { return enabled }
        let value = (try? JSONDecoder().decode(Bool.self, from: Data(contentsOf: preference))) ?? false
        enabled = value; return value
    }
    func setCloudEnabled(_ value: Bool) throws {
        if value && !cloudAvailable() { throw CloudBackupUnavailable() }
        try FileManager.default.createDirectory(at: preference.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: preference, options: .atomic)
        enabled = value
    }
    func requireInitialCloudRecovery() throws {
        guard usesCloud else { return }
        try FileManager.default.createDirectory(at: recoveryRequirement.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("true".utf8).write(to: recoveryRequirement, options: .atomic)
    }
    func finishInitialCloudRecovery() throws {
        if FileManager.default.fileExists(atPath: recoveryRequirement.path) {
            try FileManager.default.removeItem(at: recoveryRequirement)
        }
    }
    func save(_ state: AppState, activity: LocalActivity, at date: Date) async throws -> CompactBackupStatus {
        let info = try await local.save(state, activity: activity, at: date)
        try Task.checkCancellation()
        let available = cloudAvailable()
        var status = CompactBackupStatus(local: info, cloudMessage: available ? "" : CloudBackupUnavailable().localizedDescription,
                                         cloudAvailable: available, cloudEnabled: cloudRequested() && available)
        var snapshotDirectory = info.url.deletingLastPathComponent()
        var include = URLResourceValues(); include.isExcludedFromBackup = false
        try? snapshotDirectory.setResourceValues(include)
        guard cloudRequested() else { return status }
        do {
            guard let cloud = cloudDirectory() else { status.cloudMessage = CloudBackupUnavailable().localizedDescription; return status }
            if FileManager.default.fileExists(atPath: recoveryRequirement.path) {
                let previous = try await recoveryFromCloud(requestDownload: true)
                defer { if let previous { try? FileManager.default.removeItem(at: previous.url) } }
                try Task.checkCancellation()
                status.cloudAvailable = cloudAvailable()
                status.cloudEnabled = cloudRequested() && status.cloudAvailable
                guard status.cloudEnabled else { return status }
                if previous != nil {
                    status.cloudRecoveryAvailable = true
                    status.cloudMessage = "Existe uma cópia anterior no iCloud. O envio está pausado para preservá-la. Use Recuperar do iCloud antes de enviar esta coleção."
                    return status
                }
                try finishInitialCloudRecovery()
            }
            try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
            let destination = cloud.appendingPathComponent(info.url.lastPathComponent)
            let data = try Data(contentsOf: info.url)
            try Task.checkCancellation()
            try coordinatedWrite(data, to: destination)
            // Include remote documents even if only provider placeholders exist locally.
            let day = StudyEngine.localDate(date)
            let indexed = lastCloudRotationDay == day ? [] : await discover(cloud).urls
            try Task.checkCancellation()
            status.cloudAvailable = cloudAvailable()
            status.cloudEnabled = cloudRequested() && status.cloudAvailable
            guard status.cloudEnabled else { return status }
            let localNames = try FileManager.default.contentsOfDirectory(at: cloud, includingPropertiesForKeys: nil)
            let names = Set(localNames + indexed)
                .filter { $0.lastPathComponent.range(of: #"^Ninho-\d{4}-\d{2}-\d{2}\.compact\.zip$"#, options: .regularExpression) != nil }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
            for old in names.dropFirst(CompactBackup.retainedDays) {
                try Task.checkCancellation()
                var coordinationError: NSError?
                NSFileCoordinator().coordinate(writingItemAt: old, options: .forDeleting, error: &coordinationError) { url in try? FileManager.default.removeItem(at: url) }
            }
            lastCloudRotationDay = day
            status.cloudMessage = "Cópia entregue ao iCloud Drive. O iOS controla o envio; sem conexão, ele pode ficar pendente."
        } catch {
            status.cloudAvailable = cloudAvailable()
            status.cloudEnabled = cloudRequested() && status.cloudAvailable
            status.cloudMessage = cloudRequested() ? "A cópia local está salva. O iCloud Drive não recebeu esta atualização: \(error.localizedDescription)" : "Envio automático desligado. Cópias já existentes no iCloud não foram apagadas."
        }
        return status
    }
    func localRecovery() async throws -> CompactBackupInfo? { try await local.newest()?.info }
    func recoveryFromCloud(requestDownload: Bool) async throws -> CompactBackupInfo? {
        guard let directory = cloudDirectory() else { throw CloudBackupUnavailable() }
        let listing = await discover(directory)
        try Task.checkCancellation()
        guard listing.complete else { throw CloudRecoveryPending() }
        let localFiles = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.ubiquitousItemDownloadingStatusKey])) ?? []
        let files = Set(listing.urls + localFiles)
            .filter { $0.lastPathComponent.range(of: #"^Ninho-\d{4}-\d{2}-\d{2}\.compact\.zip$"#, options: .regularExpression) != nil }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for file in files {
            let values = try? file.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
            if values == nil || (values?.isUbiquitousItem == true && values?.ubiquitousItemDownloadingStatus != .current) {
                if requestDownload { try FileManager.default.startDownloadingUbiquitousItem(at: file) }
                throw CloudRecoveryPending()
            }
            do { return try coordinatedRead(file) }
            catch is CancellationError { throw CancellationError() }
            catch { continue }
        }
        if !files.isEmpty { throw CloudBackupUnreadable() }
        return nil
    }
    func initialCloudRecovery(attempts: Int = 3, retryDelay: Duration = .seconds(1)) async throws -> CompactBackupInfo? {
        try Task.checkCancellation()
        guard cloudAvailable() else { throw CloudBackupUnavailable() }
        for attempt in 0..<max(1, attempts) {
            do { return try await recoveryFromCloud(requestDownload: true) }
            catch is CloudRecoveryPending {
                if attempt + 1 >= max(1, attempts) { throw CloudRecoveryPending() }
                try await Task.sleep(for: retryDelay)
            }
        }
        return nil
    }
    func export(_ state: AppState, activity: LocalActivity, at date: Date) async throws -> URL {
        let info = try await local.save(state, activity: activity, at: date)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Ninho-\(StudyEngine.localDate(date))-\(UUID().uuidString.prefix(6)).compact.zip")
        try Data(contentsOf: info.url).write(to: url, options: .atomic)
        return url
    }
    private func cloudDirectory() -> URL? {
        guard usesCloud, let container = cloudContainer() else { return nil }
        return container.appendingPathComponent("Documents/CompactBackups", isDirectory: true)
    }
    private func coordinatedWrite(_ data: Data, to destination: URL) throws {
        var coordinationError: NSError?, writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: destination, options: .forReplacing, error: &coordinationError) { url in
            do {
                // Avoid uploading byte-identical snapshots every time the app is foregrounded.
                let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
                if size == data.count, let existing = try? Data(contentsOf: url), existing == data { return }
                try data.write(to: url, options: .atomic)
            } catch { writeError = error }
        }
        if let error = coordinationError ?? (writeError as NSError?) { throw error }
    }
    private func coordinatedRead(_ source: URL) throws -> CompactBackupInfo {
        var coordinationError: NSError?, readError: Error?, result: CompactBackupInfo?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { url in
            do {
                _ = try CompactBackup.read(from: url)
                let copy = FileManager.default.temporaryDirectory.appendingPathComponent("Ninho-cloud-recovery-\(UUID().uuidString).compact.zip")
                try Data(contentsOf: url).write(to: copy, options: .atomic)
                result = try CompactBackup.read(from: copy).info
            } catch { readError = error }
        }
        if let error = coordinationError ?? (readError as NSError?) { throw error }
        guard let result else { throw CloudRecoveryPending() }
        return result
    }
}

@MainActor final class ICloudSnapshotDiscovery {
    private let query = NSMetadataQuery()
    private var observer: NSObjectProtocol?
    private var timeout: Task<Void, Never>?
    private var continuation: CheckedContinuation<CloudSnapshotListing, Never>?
    private let directory: URL
    private init(directory: URL) { self.directory = directory }
    static func find(in directory: URL) async -> CloudSnapshotListing {
        let search = ICloudSnapshotDiscovery(directory: directory)
        return await search.run()
    }
    private func run() async -> CloudSnapshotListing {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
                query.predicate = NSPredicate(format: "%K LIKE %@", NSMetadataItemFSNameKey, "Ninho-*.compact.zip")
                query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSNameKey, ascending: false)]
                observer = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.finish(complete: true) }
                }
                guard !Task.isCancelled, query.start() else { finish(); return }
                timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(4)) } catch { return }
                    self?.finish()
                }
            }
        } onCancel: { Task { @MainActor [weak self] in self?.finish() } }
    }
    private func finish(complete: Bool = false) {
        guard let continuation else { return }
        self.continuation = nil
        query.disableUpdates()
        let complete = complete && query.resultCount <= 100
        let parent = directory.standardizedFileURL.path + "/"
        let urls = query.results.prefix(100).compactMap { item -> URL? in
            guard let item = item as? NSMetadataItem, let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL,
                  url.standardizedFileURL.path.hasPrefix(parent) else { return nil }
            return url
        }
        query.stop(); timeout?.cancel(); timeout = nil
        if let observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
        continuation.resume(returning: CloudSnapshotListing(urls: urls, complete: complete))
    }
}

struct CloudRecoveryPending: Error, LocalizedError {
    var errorDescription: String? { "O iCloud ainda está procurando ou baixando sua cópia. A cópia anterior será preservada. Mantenha a conexão; o Ninho tentará novamente ao voltar para o aplicativo." }
}

struct CloudBackupUnavailable: Error, LocalizedError {
    var errorDescription: String? { "O backup automático do iCloud não está disponível nesta instalação ou conta. A instalação com conta gratuita de desenvolvedor não permite esse recurso. A cópia local é apagada junto com o Ninho e não protege contra a exclusão do aplicativo." }
}

struct CloudBackupUnreadable: Error, LocalizedError {
    var errorDescription: String? { "Encontrei cópias no iCloud, mas não consegui validar nenhuma. Elas foram preservadas; nenhuma coleção vazia será enviada para substituí-las. Confira sua conexão e tente novamente." }
}
