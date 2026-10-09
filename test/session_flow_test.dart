import 'package:flutter_test/flutter_test.dart';
import 'package:revise/crm/crm_card.dart';
import 'package:revise/crm/crm_controller.dart';
import 'package:revise/engine/engine_events.dart';
import 'package:revise/engine/mock_caption_engine.dart';
import 'package:revise/session/session_controller.dart';

MockCaptionEngine fastMock(MockScenario s) => MockCaptionEngine(
  scenario: s,
  wordInterval: const Duration(milliseconds: 1),
  turnGap: const Duration(milliseconds: 1),
  llmDelay: const Duration(milliseconds: 1),
);

Future<void> until(bool Function() done) async {
  for (var i = 0; i < 2000 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(done(), isTrue);
}

Future<SessionController> recordFullMeeting(MockScenario s) async {
  final session = SessionController(fastMock(s));
  await session.init();
  await session.start();
  await until(() => session.finals.length == MockCaptionEngine.script.length);
  await session.stop();
  return session;
}

void main() {
  test('mock meeting: names detected, unknown kept, finals ordered', () async {
    final session = await recordFullMeeting(MockScenario.meeting);
    expect(session.state, EngineState.stopped);
    expect(session.partials, isEmpty);
    expect(session.displayName(1), 'Zairus');
    expect(session.displayName(2), 'Jeush');
    expect(session.displayName(3), 'Sam'); // called by name, answered next
    expect(session.displayName(4), 'Jairus');
    expect(session.displayName(0), 'Unknown');
    final ids = session.finals.map((s) => s.id).toList();
    expect(ids, [
      for (var i = 1; i <= 8; i++) 's-${i.toString().padLeft(4, '0')}',
    ]);
  });

  test('manual names beat inferred names', () async {
    final session = SessionController(fastMock(MockScenario.meeting));
    await session.init();
    await session.start();
    session.rename(1, 'Boss');
    await until(() => session.finals.length == MockCaptionEngine.script.length);
    await session.stop();
    expect(session.displayName(1), 'Boss');
  });

  test('CRM cards generate with evidence; empty fields stay empty', () async {
    final session = await recordFullMeeting(MockScenario.meeting);
    final crm = CrmController(session.engine, session);
    await crm.generateMissing();
    expect(crm.cards.length, 4);
    expect(crm.cards.values.every((c) => c.status == CrmStatus.done), isTrue);
    final sam = crm.cards[3]!;
    expect(sam.commitments.map((c) => c.what), [
      'send the deck',
      'email the timeline to everyone',
    ]);
    expect(sam.commitments.first.due, 'Friday morning');
    expect(sam.evidence['commitments[0].what'], ['s-0004']);
    expect(crm.cards[1]!.commitments, isEmpty);
    expect(crm.cards[1]!.contactMentioned, isNull);
  });

  test(
    'CRM failure: auto retry once, then manual retry fixes only failed',
    () async {
      final session = await recordFullMeeting(MockScenario.crmFailure);
      final crm = CrmController(session.engine, session);
      await crm.generateMissing();
      expect(crm.cards[3]!.status, CrmStatus.failed);
      crm.cards[1]!
        ..role = 'CEO'
        ..markEdited('role');
      await crm.retryFailed();
      expect(crm.cards[3]!.status, CrmStatus.done);
      expect(crm.cards[1]!.role, 'CEO');
      expect(crm.cards[1]!.userEdited, contains('role'));
    },
  );

  test('empty session: no lines, no cards', () async {
    final session = SessionController(fastMock(MockScenario.emptySpeech));
    await session.init();
    await session.start();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await session.stop();
    final crm = CrmController(session.engine, session);
    await crm.generateMissing();
    expect(session.finals, isEmpty);
    expect(crm.cards, isEmpty);
  });

  test('pause flushes the current line; Stop while paused works', () async {
    final engine = MockCaptionEngine(
      wordInterval: const Duration(milliseconds: 20),
      turnGap: const Duration(milliseconds: 1),
    );
    final session = SessionController(engine);
    await session.init();
    await session.start();
    await until(() => session.partials.isNotEmpty);
    await session.pause();
    await until(() => session.finals.isNotEmpty);
    expect(session.finals.first.text, MockCaptionEngine.script.first.$2);
    await session.stop();
    expect(session.state, EngineState.stopped);
  });

  test('evidence from another speaker or unknown IDs is rejected', () {
    final mine = Segment(
      id: 's-0001',
      text: "I'm Ana from Acme",
      speakerId: 1,
      isFinal: true,
      tStartMs: 0,
      tEndMs: 10,
    );
    final card = CrmCard(speakerId: 1)
      ..applyModelOutput(
        'Here: {"name":"Ana","role":"CTO","organization":"Acme",'
        '"topics":["x"],"commitments":[],"source_segments":'
        '{"role":["s-0099"],"organization":["s-0001"],"topics[0]":["s-0002"]}}',
        {'s-0001': mine},
      );
    expect(card.role, isNull);
    expect(card.organization, 'Acme');
    expect(card.topics, isEmpty);
    expect(
      () => CrmCard(speakerId: 1).applyModelOutput('not json', {}),
      throwsFormatException,
    );
  });

  test('caption event parsing tolerates bad input', () {
    expect(EngineEvent.fromMap('nope'), isNull);
    expect(EngineEvent.fromMap({'type': 'state', 'state': 'weird'}), isNull);
    final e = EngineEvent.fromMap({
      'type': 'caption',
      'segmentId': 's-1',
      'text': 'hi',
      'speakerId': 2,
      'isFinal': true,
      'tStartMs': 50,
      'tEndMs': 10,
    });
    expect(e, isA<CaptionEvent>());
    expect((e! as CaptionEvent).tEndMs, 50);
  });
}
