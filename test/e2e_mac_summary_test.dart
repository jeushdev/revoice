// Optional: Jairus's real SummaryController (summary, suggested questions, Ask) against the real
// on-device model on the Mac, with the Mark/Anna script.  E2E_LLM=1 flutter test test/e2e_mac_summary_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:revise/session/session_controller.dart';
import 'package:revise/summary/summary_controller.dart';

import 'e2e_mac_llm_test.dart' show MacLlmEngine;
import 'speaker_split_test.dart' show build, labels, withIntros;

const markAnna = <(int, String)>[
  (1, 'Hi Anna, thanks for meeting me.'),
  (2, 'Thanks Mark. We have a problem with lost orders. Our staff write them on paper and some get lost.'),
  (1, 'I see. Our app keeps every order in one place.'),
  (2, 'How much does it cost?'),
  (1, 'It costs 500 pesos a month.'),
  (2, "That works for us. Let's go with the monthly plan."),
  (1, "Great. I'll send the setup guide by Friday."),
  (2, "I'll train my staff on Monday."),
];

void main() {
  final skip = Platform.environment['E2E_LLM'] == '1' ? null : 'set E2E_LLM=1';

  test('Mark/Anna: summary, suggested questions and asks', () async {
    final engine = MacLlmEngine(Directory.systemTemp.createTempSync());
    final session = SessionController(engine);
    for (var i = 0; i < markAnna.length; i++) {
      session.debugAddFinal(Segment(
        id: 's-${(i + 1).toString().padLeft(4, '0')}',
        text: markAnna[i].$2,
        speakerId: markAnna[i].$1,
        isFinal: true,
        tStartMs: i * 3000,
        tEndMs: i * 3000 + 2500,
      ));
    }
    session.rename(1, 'Mark');
    session.rename(2, 'Anna');
    final summary = SummaryController(engine, session);
    await summary.run();
    print('STATUS ${summary.status} error=${summary.error}');
    print('SUMMARY ${summary.summary}');
    print('SUGGESTED ${summary.questions.map((q) => q.text).toList()}');
    // Every suggested question, as the user would tap them.
    for (final q in [...summary.questions]) {
      await summary.ask(q);
      print('SUGGESTED-ASK "${q.text}" -> found=${q.found} ${q.answer} <- ${q.sources} err=${q.error}');
    }
    for (final text in [
      'What problem does Anna have?',
      'How much does it cost?',
      'What will Mark do and when?',
      'Did they talk about delivery?',
    ]) {
      final q = SuggestedQuestion(text);
      await summary.ask(q);
      print('ASK "$text" -> found=${q.found} ${q.answer} <- ${q.sources} err=${q.error}');
    }
  }, skip: skip, timeout: const Timeout(Duration(minutes: 10)));

  for (final oneSpeaker in [true, false]) {
    test('Mark/Anna through the session code, ${oneSpeaker ? 'ALL lines on ONE speaker id' : 'Moonshine separated them'}', () async {
      final engine = MacLlmEngine(Directory.systemTemp.createTempSync());
      final session = build(withIntros, oneSpeaker: oneSpeaker, names: ['Mark', 'Anna']);
      session.applyPostStop(); // what Stop does to the labels
      print('RUN ${oneSpeaker ? 'ONE-SPEAKER' : 'SEPARATED'}');
      print('LABELS ${labels(session)}  (autoSplit=${session.autoSplitApplied}, moonshine ids=${session.finals.map((l) => l.speakerId).join()})');
      final summary = SummaryController(engine, session);
      await summary.run();
      print('SUMMARY ${summary.summary}');
      for (final q in summary.questions) {
        final cached = q.cached;
        print('SUGGESTED "${q.text}" -> ${cached == null ? '(not pre-answered)' : '${cached.found}: ${cached.answer} <- ${cached.sources}'}');
      }
      expect(summary.questions, isNotEmpty);
    }, skip: skip, timeout: const Timeout(Duration(minutes: 10)));
  }
}
