import Foundation
import WidgetKit
import NinhoWidgetSupport

actor WidgetPublisher {
    private var lastRevision = -1
    func publish(_ snapshot: WidgetSnapshot, revision: Int) async throws {
        guard revision > lastRevision else { return }
        guard let group = Bundle.main.object(forInfoDictionaryKey: "NinhoAppGroup") as? String,
              let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
        else { throw WidgetSnapshotError.unavailable }
        try WidgetSnapshotFile.write(snapshot, in: directory)
        lastRevision = revision
        await MainActor.run {
            for kind in ["NinhoStreak", "NinhoToday", "NinhoFocus"] { WidgetCenter.shared.reloadTimelines(ofKind: kind) }
        }
    }
}
