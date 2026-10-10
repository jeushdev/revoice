# ReVoice submission notes

Team LarpCode, AppBuildersPH Hackathon 2026 (Local AI). Fill the items marked TODO before submitting.

## Why local AI

| Reason | ReVoice |
| --- | --- |
| Impossible with cloud-only | Works in airplane mode. No signal, captions and summary still work. |
| Private | No app-initiated upload of conversation audio or text. Audio never leaves the native layer; Dart only sees text. |
| Slow | No network round trip. |
| Expensive | No per-minute fees and no mobile data. |

## Models and runtimes (bundled, no download at runtime)

| Part | What | Notes |
| --- | --- | --- |
| Speech to text | Moonshine Voice Small Streaming, English | Swift package `moonshine-swift` 0.1.5. TODO confirm model license text. |
| Speaker identification | Moonshine diarization assets | Bundled in `ios-native/Models/diarization`. TODO confirm license text. |
| Language model | Qwen 2.5 1.5B Instruct, Q4_K_M GGUF (`qwen2.5-1.5b-instruct-q4_k_m.gguf`, about 1.1 GB) | Apache 2.0 per the Qwen model card. TODO include the notice. |
| LLM runtime | llama.cpp prebuilt XCFramework, release b11531 (Metal) | MIT. TODO include the notice. |
| App | Flutter, Dart, Swift | |

A Q8_0 variant of the same model was considered and not adopted (not tested; download too slow, and memory on the
iPhone 13 is tight). Decoding is greedy, so there is no temperature to tune.

## Network

None at runtime. Models are fetched once on the developer Mac by `ios-native/fetch-models.sh` and bundled
into the app. Missing assets show an error and never trigger a download. TODO: confirm with the airplane mode
run in DEMO.md; for Android, confirm the release manifest has no INTERNET permission.

## Existing code and assets

- Moonshine and llama.cpp packages as listed above.
- Mock engine and sample conversations are our own and are labelled "Demo / Sample data" in the app.
- TODO: list any SDK sample code that was reused.

## AI development tools used

- Claude Code (Anthropic) for the iOS native engine work, the meeting AI logic, tests and docs.
- TODO: the team lists every other tool used (for example Claude Design for the mockups, Codex, Copilot).

## What is real and what is not (disclosures)

- **Live capture:** real on device (Moonshine). Sample data mode is scripted and clearly labelled.
- **Summary, suggested questions and Ask:** real on device (Qwen 2.5 1.5B).
- **Clean transcript:** rule based, no model.
- **CRM cards:** not part of the product. The first PRD planned them; they were dropped.
- **Verified build:** TODO exact stage device and OS, measured caption latency, summary time, peak memory.
  Measured only on a Mac so far (Apple GPU, same model and code): summary about 4 to 6 s, one answer 0.4 to 1.7 s,
  polishing by model removed because it was too slow on the phone (53 s for 10 turns).
- **Limitations:** see the end of README.md (small model can misattribute, memory only Library, English only,
  voice detector window not yet measured on real speech, long conversations are truncated for the summary).
- **Optional features omitted:** post-Stop audio re-transcription, model polishing of the transcript (code kept behind a flag).

## Submission readiness checklist

- [ ] Official portal, timezone and rules re-confirmed (cutoff reported as 10:00 AM PHT on Oct 10, one submission).
- [ ] Demo video, about 1 minute, recorded in airplane mode (see DEMO.md).
- [ ] Post and tags (#AppBuildersPH) per the confirmed rules.
- [ ] Repository accessible to judges; PR from `zrs/ios` merged or the demo branch named.
- [ ] Model and SDK license notices included.
- [ ] Measured numbers above filled in on the stage phone.
