import Foundation
import llama

#if os(iOS)
import os
#endif

struct LlmStats {
    var loadMs = 0
    var promptTokens = 0
    var promptMs = 0
    var generatedTokens = 0
    var generateMs = 0

    var promptTokensPerSecond: Double {
        promptMs > 0 ? Double(promptTokens) / (Double(promptMs) / 1000) : 0
    }
    var tokensPerSecond: Double {
        generateMs > 0 ? Double(generatedTokens) / (Double(generateMs) / 1000) : 0
    }
}

struct LlamaError: Error, CustomStringConvertible {
    let description: String
}

/// Thin Swift wrapper over llama.cpp's C API: load a GGUF model once, then run prompts.
///
/// Not thread-safe: use it from one queue at a time (ReviseEngine does). Every call starts from
/// an empty KV cache, so calls never leak context into each other.
/// The model is kept loaded between calls; freeing it is just dropping the last reference.
final class LlamaRunner {
    private let model: OpaquePointer
    private let context: OpaquePointer
    private let vocab: OpaquePointer
    private let chatTemplate: String
    private let batchSize = 512

    /// How long loading the model + creating the context took.
    let loadMs: Int
    let contextSize: Int

    /// llama.cpp's global backend init; safe to call once for the whole process.
    private static let backendReady: Bool = {
        llama_backend_init()
        return true
    }()

    init(modelPath: String, contextSize: Int = 4096) throws {
        _ = Self.backendReady
        let started = DispatchTime.now()
        let memBefore = Self.availableMemoryMB()

        var modelParams = llama_model_default_params()
        #if targetEnvironment(simulator)
        modelParams.n_gpu_layers = 0           // no Metal in the simulator
        #else
        modelParams.n_gpu_layers = 99          // offload every layer to the GPU (Metal)
        #endif
        guard let loadedModel = llama_model_load_from_file(modelPath, modelParams) else {
            throw LlamaError(description: "Could not load the LLM file (corrupt, or not enough memory)")
        }

        var contextParams = llama_context_default_params()
        contextParams.n_ctx = UInt32(contextSize)
        contextParams.n_batch = UInt32(batchSize)
        guard let loadedContext = llama_init_from_model(loadedModel, contextParams) else {
            llama_model_free(loadedModel)
            throw LlamaError(description: "Could not create the LLM context (not enough memory?)")
        }
        model = loadedModel
        context = loadedContext
        vocab = llama_model_get_vocab(loadedModel)!
        self.contextSize = contextSize
        if let cString = llama_model_chat_template(loadedModel, nil) {
            chatTemplate = String(cString: cString)
        } else {
            chatTemplate = ""
        }
        loadMs = Int(Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000)
        NSLog("REVISE-LLM loaded in %d ms, context %d tokens, free memory before=%d MB after=%d MB",
              loadMs, contextSize, memBefore, Self.availableMemoryMB())
    }

    deinit {
        llama_free(context)
        llama_model_free(model)
    }

    /// Runs one prompt and returns the generated text plus timing.
    /// - grammar: optional GBNF text; the model can then only produce text the grammar allows.
    func generate(prompt: String, system: String? = nil, maxTokens: Int, grammar: String?)
        throws -> (text: String, stats: LlmStats)
    {
        var stats = LlmStats(loadMs: loadMs)
        let formatted = formatChat(system: system, user: prompt)
        var promptTokens = tokenize(formatted)
        guard !promptTokens.isEmpty else { throw LlamaError(description: "Empty prompt") }
        // Leave room for the answer; if the prompt alone is too long, fail clearly.
        guard promptTokens.count < contextSize - 16 else {
            throw LlamaError(description: "Prompt is too long (\(promptTokens.count) tokens; limit \(contextSize - 16))")
        }
        let budget = min(maxTokens, contextSize - promptTokens.count - 1)
        stats.promptTokens = promptTokens.count

        llama_memory_clear(llama_get_memory(context), true)    // fresh KV cache for every call

        // Sampler chain: optional grammar filter first, then greedy (deterministic, best for extraction).
        let chain = llama_sampler_chain_init(llama_sampler_chain_default_params())!
        defer { llama_sampler_free(chain) }
        if let grammar, !grammar.isEmpty {
            guard let grammarSampler = llama_sampler_init_grammar(vocab, grammar, "root") else {
                throw LlamaError(description: "The JSON grammar could not be parsed")
            }
            llama_sampler_chain_add(chain, grammarSampler)
        }
        llama_sampler_chain_add(chain, llama_sampler_init_greedy())

        // 1) Prompt processing ("prefill"), in chunks no bigger than the batch size.
        let promptStart = DispatchTime.now()
        var offset = 0
        while offset < promptTokens.count {
            let count = min(batchSize, promptTokens.count - offset)
            let status = promptTokens.withUnsafeMutableBufferPointer { buffer -> Int32 in
                llama_decode(context, llama_batch_get_one(buffer.baseAddress! + offset, Int32(count)))
            }
            guard status == 0 else { throw LlamaError(description: "Decoding the prompt failed (code \(status))") }
            offset += count
        }
        stats.promptMs = Self.elapsedMs(since: promptStart)

        // 2) Generation: sample one token, feed it back, repeat until end-of-turn or the budget.
        let generateStart = DispatchTime.now()
        var bytes: [UInt8] = []
        var generated = 0
        while generated < budget {
            var token = llama_sampler_sample(chain, context, -1)   // also tells the grammar what was chosen
            if llama_vocab_is_eog(vocab, token) { break }
            bytes.append(contentsOf: piece(for: token))
            generated += 1
            let status = withUnsafeMutablePointer(to: &token) { pointer -> Int32 in
                llama_decode(context, llama_batch_get_one(pointer, 1))
            }
            guard status == 0 else { throw LlamaError(description: "Generating failed (code \(status))") }
        }
        stats.generatedTokens = generated
        stats.generateMs = Self.elapsedMs(since: generateStart)

        NSLog("REVISE-LLM prompt %d tok in %d ms (%.1f tok/s); generated %d tok in %d ms (%.1f tok/s)",
              stats.promptTokens, stats.promptMs, stats.promptTokensPerSecond,
              stats.generatedTokens, stats.generateMs, stats.tokensPerSecond)
        return (String(decoding: bytes, as: UTF8.self), stats)
    }

    // MARK: - Helpers

    /// Wraps the prompt in the model's chat format. We recognise the two families we may ship
    /// (Qwen/ChatML and Gemma); anything else falls back to ChatML.
    private func formatChat(system: String?, user: String) -> String {
        if chatTemplate.contains("<start_of_turn>") {
            // Gemma has no system role: fold it into the user turn.
            let body = [system, user].compactMap { $0 }.joined(separator: "\n\n")
            return "<start_of_turn>user\n\(body)<end_of_turn>\n<start_of_turn>model\n"
        }
        let systemText = system ?? "You are a precise assistant. Follow the instructions exactly."
        return "<|im_start|>system\n\(systemText)<|im_end|>\n<|im_start|>user\n\(user)<|im_end|>\n<|im_start|>assistant\n"
    }

    private func tokenize(_ text: String) -> [llama_token] {
        let capacity = text.utf8.count + 16
        var tokens = [llama_token](repeating: 0, count: capacity)
        // add_special=false: the chat format above already contains the special tokens as text;
        // parse_special=true turns "<|im_start|>" etc. into their real token IDs.
        var count = llama_tokenize(vocab, text, Int32(text.utf8.count), &tokens, Int32(capacity), false, true)
        if count < 0 {
            tokens = [llama_token](repeating: 0, count: Int(-count))
            count = llama_tokenize(vocab, text, Int32(text.utf8.count), &tokens, -count, false, true)
        }
        return Array(tokens.prefix(max(0, Int(count))))
    }

    /// Bytes of one token. Collected as bytes (not String) because a character can be split
    /// across tokens; we decode to a String only at the end.
    private func piece(for token: llama_token) -> [UInt8] {
        var buffer = [CChar](repeating: 0, count: 128)
        var length = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        if length < 0 {
            buffer = [CChar](repeating: 0, count: Int(-length))
            length = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        }
        return buffer.prefix(max(0, Int(length))).map { UInt8(bitPattern: $0) }
    }

    private static func elapsedMs(since start: DispatchTime) -> Int {
        Int(Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)
    }

    /// Memory this app may still use, in MB (iOS only; -1 elsewhere). Helps judge fit on 4 GB phones.
    static func availableMemoryMB() -> Int {
        #if os(iOS)
        return Int(os_proc_available_memory() / 1_048_576)
        #else
        return -1
        #endif
    }
}
