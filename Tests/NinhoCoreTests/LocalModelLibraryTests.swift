import Foundation
import XCTest
@testable import NinhoCore

final class LocalModelLibraryTests: XCTestCase, @unchecked Sendable {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func gguf(root: URL, filename: String = "small.gguf", architecture: String = "qwen2",
                      name: String = "Qwen2.5 0.5B Instruct", quantization: UInt64 = 15,
                      embedding: UInt64 = 896, layers: UInt64 = 24, duplicate: Bool = false) throws -> URL {
        var bytes = Data([0x47, 0x47, 0x55, 0x46])
        func number(_ value: UInt64, _ count: Int) { for offset in 0..<count { bytes.append(UInt8(truncatingIfNeeded: value >> (offset * 8))) } }
        func string(_ value: String) { number(UInt64(value.utf8.count), 8); bytes.append(contentsOf: value.utf8) }
        func text(_ key: String, _ value: String) { string(key); number(8, 4); string(value) }
        func integer(_ key: String, _ value: UInt64) { string(key); number(4, 4); number(value, 4) }
        number(3, 4); number(1, 8); number(duplicate ? 7 : 6, 8)
        text("general.architecture", architecture); text("general.name", name)
        integer("general.file_type", quantization); integer("qwen2.embedding_length", embedding)
        integer("qwen2.block_count", layers)
        string("tokenizer.ggml.tokens"); number(9, 4); number(8, 4); number(2, 8); string("one"); string("two")
        if duplicate { text("general.architecture", "qwen3") }
        bytes.append(Data(repeating: 0, count: Int(GGUFImportPolicy.minimumBytes) - bytes.count))
        let url = root.appendingPathComponent(filename); try bytes.write(to: url); return url
    }
    func testAcceptsSupportedMetadataAndBothSizes() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let small = try gguf(root: root)
        XCTAssertEqual(try GGUFImportPolicy.inspect(small), "Qwen2.5 0.5B Instruct")
        let larger = try gguf(root: root, filename: "larger.gguf", name: "Qwen2.5 1.5B Instruct", embedding: 1536, layers: 28)
        XCTAssertEqual(try GGUFImportPolicy.inspect(larger), "Qwen2.5 1.5B Instruct")
    }
    func testRejectsRenamedArchivesUnknownArchitecturesQuantizationAndLargeModels() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        for change in ["architecture", "quantization", "layers", "base", "extension", "duplicate"] {
            let file = try gguf(root: root, filename: change == "extension" ? "model.zip" : "\(change).gguf",
                architecture: change == "architecture" ? "qwen3" : "qwen2",
                name: change == "base" ? "Qwen2.5 Base" : "Qwen2.5 0.5B Instruct",
                quantization: change == "quantization" ? 1 : 15,
                layers: change == "layers" ? 100 : 24, duplicate: change == "duplicate")
            XCTAssertThrowsError(try GGUFImportPolicy.inspect(file), change)
        }
        let bad = root.appendingPathComponent("archive.gguf")
        try Data(repeating: 0x50, count: 1_000_000).write(to: bad)
        XCTAssertThrowsError(try GGUFImportPolicy.inspect(bad))
    }
    func testRejectsTruncationAndAbsurdMetadataCountWithoutLargeAllocation() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let small = root.appendingPathComponent("partial.gguf")
        try Data("GGUF".utf8).write(to: small)
        XCTAssertThrowsError(try GGUFImportPolicy.inspect(small)) { XCTAssertEqual($0 as? ModelImportFailure, .size) }
        let url = try gguf(root: root)
        let handle = try FileHandle(forWritingTo: url); defer { try? handle.close() }
        try handle.seek(toOffset: 16); try handle.write(contentsOf: Data(repeating: 255, count: 8))
        XCTAssertThrowsError(try GGUFImportPolicy.inspect(url))
    }
    func testImportedSelectionSurvivesReopenAndUsesGeneratedSafeFilename() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let source = try gguf(root: root, filename: "chosen model.gguf")
        let storage = root.appendingPathComponent("models")
        let library = LocalModelLibrary(directory: storage)
        let candidate = try await library.stage(source: source)
        let before = try await library.load(); XCTAssertNil(before.model)
        let selected = try await library.commit(candidate)
        let restored = try await LocalModelLibrary(directory: storage).load()
        XCTAssertEqual(restored, selected); XCTAssertEqual(restored.engine, .imported)
        XCTAssertEqual(restored.model?.originalFilename, "chosen model.gguf")
        XCTAssertEqual(candidate.url.lastPathComponent, "\(candidate.model.id.uuidString).gguf")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }
    func testRejectedNativeValidationDiscardsCandidateAndPreservesPreviousModel() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let source = try gguf(root: root)
        let library = LocalModelLibrary(directory: root.appendingPathComponent("models"))
        let old = try await library.stage(source: source), selected = try await library.commit(old)
        let rejected = try await library.stage(source: source)
        try await library.discard(rejected)
        let actual = try await library.load()
        XCTAssertEqual(actual, selected)
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: rejected.url.path))
    }
    func testCancelledCommitPreservesPreviousSelection() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let source = try gguf(root: root)
        let library = LocalModelLibrary(directory: root.appendingPathComponent("models"))
        let original = try await library.stage(source: source), selected = try await library.commit(original)
        let candidate = try await library.stage(source: source)
        let task = Task { () throws -> ModelSelection in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await library.commit(candidate)
        }
        do { _ = try await task.value; XCTFail("Cancelled import committed") } catch is CancellationError { }
        try await library.discard(candidate)
        let actual = try await library.load(); XCTAssertEqual(actual, selected)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.url.path))
    }
    func testSelectingIncludedKeepsImportedFileAndRemovalPreservesSource() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let source = try gguf(root: root)
        let library = LocalModelLibrary(directory: root.appendingPathComponent("models"))
        let candidate = try await library.stage(source: source)
        _ = try await library.commit(candidate)
        let embedded = try await library.select(.embedded)
        XCTAssertEqual(embedded.model, candidate.model); XCTAssertEqual(embedded.engine, .embedded)
        XCTAssertTrue(FileManager.default.fileExists(atPath: candidate.url.path))
        let cleared = try await library.remove()
        XCTAssertNil(cleared.model); XCTAssertEqual(cleared.engine, .embedded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: candidate.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }
    func testCannotSelectMissingOrUnimportedModel() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let library = LocalModelLibrary(directory: root.appendingPathComponent("models"))
        do { _ = try await library.select(.imported); XCTFail("Selected absent model") }
        catch { XCTAssertEqual(error as? ModelImportFailure, .missing) }
    }
    func testReopenCleansCrashedCopiesButKeepsSelectedModelAndUnmanagedFiles() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let source = try gguf(root: root), storage = root.appendingPathComponent("models")
        let library = LocalModelLibrary(directory: storage)
        let active = try await library.stage(source: source)
        let selected = try await library.commit(active)
        let orphan = storage.appendingPathComponent("\(UUID().uuidString).gguf")
        let partial = storage.appendingPathComponent("\(UUID().uuidString).partial")
        let unrelated = storage.appendingPathComponent("user-document.gguf")
        for file in [orphan, partial, unrelated] { try Data("interrupted copy".utf8).write(to: file) }
        let loaded = try await LocalModelLibrary(directory: storage).load()
        XCTAssertEqual(loaded, selected)
        XCTAssertTrue(FileManager.default.fileExists(atPath: active.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path))
    }
    func testConcurrentValidationLeasesArePreservedAcrossLibraryInstances() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let source = try gguf(root: root), storage = root.appendingPathComponent("models")
        let first = LocalModelLibrary(directory: storage), second = LocalModelLibrary(directory: storage)
        let a = try await first.stage(source: source), b = try await second.stage(source: source)
        _ = try await first.load(); _ = try await second.load()
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: b.url.path))
        let selected = try await first.commit(a)
        let actual = try await second.load()
        XCTAssertEqual(actual, selected)
        XCTAssertTrue(FileManager.default.fileExists(atPath: b.url.path))
        try await second.discard(b)
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: b.url.path))
    }
    func testCorruptManifestNeedsExplicitRecoveryAndQuarantinesWeightsWithoutTouchingStudies() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let source = try gguf(root: root), storage = root.appendingPathComponent("models")
        let study = root.appendingPathComponent("state.json"), studyData = Data("synthetic profile and studies".utf8)
        try studyData.write(to: study)
        let library = LocalModelLibrary(directory: storage)
        let candidate = try await library.stage(source: source)
        _ = try await library.commit(candidate)
        let manifest = storage.appendingPathComponent("selection.json"), corrupted = Data("{interrupted metadata".utf8)
        try corrupted.write(to: manifest)
        let orphan = storage.appendingPathComponent("\(UUID().uuidString).partial")
        try Data("unfinished copy".utf8).write(to: orphan)
        do { _ = try await library.load(); XCTFail("Invalid configuration accepted") }
        catch { XCTAssertEqual(error as? ModelImportFailure, .selection) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: candidate.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: orphan.path))
        let recovered = try await library.recoverSelection()
        XCTAssertEqual(recovered.engine, .embedded); XCTAssertNil(recovered.model)
        let quarantine = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: storage.appendingPathComponent("Recovery"), includingPropertiesForKeys: nil).first)
        XCTAssertEqual(try Data(contentsOf: quarantine.appendingPathComponent("selection.json")), corrupted)
        XCTAssertTrue(FileManager.default.fileExists(atPath: quarantine.appendingPathComponent(candidate.url.lastPathComponent).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: quarantine.appendingPathComponent(orphan.lastPathComponent).path))
        XCTAssertEqual(try Data(contentsOf: study), studyData)
        let next = try await library.stage(source: source)
        let selected = try await library.commit(next)
        XCTAssertEqual(selected.engine, .imported)
        XCTAssertTrue(FileManager.default.fileExists(atPath: quarantine.appendingPathComponent(candidate.url.lastPathComponent).path))
    }
}
