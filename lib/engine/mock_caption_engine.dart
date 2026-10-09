import 'dart:async';
import 'dart:convert';

import 'caption_engine.dart';
import 'engine_events.dart';

enum MockScenario {
  /// Scripted 4-person meeting with names, topics and commitments.
  meeting,

  /// Listening with no speech at all.
  emptySpeech,

  /// Like [meeting], but the summary fails until the user taps Retry.
  summaryFailure,

  /// The mic drops after five lines (state `error`); earlier lines are kept.
  micInterrupted,

  /// `start` fails with `permission_denied`.
  micDenied,

  /// `init` reports no speech model; `start` fails with `model_missing`.
  modelMissing,
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
  int _summaryAttempts = 0;

  @override
  Stream<EngineEvent> get events => _controller.stream;

  @override
  Future<InitResult> init() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    _emitState(EngineState.ready);
    final stt = scenario != MockScenario.modelMissing;
    return InitResult(sttReady: stt, llmReady: true);
  }

  @override
  Future<void> start({String language = 'en'}) async {
    _require({EngineState.ready, EngineState.stopped}, 'start');
    if (scenario == MockScenario.micDenied) {
      throw const EngineException(
        EngineErrorCode.permissionDenied,
        'Microphone permission denied.',
      );
    }
    if (scenario == MockScenario.modelMissing) {
      throw const EngineException(
        EngineErrorCode.modelMissing,
        'Speech model not found.',
      );
    }
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
    _require({
      EngineState.listening,
      EngineState.paused,
      EngineState.error,
    }, 'stop');
    _session++; // cancels playback; the in-flight line is flushed below
    _flushPending();
    _resumeGate?.complete();
    _resumeGate = null;
    _clock.stop();
    _emitState(EngineState.stopped);
  }

  /// Prompts that start with a `TASK:` line (the summary screen's own prompts).
  Future<String> _generateTask(String prompt) {
    final task = RegExp(
      r'^TASK: (\w+)',
      multiLine: true,
    ).firstMatch(prompt)?.group(1);
    return _llm(
      () => jsonEncode(switch (task) {
        'match_speakers' => _matchSpeakers(prompt),
        'summary' => _summary(prompt),
        'questions' => {'questions': _questions},
        'answer' => _answer(prompt),
        _ => throw const EngineException(
          EngineErrorCode.inferenceFailed,
          'Unknown task.',
        ),
      }),
    );
  }

  // --- canned LLM output for the scripted meeting ---------------------

  static const _speakerNames = {1: 'Zairus', 2: 'Jeush', 3: 'Sam', 4: 'Jairus'};

  Map<String, Object?> _matchSpeakers(String prompt) {
    final names =
        (RegExp(
                  r'^Names: (.*)$',
                  multiLine: true,
                ).firstMatch(prompt)?.group(1) ??
                '')
            .split(',')
            .map((n) => n.trim().toLowerCase())
            .toSet();
    return {
      'speakers': {
        for (final MapEntry(:key, :value) in _speakerNames.entries)
          '$key': names.contains(value.toLowerCase()) ? value : null,
      },
    };
  }

  Map<String, Object?> _summary(String prompt) {
    if (scenario == MockScenario.summaryFailure && ++_summaryAttempts <= 1) {
      // Fails the first run; the user's Retry works.
      throw const EngineException(
        EngineErrorCode.inferenceFailed,
        'The model ran out of memory.',
      );
    }
    // Only mentions what the (possibly short) transcript contains.
    final parts = [
      'A LarpCode team check-in about the ReVise demo.',
      if (prompt.contains('demo deck'))
        'Zairus asked Sam for the demo deck by Friday.',
      if (prompt.contains('caption screen'))
        'Jairus is finishing the caption screen tonight.',
      if (prompt.contains('Monday'))
        'Jeush set a budget and launch timeline review for Monday.',
    ];
    return {'summary': parts.join(' ')};
  }

  static const _questions = [
    'What was it about?',
    'Who took part?',
    'What are the deadlines?',
    'What did Sam agree to do?',
    'What happens on Monday?',
  ];

  Map<String, Object?> _answer(String prompt) {
    final q =
        (RegExp(
                  r'^Question: (.*)$',
                  multiLine: true,
                ).firstMatch(prompt)?.group(1) ??
                '')
            .toLowerCase();
    Map<String, Object?> found(String answer, List<String> sources) => {
      'found': true,
      'answer': answer,
      'sources': sources,
    };
    if (q.contains('deadline')) {
      return found(
        '- Sam: demo deck by Friday morning\n'
        '- Jairus: caption screen tonight\n'
        '- Team: budget and launch timeline review on Monday',
        ['s-0003', 's-0004', 's-0005', 's-0007'],
      );
    }
    if (q.contains('who')) {
      return found(
        '- Zairus, leads product\n'
        '- Jeush, Android build\n'
        '- Sam, demo deck\n'
        '- Jairus, caption screen',
        ['s-0001', 's-0002', 's-0004', 's-0005'],
      );
    }
    if (q.contains('about')) {
      return found(
        'Planning the ReVise demo: who owns the deck, the caption screen and '
        'the launch timeline.',
        ['s-0001', 's-0003', 's-0007'],
      );
    }
    if (q.contains('sam')) {
      return found(
        'Send the demo deck by Friday morning and email the timeline to '
        'everyone after the meeting.',
        ['s-0004', 's-0008'],
      );
    }
    if (q.contains('monday')) {
      return found('The team reviews the budget and the launch timeline.', [
        's-0007',
      ]);
    }
    return {'found': false, 'answer': '', 'sources': <String>[]};
  }

  /// Demo mode answers the three meeting-AI calls (summary, suggested questions, Q&A) with simple
  /// rule-based stand-ins built from the transcript in the prompt, so the UI can be built without
  /// a phone. Anything else still reports model_missing.
  @override
  Future<String> generate({
    required String prompt,
    int maxTokens = 512,
    bool json = true,
    String? system,
    Object? jsonGrammar,
    String? requestId,
  }) async {
    if (RegExp(r'^TASK: \w+', multiLine: true).hasMatch(prompt)) return _generateTask(prompt);
    final grammar = jsonGrammar is String ? jsonGrammar : '';
    final turns = [
      for (final m in RegExp(r'^\[(s-\d+)\] [^:\n]+: (.+)$', multiLine: true).allMatches(prompt))
        (id: m.group(1)!, text: m.group(2)!),
    ];
    if (turns.isEmpty ||
        !(grammar.contains('bullets') || grammar.contains('questions') || grammar.contains('supported'))) {
      throw const EngineException(
        EngineErrorCode.modelMissing,
        'Demo mode has no on-device model for this step.',
      );
    }
    return _llm(() {
      if (grammar.contains('bullets')) {
        final picks = {0, turns.length ~/ 2, turns.length - 1}.map((i) => turns[i]).toList();
        const kinds = ['topic', 'decision', 'action'];
        return jsonEncode({
          'bullets': [
            for (var i = 0; i < picks.length; i++)
              {
                'text': picks[i].text.split(' ').take(10).join(' '),
                'kind': kinds[i % 3],
                if (kinds[i % 3] == 'action') ...{'who': 'Sam', 'due': 'Friday'},
                'sources': [picks[i].id],
              },
          ],
        });
      }
      if (grammar.contains('questions')) {
        return jsonEncode({
          'questions': ['What was agreed?', 'Who has an action item?', 'Is a deadline mentioned?'],
        });
      }
      final question = RegExp(r'^Question: (.+)$', multiLine: true).firstMatch(prompt)?.group(1) ?? '';
      Set<String> words(String t) => {
        for (final w in RegExp(r'[a-z]{4,}').allMatches(t.toLowerCase())) w.group(0)!,
      };
      final asked = words(question);
      ({String id, String text})? best;
      var bestScore = 0;
      for (final t in turns) {
        final score = words(t.text).intersection(asked).length;
        if (score > bestScore) {
          best = t;
          bestScore = score;
        }
      }
      return jsonEncode(
        best == null
            ? {'answer': 'Not mentioned in the conversation.', 'supported': false, 'sources': <String>[]}
            : {'answer': best.text, 'supported': true, 'sources': [best.id]},
      );
    });
  }

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
      if (scenario == MockScenario.micInterrupted && _segmentCounter == 5) {
        _clock.stop();
        _emitState(EngineState.error, 'Microphone interrupted.');
        return;
      }
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

  void _emitState(EngineState s, [String? message]) {
    _state = s;
    _add(StateEvent(s, message));
  }

  void _add(EngineEvent e) {
    if (!_controller.isClosed) _controller.add(e);
  }
}
