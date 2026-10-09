import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:revise/engine/caption_engine.dart';
import 'package:revise/engine/engine_events.dart';
import 'package:revise/session/session_controller.dart';

/// Engine stub: tests push events by hand.
class _Engine implements CaptionEngine {
  final controller = StreamController<EngineEvent>.broadcast();
  @override
  Stream<EngineEvent> get events => controller.stream;
  @override
  Future<InitResult> init() async => const InitResult(sttReady: true, llmReady: false);
  @override
  Future<void> start({String language = 'en'}) async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> stop() async => controller.add(const StateEvent(EngineState.stopped, null));
  @override
  Future<String> cleanLine({required String text, required String prompt, int maxTokens = 512}) async => text;
  @override
  Future<String> generate({
    required String prompt,
    int maxTokens = 512,
    bool json = true,
    String? system,
    Object? jsonGrammar,
    String? requestId,
  }) async => throw const EngineException(EngineErrorCode.modelMissing, 'no llm');
  @override
  Future<void> dispose() async {}

  void caption(String id, String text, int speaker, {bool isFinal = true}) =>
      controller.add(CaptionEvent(
        segmentId: id,
        text: text,
        speakerId: speaker,
        isFinal: isFinal,
        tStartMs: int.parse(id.substring(2)) * 1000,
        tEndMs: int.parse(id.substring(2)) * 1000 + 800,
      ));
}

void main() {
  late _Engine engine;
  late SessionController session;

  Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 10));

  setUp(() async {
    engine = _Engine();
    session = SessionController(engine);
    await session.init();
    engine.controller.add(const StateEvent(EngineState.listening, null));
    await pump();
  });

  test('Switch speaker forces new lines to the next speaker; Auto returns to Moonshine labels', () async {
    engine.caption('s-0001', 'Hello there.', 1);
    await pump();
    expect(session.currentSpeaker, 1);

    session.switchSpeaker(); // 1 -> 2 even though only speaker 1 exists
    expect(session.liveSpeakerOverride, 2);
    engine.caption('s-0002', 'Hi.', 1); // Moonshine still says 1
    await pump();
    final second = session.finals.last;
    expect(session.speakerOf(second), 2);
    expect(second.speakerId, 1, reason: 'the original label is kept');

    session.switchSpeaker(); // 2 -> 1
    expect(session.liveSpeakerOverride, 1);

    session.useAutoSpeaker();
    engine.caption('s-0003', 'Back to auto.', 2);
    await pump();
    expect(session.speakerOf(session.finals.last), 2);
  });

  test('a name said by a manually switched speaker is assigned to that speaker', () async {
    engine.caption('s-0001', "Hi, I'm David.", 1);
    await pump();
    session.switchSpeaker();
    engine.caption('s-0002', "Hi David, my name's John.", 1);
    await pump();
    expect(session.speakerNames[1]?.name, 'David');
    expect(session.speakerNames[2]?.name, 'John');
  });

  test('tapping a line changes only that line', () async {
    engine.caption('s-0001', 'One.', 1);
    engine.caption('s-0002', 'Two.', 1);
    await pump();
    session.setLineSpeaker('s-0002', 2);
    expect(session.finals.map(session.speakerOf).toList(), [1, 2]);
    expect(session.knownSpeakers, [1, 2]);
  });

  test('no speaker labels at all: Stop OFFERS a guess (default off); originals kept; switch applies it', () async {
    const talk = [
      "Hi, I'm David.",
      "Hi David, my name's John. Nice to meet you.",
      'Nice to meet you too. What do you do?',
      'I work in logistics.',
      'That sounds busy. How big is the team?',
      'About twelve people.',
    ];
    for (var i = 0; i < talk.length; i++) {
      engine.caption('s-000${i + 1}', talk[i], 0); // Moonshine gave no speaker at all
      await pump();
    }
    await session.stop();

    expect(session.hasSuggestions, isTrue);
    expect(session.useSuggestions, isFalse, reason: 'off by default');
    expect(session.finals.every((s) => session.speakerOf(s) == 0), isTrue, reason: 'nothing applied yet');
    expect(session.finals.every((s) => s.suggestedSpeakerId != null), isTrue);

    session.setUseSuggestions(true);
    expect(session.finals.map(session.speakerOf).toSet(), {1, 2});
    expect(session.finals.every((s) => s.speakerId == 0), isTrue, reason: 'originals untouched');
    expect(session.displayName(1), 'David');
    expect(session.displayName(2), 'John');

    session.setUseSuggestions(false);
    expect(session.knownSpeakers, isEmpty);
  });

  test('Unknown lines plus a real speaker: no suggestions are offered at all', () async {
    engine.caption('s-0001', "Hi, I'm John.", 0);
    await pump();
    for (var i = 2; i <= 5; i++) {
      engine.caption('s-000$i', ['', 'Hey there.', 'How are you?', 'Fine.', 'Good.'][i - 1], 2);
      await pump();
    }
    await session.stop();
    expect(session.hasSuggestions, isFalse);
    expect(session.finals.first.speakerId, 0);
  });

  test('a manual rename survives toggling suggestions', () async {
    for (var i = 0; i < 4; i++) {
      engine.caption('s-000${i + 1}', ['Hello there.', 'Hi, how are you?', 'Fine, thanks.', 'Good to hear.'][i], 0);
      await pump();
    }
    await session.stop();
    session.setUseSuggestions(true);
    session.rename(2, 'Priya');
    session.setUseSuggestions(false);
    session.setUseSuggestions(true);
    expect(session.displayName(2), 'Priya');
  });

  test('speaker revision relabels a finished line; Unknown -> known applies the name rules', () async {
    engine.caption('s-0001', "Hi, I'm David.", 0); // finished while Unknown
    await pump();
    expect(session.speakerNames, isEmpty);
    expect(session.displayName(session.speakerOf(session.finals.single)), 'Unknown');

    engine.controller.add(const SpeakerRevisionEvent(segmentId: 's-0001', speakerId: 1));
    await pump();
    expect(session.speakerOf(session.finals.single), 1);
    expect(session.speakerNames[1]?.name, 'David', reason: 'name rule runs once the speaker is known');
    expect(session.finals.single.text, "Hi, I'm David.", reason: 'text is never changed');
  });

  test('speaker revision never overrides Switch speaker or a tapped line', () async {
    session.switchSpeaker(); // override = 2 for new lines
    engine.caption('s-0001', 'Forced line.', 1);
    engine.caption('s-0002', 'Tapped line.', 1);
    await pump();
    session.setLineSpeaker('s-0002', 1);
    engine.controller.add(const SpeakerRevisionEvent(segmentId: 's-0001', speakerId: 3));
    engine.controller.add(const SpeakerRevisionEvent(segmentId: 's-0002', speakerId: 3));
    await pump();
    expect(session.finals.map(session.speakerOf).toList(), [2, 1]);
    expect(session.finals.map((s) => s.speakerId).toList(), [3, 3], reason: "Moonshine's own label does update");
  });

  test('speaker event parsing', () {
    final ok = EngineEvent.fromMap({'type': 'speaker', 'segmentId': 's-0003', 'speakerId': 2});
    expect(ok, isA<SpeakerRevisionEvent>());
    expect(EngineEvent.fromMap({'type': 'speaker', 'segmentId': 's-0003'}), isNull);
    expect(EngineEvent.fromMap({'type': 'speaker', 'speakerId': 2}), isNull);
  });
}
