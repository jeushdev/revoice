import 'dart:async';

import 'package:flutter/foundation.dart';

import '../engine/caption_engine.dart';
import '../engine/engine_events.dart';
import '../engine/platform_caption_engine.dart';
import 'name_rules.dart';
import 'speaker_suggestions.dart';

class Segment {
  Segment({
    required this.id,
    required this.text,
    required this.speakerId,
    required this.isFinal,
    required this.tStartMs,
    required this.tEndMs,
  });

  final String id;

  /// Original words from STT. Never rewritten (renames live in speakerNames).
  String text;
  int speakerId;
  bool isFinal;
  int tStartMs;
  int tEndMs;

  /// Speaker chosen by the user (Switch speaker button / tapping the line). Wins over everything.
  int? manualSpeakerId;

  /// Speaker suggested by the post-Stop on-device model. The original [speakerId] is kept.
  int? suggestedSpeakerId;
}

/// auto: heard live (name rules). suggested: matched by the LLM after Stop
/// from the names entered before recording. manual: typed by the user.
enum NameSource { auto, suggested, manual }

class SpeakerName {
  const SpeakerName(this.name, this.source);
  final String name;
  final NameSource source;
}

/// Holds one recording session: segments, speaker names, engine state.
/// Audio never reaches Dart; only text events do.
class SessionController extends ChangeNotifier {
  SessionController(this.engine);

  final CaptionEngine engine;

  EngineState? state;
  String? errorMessage;
  InitResult? initResult;
  bool interrupted = false;

  /// Wall-clock start of the session, for the Library.
  DateTime? startedAt;

  /// Session time when the mic dropped (state `error`), for the banner.
  int? interruptedAtMs;
  final Stopwatch _clock = Stopwatch();

  /// Listening time so far (pauses excluded).
  Duration get elapsed => _clock.elapsed;

  final Map<String, Segment> _segments = {};
  final Map<int, SpeakerName> speakerNames = {};

  /// Names entered before recording (optional). Context for the LLM only.
  List<String> expectedNames = const [];
  ({String name, int fromSpeaker})? _pendingCall;
  StreamSubscription<EngineEvent>? _sub;
  Completer<void>? _stoppedSeen;

  /// Finalized lines in timestamp order.
  List<Segment> get finals {
    final list = _segments.values.where((s) => s.isFinal).toList()
      ..sort((a, b) => a.tStartMs.compareTo(b.tStartMs));
    return list;
  }

  /// In-progress (grey) lines, not yet confirmed.
  List<Segment> get partials =>
      _segments.values.where((s) => !s.isFinal).toList()
        ..sort((a, b) => a.tStartMs.compareTo(b.tStartMs));

  /// Which speaker a line is shown and counted under: the user's choice, else the on-device
  /// model's suggestion (if suggestions are on), else what Moonshine heard. [Segment.speakerId]
  /// itself is never overwritten.
  int speakerOf(Segment s) =>
      s.manualSpeakerId ?? (useSuggestions ? s.suggestedSpeakerId : null) ?? s.speakerId;

  /// Whether post-Stop speaker suggestions are shown. OFF by default: they are a rough guess
  /// offered only when the audio gave no speakers at all; the original labels are always kept.
  bool useSuggestions = false;

  /// True when Stop found the voices were not separated and suggested labels from turn-taking
  /// and names (see speaker_suggestions.dart).
  bool get hasSuggestions => _suggestionsApplied;
  bool _suggestionsApplied = false;
  Map<int, SpeakerName> _namesBeforeSuggestions = {};
  Map<int, SpeakerName> _namesSuggested = {};

  /// Runs at Stop, before any CRM card is made. Original [Segment.speakerId] values are untouched.
  void _applySuggestions() {
    final result = suggestSpeakers([
      for (final s in finals) SuggestionLine(s.id, s.text, speakerOf(s)),
    ]);
    if (result == null) return;
    for (final s in finals) {
      s.suggestedSpeakerId = result.speakers[s.id];
    }
    _namesBeforeSuggestions = Map.of(speakerNames);
    _namesSuggested = {
      for (final e in speakerNames.entries)
        if (e.value.source == NameSource.manual) e.key: e.value, // the user's own names always stay
    };
    result.names.forEach((id, name) {
      _namesSuggested.putIfAbsent(id, () => SpeakerName(name, NameSource.auto));
    });
    // Offered, not applied: labels and names change only when the user turns the switch on.
    useSuggestions = false;
    _suggestionsApplied = true;
  }

  /// Switch between the suggested labels/names and the original ones.
  void setUseSuggestions(bool on) {
    if (!_suggestionsApplied) return;
    useSuggestions = on;
    final manual = {
      for (final e in speakerNames.entries)
        if (e.value.source == NameSource.manual) e.key: e.value,
    };
    speakerNames
      ..clear()
      ..addAll(on ? _namesSuggested : _namesBeforeSuggestions)
      ..addAll(manual);
    notifyListeners();
  }

  /// Speakers with at least one final line, excluding unknown (0).
  List<int> get knownSpeakers => {
    for (final s in finals)
      if (speakerOf(s) != 0) speakerOf(s),
  }.toList()..sort();

  // --- Manual speaker controls (safety net when diarization can't tell voices apart) ---

  /// While set, every NEW line is labelled with this speaker instead of Moonshine's guess.
  int? liveSpeakerOverride;

  /// The speaker the next line will be labelled with (override, else the last line's speaker).
  int get currentSpeaker {
    if (liveSpeakerOverride != null) return liveSpeakerOverride!;
    final all = [...finals, ...partials];
    for (var i = all.length - 1; i >= 0; i--) {
      if (speakerOf(all[i]) != 0) return speakerOf(all[i]);
    }
    return 1;
  }

  /// "Switch speaker": the next lines belong to the next speaker (1 -> 2 -> ... -> 1).
  /// There are always at least two speakers to switch between.
  void switchSpeaker() {
    final ids = {...knownSpeakers, currentSpeaker, 2};
    final count = ids.reduce((a, b) => a > b ? a : b).clamp(2, 4);
    liveSpeakerOverride = currentSpeaker % count + 1;
    notifyListeners();
  }

  /// Back to Moonshine's own speaker labels for new lines.
  void useAutoSpeaker() {
    liveSpeakerOverride = null;
    notifyListeners();
  }

  /// Tap-a-line on the transcript: put this line under [speakerId] (0 = unknown).
  void setLineSpeaker(String segmentId, int speakerId) {
    final seg = _segments[segmentId];
    if (seg == null) return;
    seg.manualSpeakerId = speakerId;
    notifyListeners();
  }

  String displayName(int speakerId) {
    if (speakerId == 0) return 'Unknown';
    return speakerNames[speakerId]?.name ?? 'Speaker $speakerId';
  }

  Future<void> init() async {
    _sub ??= engine.events.listen(_onEvent);
    try {
      initResult = await engine.init();
    } on EngineException catch (e) {
      _fail(e.message ?? e.code.wire);
    }
    notifyListeners();
  }

  Future<void> start() async {
    _segments.clear();
    speakerNames.clear();
    liveSpeakerOverride = null;
    _suggestionsApplied = false;
    useSuggestions = false;
    _pendingCall = null;
    interrupted = false;
    interruptedAtMs = null;
    errorMessage = null;
    lastErrorCode = null;
    _clock
      ..stop()
      ..reset();
    // Names entered before recording go to the speech model as key terms.
    final e = engine;
    if (e is PlatformCaptionEngine) e.keyterms = expectedNames.toList();
    await _guard(() => engine.start());
    if (lastErrorCode == null) {
      startedAt = DateTime.now();
      _clock.start();
    }
  }

  Future<void> pause() async {
    await _guard(engine.pause);
    _clock.stop();
  }

  Future<void> resume() async {
    await _guard(engine.resume);
    if (state == EngineState.listening) _clock.start();
  }

  /// Resolves after native confirmed `stopped` and pending lines are flushed.
  Future<void> stop() async {
    final seen = _stoppedSeen = Completer<void>();
    await _guard(engine.stop);
    if (state != EngineState.stopped) {
      await seen.future.timeout(const Duration(seconds: 5), onTimeout: () {});
    }
    _clock.stop();
    // Unconfirmed partials are excluded from the transcript and summary.
    _segments.removeWhere((_, s) => !s.isFinal);
    _applySuggestions(); // before CRM cards are generated, so cards use the suggested labels
    notifyListeners();
  }

  /// Test helper: puts a finished line into the session without running an engine.
  @visibleForTesting
  void debugAddFinal(Segment s) => _segments[s.id] = s;

  /// Manual names always win over inferred names.
  void rename(int speakerId, String name) {
    final trimmed = name.trim();
    if (speakerId == 0 || trimmed.isEmpty) return;
    speakerNames[speakerId] = SpeakerName(trimmed, NameSource.manual);
    notifyListeners();
  }

  /// LLM match from [expectedNames]. Never overrides a manual name, and
  /// replaces a live-heard name only when that name was not on the list.
  void suggestName(int speakerId, String name) {
    final current = speakerNames[speakerId];
    if (speakerId == 0 || current?.source == NameSource.manual) return;
    if (current != null &&
        current.source == NameSource.auto &&
        expectedNames.any(
          (n) => n.toLowerCase() == current.name.toLowerCase(),
        )) {
      return;
    }
    speakerNames[speakerId] = SpeakerName(name, NameSource.suggested);
    notifyListeners();
  }

  void _onEvent(EngineEvent event) {
    switch (event) {
      case CaptionEvent():
        _onCaption(event);
      case SpeakerRevisionEvent():
        _onSpeakerRevision(event);
      case LlmTokenEvent():
        return; // LLM streaming belongs to MeetingAiController, not the session
      case StateEvent(:final state, :final message):
        this.state = state;
        if (state == EngineState.error) {
          errorMessage = message;
          interrupted = true;
          interruptedAtMs = _clock.elapsedMilliseconds;
          _clock.stop();
        }
        if (state == EngineState.stopped || state == EngineState.error) {
          _stoppedSeen?.complete();
          _stoppedSeen = null;
        }
    }
    notifyListeners();
  }

  void _onCaption(CaptionEvent e) {
    if (state != EngineState.listening && state != EngineState.paused) {
      return; // late events from a stopped session never leak in
    }
    final existing = _segments[e.segmentId];
    if (existing != null && existing.isFinal) return; // finals never change
    final seg =
        existing ??
        (_segments[e.segmentId] = Segment(
          id: e.segmentId,
          text: e.text,
          speakerId: e.speakerId,
          isFinal: false,
          tStartMs: e.tStartMs,
          tEndMs: e.tEndMs,
        )..manualSpeakerId = liveSpeakerOverride);   // "Switch speaker" is on: this line is forced
    seg
      ..text = e
          .text // partials replace the whole text
      ..speakerId = e.speakerId
      ..tStartMs = e.tStartMs
      ..tEndMs = e.tEndMs
      ..isFinal = e.isFinal;
    if (e.isFinal) _applyNameRules(seg);
  }

  /// Moonshine changed its mind about who spoke a line. The original [Segment.speakerId] is
  /// updated (it is Moonshine's label); anything the user chose (Switch speaker, tapped line)
  /// is untouched because [speakerOf] prefers [Segment.manualSpeakerId].
  void _onSpeakerRevision(SpeakerRevisionEvent e) {
    final seg = _segments[e.segmentId];
    if (seg == null || seg.speakerId == e.speakerId) return;
    final wasUnknown = seg.speakerId == 0;
    seg.speakerId = e.speakerId;
    // A line that was Unknown when it finished never had its name rules applied ("Hi, I'm David"
    // said before the voices were told apart). Now that it has a speaker, apply them once.
    if (wasUnknown && seg.isFinal && seg.manualSpeakerId == null && state == EngineState.listening) {
      _applyNameRules(seg);
    }
  }

  void _applyNameRules(Segment seg) {
    final speaker = speakerOf(seg);
    final call = _pendingCall;
    if (call != null && speaker != 0 && speaker != call.fromSpeaker) {
      _assignAuto(speaker, call.name);
      _pendingCall = null;
    } else if (call != null && speaker != call.fromSpeaker) {
      _pendingCall = null; // unknown speaker answered: discard
    }
    if (speaker != 0) {
      final self = selfIntroName(seg.text);
      if (self != null) _assignAuto(speaker, self);
      final called = calledName(seg.text);
      if (called != null) _pendingCall = (name: called, fromSpeaker: speaker);
    }
  }

  void _assignAuto(int speakerId, String name) {
    final source = speakerNames[speakerId]?.source;
    if (source == NameSource.manual || source == NameSource.suggested) return;
    speakerNames[speakerId] = SpeakerName(name, NameSource.auto);
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on EngineException catch (e) {
      _fail(e.message ?? e.code.wire, code: e.code);
    }
  }

  EngineErrorCode? lastErrorCode;

  void _fail(String message, {EngineErrorCode? code}) {
    errorMessage = message;
    lastErrorCode = code;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    unawaited(engine.dispose());
    super.dispose();
  }
}
