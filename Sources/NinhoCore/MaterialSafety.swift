import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

public enum LibraryError: Error, LocalizedError, Sendable {
    case invalid(String)
    public var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}

enum MaterialSafety {
    static let stateLimit = 32 * 1024 * 1024
    static let manifestLimit = 2 * 1024 * 1024
    static let backupLimit = 20 * 1024 * 1024 * 1024
    static let media = Set(["mp4", "webm", "mov", "mkv", "mp3", "wav", "ogg", "m4a", "aac", "flac"])
    static let extensions = media.union(["pdf", "png", "jpg", "jpeg", "webp", "txt", "md", "docx", "pptx", "xlsx"])
    static func limit(_ ext: String) -> Int { media.contains(ext) ? 2 * 1024 * 1024 * 1024 : 100 * 1024 * 1024 }
    static func require(_ value: Bool, _ message: String) throws { if !value { throw LibraryError.invalid(message) } }
    static func storedName(_ name: String) throws {
        try require(name.range(of: #"(?i)^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(pdf|png|jpg|jpeg|webp|txt|md|docx|pptx|xlsx|mp4|webm|mov|mkv|mp3|wav|ogg|m4a|aac|flac)$"#, options: .regularExpression) != nil, "Nome interno do material inválido.")
    }
    static func regular(_ url: URL, maximum: Int, expected: Int? = nil) throws -> Int {
        try require(url.isFileURL, "Selecione um arquivo local.")
        let values = try FileManager.default.attributesOfItem(atPath: url.path)
        try require(values[.type] as? FileAttributeType == .typeRegular, "Selecione um arquivo comum, sem links simbólicos.")
        guard let size = (values[.size] as? NSNumber)?.intValue else { throw LibraryError.invalid("Não foi possível ler o tamanho do arquivo.") }
        try require(size >= 0 && size <= maximum && (expected == nil || size == expected), "O tamanho do arquivo é inválido ou excede o limite permitido.")
        return size
    }
    static func read(_ url: URL, maximum: Int) throws -> Data {
        let size = try regular(url, maximum: maximum)
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var data = Data()
        while let chunk = try handle.read(upToCount: 65536), !chunk.isEmpty {
            try require(chunk.count <= maximum - data.count && chunk.count <= size - data.count, "O arquivo mudou ou excede o limite permitido.")
            data.append(chunk)
        }
        try require(data.count == size, "O arquivo está incompleto.")
        return data
    }
    static func isMissing(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(ns.code) { return true }
        if ns.domain == NSPOSIXErrorDomain && ns.code == 2 { return true }
        return (ns.userInfo[NSUnderlyingErrorKey] as? Error).map(isMissing) ?? false
    }
    static func signature(_ data: Data, ext: String) throws {
        let bytes = [UInt8](data.prefix(8192))
        func prefix(_ test: [UInt8]) -> Bool { bytes.starts(with: test) }
        func tag(_ start: Int, _ count: Int, _ text: String) -> Bool {
            guard bytes.count >= start + count else { return false }
            return Array(bytes[start..<(start + count)]) == Array(text.utf8)
        }
        try require(!prefix([77,90]) && !prefix([127,69,76,70]), "Arquivos executáveis não são materiais de estudo.")
        let valid: Bool
        switch ext {
        case "pdf": valid = Data(bytes.prefix(1024)).range(of: Data("%PDF-".utf8)) != nil
        case "png": valid = prefix([137,80,78,71,13,10,26,10])
        case "jpg", "jpeg": valid = prefix([255,216,255])
        case "webp": valid = tag(0,4,"RIFF") && tag(8,4,"WEBP")
        case "docx", "pptx", "xlsx": valid = prefix([80,75,3,4])
        case "txt", "md": valid = !bytes.contains(0)
        case "mp4", "m4a": valid = tag(4,4,"ftyp")
        case "mov": valid = ["ftyp","moov","mdat","wide"].contains { tag(4,4,$0) }
        case "webm", "mkv": valid = prefix([26,69,223,163])
        case "mp3": valid = tag(0,3,"ID3") || (bytes.count > 1 && bytes[0] == 255 && bytes[1] & 224 == 224)
        case "aac": valid = bytes.count > 1 && bytes[0] == 255 && bytes[1] & 246 == 240
        case "wav": valid = tag(0,4,"RIFF") && tag(8,4,"WAVE")
        case "ogg": valid = tag(0,4,"OggS")
        case "flac": valid = tag(0,4,"fLaC")
        default: valid = false
        }
        try require(valid, "O conteúdo do arquivo não corresponde ao formato .\(ext).")
    }
    static func inspect(_ url: URL, expected: Int? = nil, ext: String? = nil, maximum: Int? = nil) throws -> (size: Int, hash: String) {
        let size = try regular(url, maximum: maximum ?? limit(ext ?? url.pathExtension.lowercased()), expected: expected)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256(), count = 0, header = Data()
        while let chunk = try handle.read(upToCount: 65536), !chunk.isEmpty {
            count += chunk.count
            try require(count <= size, "O material mudou durante a leitura.")
            if header.count < 8192 { header.append(chunk.prefix(8192 - header.count)) }
            hash.update(data: chunk)
        }
        try require(count == size, "O material está incompleto.")
        if let ext { try signature(header, ext: ext) }
        return (size, hash.finalize().map { String(format: "%02x", $0) }.joined())
    }
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func directory(_ url: URL) throws {
        try require(url.isFileURL, "A biblioteca precisa usar uma pasta local.")
        do { try existingDirectory(url) }
        catch {
            guard isMissing(error) else { throw error }
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try existingDirectory(url)
        }
    }
    static func existingDirectory(_ url: URL) throws {
        try require(url.isFileURL, "A biblioteca precisa usar uma pasta local.")
        let values = try FileManager.default.attributesOfItem(atPath: url.path)
        try require(values[.type] as? FileAttributeType == .typeDirectory, "A pasta da biblioteca não pode ser um link simbólico.")
    }
    /// Reject unknown fields: Codable would silently discard them on save.
    static func decodeState(_ data: Data) throws -> AppState {
        let object: Any
        do { object = try JSONSerialization.jsonObject(with: data) }
        catch { throw LibraryError.invalid("O índice de dados está corrompido.") }
        guard let state = object as? [String: Any] else { throw LibraryError.invalid("Índice de dados inválido.") }
        func keys(_ object: [String: Any], required: Set<String>, optional: Set<String> = []) throws {
            let found = Set(object.keys)
            try require(required.isSubset(of: found) && found.isSubset(of: required.union(optional)), "O índice contém campos ausentes ou desconhecidos.")
        }
        try keys(state, required: ["version", "settings", "programs", "subjects", "courses", "lessons", "cards", "exams", "materials", "sessions", "tasks"])
        guard let settings = state["settings"] as? [String: Any] else { throw LibraryError.invalid("Configurações inválidas.") }
        try keys(settings, required: ["name", "dailyMinutes", "newCardsPerDay", "focusMinutes", "breakMinutes", "theme", "sound", "reducedMotion"])
        let schemas: [String: Set<String>] = [
            "programs": ["id", "name", "track", "color", "description"],
            "subjects": ["id", "programId", "name", "track", "color"],
            "courses": ["id", "subjectId", "title", "provider", "url"],
            "lessons": ["id", "courseId", "subjectId", "title", "description", "url", "order", "status", "updatedAt", "notes"],
            "cards": ["id", "subjectId", "question", "answer", "source", "sourceUrl", "dueAt", "lastReviewedAt", "intervalDays", "ease", "repetitions", "lapses", "flag", "suspended", "createdAt"],
            "exams": ["id", "title", "subjectId", "date", "time", "location", "notes", "completed"],
            "materials": ["id", "name", "storedName", "type", "size", "subjectId", "lessonId", "createdAt", "notes"],
            "sessions": ["id", "subjectId", "lessonId", "durationMinutes", "completedAt", "kind"],
            "tasks": ["id", "title", "date", "subjectId", "completed"]
        ]
        for (name, required) in schemas {
            guard let items = state[name] as? [[String: Any]] else { throw LibraryError.invalid("Coleção inválida: \(name).") }
            for item in items { try keys(item, required: required, optional: name == "cards" ? ["lessonId"] : []) }
        }
        let decoded = try JSONDecoder().decode(AppState.self, from: data)
        try StudyEngine.validate(decoded)
        return decoded
    }
}
