# HANDOFF for Jairus: clean transcript, summary, Ask the meeting

Logic only. No screen was changed. Everything below hangs off one object, `MeetingAiController`
(`lib/ai/meeting_ai_controller.dart`). It is a `ChangeNotifier`: wrap your widgets in
`ListenableBuilder(listenable: ai, ...)` and read its fields.

## Wiring (3 lines)

```dart
final session = SessionController(engine);                 // you already have this
final ai = MeetingAiController(engine, session);           // NEW: create it next to the session
// ... pass `ai` to the transcript screen. Call ai.dispose() when you dispose the session.
```

Create it **before** the user taps Stop (for example right where `LiveScreen` gets its `session`).
It watches `session.state`; when the session becomes `stopped` it starts by itself:
polish, then summary, then 3 suggested questions. A new `Start` resets it. Pass
`autoRun: false` if you would rather call `ai.runAll()` yourself.

`engine` can be `MockCaptionEngine` (Demo mode): it now answers polish, summary, suggestions and
Q&A with simple stand-ins built from the transcript, so you can build every state without a phone.

## States

`ai.state` is a `MeetingAiState`:

| state | meaning | what to show |
| --- | --- | --- |
| `idle` | nothing has run yet (before Stop) | nothing |
| `polishing` | merging done, LLM is punctuating turns. `ai.polishDone` of `ai.polishTotal` | "Polishing transcript..." |
| `summarizing` | writing the summary and suggested questions | summary skeleton |
| `answering` | an `ask()` is running. `ai.streamingAnswer` fills in as it is written (iOS) | typing text |
| `done` | everything requested has finished | content |
| `error` | `ai.errorMessage` says why. The original lines are always still there | message and a retry button |

One LLM request runs at a time. If you call `ask()` while it is polishing, it waits its turn
(state shows what is running right now).

## API

| member | type | notes |
| --- | --- | --- |
| `state` | `MeetingAiState` | see above |
| `errorMessage` | `String?` | set when `state == error` |
| `showClean` / `setShowClean(bool)` | `bool` / method | the Clean / Original toggle |
| `originalLines` | `List<TranscriptLine>` | Original view. `segmentId`, `speakerId`, `speakerName`, `text` (with edits), `originalText`, `edited`, `tStartMs` |
| `cleanTurns` | `List<Turn>` | Clean view. `id`, `speakerId`, `text` (clean once polished), `rawText`, `segmentIds`, `status` (`raw` / `polished` / `kept`), `tStartMs`, `tEndMs` |
| `turnOfSegment(id)` | `Turn?` | the turn that contains a segment id (for scrolling to a source) |
| `needsPolish` | `bool` | some turns are not punctuated yet (after edits or a speaker change). Call `polish()` |
| `summary` | `MeetingSummary?` | `.bullets` is `List<SummaryBullet>`: `text`, `kind` (`topic` / `decision` / `action`), `who?`, `due?`, `sources` (segment ids, never empty) |
| `summaryStale` | `bool` | lines were edited or a speaker changed after the summary was made. Offer "Refresh" -> `summarize()` |
| `suggestedQuestions` | `List<String>` | up to 3, after the summary |
| `answers` | `List<MeetingAnswer>` | every question so far: `question`, `answer`, `sources`, `supported` |
| `streamingAnswer` | `String` | the answer being written right now, empty otherwise |
| `timingsMs` | `Map<String,int>` | `polish`, `summary`, `suggest`, `answer` (debug) |
| `transcriptTruncated` | `bool` | transcript was too long (about 8000 chars, roughly 10 minutes of speech); the oldest turns were left out of summary and Q&A only |
| `runAll()` | `Future<void>` | polish, then summary and suggestions |
| `polish()` / `summarize()` | `Future<void>` | one step, redoes only what is missing or stale |
| `ask(String)` | `Future<MeetingAnswer>` | answer only from the transcript. Not in the transcript gives exactly `"Not mentioned in the conversation."` with `supported == false` and no sources (`notMentioned` constant) |
| `editLine(segmentId, newText)` | `bool` | keeps the original, marks the line edited |
| `revertLine(segmentId)` / `isEdited(id)` | | undo one edit / check |
| `replaceAll(from, to)` | `int` | case-insensitive, whole words; returns how many lines changed |
| `reset()` | | forget everything (also automatic on a new Start) |

Streams to listen to: only `ai` itself (the `ChangeNotifier`). Token streaming from the LLM is
already turned into `ai.streamingAnswer`; you do not need the engine's `LlmTokenEvent`.

Rules baked in (so the UI does not need to repeat them):

- Original words are never rewritten. `Turn.rawText` and `TranscriptLine.originalText` always keep them.
- A punctuated turn is accepted only if its words match the originals (ignoring punctuation,
  capitals and um/uh). Otherwise `status == kept` and `text == rawText`.
- Summary bullets without a real citation are dropped. Citations are found from the words of each
  bullet (not from what the model says), and they are always the first segment id of a turn.
- No dashes (em or en) in any generated text.

## Copy-paste examples

All four assume `ai` (a `MeetingAiController`) and `session` are in scope.

### 1. "Polishing transcript..." loading state

```dart
ListenableBuilder(
  listenable: ai,
  builder: (context, _) {
    if (ai.state == MeetingAiState.polishing) {
      return Row(children: [
        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 8),
        Text('Polishing transcript... ${ai.polishDone} of ${ai.polishTotal}'),
      ]);
    }
    return const SizedBox.shrink();
  },
)
```

### 2. Clean / Original toggle

```dart
ListenableBuilder(
  listenable: ai,
  builder: (context, _) => Column(children: [
    SegmentedButton<bool>(
      segments: const [
        ButtonSegment(value: true, label: Text('Clean')),
        ButtonSegment(value: false, label: Text('Original')),
      ],
      selected: {ai.showClean},
      onSelectionChanged: (v) => ai.setShowClean(v.first),
    ),
    if (ai.showClean)
      for (final turn in ai.cleanTurns)
        ListTile(title: Text(session.displayName(turn.speakerId)), subtitle: Text(turn.text))
    else
      for (final line in ai.originalLines)
        ListTile(
          title: Text(line.speakerName),
          subtitle: Text(line.text),
          trailing: line.edited ? const Text('edited') : null,
        ),
  ]),
)
```

### 3. Summary bullets with tappable sources

```dart
ListenableBuilder(
  listenable: ai,
  builder: (context, _) {
    final summary = ai.summary;
    if (summary == null) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (ai.summaryStale) TextButton(onPressed: ai.summarize, child: const Text('Refresh summary')),
      for (final b in summary.bullets)
        ListTile(
          title: Text(b.text),
          subtitle: Text([
            b.kind.name,
            if (b.who != null) b.who!,
            if (b.due != null) 'due ${b.due}',
          ].join(' | ')),
          trailing: Wrap(children: [
            for (final id in b.sources)
              ActionChip(
                label: const Text('source'),
                onPressed: () {
                  final turn = ai.turnOfSegment(id);   // scroll your transcript list to this turn
                  debugPrint('jump to ${turn?.id}');
                },
              ),
          ]),
        ),
    ]);
  },
)
```

### 4. Ask box + suggested question chips

```dart
class AskBox extends StatefulWidget {
  const AskBox({super.key, required this.ai});
  final MeetingAiController ai;
  @override
  State<AskBox> createState() => _AskBoxState();
}

class _AskBoxState extends State<AskBox> {
  final controller = TextEditingController();

  void _ask(String q) {
    if (q.trim().isEmpty) return;
    widget.ai.ask(q);
    controller.clear();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.ai,
    builder: (context, _) => Column(children: [
      Wrap(spacing: 8, children: [
        for (final q in widget.ai.suggestedQuestions)
          ActionChip(label: Text(q), onPressed: widget.ai.busy ? null : () => _ask(q)),
      ]),
      TextField(
        controller: controller,
        enabled: !widget.ai.busy,
        decoration: const InputDecoration(hintText: 'Ask about the meeting'),
        onSubmitted: _ask,
      ),
      if (widget.ai.streamingAnswer.isNotEmpty) Text(widget.ai.streamingAnswer),
      for (final a in widget.ai.answers.reversed)
        ListTile(
          title: Text(a.question),
          subtitle: Text(a.answer),            // "Not mentioned in the conversation." when !a.supported
          trailing: a.supported ? Text('${a.sources.length} source(s)') : null,
        ),
    ]),
  );
}
```

## Things you need to know

- **CRM is off.** Nothing generates CRM cards after Stop any more. `LiveScreen._stop()` still calls
  `crm.generateMissing()`; it is now a no-op unless `CrmController.autoGenerate = true` (default
  false) or you pass `force: true`. The CRM code is untouched. The CRM Retry button still works.
- **Speaker fixes after Stop** (tap a line, Switch speaker, suggestions on/off) change how lines
  merge. The controller notices: `cleanTurns` is re-merged, `summaryStale` turns true and
  `needsPolish` turns true. Offer a button that calls `ai.polish()` then `ai.summarize()`.
- **Timing.** Polishing is one short LLM call per merged turn; on a Mac it is about 0.2 s per
  turn, on the phone expect several times that. Show the progress text. The summary is the slow
  step (about 215 tokens written).
- **The LLM only runs while the engine is stopped.** Calling `ask()` during recording returns
  "not mentioned" and sets `state == error` ("not allowed while listening").
- **Language:** English only.
- **Test screen without your UI:** `flutter run --release -t lib/main_ai_debug.dart -d <iphone>`
  (buttons: Start, Stop, Load sample, Clean, Summary, Ask, Show Original/Clean, Edit, Replace).
  Add `--dart-define=DEMO=true` to use the mock engine.

## Dart files changed or added

Added:
- `lib/ai/meeting_ai_controller.dart` (the controller above)
- `lib/ai/meeting_parsing.dart` (prompts, grammars, strict parsing of summary / answers)
- `lib/transcript/clean_transcript.dart` (merging, filler removal, word guard)
- `lib/main_ai_debug.dart` (test screen, not part of the app)
- `tool/gen_llm_inputs.dart` (builds real prompts for the Mac LLM test tool)
- `test/meeting_ai_test.dart`

Changed (none are screens or widgets):
- `lib/crm/crm_controller.dart` (`autoGenerate` flag, off)
- `lib/engine/caption_engine.dart`, `platform_caption_engine.dart` (`generate(requestId:)`)
- `lib/engine/engine_events.dart` (new `LlmTokenEvent`)
- `lib/engine/mock_caption_engine.dart` (demo stand-ins for summary / Q&A)
- `lib/session/session_controller.dart` (ignores `LlmTokenEvent`; `debugAddFinal` test helper)
- `test/session_flow_test.dart`, `test/screens_smoke_test.dart` (call `generateMissing(force: true)`)
- `test/manual_speaker_test.dart` (fake engine got the new `requestId` parameter)

Swift: `ios-native/Revise/ReviseEngine.swift` (two Moonshine options for line grouping),
`ios-native/MacLlmTest/Sources/llmtest/main.swift` (new `steps` mode).
