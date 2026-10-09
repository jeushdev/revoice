// Minimal test screen for the clean transcript / summary / Q&A logic. NOT part of the product UI.
//
//   flutter run --release -t lib/main_ai_debug.dart -d <iphone>
//
// Needs no work from Jairus's screens. Record for real (Init, Start, talk, Stop) or tap
// "Load sample" for a scripted two-person conversation (it still does a 1 second Start/Stop,
// because the on-device LLM only runs while the engine is stopped).
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'package:flutter/material.dart';

import 'ai/meeting_ai_controller.dart';
import 'engine/caption_engine.dart';
import 'engine/mock_caption_engine.dart';
import 'engine/platform_caption_engine.dart';
import 'session/session_controller.dart';

void main() => runApp(const _DebugApp());

const _sample = <(int, String, int, int)>[
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

const _sampleQuestion = 'When will Jun send the demo?';

class _DebugApp extends StatelessWidget {
  const _DebugApp();

  @override
  Widget build(BuildContext context) => const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: _DebugPage(),
  );
}

class _DebugPage extends StatefulWidget {
  const _DebugPage();

  @override
  State<_DebugPage> createState() => _DebugPageState();
}

class _DebugPageState extends State<_DebugPage> {
  late final CaptionEngine engine = const bool.fromEnvironment('DEMO')
      ? MockCaptionEngine()
      : PlatformCaptionEngine();
  late final SessionController session = SessionController(engine);
  late final MeetingAiController ai = MeetingAiController(engine, session, autoRun: false);
  String note = '';

  @override
  void initState() {
    super.initState();
    session.init();
    session.addListener(_refresh);
    ai.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  Future<void> _loadSample() async {
    await session.start();
    await Future<void>.delayed(const Duration(seconds: 1));
    await session.stop();
    for (var i = 0; i < _sample.length; i++) {
      final (speaker, text, start, end) = _sample[i];
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
    session.rename(1, 'Maria');
    session.rename(2, 'Jun');
    ai.reset();
    setState(() => note = 'Sample loaded: ${_sample.length} lines.');
  }

  String get _output {
    final b = StringBuffer();
    b.writeln('engine: ${session.state?.name}   ai: ${ai.state.name}'
        '${ai.state == MeetingAiState.polishing ? ' ${ai.polishDone}/${ai.polishTotal}' : ''}');
    if (ai.errorMessage != null) b.writeln('ERROR: ${ai.errorMessage}');
    if (ai.timingsMs.isNotEmpty) b.writeln('timings ms: ${ai.timingsMs}');
    if (ai.transcriptTruncated) b.writeln('(transcript was too long; oldest turns left out)');
    b.writeln();
    b.writeln(ai.showClean ? '== CLEAN (${ai.cleanTurns.length} turns) ==' : '== ORIGINAL (${ai.originalLines.length} lines) ==');
    if (ai.showClean) {
      for (final t in ai.cleanTurns) {
        b.writeln('[${t.id}] ${session.displayName(t.speakerId)} (${t.status.name}, ${t.segmentIds.length} lines): ${t.text}');
      }
    } else {
      for (final l in ai.originalLines) {
        b.writeln('[${l.segmentId}] ${l.speakerName}: ${l.text}${l.edited ? '  (edited)' : ''}');
      }
    }
    final summary = ai.summary;
    if (summary != null) {
      b.writeln('\n== SUMMARY${ai.summaryStale ? ' (stale)' : ''} ==');
      for (final x in summary.bullets) {
        b.writeln('- [${x.kind.name}] ${x.text}'
            '${x.who != null ? '  who: ${x.who}' : ''}${x.due != null ? '  due: ${x.due}' : ''}'
            '  <- ${x.sources.join(', ')}');
      }
    }
    if (ai.suggestedQuestions.isNotEmpty) b.writeln('\nSuggested: ${ai.suggestedQuestions.join('  |  ')}');
    if (ai.streamingAnswer.isNotEmpty) b.writeln('\nanswering: ${ai.streamingAnswer}');
    for (final a in ai.answers) {
      b.writeln('\nQ: ${a.question}\nA: ${a.answer}  (supported=${a.supported}, sources: ${a.sources.join(', ')})');
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    Widget button(String label, VoidCallback? onTap) =>
        FilledButton.tonal(onPressed: onTap, child: Text(label));
    return Scaffold(
      appBar: AppBar(title: const Text('Meeting AI test')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                button('Start', session.start),
                button('Stop', session.stop),
                button('Load sample', _loadSample),
                button('Clean', ai.busy ? null : ai.polish),
                button('Summary', ai.busy ? null : ai.summarize),
                button('Ask', ai.busy ? null : () => ai.ask(_sampleQuestion)),
                button(ai.showClean ? 'Show Original' : 'Show Clean', () {
                  ai.showClean = !ai.showClean;
                  setState(() {});
                }),
                button('Edit s-0002', () => ai.editLine('s-0002', 'Sure, tell me about your shop.')),
                button('Facebook to Messenger', () => ai.replaceAll('Facebook', 'Messenger')),
              ],
            ),
            if (note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(note)),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: SelectableText(_output, style: const TextStyle(fontFamily: 'Menlo', fontSize: 12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    ai.dispose();
    session.dispose();
    super.dispose();
  }
}
