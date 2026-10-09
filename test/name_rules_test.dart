import 'package:flutter_test/flutter_test.dart';
import 'package:revise/session/name_rules.dart';

void main() {
  test('self-introductions', () {
    expect(selfIntroName("Hi everyone, I'm Zairus, I lead product."), 'Zairus');
    expect(selfIntroName('my name is jeush'), 'Jeush');
    expect(selfIntroName("I'm good, thanks"), isNull);
    expect(selfIntroName('This is great'), isNull);
  });

  test('called by name', () {
    expect(calledName('Sam, can you send the deck?'), 'Sam');
    expect(calledName('What do you think, Jairus?'), 'Jairus');
    expect(calledName('Sure, I will send it.'), isNull);
    expect(calledName('Is it done?'), isNull);
  });
}
