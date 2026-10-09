import 'package:flutter_test/flutter_test.dart';
import 'package:revise/session/clean_transcript.dart';

void main() {
  test('accepts filler removal and punctuation fixes', () {
    expect(
      acceptClean(
        'um so the pilot uh starts monday',
        'So the pilot starts monday.',
      ),
      isTrue,
    );
  });

  test('rejects changed numbers, negations, names and big rewrites', () {
    expect(
      acceptClean('send 3 decks by Friday', 'send 4 decks by Friday'),
      isFalse,
    );
    expect(
      acceptClean("we can't ship it today", 'we can ship it today'),
      isFalse,
    );
    expect(
      acceptClean('ask Mara about the specs', 'ask Dev about the specs'),
      isFalse,
    );
    expect(
      acceptClean(
        'the pilot sites are ready',
        'all three warehouses look good to go now',
      ),
      isFalse,
    );
  });
}
