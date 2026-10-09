import 'engine_events.dart';

/// What the UI talks to. [PlatformCaptionEngine] calls the native Swift or
/// Kotlin backend; [MockCaptionEngine] replays a scripted conversation so the
/// UI can be built without a phone.
abstract class CaptionEngine {
  /// Subscribe before calling [init].
  Stream<EngineEvent> get events;

  Future<InitResult> init();
  Future<void> start({String language = 'en'});
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();

  /// Returns raw model output. Dart parses and validates it.
  Future<String> generateCrm({required String prompt, int maxTokens = 512});

  /// Optional F2b stretch. Returns a candidate; Dart applies the safety checks.
  Future<String> cleanLine({
    required String text,
    required String prompt,
    int maxTokens = 512,
  });

  Future<void> dispose();
}
