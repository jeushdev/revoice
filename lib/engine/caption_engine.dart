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

  /// Generic on-device LLM call (iOS: llama.cpp). Returns the generated text.
  /// [jsonGrammar]: `true` = any valid JSON, a String = your own GBNF grammar, null = free text.
  /// [requestId]: when set, every new piece of text is also sent on [events] as an
  /// [LlmTokenEvent] with this id while the model is writing (iOS only).
  /// Throws [EngineException] (model_missing when no LLM is available).
  Future<String> generate({
    required String prompt,
    int maxTokens = 512,
    String? system,
    Object? jsonGrammar,
    String? requestId,
  });

  Future<void> dispose();
}
