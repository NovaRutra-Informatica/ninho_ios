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
    private var locked: Bool { store.focus.phase == .running || store.focus.phase == .paused || store.focus.pendingSession != nil }
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image("owl").resizable().scaledToFit().frame(width: 104, height: 104).accessibilityHidden(true)
                Text(store.focus.phase == .completed ? "Você fez espaço para aprender." : "Uma coisa de cada vez.").font(.system(.title, design: .rounded, weight: .bold)).multilineTextAlignment(.center)
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    let remaining = store.focus.remainingSeconds(at: timeline.date)
                    VStack(spacing: 16) {
                        Text(String(format: "%02d:%02d", Int(remaining) / 60, Int(remaining) % 60)).font(.system(size: 64, weight: .medium, design: .rounded)).monospacedDigit().minimumScaleFactor(0.6).accessibilityIdentifier("focus.elapsed")
                        ProgressView(value: store.focus.elapsedSeconds(at: timeline.date), total: store.focus.snapshot.targetSeconds).tint(NinhoStyle.green)
                    }
                }.ninhoCard()
                if locked {
                    VStack(spacing: 8) { Text(store.state.subjects.first { $0.id == store.focus.snapshot.subjectId }?.name ?? "Foco livre").font(.headline); if let current = store.state.lessons.first(where: { $0.id == store.focus.snapshot.lessonId }) { Text(current.title).font(.body) } }.accessibilityElement(children: .combine)
                    if !lessonID.isEmpty && lessonID != store.focus.snapshot.lessonId { Text("Há uma sessão em outra aula. Conclua-a antes de começar esta.").font(.body).foregroundStyle(.secondary) }
                } else {
                    VStack(alignment: .leading, spacing: 18) {
                        SubjectPicker(selection: $subject, allowEmpty: true)
                        Picker("Aula", selection: $lesson) { Text("Sem aula específica").tag(""); ForEach(store.state.lessons.filter { $0.subjectId == subject }) { Text($0.title).tag($0.id) } }
                        Stepper("\(minutes) minutos de foco", value: $minutes, in: 1...180, step: 1)
                    }.ninhoCard()
                }
                if let issue = store.focusRecoveryIssue {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(issue).font(.body).foregroundStyle(.secondary)
                        Button("Tentar recuperar cronômetro") { Task { await store.retryFocusRecovery() } }
                            .disabled(store.busy).accessibilityIdentifier("focus.retryRecovery")
                    }.ninhoCard()
                } else { controls }
                if store.focus.phase == .completed { Text("Que tal descansar por \(store.state.settings.breakMinutes) minutos antes do próximo passo?").font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center) }
                if !store.notice.isEmpty { Text(store.notice).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center).accessibilityIdentifier("app.notice") }
                Text("O cronômetro continua ao sair da tela. Pausar interrompe a contagem. Finalizar salva apenas o tempo usado, sem marcar a aula como concluída.").font(.body).foregroundStyle(.secondary)
            }.padding(24)
        }.background(Color(.systemGroupedBackground)).navigationTitle("Hora do foco").navigationBarTitleDisplayMode(.inline).accessibilityIdentifier("screen.focus")
            .task { subject = subjectID; lesson = lessonID; minutes = store.state.settings.focusMinutes }
            .onChange(of: subject) { if !store.state.lessons.contains(where: { $0.id == lesson && $0.subjectId == subject }) { lesson = "" } }
            .confirmationDialog("Descartar o tempo desta sessão?", isPresented: $resetting, titleVisibility: .visible) { Button("Reiniciar sem registrar", role: .destructive) { Task { await store.focusAction("reset") } } }
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
