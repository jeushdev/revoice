import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:revise/ai/meeting_ai_controller.dart';
import 'package:revise/ai/meeting_parsing.dart';
import 'package:revise/engine/caption_engine.dart';
import 'package:revise/engine/engine_events.dart';
import 'package:revise/engine/mock_caption_engine.dart';
import 'package:revise/session/session_controller.dart';
import 'package:revise/transcript/clean_transcript.dart';

MergeLine line(String id, int speaker, String text, int start, int end) =>
    MergeLine(id: id, speakerId: speaker, text: text, tStartMs: start, tEndMs: end);

/// Engine whose LLM answers come from callbacks, so no model is needed.
class FakeLlmEngine implements CaptionEngine {
  FakeLlmEngine({this.onGenerate, this.onClean});

  String Function(String prompt, Object? grammar)? onGenerate;
  String Function(String text)? onClean;
  final events0 = StreamController<EngineEvent>.broadcast();
  final generateCalls = <String>[];
  final cleanCalls = <String>[];
  String? lastRequestId;

  @override
  Stream<EngineEvent> get events => events0.stream;

  @override
  Future<String> generate({
    required String prompt,
    int maxTokens = 512,
    String? system,
    Object? jsonGrammar,
    String? requestId,
  }) async {
    generateCalls.add(prompt);
    lastRequestId = requestId;
    final reply = onGenerate!(prompt, jsonGrammar);
    if (requestId != null) {
      for (var i = 0; i < reply.length; i += 7) {
        events0.add(LlmTokenEvent(requestId: requestId, delta: reply.substring(i, (i + 7).clamp(0, reply.length))));
      }
      await Future<void>.delayed(Duration.zero);
    }
    return reply;
  }

  @override
  Future<String> cleanLine({required String text, required String prompt, int maxTokens = 512}) async {
    cleanCalls.add(text);
    return onClean!(text);
  }

  @override
  Future<String> generateCrm({required String prompt, int maxTokens = 512}) async => '{}';
  @override
  Future<InitResult> init() async => const InitResult(sttReady: true, llmReady: true);
  @override
  Future<void> start({String language = 'en'}) async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

/// A stopped session holding the given final lines (speaker, text, startMs, endMs).
SessionController sessionWith(List<(int, String, int, int)> lines) {
  final session = SessionController(FakeLlmEngine());
  for (var i = 0; i < lines.length; i++) {
    final (speaker, text, start, end) = lines[i];
    session.debugAddFinal(
      Segment(
        id: 's-${(i + 1).toString().padLeft(4, '0')}',
        text: text,
        speakerId: speaker,
        isFinal: true,
        tStartMs: start,
        tEndMs: end,
      ),
    );
  }
  return session;
}

const phoneRun = <(int, String, int, int)>[
  (1, 'Honestly...', 0, 900),
  (1, 'Is the paperwork', 1200, 2400),
  (1, 'We track all our orders in a notebook.', 2800, 5200),
  (1, 'And things get lost.', 5600, 6800),
  (2, 'That sounds painful.', 9000, 10000),
];

void main() {
  group('mergeFragments', () {
    test('phone-run case merges into one turn and keeps every segment id', () {
      final turns = mergeFragments([
        line('s-1', 1, 'Honestly...', 0, 900),
        line('s-2', 1, 'Is the paperwork', 1200, 2400),
        line('s-3', 1, 'We track all our orders in a notebook.', 2800, 5200),
        line('s-4', 1, 'And things get lost.', 5600, 6800),
      ]);
      expect(turns, hasLength(1));
      expect(turns.single.segmentIds, ['s-1', 's-2', 's-3', 's-4']);
      expect(
        turns.single.rawText,
        'Honestly... Is the paperwork We track all our orders in a notebook. And things get lost.',
      );
    });

    test('different speaker, long gap, or finished sentence + capital start do not merge', () {
      expect(mergeFragments([line('a', 1, 'Hello there.', 0, 500), line('b', 2, 'Hi.', 600, 900)]), hasLength(2));
      expect(mergeFragments([line('a', 1, 'Is the paperwork', 0, 500), line('b', 1, 'we lose it', 2500, 3000)]), hasLength(2));
      expect(mergeFragments([line('a', 1, 'That is done.', 0, 500), line('b', 1, 'Next topic is budget', 800, 1500)]), hasLength(2));
    });

    test('merges on lowercase start or and/so/but/because/or after a finished sentence', () {
      expect(mergeFragments([line('a', 1, 'We shipped it.', 0, 500), line('b', 1, 'because it was ready', 700, 1500)]), hasLength(1));
      for (final w in ['And', 'So', 'But', 'Because', 'Or']) {
        expect(mergeFragments([line('a', 1, 'We shipped it.', 0, 500), line('b', 1, '$w later', 700, 1500)]), hasLength(1), reason: w);
      }
    });

    test('gap exactly 1.5 s does not merge; empty lines are skipped', () {
      expect(mergeFragments([line('a', 1, 'and so', 0, 1000), line('b', 1, 'on', 2500, 3000)]), hasLength(2));
      expect(mergeFragments([line('a', 1, '  ', 0, 100), line('b', 1, 'Hi', 200, 300)]).single.segmentIds, ['b']);
    });
  });

  group('word guard', () {
    test('punctuation, capitals and um/uh are ignored', () {
      expect(
        passesWordGuard(
          'um honestly is the paperwork we track all our orders in a notebook and things get lost',
          'Honestly, is the paperwork... We track all our orders in a notebook, and things get lost.',
        ),
        isTrue,
      );
      expect(passesWordGuard("it's well-known", "It's well known."), isTrue);
    });

    test('a changed, added, dropped or reordered word is rejected', () {
      expect(passesWordGuard('we ship on friday', 'We ship on Monday.'), isFalse);
      expect(passesWordGuard('we ship on friday', 'We will ship on Friday.'), isFalse);
      expect(passesWordGuard('we ship on friday', 'We ship Friday.'), isFalse);
      expect(passesWordGuard('we ship on friday', 'On Friday we ship.'), isFalse);
      expect(passesWordGuard('we owe 20 dollars', 'We owe twenty dollars.'), isFalse);
    });

    test('model replies are tidied and dashes removed', () {
      expect(sanitizeModelText('"Hello there."'), 'Hello there.');
      expect(sanitizeModelText('Text: Hi — there.\n'), 'Hi, there.');
    });
  });

  group('rules before the model', () {
    test('fillers are removed by rule, commas stuck to them too', () {
      expect(stripFillers('Sure, so um, tell me about it'), 'Sure, so tell me about it');
      expect(stripFillers('mostly Facebook, and uh some by text'), 'mostly Facebook, and some by text');
      expect(stripFillers('Um, hello. Umbrella and uhm sure'), 'hello. Umbrella and sure');
    });

    test('a pause between an unfinished fragment and a new sentence becomes "..."', () {
      final turn = mergeFragments([
        line('a', 1, 'Honestly...', 0, 900),
        line('b', 1, 'Is the paperwork', 1200, 2400),
        line('c', 1, 'We track all our orders in a notebook.', 2800, 5200),
        line('d', 1, 'And things get lost.', 5600, 6800),
      ]).single;
      expect(turn.hintedText, 'Honestly... Is the paperwork... We track all our orders in a notebook. And things get lost.');
      expect(passesWordGuard(turn.rawText, turn.hintedText), isTrue); // only punctuation differs
      final cont = mergeFragments([line('a', 1, 'About forty', 0, 900), line('b', 1, 'and some by text', 1200, 2000)]).single;
      expect(cont.hintedText, 'About forty and some by text'); // continuations are not cut
    });

    test('evidence is the turn that shares the claim\'s words; invented claims find none', () {
      const turns = {
        's-1': 'We track all our orders in a notebook.',
        's-2': 'I will send you a demo by next Friday.',
      };
      expect(findEvidence('Jun sends a demo next Friday', turns), ['s-2']);
      expect(findEvidence('The office is in Manila', turns), isEmpty);
    });

    test('an invented answer is unsupported even if the model cites a real id', () {
      const turns = {'s-1': 'We track all our orders in a notebook.'};
      final a = parseAnswer(
        'What is the address?',
        '{"answer": "Her address is 12 Mango Street.", "supported": true, "sources": ["s-1"]}',
        {'s-1'},
        turnText: turns,
      );
      expect(a.supported, isFalse);
      expect(a.answer, notMentioned);
      final yes = parseAnswer(
        'Do they use a notebook?',
        '{"answer": "Yes.", "supported": true, "sources": []}',
        {'s-1'},
        turnText: turns,
      );
      expect(yes.supported, isTrue); // a short answer uses the question words
      expect(yes.sources, ['s-1']);
    });
  });

  group('invented names', () {
    test('a capitalised word missing from the transcript marks the claim invented', () {
      const known = 'the launch is on the twelfth. Carlo prints them. Maria Jun';
      expect(inventsName('Maria confirms the launch is December 12th', known), isTrue);
      expect(inventsName('Carlo prints the posters', known), isFalse);
      expect(inventsName("Maria's launch is on the twelfth", known), isFalse);
      expect(inventsName('Jun asks about Manila', known), isTrue);
    });

    test('such a bullet or answer is dropped', () {
      const turns = {'s-1': 'the launch is on the twelfth'};
      expect(
        () => parseSummary(
          '{"bullets":[{"text":"The launch is in December","kind":"topic","sources":["s-1"]}]}',
          {'s-1'},
          turnText: turns,
          knownText: 'the launch is on the twelfth',
        ),
        throwsFormatException,
      );
      final a = parseAnswer(
        'When is the launch?',
        '{"answer": "The launch is on December twelfth.", "supported": true, "sources": ["s-1"]}',
        {'s-1'},
        turnText: turns,
        knownText: 'the launch is on the twelfth',
      );
      expect(a.supported, isFalse);
    });
  });

  group('summary parsing', () {
    final ids = {'s-0001', 's-0002', 's-0003'};

    test('valid output, uncited and unknown-source bullets are dropped, extras trimmed', () {
      final raw = '''{"bullets": [
        {"text": "They track orders in a notebook.", "kind": "topic", "who": null, "due": null, "sources": ["s-0001"]},
        {"text": "No citation here.", "kind": "topic", "who": null, "due": null, "sources": []},
        {"text": "Fake source.", "kind": "decision", "who": null, "due": null, "sources": ["s-9999"]},
        {"text": "Maria sends the deck.", "kind": "action", "who": "Maria", "due": "Friday", "sources": ["s-0002", "s-9999", "s-0003"]}
      ]}''';
      final bullets = parseSummary(raw, ids);
      expect(bullets.map((b) => b.text), ['They track orders in a notebook.', 'Maria sends the deck.']);
      expect(bullets.last.kind, BulletKind.action);
      expect(bullets.last.who, 'Maria');
      expect(bullets.last.due, 'Friday');
      expect(bullets.last.sources, ['s-0002', 's-0003']);
      expect(bullets.first.who, isNull);
    });

    test('who and due only survive on actions; em dashes are removed', () {
      final b = parseSummary(
        '{"bullets":[{"text":"Budget — tight","kind":"topic","who":"Sam","due":"Monday","sources":["s-0001"]}]}',
        ids,
      ).single;
      expect(b.text, 'Budget, tight');
      expect(b.who, isNull);
      expect(b.due, isNull);
    });

    test('nothing usable, or not JSON, throws', () {
      expect(() => parseSummary('{"bullets":[]}', ids), throwsFormatException);
      expect(() => parseSummary('sorry', ids), throwsFormatException);
    });

    test('grammar only allows the real segment ids', () {
      final g = summaryGrammar(['s-0001', 's-0002']);
      expect(g, contains(r'"\"s-0001\"" | "\"s-0002\""'));
    });
  });

  group('answer parsing', () {
    final ids = {'s-0001', 's-0002'};

    test('supported answer keeps text and valid sources, max 3 sentences', () {
      final a = parseAnswer(
        'When?',
        '{"answer": "Friday. By noon. At the office. Bring coffee.", "supported": true, "sources": ["s-0002", "s-0404"]}',
        ids,
      );
      expect(a.supported, isTrue);
      expect(a.answer, 'Friday. By noon. At the office.');
      expect(a.sources, ['s-0002']);
    });

    test('not mentioned: unsupported, no sources, or model claims support without a citation', () {
      for (final raw in [
        '{"answer": "$notMentioned", "supported": false, "sources": []}',
        '{"answer": "Maybe Tuesday.", "supported": false, "sources": ["s-0001"]}',
        '{"answer": "Maybe Tuesday.", "supported": true, "sources": []}',
        '{"answer": "Maybe Tuesday.", "supported": true, "sources": ["s-9999"]}',
        '{"answer": "Not mentioned anywhere", "supported": true, "sources": ["s-0001"]}',
      ]) {
        final a = parseAnswer('When?', raw, ids);
        expect(a.supported, isFalse, reason: raw);
        expect(a.answer, notMentioned);
        expect(a.sources, isEmpty);
      }
    });

    test('streamed JSON reveals the answer text as it grows', () {
      expect(partialAnswer('{"answ'), '');
      expect(partialAnswer('{"answer": "By Fri'), 'By Fri');
      expect(partialAnswer(r'{"answer": "Say \"hi\" now", "supp'), 'Say "hi" now');
    });

    test('suggested questions: exactly up to 3, deduped', () {
      expect(parseQuestions('{"questions": ["A?", "a?", "B?", "C?"]}'), ['A?', 'B?', 'C?']);
      expect(() => parseQuestions('{"questions": []}'), throwsFormatException);
    });
  });

  group('MeetingAiController', () {
    String? cleanFor(String t) => switch (t) {
      _ when t.startsWith('Honestly') =>
        'Honestly, is the paperwork? We track all our orders in a notebook. And things get lost.',
      _ => null,
    };

    FakeLlmEngine engineWith({String Function(String, Object?)? gen, String Function(String)? clean}) =>
        FakeLlmEngine(onGenerate: gen ?? (_, _) => '{}', onClean: clean ?? (t) => cleanFor(t) ?? t);

    test('polish merges, punctuates, and keeps both versions', () async {
      final engine = engineWith();
      final session = sessionWith(phoneRun);
      final ai = MeetingAiController(engine, session, autoRun: false);
      expect(ai.originalLines, hasLength(5));
      expect(ai.cleanTurns, hasLength(2));
      await ai.polish();
      expect(ai.state, MeetingAiState.done);
      final first = ai.cleanTurns.first;
      expect(first.status, TurnStatus.polished);
      expect(first.text, startsWith('Honestly, is the paperwork?'));
      expect(first.segmentIds, ['s-0001', 's-0002', 's-0003', 's-0004']);
      expect(ai.originalLines.first.text, 'Honestly...'); // original untouched
      expect(ai.cleanTurns.last.text, 'That sounds painful.'); // 3 words: rules only, no model call
      expect(engine.cleanCalls, hasLength(1));
    });

    test('a polish that changes a word is rejected and the original words stay', () async {
      final engine = engineWith(clean: (t) => 'Honestly, is the paperwork? We track all our orders in a binder. And things get lost.');
      final session = sessionWith(phoneRun);
      final ai = MeetingAiController(engine, session, autoRun: false);
      await ai.polish();
      expect(ai.cleanTurns.first.status, TurnStatus.kept);
      expect(ai.cleanTurns.first.text, ai.cleanTurns.first.rawText);
    });

    test('summary + suggestions run through the grammar path; summary cites real ids', () async {
      final engine = engineWith(
        gen: (prompt, grammar) {
          if ((grammar as String).contains('bullets')) {
            return '{"bullets": ['
                '{"text": "Orders are tracked in a notebook.", "kind": "topic", "who": null, "due": null, "sources": ["s-0001"]},'
                '{"text": "Invented.", "kind": "decision", "who": null, "due": null, "sources": ["s-0777"]},'
                '{"text": "Speaker 2 says that sounds painful.", "kind": "action", "who": "Speaker 2", "due": "[s-0001]", "sources": ["s-0001"]}]}';
          }
          return '{"questions": ["Who looks for a tool?", "What goes wrong?", "How are orders tracked?"]}';
        },
      );
      final session = sessionWith(phoneRun);
      final ai = MeetingAiController(engine, session, autoRun: false);
      await ai.runAll();
      expect(ai.state, MeetingAiState.done);
      expect(ai.summary!.bullets, hasLength(2));
      expect(ai.summary!.bullets.every((b) => b.sources.isNotEmpty), isTrue);
      // Citations come from the words, not from what the model claimed (it said s-0001 for both).
      expect(ai.summary!.bullets.first.sources, ['s-0001']); // notebook turn
      expect(ai.summary!.bullets.last.sources, ['s-0005']); // "That sounds painful."
      expect(ai.summary!.bullets.last.due, isNull); // "[s-0001]" is not a time
      expect(ai.suggestedQuestions, hasLength(3));
      // The transcript goes first and is identical for summary and suggestions (prompt cache).
      final prefix = engine.generateCalls.map((p) => p.substring(0, p.indexOf('</transcript>'))).toSet();
      expect(prefix, hasLength(1));
      expect(engine.generateCalls.first, contains('[s-0001] Speaker 1: Honestly, is the paperwork?'));
      expect(ai.turnOfSegment('s-0003')!.id, 's-0001');
    });

    test('Q&A: supported answer streams and cites; unsupported gives the exact fallback', () async {
      final engine = engineWith(
        gen: (prompt, grammar) => prompt.contains('Who is the CEO')
            ? '{"answer": "$notMentioned", "supported": false, "sources": []}'
            : '{"answer": "They use a notebook.", "supported": true, "sources": ["s-0001"]}',
      );
      final session = sessionWith(phoneRun);
      final ai = MeetingAiController(engine, session, autoRun: false);
      final streamed = <String>[];
      ai.addListener(() => streamed.add(ai.streamingAnswer));
      final yes = await ai.ask('How do they track orders?');
      expect(yes.supported, isTrue);
      expect(yes.answer, 'They use a notebook.');
      expect(yes.sources, ['s-0001']);
      expect(engine.lastRequestId, isNotNull);
      expect(streamed.any((s) => s.isNotEmpty && s != 'They use a notebook.'), isTrue); // partial text seen
      final no = await ai.ask('Who is the CEO?');
      expect(no.supported, isFalse);
      expect(no.answer, 'Not mentioned in the conversation.');
      expect(no.sources, isEmpty);
      expect(ai.answers, hasLength(2));
      expect(ai.streamingAnswer, '');
    });

    test('a model failure goes to the error state and the queue keeps working', () async {
      var fail = true;
      final engine = engineWith(
        gen: (p, g) {
          if (fail) throw const EngineException(EngineErrorCode.inferenceFailed, 'boom');
          return '{"answer": "A notebook.", "supported": true, "sources": ["s-0001"]}';
        },
      );
      final session = sessionWith(phoneRun);
      final ai = MeetingAiController(engine, session, autoRun: false);
      final a = await ai.ask('How?');
      expect(a.supported, isFalse);
      expect(ai.state, MeetingAiState.error);
      expect(ai.errorMessage, 'boom');
      fail = false;
      expect((await ai.ask('How?')).supported, isTrue);
      expect(ai.state, MeetingAiState.done);
    });

    test('model_missing during polish ends in error, original text intact', () async {
      final engine = engineWith(clean: (t) => throw const EngineException(EngineErrorCode.modelMissing, 'no model'));
      final session = sessionWith(phoneRun);
      final ai = MeetingAiController(engine, session, autoRun: false);
      await ai.runAll();
      expect(ai.state, MeetingAiState.error);
      expect(ai.summary, isNull);
      expect(ai.originalLines, hasLength(5));
    });

    test('editing: originals kept, edits marked, summary stale, Q&A sees edited text', () async {
      final engine = engineWith(
        gen: (p, g) => '{"answer": "ok", "supported": true, "sources": ["s-0003"]}',
      );
      final session = sessionWith([
        (1, 'Our client is Acme Logistix and they pay on Friday.', 0, 3000),
        (2, 'I will call Logistix on Monday.', 4000, 6000),
      ]);
      final ai = MeetingAiController(engine, session, autoRun: false);
      expect(ai.cleanTurns, hasLength(2));
      expect(ai.replaceAll('logistix', 'Logistics'), 2);
      expect(ai.originalLines.first.text, 'Our client is Acme Logistics and they pay on Friday.');
      expect(ai.originalLines.first.originalText, 'Our client is Acme Logistix and they pay on Friday.');
      expect(ai.originalLines.first.edited, isTrue);
      expect(ai.isEdited('s-0001'), isTrue);
      expect(ai.cleanTurns.first.rawText, contains('Logistics'));
      await ai.ask('Who is the client?');
      expect(engine.generateCalls.single, contains('Acme Logistics'));
      expect(engine.generateCalls.single, isNot(contains('Logistix')));
      expect(ai.editLine('s-0002', 'I will call them on Tuesday.'), isTrue);
      expect(ai.editLine('s-9999', 'x'), isFalse);
      expect(ai.editLine('s-0002', '   '), isFalse);
      ai.revertLine('s-0002');
      expect(ai.originalLines.last.text, 'I will call Logistix on Monday.');
      expect(ai.replaceAll('', 'x'), 0);
    });

    test('summary becomes stale after an edit; polishing again only redoes changed turns', () async {
      final engine = engineWith(
        gen: (p, g) => (g as String).contains('bullets')
            ? '{"bullets":[{"text":"Better way to track orders","kind":"topic","who":null,"due":null,"sources":["s-0001"]}]}'
            : '{"questions":["Q1?","Q2?","Q3?"]}',
        clean: (t) => '$t.',
      );
      final session = sessionWith([
        (1, 'we need a better way to track orders', 0, 3000),
        (2, 'yes the notebook keeps losing pages', 8000, 10000),
      ]);
      final ai = MeetingAiController(engine, session, autoRun: false);
      await ai.runAll();
      expect(engine.cleanCalls, hasLength(2));
      expect(ai.summaryStale, isFalse);
      ai.editLine('s-0002', 'yes the notebook keeps losing all pages');
      expect(ai.summaryStale, isTrue);
      await ai.polish();
      expect(engine.cleanCalls, hasLength(3)); // only the edited turn was sent again
    });

    test('changing a line\'s speaker after Stop re-merges and asks for a new polish', () async {
      final engine = engineWith(clean: (t) => '$t.');
      final session = sessionWith([
        (1, 'we need a better way to track orders', 0, 3000),
        (1, 'and the notebook keeps losing pages', 3500, 5500),
      ]);
      final ai = MeetingAiController(engine, session, autoRun: false);
      await ai.polish();
      expect(ai.cleanTurns, hasLength(1));
      expect(ai.needsPolish, isFalse);
      session.setLineSpeaker('s-0002', 2);
      await Future<void>.delayed(Duration.zero);
      expect(ai.cleanTurns, hasLength(2)); // different speakers no longer merge
      expect(ai.needsPolish, isTrue);
    });

    test('auto-run starts after Stop on a real session with the mock engine', () async {
      final mock = MockCaptionEngine(
        wordInterval: const Duration(milliseconds: 1),
        turnGap: const Duration(milliseconds: 1),
        llmDelay: const Duration(milliseconds: 1),
      );
      final session = SessionController(mock);
      final ai = MeetingAiController(mock, session);
      await session.init();
      await session.start();
      for (var i = 0; i < 400 && session.finals.length < MockCaptionEngine.script.length; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await session.stop();
      for (var i = 0; i < 200 && ai.state != MeetingAiState.error && ai.state != MeetingAiState.done; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      // Demo mode answers polish, summary and suggestions with rule-based stand-ins.
      expect(ai.state, MeetingAiState.done);
      expect(ai.cleanTurns, isNotEmpty);
      expect(ai.summary!.bullets, isNotEmpty);
      expect(ai.suggestedQuestions, hasLength(3));
      final a = await ai.ask('Who will send the deck by Friday?');
      expect(a.supported, isTrue);
      expect(a.sources, isNotEmpty);
      expect((await ai.ask('What is the weather?')).answer, notMentioned);
    });
  });
}
