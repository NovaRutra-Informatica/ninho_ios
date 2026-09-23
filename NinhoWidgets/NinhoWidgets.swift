import SwiftUI
import WidgetKit
import NinhoWidgetSupport

private struct NinhoEntry: TimelineEntry {
    let date: Date
    let value: WidgetMoment?
}

private struct NinhoProvider: TimelineProvider {
    func placeholder(in context: Context) -> NinhoEntry {
        NinhoEntry(date: .now, value: WidgetMoment(date: .now, streak: 3, studiedToday: true, todayMinutes: 20, goalMinutes: 30, dueReviews: 4))
    }
    func getSnapshot(in context: Context, completion: @escaping (NinhoEntry) -> Void) {
        if context.isPreview { completion(placeholder(in: context)); return }
        let now = Date()
        completion(NinhoEntry(date: now, value: load()?.moment(at: now)))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<NinhoEntry>) -> Void) {
        let now = Date()
        guard let snapshot = load(), let current = snapshot.moment(at: now) else {
            completion(Timeline(entries: [NinhoEntry(date: now, value: nil)], policy: .after(now.addingTimeInterval(3600))))
            return
        }
        var entries = [NinhoEntry(date: now, value: current)]
        entries += snapshot.moments.filter { $0.date > now }.map { NinhoEntry(date: $0.date, value: $0) }
        entries.append(NinhoEntry(date: snapshot.validUntil, value: nil))
        completion(Timeline(entries: entries, policy: .after(snapshot.validUntil)))
    }
    private func load() -> WidgetSnapshot? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "NinhoAppGroup") as? String,
              let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
        else { return nil }
        return try? WidgetSnapshotFile.read(in: directory)
    }
}

private enum WidgetPage { case streak, today, focus
    var destination: URL { URL(string: "ninho://\(self == .streak ? "progress" : self == .today ? "today" : "focus")")! }
    var title: String { self == .streak ? "Seu foguinho" : self == .today ? "Seu dia" : "Hora de focar" }
    var symbol: String { self == .streak ? "flame.fill" : self == .today ? "checkmark.circle" : "timer" }
}

private struct NinhoWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    let entry: NinhoEntry
    let page: WidgetPage
    private var green: Color { scheme == .dark ? Color(red: 0.55, green: 0.78, blue: 0.65) : Color(red: 0.22, green: 0.43, blue: 0.34) }
    private var surface: Color { scheme == .dark ? Color(red: 0.11, green: 0.12, blue: 0.14) : Color(red: 0.98, green: 0.98, blue: 0.95) }
    private var accessory: Bool { family == .accessoryCircular || family == .accessoryRectangular }
    var body: some View {
        Group {
            if let value = entry.value {
                if accessory { compact(value) } else { expanded(value) }
            } else {
                VStack(alignment: accessory ? .center : .leading, spacing: 6) {
                    Image(systemName: page.symbol).foregroundStyle(green)
                    Text("Abra o Ninho").font(accessory ? .caption : .headline)
                    if !accessory { Text("Atualize seu cantinho de estudos.").font(.caption).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: accessory ? .center : .leading)
            }
        }
        .containerBackground(surface, for: .widget)
        .widgetURL(page.destination)
        .privacySensitive()
    }
    @ViewBuilder private func compact(_ value: WidgetMoment) -> some View {
        if family == .accessoryCircular {
            VStack(spacing: 1) {
                Image(systemName: page.symbol).font(.caption)
                if page == .streak { Text("\(value.streak)").font(.headline).monospacedDigit() }
                else { focusNumber(value).font(.caption).monospacedDigit() }
            }.widgetAccentable()
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Label(page.title, systemImage: page.symbol).font(.headline).widgetAccentable()
                if page == .streak { Text("\(value.streak) \(value.streak == 1 ? "dia" : "dias") · \(value.studiedToday ? "Hoje contado" : "Vamos estudar?")").font(.caption) }
                else if page == .today { Text("\(Int(value.todayMinutes))/\(value.goalMinutes) min · \(value.dueReviews) revisões").font(.caption) }
                else { focusNumber(value).font(.caption) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func expanded(_ value: WidgetMoment) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Label(page.title, systemImage: page.symbol).font(.system(.caption, design: .rounded, weight: .semibold)).foregroundStyle(page == .streak ? .orange : green)
                switch page {
                case .streak:
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(value.streak)").font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                        Text(value.streak == 1 ? "dia" : "dias").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(value.studiedToday ? "Hoje já conta. Bom trabalho!" : value.streak > 0 ? "Um pouquinho hoje mantém o ritmo." : "Seu próximo dia começa aqui.").font(.caption).foregroundStyle(.secondary).lineLimit(3)
                case .today:
                    Text("\(Int(value.todayMinutes)) de \(value.goalMinutes) min").font(.system(.title3, design: .rounded, weight: .bold)).minimumScaleFactor(0.75)
                    ProgressView(value: min(1, value.todayMinutes / Double(max(1, value.goalMinutes)))).tint(green)
                    if family == .systemMedium {
                        Link(destination: URL(string: "ninho://reviews")!) { Label("\(value.dueReviews) revisões disponíveis", systemImage: "rectangle.on.rectangle").font(.caption).foregroundStyle(green) }
                    } else { Text("\(value.dueReviews) revisões disponíveis").font(.caption).foregroundStyle(.secondary) }
                case .focus:
                    focusNumber(value).font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit().minimumScaleFactor(0.6)
                    Text(focusCaption(value)).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if family == .systemMedium {
                VStack(spacing: 6) {
                    Image("owl").renderingMode(.original).resizable().scaledToFit().frame(width: 64, height: 64)
                    if page == .today {
                        Link(destination: URL(string: "ninho://focus")!) { Text("Focar agora").font(.system(.caption, design: .rounded, weight: .bold)).foregroundStyle(green).padding(.horizontal, 12).padding(.vertical, 8).background(green.opacity(0.12), in: Capsule()) }
                    } else { Text("no seu ritmo").font(.system(.caption2, design: .rounded)).foregroundStyle(.secondary) }
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
    @ViewBuilder private func focusNumber(_ value: WidgetMoment) -> some View {
        if let end = value.focusEndsAt, end > entry.date {
            Text(timerInterval: entry.date...end, countsDown: true)
        } else if value.focusState == "paused" {
            Text("\(Int(value.focusRemainingSeconds) / 60):\(String(format: "%02d", Int(value.focusRemainingSeconds) % 60))")
        } else if value.focusState == "ready" { Text("Concluído") }
        else { Text("\(value.focusMinutes) min") }
    }
    private func focusCaption(_ value: WidgetMoment) -> String {
        switch value.focusState {
        case "running": "Seu foco está em andamento."
        case "paused": "Pausado. Toque para retomar."
        case "ready": "Abra para registrar seu foco."
        case "completed": "Tempo salvo. Um passo de cada vez."
        default: "Um cantinho para se concentrar."
        }
    }
}

struct NinhoStreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NinhoStreak", provider: NinhoProvider()) { NinhoWidgetView(entry: $0, page: .streak) }
            .configurationDisplayName("Seu foguinho").description("Sua sequência de dias com estudo registrado.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}
struct NinhoTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NinhoToday", provider: NinhoProvider()) { NinhoWidgetView(entry: $0, page: .today) }
            .configurationDisplayName("Seu dia de estudos").description("Meta de minutos, revisões e acesso ao foco.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}
struct NinhoFocusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NinhoFocus", provider: NinhoProvider()) { NinhoWidgetView(entry: $0, page: .focus) }
            .configurationDisplayName("Hora de focar").description("Acompanhe o cronômetro e volte ao seu foco.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}
@main struct NinhoWidgets: WidgetBundle {
    var body: some Widget { NinhoStreakWidget(); NinhoTodayWidget(); NinhoFocusWidget() }
}
