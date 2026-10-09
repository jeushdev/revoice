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
  private var llmAssetsPresent = false
  private var llmBusy = false

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
      llmAssetsPresent = ReviseModelStore.llmAssetPresent()
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
    case "generateCrm", "cleanLine":
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

  private func handleLlm(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard state == .stopped else { return result(invalidState(call.method)) }
    guard !llmBusy else {
      return result(
        FlutterError(code: "invalid_state", message: "LLM request already running.", details: nil))
    }
    guard llmAssetsPresent else {
      return result(
        FlutterError(code: "model_missing", message: "Bundled LLM not found.", details: nil))
    }
    guard let args = call.arguments as? [String: Any],
      let prompt = args["prompt"] as? String
    else {
      return result(
        FlutterError(code: "inference_failed", message: "Missing prompt.", details: nil))
    }
    let maxTokens = args["maxTokens"] as? Int ?? 512
    llmBusy = true
    DispatchQueue.global(qos: .userInitiated).async {
      // TODO(zairus): load llama.cpp / MLX model lazily, run `prompt` with
      // `maxTokens` (JSON grammar for generateCrm), return the raw text.
      _ = (prompt, maxTokens)
      let output: String? = nil
      DispatchQueue.main.async {
        self.llmBusy = false
        guard let text = output else {
          return result(
            FlutterError(code: "inference_failed", message: "LLM not wired in yet.", details: nil))
        }
        result(call.method == "generateCrm" ? ["json": text] : ["text": text])
      }
    }
  }

  private func invalidState(_ method: String) -> FlutterError {
    FlutterError(
      code: "invalid_state",
      message: "\(method) is not allowed while \(state?.rawValue ?? "uninitialized").",
      details: nil)
  }
}
