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

  /// Optional F2b stretch. Returns a candidate; Dart applies the safety checks.
  Future<String> cleanLine({
    required String text,
    required String prompt,
    int maxTokens = 512,
  });

  /// Runs one on-device LLM prompt (iOS: llama.cpp) and returns the raw output. Dart builds the
  /// prompts and parses and validates the output.
  /// - [json]: `true` (default) asks for any valid JSON (grammar-constrained); `false` is free text.
  /// - [jsonGrammar]: your own GBNF grammar (a String) or `true`; overrides [json].
  /// - [system]: system prompt. Keep it identical between calls so the prompt cache is reused.
  /// - [requestId]: when set, every new piece of text is also sent on [events] as an
  ///   [LlmTokenEvent] with this id while the model is writing (iOS only).
  /// Throws [EngineException] (model_missing when no LLM is available).
  Future<String> generate({
    required String prompt,
    int maxTokens = 512,
    bool json = true,
    String? system,
    Object? jsonGrammar,
    String? requestId,
  });

  Future<void> dispose();
}
