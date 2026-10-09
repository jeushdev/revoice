import 'dart:async';
import 'dart:convert';

import 'caption_engine.dart';
import 'engine_events.dart';

enum MockScenario {
  /// Scripted 4-person meeting with names, topics and commitments.
  meeting,

  /// Listening with no speech at all.
  emptySpeech,

  /// Like [meeting], but Sam's CRM card fails twice before a manual retry works.
  crmFailure,
}

/// Replays a scripted conversation through the exact contract events, so the
/// UI can be built on Windows without a phone. Labelled "Demo / Sample data".
class MockCaptionEngine implements CaptionEngine {
  MockCaptionEngine({
    this.scenario = MockScenario.meeting,
    this.wordInterval = const Duration(milliseconds: 140),
    this.turnGap = const Duration(milliseconds: 700),
    this.llmDelay = const Duration(milliseconds: 900),
  });

  final MockScenario scenario;
  final Duration wordInterval;
  final Duration turnGap;
  final Duration llmDelay;

  static const script = <(int, String)>[
    (1, "Hi everyone, I'm Zairus, I lead product at LarpCode."),
    (2, 'Thanks Zairus. My name is Jeush, I handle the Android build.'),
    (1, 'Sam, can you send the demo deck by Friday?'),
    (3, 'Sure, I will send the deck by Friday morning.'),
    (4, "And I'm Jairus. I'll finish the caption screen tonight."),
    (0, 'Sorry, can everyone hear me?'),
    (2, "Let's review the budget and the launch timeline on Monday."),
    (3, 'I can email the timeline to everyone after this.'),
  ];

  final _controller = StreamController<EngineEvent>.broadcast();
  EngineState? _state;
  int _session = 0;
  int _segmentCounter = 0;
  final _clock = Stopwatch();
  Completer<void>? _resumeGate;
  bool _llmBusy = false;
  final _crmAttempts = <String, int>{};

  @override
  Stream<EngineEvent> get events => _controller.stream;

  @override
  Future<InitResult> init() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    _emitState(EngineState.ready);
    return const InitResult(sttReady: true, llmReady: true);
  }

  @override
  Future<void> start({String language = 'en'}) async {
    _require({EngineState.ready, EngineState.stopped}, 'start');
    final session = ++_session;
    _segmentCounter = 0;
    _clock
      ..reset()
      ..start();
    _emitState(EngineState.listening);
    if (scenario != MockScenario.emptySpeech) unawaited(_play(session));
  }

  @override
  Future<void> pause() async {
    _require({EngineState.listening}, 'pause');
    _resumeGate = Completer<void>();
    _emitState(EngineState.paused);
  }

  @override
  Future<void> resume() async {
    _require({EngineState.paused}, 'resume');
    _emitState(EngineState.listening);
    _resumeGate?.complete();
    _resumeGate = null;
  }

  @override
  Future<void> stop() async {
    if (_state == EngineState.stopped) return;
    _require({EngineState.listening, EngineState.paused}, 'stop');
    _session++; // cancels playback; the in-flight line is flushed below
    _flushPending();
    _resumeGate?.complete();
    _resumeGate = null;
    _clock.stop();
    _emitState(EngineState.stopped);
  }

  @override
  Future<String> generateCrm({
    required String prompt,
    int maxTokens = 512,
  }) async {
    final name =
        RegExp(
          r'^Known name: (.+)$',
          multiLine: true,
        ).firstMatch(prompt)?.group(1)?.trim() ??
        '';
    return _llm(() {
      final attempt = _crmAttempts[name] = (_crmAttempts[name] ?? 0) + 1;
      if (scenario == MockScenario.crmFailure &&
          name == 'Sam' &&
          attempt <= 2) {
        return 'Sure! Here is the card: {"name": "Sam", oops';
      }
      final card = _cannedCards[name] ?? _emptyCard(name);
      return jsonEncode(card);
    });
  }

  /// Demo mode has no model for the generic LLM call; callers treat model_missing as "skip".
  @override
  Future<String> generate({
    required String prompt,
    int maxTokens = 512,
    String? system,
    Object? jsonGrammar,
    String? requestId,
  }) async => throw const EngineException(
    EngineErrorCode.modelMissing,
    'Demo mode has no on-device model for this step.',
  );

  @override
  Future<String> cleanLine({
    required String text,
    required String prompt,
    int maxTokens = 512,
  }) {
    return _llm(() {
      final cleaned = text
          .replaceAll(RegExp(r'\b(um|uh)\b[,]?\s*', caseSensitive: false), '')
          .trim();
      if (cleaned.isEmpty) return text;
      return cleaned[0].toUpperCase() + cleaned.substring(1);
    });
  }

  @override
  Future<void> dispose() async {
    _session++;
    await _controller.close();
  }

  // --- playback ---------------------------------------------------------

  String? _pendingId;
  (int, String)? _pendingLine;
  int _pendingStart = 0;

  Future<void> _play(int session) async {
    for (final line in script) {
      if (!await _wait(turnGap, session)) return;
      final (speaker, text) = line;
      final id = 's-${(++_segmentCounter).toString().padLeft(4, '0')}';
      _pendingId = id;
      _pendingLine = line;
      _pendingStart = _clock.elapsedMilliseconds;
      final words = text.split(' ');
      for (var i = 1; i <= words.length; i++) {
        if (!await _wait(wordInterval, session)) return;
        if (_pendingId != id) break; // flushed as final by a pause
        _emitCaption(id, words.take(i).join(' '), speaker, false);
      }
      if (session != _session) return;
      if (_pendingId == id) _emitCaption(id, text, speaker, true);
      _pendingId = null;
      _pendingLine = null;
    }
  }

  /// Waits [d], holding while paused. Returns false if the session ended.
  Future<bool> _wait(Duration d, int session) async {
    await Future<void>.delayed(d);
    while (_resumeGate != null && session == _session) {
      // Pause flushes pending speech as final, then holds.
      _flushPending();
      await _resumeGate!.future;
    }
    return session == _session;
  }

  void _flushPending() {
    final id = _pendingId;
    final line = _pendingLine;
    if (id == null || line == null) return;
    _emitCaption(id, line.$2, line.$1, true);
    _pendingId = null;
    _pendingLine = null;
  }

  void _emitCaption(String id, String text, int speaker, bool isFinal) {
    final now = _clock.elapsedMilliseconds;
    _add(
      CaptionEvent(
        segmentId: id,
        text: text,
        speakerId: speaker,
        isFinal: isFinal,
        tStartMs: _pendingStart,
        tEndMs: now < _pendingStart ? _pendingStart : now,
      ),
    );
  }

  // --- helpers ----------------------------------------------------------

  Future<String> _llm(String Function() produce) async {
    _require({EngineState.stopped}, 'LLM request');
    if (_llmBusy) {
      throw const EngineException(
        EngineErrorCode.invalidState,
        'LLM request already running.',
      );
    }
    _llmBusy = true;
    try {
      await Future<void>.delayed(llmDelay);
      return produce();
    } finally {
      _llmBusy = false;
    }
  }

  void _require(Set<EngineState> allowed, String what) {
    if (!allowed.contains(_state)) {
      throw EngineException(
        EngineErrorCode.invalidState,
        '$what is not allowed while ${_state?.name ?? 'uninitialized'}.',
      );
    }
  }

  void _emitState(EngineState s) {
    _state = s;
    _add(StateEvent(s));
  }

  void _add(EngineEvent e) {
    if (!_controller.isClosed) _controller.add(e);
  }

  static Map<String, Object?> _emptyCard(String name) => {
    'name': name,
    'role': null,
    'organization': null,
    'contact_mentioned': null,
    'topics': <String>[],
    'commitments': <Object>[],
    'follow_up': null,
    'notes': null,
    'source_segments': <String, Object>{},
  };

  static final Map<String, Map<String, Object?>> _cannedCards = {
    'Zairus': {
      ..._emptyCard('Zairus'),
      'role': 'Product lead',
      'organization': 'LarpCode',
      'topics': ['demo deck'],
      'source_segments': {
        'name': ['s-0001'],
        'role': ['s-0001'],
        'organization': ['s-0001'],
        'topics[0]': ['s-0003'],
      },
    },
    'Jeush': {
      ..._emptyCard('Jeush'),
      'role': 'Android build',
      'topics': ['budget', 'launch timeline'],
      'source_segments': {
        'name': ['s-0002'],
        'role': ['s-0002'],
        'topics[0]': ['s-0007'],
        'topics[1]': ['s-0007'],
      },
    },
    'Sam': {
      ..._emptyCard('Sam'),
      'topics': ['demo deck', 'timeline'],
      'commitments': [
        {'what': 'send the deck', 'due': 'Friday morning'},
        {'what': 'email the timeline to everyone', 'due': null},
      ],
      'source_segments': {
        'topics[0]': ['s-0004'],
        'topics[1]': ['s-0008'],
        'commitments[0].what': ['s-0004'],
        'commitments[0].due': ['s-0004'],
        'commitments[1].what': ['s-0008'],
      },
    },
    'Jairus': {
      ..._emptyCard('Jairus'),
      'topics': ['caption screen'],
      'commitments': [
        {'what': 'finish the caption screen', 'due': 'tonight'},
      ],
      'source_segments': {
        'name': ['s-0005'],
        'topics[0]': ['s-0005'],
        'commitments[0].what': ['s-0005'],
        'commitments[0].due': ['s-0005'],
      },
    },
  };
}
