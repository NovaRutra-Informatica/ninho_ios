import Foundation
import FoundationModels
import Combine
import NinhoCore

/// Release this session; iOS manages the on-device model's memory.
@MainActor final class AppleFoundationModelClient: AssistantModelClient {
    private var session: LanguageModelSession?
    private var requestID: UUID?

    var availability: AssistantAvailability {
        switch SystemLanguageModel.default.availability {
        case .available: return .available
        case .unavailable(.deviceNotEligible): return .unavailable(.deviceNotEligible)
        case .unavailable(.appleIntelligenceNotEnabled): return .unavailable(.intelligenceDisabled)
        case .unavailable(.modelNotReady): return .unavailable(.modelNotReady)
        case .unavailable: return .unavailable(.other)
        @unknown default: return .unavailable(.other)
        }
    }

    func respond(to prompt: AssistantPrompt) async throws -> String {
        try Task.checkCancellation()
        guard availability.isAvailable else { throw AssistantFailure.unavailable }
        guard session?.isResponding != true else { throw AssistantFailure.busy }
        let id = UUID()
        // A fresh session bounds the transcript; the core supplies limited history.
        let current = LanguageModelSession(instructions: prompt.instructions)
        session = current; requestID = id
        defer {
            if requestID == id { session = nil; requestID = nil }
        }
        do {
            let response = try await current.respond(
                to: prompt.prompt,
                options: GenerationOptions(temperature: 0.35, maximumResponseTokens: prompt.maximumResponseTokens)
            )
            try Task.checkCancellation()
            return response.content
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as LanguageModelSession.GenerationError {
            // iOS 26/Xcode 26 errors; validate replacements against the target SDK.
            switch error {
            case .exceededContextWindowSize: throw AssistantFailure.contextTooLarge
            case .assetsUnavailable: throw AssistantFailure.unavailable
            case .guardrailViolation, .refusal: throw AssistantFailure.refused
            case .rateLimited, .concurrentRequests: throw AssistantFailure.busy
            case .unsupportedLanguageOrLocale: throw AssistantFailure.unsupportedLanguage
            default: throw AssistantFailure.other("O modelo da Apple não respondeu desta vez.")
            }
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw AssistantFailure.other("O modelo da Apple não respondeu desta vez.")
        }
    }

    func release() {
        requestID = nil
        session = nil
    }
}

@MainActor final class UnavailableAssistantClient: AssistantModelClient {
    let reason: AssistantUnavailableReason
    init(reason: AssistantUnavailableReason = .other) { self.reason = reason }
    var availability: AssistantAvailability { .unavailable(reason) }
    func respond(to prompt: AssistantPrompt) async throws -> String { throw AssistantFailure.unavailable }
    func release() {}
}

@MainActor final class LocalAssistantModel: ObservableObject {
    @Published private(set) var availability: AssistantAvailability = .checking
    @Published private(set) var messages: [AssistantMessage] = []
    @Published private(set) var isResponding = false
    @Published private(set) var error: String?
    @Published private(set) var notice = ""
    @Published private(set) var retryQuestion: String?

    private let conversation: AssistantConversation
    private var task: Task<Void, Never>?
    private var activeID: UUID?

    init(client: (any AssistantModelClient)? = nil) {
        conversation = AssistantConversation(client: client ?? AppleFoundationModelClient())
    }

    func refreshAvailability() {
        conversation.refreshAvailability()
        synchronize()
    }

    @discardableResult
    func send(_ question: String, state: AppState, subjectID: String? = nil, retry: Bool = false) -> Bool {
        guard task == nil else { return false }
        guard let request = conversation.begin(question: question, state: state, subjectID: subjectID, retry: retry) else {
            synchronize()
            return false
        }
        activeID = request.id
        synchronize()
        task = Task { [weak self] in
            guard let self else { return }
            await conversation.perform(request)
            guard activeID == request.id else { return }
            task = nil; activeID = nil
            synchronize()
        }
        return true
    }

    func retry(state: AppState, subjectID: String? = nil) {
        guard let question = retryQuestion else { return }
        send(question, state: state, subjectID: subjectID, retry: true)
    }

    func cancel() {
        activeID = nil
        task?.cancel(); task = nil
        conversation.cancel()
        synchronize()
    }

    func newConversation() {
        cancel()
        conversation.clear()
        synchronize()
    }

    func deactivate() { cancel() }

    private func synchronize() {
        availability = conversation.availability; messages = conversation.messages
        isResponding = conversation.isResponding; error = conversation.error
        notice = conversation.notice; retryQuestion = conversation.retryQuestion
    }
}
