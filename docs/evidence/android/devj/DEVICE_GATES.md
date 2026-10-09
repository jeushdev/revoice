# devJ phone gates — all pending

Use only consenting development speakers reading synthetic fixtures; no customer
audio, persisted raw audio, transcript-bearing diagnostics or cloud inference.
Aggregate counters/timings only in evidence; sample text may be visually reviewed
on-device but not dumped via SDK logs. No uninstall or data clearing.

## Prerequisites to request

- [ ] devS/Jairus-approved integration commit containing the existing `jai-flutter`
  shell and minimal build/dependency setup; explicit devJ branch-update approval.
- [ ] Compatible existing Flutter/Dart (shell requires >=3.13.5, installed 3.13.2)
  and agreed JDK/SDK/wrapper configuration; no automatic install/upgrade.
- [ ] Review pinned SDK array lifetime/ignored statuses/sub-hop tail against
  resolved 0.1.5 artifact; approved resolution before production implementation.
- [ ] devS verified app-private STT/diarization directories + required notices and
  release manifest/build setup. Existing model binaries verified on desktop only.
- [ ] Connect/authorize intended Redmi Note 14 Pro 5G; explicit test-APK install
  approval and preservation strategy for existing `com.larpcode.revise` sessions.
  Instrumentation commands install APKs too; do not run them without approval.

## Minimal feasibility test after prerequisites

Record build commit, resolved Maven artifact hashes/ABIs, ten actual model hashes,
phone OS/build, CPU/ABI, **physical** RAM, free storage and page size. SDK source
declares minSdk 26 and arm64-v8a/armeabi-v7a/x86_64, not verified shipping AAR ABIs.

| Gate | Device action | Required evidence |
| --- | --- | --- |
| Local loading | Airplane mode, Wi-Fi off; explicit local directories, arch 2, identify_speakers=true | No fetch/helper/network use; Tiny text and nonempty speaker spans; missing/corrupt diarization fails visibly |
| Capture stop | Pause during speech, including a blocked read | Recording state inactive, capture thread joined, AudioRecord released before paused; no further accepted real PCM |
| Pause flush | Trial end-of-word, mid-phrase, <0.5 s pending real audio, empty/silent input | Accepted=drained real samples; actual complete callbacks, no outstanding partial, synthetic <=32768 @16 kHz; elapsed time/callback thread counts; no fake final |
| Same-stream resume | Same two speakers alternate before/after pauses of 1/10/60 s; repeat 10 pauses | No SDK stop/start on Pause; same stream/SDK IDs/registry, no prior transcript reset; returning voices' app IDs stable; quantify errors |
| Silence cap failure | Fixture/fake boundary remains incomplete at cap | Capture off, failure surfaced, no paused/success/final fabrication; native resources not closed under running call |
| Diarization lag | Several short turns then Pause under inference load | Measure missing/outdated spans at final; frozen app attribution remains unchanged even after later SDK corrections; no claimed final clustering drain on Pause |
| Stop residual | Speech <0.5 s since last update; aligned and unaligned tail sizes, including 1/511 samples; Stop mid-word | Check every accepted real sample accounted, verify reviewed padding if needed; actual trailing SDK final, once only; compare no-new-audio Stop path |
| Stop while paused | Pause/resume/Pause/Stop, repeat Stop | No mic restart; FIFO finals before stopped, one method completion, no duplicate finals |
| Identity/ambiguity | Two speakers, then four; overlap; fifth voice; short unknown turns | Stable known 1–4, unknown 0; signed SDK IDs handled; no index-based mapping, merge/reuse or longest-span guessing |
| Time mapping | Pause at known wall boundary; wait 10 s, resume; delay callbacks deliberately | Integer 0<=start<=end, paused wall time counted, synthetic end clamps to boundary; no timestamp drift after repeated pauses |
| Disposal/errors | Permission revocation/background/sink loss; second session after Stop | Actual mic shutdown, finalized text preserved, interrupted partial unconfirmed; no stale events or simultaneous STT/Gemma residency |
| Native lifetime | Repeated feeds and two full sessions, with SDK array issue resolved/under explicit diagnostic approval | Native/Java heap and GC/JNI observations, no growing pin/copy leak; do not call desktop stubs a leak test |

Do not pass M0 on live text alone. If silence cap cannot produce genuine finals
without resetting speaker state, stop at the plan gate and return the discrepancy
for an explicit revision. CRM/device release gates remain devS-owned, outside this
bounded task. No speed/quality/memory claims until actual measurements exist.
