import Foundation

public enum OptionalAssistantEngine: String, Codable, CaseIterable, Sendable {
    case embedded, apple, imported
}

public struct ImportedModel: Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let originalFilename: String
    public let byteCount: Int64
    public var storedFilename: String { "\(id.uuidString).gguf" }
}

public struct ModelSelection: Codable, Equatable, Sendable {
    public var version = 1
    public var engine: OptionalAssistantEngine = .embedded
    public var model: ImportedModel?
    public init() {}
}

public enum ModelImportFailure: Error, LocalizedError, Equatable {
    case extensionMismatch, size, invalidFile, unsupported, missing, selection
    public var errorDescription: String? {
        switch self {
        case .extensionMismatch: "Selecione um único arquivo .gguf. ZIP, .safetensors, .task e .litertlm não funcionam nesta versão para iPhone."
        case .size: "O modelo precisa ter entre 1 MB e 1,2 GiB. Use Qwen2.5 0.5B ou 1.5B Instruct Q4_K_M."
        case .invalidFile: "Este GGUF está incompleto ou inválido. Copie novamente o arquivo inteiro para o iPhone."
        case .unsupported: "Use Qwen2.5 0.5B ou 1.5B Instruct, quantização Q4_K_M, em um único GGUF. Outros formatos e modelos ainda não são aceitos."
        case .missing: "O arquivo importado não está mais disponível. Importe-o novamente ou escolha o acompanhamento incluído."
        case .selection: "Não foi possível ler a configuração do modelo local. Seu perfil e seus estudos continuam preservados."
        }
    }
}

/// Inspects bounded GGUF metadata before any native tensor allocation. No untrusted paths
/// or archives are extracted. The native runtime separately verifies and loads all weights.
public enum GGUFImportPolicy {
    public static let maximumBytes: Int64 = 1_288_490_188
    public static let minimumBytes: Int64 = 1_000_000
    public static func inspect(_ url: URL) throws -> String {
        guard url.pathExtension.lowercased() == "gguf" else { throw ModelImportFailure.extensionMismatch }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw ModelImportFailure.invalidFile }
        guard let size = values.fileSize, Int64(size) >= minimumBytes, Int64(size) <= maximumBytes else { throw ModelImportFailure.size }
        let reader = try GGUFReader(url: url)
        guard try reader.read(4) == Data([0x47, 0x47, 0x55, 0x46]), try reader.number(4) == 3 else { throw ModelImportFailure.invalidFile }
        let tensors = try reader.number(8), count = try reader.number(8)
        guard tensors > 0, tensors <= 1_000, count > 0, count <= 512 else { throw ModelImportFailure.invalidFile }
        var strings: [String: String] = [:], numbers: [String: UInt64] = [:]
        var seen = Set<String>()
        for _ in 0..<count {
            try Task.checkCancellation()
            let key = try reader.string(limit: 512)
            guard seen.insert(key).inserted else { throw ModelImportFailure.invalidFile }
            let type = try reader.number(4)
            if ["general.name", "general.architecture"].contains(key), type == 8 {
                strings[key] = try reader.string(limit: 512)
            } else if ["general.file_type", "qwen2.embedding_length", "qwen2.block_count", "split.count"].contains(key), [2, 4, 10].contains(type) {
                numbers[key] = try reader.number(type == 2 ? 2 : type == 4 ? 4 : 8)
            } else { try reader.skip(type: type) }
        }
        let name = strings["general.name"] ?? ""
        let small = numbers["qwen2.embedding_length"] == 896 && numbers["qwen2.block_count"] == 24
        let medium = numbers["qwen2.embedding_length"] == 1536 && numbers["qwen2.block_count"] == 28
        guard strings["general.architecture"] == "qwen2", name.lowercased().contains("qwen2.5"),
              name.lowercased().contains("instruct"), numbers["general.file_type"] == 15,
              (small || medium), (numbers["split.count"] ?? 1) == 1 else { throw ModelImportFailure.unsupported }
        return name
    }
}

private final class GGUFReader {
    let handle: FileHandle
    var offset = 0
    private var buffer = Data()
    private var cursor = 0
    init(url: URL) throws { handle = try FileHandle(forReadingFrom: url) }
    deinit { try? handle.close() }
    func read(_ count: Int) throws -> Data {
        guard count >= 0, offset + count <= 16_777_216 else { throw ModelImportFailure.invalidFile }
        var result = Data(); result.reserveCapacity(count)
        while result.count < count {
            if cursor == buffer.count {
                buffer = try handle.read(upToCount: 65_536) ?? Data(); cursor = 0
                guard !buffer.isEmpty else { throw ModelImportFailure.invalidFile }
            }
            let amount = min(count - result.count, buffer.count - cursor)
            result.append(buffer[cursor..<cursor + amount]); cursor += amount
        }
        offset += count; return result
    }
    func number(_ count: Int) throws -> UInt64 {
        let bytes = try read(count)
        return bytes.enumerated().reduce(UInt64(0)) { $0 | (UInt64($1.element) << ($1.offset * 8)) }
    }
    func string(limit: Int = 262_144) throws -> String {
        let count = try number(8)
        guard count <= limit else { throw ModelImportFailure.invalidFile }
        guard let result = String(data: try read(Int(count)), encoding: .utf8) else { throw ModelImportFailure.invalidFile }
        return result
    }
    func skip(type: UInt64, arrayElement: Bool = false) throws {
        switch type {
        case 0, 1, 7: _ = try read(1)
        case 2, 3: _ = try read(2)
        case 4, 5, 6: _ = try read(4)
        case 10, 11, 12: _ = try read(8)
        case 8: _ = try string()
        case 9:
            guard !arrayElement else { throw ModelImportFailure.invalidFile }
            let nested = try number(4), count = try number(8)
            guard count <= 250_000 else { throw ModelImportFailure.invalidFile }
            for index in 0..<count {
                if index.isMultiple(of: 1024) { try Task.checkCancellation() }
                try skip(type: nested, arrayElement: true)
            }
        default: throw ModelImportFailure.invalidFile
        }
    }
}

public struct StagedModel: Sendable {
    public let model: ImportedModel
    public let url: URL
}

/// Shared leases prevent a second library instance from deleting a staged file while
/// native validation is running. A process exit releases all leases automatically.
private final class ModelFileTransactions: @unchecked Sendable {
    static let shared = ModelFileTransactions()
    private let lock = NSRecursiveLock()
    var leases = Set<String>() // Access only within perform.
    func perform<Result>(_ work: () throws -> Result) rethrows -> Result {
        lock.lock(); defer { lock.unlock() }
        return try work()
    }
}

/// A staged copy is invisible to selection until the caller verifies native loading.
/// The manifest is the commit point; failure/cancellation leaves the previous model intact.
public actor LocalModelLibrary {
    private let directory: URL
    private var stagedPaths = Set<String>()
    public init(directory: URL) { self.directory = directory }
    deinit {
        let paths = stagedPaths
        ModelFileTransactions.shared.perform {
            ModelFileTransactions.shared.leases.subtract(paths)
        }
    }
    private var manifest: URL { directory.appendingPathComponent("selection.json") }

    public func load() throws -> ModelSelection {
        try ModelFileTransactions.shared.perform {
            let value = try readSelection()
            try cleanAbandonedFiles(selected: value.model)
            return value
        }
    }
    private func readSelection() throws -> ModelSelection {
        guard FileManager.default.fileExists(atPath: manifest.path) else { return ModelSelection() }
        let values = try manifest.resourceValues(forKeys: [.fileSizeKey])
        guard (values.fileSize ?? 100_000) <= 16_384 else { throw ModelImportFailure.selection }
        guard let selection = try? JSONDecoder().decode(ModelSelection.self, from: Data(contentsOf: manifest)), selection.version == 1 else { throw ModelImportFailure.selection }
        return selection
    }
    public func modelURL(_ model: ImportedModel) throws -> URL {
        try ModelFileTransactions.shared.perform {
        let url = directory.appendingPathComponent(model.storedFilename)
        guard FileManager.default.fileExists(atPath: url.path) else { throw ModelImportFailure.missing }
        return url
        }
    }
    public func stage(source: URL) throws -> StagedModel {
        try ModelFileTransactions.shared.perform {
        _ = try load() // Fail before copying a large file if the existing manifest cannot be preserved.
        let name = try GGUFImportPolicy.inspect(source)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID()
        let target = directory.appendingPathComponent("\(id.uuidString).gguf")
        let partial = directory.appendingPathComponent("\(id.uuidString).partial")
        let lease = target.standardizedFileURL.path
        stagedPaths.insert(lease); ModelFileTransactions.shared.leases.insert(lease)
        var keep = false
        defer {
            if !keep { try? FileManager.default.removeItem(at: target); releaseLease(lease) }
            try? FileManager.default.removeItem(at: partial)
        }
        guard FileManager.default.createFile(atPath: partial.path, contents: nil) else { throw ModelImportFailure.invalidFile }
        let input = try FileHandle(forReadingFrom: source), output = try FileHandle(forWritingTo: partial)
        defer { try? input.close(); try? output.close() }
        var copied: Int64 = 0
        while let block = try input.read(upToCount: 1_048_576), !block.isEmpty {
            try Task.checkCancellation()
            copied += Int64(block.count)
            guard copied <= GGUFImportPolicy.maximumBytes else { throw ModelImportFailure.size }
            try output.write(contentsOf: block)
        }
        try output.synchronize()
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: partial, to: target)
        let copiedName = try GGUFImportPolicy.inspect(target)
        guard copiedName == name else { throw ModelImportFailure.invalidFile }
        keep = true
        return StagedModel(model: ImportedModel(id: id, name: name, originalFilename: String(source.lastPathComponent.prefix(160)), byteCount: copied), url: target)
        }
    }
    public func commit(_ candidate: StagedModel) throws -> ModelSelection {
        try ModelFileTransactions.shared.perform {
        try Task.checkCancellation()
        guard candidate.url.standardizedFileURL == directory.appendingPathComponent(candidate.model.storedFilename).standardizedFileURL else { throw ModelImportFailure.invalidFile }
        let old = try load()
        var current = ModelSelection(); current.engine = .imported; current.model = candidate.model
        try persist(current)
        releaseLease(candidate.url.standardizedFileURL.path)
        if let previous = old.model, previous.id != candidate.model.id { try? FileManager.default.removeItem(at: directory.appendingPathComponent(previous.storedFilename)) }
        return current
        }
    }
    public func discard(_ candidate: StagedModel) throws {
        ModelFileTransactions.shared.perform {
        guard candidate.url.standardizedFileURL == directory.appendingPathComponent(candidate.model.storedFilename).standardizedFileURL else { return }
        let value = try? readSelection()
        guard value?.model?.id != candidate.model.id,
              value != nil || stagedPaths.contains(candidate.url.standardizedFileURL.path) else { return }
        try? FileManager.default.removeItem(at: candidate.url)
        releaseLease(candidate.url.standardizedFileURL.path)
        }
    }
    public func select(_ engine: OptionalAssistantEngine) throws -> ModelSelection {
        try ModelFileTransactions.shared.perform {
        var value = try load()
        if engine == .imported {
            guard let model = value.model else { throw ModelImportFailure.missing }
            _ = try modelURL(model)
        }
        value.engine = engine; try persist(value); return value
        }
    }
    public func remove() throws -> ModelSelection {
        try ModelFileTransactions.shared.perform {
        let old = try load()
        let value = ModelSelection()
        try persist(value)
        if let model = old.model { try? FileManager.default.removeItem(at: directory.appendingPathComponent(model.storedFilename)) }
        return value
        }
    }
    /// Explicit recovery only. Preserve the malformed manifest and unleased model files
    /// together, then reset only the optional-model selection. Study data is outside here.
    public func recoverSelection() throws -> ModelSelection {
        try ModelFileTransactions.shared.perform {
            if let valid = try? readSelection() { return valid }
            let recovery = directory.appendingPathComponent("Recovery/\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: manifest, to: recovery.appendingPathComponent("selection.json"))
            var moved: [(URL, URL)] = []
            do {
                for original in try unleasedModelFiles() {
                    let destination = recovery.appendingPathComponent(original.lastPathComponent)
                    try FileManager.default.moveItem(at: original, to: destination)
                    moved.append((original, destination))
                }
                let value = ModelSelection(); try persist(value); return value
            } catch {
                for (original, saved) in moved.reversed() { try? FileManager.default.moveItem(at: saved, to: original) }
                throw error
            }
        }
    }
    private func releaseLease(_ path: String) {
        stagedPaths.remove(path); ModelFileTransactions.shared.leases.remove(path)
    }
    private func unleasedModelFiles() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]).filter { file in
            guard ["partial", "gguf"].contains(file.pathExtension), UUID(uuidString: file.deletingPathExtension().lastPathComponent) != nil else { return false }
            let canonical = file.deletingPathExtension().appendingPathExtension("gguf").standardizedFileURL.path
            guard !ModelFileTransactions.shared.leases.contains(canonical),
                  let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true else { return false }
            return true
        }
    }
    private func cleanAbandonedFiles(selected: ImportedModel?) throws {
        for file in try unleasedModelFiles() {
            if file.pathExtension == "gguf", UUID(uuidString: file.deletingPathExtension().lastPathComponent) == selected?.id { continue }
            try FileManager.default.removeItem(at: file)
        }
    }
    private func persist(_ value: ModelSelection) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: manifest, options: .atomic)
    }
}
