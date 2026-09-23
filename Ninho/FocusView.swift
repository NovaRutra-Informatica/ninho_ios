import SwiftUI
import NinhoCore

struct FocusView: View {
    @EnvironmentObject var store: NinhoStore
    var subjectID = ""
    var lessonID = ""
    @State private var subject = ""
    @State private var lesson = ""
    @State private var minutes = 25
    @State private var resetting = false
    @State private var initialized = false
    private var locked: Bool { store.focus.phase == .running || store.focus.phase == .paused || store.focus.pendingSession != nil }
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image("owl").renderingMode(.original).resizable().scaledToFit().frame(width: 104, height: 104).accessibilityHidden(true)
                Text(store.focus.phase == .completed ? "Você fez espaço para aprender." : "Uma coisa de cada vez.").font(.system(.title, design: .rounded, weight: .bold)).multilineTextAlignment(.center)
                Group {
                    if store.focus.phase == .running {
                        TimelineView(.periodic(from: .now, by: 1)) { timeline in timerDisplay(at: timeline.date) }
                    } else { timerDisplay(at: .now) }
                }.ninhoCard()
                if locked {
                    VStack(spacing: 8) { Text(store.state.subjects.first { $0.id == store.focus.snapshot.subjectId }?.name ?? "Foco livre").font(.headline); if let current = store.state.lessons.first(where: { $0.id == store.focus.snapshot.lessonId }) { Text(current.title).font(.body) } }.accessibilityElement(children: .combine)
                    if !lessonID.isEmpty && lessonID != store.focus.snapshot.lessonId { Text("Há uma sessão em outra aula. Conclua-a antes de começar esta.").font(.body).foregroundStyle(.secondary) }
                } else {
                    VStack(alignment: .leading, spacing: 18) {
                        SubjectPicker(selection: $subject, allowEmpty: true)
                        Picker("Aula", selection: $lesson) { Text("Sem aula específica").tag(""); ForEach(store.state.lessons.filter { $0.subjectId == subject }) { Text($0.title).tag($0.id) } }
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Tempo de foco").font(.headline)
                            HStack {
                                ForEach([15, 25, 45, 60], id: \.self) { value in
                                    Button("\(value) min") { minutes = value }
                                        .buttonStyle(.bordered).tint(minutes == value ? NinhoStyle.green : .secondary)
                                        .accessibilityIdentifier("focus.preset.\(value)")
                                }
                            }
                            Slider(value: Binding(get: { Double(minutes) }, set: { minutes = Int($0) }), in: 1...180, step: 1)
                                .accessibilityLabel("Duração do foco").accessibilityValue("\(minutes) minutos")
                                .accessibilityIdentifier("focus.duration")
                            Stepper("\(minutes) minutos", value: $minutes, in: 1...180)
                                .accessibilityIdentifier("focus.minutes")
                        }
                    }.ninhoCard()
                }
                if let issue = store.focusRecoveryIssue {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(issue).font(.body).foregroundStyle(.secondary)
                        Button("Tentar recuperar cronômetro") { Task { await store.retryFocusRecovery() } }
                            .disabled(store.busy).accessibilityIdentifier("focus.retryRecovery")
                    }.ninhoCard()
                } else { controls }
                VStack(alignment: .leading, spacing: 10) {
                    Button("Avisar quando o foco terminar", systemImage: "bell") { Task { await store.enableFocusNotifications() } }
                        .buttonStyle(.bordered).accessibilityIdentifier("focus.notifications")
                    if !store.focusNotificationNotice.isEmpty { Text(store.focusNotificationNotice).font(.footnote).foregroundStyle(.secondary) }
                    Text("O aviso é silencioso para respeitar sua música. Com o iPhone bloqueado, o sistema pode suspender o Ninho; ao voltar, a contagem é recuperada pelos horários salvos.").font(.footnote).foregroundStyle(.secondary)
                }.ninhoCard()
                if store.focus.phase == .completed { Text("Que tal descansar por \(store.state.settings.breakMinutes) minutos antes do próximo passo?").font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center) }
                if !store.notice.isEmpty { Text(store.notice).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center).accessibilityIdentifier("app.notice") }
                Text("O cronômetro continua ao sair da tela. Pausar interrompe a contagem. Finalizar salva apenas o tempo usado, sem marcar a aula como concluída.").font(.body).foregroundStyle(.secondary)
            }.padding(24)
        }.background(NinhoStyle.canvas).navigationTitle("Hora do foco").navigationBarTitleDisplayMode(.inline).accessibilityIdentifier("screen.focus").ninhoTutorial(.focus)
            .task {
                guard !initialized else { return }
                initialized = true; subject = subjectID; lesson = lessonID; minutes = store.state.settings.focusMinutes
            }
            .onChange(of: subject) { if !store.state.lessons.contains(where: { $0.id == lesson && $0.subjectId == subject }) { lesson = "" } }
            .confirmationDialog("Descartar o tempo desta sessão?", isPresented: $resetting, titleVisibility: .visible) { Button("Reiniciar sem registrar", role: .destructive) { Task { await store.focusAction("reset") } } }
    }
    private func timerDisplay(at date: Date) -> some View {
        let remaining = locked ? store.focus.remainingSeconds(at: date) : Double(minutes * 60)
        return VStack(spacing: 16) {
            Text(String(format: "%02d:%02d", Int(ceil(remaining)) / 60, Int(ceil(remaining)) % 60))
                .font(.system(size: 64, weight: .medium, design: .rounded)).monospacedDigit().minimumScaleFactor(0.6)
                .accessibilityIdentifier("focus.elapsed")
            ProgressView(value: locked ? store.focus.elapsedSeconds(at: date) : 0, total: max(1, store.focus.snapshot.targetSeconds)).tint(NinhoStyle.green)
        }
    }
    @ViewBuilder private var controls: some View {
        VStack(spacing: 14) {
            switch store.focus.phase {
            case .idle, .completed:
                if store.focus.pendingSession != nil { Button("Salvar sessão concluída") { Task { await store.focusAction("finish") } }.accessibilityIdentifier("focus.finish") }
                else { Button("Começar foco", systemImage: "play.fill") { Task { await store.focusAction("start", subjectId: subject, lessonId: lesson, minutes: Double(minutes)) } }.accessibilityIdentifier("focus.start") }
            case .running:
                Button("Pausar", systemImage: "pause.fill") { Task { await store.focusAction("pause") } }.accessibilityIdentifier("focus.pause")
                Button("Finalizar e registrar") { Task { await store.focusAction("finish") } }.accessibilityIdentifier("focus.finish")
            case .paused:
                Button("Continuar", systemImage: "play.fill") { Task { await store.focusAction("resume") } }.accessibilityIdentifier("focus.resume")
                Button("Finalizar e registrar") { Task { await store.focusAction("finish") } }.accessibilityIdentifier("focus.finish")
            }
        }.buttonStyle(.borderedProminent).controlSize(.large).disabled(store.busy)
        if locked && store.focus.pendingSession == nil { Button("Reiniciar", role: .destructive) { resetting = true }.accessibilityIdentifier("focus.reset") }
    }
}
