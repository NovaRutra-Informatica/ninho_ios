import SwiftUI
import NinhoCore

struct NinhoHeaderShortcuts: ViewModifier {
    @EnvironmentObject private var store: NinhoStore
    @State private var showingCalendar = false

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarLeading) {
                HStack(spacing: 2) {
                    NavigationLink { MoreView() } label: {
                        Image(systemName: "person.crop.circle").font(.system(size: 21))
                            .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    }.labelStyle(.iconOnly)
                        .accessibilityLabel("Meu perfil e preferências").accessibilityIdentifier("navigation.profile")
                    Button { showingCalendar = true } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "flame.fill").font(.system(size: 20)).foregroundStyle(NinhoStyle.amber)
                            Text(store.overview.streak.formatted()).font(.subheadline.weight(.bold)).monospacedDigit().lineLimit(1)
                                .foregroundStyle(.primary).contentTransition(.numericText())
                        }.padding(.horizontal, 6).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityLabel("Sua sequência: \(store.overview.streak) \(store.overview.streak == 1 ? "dia" : "dias")")
                        .accessibilityHint("Abre o calendário dos dias em que você estudou.")
                        .accessibilityIdentifier("navigation.streak")
                }
            }
        }.sheet(isPresented: $showingCalendar) { StreakCalendarView() }
    }
}

struct StreakCalendarView: View {
    @EnvironmentObject private var store: NinhoStore
    @Environment(\.dismiss) private var dismiss
    @State private var month = Date()
    @State private var evaluatedAt = Date()
    @State private var activeDays: Set<String>?
    private var calendar: Calendar { .current }
    private var summary: StudyCalendarMonth {
        StudyCalendarMonth(containing: month, activeDays: activeDays ?? [], at: evaluatedAt, calendar: calendar)
    }
    private var isCurrentMonth: Bool { calendar.isDate(month, equalTo: evaluatedAt, toGranularity: .month) }
    private var weekdayLabels: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return (0..<7).map { symbols[($0 + calendar.firstWeekday - 1) % 7] }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 12) {
                        Image(systemName: "flame.fill").font(.system(size: 30)).foregroundStyle(NinhoStyle.amber)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(store.overview.streak) \(store.overview.streak == 1 ? "dia seguido" : "dias seguidos")")
                                .font(.system(.title2, design: .rounded, weight: .bold))
                            Text("Cada dia de estudo deixa sua marca.").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    VStack(spacing: 18) {
                        HStack {
                            monthButton("Mês anterior", symbol: "chevron.left", offset: -1)
                            Text(month.formatted(.dateTime.month(.wide).year())).font(.headline)
                                .frame(maxWidth: .infinity).multilineTextAlignment(.center).accessibilityIdentifier("streak.month")
                            monthButton("Próximo mês", symbol: "chevron.right", offset: 1).disabled(isCurrentMonth)
                        }
                        if activeDays == nil {
                            ProgressView("Abrindo seus dias de estudo…").frame(maxWidth: .infinity).padding(.vertical, 30)
                        } else {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7), spacing: 8) {
                                ForEach(0..<7, id: \.self) { index in
                                    Text(weekdayLabels[index]).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity).accessibilityHidden(true)
                                }
                                ForEach(0..<summary.leadingEmptyDays, id: \.self) { _ in Color.clear.frame(height: 54).accessibilityHidden(true) }
                                ForEach(summary.days) { day in dayCell(day) }
                            }.accessibilityIdentifier("streak.calendar")
                            HStack(spacing: 18) {
                                Label("Dia estudado", systemImage: "flame.fill").foregroundStyle(NinhoStyle.amber)
                                Label("Hoje", systemImage: "circle").foregroundStyle(NinhoStyle.green)
                            }.font(.caption).frame(maxWidth: .infinity)
                        }
                        if !isCurrentMonth {
                            Button("Voltar para hoje") { month = Date() }.font(.subheadline.weight(.semibold))
                                .frame(minHeight: 44).accessibilityIdentifier("streak.today")
                        }
                    }.ninhoCard()
                    if activeDays != nil {
                        Text(summary.studiedDays == 0 ? "Ainda não há estudos registrados neste mês." : "Você estudou em \(summary.studiedDays) \(summary.studiedDays == 1 ? "dia deste mês" : "dias deste mês").")
                            .font(.subheadline).accessibilityIdentifier("streak.monthSummary")
                    }
                    Text("O foguinho conta dias com sessões ou revisões registradas. Abrir o aplicativo ou deixar um cronômetro sem salvar não marca o dia.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(20).frame(maxWidth: 580).frame(maxWidth: .infinity)
            }.background(NinhoStyle.canvas).navigationTitle("Sua sequência").navigationBarTitleDisplayMode(.inline)
                .accessibilityIdentifier("screen.streak")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Concluir") { dismiss() }.accessibilityIdentifier("streak.close") } }
        }.task(id: store.revision) {
            let sessions = store.state.sessions, now = Date(), activeCalendar = Calendar.current
            let worker = Task.detached(priority: .userInitiated) { StudyStreak.activeDays(in: sessions, at: now, calendar: activeCalendar) }
            let days = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard !Task.isCancelled else { return }
            activeDays = days; evaluatedAt = now
        }
    }

    private func monthButton(_ label: String, symbol: String, offset: Int) -> some View {
        Button {
            if let next = calendar.date(byAdding: .month, value: offset, to: summary.start) { month = next }
        } label: { Image(systemName: symbol).frame(width: 44, height: 44).contentShape(Rectangle()) }
            .buttonStyle(.plain).accessibilityLabel(label)
            .accessibilityIdentifier(offset < 0 ? "streak.previous" : "streak.next")
    }

    private func dayCell(_ day: StudyCalendarMonth.Day) -> some View {
        VStack(spacing: 4) {
            Text(day.number.formatted()).font(.subheadline.weight(day.studied || day.isToday ? .bold : .regular)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.65)
            Image(systemName: "flame.fill").font(.system(size: 10)).foregroundStyle(NinhoStyle.amber).opacity(day.studied ? 1 : 0)
        }.frame(maxWidth: .infinity).frame(minHeight: 54)
            .background(day.studied ? NinhoStyle.green.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 13))
            .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(day.isToday ? NinhoStyle.green : .clear, lineWidth: 1.5) }
            .opacity(day.isFuture ? 0.35 : 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(day.date.formatted(date: .complete, time: .omitted))\(day.isToday ? ", hoje" : ""), \(day.studied ? "estudo registrado" : day.isFuture ? "dia futuro" : "sem estudo registrado")")
            .accessibilityIdentifier("streak.day.\(day.id)")
    }
}
