import Foundation
import llama

public final class ModelCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    public init() {}
    public func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    public func check() throws { if isCancelled { throw CancellationError() } }
}

public enum LocalModelError: Error, LocalizedError {
    case load, unsupported, context, inputTooLong, decoding
    public var errorDescription: String? {
        switch self {
        case .load: "Não foi possível abrir os pesos. Confira se o GGUF está completo e se há memória disponível."
        case .unsupported: "Use Qwen2.5 0.5B ou 1.5B Instruct em GGUF Q4_K_M. Outros modelos ainda não são aceitos."
        case .context: "Não há memória suficiente para preparar o modelo neste momento."
        case .inputTooLong: "O perfil e os registros excedem o contexto deste modelo. Reduza os textos do perfil; nenhuma resposta foi descartada."
        case .decoding: "O modelo não conseguiu concluir a sugestão. Seus registros não foram alterados."
        }
    }
}

/// Synchronous native work. Call exclusively from a worker task, never from MainActor.
/// Every request owns and frees its context, sampler, model and Metal allocations.
public enum NinhoLlamaRuntime {
    public static let version = "llama.cpp b10000"
    private static let initialized: Void = {
        llama_log_set({ _, _, _ in }, nil) // Do not log prompts, paths or user content.
        ggml_backend_load_all()
        llama_backend_init()
    }()

    public static func validate(path: String, cancellation: ModelCancellation) throws -> String {
        let model = try load(path: path, cancellation: cancellation)
        defer { llama_model_free(model) }
        try cancellation.check()
        return try modelName(model)
    }

    public static func generate(path: String, instructions: String, prompt: String,
                                cancellation: ModelCancellation) throws -> String {
        let model = try load(path: path, cancellation: cancellation)
        defer { llama_model_free(model) }
        _ = try modelName(model)
        try cancellation.check()
        guard let vocabulary = llama_model_get_vocab(model) else { throw LocalModelError.load }
        var parameters = llama_context_default_params()
        parameters.n_ctx = 4096
        parameters.n_batch = 128
        parameters.n_ubatch = 128
        parameters.n_threads = Int32(max(1, min(4, ProcessInfo.processInfo.activeProcessorCount - 2)))
        parameters.n_threads_batch = parameters.n_threads
        parameters.abort_callback_data = Unmanaged.passUnretained(cancellation).toOpaque()
        parameters.abort_callback = { pointer in
            guard let pointer else { return true }
            return Unmanaged<ModelCancellation>.fromOpaque(pointer).takeUnretainedValue().isCancelled
        }
        guard let context = llama_init_from_model(model, parameters) else {
            try cancellation.check(); throw LocalModelError.context
        }
        defer { llama_free(context) }
        guard let sampler = llama_sampler_init_greedy() else { throw LocalModelError.context }
        defer { llama_sampler_free(sampler) }
        // Only the validated Qwen2.5 Instruct family is supported, using its ChatML template.
        // Escape model delimiters inside supplied data so they cannot manufacture chat roles.
        let clean: (String) -> String = { $0.replacingOccurrences(of: "<|", with: "< |") }
        let input = "<|im_start|>system\n\(clean(instructions))<|im_end|>\n<|im_start|>user\n\(clean(prompt))<|im_end|>\n<|im_start|>assistant\n"
        guard input.utf8.count <= 12_000 else { throw LocalModelError.inputTooLong }
        var tokens = [llama_token](repeating: 0, count: input.utf8.count + 16)
        let count = input.withCString { text in
            tokens.withUnsafeMutableBufferPointer { buffer in
                llama_tokenize(vocabulary, text, Int32(input.utf8.count), buffer.baseAddress, Int32(buffer.count), true, true)
            }
        }
        let outputLimit = 384
        guard count > 0, Int(count) + outputLimit <= 4096 else { throw LocalModelError.inputTooLong }
        tokens = Array(tokens.prefix(Int(count)))
        var batch = llama_batch_init(128, 0, 1)
        defer { llama_batch_free(batch) }
        func decode(_ slice: ArraySlice<llama_token>, position: Int) throws {
            try cancellation.check()
            batch.n_tokens = Int32(slice.count)
            for (offset, token) in slice.enumerated() {
                batch.token[offset] = token
                batch.pos[offset] = Int32(position + offset)
                batch.n_seq_id[offset] = 1
                batch.seq_id[offset]![0] = 0
                batch.logits[offset] = offset == slice.count - 1 ? 1 : 0
            }
            let result = llama_decode(context, batch)
            try cancellation.check()
            guard result == 0 else { throw LocalModelError.decoding }
        }
        for start in stride(from: 0, to: tokens.count, by: 128) {
            try decode(tokens[start..<min(start + 128, tokens.count)], position: start)
        }
        var bytes = [UInt8]()
        for index in 0..<outputLimit {
            try cancellation.check()
            let token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocabulary, token) { break }
            var piece = [CChar](repeating: 0, count: 256)
            var size = llama_token_to_piece(vocabulary, token, &piece, Int32(piece.count), 0, false)
            if size < 0 {
                guard size >= -16_384 else { throw LocalModelError.decoding }
                piece = [CChar](repeating: 0, count: Int(-size))
                size = llama_token_to_piece(vocabulary, token, &piece, Int32(piece.count), 0, false)
            }
            guard size >= 0, size <= piece.count else { throw LocalModelError.decoding }
            bytes.append(contentsOf: piece.prefix(Int(size)).map { UInt8(bitPattern: $0) })
            try decode([token][...], position: tokens.count + index)
        }
        try cancellation.check()
        let result = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw LocalModelError.decoding }
        return result
    }

    private static func load(path: String, cancellation: ModelCancellation) throws -> OpaquePointer {
        _ = initialized
        try cancellation.check()
        var parameters = llama_model_default_params()
        #if targetEnvironment(simulator)
        parameters.n_gpu_layers = 0
        #else
        parameters.n_gpu_layers = 99
        #endif
        parameters.use_mmap = true
        parameters.progress_callback_user_data = Unmanaged.passUnretained(cancellation).toOpaque()
        parameters.progress_callback = { _, pointer in
            guard let pointer else { return false }
            return !Unmanaged<ModelCancellation>.fromOpaque(pointer).takeUnretainedValue().isCancelled
        }
        let model = path.withCString { llama_model_load_from_file($0, parameters) }
        guard let model else { try cancellation.check(); throw LocalModelError.load }
        return model
    }

    private static func modelName(_ model: OpaquePointer) throws -> String {
        func metadata(_ key: String) -> String {
            var text = [CChar](repeating: 0, count: 512)
            let count = key.withCString { llama_model_meta_val_str(model, $0, &text, text.count) }
            guard count > 0, count < text.count else { return "" }
            return String(decoding: text.prefix(Int(count)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
        let name = metadata("general.name")
        let parameters = llama_model_n_params(model)
        guard metadata("general.architecture") == "qwen2",
              name.lowercased().contains("qwen2.5"), name.lowercased().contains("instruct"),
              metadata("general.file_type") == "15",
              parameters >= 400_000_000, parameters <= 1_800_000_000 else { throw LocalModelError.unsupported }
        return name
    }
}
