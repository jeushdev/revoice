# ReVoice

Offline live captions for face-to-face conversations, with speaker labels, a clean
transcript, an on-device summary and "Ask the meeting". All AI runs on the phone.
No network is used at runtime. Spec: [PRD.md](PRD.md). Submission details:
[SUBMISSION.md](SUBMISSION.md). Demo script: [DEMO.md](DEMO.md). UI hand-off notes:
[HANDOFF.md](HANDOFF.md).

## What it does

1. **Live captions** with speaker labels (Moonshine Small Streaming plus speaker identification).
   If the voices are not told apart, **Switch speaker** and **Auto** on the live screen set the label for new lines.
   Names typed before recording are passed to the speech model as key terms.
2. **Transcript**, Clean or Original. Clean merges fragments of one thought, removes um/uh and
   capitalises the first letter. It uses rules only (no model), and the original words are always kept.
3. **Summary** after Stop, written by the on-device LLM, with the speakers matched to the names you
   entered only when the conversation backs it up.
4. **Suggested questions and Ask.** Every suggested question is answered in the background first and shown only if
   the transcript supports the answer. Answers cite the lines they came from. A question the conversation
   cannot answer says "Not mentioned in this conversation."
5. **Library** of sessions with delete (removes everything the session holds).

CRM cards are no longer a product feature.

## Layout

| Path | What |
| --- | --- |
| `lib/engine/` | Platform contract: events, `CaptionEngine`, `PlatformCaptionEngine` (channels), `MockCaptionEngine` (scripted demo) |
| `lib/session/` | Session state, partial and final lines, speaker labels, name rules, live continuation of unfinished lines |
| `lib/summary/` | `SummaryController`: summary, speaker matching, suggested questions, Ask (the screens use this) |
| `lib/transcript/` | Merge rules, filler removal, word guard (pure Dart) |
| `lib/ai/` | `MeetingAiController` (Clean transcript, edits, cited summary and Q&A logic) and strict output parsing |
| `lib/app/`, `lib/ui/` | App state and screens |
| `ios/Runner/ReviseEnginePlugin.swift` | iOS channel handler |
| `ios-native/Revise/` | iOS engine: Moonshine capture and captions, llama.cpp runner, grammars |
| `ios-native/MacLlmTest/` | Mac command line tool that runs the real LLM code without a phone |
| `tool/` | `gen_llm_inputs.dart` (real prompts for the Mac tool), `set_ios_target.sh` |
| `android/` | Android shell (same channel contract) |

Channels: EventChannel `revise/captions` (native to Dart, one map per event, including `llm` token events)
and MethodChannel `revise/engine`: `init`, `start` (`language`, `keyterms`), `pause`, `resume`, `stop`,
`generate`, `cleanLine`. Error codes: `permission_denied`, `model_missing`, `capture_failed`,
`inference_failed`, `invalid_state`. The LLM only runs while the engine is stopped.

## Run

```sh
flutter pub get
flutter test
```

Settings has a **Sample data** switch. It replays a scripted meeting through the same events, so the UI works
without native code or a phone. Turn it off to use the native engine.

### iPhone (real models)

1. Get the models once (needs internet on the Mac, never on the phone): `sh ios-native/fetch-models.sh`.
   This fills `ios-native/Models/` (speech model, speaker models, `llm/qwen2.5-1.5b-instruct-q4_k_m.gguf`).
   The folder is not in git. The Runner bundles it, so the installed app needs no download.
2. Make sure `ios/Flutter/Target.xcconfig` says `FLUTTER_TARGET=lib/main.dart`
   (`tool/set_ios_target.sh main`).
3. Open `ios/Runner.xcworkspace` in Xcode, choose the phone, set the signing team, press Run.
   The Runner scheme's Run action is Release with Metal validation off (Debug is several times slower for the LLM).

If `flutter build ios` says "Application not configured for iOS", Xcode is not the active developer
directory: `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.

### Mac LLM check (no phone)

```sh
cd ios-native/MacLlmTest && swift build && cd ../..
E2E_LLM=1 flutter test test/e2e_mac_summary_test.dart   # real model, Mark/Anna script
```

## How the small model is kept honest

The on-device model is Qwen 2.5 1.5B Instruct (Q4_K_M). It is small, so the Dart side does not trust it:

- JSON grammars force every required key, and citations can only be real segment ids.
- Sources are recomputed from the words of each answer. An answer no line supports is "not mentioned".
- A capitalised name that nobody said makes an answer or summary bullet invalid.
- If none of a question's words appear in the conversation, the answer is "not mentioned" without asking the model.
- Summary sentences that are questions are dropped.
- A model-suggested speaker name is applied only with evidence in the transcript (self introduction or being addressed).
- Decoding is greedy. A failed decode is retried after clearing the cache, then with a rebuilt context.

## Known limitations

- Summaries from a 1.5B model can misattribute who did what, and rarely label anything as an action item.
- Live line grouping uses Moonshine's voice detector window (`vad_window_duration` 2.0 s, about 1.0 s of silence),
  so a line starts and ends about a second later than the default. Not yet measured on real speech.
- Sessions are kept in memory only. Closing the app loses the Library.
- Long conversations: summary and Ask read about the last 7000 characters (roughly 10 minutes of speech).
- English only.
