import Foundation
import XCTest
import ZIPFoundation
@testable import NinhoCore

final class StudyLibraryTests: XCTestCase, @unchecked Sendable {
    private func fixture() -> AppState {
        AppState(programs: [.init(id: "p", name: "Curso")], subjects: [.init(id: "s", programId: "p", name: "Matéria")], courses: [.init(id: "c", subjectId: "s", title: "Módulo")], lessons: [.init(id: "l", courseId: "c", subjectId: "s", title: "Aula 00"), .init(id: "l2", courseId: "c", subjectId: "s", title: "Aula 01")])
    }
    private func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("NinhoTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func pdf(in root: URL, name: String = "aula.pdf", bytes: Int = 128) throws -> URL {
        let file = root.appendingPathComponent(name)
        var data = Data("%PDF-1.7\n".utf8); data.append(Data(repeating: 32, count: bytes)); data.append(Data("\n%%EOF".utf8))
        try data.write(to: file); return file
    }
    func testPersistenceAndInvalidCommandDoNotLoseExistingState() async throws {
        let root = try temporary(), library = StudyLibrary(root: root)
        let initial = try await library.load(seed: fixture())
        let saved = try await library.apply(.updateLesson(id: "l", notes: "Meu resumo"))
        XCTAssertEqual(saved.lessons[0].notes, "Meu resumo")
        do { _ = try await library.apply(.saveSubject(.init(programId: "missing", name: "Erro"))); XCTFail("Invalid reference accepted") } catch {}
        let reopened = try await StudyLibrary(root: root).load()
        XCTAssertEqual(saved, reopened); XCTAssertEqual(initial.lessons[1], reopened.lessons[1])
    }
    func testRealCopyDedupLessonContextAndReopen() async throws {
        let root = try temporary(), sourceRoot = try temporary(), library = StudyLibrary(root: root)
        _ = try await library.load(seed: fixture())
        let source = try pdf(in: sourceRoot, bytes: 12 * 1024 * 1024)
        let state = try await library.importMaterial(from: source, subjectId: "s", lessonId: "l")
        let again = try await library.importMaterial(from: source, subjectId: "s", lessonId: "l")
        XCTAssertEqual(state, again)
        let next = try await library.importMaterial(from: source, subjectId: "s", lessonId: "l2")
        XCTAssertEqual(next.materials.count, 2)
        let savedURL = try await library.materialURL(id: state.materials[0].id)
        XCTAssertNotEqual(source, savedURL)
        XCTAssertEqual(try MaterialSafety.inspect(source, ext: "pdf").hash, try MaterialSafety.inspect(savedURL, ext: "pdf").hash)
        try FileManager.default.removeItem(at: source)
        let reopened = StudyLibrary(root: root)
        _ = try await reopened.load()
        let url = try await reopened.materialURL(id: state.materials[0].id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
    func testInvalidImportsCannotCreateMaterialRecords() async throws {
        let root = try temporary(), sourceRoot = try temporary(), library = StudyLibrary(root: root)
        let initial = try await library.load(seed: fixture())
        for (name, data) in [("fake.pdf", Data("<html>login</html>".utf8)), ("program.pdf", Data("MZfake".utf8)), ("program.exe", Data("MZ".utf8)), ("bad.png", Data("png".utf8))] {
            let url = sourceRoot.appendingPathComponent(name); try data.write(to: url)
            do { _ = try await library.importMaterial(from: url, subjectId: "s", lessonId: "l"); XCTFail("Accepted \(name)") } catch {}
        }
        let source = try pdf(in: sourceRoot)
        do { _ = try await library.importMaterial(from: source, subjectId: "wrong", lessonId: "l"); XCTFail("Wrong subject") } catch {}
        let link = sourceRoot.appendingPathComponent("link.pdf")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        do { _ = try await library.importMaterial(from: link, subjectId: "s", lessonId: "l"); XCTFail("Symlink") } catch {}
        let after = try await library.load(); XCTAssertEqual(initial, after)
    }
    func testRemovalRevokesAccessButPreservesOtherData() async throws {
        let root = try temporary(), sourceRoot = try temporary(), library = StudyLibrary(root: root)
        _ = try await library.load(seed: fixture())
        let imported = try await library.importMaterial(from: pdf(in: sourceRoot), subjectId: "s", lessonId: "l")
        let material = try XCTUnwrap(imported.materials.first)
        let removed = try await library.apply(.removeMaterial(id: material.id))
        XCTAssertTrue(removed.materials.isEmpty); XCTAssertEqual(removed.lessons, imported.lessons)
        do { _ = try await library.materialURL(id: material.id); XCTFail("Unregistered access") } catch {}
        do { _ = try await library.materialURL(id: "../../outside"); XCTFail("Traversal") } catch {}
    }
    func testZIPRoundtripKeepsFilesAndProgressWithSafetyBackup() async throws {
        let root = try temporary(), targetRoot = try temporary(), sourceRoot = try temporary()
        let library = StudyLibrary(root: root), target = StudyLibrary(root: targetRoot)
        _ = try await library.load(seed: fixture())
        _ = try await library.apply(.updateLesson(id: "l", status: .inProgress, notes: "SQL"))
        let expected = try await library.importMaterial(from: pdf(in: sourceRoot, bytes: 2_000_000), subjectId: "s", lessonId: "l")
        let zip = sourceRoot.appendingPathComponent("backup.zip")
        try await library.exportBackup(to: zip)
        _ = try await target.load(seed: fixture())
        let restored = try await target.restoreBackup(from: zip)
        XCTAssertEqual(restored, expected)
        let materialURL = try await target.materialURL(id: expected.materials[0].id)
        XCTAssertEqual(try MaterialSafety.inspect(materialURL, ext: "pdf").size, expected.materials[0].size)
        let backups = try FileManager.default.contentsOfDirectory(atPath: targetRoot.appendingPathComponent("backups").path)
        XCTAssertEqual(backups.filter { $0.hasSuffix(".zip") }.count, 1)
        XCTAssertEqual(backups.filter { $0.hasSuffix("-pointer.json") }.count, 1)
        let reopened = try await StudyLibrary(root: targetRoot).load(); XCTAssertEqual(reopened, expected)
    }
    func testCorruptOrUnexpectedZIPKeepsCollection() async throws {
        let root = try temporary(), sourceRoot = try temporary(), library = StudyLibrary(root: root)
        let initial = try await library.load(seed: fixture())
        for name in ["../outside", "materials/../../outside", "unregistered.txt"] {
            let zip = sourceRoot.appendingPathComponent(UUID().uuidString + ".zip")
            let archive = try Archive(url: zip, accessMode: .create)
            try archive.addEntry(with: name, type: .file, uncompressedSize: Int64(1)) { _, _ in Data([1]) }
            do { _ = try await library.restoreBackup(from: zip); XCTFail("Bad zip accepted") } catch {}
            let after = try await library.load(); XCTAssertEqual(after, initial)
        }
        let invalid = sourceRoot.appendingPathComponent("bad.zip"); try Data("not a zip".utf8).write(to: invalid)
        do { _ = try await library.restoreBackup(from: invalid); XCTFail("Malformed archive") } catch {}
        let after = try await library.load(); XCTAssertEqual(after, initial)
    }
    func testSeedCanDecodeAndValidateDesktopState() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "seed-state", withExtension: "json", subdirectory: "Fixtures"))
        let state = try JSONDecoder().decode(AppState.self, from: Data(contentsOf: url))
        try StudyEngine.validate(state)
        XCTAssertEqual(state.lessons.count, 271); XCTAssertEqual(state.courses.count, 20)
        XCTAssertEqual(try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state)), state)
    }

    private func windowsZIP() throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: "windows-v2", withExtension: "zip", subdirectory: "Fixtures"))
    }
    private func payloads(_ source: URL) throws -> [(String, Data)] {
        let archive = try Archive(url: source, accessMode: .read)
        return try archive.map { entry in
            var bytes = Data()
            let crc = try archive.extract(entry) { bytes.append($0) }
            XCTAssertEqual(crc, entry.checksum)
            return (entry.path, bytes)
        }
    }
    private func writeZIP(_ files: [(String, Data)], in root: URL, symlink: String? = nil) throws -> URL {
        let url = root.appendingPathComponent(UUID().uuidString + ".zip")
        let archive = try Archive(url: url, accessMode: .create)
        for (name, data) in files {
            try archive.addEntry(with: name, type: name == symlink ? .symlink : .file, uncompressedSize: Int64(data.count)) { offset, size in
                data.subdata(in: Int(offset)..<min(Int(offset) + size, data.count))
            }
        }
        return url
    }
    private func currentFolder(_ root: URL) throws -> URL {
        let id = try JSONDecoder().decode(String.self, from: Data(contentsOf: root.appendingPathComponent("current.json")))
        return root.appendingPathComponent("collections").appendingPathComponent(id)
    }
    private func assertRejected(_ zip: URL, root: URL, library: StudyLibrary, expected: AppState, file: StaticString = #filePath, line: UInt = #line) async throws {
        let pointer = try Data(contentsOf: root.appendingPathComponent("current.json"))
        let generations = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("collections").path).sorted()
        do { _ = try await library.restoreBackup(from: zip); XCTFail("Invalid ZIP was restored", file: file, line: line) } catch {}
        let after = try await library.load()
        XCTAssertEqual(after, expected, file: file, line: line)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("current.json")), pointer, file: file, line: line)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("collections").path).sorted(), generations, file: file, line: line)
        let notice = await library.takeRecoveryNotice()
        XCTAssertNil(notice, file: file, line: line)
    }

    func testWindowsZIPImportsFullHistoryAndSwiftExportPreservesItsContents() async throws {
        let root = try temporary(), output = try temporary(), library = StudyLibrary(root: root)
        let expectedState = try XCTUnwrap(payloads(windowsZIP()).first { $0.0 == "state.json" }?.1)
        let expected = try JSONDecoder().decode(AppState.self, from: expectedState)
        let restored = try await library.restoreBackup(from: windowsZIP())
        XCTAssertEqual(restored, expected)
        XCTAssertEqual(restored.lessons[0].notes, "Acentos: São Caetano, café 🦉")
        XCTAssertEqual(restored.cards[0].lapses, 1)
        XCTAssertEqual(StudyEngine.lessonStats(in: restored)["l"]?.durationMinutes, 12.5)
        let exported = output.appendingPathComponent("swift-v2.zip")
        try await library.exportBackup(to: exported)
        let files = try payloads(exported)
        let encodedState = try XCTUnwrap(files.first { $0.0 == "state.json" }?.1)
        XCTAssertEqual(try JSONDecoder().decode(AppState.self, from: encodedState), expected)
        for (name, bytes) in try payloads(windowsZIP()) where name.hasPrefix("materials/") {
            XCTAssertEqual(files.first { $0.0 == name }?.1, bytes)
        }
        // Optional handoff to the Windows backup reader.
        if let destination = ProcessInfo.processInfo.environment["NINHO_INTEROP_OUTPUT"] {
            try FileManager.default.copyItem(at: exported, to: URL(fileURLWithPath: destination))
        }
    }

    func testSHAStateAndMaterialTamperingRejectsBeforeChangingPointer() async throws {
        let root = try temporary(), output = try temporary(), library = StudyLibrary(root: root)
        let initial = try await library.load(seed: fixture())
        let original = try payloads(windowsZIP())
        for target in ["state.json", "materials/12345678-1234-1234-1234-123456789012.pdf"] {
            var changed = original
            let index = try XCTUnwrap(changed.firstIndex { $0.0 == "manifest.json" })
            var manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: changed[index].1) as? [String: Any])
            var files = try XCTUnwrap(manifest["files"] as? [[String: Any]])
            let file = try XCTUnwrap(files.firstIndex { $0["path"] as? String == target })
            files[file]["sha256"] = String(repeating: "0", count: 64)
            manifest["files"] = files; changed[index].1 = try JSONSerialization.data(withJSONObject: manifest)
            try await assertRejected(writeZIP(changed, in: output), root: root, library: library, expected: initial)
        }
    }

    func testCentralDirectoryCRCAndOversizedHeaderAreRejected() async throws {
        let root = try temporary(), output = try temporary(), library = StudyLibrary(root: root)
        let initial = try await library.load(seed: fixture())
        let original = try Data(contentsOf: windowsZIP())
        let signature = Data([0x50, 0x4b, 0x01, 0x02])
        let offset = try XCTUnwrap(original.range(of: signature)?.lowerBound)
        for field in [16, 24] { // central CRC32 and declared uncompressed size
            var changed = original
            if field == 16 { changed[offset + field] ^= 0xff }
            else { changed.replaceSubrange((offset + field)..<(offset + field + 4), with: [255, 255, 255, 255]) }
            let zip = output.appendingPathComponent(UUID().uuidString + ".zip")
            try changed.write(to: zip)
            try await assertRejected(zip, root: root, library: library, expected: initial)
        }
    }

    func testDuplicateCasefoldPathsSymlinksAndMissingMaterialsAreRejected() async throws {
        let root = try temporary(), output = try temporary(), library = StudyLibrary(root: root)
        let initial = try await library.load(seed: fixture()), files = try payloads(windowsZIP())
        let material = try XCTUnwrap(files.first { $0.0.hasPrefix("materials/") })
        let duplicate = try writeZIP(files + [(material.0.uppercased(), material.1)], in: output)
        try await assertRejected(duplicate, root: root, library: library, expected: initial)
        let symlink = try writeZIP(files, in: output, symlink: material.0)
        try await assertRejected(symlink, root: root, library: library, expected: initial)
        let missing = try writeZIP(files.filter { $0.0 != material.0 }, in: output)
        try await assertRejected(missing, root: root, library: library, expected: initial)
    }

    func testUnknownStateFieldsAreRejectedEvenWhenHashesAreCorrect() async throws {
        let root = try temporary(), output = try temporary(), library = StudyLibrary(root: root)
        let initial = try await library.load(seed: fixture())
        var files = try payloads(windowsZIP())
        let stateIndex = try XCTUnwrap(files.firstIndex { $0.0 == "state.json" })
        var state = try XCTUnwrap(JSONSerialization.jsonObject(with: files[stateIndex].1) as? [String: Any])
        state["unknownFutureProgress"] = ["important": true]
        files[stateIndex].1 = try JSONSerialization.data(withJSONObject: state)
        let manifestIndex = try XCTUnwrap(files.firstIndex { $0.0 == "manifest.json" })
        var manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: files[manifestIndex].1) as? [String: Any])
        var entries = try XCTUnwrap(manifest["files"] as? [[String: Any]])
        let entry = try XCTUnwrap(entries.firstIndex { $0["path"] as? String == "state.json" })
        entries[entry]["size"] = files[stateIndex].1.count
        entries[entry]["sha256"] = MaterialSafety.digest(files[stateIndex].1)
        manifest["files"] = entries; files[manifestIndex].1 = try JSONSerialization.data(withJSONObject: manifest)
        try await assertRejected(writeZIP(files, in: output), root: root, library: library, expected: initial)
    }

    func testRestoreWithOldMissingOrDamagedPDFPreservesOldGeneration() async throws {
        for damage in ["missing", "truncated", "signature"] {
            let root = try temporary(), source = try temporary(), library = StudyLibrary(root: root)
            _ = try await library.load(seed: fixture())
            let old = try await library.importMaterial(from: pdf(in: source), subjectId: "s", lessonId: "l")
            let url = try await library.materialURL(id: old.materials[0].id)
            let folder = try currentFolder(root)
            let oldStateBytes = try Data(contentsOf: folder.appendingPathComponent("state.json"))
            let damaged = damage == "signature" ? Data(repeating: 65, count: old.materials[0].size) : Data("broken".utf8)
            if damage == "missing" { try FileManager.default.removeItem(at: url) } else { try damaged.write(to: url) }
            let restored = try await library.restoreBackup(from: windowsZIP())
            XCTAssertEqual(restored.cards[0].id, "card-win")
            let restoredURL = try await library.materialURL(id: restored.materials[0].id)
            XCTAssertTrue(FileManager.default.fileExists(atPath: restoredURL.path))
            XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("state.json")), oldStateBytes)
            if damage != "missing" { XCTAssertEqual(try Data(contentsOf: url), damaged) }
            let notice = await library.takeRecoveryNotice()
            XCTAssertTrue(notice?.contains("anexos ausentes") == true)
            XCTAssertTrue(notice?.contains("danificados") == true)
            let backups = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("backups").path)
            XCTAssertTrue(backups.contains { $0.hasSuffix("-indice-original.json") })
            XCTAssertTrue(backups.contains { $0.hasSuffix("-anexos-disponiveis.zip") })
        }
    }

    func testRestoresWhenPreviousIndexIsCorruptedWithoutDeletingRawBytes() async throws {
        var invalidState = fixture(); invalidState.subjects[0].programId = "orphan-program"
        for broken in [Data("not-json-original-data".utf8), try JSONEncoder().encode(invalidState)] {
        let root = try temporary(), library = StudyLibrary(root: root)
        _ = try await library.load(seed: fixture())
        let oldFolder = try currentFolder(root), stateFile = oldFolder.appendingPathComponent("state.json")
        try broken.write(to: stateFile)
        let reopened = StudyLibrary(root: root)
        do { _ = try await reopened.load(); XCTFail("Corrupted index accepted") } catch {}
        let restored = try await reopened.restoreBackup(from: windowsZIP())
        XCTAssertEqual(restored.cards.first?.id, "card-win")
        XCTAssertEqual(try Data(contentsOf: stateFile), broken)
        let notice = await reopened.takeRecoveryNotice()
        XCTAssertTrue(notice?.contains("índice anterior estava danificado") == true)
        }
    }

    func testFailedImportSaveRollsBackNewCopyAndPreservesMetadata() async throws {
        let root = try temporary(), source = try temporary(), library = StudyLibrary(root: root)
        let initial = try await library.load(seed: fixture())
        let folder = try currentFolder(root)
        let before = try Data(contentsOf: folder.appendingPathComponent("state.json"))
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("state.previous.json"), withIntermediateDirectories: false)
        do { _ = try await library.importMaterial(from: pdf(in: source), subjectId: "s", lessonId: "l"); XCTFail("Failed metadata save committed an import") } catch {}
        let after = try await library.load()
        XCTAssertEqual(after, initial)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("state.json")), before)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("materials").path), [])
    }

    func testSafetyBackupFailureKeepsPointerStateAndGenerationCount() async throws {
        let root = try temporary(), library = StudyLibrary(root: root)
        let initial = try await library.load(seed: fixture())
        // A file at this path forces failure even when tests run as root.
        try Data("occupied".utf8).write(to: root.appendingPathComponent("backups"))
        try await assertRejected(windowsZIP(), root: root, library: library, expected: initial)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("backups")), Data("occupied".utf8))
    }

    func testReplacedMaterialsDirectoryCannotRedirectOpeningOrImporting() async throws {
        let root = try temporary(), source = try temporary(), outside = try temporary(), library = StudyLibrary(root: root)
        _ = try await library.load(seed: fixture())
        let imported = try await library.importMaterial(from: pdf(in: source), subjectId: "s", lessonId: "l")
        let directory = try currentFolder(root).appendingPathComponent("materials")
        let preserved = root.appendingPathComponent("old-materials")
        try FileManager.default.moveItem(at: directory, to: preserved)
        try FileManager.default.createSymbolicLink(at: directory, withDestinationURL: outside)
        do { _ = try await library.materialURL(id: imported.materials[0].id); XCTFail("Directory symlink accepted") } catch {}
        do { _ = try await library.importMaterial(from: pdf(in: source, name: "other.pdf", bytes: 129), subjectId: "s", lessonId: "l2"); XCTFail("Import followed directory symlink") } catch {}
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outside.path), [])
        let after = try await library.load(); XCTAssertEqual(after, imported)
    }

    func testReimportCanReplaceMissingOrCorruptedCopyWithoutDeletingItsRecord() async throws {
        for damage in ["missing", "signature", "truncated"] {
            let root = try temporary(), source = try temporary(), library = StudyLibrary(root: root)
            _ = try await library.load(seed: fixture())
            let original = try pdf(in: source)
            let first = try await library.importMaterial(from: original, subjectId: "s", lessonId: "l")
            let old = first.materials[0], url = try await library.materialURL(id: old.id)
            if damage == "missing" { try FileManager.default.removeItem(at: url) }
            else { try Data(repeating: 65, count: damage == "signature" ? old.size : 4).write(to: url) }
            let after = try await library.importMaterial(from: original, subjectId: "s", lessonId: "l")
            XCTAssertEqual(after.materials.count, 2)
            XCTAssertEqual(after.materials[0], old)
            XCTAssertEqual(after.lessons, first.lessons)
            let repaired = try await library.materialURL(id: after.materials[1].id)
            XCTAssertEqual(try Data(contentsOf: repaired), try Data(contentsOf: original))
            let notice = await library.takeRecoveryNotice()
            XCTAssertTrue(notice?.contains("registro anterior foi preservado") == true)
            let repeated = try await library.importMaterial(from: original, subjectId: "s", lessonId: "l")
            XCTAssertEqual(repeated, after)
        }
    }

    func testMissingClassificationNeverSwallowsPermissionOrDeviceFailures() {
        XCTAssertTrue(MaterialSafety.isMissing(NSError(domain: NSPOSIXErrorDomain, code: 2)))
        for code in [5, 13, 28] { // EIO, EACCES, ENOSPC
            XCTAssertFalse(MaterialSafety.isMissing(NSError(domain: NSPOSIXErrorDomain, code: code)))
        }
        XCTAssertFalse(MaterialSafety.isMissing(NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)))
    }

    func testInvalidFocusPreservationKeepsExactBytesAndStudyState() async throws {
        let root = try temporary(), library = StudyLibrary(root: root)
        let initial = try await library.load(seed: fixture())
        let folder = try currentFolder(root)
        let stateBytes = try Data(contentsOf: folder.appendingPathComponent("state.json"))
        let source = folder.appendingPathComponent("focus.json")
        let original = Data(repeating: 91, count: 128 * 1024)
        try original.write(to: source)
        do { _ = try await library.loadAuxiliary(FocusSnapshot.self, name: "focus.json"); XCTFail("Oversized timer accepted") } catch {}
        let preservedName = try await library.preserveInvalidFocus()
        let name = try XCTUnwrap(preservedName)
        XCTAssertTrue(name.hasPrefix("focus-invalid-")); XCTAssertTrue(name.hasSuffix(".json"))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("backups").appendingPathComponent(name)), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("state.json")), stateBytes)
        let restored = try await library.load(); XCTAssertEqual(restored, initial)
        try await library.saveAuxiliary(FocusSnapshot(), name: "focus.json")
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("backups").appendingPathComponent(name)), original)
    }

    func testFocusPreservationFailureDoesNotOverwriteOriginalOrBackupObstacle() async throws {
        let root = try temporary(), library = StudyLibrary(root: root)
        _ = try await library.load(seed: fixture())
        let focus = try currentFolder(root).appendingPathComponent("focus.json")
        let original = Data("invalid timer original".utf8), obstacle = Data("preserve this too".utf8)
        try original.write(to: focus)
        try obstacle.write(to: root.appendingPathComponent("backups"))
        do { _ = try await library.preserveInvalidFocus(); XCTFail("Non-directory recovery location accepted") } catch {}
        XCTAssertEqual(try Data(contentsOf: focus), original)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("backups")), obstacle)
    }

    func testFocusRecoveryRejectsLinksIncludingDanglingLinks() async throws {
        let root = try temporary(), outside = try temporary(), library = StudyLibrary(root: root)
        _ = try await library.load(seed: fixture())
        let focus = try currentFolder(root).appendingPathComponent("focus.json")
        let target = outside.appendingPathComponent("outside.json")
        for exists in [true, false] {
            if exists { try Data("outside original".utf8).write(to: target) }
            else { try FileManager.default.removeItem(at: target) }
            try FileManager.default.createSymbolicLink(at: focus, withDestinationURL: target)
            do { _ = try await library.loadAuxiliary(FocusSnapshot.self, name: "focus.json"); XCTFail("Linked focus was treated as a fresh timer") } catch {}
            do { _ = try await library.preserveInvalidFocus(); XCTFail("Linked focus was moved") } catch {}
            XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: focus.path), target.path)
            if exists { XCTAssertEqual(try Data(contentsOf: target), Data("outside original".utf8)) }
            try FileManager.default.removeItem(at: focus)
        }
    }

    func testAbsentAuxiliaryNeedsNoRecoveryFile() async throws {
        let root = try temporary(), library = StudyLibrary(root: root)
        _ = try await library.load(seed: fixture())
        let snapshot = try await library.loadAuxiliary(FocusSnapshot.self, name: "focus.json")
        let preserved = try await library.preserveInvalidFocus()
        XCTAssertNil(snapshot); XCTAssertNil(preserved)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("backups").path))
    }
}
