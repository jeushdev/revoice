import 'dart:async';

/// Serializes LLM requests (one `generate` / `cleanLine` at a time), so the
/// summary, questions and the clean transcript can share one engine safely.
class LlmLock {
  Future<void> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() request) {
    final result = _tail.then((_) => request());
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }
}
