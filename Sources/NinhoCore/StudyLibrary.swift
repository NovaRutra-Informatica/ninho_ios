import Foundation
import ZIPFoundation

private struct BackupFile: Codable { var path: String; var size: Int; var sha256: String }
private struct BackupManifest: Codable {
    var format = "NinhoBackup"
    var version = 1
    var createdAt = StudyEngine.timestamp(Date())
    var files: [BackupFile]
}

/// Restore into a new generation; switch its pointer only after validation.
public actor StudyLibrary {
    public let root: URL
    private var generation: URL?
    private var state: AppState?
    private var recoveryNotice: String?
    private let fm = FileManager.default
    public init(root: URL) { self.root = root.standardizedFileURL }

    public func load(seed: AppState = AppState()) throws -> AppState {
        if let state { return state }
        try MaterialSafety.directory(root)
        try MaterialSafety.directory(root.appendingPathComponent("collections"))
        let pointer = root.appendingPathComponent("current.json")
        if fm.fileExists(atPath: pointer.path) {
            let id = try JSONDecoder().decode(String.self, from: MaterialSafety.read(pointer, maximum: 1024))
            try MaterialSafety.require(UUID(uuidString: id) != nil, "O índice da biblioteca está inválido.")
            let folder = root.appendingPathComponent("collections").appendingPathComponent(id)
            try MaterialSafety.existingDirectory(folder)
            let current = try readState(folder.appendingPathComponent("state.json"))
            generation = folder; state = current
            return current
        }
        try StudyEngine.validate(seed)
        let folder = try newGeneration()
        try save(seed, to: folder, previous: false)
        try switchGeneration(folder)
        state = seed; return seed
    }

    public func apply(_ command: StudyCommand, now: Date = Date()) throws -> AppState {
        switch command {
        case .addMaterial: throw LibraryError.invalid("Adicione arquivos pelo seletor de materiais.")
        default: break
        }
        let current = try load()
        let updated = try StudyEngine.apply(command, to: current, now: now)
        guard let generation else { throw LibraryError.invalid("A biblioteca não abriu.") }
        try save(updated, to: generation)
        state = updated
        // Retain removed files for recovery; export only registered materials.
        return updated
    }

    public func importMaterial(from source: URL, subjectId: String = "", lessonId: String = "") throws -> AppState {
        let current = try load()
        let ext = source.pathExtension.lowercased()
        try MaterialSafety.require(MaterialSafety.extensions.contains(ext), "Esse formato não é aceito pela biblioteca.")
        let inspected = try MaterialSafety.inspect(source, ext: ext)
        // Identical content in another lesson is a separate, intentional link.
        var unavailableDuplicate = false
        for material in current.materials where material.subjectId == subjectId && material.lessonId == lessonId && material.size == inspected.size {
            do {
                let existing = try materialURL(id: material.id)
                if try MaterialSafety.inspect(existing, expected: material.size, ext: material.type).hash == inspected.hash { return current }
            } catch {
                // Skip damaged copies; propagate permission and device errors.
                guard error is LibraryError || MaterialSafety.isMissing(error) else { throw error }
                unavailableDuplicate = true
            }
        }
        guard let generation else { throw LibraryError.invalid("A biblioteca não abriu.") }
        try checkedGeneration(generation)
        let id = UUID().uuidString.lowercased()
        let material = Material(id: id, name: source.lastPathComponent, storedName: "\(id).\(ext)", type: ext, size: inspected.size, subjectId: subjectId, lessonId: lessonId)
        let updated = try StudyEngine.apply(.addMaterial(material), to: current)
        let directory = generation.appendingPathComponent("materials")
        try MaterialSafety.directory(directory)
        let destination = directory.appendingPathComponent(material.storedName)
        do {
            try fm.copyItem(at: source, to: destination)
            let copied = try MaterialSafety.inspect(destination, expected: material.size, ext: ext)
            try MaterialSafety.require(copied.hash == inspected.hash, "O arquivo mudou durante a importação. Tente novamente.")
            try save(updated, to: generation)
            state = updated
            if unavailableDuplicate { recoveryNotice = "Uma cópia anterior estava ausente ou danificada. O novo arquivo foi adicionado; o registro anterior foi preservado e pode ser removido por você." }
            return updated
        } catch { try? fm.removeItem(at: destination); throw error }
    }

    public func materialURL(id: String) throws -> URL {
        let current = try load()
        guard let item = current.materials.first(where: { $0.id == id }), let generation else { throw LibraryError.invalid("Material não encontrado na biblioteca.") }
        return try materialURL(item, in: generation)
    }

    private func checkedGeneration(_ folder: URL) throws {
        try MaterialSafety.existingDirectory(root)
        try MaterialSafety.existingDirectory(root.appendingPathComponent("collections"))
        try MaterialSafety.existingDirectory(folder)
    }
    private func materialURL(_ item: Material, in folder: URL) throws -> URL {
        try checkedGeneration(folder)
        try MaterialSafety.storedName(item.storedName)
        let directory = folder.appendingPathComponent("materials")
        try MaterialSafety.existingDirectory(directory)
        let url = directory.appendingPathComponent(item.storedName)
        _ = try MaterialSafety.regular(url, maximum: MaterialSafety.limit(item.type), expected: item.size)
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        try MaterialSafety.signature(try handle.read(upToCount: 8192) ?? Data(), ext: item.type)
        return url
    }

    public func exportBackup(to destination: URL) throws {
        let current = try load()
        guard let generation else { throw LibraryError.invalid("A biblioteca não abriu.") }
        try exportBackup(current, from: generation, to: destination)
    }
    private func exportBackup(_ current: AppState, from folder: URL, to destination: URL) throws {
        try StudyEngine.validate(current)
        try checkedGeneration(folder)
        try MaterialSafety.require(destination.isFileURL && destination.pathExtension.lowercased() == "zip", "Escolha um destino local com extensão .zip.")
        try MaterialSafety.require(!fm.fileExists(atPath: destination.path), "Já existe um backup com esse nome. Escolha outro destino.")
        try MaterialSafety.require(current.materials.count <= 5000, "O backup suporta até 5.000 materiais.")
        try MaterialSafety.directory(destination.deletingLastPathComponent())
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".zip")
        do {
            let archive = try Archive(url: temporary, accessMode: .create)
            let stateData = try encoded(current)
            var manifest = BackupManifest(files: [BackupFile(path: "state.json", size: stateData.count, sha256: MaterialSafety.digest(stateData))])
            try add(stateData, name: "state.json", to: archive)
            var total = stateData.count
            for item in current.materials {
                let url = try materialURL(item, in: folder)
                let checked = try MaterialSafety.inspect(url, expected: item.size, ext: item.type)
                total += checked.size
                try MaterialSafety.require(total <= MaterialSafety.backupLimit, "O backup excede 20 GB.")
                let name = "materials/" + item.storedName
                try archive.addEntry(with: name, fileURL: url, compressionMethod: MaterialSafety.media.contains(item.type) ? .none : .deflate)
                manifest.files.append(BackupFile(path: name, size: checked.size, sha256: checked.hash))
            }
            try add(try JSONEncoder().encode(manifest), name: "manifest.json", to: archive)
            // Re-read all checksums from the finished archive before delivery.
            try validateArchive(archive, extractTo: nil)
            _ = try MaterialSafety.regular(temporary, maximum: MaterialSafety.backupLimit)
            try fm.moveItem(at: temporary, to: destination)
        } catch { try? fm.removeItem(at: temporary); throw error }
    }

    public func restoreBackup(from source: URL) throws -> AppState {
        // Validate the selected backup before trying to load or repair old data.
        try MaterialSafety.directory(root)
        try MaterialSafety.directory(root.appendingPathComponent("collections"))
        _ = try MaterialSafety.regular(source, maximum: MaterialSafety.backupLimit)
        let archive = try Archive(url: source, accessMode: .read)
        let folder = try newGeneration()
        do {
            let restored = try validateArchive(archive, extractTo: folder)
            let backups = root.appendingPathComponent("backups")
            try MaterialSafety.directory(backups)
            let label = "antes-restauracao-\(UUID().uuidString)"
            let pointer = root.appendingPathComponent("current.json")
            var notice: String?
            var oldState: AppState?
            if fm.fileExists(atPath: pointer.path) {
                let pointerData = try MaterialSafety.read(pointer, maximum: 1024)
                // The exact pointer and every old generation remain available.
                try pointerData.write(to: backups.appendingPathComponent(label + "-pointer.json"), options: .atomic)
                do { oldState = try load() }
                catch {
                    guard error is DecodingError || error is StudyError || error is LibraryError || MaterialSafety.isMissing(error) else { throw error }
                    notice = "O índice anterior estava danificado. A coleção antiga e seu ponteiro foram preservados em \(root.path)."
                }
            }
            if let oldState, let previous = generation {
                var available: [Material] = [], missing = 0, damaged = 0
                for material in oldState.materials {
                    do {
                        _ = try materialURL(material, in: previous)
                        available.append(material)
                    } catch {
                        if MaterialSafety.isMissing(error) { missing += 1 }
                        else if error is LibraryError { damaged += 1 }
                        else { throw error }
                    }
                }
                if missing > 0 || damaged > 0 {
                    try encoded(oldState).write(to: backups.appendingPathComponent(label + "-indice-original.json"), options: .atomic)
                    var safety = oldState; safety.materials = available
                    try exportBackup(safety, from: previous, to: backups.appendingPathComponent(label + "-anexos-disponiveis.zip"))
                    notice = "\(missing) anexos ausentes e \(damaged) danificados na coleção anterior. O índice original e os anexos válidos foram copiados para backups; todos os arquivos antigos permanecem em \(previous.path)."
                } else {
                    try exportBackup(oldState, from: previous, to: backups.appendingPathComponent(label + ".zip"))
                }
            }
            try switchGeneration(folder)
            state = restored
            recoveryNotice = notice.map { $0 + " O backup selecionado foi restaurado." }
            return restored
        } catch { try? fm.removeItem(at: folder); throw error }
    }

    public func takeRecoveryNotice() -> String? {
        defer { recoveryNotice = nil }
        return recoveryNotice
    }

    public func saveAuxiliary<T: Encodable & Sendable>(_ value: T, name: String) throws {
        _ = try load()
        try MaterialSafety.require(name == "focus.json", "Registro auxiliar desconhecido.")
        guard let generation else { throw LibraryError.invalid("A biblioteca não abriu.") }
        try checkedGeneration(generation)
        let data = try JSONEncoder().encode(value)
        try MaterialSafety.require(data.count <= 65536, "O registro auxiliar excede o limite permitido.")
        try data.write(to: generation.appendingPathComponent(name), options: .atomic)
    }
    public func loadAuxiliary<T: Decodable & Sendable>(_ type: T.Type, name: String) throws -> T? {
        _ = try load()
        try MaterialSafety.require(name == "focus.json", "Registro auxiliar desconhecido.")
        guard let generation else { return nil }
        let url = generation.appendingPathComponent(name)
        try checkedGeneration(generation)
        let data: Data
        do { data = try MaterialSafety.read(url, maximum: 65536) }
        catch { if MaterialSafety.isMissing(error) { return nil }; throw error }
        return try JSONDecoder().decode(type, from: data)
    }

    /// Move invalid timer bytes intact without loading them. Reject links and I/O failures.
    public func preserveInvalidFocus() throws -> String? {
        _ = try load()
        guard let generation else { throw LibraryError.invalid("A biblioteca não abriu.") }
        try checkedGeneration(generation)
        let source = generation.appendingPathComponent("focus.json")
        do { _ = try MaterialSafety.regular(source, maximum: Int.max) }
        catch { if MaterialSafety.isMissing(error) { return nil }; throw error }
        let backups = root.appendingPathComponent("backups")
        try MaterialSafety.directory(backups)
        let name = "focus-invalid-\(UUID().uuidString).json"
        try fm.moveItem(at: source, to: backups.appendingPathComponent(name))
        return name
    }

    private func newGeneration() throws -> URL {
        let folder = root.appendingPathComponent("collections").appendingPathComponent(UUID().uuidString)
        try MaterialSafety.directory(folder.appendingPathComponent("materials"))
        return folder
    }
    private func switchGeneration(_ folder: URL) throws {
        try checkedGeneration(folder)
        try JSONEncoder().encode(folder.lastPathComponent).write(to: root.appendingPathComponent("current.json"), options: .atomic)
        generation = folder
    }
    private func encoded(_ value: AppState) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try MaterialSafety.require(data.count <= MaterialSafety.stateLimit, "A coleção excede o limite de dados.")
        return data
    }
    private func save(_ value: AppState, to folder: URL, previous: Bool = true) throws {
        try checkedGeneration(folder)
        try StudyEngine.validate(value)
        let data = try encoded(value), url = folder.appendingPathComponent("state.json")
        if previous && fm.fileExists(atPath: url.path) {
            _ = try readState(url)
            try MaterialSafety.read(url, maximum: MaterialSafety.stateLimit).write(to: folder.appendingPathComponent("state.previous.json"), options: .atomic)
        }
        try data.write(to: url, options: .atomic)
    }
    private func readState(_ url: URL) throws -> AppState {
        try MaterialSafety.decodeState(MaterialSafety.read(url, maximum: MaterialSafety.stateLimit))
    }
    private func add(_ data: Data, name: String, to archive: Archive) throws {
        try archive.addEntry(with: name, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .deflate) { offset, size in
            data.subdata(in: Int(offset)..<min(Int(offset) + size, data.count))
        }
    }
    @discardableResult private func validateArchive(_ archive: Archive, extractTo folder: URL?) throws -> AppState {
        var entries: [String: Entry] = [:], normalized = Set<String>(), total: UInt64 = 0, entryCount = 0
        for entry in archive {
            entryCount += 1
            try MaterialSafety.require(entryCount <= 5002, "O backup tem arquivos demais.")
            try MaterialSafety.require(normalized.insert(entry.path.lowercased()).inserted, "O backup contém caminhos duplicados.")
            if entry.path == "materials/" {
                try MaterialSafety.require(entry.type == .directory && entry.uncompressedSize == 0, "Pasta inválida no backup.")
                continue
            }
            try MaterialSafety.require(entry.type == .file, "Links e pastas inesperadas não são aceitos no backup.")
            if entry.path != "state.json" && entry.path != "manifest.json" {
                try MaterialSafety.require(entry.path.hasPrefix("materials/"), "Caminho não permitido no backup.")
                try MaterialSafety.storedName(String(entry.path.dropFirst(10)))
            }
            let entryLimit = entry.path == "state.json" ? MaterialSafety.stateLimit : entry.path == "manifest.json" ? MaterialSafety.manifestLimit : MaterialSafety.limit((entry.path as NSString).pathExtension.lowercased())
            try MaterialSafety.require(entry.uncompressedSize <= UInt64(entryLimit), "Um arquivo do backup excede o limite permitido.")
            let sum = total.addingReportingOverflow(entry.uncompressedSize)
            try MaterialSafety.require(!sum.overflow && sum.partialValue <= UInt64(MaterialSafety.backupLimit), "O backup descompactado excede 20 GB.")
            total = sum.partialValue
            entries[entry.path] = entry
        }
        guard let stateEntry = entries["state.json"], let manifestEntry = entries["manifest.json"] else { throw LibraryError.invalid("Escolha um backup ZIP exportado pelo Ninho.") }
        func read(_ entry: Entry, limit: Int, output: URL? = nil) throws -> Data {
            try MaterialSafety.require(entry.uncompressedSize <= UInt64(limit), "O arquivo do backup excede o limite permitido.")
            var data = Data(), count = 0
            var sink: FileHandle?
            if let output {
                try MaterialSafety.require(fm.createFile(atPath: output.path, contents: nil), "Não foi possível extrair o material.")
                sink = try FileHandle(forWritingTo: output)
            }
            defer { try? sink?.close() }
            let crc = try archive.extract(entry, bufferSize: 65536) { chunk in
                count += chunk.count
                try MaterialSafety.require(count <= limit && UInt64(count) <= entry.uncompressedSize, "Arquivo expandido além do limite.")
                if let sink { try sink.write(contentsOf: chunk) } else { data.append(chunk) }
            }
            try sink?.synchronize()
            try MaterialSafety.require(crc == entry.checksum && UInt64(count) == entry.uncompressedSize, "O backup está incompleto ou corrompido.")
            return data
        }
        let manifestData = try read(manifestEntry, limit: MaterialSafety.manifestLimit)
        let manifest = try JSONDecoder().decode(BackupManifest.self, from: manifestData)
        try MaterialSafety.require(manifest.format == "NinhoBackup" && manifest.version == 1 && manifest.files.count <= 5001, "Formato de backup não reconhecido.")
        try MaterialSafety.require(Set(manifest.files.map { $0.path.lowercased() }).count == manifest.files.count, "Manifesto duplicado.")
        try MaterialSafety.require(manifest.files.allSatisfy { $0.sha256.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil }, "Hash inválido no manifesto.")
        let stateData = try read(stateEntry, limit: MaterialSafety.stateLimit)
        let restored = try MaterialSafety.decodeState(stateData)
        let expected = Set(["state.json"] + restored.materials.map { "materials/" + $0.storedName })
        try MaterialSafety.require(Set(entries.keys) == expected.union(["manifest.json"]) && Set(manifest.files.map(\.path)) == expected, "O índice e os arquivos do backup não correspondem.")
        for file in manifest.files {
            guard let entry = entries[file.path] else { throw LibraryError.invalid("Arquivo ausente no backup.") }
            try MaterialSafety.require(file.size >= 0 && UInt64(file.size) == entry.uncompressedSize, "Tamanho inconsistente no manifesto.")
            if file.path == "state.json" {
                try MaterialSafety.require(MaterialSafety.digest(stateData) == file.sha256, "O índice do backup está corrompido.")
            } else {
                guard let item = restored.materials.first(where: { "materials/" + $0.storedName == file.path }) else { throw LibraryError.invalid("Material desconhecido.") }
                try MaterialSafety.require(item.size == file.size, "Metadados de tamanho inconsistentes.")
                // Stream extraction to bound memory use for videos.
                let scratch = folder?.appendingPathComponent(file.path) ?? root.appendingPathComponent(UUID().uuidString + ".verify")
                defer { if folder == nil { try? fm.removeItem(at: scratch) } }
                _ = try read(entry, limit: MaterialSafety.limit(item.type), output: scratch)
                let checked = try MaterialSafety.inspect(scratch, expected: file.size, ext: item.type)
                try MaterialSafety.require(checked.hash == file.sha256, "A integridade de um material não foi confirmada.")
            }
        }
        if let folder { try stateData.write(to: folder.appendingPathComponent("state.json"), options: .atomic) }
        return restored
    }
}
