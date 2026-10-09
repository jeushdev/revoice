import 'dart:async';

/// Serializes LLM requests (PRD: one `generateCrm` / `cleanLine` at a time),
/// so CRM and the clean transcript can share one engine safely.
class LlmLock {
  Future<void> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() request) {
    final result = _tail.then((_) => request());
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }
}
