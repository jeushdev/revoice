import Flutter
import UIKit

/// Native side of the ReVise platform contract (PRD section 7).
///
/// - EventChannel `revise/captions`: native -> Dart, one map per event.
/// - MethodChannel `revise/engine`: Dart -> native commands.
///
/// The channel plumbing and state machine are done. Zairus wires Moonshine
/// (STT + diarization) and the local LLM into the `TODO(zairus)` spots.
/// Audio never crosses into Dart.
final class ReviseEnginePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

  enum State: String {
    case ready, listening, paused, stopped, error
  }

  private var eventSink: FlutterEventSink?
  private var state: State?
  private var sttReady = false
  private var llmAssetsPresent = false
  private var llmBusy = false

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
      handleInit(result)
    case "start":
      handleStart(result)
    case "pause":
      guard state == .listening else { return result(invalidState("pause")) }
      // TODO(zairus): stop mic capture, flush pending speech as final, then:
      emitState(.paused)
      result(true)
    case "resume":
      guard state == .paused else { return result(invalidState("resume")) }
      // TODO(zairus): restart mic capture; keep the session and speaker mapping.
      emitState(.listening)
      result(true)
    case "stop":
      handleStop(result)
    case "generateCrm", "cleanLine":
      handleLlm(call, result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func handleInit(_ result: @escaping FlutterResult) {
    // TODO(zairus): load bundled Moonshine STT + diarization assets from the
    // app bundle with local-file loaders (no auto-download). Set sttReady.
    sttReady = false
    // TODO(zairus): check the bundled LLM file exists. Do NOT load it here.
    llmAssetsPresent = false
    emitState(.ready)
    result(["sttReady": sttReady, "llmReady": llmAssetsPresent])
  }

  private func handleStart(_ result: @escaping FlutterResult) {
    guard state == .ready || state == .stopped else { return result(invalidState("start")) }
    guard sttReady else {
      return result(
        FlutterError(
          code: "model_missing", message: "Moonshine is not wired in yet.", details: nil))
    }
    // TODO(zairus): free the LLM if loaded, reload STT if it was released,
    // request mic permission (permission_denied on refusal), start capture,
    // and call emitCaption(...) for every partial and final segment.
    emitState(.listening)
    result(true)
  }

  private func handleStop(_ result: @escaping FlutterResult) {
    if state == .stopped { return result(true) }  // repeated Stop is a no-op
    guard state == .listening || state == .paused else { return result(invalidState("stop")) }
    // TODO(zairus): stop capture, flush every pending segment as final
    // (emitCaption with isFinal=true), then release STT + diarization.
    emitState(.stopped)
    result(true)
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

  // MARK: - Events

  /// Call for every partial and final segment. Always on the main thread.
  func emitCaption(
    segmentId: String, text: String, speakerId: Int, isFinal: Bool, tStartMs: Int, tEndMs: Int
  ) {
    send([
      "type": "caption", "segmentId": segmentId, "text": text, "speakerId": speakerId,
      "isFinal": isFinal, "tStartMs": tStartMs, "tEndMs": tEndMs,
    ])
  }

  /// Use for async failures (mic interrupted, capture failed).
  func emitError(_ message: String) {
    state = .error
    send(["type": "state", "state": State.error.rawValue, "message": message])
  }

  private func emitState(_ newState: State) {
    state = newState
    send(["type": "state", "state": newState.rawValue, "message": NSNull()])
  }

  private func send(_ event: [String: Any]) {
    let deliver = { self.eventSink?(event) }
    Thread.isMainThread ? deliver() : DispatchQueue.main.async(execute: deliver)
  }

  private func invalidState(_ method: String) -> FlutterError {
    FlutterError(
      code: "invalid_state",
      message: "\(method) is not allowed while \(state?.rawValue ?? "uninitialized").",
      details: nil)
  }
}
