import Foundation
import Combine
import NinhoCore
import NinhoLlama

@MainActor final class OptionalModelController: ObservableObject {
    static let shared = OptionalModelController()
    @Published private(set) var selection = ModelSelection()
    @Published private(set) var working = false
    @Published private(set) var notice = ""
    @Published private(set) var needsRecovery = false
    @Published private(set) var appleAvailability: AssistantAvailability = .checking
    private let library: LocalModelLibrary
    private let apple = AppleFoundationModelClient()
    private var operation: Task<Void, Never>?
    private var cancellation: ModelCancellation?

    var selectedName: String {
        switch selection.engine {
        case .embedded: "Ninho Adaptativo v1 · análise estatística incluída"
        case .apple: "Apple Foundation Models · modelo local do iOS"
        case .imported: selection.model?.name ?? "Modelo importado indisponível"
        }
    }
    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let testing = ProcessInfo.processInfo.arguments.contains("--uitesting")
        let profile = (ProcessInfo.processInfo.environment["NINHO_TEST_PROFILE"] ?? "default").filter { $0.isLetter || $0.isNumber || $0 == "-" }
        var directory = support.appendingPathComponent(testing ? "NinhoUITests/\(profile.isEmpty ? "default" : profile)/OptionalModels" : "Ninho/OptionalModels")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
        library = LocalModelLibrary(directory: directory)
    }
    func refresh() async {
        guard !working else { return }
        appleAvailability = ProcessInfo.processInfo.arguments.contains("--disable-ai") ? .unavailable(.other) : apple.availability
        do { selection = try await library.load(); needsRecovery = false }
        catch { record(error) }
    }
    func select(_ engine: OptionalAssistantEngine) async {
        guard !working else { return }
        working = true; defer { working = false }
        do { selection = try await library.select(engine); notice = "Preferência salva neste iPhone." }
        catch { record(error) }
    }
    func importModel(from source: URL) {
        guard !working else { return }
        working = true; notice = "Conferindo e copiando o modelo… O anterior permanece disponível até terminar."
        let token = ModelCancellation(); cancellation = token
        operation = Task {
            let scoped = source.startAccessingSecurityScopedResource()
            defer {
                if scoped { source.stopAccessingSecurityScopedResource() }
                working = false; operation = nil; cancellation = nil
            }
            var candidate: StagedModel?
            do {
                let staged = try await library.stage(source: source); candidate = staged
                try Task.checkCancellation(); try token.check()
                notice = "Validando os pesos com llama.cpp…"
                let worker = Task.detached(priority: .utility) {
                    try NinhoLlamaRuntime.validate(path: staged.url.path, cancellation: token)
                }
                _ = try await withTaskCancellationHandler { try await worker.value } onCancel: { token.cancel(); worker.cancel() }
                try Task.checkCancellation(); try token.check()
                selection = try await library.commit(staged)
                candidate = nil
                notice = "\(selection.model?.name ?? "Modelo") importado. Os pesos só ficam na memória durante uma sugestão."
            } catch is CancellationError { notice = "Importação interrompida. O modelo anterior foi preservado." }
            catch { record(error) }
            if let candidate { try? await library.discard(candidate) }
        }
    }
    func removeModel() async {
        guard !working else { return }
        working = true; defer { working = false }
        do { selection = try await library.remove(); notice = "Modelo opcional removido. O acompanhamento incluído continua pronto." }
        catch { record(error) }
    }
    func recoverSelection() async {
        guard !working else { return }
        working = true; defer { working = false }
        do {
            selection = try await library.recoverSelection(); needsRecovery = false
            notice = "Acompanhamento incluído restaurado. A configuração anterior e os arquivos foram guardados na pasta de recuperação dos modelos. Seu perfil e seus estudos não mudaram."
        } catch { record(error) }
    }
    private func record(_ error: Error) {
        notice = error.localizedDescription
        if (error as? ModelImportFailure) == .selection { needsRecovery = true }
    }
    func suggest(state: AppState) async throws -> String {
        guard !working else { throw AssistantFailure.busy }
        guard !needsRecovery else { throw ModelImportFailure.selection }
        guard !ProcessInfo.processInfo.arguments.contains("--disable-ai") else { throw AssistantFailure.unavailable }
        working = true
        let token = ModelCancellation(); cancellation = token
        defer { working = false; cancellation = nil; apple.release() }
        try Task.checkCancellation()
        if selection.engine == .embedded {
            let worker = Task.detached(priority: .userInitiated) { try AdaptiveMentor.analyze(state).plan }
            return try await withTaskCancellationHandler {
                let plan = try await worker.value
                try Task.checkCancellation(); try token.check()
                return plan
            } onCancel: { token.cancel(); worker.cancel() }
        }
        let contextWorker = Task.detached(priority: .userInitiated) {
            try AssistantContextBuilder.build(state: state,
                question: "Com base no meu perfil permanente e nos registros, proponha um próximo passo de estudo viável e uma adaptação para minha rotina. Não invente progresso nem altere meus objetivos.", compact: true)
        }
        let prompt = try await withTaskCancellationHandler { try await contextWorker.value } onCancel: { token.cancel(); contextWorker.cancel() }
        try Task.checkCancellation(); try token.check()
        switch selection.engine {
        case .embedded: throw AssistantFailure.busy
        case .apple:
            guard apple.availability.isAvailable else { throw AssistantFailure.unavailable }
            let text = try await apple.respond(to: prompt)
            try token.check(); try Task.checkCancellation()
            return text
        case .imported:
            guard let model = selection.model else { throw ModelImportFailure.missing }
            let path = try await library.modelURL(model).path
            try token.check(); try Task.checkCancellation()
            let worker = Task.detached(priority: .userInitiated) {
                try NinhoLlamaRuntime.generate(path: path, instructions: prompt.instructions, prompt: prompt.prompt, cancellation: token)
            }
            return try await withTaskCancellationHandler {
                let text = try await worker.value
                try Task.checkCancellation(); try token.check()
                return text
            } onCancel: { token.cancel(); worker.cancel() }
        }
    }
    func cancel() { cancellation?.cancel(); operation?.cancel(); apple.release() }
}
