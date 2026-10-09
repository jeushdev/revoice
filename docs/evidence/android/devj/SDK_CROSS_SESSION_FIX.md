# Moonshine cross-session VAD isolation

October 10, 2026. **Core source fix prepared and desktop-tested; not adopted.**
User requested this correction before microphone integration. No app dependency,
capture implementation, model asset, device state, commit or publication changed.
The published core binaries and earlier JNI-only AARs still contain the defect.

## Source correction

`sdk-fix/0004-per-stream-vad-state.patch` targets the original revision,
`234f60faa0eb388b01cdf7e60aca232af37aefda`. It changes only the Silero and
VoiceActivityDetector `.cpp`/`.h` files, independently of patches 0001–0003.

- Each detector owns a zero-initialized `SileroVad::State`: 256 recurrent floats
  and 64 context samples. Prediction takes that state explicitly. The shared
  model/session has no recurrent, context or mutable input/output scratch buffers.
- New-session `start()` resets that detector's history, probability window,
  look-behind, pending remainder, segment audio/list, clock and transition flags.
  `assign`, not same-size `resize`, clears reused smoothing/look-behind vectors.
  Voice-end also clears look-behind, without resetting recurrent history.
- The retained shared model uses synchronized C++ local-static initialization,
  including retry after constructor failure. Existing prediction serialization
  remains. Resetting/starting B never resets A's history.
- Same-stream Pause remains **capture-only**: do not invoke VAD/SDK start or
  stop/start on resume. History survives gaps in feeding and ordinary updates.
  Stop-tail, diarization, silence-finalization and caption completion are unchanged.
- Constructor ORT failures throw and release partially acquired resources.
  Prediction checks statuses, releases input/partial-output tensors on every exit,
  and commits history/output values only after both outputs are accessible.
  Invalid chunk sizes fail before tensor creation; the reviewed path is hop 512
  at 16 kHz. Fixed exception messages contain no model paths or audio content.

Prediction failure is terminal for an app append: the detector's sample count
and look-behind may already have advanced before inference fails. Unchanged
recurrent history is **not** permission to retry/replay accepted audio. The
adapter still needs serialized feed/start/free lifecycle calls for each stream;
this patch does not repair free/in-flight races or make a detector thread-safe.

Patch SHA-256:
`7a923e21bfcbc18585c739dba4f83010c41e06f13cd1d8823ed632d2ab2420ce`.

| Patched file under `core/` | SHA-256 |
| --- | --- |
| `silero-vad.cpp` | `615888e25872171c5587746c2dd01da3ab0ba2c28a7a761e5495f87db2ddba62` |
| `silero-vad.h` | `4a854fe4a6dddc77f2ed5e0510f467a1311f8635b9ab0cb22f9a4233f0615637` |
| `voice-activity-detector.cpp` | `1857fdc48787653dc7032eb086ad0809c6145b1d61599c8419dd584045dff7e3` |
| `voice-activity-detector.h` | `7482c206c6fe1436eff4a6839d857daf1aa5937f45d37447707e7558fe30fd86` |

## Reproduction and actual checks

`core-inputs.json` separately pins the four original source files and five
supporting headers. Existing `inputs.json`, dependencies and patches 0001–0003
are unchanged. Four dependency headers (394,672 bytes total) were fetched from
the exact raw upstream revision; other inputs were already local. No repository
archive, model, toolchain or binary dependency was downloaded.

Prepare those files at their original relative paths and verify their hashes.
The runner is offline and never overwrites an existing run directory.

```powershell
python -B docs/evidence/android/devj/sdk-fix/review_core.py --source-root <pinned-source-root> --run-name cross-session-final-r2 --android-objects --mutations
```

For another machine use a **fresh** run name and explicit `--host-cxx`/`--ndk`.
The runner is Windows-oriented, like the JNI runner. Omit `--android-objects`
for host-only checks. NDK inputs are hash-verified before cross-compilation;
host tests use warnings-as-errors and libstdc++ assertions.

Actual final run exited 0:

- **10 host groups**: constructor/prediction faults and cleanup; 24 concurrent
  first-use constructors; new detector after another stream; 100 stop/start reuse
  cycles versus fresh detectors; interleaved independent streams versus isolated
  runs; restarting A while B continues; capture-gap continuity with a sub-hop
  accepted remainder; voice-end buffer clearing; propagated VAD inference errors.
- A separate fresh-process **singleton failure/retry** scenario passed.
- Three compiled negative mutations failed at the expected assertions: shared
  history, missing recurrent reset, and `resize` instead of buffer clearing.
- Both patched translation units built to Android/API26 **object files** for
  arm64-v8a, armeabi-v7a and x86_64 (six objects), with warnings-as-errors.
- The existing JNI runner passed again: **16 streaming-add scenarios, 403
  required-path cases, 10 Java groups** and JNI syntax checks for all three ABIs.
  `review.py` now explicitly selects patches 0001–0003; it cannot accidentally
  claim to include 0004 in a JNI-only rebuild.

Commands, input/output hashes and logs remain under
`%LOCALAPPDATA%/Temp/opencode/devj-moonshine-sdk-fix/cross-session-final-r2/` and
`cross-session-jni-regression-r1/`. Earlier runs are retained: host-r1 exposed a
missing transitive ORT EP header (now pinned), host-r2 passed before final fixture
expansion, and final-r1 timed out during the last object build. Final-r2 completed
all checks with a longer command timeout.

## Remaining gate before microphone integration

The subsequent [`full-core milestone`](SDK_FULL_CORE_REBUILD.md) records new
exact-revision source acquisition, real embedded-model verification and full
Android core/JNI linking. The limits below describe **this earlier fake-ORT
fixture milestone**; they are not a substitute for the subsequent real-inference
and error-propagation review.

Tests compile the **complete patched source files** with real pinned ORT API,
utility, resampler and debug headers, but substitute fake ORT/helper behavior and
a one-byte **test-only embedded-model header**. Android objects use that same
model stand-in. No real model inference, sanitizer, ART/GC, linked core library,
AAR repack, application build or device test ran. Never package the test header.

The locally available upstream tree is partial. A full pinned core/dependency
checkout and the real embedded Silero model are still needed to rebuild/link
`libmoonshine` for every ABI and check integration against the rest of the SDK.
Do **not** overlay these objects onto the published binary or claim the old
JNI-only AAR fixes cross-session state. The internal C++ class layout/signature
changed; rebuild its consumers together. No new deployable artifact/hash exists.

Then review combined patches 0001–0004, propagate core failures through the real
C API/JNI, validate repeated sessions with real inference, and retain the
Stop/Pause, one-provider, artifact identity/metadata, shrinker and separate device
approval gates. Optional Silero reload helpers and unrelated native paths remain
outside this fix. Source-level isolation is established by desktop fixtures;
production integration readiness is not.
