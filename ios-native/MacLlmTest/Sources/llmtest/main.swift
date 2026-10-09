import Foundation

// Usage: llmtest <promptFile> <outFile> [modelPath]
//        llmtest generate <promptFile> <outFile> [systemFile] [grammarFile]   (the generic `generate` method)
// Runs generateCrm exactly like the app: plan -> warm-up -> generate -> add evidence.
// Default model: ../Models/llm/<first .gguf>. Run with DYLD_FRAMEWORK_PATH pointing at the
// macOS llama.framework inside .build/artifacts (see README).
setvbuf(stdout, nil, _IONBF, 0)

// Everything lives in a function so the model is freed before the process exits;
// otherwise Metal's exit-time cleanup aborts.
func run() throws {
    var args = CommandLine.arguments
    if args.count >= 4, args[1] == "generate" {
        // Generic mode: free system prompt and optional GBNF grammar, like the app's `generate` method.
        let prompt = try String(contentsOfFile: args[2], encoding: .utf8)
        let system = args.count > 4 ? try String(contentsOfFile: args[4], encoding: .utf8) : nil
        let grammar = args.count > 5 ? try String(contentsOfFile: args[5], encoding: .utf8) : nil
        // LLM_PATH=/path/to/model.gguf overrides the default (first .gguf in ../Models/llm).
        let modelPath: String
        if let override = ProcessInfo.processInfo.environment["LLM_PATH"] {
            modelPath = override
        } else {
            let dir = "../Models/llm"
            let file = try FileManager.default.contentsOfDirectory(atPath: dir).sorted().first { $0.hasSuffix(".gguf") }!
            modelPath = "\(dir)/\(file)"
        }
        let runner = try LlamaRunner(modelPath: modelPath)
        let out = try runner.generate(prompt: prompt, system: system, maxTokens: 512, grammar: grammar)
        try out.text.write(toFile: args[3], atomically: true, encoding: .utf8)
        print("wrote \(out.stats.generatedTokens) tokens in \(out.stats.generateMs) ms; prompt \(out.stats.promptTokens) tokens")
        return
    }
    if args.count >= 3, args[1] == "steps" {
        // Several generate calls on ONE loaded model, in order, like the app does after Stop.
        // Manifest JSON: {"system": "path", "steps": [{"name","prompt","grammar","out","maxTokens"}]}
        // Prints per step: wall time, prompt tokens split into cached / new, and generation speed,
        // so the prompt-cache effect (same transcript, different task) is visible.
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[2]))) as! [String: Any]
        let system = (manifest["system"] as? String).map { try! String(contentsOfFile: $0, encoding: .utf8) }
        let modelPath: String
        if let override = ProcessInfo.processInfo.environment["LLM_PATH"] {
            modelPath = override
        } else {
            let dir = "../Models/llm"
            let file = try FileManager.default.contentsOfDirectory(atPath: dir).sorted().first { $0.hasSuffix(".gguf") }!
            modelPath = "\(dir)/\(file)"
        }
        let runner = try LlamaRunner(modelPath: modelPath)
        print("model load \(runner.loadMs) ms")
        for step in manifest["steps"] as! [[String: Any]] {
            let prompt = try String(contentsOfFile: step["prompt"] as! String, encoding: .utf8)
            let grammar = (step["grammar"] as? String).map { try! String(contentsOfFile: $0, encoding: .utf8) }
            runner.injectDecodeFailures = step["injectFailures"] as? Int ?? 0
            let started = DispatchTime.now()
            let out = try runner.generate(
                prompt: prompt, system: (step["system"] as? String).map { try! String(contentsOfFile: $0, encoding: .utf8) } ?? system,
                maxTokens: step["maxTokens"] as? Int ?? 512, grammar: grammar)
            let wallMs = Int(Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000)
            try out.text.write(toFile: step["out"] as! String, atomically: true, encoding: .utf8)
            let s = out.stats
            print("STEP \(step["name"] as! String): wall \(wallMs) ms | prompt \(s.promptTokens) tok (\(s.reusedTokens) cached, \(s.newPromptTokens) new in \(s.promptMs) ms) | wrote \(s.generatedTokens) tok in \(s.generateMs) ms (\(String(format: "%.1f", s.tokensPerSecond)) tok/s)")
        }
        return
    }
    guard args.count >= 3 else { print("usage: llmtest <promptFile> <outFile> [modelPath]"); exit(2) }
    let prompt = try String(contentsOfFile: args[1], encoding: .utf8)
    let modelPath: String
    if args.count > 3 {
        modelPath = args[3]
    } else {
        let dir = "../Models/llm"
        guard let file = try FileManager.default.contentsOfDirectory(atPath: dir).sorted().first(where: { $0.hasSuffix(".gguf") })
        else { print("no .gguf in \(dir)"); exit(2) }
        modelPath = "\(dir)/\(file)"
    }
    let runner = try LlamaRunner(modelPath: modelPath)
    let plan = CrmEvidence.plan(forPrompt: prompt)
    try runner.warmup(system: ReviseGrammars.crmValuesOnlySystem)
    let out = try runner.generate(prompt: prompt, system: plan.system, maxTokens: 512, grammar: plan.grammar)
    try plan.finish(out.text).write(toFile: args[2], atomically: true, encoding: .utf8)
    print("wrote \(out.stats.generatedTokens) tokens; evidence lines parsed: \(plan.lines.count)")
}
try run()
