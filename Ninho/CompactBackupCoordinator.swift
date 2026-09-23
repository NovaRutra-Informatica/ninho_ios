import Foundation
import NinhoCore

struct CompactBackupStatus: Sendable {
    var local: CompactBackupInfo?
    var cloudMessage = ""
    var cloudRecoveryAvailable = false
}

actor CompactBackupCoordinator {
    let local: CompactBackupStore
    private let cloudIdentifier: String?
    private let preference: URL
    private let usesCloud: Bool
    private var enabled: Bool?
    private var lastCloudRotationDay: String?

    init(localDirectory: URL, usesCloud: Bool) {
        local = CompactBackupStore(directory: localDirectory)
        preference = localDirectory.appendingPathComponent("cloud-preference.json")
        cloudIdentifier = Bundle.main.object(forInfoDictionaryKey: "NinhoICloudContainer") as? String
        self.usesCloud = usesCloud
    }
    func cloudEnabled() -> Bool {
        if let enabled { return enabled }
        let value = (try? JSONDecoder().decode(Bool.self, from: Data(contentsOf: preference))) ?? false
        enabled = value; return value
    }
    func setCloudEnabled(_ value: Bool) throws {
        try FileManager.default.createDirectory(at: preference.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: preference, options: .atomic)
        enabled = value
    }
    func save(_ state: AppState, activity: LocalActivity, at date: Date) async throws -> CompactBackupStatus {
        let info = try await local.save(state, activity: activity, at: date)
        try Task.checkCancellation()
        var status = CompactBackupStatus(local: info)
        var snapshotDirectory = info.url.deletingLastPathComponent()
        var include = URLResourceValues(); include.isExcludedFromBackup = false
        try? snapshotDirectory.setResourceValues(include)
        guard cloudEnabled() else { return status }
        do {
            guard let cloud = cloudDirectory() else { status.cloudMessage = "iCloud Drive indisponível. A cópia local continua salva; confira sua conta e o iCloud Drive nos Ajustes do iPhone."; return status }
            try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
            let destination = cloud.appendingPathComponent(info.url.lastPathComponent)
            let data = try Data(contentsOf: info.url)
            try Task.checkCancellation()
            try coordinatedWrite(data, to: destination)
            // Include remote documents even if only provider placeholders exist locally.
            let day = StudyEngine.localDate(date)
            let indexed = lastCloudRotationDay == day ? [] : await ICloudSnapshotDiscovery.find(in: cloud)
            try Task.checkCancellation()
            guard cloudEnabled() else { return status }
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
        } catch { status.cloudMessage = "A cópia local está salva. O iCloud Drive não recebeu esta atualização: \(error.localizedDescription)" }
        return status
    }
    func localRecovery() async throws -> CompactBackupInfo? { try await local.newest()?.info }
    func recoveryFromCloud(requestDownload: Bool) async throws -> CompactBackupInfo? {
        guard let directory = cloudDirectory() else { return nil }
        let indexed = await ICloudSnapshotDiscovery.find(in: directory)
        try Task.checkCancellation()
        let localFiles = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.ubiquitousItemDownloadingStatusKey])) ?? []
        let files = Set(indexed + localFiles)
            .filter { $0.lastPathComponent.range(of: #"^Ninho-\d{4}-\d{2}-\d{2}\.compact\.zip$"#, options: .regularExpression) != nil }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for file in files {
            let values = try? file.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
            if values == nil || (values?.isUbiquitousItem == true && values?.ubiquitousItemDownloadingStatus != .current) {
                if requestDownload { try FileManager.default.startDownloadingUbiquitousItem(at: file) }
                throw CloudRecoveryPending()
            }
            if let result = try? coordinatedRead(file) { return result }
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
        guard usesCloud, let cloudIdentifier, !cloudIdentifier.contains("$("),
              let container = FileManager.default.url(forUbiquityContainerIdentifier: cloudIdentifier) else { return nil }
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

@MainActor private final class ICloudSnapshotDiscovery {
    private let query = NSMetadataQuery()
    private var observer: NSObjectProtocol?
    private var timeout: Task<Void, Never>?
    private var continuation: CheckedContinuation<[URL], Never>?
    private let directory: URL
    private init(directory: URL) { self.directory = directory }
    static func find(in directory: URL) async -> [URL] {
        let search = ICloudSnapshotDiscovery(directory: directory)
        return await search.run()
    }
    private func run() async -> [URL] {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
                query.predicate = NSPredicate(format: "%K LIKE %@", NSMetadataItemFSNameKey, "Ninho-*.compact.zip")
                query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSNameKey, ascending: false)]
                observer = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.finish() }
                }
                guard !Task.isCancelled, query.start() else { finish(); return }
                timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(4)) } catch { return }
                    self?.finish()
                }
            }
        } onCancel: { Task { @MainActor [weak self] in self?.finish() } }
    }
    private func finish() {
        guard let continuation else { return }
        self.continuation = nil
        query.disableUpdates()
        let parent = directory.standardizedFileURL.path + "/"
        let urls = query.results.prefix(100).compactMap { item -> URL? in
            guard let item = item as? NSMetadataItem, let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL,
                  url.standardizedFileURL.path.hasPrefix(parent) else { return nil }
            return url
        }
        query.stop(); timeout?.cancel(); timeout = nil
        if let observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
        continuation.resume(returning: urls)
    }
}

struct CloudRecoveryPending: Error, LocalizedError {
    var errorDescription: String? { "Há uma cópia no iCloud que ainda precisa ser baixada. Toque em Recuperar do iCloud, mantenha uma conexão disponível e tente novamente quando o iOS concluir o download." }
}
