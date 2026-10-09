import Foundation

// Usage: llmtest <promptFile> <outFile> [modelPath]
// Runs generateCrm exactly like the app: plan -> warm-up -> generate -> add evidence.
// Default model: ../Models/llm/<first .gguf>. Run with DYLD_FRAMEWORK_PATH pointing at the
// macOS llama.framework inside .build/artifacts (see README).
setvbuf(stdout, nil, _IONBF, 0)

// Everything lives in a function so the model is freed before the process exits;
// otherwise Metal's exit-time cleanup aborts.
func run() throws {
    let args = CommandLine.arguments
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
