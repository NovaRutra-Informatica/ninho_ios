import Foundation
import ZIPFoundation

public struct CompactBackupInfo: Equatable, Sendable {
    public let url: URL
    public let createdAt: String
    public let stateHash: String
    public let bytes: Int
}

private struct CompactManifest: Codable {
    var format = "NinhoCompactBackup"
    var version = 1
    var includesAttachments = false
    var createdAt: String
    var stateVersion: Int
    var stateBytes: Int
    var sha256: String
    var activityBytes: Int?
    var activitySHA256: String?
}

public enum CompactBackup {
    public static let archiveLimit = 8 * 1024 * 1024
    public static let retainedDays = 7
    public static func recognizes(_ source: URL) throws -> Bool {
        _ = try MaterialSafety.regular(source, maximum: MaterialSafety.backupLimit)
        let archive = try Archive(url: source, accessMode: .read)
        guard let entry = archive["manifest.json"], entry.type == .file, entry.uncompressedSize <= 4_096 else { return false }
        var bytes = Data()
        let crc = try archive.extract(entry) { block in
            try MaterialSafety.require(bytes.count + block.count <= 4_096, "Manifesto de backup inválido.")
            bytes.append(block)
        }
        guard crc == entry.checksum, let value = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { return false }
        return value["format"] as? String == "NinhoCompactBackup"
    }
    public static func lightweight(_ state: AppState) throws -> AppState {
        try StudyEngine.validate(state)
        return state
    }
    public static func read(from source: URL) throws -> (state: AppState, activity: LocalActivity?, info: CompactBackupInfo) {
        let bytes = try MaterialSafety.regular(source, maximum: archiveLimit)
        let archive = try Archive(url: source, accessMode: .read)
        let entries = Array(archive.prefix(4))
        let names = Set(entries.map(\.path))
        try MaterialSafety.require(entries.count == names.count && (names == ["state.json", "manifest.json"] || names == ["state.json", "manifest.json", "activity.json"]), "Escolha um backup compacto do Ninho, sem anexos.")
        func extract(_ name: String, limit: Int) throws -> Data {
            guard let entry = archive[name], entry.type == .file else { throw LibraryError.invalid("Arquivo de backup inválido.") }
            try MaterialSafety.require(entry.uncompressedSize <= UInt64(limit), "O backup descompactado excede o limite.")
            var data = Data()
            let checksum = try archive.extract(entry, bufferSize: 65_536) { block in
                try Task.checkCancellation()
                try MaterialSafety.require(data.count + block.count <= limit, "O backup excede o limite de dados.")
                data.append(block)
            }
            try MaterialSafety.require(checksum == entry.checksum && data.count == entry.uncompressedSize, "O backup está incompleto ou corrompido.")
            return data
        }
        let manifest = try JSONDecoder().decode(CompactManifest.self, from: extract("manifest.json", limit: 4_096))
        try MaterialSafety.require(manifest.format == "NinhoCompactBackup" && manifest.version == 1 && !manifest.includesAttachments && StudyEngine.parseTimestamp(manifest.createdAt) != nil, "Versão de backup compacto não reconhecida.")
        let data = try extract("state.json", limit: MaterialSafety.stateLimit)
        try MaterialSafety.require(data.count == manifest.stateBytes && MaterialSafety.digest(data) == manifest.sha256, "Os dados do backup estão corrompidos.")
        let state = try MaterialSafety.decodeState(data)
        try MaterialSafety.require(state.version == manifest.stateVersion, "Este backup compacto contém dados incompatíveis.")
        var activity: LocalActivity?, activityData = Data()
        if names.contains("activity.json") {
            activityData = try extract("activity.json", limit: 262_144)
            try MaterialSafety.require(activityData.count == manifest.activityBytes && MaterialSafety.digest(activityData) == manifest.activitySHA256, "O histórico agregado do backup está corrompido.")
            activity = try JSONDecoder().decode(LocalActivity.self, from: activityData)
            try activity?.validate()
        } else { try MaterialSafety.require(manifest.activityBytes == nil && manifest.activitySHA256 == nil, "O histórico agregado do backup está ausente.") }
        return (state, activity, CompactBackupInfo(url: source, createdAt: manifest.createdAt, stateHash: MaterialSafety.digest(data + activityData), bytes: bytes))
    }
    public static func write(_ state: AppState, activity: LocalActivity? = nil, to destination: URL, at date: Date = Date()) throws -> CompactBackupInfo {
        try Task.checkCancellation()
        let state = try lightweight(state)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)
        try MaterialSafety.require(data.count <= MaterialSafety.stateLimit, "A coleção excede o limite do backup compacto.")
        var activity = activity
        try activity?.validate(); activity?.prune(at: date)
        let activityData = try activity.map { try encoder.encode($0) }
        try MaterialSafety.require((activityData?.count ?? 0) <= 262_144, "O histórico agregado excede o limite de 256 KiB.")
        let hash = MaterialSafety.digest(data + (activityData ?? Data()))
        if let previous = try? read(from: destination), previous.info.stateHash == hash { return previous.info }
        try MaterialSafety.directory(destination.deletingLastPathComponent())
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".compact-writing")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let archive = try Archive(url: temporary, accessMode: .create)
        func add(_ value: Data, name: String) throws {
            try archive.addEntry(with: name, type: .file, uncompressedSize: Int64(value.count), compressionMethod: .deflate) { offset, count in
                try Task.checkCancellation()
                return value.subdata(in: Int(offset)..<min(Int(offset) + count, value.count))
            }
        }
        try add(data, name: "state.json")
        if let activityData { try add(activityData, name: "activity.json") }
        let manifest = CompactManifest(createdAt: StudyEngine.timestamp(date), stateVersion: state.version, stateBytes: data.count, sha256: MaterialSafety.digest(data), activityBytes: activityData?.count, activitySHA256: activityData.map(MaterialSafety.digest))
        try add(try encoder.encode(manifest), name: "manifest.json")
        _ = try read(from: temporary)
        try Task.checkCancellation()
        try MaterialSafety.read(temporary, maximum: archiveLimit).write(to: destination, options: .atomic)
        return try read(from: destination).info
    }
}

public actor CompactBackupStore {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func save(_ state: AppState, activity: LocalActivity? = nil, at date: Date = Date(), calendar: Calendar = .current) throws -> CompactBackupInfo {
        try MaterialSafety.directory(directory)
        let path = directory.appendingPathComponent("Ninho-\(StudyEngine.localDate(date, calendar: calendar)).compact.zip")
        let info = try CompactBackup.write(state, activity: activity, to: path, at: date)
        let existing = try files()
        for old in existing.dropFirst(CompactBackup.retainedDays) { try FileManager.default.removeItem(at: old) }
        for partial in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where partial.pathExtension == "compact-writing" && UUID(uuidString: partial.deletingPathExtension().lastPathComponent) != nil {
            try? FileManager.default.removeItem(at: partial)
        }
        return info
    }
    public func newest() throws -> (state: AppState, activity: LocalActivity?, info: CompactBackupInfo)? {
        for file in try files() { if let value = try? CompactBackup.read(from: file) { return value } }
        return nil
    }
    public func list() throws -> [CompactBackupInfo] { try files().compactMap { try? CompactBackup.read(from: $0).info } }
    private func files() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        try MaterialSafety.existingDirectory(directory)
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.range(of: #"^Ninho-\d{4}-\d{2}-\d{2}\.compact\.zip$"#, options: .regularExpression) != nil }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
}
