/// Events and errors of the ReVise platform contract (PRD section 7).
library;

enum EngineState { ready, listening, paused, stopped, error }

sealed class EngineEvent {
  const EngineEvent();

  /// Parses one event map sent on `revise/captions`. Returns null for unknown
  /// or malformed events so a bad native message never crashes the UI.
  static EngineEvent? fromMap(Object? raw) {
    if (raw is! Map) return null;
    switch (raw['type']) {
      case 'caption':
        final id = raw['segmentId'];
        final text = raw['text'];
        if (id is! String || text is! String) return null;
        final start = (raw['tStartMs'] as num?)?.toInt() ?? 0;
        final end = (raw['tEndMs'] as num?)?.toInt() ?? start;
        return CaptionEvent(
          segmentId: id,
          text: text,
          speakerId: (raw['speakerId'] as num?)?.toInt() ?? 0,
          isFinal: raw['isFinal'] == true,
          tStartMs: start,
          tEndMs: end < start ? start : end,
        );
      case 'state':
        final state = EngineState.values
            .where((s) => s.name == raw['state'])
            .firstOrNull;
        if (state == null) return null;
        return StateEvent(state, raw['message'] as String?);
    }
    return null;
  }
}

class CaptionEvent extends EngineEvent {
  const CaptionEvent({
    required this.segmentId,
    required this.text,
    required this.speakerId,
    required this.isFinal,
    required this.tStartMs,
    required this.tEndMs,
  });

  final String segmentId;
  final String text;

  /// Stable within a session, starting at 1. 0 means unknown.
  final int speakerId;
  final bool isFinal;
  final int tStartMs;
  final int tEndMs;

  Map<String, Object?> toMap() => {
    'type': 'caption',
    'segmentId': segmentId,
    'text': text,
    'speakerId': speakerId,
    'isFinal': isFinal,
    'tStartMs': tStartMs,
    'tEndMs': tEndMs,
  };
}

class StateEvent extends EngineEvent {
  const StateEvent(this.state, [this.message]);

  final EngineState state;
  final String? message;
}

/// Error codes native code reports through PlatformException.
enum EngineErrorCode {
  permissionDenied('permission_denied'),
  modelMissing('model_missing'),
  captureFailed('capture_failed'),
  inferenceFailed('inference_failed'),
  invalidState('invalid_state'),
  unknown('unknown');

  const EngineErrorCode(this.wire);
  final String wire;

  static EngineErrorCode fromWire(String code) =>
      values.where((c) => c.wire == code).firstOrNull ?? unknown;
}

class EngineException implements Exception {
  const EngineException(this.code, [this.message]);

  final EngineErrorCode code;
  final String? message;

  @override
  String toString() => 'EngineException(${code.wire}: $message)';
}

class InitResult {
  const InitResult({required this.sttReady, required this.llmReady});

  final bool sttReady;

  /// LLM assets are present; inference is not verified yet.
  final bool llmReady;
}
