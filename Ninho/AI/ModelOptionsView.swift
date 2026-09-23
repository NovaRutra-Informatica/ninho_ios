import SwiftUI
import UniformTypeIdentifiers
import UIKit
import NinhoCore
import NinhoLlama

@MainActor struct AssistantIdentityCard: View {
    @ObservedObject private var model = OptionalModelController.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Íris · sua assistente de estudos", systemImage: "sparkles").font(.headline)
            Text("Acompanhamento: Ninho Adaptativo v1").font(.subheadline.weight(.semibold))
            Text("Motor estatístico local incluído. Analisa seus registros e mostra sugestões; não é um modelo de linguagem.").font(.footnote).foregroundStyle(.secondary)
            Text("Modelo opcional: \(model.selection.engine == .embedded ? "nenhum ativado" : model.selectedName)").font(.subheadline)
            NavigationLink { ModelOptionsView() } label: {
                Label("Conhecer ou trocar o modelo", systemImage: "slider.horizontal.3").frame(maxWidth: .infinity)
            }.buttonStyle(.bordered).accessibilityIdentifier("assistant.models")
        }.ninhoCard().task { await model.refresh() }
    }
}

@MainActor struct ModelOptionsView: View {
    @EnvironmentObject private var store: NinhoStore
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var model = OptionalModelController.shared
    @State private var importing = false
    @State private var confirmingRemoval = false
    @State private var generation: Task<Void, Never>?
    @State private var status = ""
    @State private var result = ""
    @State private var resultSource = ""
    @State private var resultRevision: Int?
    @State private var generatedProfile: StudentProfile?
    @State private var saving = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Íris, do seu jeito", systemImage: "sparkles").font(.title2.weight(.semibold))
                    Text("O Ninho já acompanha seus estudos sem baixar nada. Se quiser, um modelo de linguagem pode escrever uma sugestão a partir do perfil e dos registros. Ele só é carregado quando você pedir aqui.")
                    Text("Selecionado: \(model.selectedName)").font(.subheadline.weight(.semibold)).accessibilityIdentifier("model.selected")
                }.ninhoCard()
                VStack(alignment: .leading, spacing: 16) {
                    Text("Quem prepara a sugestão").font(.headline)
                    option(.embedded, title: "Ninho Adaptativo v1", detail: "Incluído · leve · sempre offline. Estatística e regras transparentes para o acompanhamento diário.")
                    option(.apple, title: "Apple Foundation Models", detail: appleDetail)
                    if let imported = model.selection.model {
                        option(.imported, title: imported.name, detail: "\(ByteCountFormatter.string(fromByteCount: imported.byteCount, countStyle: .file)) · \(NinhoLlamaRuntime.version) · GGUF Q4_K_M")
                        Text(imported.originalFilename).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                        Button("Remover arquivo importado", role: .destructive) { confirmingRemoval = true }.disabled(model.working)
                    }
                }.ninhoCard()
                importGuide
                if !model.notice.isEmpty { Text(model.notice).font(.footnote).accessibilityIdentifier("model.notice") }
                if model.needsRecovery {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("A configuração dos modelos precisa de recuperação.").font(.headline)
                        Text("Você pode voltar ao acompanhamento incluído. O Ninho guarda a configuração danificada e os arquivos de modelo em uma pasta de recuperação, sem alterar seu perfil ou seus estudos.").font(.subheadline)
                        Button("Recuperar configuração dos modelos") { Task { await model.recoverSelection() } }
                            .buttonStyle(.bordered).disabled(model.working).accessibilityIdentifier("model.recover")
                    }.ninhoCard()
                }
                if model.working {
                    HStack { ProgressView(); Text("Preparando no iPhone…"); Spacer(); Button("Cancelar") { cancel() } }
                }
                VStack(alignment: .leading, spacing: 16) {
                    Label("Uma sugestão para seu perfil", systemImage: "leaf").font(.headline)
                    Text("As respostas completas do perfil são inseridas em cada pedido. A IA pode errar; confira a sugestão antes de guardá-la. Seu plano e seus objetivos não mudam sozinhos.").font(.subheadline).foregroundStyle(.secondary)
                    Button { prepare() } label: { Label("Preparar sugestão com o modelo selecionado", systemImage: "sparkles").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).disabled(model.working || model.needsRecovery || generation != nil || saving || store.state.profile == nil)
                        .accessibilityIdentifier("model.generate")
                    if !result.isEmpty {
                        Text(resultSource).font(.caption).foregroundStyle(.secondary)
                        Text(result).textSelection(.enabled).accessibilityIdentifier("model.result")
                        Button("Guardar como meu plano") { Task { await saveSuggestion() } }
                            .buttonStyle(.bordered).disabled(saving || store.state.profile?.revision != resultRevision)
                        if store.state.profile?.revision != resultRevision {
                            Text("Seu perfil mudou. Prepare outra sugestão com as respostas atuais.").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    if !status.isEmpty { Text(status).font(.footnote).accessibilityIdentifier("model.status") }
                }.ninhoCard()
            }.padding(20).frame(maxWidth: 650).frame(maxWidth: .infinity)
        }.background(NinhoStyle.canvas).navigationTitle("Modelo da Íris").navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("screen.models").task { await model.refresh() }
            .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "gguf", conformingTo: .data) ?? .data], allowsMultipleSelection: false) { outcome in
                switch outcome {
                case .success(let urls): if let url = urls.first { model.importModel(from: url) }
                case .failure(let error): status = error.localizedDescription
                }
            }
            .confirmationDialog("Remover somente o modelo opcional?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
                Button("Remover modelo", role: .destructive) { Task { await model.removeModel() } }
            } message: { Text("Seus estudos, perfil e planos continuam salvos. O acompanhamento incluído segue funcionando.") }
            .onChange(of: scenePhase) { _, phase in if phase != .active { cancel() } }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                cancel(); status = "O iPhone pediu mais memória. A geração foi interrompida; seu plano anterior continua salvo."
            }
            .onDisappear { cancel() }
    }
    private var appleDetail: String {
        switch model.appleAvailability {
        case .available: "Modelo local do iOS disponível. O nome e a revisão exatos dos pesos são gerenciados pela Apple e não são expostos pelo sistema."
        case .checking: "Consultando disponibilidade do modelo local do iOS…"
        case .unavailable(let reason): reason.message
        }
    }
    private func option(_ engine: OptionalAssistantEngine, title: String, detail: String) -> some View {
        Button { Task { await model.select(engine) } } label: {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: model.selection.engine == engine ? "checkmark.circle.fill" : "circle").foregroundStyle(NinhoStyle.green)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.padding(15).background(NinhoStyle.canvas, in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain).disabled(model.working)
            .accessibilityAddTraits(model.selection.engine == engine ? .isSelected : [])
            .accessibilityIdentifier("model.engine.\(engine.rawValue)")
    }
    private var importGuide: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label("Importar um modelo do Arquivos", systemImage: "square.and.arrow.down").font(.headline)
            Text("Formato aceito no iPhone: um arquivo .gguf de Qwen2.5 0.5B ou 1.5B Instruct, quantizado em Q4_K_M, até 1,2 GiB.").font(.subheadline.weight(.semibold))
            Text("1. Obtenha o arquivo completo na página oficial do modelo. Para começar, escolha Qwen2.5-0.5B-Instruct-Q4_K_M.gguf; ele usa menos memória que o de 1.5B.")
            Text("2. Copie para Arquivos → No Meu iPhone, por AirDrop, cabo ou pelo navegador. Espere a cópia terminar. Um arquivo apenas na nuvem precisa estar baixado antes de usar offline.")
            Text("3. Toque em Importar GGUF e selecione esse arquivo. Reserve espaço para a cópia; o Ninho confere o formato e abre os pesos antes de substituir o modelo anterior.")
            Text("4. Depois, use Preparar sugestão. Sair desta tela ou colocar o Ninho em segundo plano interrompe a geração e libera os pesos. O temporizador e o acompanhamento leve continuam independentes.")
            Link("Página oficial do Qwen2.5 0.5B Instruct GGUF", destination: URL(string: "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF")!)
            Text("ZIP, pastas, modelos divididos em partes, .safetensors, .task e .litertlm não são aceitos no iPhone. Os arquivos de IA não entram no backup da coleção. O Ninho não baixa modelos automaticamente nem envia seu perfil para servidores.").font(.footnote).foregroundStyle(.secondary)
            Button { importing = true } label: { Label(model.selection.model == nil ? "Importar GGUF" : "Importar outro GGUF", systemImage: "folder").frame(maxWidth: .infinity) }
                .buttonStyle(.bordered).disabled(model.working).accessibilityIdentifier("model.import")
        }.font(.subheadline).ninhoCard()
    }
    private func cancel() { generation?.cancel(); model.cancel() }
    private func prepare() {
        guard generation == nil else { return }
        status = ""; result = ""; generatedProfile = nil
        generation = Task {
            defer { generation = nil }
            await store.flushPreferences()
            guard !Task.isCancelled else { return }
            guard !store.hasPendingPreferences, let profile = store.state.profile else { status = "Salve seu perfil antes de preparar uma sugestão."; return }
            let snapshot = store.state, source = model.selectedName
            do {
                let text = try await model.suggest(state: snapshot)
                try Task.checkCancellation()
                guard store.state.profile == profile else { status = "O perfil mudou durante a geração. Prepare uma nova sugestão."; return }
                result = text; resultSource = source; resultRevision = profile.revision; generatedProfile = profile
            } catch is CancellationError { status = "Geração interrompida. Seu plano anterior foi preservado." }
            catch { status = error.localizedDescription }
        }
    }
    private func saveSuggestion() async {
        guard !saving else { return }
        saving = true; defer { saving = false }
        await store.flushPreferences()
        guard !store.hasPendingPreferences, let original = generatedProfile, var profile = store.state.profile,
              profile == original, profile.revision == resultRevision, !result.isEmpty else {
            status = "O perfil mudou. Prepare uma nova sugestão antes de salvar."; return
        }
        profile.plan = String(result.prefix(4_000)); profile.planStatus = "ready"; profile.planProfileRevision = profile.revision
        if await store.perform(.updateProfile(profile)) { status = "Sugestão salva no seu perfil, junto do backup da coleção." }
        else { status = "Não foi possível salvar a sugestão. Ela continua nesta tela para tentar novamente." }
    }
}
