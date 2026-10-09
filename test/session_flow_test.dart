import 'package:flutter_test/flutter_test.dart';
import 'package:revise/engine/engine_events.dart';
import 'package:revise/engine/mock_caption_engine.dart';
import 'package:revise/session/session_controller.dart';
import 'package:revise/summary/summary_controller.dart';

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

/// Replies with fixed text per prompt TASK, to test validation.
class ScriptedLlm extends MockCaptionEngine {
  ScriptedLlm(this.replies)
    : super(
        wordInterval: const Duration(milliseconds: 1),
        turnGap: const Duration(milliseconds: 1),
        llmDelay: const Duration(milliseconds: 1),
      );
  final Map<String, String> replies;

  @override
  Future<String> generate({
    required String prompt,
    int maxTokens = 512,
    bool json = true,
    String? system,
    Object? jsonGrammar,
    String? requestId,
  }) async {
    final task = RegExp(
      r'^TASK: (\w+)',
      multiLine: true,
    ).firstMatch(prompt)!.group(1)!;
    return replies[task] ?? 'no idea';
  }
}

Future<SessionController> recordFullMeeting(
  MockScenario s, {
  MockCaptionEngine? engine,
  List<String> names = const [],
}) async {
  final session = SessionController(engine ?? fastMock(s))
    ..expectedNames = names;
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

  test('summary: names matched, summary written, questions drafted', () async {
    final session = await recordFullMeeting(
      MockScenario.meeting,
      names: ['Zairus', 'Sam'],
    );
    final summary = SummaryController(session.engine, session);
    await summary.run();
    expect(summary.status, SummaryStatus.done);
    expect(summary.steps.values.every((s) => s == StepStatus.done), isTrue);
    expect(summary.summary, contains('demo deck by Friday'));
    expect(
      summary.questions.map((q) => q.text),
      contains('What are the deadlines?'),
    );
    expect(
      summary.questions.every((q) => q.status == QuestionStatus.idle),
      isTrue,
    );
  });

  test('questions are answered only when asked, with valid sources', () async {
    final session = await recordFullMeeting(MockScenario.meeting);
    final summary = SummaryController(session.engine, session);
    await summary.run();
    expect(summary.steps[SummaryStep.matching], StepStatus.skipped);
    final deadlines = summary.questions.firstWhere(
      (q) => q.text.contains('deadlines'),
    );
    await summary.ask(deadlines);
    expect(deadlines.status, QuestionStatus.answered);
    expect(deadlines.answer, contains('Sam: demo deck by Friday morning'));
    expect(deadlines.sources, ['s-0003', 's-0004', 's-0005', 's-0007']);
    expect(summary.asked, [deadlines]);
    expect(summary.plainText(), contains('What are the deadlines?'));

    final odd = SuggestedQuestion('What did the cat eat?');
    await summary.ask(odd);
    expect(odd.found, isFalse);
    expect(odd.answer, isNull);
    summary.dismiss(deadlines);
    expect(summary.asked, [odd]);
  });

  test('suggested names never beat manual or listed heard names', () {
    final session = SessionController(fastMock(MockScenario.meeting))
      ..expectedNames = ['Zairus', 'Jesh'];
    session
      ..speakerNames[1] = const SpeakerName('Zairus', NameSource.auto)
      ..speakerNames[2] = const SpeakerName('Jeush', NameSource.auto)
      ..speakerNames[3] = const SpeakerName('Boss', NameSource.manual)
      ..suggestName(1, 'Jesh')
      ..suggestName(2, 'Jesh')
      ..suggestName(3, 'Zairus')
      ..suggestName(4, 'Zairus');
    expect(session.displayName(1), 'Zairus'); // heard and on the list
    expect(session.displayName(2), 'Jesh'); // heard name was not listed
    expect(session.speakerNames[2]!.source, NameSource.suggested);
    expect(session.displayName(3), 'Boss'); // manual wins
    expect(session.displayName(4), 'Zairus');
  });

  test('model output is validated: unlisted names, bad JSON, bad questions', () async {
    final engine = ScriptedLlm({
      'match_speakers':
          '{"speakers": {"1": "Mallory", "2": "Sam", "3": "sam", "9": "Sam"}}',
      'summary': 'Sure! {"summary": "Short recap."}',
      'questions': '{"questions": ["Who took part?", "not a question", 3, "Who took part?"]}',
    });
    final session = await recordFullMeeting(
      MockScenario.meeting,
      engine: engine,
      names: ['Sam'],
    );
    final summary = SummaryController(engine, session);
    await summary.run();
    expect(summary.status, SummaryStatus.done);
    expect(summary.summary, 'Short recap.');
    expect(session.displayName(1), 'Zairus'); // Mallory is not on the list
    expect(session.displayName(2), 'Sam'); // first use of the name wins
    expect(session.displayName(3), 'Sam'); // heard live, kept
    expect(session.speakerNames[3]!.source, NameSource.auto);
    expect(summary.questions.map((q) => q.text), ['Who took part?']);

    final broken = ScriptedLlm({'summary': 'no json here'});
    final s2 = await recordFullMeeting(MockScenario.meeting, engine: broken);
    final failed = SummaryController(broken, s2);
    await failed.run();
    expect(failed.status, SummaryStatus.failed);
    expect(failed.error, contains('Invalid model output'));
  });

  test('summary failure: Retry finishes without redoing done steps', () async {
    final session = await recordFullMeeting(MockScenario.summaryFailure);
    final summary = SummaryController(session.engine, session);
    await summary.run();
    expect(summary.status, SummaryStatus.failed);
    expect(summary.steps[SummaryStep.summarizing], StepStatus.failed);
    expect(summary.steps[SummaryStep.suggesting], StepStatus.pending);
    await summary.run();
    expect(summary.status, SummaryStatus.done);
    expect(summary.questions, isNotEmpty);
  });

  test('empty session: nothing to summarize', () async {
    final session = SessionController(fastMock(MockScenario.emptySpeech));
    await session.init();
    await session.start();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await session.stop();
    final summary = SummaryController(session.engine, session);
    await summary.run();
    expect(session.finals, isEmpty);
    expect(summary.status, SummaryStatus.idle);
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
