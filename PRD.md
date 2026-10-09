# ReVise PRD

Oct 9, 2026 · @Jairus Macabuhay · Team LarpCode · AppBuildersPH Hackathon 2026 (Local AI)

## 1. Summary

**ReVise** is a phone app that live-captions face-to-face conversations. It labels who is speaking, switches the labels to real names when names come up, and ends with a final transcript plus an auto-generated CRM card for each named speaker. **All AI runs on the phone and works offline. The app uploads no audio or text; text leaves the app only when the user chooses Copy or Share.**

**Document status:** implementation specification reviewed on October 9, 2026. The Android model/runtime decision is approved: Moonshine Tiny Streaming with speaker identification, and Gemma 3 1B INT4 through LiteRT-LM. Device integration, performance, release compatibility, and submission disclosures still require the checks below; this document is not evidence of a working build. The product name and channel prefix are **ReVise** / `revise`; the checkout folder is `revoice`. See [the Android implementation plan](ANDROID_IMPLEMENTATION_PLAN.md) for the approved decisions, proposed files, milestones, and verification gates.

- **Goal:** secure (local only), available offline, reliable transcript.
- **Use cases:** meetings, classrooms, interviews, personal conversations.
- **Language:** English for v1. Taglish is a later improvement.
- **Demo platforms:** iPhone 14 Pro Max (reported iOS 27.0.1) and Redmi Note 14 Pro 5G (reported Android 16 and 16 GB RAM). Native owners verify actual OS versions and physical Android RAM before testing. Prioritize a small Android installation and memory footprint even on the reported 16 GB device. The stage demo uses whichever works best by 6 AM PHT on October 10.
- **Deadline:** team-reported submission cutoff is 10:00 AM on October 10, with one submission and no edits afterward. Jairus confirms the official portal, timezone, and current rules before submission; the timeline assumes PHT (UTC+8).

## 2. Why local AI (for the submission form)

| Reason | ReVise |
| :---- | :---- |
| Impossible with cloud-only | No signal, no captions. ReVise keeps working in airplane mode. |
| Private | No app-initiated upload of meeting, interview, or personal-conversation audio or text. Export is user initiated. |
| Slow | No network round trip. Caption latency depends on the device and must be measured. |
| Expensive | No per-minute transcription fees and no mobile data used. |

## 3. Team and ownership

| Person | Role | Machine | Owns |
| :---- | :---- | :---- | :---- |
| Jairus | Flutter UI + shared Dart logic | Windows | All screens, MockEngine, name-detection rules, transcript model, CRM prompt and JSON parsing, text export |
| Zairus | iOS native backend (Swift) | Mac | iOS module: mic, Moonshine, speaker IDs, on-device LLM for CRM, iOS builds |
| devJ (Jeush) | Android native backend (Kotlin) | Windows | Mic capture, Moonshine transcription/diarization, immutable caption events, speaker IDs and timestamps |
| devS (Sam) | Android native backend (Kotlin) | Windows | Gemma CRM inference, model assets, channel/controller integration, Android builds, README and disclosures |

**Rule:** native code does audio capture and AI inference. Flutter handles text display, name rules, prompts, validation, and local text storage. Audio never crosses into Dart.

**Android parallel workflow:** devS works on `devs/android-crm-assets`; devJ works on `devj/android-captions-speakers`. Both branch from and open PRs into `codex/kotlin-development`. devS owns the shared native channel/controller files; devJ supplies the capture/STT component and reviews its integration. See [ANDROID_WORK_SPLIT.md](ANDROID_WORK_SPLIT.md) for feature assignments, file ownership, handoffs, and merge gates. Flutter/Dart and iOS work retain the owners above.

| Android feature | devJ owns | devS owns |
| :---- | :---- | :---- |
| F1 live captions | Mic capture, bounded PCM queue, Moonshine STT/diarization, caption snapshots | Verified model assets and native channel/controller integration |
| F2 final transcript | Pause/Stop audio drain and SDK flush, immutable finals and timestamps | Final-event completion barrier, state/errors, STT release before CRM |
| F3 speaker labels | Stable session IDs 1–4, unknown=0, frozen final attribution | Preserve speaker fields through native channels |
| F4 CRM cards | Review the speech-to-CRM resource handoff | Gemma/LiteRT-LM, fresh conversations, 512-token output cap, timeout/cancellation and raw output |

Both developers work on the Android backend only. Each uses their own feature branch and submits a PR to `codex/kotlin-development`; the other reviews it. devJ owns the speech files and devS owns the shared controller/registration files, so their implementations can proceed simultaneously without editing the same files. Neither implementation is merged into `main` as part of this workflow.

## 4. Features (F1–F4 required; F2b optional)

### F1. Live English transcription

- Mic audio is transcribed live with **Moonshine Voice** (English, streaming).
- Partial text is shown in grey (`isFinal=false`) and replaced by final text in black (`isFinal=true`).
- Controls: Start, Pause, Resume, Stop. Adjustable caption text size.

### F2. Final transcript after the conversation

- After Stop, the app shows the full transcript with speaker names and timestamps.
- Saved on the device. Export as plain text (share or copy).
- Preserve final segment IDs, speaker IDs, original text, and session-relative timestamps. Store speaker names separately so renaming updates the transcript without altering its original words.
- No raw audio is saved. Keep transcripts and CRM cards in app-private storage and exclude them from automatic OS cloud backup. Clipboard and share destinations are controlled by the user and may send exported text elsewhere.
- A session with no final speech shows an empty transcript and does not generate CRM cards.

### F2b. Clean transcript (optional, after Stop)

- The same on-device LLM used for CRM cleans the final transcript, **one line at a time**:

  - removes fillers ("um", "uh", "like", repeated words)
  - fixes punctuation and capitalization
  - never adds, removes or changes meaning words
- A toggle switches between the **Clean** and **Original** view. The original is always kept.
- Live captions are **not** polished by an LLM. Live polish comes from Moonshine's own partial → final pass (grey → black).
- Use the optional `cleanLine` contract in section 7, with the prompt kept in Dart. Reject a candidate if token-level edit distance divided by the original token count exceeds 0.30 (case-insensitive, whitespace-tokenized comparison). Also reject changes to names, numbers, dates, or negations. These checks reduce risk but do not prove meaning preservation; the original remains authoritative.
- Timeline: built after F4 works, as a stretch before the 6 AM checkpoint.

### F3. Live subtitle labels that switch to real names

- Native code gives each voice a `speakerId` (Moonshine speaker identification). The UI shows `Speaker 1`, `Speaker 2`, and so on.
- Name detection (Dart, rule-based):

  - Self-introduction: "I'm X", "I am X", "my name is X", "this is X" → that speaker = X.
  - Called by name: "X, what do you think?" or a line starting or ending with "X?" → the **next different speaker** = X.
  - Extract candidate name tokens from these patterns, excluding stopwords. Matching must tolerate STT capitalization; capitalization alone does not establish identity.
- When a name is found, every past and future line from that speaker is relabeled.
- **Tap-to-rename** on any label as the manual fallback.
- Supports **2–4 speakers** per session.
- Apply name rules only to final segments. Normalize capitalization for matching; capitalized text alone is not enough to establish a name. Ambiguous matches leave the existing label unchanged.
- Called-by-name matching is a heuristic, not verified identity. Only the immediately following final turn from a different, known speaker is eligible; consume or discard the candidate after that turn. Do not replace a manually assigned name.
- Manual names take precedence over inferred names. Duplicate names do not merge speaker IDs. Keep unknown speakers labeled `Unknown`; disclose limitations for overlapping speech and more than four speakers.

### F4. Auto-CRM mapping after the conversation

- After Stop flushes and saves the transcript, the app automatically generates one CRM card per named speaker, using an **on-device LLM**, sequentially. Transcript viewing and export remain available while generation runs.
- Each field cites the transcript line(s) it came from. Empty fields stay empty, and the model must not guess.
- The user can edit a card. Cards are stored on the device, with text export.
- Show generation progress and a visible failure state per card. A **Retry CRM** button retries failed cards only; it does not overwrite successful or user-edited cards.
- If no speaker is named, explain that a name is needed. Naming a speaker on the stopped transcript makes that speaker eligible for automatic generation.
- Topics and commitments are populated only when explicitly stated. A conversation with no commitment must produce an empty commitments list.

## 5. Out of scope (v1)

- Taglish and Tagalog (later: swap Moonshine for Whisper behind the same contract)
- Translation
- Cloud sync, accounts, any network calls
- Speaker recognition across sessions (voice enrollment)
- PDF or vCard export

## 6. Architecture

```
[Mic] -> Native (Swift | Kotlin): audio capture -> Moonshine streaming STT -> speaker ID
            | EventChannel "revise/captions" (caption + state events)
            v
        Flutter (Dart): caption UI, name rules, transcript store, CRM screens
            | MethodChannel "revise/engine" (init, start, pause, resume, stop, generateCrm)
            v
        Native: on-device LLM -> CRM JSON
```

### Model choices per device

| Part | iPhone 14 Pro Max | Redmi Note 14 Pro 5G |
| :---- | :---- | :---- |
| Speech-to-text and speakers | Moonshine Voice Swift SDK (Small Streaming; Tiny if slow) | **Approved:** Moonshine Voice Android SDK, English **Tiny Streaming**, with bundled diarization assets |
| CRM LLM | llama.cpp or MLX Swift with Qwen 2.5 1.5B Instruct Q4 or Gemma 3 1B in a compatible format. **The iPhone 14 Pro Max is not eligible for Apple Intelligence.** | **Approved:** **Gemma 3 1B INT4**, `gemma3-1b-it-int4.litertlm`, through **LiteRT-LM Kotlin** |
| Fallback STT | whisper.cpp `base.en` | whisper.cpp `base.en` only after a failed Moonshine gate and an explicit plan revision |

The Android product choices are approved, but their compatibility and performance are unverified. Initial Android dependency pins are `ai.moonshine:moonshine-voice:0.1.5` and `com.google.ai.edge.litertlm:litertlm-android:0.18.0`; the implementation plan records the Gemma revision and checksum. Confirm these exact artifacts on the phone before integration. The iOS choices remain candidates owned by Zairus. Each native owner records the exact working runtime, SDK version, model revision, quantization, and license after an on-device spike. Record model size, peak memory, caption latency with speaker identification enabled, and CRM duration. Do not present an unmeasured speed or integration time as a guarantee. Changing the approved Android model family or shared contract requires a new decision, rather than an automatic fallback substitution.

Moonshine speaker identification requires separate diarization assets. Bundle the STT, diarization, and LLM assets in the demo installation and use local-file loaders; disable automatic SDK downloads. Missing assets must produce a visible error rather than trigger a network request. See the official sources in section 14.

### iPhone 14 Pro Max notes (no Apple on-device model)

- The iPhone 14 Pro Max is not eligible for Apple Intelligence, so use a separately bundled local LLM through **llama.cpp or MLX Swift**. Confirm runtime/model compatibility on the actual phone.
- **Memory:** after Stop flushes the final captions, release the STT and diarization models before loading the LLM. Apply the same sequential-loading policy on Android. Reload STT before a new recording session.
- **Integration:** start with the selected runtime's native example and validate the exact packaged model before connecting Flutter.
- **Valid JSON:** where supported, constrain output with a JSON grammar matching section 8. Still validate JSON structure, field types, and evidence in Dart; grammar constraints do not guarantee factual correctness.
- **App size:** measure the packaged assets and available device storage. Bundle every required asset for the demo, with no first-launch download step.

## 7. Platform contract (agree before coding)

### EventChannel `revise/captions` (native → Dart)

```json
[
  {"type":"caption","segmentId":"s-0012","text":"so the deadline is friday","speakerId":1,"isFinal":false,"tStartMs":41230,"tEndMs":43010},
  {"type":"state","state":"listening","message":null}
]
```

The array illustrates two separate event maps; native sends one map per event, not an array or a serialized JSON string.

- `state` values: `ready`, `listening`, `paused`, `stopped`, `error`.
- Partial events replace the whole current text for the same `segmentId`; text may shrink or change. The final event fixes text, timestamps, and speaker attribution, and that segment is never revised afterward. Ignore duplicate final events.
- **Approved v1 speaker policy:** Moonshine can revise speaker spans after its line-completed callback. The Android adapter snapshots the attribution when it emits the app's final caption and ignores later revisions for that segment. This may preserve an attribution error. Missing, ambiguous, overlapping, or multi-speaker attribution remains `speakerId=0`; it must not be guessed. Snapshot primitive values rather than retaining mutable SDK line objects. This policy preserves the shared channel contract and must be disclosed in the demo limitations.
- `speakerId` is a stable app-level integer within a session, starting at 1; `0` means unknown. Native adapters normalize SDK IDs into this convention and use unknown when attribution is unavailable.
- `segmentId` is unique within a session. Timestamps are integer milliseconds from session start, with `0 <= tStartMs <= tEndMs`; paused time remains part of elapsed session time. Display final segments in timestamp order.
- Only one session may be active. Clear mappings on a new session and prevent events from a stopped session from entering the new one.

### MethodChannel `revise/engine` (Dart → native)

| Method | Args | Returns |
| :---- | :---- | :---- |
| `init` | none | `{sttReady: bool, llmReady: bool}`; loads STT/diarization and checks bundled LLM assets without loading the LLM. `llmReady` means assets are present, not that inference has been verified. |
| `start` | `{language: "en"}` | `true` |
| `pause` / `resume` | none | `true` |
| `stop` | none | `true` after all pending segments are flushed as final and the `stopped` event is emitted |
| `generateCrm` | `{prompt: string, maxTokens: 512}` | `{json: string}` raw model output; Dart parses and validates it |
| `cleanLine` (stretch only) | `{text: string, prompt: string, maxTokens: 512}` | `{text: string}` candidate cleaned text; Dart applies F2b checks |

**Prompt, schema, and validation live in Dart (Jairus),** so both platforms use the same card structure and evidence rules. Different local models may produce different valid field values.

### Lifecycle and errors

- Dart subscribes before calling `init` and accepts both method results and events asynchronously. After `stop` returns, wait until the `stopped` event has been consumed before saving and generating CRM; channel callbacks can be delivered in a different order.
- Successful `init` emits `ready`. Missing STT/diarization assets prevent recording; a missing LLM may leave transcription available with `llmReady=false`, but CRM reports `model_missing`. After a recording error, re-run `init` before starting a new session and keep the interrupted session separate.
- `start` is allowed from `ready` or `stopped`, `pause` from `listening`, and `resume` from `paused`. `stop` is allowed while listening or paused; repeating Stop after stopping succeeds without duplicating segments. Reject other transitions with `invalid_state`.
- Pause stops audio capture and flushes pending speech before emitting `paused`; resume preserves the session and speaker mapping.
- `generateCrm` and `cleanLine` run only while stopped, one request at a time. Free the LLM before restarting recording. A CRM failure does not invalidate the saved transcript.
- Methods report failures through Flutter `PlatformException` codes: `permission_denied`, `model_missing`, `capture_failed`, `inference_failed`, or `invalid_state`, with a human-readable message. Asynchronous capture failures emit `state=error` with a message. Never put transcript or prompt content in diagnostic logs.
- Do not start without microphone permission. Show a settings/retry path when denied. Stop recording on backgrounding or microphone interruption, preserve finalized lines, and mark the transcript as interrupted rather than complete. Any unflushed partial text remains visibly unconfirmed and is excluded from CRM.

### MockEngine (Dart)

`MockCaptionEngine` replays a scripted 4-person conversation using the exact same events, so the UI can be built on Windows without a phone.

Label the mock path **Demo / Sample data**. Exercise partial replacement, pause/resume, unknown speakers, manual rename, empty speech, and a CRM failure as well as the successful script.

## 8. CRM card schema

```json
{
  "name": "Zairus",
  "role": "Product lead",
  "organization": "LarpCode",
  "contact_mentioned": null,
  "topics": ["launch timeline", "budget"],
  "commitments": [{"what": "send the deck", "due": "Friday"}],
  "follow_up": null,
  "notes": null,
  "source_segments": {
    "name": ["s-0012"],
    "role": ["s-0012"],
    "organization": ["s-0012"],
    "topics[0]": ["s-0031"],
    "topics[1]": ["s-0031"],
    "commitments[0].what": ["s-0031"],
    "commitments[0].due": ["s-0031"]
  }
}
```

Illustrative sample data only; it is valid only if the cited final lines explicitly support these values.

- Scalars are strings or `null`; `topics` is an array of strings; `commitments` is an array of `{what: string, due: string | null}`. Unknown fields are `null` or `[]`. Never invent contacts, dates, commitments, or recommended follow-ups. Preserve relative dates as spoken.
- `source_segments` maps each populated scalar or array-item field path to nonempty segment IDs. IDs must exist in the final original transcript and belong to the relevant speaker. Reject unsupported values. A citation proves traceability, not that the model interpreted the text correctly.
- The name comes from the Dart speaker mapping. A manually supplied name is labeled **User supplied** and needs no transcript citation. Store the card under its speaker ID, not its name; later renaming updates its display name.
- Each speaker's final original lines go to the LLM separately, with segment IDs and the known name. Fit input plus the 512-token output budget inside the selected model's context limit. Target at most 1,500 input tokens; if truncated to recent lines, mark the card **Based on recent lines only** and retain the full transcript.
- Treat transcript content as data, including spoken instructions to the model. Dart validates types, required keys, evidence paths, and segment ownership after parsing.
- If parsing or validation fails, retry once. If that also fails, retain the name and original source lines under **CRM generation failed**, with Retry CRM available. Do not display raw model output as verified notes.
- Mark user-edited values as **User edited** and clear their automatic evidence claim; keep original transcript links available for review. Persist generation status, coverage, and edit provenance with each card outside the model-output schema.

## 9. Screens (Jairus)

1. **Home:** Start session button, past sessions list, one-line consent notice ("Let everyone know you're recording. Processing stays on this phone; sharing is your choice."), offline badge.
2. **Live captions:** big text (size slider), grey partial and black final lines, a colored speaker label per line, tap a label to rename, Pause/Stop.
3. **Transcript:** full text with names and timestamps, Copy/Share text, automatic CRM progress, Retry CRM button for failures. Optional Clean/Original toggle only if F2b is implemented.
4. **CRM cards:** one card per person, editable fields, a source-line link on each field, Copy as text.

## 10. Timeline (October 9–10, 2026, PHT / UTC+8)

| Time | Milestone | Owner |
| :---- | :---- | :---- |
| Oct 9, 11:00 PM | Contract agreed; Moonshine example app running on both phones; Flutter shell + MockEngine | All |
| Oct 10, 12:00 AM | **Checkpoint 1:** live captions from Moonshine shown in Flutter on at least one phone | Zairus, Jeush, Jairus |
| Oct 10, 1:30 AM | Speaker IDs flowing; name rules working on mock data | Jeush, Zairus, Jairus |
| Oct 10, 3:00 AM | **Checkpoint 2:** F1–F3 working on both phones; LLM loads after STT is released | All |
| Oct 10, 5:00 AM | F4 CRM cards working on at least one phone | Sam, Zairus, Jairus |
| Oct 10, 6:00 AM | **Checkpoint 3 / feature freeze:** pick the stage phone; bug fixes only from here | All |
| Oct 10, 7:00 AM | **Demo build freeze.** README, disclosures, public-repo preparation | Sam, Jairus |
| Oct 10, 8:00 AM | Record the approximately 1-minute demo video in airplane mode; prepare the X/LinkedIn post, tags, and #AppBuildersPH per confirmed rules | Jairus |
| Oct 10, 9:00 AM | **Submit** (1-hour buffer), after confirming the official cutoff | Jairus |

Milestones are targets, not completed work. Publication, posting, and submission are team actions outside this document review.

## 11. Acceptance criteria (demo must pass)

- [ ] With airplane mode ON, a 2-person conversation shows live captions within about 1 second of speech.
- [ ] Measure first-visible-partial latency across at least 10 turns after models load, with diarization enabled; target median <= 1 second and record the slowest turn. Also exercise the supported 4-speaker case and record attribution errors.
- [ ] Lines are labeled by speaker; after "Hi, I'm Zairus", that speaker's lines show "Zairus".
- [ ] Partial text is replaced rather than appended, final segments appear once, and manual names survive subsequent automatic name matches.
- [ ] Stop produces a full transcript that can be copied as text.
- [ ] Pause/resume preserves the session; Stop while paused flushes correctly; a second session contains no events or names from the first.
- [ ] Stop automatically generates one CRM card per named speaker. Use a synthetic demo conversation with explicit topics and commitments; populated fields link to supporting original lines.
- [ ] A second fixture with no commitments or contacts leaves those fields empty. Unknown-speaker and unnamed-only sessions do not fabricate named cards.
- [ ] Invalid JSON, invalid evidence, and model failure trigger one automatic retry, then a visible failure state. Manual retry preserves successful and user-edited cards.
- [ ] A stopped session and edited CRM card survive app restart. Permission denial, empty speech, and microphone interruption show the specified states without losing finalized text.
- [ ] A fresh demo installation with bundled assets starts and completes captions plus CRM in airplane mode with Wi-Fi off. No automatic model fetch, analytics, or app network call occurs. Android's release merged manifest has no INTERNET permission; iOS is checked through runtime/network inspection because it has no equivalent general network permission.
- [ ] Record exact stage-device OS, model/runtime versions, peak memory, and CRM duration; repeat a complete session to check unloading/reloading. Demo claims match the measured build.
- [ ] If F2b ships, Original stays intact and cleaning failures or rejected candidates display the original line. CRM citations always refer to Original.

## 12. Risks and fallbacks

| Risk | Fallback |
| :---- | :---- |
| Moonshine SDK integration fails on a platform | Report the failed gate; propose whisper.cpp `base.en` behind the same contract. Android substitution needs an explicit plan revision; diarization needs a separate working path or the disclosed manual-speaker fallback. |
| Speaker IDs unreliable | Tap-to-rename plus a manual "next speaker" button; Dart assigns an explicit speaker override from the next segment onward. This is a disclosed degraded mode, not a pass for automatic speaker labeling. |
| Android Gemma too slow, inaccurate, or crashes | First measure CPU execution, bounded context/output, and sequential model loading with the approved Gemma 3 1B INT4 file. Report a failed gate before proposing a different model/runtime. Rule-based CRM is a disclosed degraded mode and does not pass F4's on-device LLM criterion. |
| iOS LLM too slow or crashes | Zairus may evaluate the listed smaller compatible candidates; record the exact working selection and limitations. |
| SDK/model license or redistribution requirements unclear | Check the license for each pinned SDK and every bundled STT, diarization, and LLM asset; include required notices and disclose them before distribution |
| Only one platform works | Demo that one; mention the other as "in progress" |

## 13. Submission disclosures (Sam to fill in)

- **Models:** Android Moonshine English Tiny Streaming plus diarization assets, Android Gemma 3 1B INT4, the exact iOS selections, and any approved fallback actually used. Record revisions and checksums.
- **Frameworks:** Flutter, Moonshine SDKs, llama.cpp / MLX / LiteRT-LM.
- **APIs and cloud:** none at runtime. Internet is used during development to obtain model assets; the demo installation includes them and needs no first-run download.
- **Existing code and assets:** list any SDK sample code reused.
- **AI dev tools:** list every one used (Claude, Devin, Copilot, etc.).
- **Verified build and limitations:** exact device/OS, measured performance, degraded/manual features, optional features omitted, and any truncated CRM input. Disclose mock/sample data separately from live capture.
- **Submission readiness:** confirm the current official portal and rules, required links/video/post, model notices, repository accessibility, and final artifacts. This checklist remains pending until Sam and Jairus fill it in.

## 14. Technical references and readiness gates

Official sources checked during this review on October 9, 2026:

- [Moonshine Voice repository and license](https://github.com/moonshine-ai/moonshine): platform support and SDK/model licensing. Pin the exact version used.
- [Moonshine diarization assets](https://github.com/moonshine-ai/moonshine/blob/main/docs/diarization-models.md): speaker identification requires separate assets; some high-level loaders automatically fetch them.
- [Apple Intelligence device requirements](https://support.apple.com/en-us/121115): the iPhone 14 Pro Max is not eligible.
- [Gemma 3 1B deployment files](https://huggingface.co/litert-community/Gemma3-1B-IT/tree/main) and [LiteRT-LM Kotlin API](https://github.com/google-ai-edge/LiteRT-LM/blob/v0.18.0/docs/api/kotlin/getting_started.md): approved Android model/runtime; compatibility and speed still require the device spike.
- [Moonshine transcription events](https://github.com/moonshine-ai/moonshine/blob/v0.1.5/docs/using/transcription.md): speaker spans can change after line completion; the approved adapter freezes app-final attribution.
- [llama.cpp grammars](https://github.com/ggml-org/llama.cpp/blob/master/grammars/README.md): constrained JSON generation; Dart still validates the content.

**Ready to implement:** required feature scope, team ownership, automatic CRM behavior, shared contract, field evidence, failure paths, and verification criteria are defined. Native owners must confirm the SDK adapter and pin a compatible model/runtime before integrating that path. **Ready to demo or submit:** only after section 11 passes on the selected stage phone and section 13 is completed. Official event requirements are not independently verified by this document review.
