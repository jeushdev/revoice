import 'dart:async';

import 'package:flutter/foundation.dart';

import '../engine/caption_engine.dart';
import '../engine/engine_events.dart';
import '../session/session_controller.dart';
import '../transcript/clean_transcript.dart';
import 'meeting_parsing.dart';

export '../transcript/clean_transcript.dart' show Turn, TurnStatus;
export 'meeting_parsing.dart' show BulletKind, MeetingAnswer, SummaryBullet, notMentioned;

enum MeetingAiState { idle, polishing, summarizing, answering, done, error }

/// One original line as shown in the "Original" view (with the user's edit applied, if any).
class TranscriptLine {
  const TranscriptLine({
    required this.segmentId,
    required this.speakerId,
    required this.speakerName,
    required this.text,
    required this.originalText,
    required this.tStartMs,
  });

  final String segmentId;
  final int speakerId;
  final String speakerName;

  /// Shown text: the user's edit if there is one, else what Moonshine heard.
  final String text;
  final String originalText;
  final int tStartMs;

  bool get edited => text != originalText;
}

/// Everything that runs on the on-device LLM after Stop: the clean transcript, the summary and
/// "Ask the meeting". One LLM request runs at a time; calls made while busy wait their turn.
///
/// Listen to this object (it is a [ChangeNotifier]); read [state], [cleanTurns], [summary],
/// [suggestedQuestions], [answers], [streamingAnswer].
class MeetingAiController extends ChangeNotifier {
  MeetingAiController(this.engine, this.session, {this.autoRun = true, this.llmPolish = false}) {
    session.addListener(_onSessionChanged);
    _tokens = engine.events.listen(_onEngineEvent);
  }

  final CaptionEngine engine;
  final SessionController session;

  /// When true, polishing + summary + suggested questions start by themselves right after Stop.
  final bool autoRun;

  /// Per-turn LLM punctuation. OFF by default: on the phone it took 53 s for 10 turns and the
  /// small model mostly failed the word guard. Off means "Clean" = merge rules + filler removal +
  /// a capital first letter, instantly and with no model call. The LLM code stays behind this flag.
  final bool llmPolish;

  /// Longest transcript sent to the model (~4 chars per token; the model's window is 4096 tokens
  /// and needs room for the question and answer). Older turns are left out of the summary and
  /// Q&A, never out of the transcript view. See [transcriptTruncated].
  static const maxTranscriptChars = 6000;

  MeetingAiState state = MeetingAiState.idle;
  String? errorMessage;

  /// Clean (true) or Original (false) view. The UI toggle just flips this.
  bool showClean = true;

  /// Flip the Clean / Original toggle.
  void setShowClean(bool clean) {
    showClean = clean;
    notifyListeners();
  }

  /// "Polishing transcript... 3 of 7" while [state] is polishing.
  int polishDone = 0;
  int polishTotal = 0;

  MeetingSummary? summary;

  /// True when lines were edited after the summary was made. Call [summarize] again.
  bool summaryStale = false;
  List<String> suggestedQuestions = const [];

  /// Every question asked so far, newest last.
  final List<MeetingAnswer> answers = [];

  /// Text of the answer being written right now (empty when none is running).
  String streamingAnswer = '';

  /// How long each step took, in milliseconds: polish, summary, suggest, answer (the last one).
  final Map<String, int> timingsMs = {};

  /// True when the transcript was too long and the oldest turns were left out of summary and Q&A.
  bool transcriptTruncated = false;

  final Map<String, String> _edits = {};

  /// Punctuated text by merged raw text, so re-merging after an edit only re-polishes what changed.
  final Map<String, ({String text, TurnStatus status})> _polishCache = {};
  List<Turn> _turns = [];
  bool _turnsBuilt = false;
  StreamSubscription<EngineEvent>? _tokens;
  Future<void> _queue = Future.value();
  String? _activeRequest;
  final StringBuffer _streamRaw = StringBuffer();
  int _requestCounter = 0;
  EngineState? _lastSessionState;
  String _speakerSignature = '';

  // --- the two transcript versions ----------------------------------------------------

  /// Original lines in time order, with edits applied. For the "Original" side of the toggle.
  List<TranscriptLine> get originalLines => [
    for (final s in session.finals)
      TranscriptLine(
        segmentId: s.id,
        speakerId: session.speakerOf(s),
        speakerName: session.displayName(session.speakerOf(s)),
        text: _edits[s.id] ?? s.text,
        originalText: s.text,
        tStartMs: s.tStartMs,
      ),
  ];

  /// Merged turns. Until [polish] has run, each turn's text is the merged original words.
  List<Turn> get cleanTurns {
    _ensureTurns();
    return List.unmodifiable(_turns);
  }

  /// The turn that contains [segmentId] (to scroll to it when a source is tapped).
  Turn? turnOfSegment(String segmentId) =>
      cleanTurns.where((t) => t.segmentIds.contains(segmentId)).firstOrNull;

  /// True when some turns are merged but not punctuated yet (after Stop finished, after edits, or
  /// after a speaker was changed). Call [polish] to fix them; it only does the missing ones.
  bool get needsPolish => cleanTurns.any((t) => t.status == TurnStatus.raw);

  bool get busy =>
      state == MeetingAiState.polishing ||
      state == MeetingAiState.summarizing ||
      state == MeetingAiState.answering;

  // --- running everything --------------------------------------------------------------

  /// Polish, then summarize, then suggest questions. Safe to call again (it only redoes what
  /// is missing or stale).
  Future<void> runAll() => _enqueue(MeetingAiState.polishing, () async {
    await _polishAll();
    state = MeetingAiState.summarizing; // straight on, no "done" flash in between
    notifyListeners();
    await _summarizeAll();
  });

  /// Merges fragments (instant) and punctuates each merged turn with the LLM. Turns whose words
  /// the model changed keep their original words. Already polished turns are skipped.
  Future<void> polish() => _enqueue(MeetingAiState.polishing, _polishAll);

  Future<void> _polishAll() async {
    _ensureTurns();
    final watch = Stopwatch()..start();
    final pending = _turns.where((t) => t.status == TurnStatus.raw).toList();
    polishTotal = pending.length;
    polishDone = 0;
    notifyListeners();
    for (final turn in pending) {
      await _polishTurn(turn);
      polishDone++;
      notifyListeners();
    }
    timingsMs['polish'] = watch.elapsedMilliseconds;
  }

  Future<void> _polishTurn(Turn turn) async {
    if (!llmPolish) {
      final ruled = capitalizeFirst(stripFillers(turn.rawText));
      turn.text = ruled.isEmpty ? turn.rawText : ruled;
      turn.status = TurnStatus.polished;
      _polishCache[turn.rawText] = (text: turn.text, status: turn.status);
      return;
    }
    final input = stripFillers(turn.hintedText); // fillers are removed by a rule, not by the model
    if (input.split(' ').length <= 3) {
      turn.text = simplePolish(turn.rawText); // not worth a model call
      turn.status = TurnStatus.polished;
      _polishCache[turn.rawText] = (text: turn.text, status: turn.status);
      return;
    }
    final out = <String>[];
    var allOk = true;
    for (final chunk in chunkForPolish(input)) {
      try {
        final reply = await engine.cleanLine(
          text: chunk,
          prompt: buildPolishPrompt(chunk),
          maxTokens: (chunk.length ~/ 2).clamp(64, 400),
        );
        final candidate = sanitizeModelText(reply);
        if (candidate.isNotEmpty && passesWordGuard(chunk, candidate)) {
          out.add(capitalizeFirst(candidate));
        } else {
          out.add(chunk); // the model changed words: keep the original words
          allOk = false;
        }
      } on EngineException catch (e) {
        if (e.code == EngineErrorCode.modelMissing) rethrow; // no model at all: stop everything
        out.add(chunk);
        allOk = false;
      }
    }
    turn.text = allOk ? out.join(' ') : turn.rawText; // any rejected chunk: keep the original words
    turn.status = allOk ? TurnStatus.polished : TurnStatus.kept;
    _polishCache[turn.rawText] = (text: turn.text, status: turn.status);
  }

  /// 3 to 5 cited bullets, then 3 suggested questions. Uses the clean (or merged) text.
  Future<void> summarize() => _enqueue(MeetingAiState.summarizing, _summarizeAll);

  Future<void> _summarizeAll() async {
    _ensureTurns();
    final input = _modelInput();
    if (input.ids.isEmpty) return;
    final watch = Stopwatch()..start();
    final bullets = await _askModel(
      task: summaryTask(),
      grammar: summaryGrammar(input.ids),
      maxTokens: 450,
      parse: (raw) => parseSummary(raw, input.ids, turnText: input.turnText, knownText: _knownText(input)),
    );
    summary = MeetingSummary(bullets);
    summaryStale = false;
    timingsMs['summary'] = watch.elapsedMilliseconds;
    notifyListeners();

    watch.reset();
    try {
      suggestedQuestions = await _askModel(
        task: suggestTask(),
        grammar: questionsGrammar,
        maxTokens: 160,
        parse: parseQuestions,
      );
    } on FormatException {
      suggestedQuestions = const []; // suggestions are optional
    }
    timingsMs['suggest'] = watch.elapsedMilliseconds;
  }

  /// Answers [question] from the transcript only. Returns the answer (also added to [answers]).
  /// While it runs, [streamingAnswer] fills in (iOS).
  Future<MeetingAnswer> ask(String question) async {
    final q = question.trim();
    // Stays "not mentioned" if the model call fails; [state] and [errorMessage] then say why.
    var result = MeetingAnswer(
      question: q,
      answer: notMentioned,
      sources: const [],
      supported: false,
    );
    await _enqueue(MeetingAiState.answering, () async {
      _ensureTurns();
      final input = _modelInput();
      if (q.isEmpty || input.ids.isEmpty) return;
      final watch = Stopwatch()..start();
      result = await _askModel(
        task: questionTask(q),
        grammar: answerGrammar(input.ids),
        maxTokens: 220,
        stream: true,
        parse: (raw) => parseAnswer(q, raw, input.ids, turnText: input.turnText, knownText: _knownText(input)),
      );
      timingsMs['answer'] = watch.elapsedMilliseconds;
      answers.add(result);
    });
    return result;
  }

  // --- editing (stretch) ---------------------------------------------------------------

  /// Replaces the words of one line. The original is kept ([TranscriptLine.originalText]).
  /// Returns false if the line does not exist or [newText] is empty.
  bool editLine(String segmentId, String newText) {
    final seg = session.finals.where((s) => s.id == segmentId).firstOrNull;
    final text = newText.trim();
    if (seg == null || text.isEmpty) return false;
    if (text == seg.text) {
      _edits.remove(segmentId);
    } else {
      _edits[segmentId] = text;
    }
    _textsChanged();
    return true;
  }

  /// Puts one edited line back to what was heard.
  void revertLine(String segmentId) {
    if (_edits.remove(segmentId) != null) _textsChanged();
  }

  bool isEdited(String segmentId) => _edits.containsKey(segmentId);

  /// Replaces [from] with [to] in every line (case-insensitive, whole words when [from] is a
  /// word). Returns how many lines changed.
  int replaceAll(String from, String to) {
    final needle = from.trim();
    if (needle.isEmpty) return 0;
    final startsWord = RegExp(r'^\w').hasMatch(needle);
    final endsWord = RegExp(r'\w$').hasMatch(needle);
    final pattern = RegExp(
      '${startsWord ? r'\b' : ''}${RegExp.escape(needle)}${endsWord ? r'\b' : ''}',
      caseSensitive: false,
    );
    var changed = 0;
    for (final s in session.finals) {
      final current = _edits[s.id] ?? s.text;
      if (!pattern.hasMatch(current)) continue;
      final updated = current.replaceAll(pattern, to).trim();
      if (updated.isEmpty) continue;
      if (updated == s.text) {
        _edits.remove(s.id);
      } else {
        _edits[s.id] = updated;
      }
      changed++;
    }
    if (changed > 0) _textsChanged();
    return changed;
  }

  /// After an edit the turns are re-merged from the edited text. Turns that did not change keep
  /// their punctuation; changed ones show merged words until [polish] runs again. The summary is
  /// marked stale; questions asked from now on already see the edited text.
  void _textsChanged() {
    _turnsBuilt = false;
    if (summary != null) summaryStale = true;
    notifyListeners();
  }

  // --- internals -----------------------------------------------------------------------

  void _ensureTurns() {
    if (_turnsBuilt) return;
    final lines = [
      for (final s in session.finals)
        MergeLine(
          id: s.id,
          speakerId: session.speakerOf(s),
          text: _edits[s.id] ?? s.text,
          tStartMs: s.tStartMs,
          tEndMs: s.tEndMs,
        ),
    ];
    _speakerSignature = _currentSpeakerSignature();
    _turns = mergeFragments(lines);
    for (final turn in _turns) {
      final cached = _polishCache[turn.rawText];
      if (cached != null) {
        turn
          ..text = cached.text
          ..status = cached.status;
      }
    }
    _turnsBuilt = true;
  }

  /// The transcript text sent to the model and the segment IDs it may cite.
  ({String text, Set<String> ids, Map<String, String> turnText}) _modelInput() {
    final lines = <String>[];
    final ids = <String>{};
    final texts = <String, String>{};
    var chars = 0;
    transcriptTruncated = false;
    for (final turn in _turns.reversed) {
      final line = '[${turn.id}] ${session.displayName(turn.speakerId)}: ${turn.text}';
      if (chars + line.length > maxTranscriptChars && lines.isNotEmpty) {
        transcriptTruncated = true;
        break;
      }
      chars += line.length + 1;
      lines.add(line);
      ids.add(turn.id);
      texts[turn.id] = turn.text;
    }
    // Time order, so evidence ties go to the earlier turn.
    final ordered = {for (final id in texts.keys.toList().reversed) id: texts[id]!};
    return (text: lines.reversed.join('\n'), ids: ids, turnText: ordered);
  }

  /// Everything a claim may name: the transcript words and the speaker names.
  String _knownText(({String text, Set<String> ids, Map<String, String> turnText}) input) =>
      '${input.text} ${session.speakerNames.values.map((n) => n.name).join(' ')}';

  /// One grammar-constrained call; retries once when the output does not parse.
  Future<T> _askModel<T>({
    required String task,
    required String grammar,
    required int maxTokens,
    required T Function(String raw) parse,
    bool stream = false,
  }) async {
    final input = _modelInput();
    // Transcript first, task last: the prompt cache keeps the transcript between requests.
    final prompt = transcriptBlock(input.text) + task;
    for (var attempt = 1;; attempt++) {
      final requestId = stream ? 'ask-${++_requestCounter}' : null;
      _activeRequest = requestId;
      _streamRaw.clear();
      streamingAnswer = '';
      try {
        final raw = await engine.generate(
          prompt: prompt,
          system: meetingSystem,
          maxTokens: maxTokens,
          jsonGrammar: grammar,
          requestId: requestId,
        );
        return parse(raw);
      } on FormatException {
        if (attempt >= 2) rethrow;
      } finally {
        _activeRequest = null;
        streamingAnswer = '';
      }
    }
  }

  void _onEngineEvent(EngineEvent event) {
    if (event is! LlmTokenEvent || event.requestId != _activeRequest) return;
    _streamRaw.write(event.delta);
    final text = partialAnswer(_streamRaw.toString());
    if (text != streamingAnswer) {
      streamingAnswer = text;
      notifyListeners();
    }
  }

  /// Runs [work] after earlier LLM jobs finish, with [running] as the visible state.
  Future<void> _enqueue(MeetingAiState running, Future<void> Function() work) {
    final job = _queue.then((_) async {
      state = running;
      errorMessage = null;
      notifyListeners();
      try {
        await work();
        state = MeetingAiState.done;
      } on EngineException catch (e) {
        state = MeetingAiState.error;
        errorMessage = e.message ?? e.code.wire;
      } on FormatException catch (e) {
        state = MeetingAiState.error;
        errorMessage = 'The model gave an unreadable answer (${e.message}). Try again.';
      } catch (e) {
        state = MeetingAiState.error; // never leave the queue stuck
        errorMessage = '$e';
      }
      notifyListeners();
    });
    _queue = job;
    return job;
  }

  void _onSessionChanged() {
    final now = session.state;
    final before = _lastSessionState;
    _lastSessionState = now;
    _checkSpeakersChanged();
    if (now == before) return;
    if (now == EngineState.listening && before != EngineState.paused) reset();
    if (now == EngineState.stopped && before != EngineState.stopped && autoRun) {
      if (session.finals.isNotEmpty) unawaited(runAll());
    }
  }

  String _currentSpeakerSignature() =>
      session.finals.map((s) => '${s.id}:${session.speakerOf(s)}').join(',');

  /// Tap-to-fix or "use suggestions" after Stop changes who said a line, which changes the merge.
  void _checkSpeakersChanged() {
    if (!_turnsBuilt || _currentSpeakerSignature() == _speakerSignature) return;
    _turnsBuilt = false;
    if (summary != null) summaryStale = true;
  }

  /// Forgets everything (a new session started).
  void reset() {
    _edits.clear();
    _polishCache.clear();
    _turns = [];
    _turnsBuilt = false;
    _speakerSignature = '';
    summary = null;
    summaryStale = false;
    suggestedQuestions = const [];
    answers.clear();
    streamingAnswer = '';
    timingsMs.clear();
    transcriptTruncated = false;
    errorMessage = null;
    state = MeetingAiState.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    session.removeListener(_onSessionChanged);
    _tokens?.cancel();
    super.dispose();
  }
}

class MeetingSummary {
  const MeetingSummary(this.bullets);
  final List<SummaryBullet> bullets;
}
