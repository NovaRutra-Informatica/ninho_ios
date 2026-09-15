import SwiftUI
import NinhoCore

@MainActor struct AssistantView: View {
    let state: AppState
    @StateObject private var model: LocalAssistantModel
    @State private var draft = ""
    @State private var subjectID = ""
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var composerFocused: Bool
    private let green = NinhoStyle.green

    init(state: AppState) {
        self.state = state
        let arguments = ProcessInfo.processInfo.arguments
        let disableForUITests = arguments.contains("--uitesting") && arguments.contains("--disable-ai")
        _model = StateObject(wrappedValue: LocalAssistantModel(
            client: disableForUITests ? UnavailableAssistantClient(reason: .modelNotReady) : nil
        ))
    }

    init(state: AppState, model: LocalAssistantModel) {
        self.state = state
        _model = StateObject(wrappedValue: model)
    }

    private var questionTooLong: Bool { draft.utf8.count > AssistantContextBuilder.maximumQuestionBytes }
    private var motionReduced: Bool { reduceMotion || state.settings.reducedMotion }

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    introduction
                    availabilityCard
                    if model.availability.isAvailable { subjectPicker }
                    if model.messages.isEmpty && model.availability.isAvailable { starters }
                    ForEach(model.messages) { message in
                        messageBubble(message)
                    }
                    if model.isResponding {
                        HStack(spacing: 10) {
                            ProgressView().tint(green)
                            Text("A Íris está pensando no seu iPhone…")
                                .font(.body)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("assistant.generating")
                    }
                    if let error = model.error {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(error, systemImage: "exclamationmark.bubble")
                                .font(.body)
                                .foregroundStyle(.primary)
                            if model.retryQuestion != nil {
                                Button("Tentar novamente") {
                                    model.retry(state: state, subjectID: subjectID.isEmpty ? nil : subjectID)
                                }
                                .buttonStyle(.bordered)
                                .disabled(model.isResponding || !model.availability.isAvailable)
                                .accessibilityIdentifier("assistant.retry")
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
                        .accessibilityIdentifier("assistant.error")
                    } else if model.retryQuestion != nil && !model.isResponding {
                        Button("Continuar de onde parei") {
                            model.retry(state: state, subjectID: subjectID.isEmpty ? nil : subjectID)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!model.availability.isAvailable)
                    }
                    if !model.notice.isEmpty {
                        Text(model.notice)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("assistant.context")
                    }
                    Color.clear.frame(height: 1).id("conversation-end")
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.messages.count) {
                withAnimation(motionReduced ? nil : .easeOut(duration: 0.25)) {
                    scroll.scrollTo("conversation-end", anchor: .bottom)
                }
            }
            .onChange(of: model.isResponding) {
                if !model.isResponding {
                    withAnimation(motionReduced ? nil : .easeOut(duration: 0.25)) {
                        scroll.scrollTo("conversation-end", anchor: .bottom)
                    }
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) { composer }
        .navigationTitle("Minha assistente")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Nova conversa", systemImage: "square.and.pencil") {
                    model.newConversation(); draft = ""
                }
                .accessibilityIdentifier("assistant.newConversation")
            }
        }
        .tint(green)
        .task { model.refreshAvailability() }
        .onDisappear { model.deactivate() }
        .onChange(of: scenePhase) {
            if scenePhase == .active { model.refreshAvailability() }
            else { model.deactivate() }
        }
        .onChange(of: state.subjects.map(\.id)) {
            if !subjectID.isEmpty && !state.subjects.contains(where: { $0.id == subjectID }) { subjectID = "" }
        }
        .accessibilityIdentifier("screen.assistant")
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 27, weight: .medium))
                    .foregroundStyle(green)
                    .frame(width: 62, height: 62)
                    .background(green.opacity(0.10), in: RoundedRectangle(cornerRadius: 22))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Oi, eu sou a Íris.").font(.title2.bold())
                    Text("Vamos dar o próximo passo?").font(.body).foregroundStyle(.secondary)
                }
            }
            Text("Converse sobre seus estudos, organize uma revisão ou peça uma explicação curta. Uso os registros do Ninho para ajudar você a escolher por onde começar.")
                .font(.body)
            Text("A IA pode errar. Cartões praticados e tempo de estudo mostram o que você registrou; não são uma medida de domínio.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 26))
    }

    @ViewBuilder private var availabilityCard: some View {
        switch model.availability {
        case .checking:
            HStack(spacing: 10) {
                ProgressView()
                Text("Conferindo a IA local…").font(.body)
            }
        case .available:
            VStack(alignment: .leading, spacing: 6) {
                Label("IA da Apple · neste iPhone", systemImage: "iphone.gen3.radiowaves.left.and.right")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(green)
                Text("O Ninho não envia esta conversa ao PC ou a um servidor. O histórico é temporário e fica só nesta tela.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("assistant.available")
        case .unavailable(let reason):
            VStack(alignment: .leading, spacing: 14) {
                Label("A conversa local ainda não está disponível", systemImage: "sparkles.rectangle.stack")
                    .font(.headline)
                Text(reason.message).font(.body)
                Button("Verificar novamente") { model.refreshAvailability() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("assistant.refreshAvailability")
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
            .accessibilityIdentifier("assistant.unavailable")
        }
    }

    private var subjectPicker: some View {
        Picker("Foco da conversa", selection: $subjectID) {
            Text("Todas as matérias").tag("")
            ForEach(state.subjects, id: \.id) { subject in
                Text(subject.name).tag(subject.id)
            }
        }
        .pickerStyle(.menu)
        .disabled(model.isResponding)
        .accessibilityIdentifier("assistant.subject")
    }

    private var starters: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Um começo simples").font(.headline)
            ForEach(["O que vale revisar hoje?", "Monte um plano curto para meu próximo estudo.", "Como diferenciar revisar de estudar de novo?"], id: \.self) { question in
                Button { send(question) } label: {
                    HStack(alignment: .center, spacing: 12) {
                        Text(question).font(.body).multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.up.right")
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)
                .disabled(model.isResponding)
            }
        }
    }

    private func messageBubble(_ message: AssistantMessage) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(message.role == .user ? "Você" : "Íris")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(message.role == .user ? Color.white.opacity(0.88) : green)
            Text(message.content).font(.body).textSelection(.enabled)
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(message.role == .user ? .white : Color.primary)
        .background(message.role == .user ? green : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
        .padding(message.role == .user ? .leading : .trailing, 20)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("assistant.message.\(message.role.rawValue)")
    }

    private var composer: some View {
        VStack(spacing: 10) {
            if questionTooLong {
                Text("A pergunta ficou longa. Divida em partes menores.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(alignment: .bottom, spacing: 12) {
                TextField("Pergunte à Íris", text: $draft, axis: .vertical)
                    .font(.body)
                    .lineLimit(1...5)
                    .focused($composerFocused)
                    .submitLabel(.send)
                    .onSubmit { send(draft) }
                    .disabled(!model.availability.isAvailable || model.isResponding)
                    .accessibilityIdentifier("assistant.prompt")
                if model.isResponding {
                    Button("Cancelar", systemImage: "stop.fill") { model.cancel() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("assistant.cancel")
                } else {
                    Button("Enviar", systemImage: "arrow.up") { send(draft) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.availability.isAvailable || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || questionTooLong)
                        .accessibilityIdentifier("assistant.send")
                }
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.bar)
    }

    private func send(_ question: String) {
        if model.send(question, state: state, subjectID: subjectID.isEmpty ? nil : subjectID) {
            draft = ""; composerFocused = false
        }
    }
}
