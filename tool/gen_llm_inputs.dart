// Builds the exact prompts/grammars the app sends to the LLM for a scripted two-person
// conversation, so ios-native/MacLlmTest can run them on the Mac ("steps" mode).
//
//   dart run tool/gen_llm_inputs.dart polish  <outDir>   -> <outDir>/manifest_polish.json
//   (run llmtest steps on it)
//   dart run tool/gen_llm_inputs.dart rest    <outDir>   -> <outDir>/manifest_rest.json
//
// "rest" reads the polish outputs, applies the same word guard the app uses, then writes the
// summary, suggested-question and Q&A steps. Pure Dart (no Flutter imports).
import 'dart:convert';
import 'dart:io';

import 'package:revise/ai/meeting_parsing.dart';
import 'package:revise/transcript/clean_transcript.dart';

const names = {1: 'Maria', 2: 'Jun'};

// (speaker, text, startMs, endMs), written the way Moonshine delivers them: fragments, fillers.
const script = <(int, String, int, int)>[
  (1, 'Hi Jun, thanks for making time.', 0, 2500),
  (2, 'Sure, so um tell me about your business.', 3000, 5500),
  (1, 'Honestly...', 6500, 7400),
  (1, 'Is the paperwork', 7700, 8800),
  (1, 'We track all our orders in a notebook.', 9200, 11500),
  (1, 'And things get lost.', 11900, 13000),
  (2, 'That sounds painful, how many orders a week?', 14500, 17000),
  (1, 'About forty, mostly from Facebook', 18000, 20000),
  (1, 'and uh some by text.', 20300, 21500),
  (2, 'Okay, I can set up a simple order tracker for you.', 23000, 26000),
  (2, "I'll send you a demo by next Friday.", 26500, 28500),
  (1, 'Great, I will share the price list with you on Monday.', 30000, 33000),
  (2, 'And the budget is around fifteen thousand pesos, right?', 34000, 37000),
  (1, 'Yes, that works for us.', 38000, 39500),
];

const questions = [
  'When will Jun send the demo?',
  "What is Maria's business address?",
  'Who shares the price list and when?',
];

List<Turn> turns() => mergeFragments([
  for (var i = 0; i < script.length; i++)
    MergeLine(
      id: 's-${(i + 1).toString().padLeft(4, '0')}',
      speakerId: script[i].$1,
      text: script[i].$2,
      tStartMs: script[i].$3,
      tEndMs: script[i].$4,
    ),
]);

void write(String path, String text) => File(path).writeAsStringSync(text);

void evaluate(String d) {
  final turnText = (jsonDecode(File('$d/turns.json').readAsStringSync()) as Map).cast<String, String>();
  final ids = turnText.keys.toSet();
  String out(String n) => File('$d/$n.out').readAsStringSync();
  print('SUMMARY');
  for (final b in parseSummary(out('summary'), ids, turnText: turnText)) {
    print('  - [${b.kind.name}] ${b.text}${b.who != null ? ' | who: ${b.who}' : ''}${b.due != null ? ' | due: ${b.due}' : ''}  <- ${b.sources.join(', ')}');
  }
  print('SUGGESTED: ${parseQuestions(out('suggest'))}');
  for (var i = 0; i < questions.length; i++) {
    final a = parseAnswer(questions[i], out('ask$i'), ids, turnText: turnText);
    print('Q: ${questions[i]}\n  A: ${a.answer}  supported=${a.supported}  <- ${a.sources.join(', ')}');
  }
}

void main(List<String> args) {
  final mode = args[0];
  if (mode == 'eval') return evaluate(Directory(args[1]).path);
  final dir = Directory(args[1])..createSync(recursive: true);
  final d = dir.path;
  final all = turns();

  if (mode == 'polish') {
    final steps = <Map<String, Object>>[];
    for (var i = 0; i < all.length; i++) {
      final input = stripFillers(all[i].hintedText);
      if (input.split(' ').length <= 3) continue; // the app skips these
      write('$d/polish_$i.txt', buildPolishPrompt(input));
      steps.add({
        'name': 'polish turn $i (${all[i].segmentIds.length} lines, ${all[i].rawText.length} chars)',
        'prompt': '$d/polish_$i.txt',
        'out': '$d/polish_$i.out',
        'maxTokens': (all[i].rawText.length ~/ 2).clamp(64, 400),
      });
    }
    write('$d/manifest_polish.json', jsonEncode({'steps': steps}));
    print('${all.length} turns from ${script.length} lines; ${steps.length} polish steps');
    return;
  }

  // mode == rest: apply the guard to what the model wrote, then build the transcript.
  var kept = 0;
  final lines = <String>[];
  final ids = <String>{};
  final turnText = <String, String>{};
  for (var i = 0; i < all.length; i++) {
    final f = File('$d/polish_$i.out');
    var text = all[i].rawText;
    if (f.existsSync()) {
      final candidate = sanitizeModelText(f.readAsStringSync());
      if (passesWordGuard(text, candidate)) {
        text = capitalizeFirst(candidate);
      } else {
        kept++;
        print('GUARD REJECTED turn $i:\n  raw : $text\n  model: $candidate');
      }
    } else {
      text = simplePolish(text);
    }
    lines.add('[${all[i].id}] ${names[all[i].speakerId]}: $text');
    ids.add(all[i].id);
    turnText[all[i].id] = text;
  }
  print('guard rejected $kept of ${all.length} turns');
  final transcript = lines.join('\n');
  write('$d/transcript.txt', transcript);
  write('$d/system.txt', meetingSystem);

  final steps = <Map<String, Object>>[];
  void step(String name, String task, String grammar, int maxTokens) {
    write('$d/$name.prompt', transcriptBlock(transcript) + task);
    write('$d/$name.gbnf', grammar);
    steps.add({
      'name': name,
      'prompt': '$d/$name.prompt',
      'grammar': '$d/$name.gbnf',
      'out': '$d/$name.out',
      'maxTokens': maxTokens,
    });
  }

  step('summary', summaryTask(), summaryGrammar(ids), 450);
  step('suggest', suggestTask(), questionsGrammar, 160);
  for (var i = 0; i < questions.length; i++) {
    step('ask$i', questionTask(questions[i]), answerGrammar(ids), 220);
  }
  write('$d/turns.json', jsonEncode(turnText));
  write('$d/manifest_rest.json', jsonEncode({'system': '$d/system.txt', 'steps': steps}));
}
