# ReVoice submission notes

Team LarpCode, AppBuildersPH Hackathon 2026 (Local AI). The current product overview and checklist disclosures are in [README.md](README.md). Remaining TODOs below are verification items, not claims of completed testing.

## Project and proof

- **Project:** ReVoice — offline live captions, speaker labels, transcripts, on-device summaries and conversation Q&A.
- **Team:** Jairus Macabuhay, Zairus Jay Opinion, Jeush (@jeushdev), Samuel Ordiales.
- **Repository:** https://github.com/jeushdev/revoice — working submission code on `main`, sourced from `zrs/ios`.
- **Demo video:** https://www.youtube.com/watch?v=KkFTXzSQAEE
- **LinkedIn submission post:** https://lnkd.in/p/g9My36rK
- **Screenshots:** [docs/screenshots](docs/screenshots), provided by the team. They show labeled Sample data mode, not proof of live model inference; some retain the former ReVise name.
- **Scope:** native iOS is the working implementation. Android native AI is unfinished; older Android branches are leftovers, not submission code.

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

No network is required for native iOS inference. Models are fetched once on the developer Mac by
`ios-native/fetch-models.sh` and bundled into the app. Missing assets show an error and never trigger a
download. Developer dependency/model downloads require internet; viewing the video/post also requires
internet. Copy/Share is user initiated, and the chosen destination may upload or sync exported text.
No hosted inference API, application backend, account or API key is required.
TODO: document the airplane-mode run with Sample data off from DEMO.md. Android is not a completed native-AI submission target.

## Existing code and assets

- Moonshine and llama.cpp packages as listed above.
- Mock engine and sample conversations are our own and are labelled "Demo / Sample data" in the app.
- Flutter packages include `share_plus`, `liquid_glass_renderer` and `cupertino_icons`; see `pubspec.lock` for resolved dependencies.
- Team-provided screenshots and repository app-icon/brand assets are used in the README.
- TODO: confirm any additional SDK sample-code reuse and include the required dependency/model notices before binary distribution.

## AI development tools used

- Claude Code (Anthropic) for the iOS native engine work, the meeting AI logic, tests and docs.
- OpenAI Codex and Claude Design, confirmed by the team.
- OpenCode; GPT-6.1 Sol (OpenAI) assisted with the submission README and repository cleanup.
- Development/design tools are not inference services used by the running app.

## What is real and what is not (disclosures)

- **Live capture:** native iOS uses Moonshine on device. Sample data mode is scripted, clearly labelled and on by default; turn it off to evaluate the real models.
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
- [x] Demo video URL supplied: https://www.youtube.com/watch?v=KkFTXzSQAEE
- [x] LinkedIn post URL supplied: https://lnkd.in/p/g9My36rK
- [x] Working `zrs/ios` implementation included on `main`.
- [ ] Airplane-mode real-model demonstration, post tags and official rules verified (see DEMO.md).
- [x] Repository made public and unauthenticated GitHub access verified for judges.
- [ ] Model and SDK license notices included.
- [ ] Measured numbers above filled in on the stage phone.
