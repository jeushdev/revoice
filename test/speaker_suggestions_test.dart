import 'package:flutter_test/flutter_test.dart';
import 'package:revise/session/speaker_suggestions.dart';

List<SuggestionLine> _all1(List<String> texts) => [
  for (var i = 0; i < texts.length; i++)
    SuggestionLine('s-${(i + 1).toString().padLeft(4, '0')}', texts[i], 0),
];

void main() {
  test('interview with no speaker labels at all is split by questions, replies and names', () {
    final lines = _all1([
      "Hi, I'm David.",
      "Hi David, my name's John. Nice to meet you.",
      'Nice to meet you too. So what do you do at the company?',
      'I work in logistics. I manage the warehouse team.',
      'That sounds busy. How big is the team?',
      "About twelve people. We're hiring two more next month.",
      'Great. Could you send me the hiring plan by Friday?',
      "Sure, I'll email it to you tomorrow morning.",
      'Perfect, thanks John.',
      "No problem David. Let's talk again next week.",
    ]);
    final s = suggestSpeakers(lines)!;
    // David = 1, John = 2 in strict alternation for this dialogue.
    final got = [for (final l in lines) s.speakers[l.id]];
    const truth = [1, 2, 1, 2, 1, 2, 1, 2, 1, 2];
    final correct = [for (var i = 0; i < got.length; i++) got[i] == truth[i]].where((x) => x).length;
    print('interview: $got  (correct $correct/10)');
    expect(correct, greaterThanOrEqualTo(9));
    expect(s.names[1], 'David');
    expect(s.names[2], 'John');
  });

  test('already separated voices are left alone', () {
    final lines = [
      const SuggestionLine('s-0001', "Hi, I'm David.", 1),
      const SuggestionLine('s-0002', 'Hello David.', 2),
      const SuggestionLine('s-0003', 'How are you?', 1),
      const SuggestionLine('s-0004', 'Fine, thanks.', 2),
    ];
    expect(suggestSpeakers(lines), isNull);
  });

  test('too few lines or a monologue gives no suggestion', () {
    expect(suggestSpeakers(_all1(['One.', 'Two.', 'Three.'])), isNull);
    expect(
      suggestSpeakers(_all1(['We ship Friday.', 'Then we test.', 'Then we review.', 'Then done.'])),
      isNull,
      reason: 'no turn-taking cue, so it stays one speaker',
    );
  });

  test('greeting a name means the speaker is someone else', () {
    final s = suggestSpeakers(_all1([
      "I'm Maria.",
      'Thanks, Maria. What is the plan?',
      'We launch in March.',
      'Great, thanks.',
    ]))!;
    expect(s.speakers['s-0001'], 1);
    expect(s.speakers['s-0002'], 2);
    expect(s.names[1], 'Maria');
  });

  test('Unknown lines plus even one real speaker label: Moonshine labels are left alone', () {
    final lines = [
      const SuggestionLine('s-0001', "Hi, I'm John.", 0),
      const SuggestionLine('s-0002', "Yo what's up johnny", 2),
      const SuggestionLine('s-0003', "I'm gonna ask about your business.", 2),
      const SuggestionLine('s-0004', 'Sure, go ahead.', 0),
    ];
    expect(suggestSpeakers(lines), isNull);
  });

  test('a line that addresses someone by name (even a nickname) is never assigned to them', () {
    final s = suggestSpeakers(_all1([
      "Hi, I'm John.",
      "Yo what's up johnny",
      "I'm gonna ask about your business.",
      'Thanks, John. Let me think.',
    ]))!;
    expect(s.speakers['s-0001'], 1); // John introduces himself
    expect(s.speakers['s-0002'], 2, reason: 'addressed TO johnny, so not John');
    expect(s.speakers['s-0004'], 2, reason: '"Thanks, John" is said to John');
  });
}
