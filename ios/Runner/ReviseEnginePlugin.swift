import Flutter
import UIKit

/// Native side of the ReVise platform contract (PRD section 7).
///
/// - EventChannel `revise/captions`: native -> Dart, one map per event.
/// - MethodChannel `revise/engine`: Dart -> native commands.
///
/// STT, speaker IDs and the state machine live in `ReviseEngine`
/// (ios-native/Revise, referenced from this project, not copied). This class only
/// translates channel calls and events. The local LLM is still a TODO(zairus).
/// Audio never crosses into Dart.
final class ReviseEnginePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

  enum State: String {
    case ready, listening, paused, stopped, error
  }

  private var eventSink: FlutterEventSink?
  private var state: State?   // mirrors the engine's last state event (main thread only)

  /// Moonshine STT + speaker IDs. Events come from audio threads, so hop to main
  /// before touching `state` or the sink; main-queue order keeps events in order.
  private lazy var engine = ReviseEngine { [weak self] event in
    DispatchQueue.main.async {
      guard let self else { return }
      if event["type"] as? String == "state",
        let raw = event["state"] as? String, let new = State(rawValue: raw)
      {
        self.state = new
      }
      self.eventSink?(event)
    }
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    startMainThreadWatchdog()
    let instance = ReviseEnginePlugin()
    let methods = FlutterMethodChannel(
      name: "revise/engine", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: methods)
    let events = FlutterEventChannel(
      name: "revise/captions", binaryMessenger: registrar.messenger())
    events.setStreamHandler(instance)
  }

  // MARK: - FlutterStreamHandler

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  // MARK: - MethodChannel

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "init":
      run(result) { await self.engine.initialize() }
    case "start":
      let language = (call.arguments as? [String: Any])?["language"] as? String ?? "en"
      run(result) {
        try await self.engine.start(language: language)
        return true
      }
    case "pause":
      run(result) {
        try await self.engine.pause()
        return true
      }
    case "resume":
      run(result) {
        try await self.engine.resume()
        return true
      }
    case "stop":
      run(result) {
        try await self.engine.stop()
        return true
      }
    case "generateCrm", "cleanLine", "generate":
      handleLlm(call, result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Runs async engine work, then answers Flutter on the main thread, mapping
  /// `ReviseError` to the PlatformException codes from PRD section 7.
  private func run(_ result: @escaping FlutterResult, _ work: @escaping () async throws -> Any) {
    Task {
      let reply: Any
      do {
        reply = try await work()
      } catch let error as ReviseError {
        reply = FlutterError(code: error.code.rawValue, message: error.message, details: nil)
      } catch {
        reply = FlutterError(
          code: "capture_failed", message: error.localizedDescription, details: nil)
      }
      await MainActor.run { result(reply) }
    }
  }

  /// On-device LLM calls. All three share one model and run only while stopped:
  ///  - generateCrm {prompt, maxTokens}            -> {json}  (CRM JSON grammar, PRD section 8)
  ///  - cleanLine   {text, prompt, maxTokens}      -> {text}  (free text)
  ///  - generate    {prompt, maxTokens, jsonGrammar?, system?} -> {text}
  ///      jsonGrammar: true = any valid JSON; a String = your own GBNF grammar; absent = free text.
  /// Every reply also carries loadMs / promptTokens / generatedTokens / tokensPerSecond.
  private func handleLlm(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any], var prompt = args["prompt"] as? String else {
      return result(FlutterError(code: "inference_failed", message: "Missing prompt.", details: nil))
    }
    let maxTokens = args["maxTokens"] as? Int ?? 512
    var system = args["system"] as? String
    let grammar: String?
    // CRM: if the "[id] text" transcript lines can be read from the prompt, the model only writes
    // values and we look up the evidence ourselves (faster, more accurate). Otherwise the model
    // writes its own citations. (CrmEvidence.plan makes that choice; the Mac test tool uses it too.)
    var crmPlan: CrmEvidence.Plan?
    switch call.method {
    case "generateCrm":
      let plan = CrmEvidence.plan(forPrompt: prompt)
      crmPlan = plan
      grammar = plan.grammar
      system = system ?? plan.system
    case "cleanLine":
      grammar = nil
      // Dart sends the instruction and the line; make sure the line is in the prompt exactly once.
      if let text = args["text"] as? String, !prompt.contains(text) {
        prompt += "\n\nLine: \(text)"
      }
    default:  // "generate"
      if let custom = args["jsonGrammar"] as? String, !custom.isEmpty {
        grammar = custom
      } else if args["jsonGrammar"] as? Bool == true {
        grammar = ReviseGrammars.anyJson
      } else {
        grammar = nil
      }
    }
    let method = call.method
    let systemText = system
    let plan = crmPlan
    // Optional streaming: pass "requestId" and every new piece of text arrives on the
    // revise/captions channel as {"type":"llm","requestId":..., "delta":"..."}.
    let requestId = args["requestId"] as? String
    let onToken: (@Sendable (String) -> Void)? = requestId.map { id in
      { [weak self] delta in
        DispatchQueue.main.async {
          self?.eventSink?(["type": "llm", "requestId": id, "delta": delta])
        }
      }
    }
    run(result) {
      let out = try await self.engine.generate(
        prompt: prompt, system: systemText, maxTokens: maxTokens, grammar: grammar,
        onToken: onToken)
      var reply: [String: Any] = [
        "loadMs": out.stats.loadMs,
        "promptTokens": out.stats.promptTokens,
        "generatedTokens": out.stats.generatedTokens,
        "tokensPerSecond": out.stats.tokensPerSecond,
        "reusedTokens": out.stats.reusedTokens,
        "promptMs": out.stats.promptMs,
        "generateMs": out.stats.generateMs,
      ]
      switch method {
      case "generateCrm":
        reply["json"] = plan?.finish(out.text) ?? out.text
      default: reply["text"] = out.text.trimmingCharacters(in: .whitespacesAndNewlines)
      }
      return reply
    }
  }

  private func invalidState(_ method: String) -> FlutterError {
    FlutterError(
      code: "invalid_state",
      message: "\(method) is not allowed while \(state?.rawValue ?? "uninitialized").",
      details: nil)
  }

  /// DEBUG only: pings the main thread every 100 ms from a background queue and logs
  /// "REVISE-STALL" when it answers more than 300 ms late, i.e. when the UI is frozen.
  private static func startMainThreadWatchdog() {
    #if DEBUG
    let queue = DispatchQueue(label: "revise.watchdog", qos: .utility)
    let timer = DispatchSource.makeTimerSource(queue: queue)
    var pingSentAt: Date?
    timer.schedule(deadline: .now() + 1, repeating: .milliseconds(100))
    timer.setEventHandler {
      if let sent = pingSentAt {
        let late = Int(Date().timeIntervalSince(sent) * 1000)
        if late > 300 { NSLog("REVISE-STALL main thread unresponsive for %d ms (still blocked)", late) }
        return  // previous ping not answered yet
      }
      pingSentAt = Date()
      DispatchQueue.main.async {
        queue.async {
          if let sent = pingSentAt, Date().timeIntervalSince(sent) > 0.3 {
            NSLog("REVISE-STALL main thread was blocked for %d ms", Int(Date().timeIntervalSince(sent) * 1000))
          }
          pingSentAt = nil
        }
      }
    }
    timer.resume()
    watchdog = timer
    #endif
  }
  private static var watchdog: DispatchSourceTimer?
}
