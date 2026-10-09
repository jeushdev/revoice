import Flutter
import UIKit

/// Glue between Flutter and `ReviseEngine`: registers the two channels from PRD section 7.
///   - MethodChannel "revise/engine"   (Dart -> Swift calls)
///   - EventChannel  "revise/captions" (Swift -> Dart caption + state events)
/// Keep this file thin; all logic lives in ReviseEngine.
final class ReviseChannels: NSObject, FlutterStreamHandler {
    static let shared = ReviseChannels()

    /// Set while Dart is listening to "revise/captions". Only touched on the main thread.
    private var sink: FlutterEventSink?

    private lazy var engine = ReviseEngine { [weak self] event in
        // Flutter wants events on the main thread; Moonshine calls us from its audio thread.
        DispatchQueue.main.async { self?.sink?(event) }
    }

    /// Call once at app launch (see ios-native/README.md for the AppDelegate lines).
    func register(with messenger: FlutterBinaryMessenger) {
        let methods = FlutterMethodChannel(name: "revise/engine", binaryMessenger: messenger)
        methods.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result)
        }
        FlutterEventChannel(name: "revise/captions", binaryMessenger: messenger)
            .setStreamHandler(self)
    }

    // MARK: - MethodChannel

    private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
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
        case "generateCrm", "cleanLine":
            // The on-device LLM is not integrated yet (PRD: separate llama.cpp / MLX spike).
            result(FlutterError(code: "model_missing", message: "On-device LLM not integrated yet", details: nil))
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// Runs async engine work, then answers Flutter on the main thread, converting
    /// `ReviseError` into the PlatformException codes the PRD defines.
    private func run(_ result: @escaping FlutterResult, _ work: @escaping () async throws -> Any) {
        Task {
            let reply: Any
            do {
                reply = try await work()
            } catch let error as ReviseError {
                reply = FlutterError(code: error.code.rawValue, message: error.message, details: nil)
            } catch {
                reply = FlutterError(code: "capture_failed", message: error.localizedDescription, details: nil)
            }
            await MainActor.run { result(reply) }
        }
    }

    // MARK: - FlutterStreamHandler (EventChannel)

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        sink = nil
        return nil
    }
}
