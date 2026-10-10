import 'package:flutter_test/flutter_test.dart';
import 'package:revise/session/session_controller.dart';
import 'package:revise/session/speaker_split.dart';
import 'package:revise/engine/mock_caption_engine.dart';

/// (true speaker 1 = Mark, 2 = Anna, text). Lines are 2 s long with 1.6 s pauses between turns.
const withIntros = <(int, String)>[
  (1, "Hi Anna, I'm Mark. Thanks for meeting me."),
  (2, "Thanks Mark. I'm Anna and we have a problem with lost orders. Our staff write them on paper and some get lost."),
  (1, 'I see. Our app keeps every order in one place.'),
  (2, 'How much does it cost?'),
  (1, 'It costs 500 pesos a month.'),
  (2, "That works for us. Let's go with the monthly plan."),
  (1, "Great. I'll send the setup guide by Friday."),
  (2, "I'll train my staff on Monday."),
];

/// The demo script: nobody introduces themselves, names are only used to address each other.
const addressOnly = <(int, String)>[
  (1, 'Hi Anna, thanks for meeting me.'),
  (2, 'Thanks Mark. We have a problem with lost orders. Our staff write them on paper and some get lost.'),
  (1, 'I see. Our app keeps every order in one place.'),
  (2, 'How much does it cost?'),
  (1, 'It costs 500 pesos a month.'),
  (2, "That works for us. Let's go with the monthly plan."),
  (1, "Great. I'll send the setup guide by Friday."),
  (2, "I'll train my staff on Monday."),
];

SessionController build(List<(int, String)> script, {required bool oneSpeaker, List<String> names = const []}) {
  final session = SessionController(MockCaptionEngine())..expectedNames = names;
  for (var i = 0; i < script.length; i++) {
    session.debugAddFinal(Segment(
      id: 's-${(i + 1).toString().padLeft(4, '0')}',
      text: script[i].$2,
      speakerId: oneSpeaker ? 1 : script[i].$1,
      isFinal: true,
      tStartMs: i * 3600,
      tEndMs: i * 3600 + 2000,
    ));
  }
  return session;
}

String labels(SessionController s) => s.finals.map((l) => s.displayName(s.speakerOf(l))).join(',');

void main() {
  const truth = 'Mark,Anna,Mark,Anna,Mark,Anna,Mark,Anna';

  test('worst case, everything on ONE speaker id, with self introductions', () {
    final s = build(withIntros, oneSpeaker: true, names: ['Mark', 'Anna']);
    s.applyPostStop();
    expect(s.autoSplitApplied, isTrue);
    expect(labels(s), truth);
    expect(s.finals.every((l) => l.speakerId == 1), isTrue); // Moonshine's labels are kept
    expect(s.knownSpeakers, [1, 2]);
  });

  test('worst case, one speaker id, names only used to address each other', () {
    final s = build(addressOnly, oneSpeaker: true, names: ['Mark', 'Anna']);
    s.applyPostStop();
    expect(labels(s), truth);
  });

  test('two intros from one speaker are detected even without entered names', () {
    final s = build(withIntros, oneSpeaker: true);
    s.applyPostStop();
    expect(labels(s), truth);
  });

  test('Moonshine separated them correctly: labels stay unchanged', () {
    for (final script in [withIntros, addressOnly]) {
      final s = build(script, oneSpeaker: false, names: ['Mark', 'Anna']);
      final before = s.finals.map((l) => l.speakerId).toList();
      s.applyPostStop();
      expect(s.autoSplitApplied, isFalse);
      expect(s.finals.map(s.speakerOf).toList(), before);
      expect(s.finals.every((l) => l.autoSpeakerId == null), isTrue);
    }
  });

  test('no name evidence at all: nothing is guessed', () {
    final s = build(const [(1, 'We should plan the launch.'), (1, 'Yes, next week works.'), (1, 'Good.')],
        oneSpeaker: true, names: ['Mark', 'Anna']);
    s.applyPostStop();
    expect(s.autoSplitApplied, isFalse);
    expect(s.knownSpeakers, [1]);
  });

  test("a line the user fixed by hand keeps the user's choice, and tap-to-fix still works", () {
    final s = build(withIntros, oneSpeaker: true, names: ['Mark', 'Anna']);
    s.setLineSpeaker('s-0003', 2); // the user puts line 3 under Anna
    s.applyPostStop();
    expect(s.speakerOf(s.finals[2]), 2);
    s.setLineSpeaker('s-0004', 1); // tap-to-fix after the automatic split
    expect(s.speakerOf(s.finals[3]), 1);
  });

  test('splitMergedSpeaker works on plain lines', () {
    final r = splitMergedSpeaker([
      const SplitLine('a', "I'm Mark.", 1, 0, 1000),
      const SplitLine('b', "I'm Anna.", 1, 2500, 3500),
    ], const []);
    expect(r!.lineSpeaker['a'] != r.lineSpeaker['b'], isTrue);
    expect(r.names.values.toSet(), {'Mark', 'Anna'});
  });
}
