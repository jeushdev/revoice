import 'package:flutter_test/flutter_test.dart';
import 'package:revise/session/name_rules.dart';

void main() {
  test('self-introductions', () {
    expect(selfIntroName("Hi everyone, I'm Zairus, I lead product."), 'Zairus');
    expect(selfIntroName('my name is jeush'), 'Jeush');
    expect(selfIntroName("my name's John"), 'John');
    expect(selfIntroName('My name’s John, nice to meet you'), 'John'); // curly apostrophe
    expect(selfIntroName("Hi, I'm David."), 'David');
    expect(selfIntroName("Hi David, my name's John. Nice to meet you."), 'John');
    expect(selfIntroName('you can call me Dee'), 'Dee');
    expect(selfIntroName("I’m David"), 'David');
    expect(selfIntroName("I'm good, thanks"), isNull);
    expect(selfIntroName("My name's not important"), isNull);
    expect(selfIntroName('This is great'), isNull);
  });

  test('called by name', () {
    expect(calledName('Sam, can you send the deck?'), 'Sam');
    expect(calledName('What do you think, Jairus?'), 'Jairus');
    expect(calledName('Sure, I will send it.'), isNull);
    expect(calledName('Is it done?'), isNull);
  });
}
