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
  Future<void> stop() async {}
  @override
  Future<String> generateCrm({required String prompt, int maxTokens = 512}) async => '';
  @override
  Future<String> cleanLine({required String text, required String prompt, int maxTokens = 512}) async => text;
  @override
  Future<String> generate({
    required String prompt,
    int maxTokens = 512,
    String? system,
    Object? jsonGrammar,
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
}
