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
    // Sources are found from the answer's words (the model's own list is not trusted).
    expect(deadlines.sources, isNotEmpty);
    expect(deadlines.sources.length, lessThanOrEqualTo(2));
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
      'answer': '{"found": true, "answer": "Zairus and Jeush took part.", "sources": []}',
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
    expect(session.displayName(2), 'Jeush'); // model said Sam, but speaker 2 never said so: no guessing
    expect(session.displayName(3), 'Sam'); // heard live, kept
    expect(session.speakerNames[3]!.source, NameSource.auto);
    // The one valid model question comes first; generic questions fill up to three.
    expect(summary.questions.first.text, 'Who took part?');
    expect(summary.questions, hasLength(3));
    expect({for (final q in summary.questions) q.text.toLowerCase()}, hasLength(3));

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

  test('summary becomes stale and is rewritten when a speaker label changes', () async {
    final session = await recordFullMeeting(MockScenario.meeting);
    final summary = SummaryController(session.engine, session);
    await summary.run();
    expect(summary.stale, isFalse);
    final first = summary.summary;
    session.setLineSpeaker('s-0004', 2); // tap-to-fix
    expect(summary.stale, isTrue);
    await until(() => !summary.stale && summary.status == SummaryStatus.done);
    expect(summary.summary, isNotNull);
    expect(first, isNotNull);
    session.rename(1, 'Boss'); // rename also counts
    expect(summary.stale, isTrue);
    summary.dispose();
  });

  test('a model name match without evidence in the conversation is ignored (no guessing)', () async {
    final session = SessionController(
      ScriptedLlm({
        'match_speakers': '{"speakers": {"1": "Anna", "2": "Mark"}}',
        'summary': '{"summary": "A chat."}',
        'questions': '{"questions": ["What was it about?"]}',
      }),
    )..expectedNames = ['Anna', 'Mark'];
    for (var i = 0; i < 4; i++) {
      session.debugAddFinal(Segment(
        id: 's-000${i + 1}',
        text: ['Hello there.', 'Hi, how are you?', 'Fine, thanks.', 'Good to hear.'][i],
        speakerId: i.isEven ? 1 : 2,
        isFinal: true,
        tStartMs: i * 3000,
        tEndMs: i * 3000 + 2000,
      ));
    }
    final summary = SummaryController(session.engine, session);
    await summary.run();
    expect(session.speakerNames, isEmpty); // nobody introduced themselves: stay "Speaker N"
    expect(session.displayName(1), 'Speaker 1');
    summary.dispose();
  });

  test('suggested questions are answered in the background; unanswerable ones are dropped; tap is instant', () async {
    final engine = _CountingLlm({
      'match_speakers': '{"speakers": {}}',
      'summary': '{"summary": "Short recap."}',
      'questions': '{"questions": ["What is the weather?", "Who took part?", "What did Sam agree to do?"]}',
      'answer': '{"found": true, "answer": "Sam will send the demo deck by Friday.", "sources": []}',
    });
    final session = await recordFullMeeting(MockScenario.meeting, engine: engine);
    final summary = SummaryController(engine, session);
    await summary.run();
    // The scripted model gives every question the same answer, so the second candidate is a
    // duplicate suggestion and is dropped; generic questions fill up to three.
    expect(summary.questions.first.text, 'Who took part?');
    expect(summary.questions.map((q) => q.text), isNot(contains('What did Sam agree to do?')));
    expect(summary.questions, hasLength(3));
    expect(summary.questions.map((q) => q.text), isNot(contains('What is the weather?')));
    expect(summary.questions.every((q) => q.cached != null && q.cached!.sources.isNotEmpty), isTrue);
    final calls = engine.calls;
    await summary.ask(summary.questions.first);
    expect(engine.calls, calls); // no model call: the answer was ready
    expect(summary.questions.first.status, QuestionStatus.answered);
    expect(summary.questions.first.answer, contains('demo deck'));
    summary.dispose();
  });
  test('the summary never contains questions', () {
    expect(
      SummaryController.dropQuestions('Mark and Anna agreed on a plan. What should they do next? Who pays? Did they agree? Mark sends the guide by Friday.'),
      'Mark and Anna agreed on a plan. Mark sends the guide by Friday.',
    );
    expect(SummaryController.dropQuestions('How much is it?'), '');
  });


  test('suggestions are never empty when the transcript has 3 or more lines', () async {
    final engine = ScriptedLlm({
      'match_speakers': '{"speakers": {}}',
      'summary': '{"summary": "Short recap."}',
      'questions': '{"questions": ["What is the weather?", "Why is the sky blue?"]}',
      'answer': '{"found": false, "answer": "", "sources": []}', // nothing is ever supported
    });
    final session = await recordFullMeeting(MockScenario.meeting, engine: engine);
    expect(session.finals.length, greaterThanOrEqualTo(3));
    final summary = SummaryController(engine, session);
    await summary.run();
    expect(summary.questions, hasLength(3));
    expect(summary.questions.every((q) => SummaryController.genericQuestions.contains(q.text)), isTrue);
    // A tap answers normally (here: not mentioned).
    await summary.ask(summary.questions.first);
    expect(summary.questions.first.found, isFalse);
    summary.dispose();
  });
}

class _CountingLlm extends ScriptedLlm {
  _CountingLlm(super.replies);
  int calls = 0;

  @override
  Future<String> generate({
    required String prompt,
    int maxTokens = 512,
    bool json = true,
    String? system,
    Object? jsonGrammar,
    String? requestId,
  }) {
    calls++;
    return super.generate(prompt: prompt, maxTokens: maxTokens);
  }
}
