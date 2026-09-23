import Foundation
import XCTest
import ZIPFoundation
@testable import NinhoCore

final class CompactBackupTests: XCTestCase, @unchecked Sendable {
    private let date = StudyEngine.parseTimestamp("2026-09-23T12:00:00Z")!
    private func temporary() throws -> URL {
        let value = FileManager.default.temporaryDirectory.appendingPathComponent("NinhoCompactTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: value, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: value) }; return value
    }
    private func fixture() -> AppState {
        var profile = StudentProfile(); profile.name = "Pessoa sintética"; profile.goal = "Aprender frações"
        profile.completedAt = StudyEngine.timestamp(date); profile.plan = "Plano salvo da Íris"; profile.planStatus = "ready"
        profile.tutorialsSeen = ["today", "studies"]
        return AppState(programs: [.init(id: "p", name: "Curso")], subjects: [.init(id: "s", programId: "p", name: "Matéria")], courses: [.init(id: "c", subjectId: "s", title: "Módulo")], lessons: [.init(id: "l", courseId: "c", subjectId: "s", title: "Aula", notes: String(repeating: "Notas de teste. ", count: 200))], cards: [.init(id: "q", subjectId: "s", lessonId: "l", question: "Quanto é 2+2?", answer: "4", createdAt: StudyEngine.timestamp(date))], materials: [.init(id: "m", name: "Livro.pdf", storedName: "12345678-1234-1234-1234-123456789012.pdf", type: "pdf", size: 100_000_000, subjectId: "s", lessonId: "l", createdAt: StudyEngine.timestamp(date), notes: "Rever página 12")], profile: profile)
    }
    func testDeflateRoundTripKeepsAllTextAndMaterialLinksButNoAttachmentBytes() throws {
        let root = try temporary(), file = root.appendingPathComponent("backup.zip"), state = fixture()
        var activity = LocalActivity(); activity.visit(.reviews, at: date); activity.trackingEnabled = false
        let info = try CompactBackup.write(state, activity: activity, to: file, at: date)
        let result = try CompactBackup.read(from: file)
        XCTAssertEqual(result.state, state); XCTAssertEqual(result.activity, activity)
        XCTAssertEqual(Set(try Archive(url: file, accessMode: .read).map(\.path)), ["state.json", "manifest.json", "activity.json"])
        XCTAssertLessThan(info.bytes, try JSONEncoder().encode(state).count)
        XCTAssertEqual(result.state.profile?.plan, "Plano salvo da Íris")
        XCTAssertEqual(result.state.materials.first?.notes, "Rever página 12")
    }
    func testSameDayUnchangedIsByteIdenticalAndChangedDataReplacesSingleDailyArchive() async throws {
        let root = try temporary(), backups = CompactBackupStore(directory: root)
        let first = try await backups.save(fixture(), at: date)
        let original = try Data(contentsOf: first.url)
        let same = try await backups.save(fixture(), at: date.addingTimeInterval(3_600))
        XCTAssertEqual(same, first); XCTAssertEqual(try Data(contentsOf: same.url), original)
        var changed = fixture(); changed.settings.name = "Nome atualizado"
        let next = try await backups.save(changed, at: date.addingTimeInterval(7_200))
        XCTAssertEqual(next.url, first.url); XCTAssertNotEqual(next.stateHash, first.stateHash)
        let list = try await backups.list(); XCTAssertEqual(list.count, 1)
        XCTAssertEqual(try CompactBackup.read(from: next.url).state.settings.name, "Nome atualizado")
    }
    func testRotationKeepsSevenDaysAndNeverRemovesUnmanagedFiles() async throws {
        let root = try temporary(), backups = CompactBackupStore(directory: root)
        let other = root.appendingPathComponent("my-backup.zip"); try Data("keep".utf8).write(to: other)
        for day in 0..<10 { _ = try await backups.save(fixture(), at: date.addingTimeInterval(Double(day) * 86_400)) }
        let files = try await backups.list()
        XCTAssertEqual(files.count, 7); XCTAssertTrue(FileManager.default.fileExists(atPath: other.path))
        XCTAssertEqual(files.first?.url.lastPathComponent, "Ninho-2026-10-02.compact.zip")
        XCTAssertEqual(files.last?.url.lastPathComponent, "Ninho-2026-09-26.compact.zip")
    }
    func testInvalidAndCancelledWritesPreservePreviousSnapshot() async throws {
        let root = try temporary(), file = root.appendingPathComponent("backup.zip")
        _ = try CompactBackup.write(fixture(), to: file, at: date)
        let original = try Data(contentsOf: file)
        var invalid = fixture(); invalid.version = 999
        XCTAssertThrowsError(try CompactBackup.write(invalid, to: file, at: date))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            var changed = self.fixture(); changed.settings.name = "Cancelled"
            return try CompactBackup.write(changed, to: file, at: self.date)
        }
        do { _ = try await task.value; XCTFail("Cancelled write succeeded") } catch is CancellationError { }
        XCTAssertEqual(try Data(contentsOf: file), original)
    }
    func testInvalidArchiveCannotReplaceCanonicalAndNewestSkipsCorruptedCopy() async throws {
        let root = try temporary(), backups = CompactBackupStore(directory: root.appendingPathComponent("snapshots"))
        let valid = try await backups.save(fixture(), at: date)
        let corrupt = valid.url.deletingLastPathComponent().appendingPathComponent("Ninho-2026-09-24.compact.zip")
        try Data("not a zip".utf8).write(to: corrupt)
        let selected = try await backups.newest(); XCTAssertEqual(selected?.info.url, valid.url)
        let library = StudyLibrary(root: root.appendingPathComponent("library"))
        let before = try await library.load(seed: fixture())
        do { _ = try await library.restoreCompactBackup(from: corrupt); XCTFail("Corrupt archive restored") } catch {}
        let after = try await library.load(); XCTAssertEqual(after, before)
    }
    func testAutomaticRestoreOnlyIntoPristineLibraryAndMissingAttachmentIsExplained() async throws {
        let root = try temporary(), file = root.appendingPathComponent("backup.zip")
        _ = try CompactBackup.write(fixture(), to: file, at: date)
        let library = StudyLibrary(root: root.appendingPathComponent("library"))
        let pristine = try await library.isPristine(); XCTAssertTrue(pristine)
        let restored = try await library.restoreCompactBackup(from: file, requirePristine: true)
        XCTAssertEqual(restored, fixture())
        do { _ = try await library.restoreCompactBackup(from: file, requirePristine: true); XCTFail("Existing collection overwritten") } catch {}
        do { _ = try await library.materialURL(id: "m"); XCTFail("Missing attachment unexpectedly exists") }
        catch { XCTAssertTrue(error.localizedDescription.contains("importe o arquivo novamente")) }
        let reopened = try await StudyLibrary(root: root.appendingPathComponent("library")).load()
        XCTAssertEqual(reopened, fixture())
    }
    func testCompactRestorePreservesPreviousGenerationAndCurrentPointerOnInvalidSnapshot() async throws {
        let root = try temporary(), file = root.appendingPathComponent("backup.zip"), location = root.appendingPathComponent("library")
        let library = StudyLibrary(root: location)
        _ = try await library.load(seed: fixture())
        let oldPointer = try Data(contentsOf: location.appendingPathComponent("current.json"))
        var updated = fixture(); updated.profile?.goal = "Novo objetivo"
        _ = try CompactBackup.write(updated, to: file, at: date)
        let restored = try await library.restoreCompactBackup(from: file)
        XCTAssertEqual(restored.profile?.goal, "Novo objetivo")
        let oldID = try JSONDecoder().decode(String.self, from: oldPointer)
        XCTAssertTrue(FileManager.default.fileExists(atPath: location.appendingPathComponent("collections/\(oldID)/state.json").path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: location.appendingPathComponent("backups"), includingPropertiesForKeys: nil).count, 1)
    }
    func testMissingOrCorruptCanonicalIndexIsNeverTreatedAsAnEmptyInstallation() async throws {
        let root = try temporary(), location = root.appendingPathComponent("library"), file = root.appendingPathComponent("backup.zip")
        _ = try await StudyLibrary(root: location).load(seed: fixture())
        _ = try CompactBackup.write(fixture(), to: file, at: date)
        try Data("corrupt pointer".utf8).write(to: location.appendingPathComponent("current.json"))
        let corrupt = StudyLibrary(root: location)
        let isEmpty = try await corrupt.isPristine(); XCTAssertFalse(isEmpty)
        do { _ = try await corrupt.restoreCompactBackup(from: file, requirePristine: true); XCTFail("Corrupt index overwritten automatically") } catch {}
        try FileManager.default.removeItem(at: location.appendingPathComponent("current.json"))
        let missing = StudyLibrary(root: location)
        let emptyWithOldFiles = try await missing.isPristine(); XCTAssertFalse(emptyWithOldFiles)
        do { _ = try await missing.load(seed: fixture()); XCTFail("Orphaned canonical collection silently replaced") } catch {}
    }
    func testRecognitionUsesManifestRatherThanFilenameAndOldFullFormatStillWorks() async throws {
        let root = try temporary(), compact = root.appendingPathComponent("ordinary.zip")
        _ = try CompactBackup.write(fixture(), to: compact, at: date)
        XCTAssertTrue(try CompactBackup.recognizes(compact))
        var state = fixture(); state.materials = []
        let library = StudyLibrary(root: root.appendingPathComponent("library")); _ = try await library.load(seed: state)
        let full = root.appendingPathComponent("misleading.compact.zip"); try await library.exportBackup(to: full)
        XCTAssertFalse(try CompactBackup.recognizes(full))
    }
    func testActivityIsPrunedValidatedAndRestoredWithOptOut() async throws {
        let root = try temporary(), file = root.appendingPathComponent("backup.zip")
        var activity = LocalActivity(); activity.visit(.reviews, at: date)
        activity.days.append(ActivityDay(date: "2020-01-01")); activity.trackingEnabled = false
        _ = try CompactBackup.write(fixture(), activity: activity, to: file, at: date)
        let read = try CompactBackup.read(from: file)
        XCTAssertEqual(read.activity?.days.count, 1); XCTAssertEqual(read.activity?.trackingEnabled, false)
        let library = StudyLibrary(root: root.appendingPathComponent("library"))
        _ = try await library.restoreCompactBackup(from: file)
        let restored = try await library.loadAuxiliary(LocalActivity.self, name: "activity.json")
        XCTAssertEqual(restored?.trackingEnabled, false)
        var invalid = activity; invalid.days[0].routes["external-application"] = RouteActivity()
        XCTAssertThrowsError(try CompactBackup.write(fixture(), activity: invalid, to: file, at: date))
    }
    func testValidZIPWithTamperedDigestOrUnexpectedPathIsRejected() throws {
        let root = try temporary(), original = root.appendingPathComponent("original.zip")
        _ = try CompactBackup.write(fixture(), to: original, at: date)
        let source = try Archive(url: original, accessMode: .read)
        for tampered in [true, false] {
            let target = root.appendingPathComponent("bad-\(tampered).zip")
            let archive = try Archive(url: target, accessMode: .create)
            for entry in source {
                var data = Data(); _ = try source.extract(entry) { data.append($0) }
                if tampered && entry.path == "state.json" {
                    var state = fixture(); state.settings.name = "Alterado sem atualizar SHA"
                    data = try JSONEncoder().encode(state)
                }
                try archive.addEntry(with: entry.path, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .deflate) { offset, count in
                    data.subdata(in: Int(offset)..<min(Int(offset) + count, data.count))
                }
            }
            if !tampered {
                try archive.addEntry(with: "../outside.txt", type: .file, uncompressedSize: Int64(1)) { _, _ in Data([1]) }
            }
            XCTAssertThrowsError(try CompactBackup.read(from: target))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.deletingLastPathComponent().appendingPathComponent("outside.txt").path))
    }
}
