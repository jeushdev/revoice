import Foundation
import llama

#if os(iOS)
import os
#endif

struct LlmStats {
    var loadMs = 0
    var promptTokens = 0            // tokens in the whole prompt
    var reusedTokens = 0            // of those, already in the KV cache (skipped)
    var promptMs = 0                // time to process the NEW prompt tokens
    var generatedTokens = 0
    var generateMs = 0

    var newPromptTokens: Int { promptTokens - reusedTokens }
    var promptTokensPerSecond: Double {
        promptMs > 0 ? Double(newPromptTokens) / (Double(promptMs) / 1000) : 0
    }
    var tokensPerSecond: Double {
        generateMs > 0 ? Double(generatedTokens) / (Double(generateMs) / 1000) : 0
    }
}

/// llama_decode returned a non-zero code (-3 and below are fatal compute errors, 1 = no KV slot).
struct LlamaDecodeError: Error {
    let code: Int32
}

struct LlamaError: Error, CustomStringConvertible {
    let description: String
}

/// Thin Swift wrapper over llama.cpp's C API: load a GGUF model once, then run prompts.
///
/// Not thread-safe: use it from one queue at a time (ReviseEngine does). The model stays loaded
/// between calls. The KV cache (the model's "memory" of the prompt it has already read) is kept
/// too: a new prompt only processes the part that differs from the previous one, so a shared
/// system prompt / instruction block is paid for once.
final class LlamaRunner {
    private let model: OpaquePointer
    private var context: OpaquePointer
    private let vocab: OpaquePointer
    private let chatTemplate: String
    /// Prompt tokens per GPU pass. Small on purpose: on the phone a long single Metal command (a
    /// 512-token pass takes seconds while Flutter is also drawing) can be killed by iOS, which
    /// llama.cpp reports as a decode failure (code -3). 128 keeps every command short.
    private var batchSize = LlamaRunner.safeBatch
    private static let safeBatch = 128
    /// Test hook (MacLlmTest): make the next N decode calls fail, to exercise the recovery ladder.
    var injectDecodeFailures = 0

    /// Tokens currently held in the KV cache (the prompt of the last call).
    private var cachedTokens: [llama_token] = []

    /// How long loading the model + creating the context took.
    let loadMs: Int
    let contextSize: Int
    /// Backend/offload lines llama.cpp printed while loading (is Metal used? how many layers?).
    let diagnostics: [String]

    // MARK: - llama.cpp log capture

    private static let logLock = NSLock()
    private static var logLines: [String] = []
    private static let logKeywords = [
        "offload", "metal", "mtl", "gpu", "flash", "device", "ubatch", "n_batch", "threads",
        "kv ", "compute buffer", "simdgroup", "bf16", "model size", "layers",
    ]

    /// llama.cpp's global init, plus a log hook that keeps the lines useful for performance triage.
    private static let backendReady: Bool = {
        llama_log_set({ _, text, _ in
            guard let text else { return }
            let line = String(cString: text).trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = line.lowercased()
            guard !line.isEmpty, LlamaRunner.logKeywords.contains(where: { lower.contains($0) }) else { return }
            LlamaRunner.logLock.lock()
            if LlamaRunner.logLines.count < 80 { LlamaRunner.logLines.append(String(line.prefix(200))) }
            LlamaRunner.logLock.unlock()
        }, nil)
        llama_backend_init()
        return true
    }()

    init(modelPath: String, contextSize: Int = 4096) throws {
        _ = Self.backendReady
        Self.logLock.lock(); Self.logLines.removeAll(); Self.logLock.unlock()
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

        guard let loadedContext = Self.makeContext(
            model: loadedModel, contextSize: contextSize, batch: Self.safeBatch, flash: true)
        else {
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

        Self.logLock.lock(); diagnostics = Self.logLines; Self.logLock.unlock()
        NSLog("REVISE-LLM loaded in %d ms, context %d tokens, threads %d, free memory before=%d MB after=%d MB",
              loadMs, contextSize, Self.threads, memBefore, Self.availableMemoryMB())
        for line in diagnostics { NSLog("REVISE-LLM-INIT %@", line) }
    }

    deinit {
        llama_free(context)
        llama_model_free(model)
    }

    // MARK: - Context creation and recovery

    /// With every layer on the GPU the CPU threads only orchestrate. The iPhone 13 has 2 fast
    /// cores; using the 4 slow ones too makes the CPU side wait on stragglers.
    private static var threads: Int32 { Int32(max(1, min(2, ProcessInfo.processInfo.activeProcessorCount / 3))) }

    private static func makeContext(model: OpaquePointer, contextSize: Int, batch: Int, flash: Bool) -> OpaquePointer? {
        var params = llama_context_default_params()
        params.n_ctx = UInt32(contextSize)
        params.n_batch = UInt32(batch)
        params.n_ubatch = UInt32(batch)
        params.flash_attn_type = flash ? LLAMA_FLASH_ATTN_TYPE_ENABLED : LLAMA_FLASH_ATTN_TYPE_DISABLED
        params.n_threads = threads
        params.n_threads_batch = threads
        if let created = llama_init_from_model(model, params) { return created }
        // Flash attention unsupported on this device? Retry with the default (auto) setting.
        params.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_AUTO
        return llama_init_from_model(model, params)
    }

    /// One decode call. Failures become `LlamaDecodeError` so `generate` can recover.
    private func decode(_ batch: llama_batch) throws {
        if injectDecodeFailures > 0 {
            injectDecodeFailures -= 1
            throw LlamaDecodeError(code: -3)
        }
        let status = llama_decode(context, batch)
        if status != 0 { throw LlamaDecodeError(code: status) }
    }

    /// Recovery after a failed decode. Level 1: forget the KV cache and start the prompt from
    /// scratch. Level 2: also build a fresh context without flash attention and with tiny passes.
    private func recover(level: Int) throws {
        cachedTokens = []
        if level == 1 {
            llama_memory_clear(llama_get_memory(context), true)
            return
        }
        guard let fresh = Self.makeContext(model: model, contextSize: contextSize, batch: 64, flash: false) else {
            throw LlamaError(description: "Could not rebuild the LLM context after a failure (not enough memory?)")
        }
        llama_free(context)
        context = fresh
        batchSize = 64
    }

    // MARK: - Warm-up

    /// Reads the system prompt ahead of time so the first real request skips it.
    /// Cheap to call repeatedly: an identical prefix is recognised and not re-processed.
    func warmup(system: String?) throws {
        let prefix = formatChat(system: system, user: "")
        // Everything up to the start of the user text is shared by every request with this system prompt.
        let marker = chatTemplate.contains("<start_of_turn>") ? "<start_of_turn>user\n" : "<|im_start|>user\n"
        guard let range = prefix.range(of: marker) else { return }
        let started = DispatchTime.now()
        let tokens = tokenize(String(prefix[..<range.upperBound]))
        try prefill(tokens)
        NSLog("REVISE-LLM warm-up: %d tokens cached in %d ms", tokens.count, Self.elapsedMs(since: started))
    }

    // MARK: - Generation

    /// Runs one prompt and returns the generated text plus timing.
    /// - grammar: optional GBNF text; the model can then only produce text the grammar allows.
    /// - onToken: called with each newly generated piece of text (for streaming to the UI).
    func generate(
        prompt: String, system: String? = nil, maxTokens: Int, grammar: String?,
        onToken: ((String) -> Void)? = nil
    ) throws -> (text: String, stats: LlmStats) {
        var level = 0
        while true {
            do {
                return try generateOnce(prompt: prompt, system: system, maxTokens: maxTokens, grammar: grammar, onToken: onToken)
            } catch let failure as LlamaDecodeError {
                level += 1
                NSLog("REVISE-LLM decode failed (code %d, free memory %d MB); recovery level %d",
                      failure.code, Self.availableMemoryMB(), level)
                guard level <= 2 else {
                    throw LlamaError(description: "Decoding failed (code \(failure.code), \(Self.availableMemoryMB()) MB free) even after recovery")
                }
                try recover(level: level)
            }
        }
    }

    private func generateOnce(
        prompt: String, system: String?, maxTokens: Int, grammar: String?,
        onToken: ((String) -> Void)?
    ) throws -> (text: String, stats: LlmStats) {
        var stats = LlmStats(loadMs: loadMs)
        let formatted = formatChat(system: system, user: prompt)
        let promptTokens = tokenize(formatted)
        guard !promptTokens.isEmpty else { throw LlamaError(description: "Empty prompt") }
        // Leave room for the answer; if the prompt alone is too long, fail clearly.
        guard promptTokens.count < contextSize - 16 else {
            throw LlamaError(description: "Prompt is too long (\(promptTokens.count) tokens; limit \(contextSize - 16))")
        }
        let budget = min(maxTokens, contextSize - promptTokens.count - 1)
        stats.promptTokens = promptTokens.count

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

        // 1) Prompt processing ("prefill"): only the part that differs from what's already cached.
        let promptStart = DispatchTime.now()
        stats.reusedTokens = try prefill(promptTokens)
        stats.promptMs = Self.elapsedMs(since: promptStart)

        // 2) Generation: sample one token, feed it back, repeat until end-of-turn or the budget.
        let generateStart = DispatchTime.now()
        var bytes: [UInt8] = []
        var emittedCount = 0
        var generated = 0
        while generated < budget {
            var token = llama_sampler_sample(chain, context, -1)   // also tells the grammar what was chosen
            if llama_vocab_is_eog(vocab, token) { break }
            bytes.append(contentsOf: piece(for: token))
            generated += 1
            if let onToken, let text = String(data: Data(bytes), encoding: .utf8) {
                // Only emit when the bytes form complete characters (a character can span tokens).
                if text.count > emittedCount {
                    onToken(String(text.dropFirst(emittedCount)))
                    emittedCount = text.count
                }
            }
            do {
                try withUnsafeMutablePointer(to: &token) { pointer in
                    try decode(llama_batch_get_one(pointer, 1))
                }
            } catch {
                cachedTokens = []
                throw error
            }
        }
        stats.generatedTokens = generated
        stats.generateMs = Self.elapsedMs(since: generateStart)

        NSLog("REVISE-LLM prompt %d tok (%d reused, %d new in %d ms = %.1f tok/s); generated %d tok in %d ms (%.1f tok/s)",
              stats.promptTokens, stats.reusedTokens, stats.newPromptTokens, stats.promptMs,
              stats.promptTokensPerSecond, stats.generatedTokens, stats.generateMs, stats.tokensPerSecond)
        return (String(decoding: bytes, as: UTF8.self), stats)
    }

    // MARK: - Prompt cache

    /// Makes the KV cache hold exactly `tokens`, processing only what isn't cached yet.
    /// Returns how many leading tokens were reused.
    @discardableResult
    private func prefill(_ tokens: [llama_token]) throws -> Int {
        // Longest shared start between what's cached and what we need now.
        var shared = 0
        let limit = min(cachedTokens.count, tokens.count)
        while shared < limit && cachedTokens[shared] == tokens[shared] { shared += 1 }
        // The last token must be decoded fresh so we have its logits to sample from.
        if shared == tokens.count { shared = tokens.count - 1 }

        let memory = llama_get_memory(context)
        // Drop everything after the shared part (old prompt tail + old answer). If partial
        // removal isn't supported, start over.
        if shared > 0, llama_memory_seq_rm(memory, 0, Int32(shared), -1) == false {
            shared = 0
        }
        if shared == 0 { llama_memory_clear(memory, true) }

        var work = tokens
        var offset = shared
        cachedTokens = []                                   // invalid until we finish successfully
        while offset < work.count {
            let count = min(batchSize, work.count - offset)
            try work.withUnsafeMutableBufferPointer { buffer in
                try decode(llama_batch_get_one(buffer.baseAddress! + offset, Int32(count)))
            }
            offset += count
        }
        cachedTokens = tokens
        return shared
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
    /// across tokens; we decode to a String only when complete.
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
