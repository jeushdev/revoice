# Moonshine required JNI paths: safety-fix follow-up

October 10, 2026. User approved **SDK fixes and desktop tests first**, with the
result returned for review before SDK adoption or microphone integration. Work
remains on `review/android-shell-devj-handoff`; no shared application code,
dependency, model, branch, installation or phone state was changed. No commit,
push, SDK publication or network acquisition was performed.

## Prepared change

`sdk-fix/0003-required-jni-path-safety.patch` applies **after** patches 0001 and
0002 to the original pinned source, commit
`234f60faa0eb388b01cdf7e60aca232af37aefda`. The existing patches and original
input manifest are unchanged. This is review-only source, not an adopted AAR.

- C-to-Java transcript conversion checks each class/member lookup, allocation,
  field write, array-region write and list insertion before another ordinary JNI
  operation. A pending Java exception is preserved, not cleared/replaced.
- Scoped JNI local frames reclaim temporary references on normal/error/C++ unwind
  paths, including per-line, speaker-span and word temporaries. Only the completed
  transcript is promoted out of the outer frame.
- Null native transcripts, inconsistent native pointer/count pairs and audio
  lengths that cannot fit `jsize` fail without dereferencing invalid buffers.
  Null text remains null; zero-length audio does not call SetFloatArrayRegion
  with a null native pointer. Successful text, signed speaker IDs and other
  metadata retain the existing conversion behavior.
- File loading acquires UTF characters with scope-bound ownership, copies option
  values into owned strings, and releases each acquired pointer on success,
  acquisition error or unwind. Option C pointers are built only after storage
  stops moving, avoiding short-string/vector relocation bugs. Per-option local
  frames keep JNI temporary references bounded for large option arrays.
- Null options/path retain their existing core-facing behavior. Null option
  entries/names/values are rejected rather than dereferenced.
- Required file-load and streaming-transcription entry points catch both standard
  and nonstandard C++ exceptions. Streaming transcription refuses entry with an
  already-pending Java exception. Their error logs contain only a fixed message,
  not exception text that could contain model paths or transcript data.

Patch SHA-256: `7b34bc02d35aa39dfb3658c04165701e3c674ae30349290648ce47d8721b4aab`.
Patched JNI source SHA-256:
`9d38d3d2f64ba6b19bccf49bd16c766566d0ccaf2e2580d4a9947f7180be70e8`.
Patched Java source remains
`5cbac694d2eba6e72f662921759340165dcbeacc03339f3ac1c23ee4ed3a2033`.
The prior candidate AAR hash does **not** identify this new patch; no new AAR was
linked or repacked in this milestone.

## Desktop evidence

`jni_required_path_test.cpp` compiles the **exact patched** guards, converter,
file-loader and streaming entry point extracted by `review.py`, using real JDK
JNI types/function table and fake operations/core. The fixture rejects ordinary
JNI/core calls while an exception is pending and checks UTF ownership, local-frame
balance, bounded references and successful field contents.

Actual run:

```powershell
python -B docs/evidence/android/devj/sdk-fix/review.py --run-name required-path-final-r2 --jni-syntax-check
```

- All three patches apply-check and apply against hash-verified inputs.
- Existing **16** streaming-add JNI scenarios pass.
- New **403** required-path cases pass, including injected exceptions at **18
  loader + 83 converter call sites**, null-without-exception lookups/allocations,
  non-null acquisitions accompanied by pending exceptions, core statuses and
  standard/nonstandard throws, null/empty/oversized native buffers, metadata
  preservation, 300 options/lines/spans/words, and 100 repeated fake load/convert
  cycles with caller-side result-reference disposal.
- Existing **10 Java test groups** pass, including all 512 Stop-ledger residues.
- The **whole patched JNI translation unit** passes NDK r28c/API26 syntax-only
  compilation with warnings-as-errors for arm64-v8a, armeabi-v7a and x86_64.
  Pinned NDK input hashes are verified first. This is not linking or ART loading.

Raw results/logs remain under
`%LOCALAPPDATA%/Temp/opencode/devj-moonshine-sdk-fix/required-path-final-r2/`.
The runner records the patch, fixture/stub-donor and runner hashes alongside
commands and pinned source/artifact/NDK hashes. The earlier final-r1 run also
passed, before adding those review-harness input hashes.
Initial `required-path-host-r1` failed test compilation on a fixture identifier
collision with libc `gets` and an incorrect signedness in the fake loader
signature; both fixture errors were corrected. `required-path-host-r2` passed
400 cases before the final three coverage additions. No failing run was removed.

These fixtures do **not** prove real allocation/GC behavior, leak-free SDK/core,
OOM recovery, native handle safety, audio recognition or device readiness.
Optional JNI paths (including Java-to-C test conversion, non-streaming audio,
memory loaders and TTS) remain outside this patch. UTF-8/modified-UTF-8 conversion
behavior is inherited, not redesigned. No C++ allocator fault injection or core
inference occurs in these tests.

## Second-session core review: still an open gate

Re-inspected the already-present pinned core source; no core source was patched.
Findings confirm that Java/JNI recreation or serialized app calls alone cannot
isolate sessions:

1. `voice-activity-detector.h:30–32` declares one static Silero instance.
   `voice-activity-detector.cpp:34–37` initializes it without the prediction mutex.
   The prediction mutex at lines 153–155 serializes calls but does not isolate
   state; constructor initialization also has a separate potential race.
2. `silero-vad.cpp:158–161` mutates that instance's recurrent state and audio
   context after each prediction. `VoiceActivityDetector::start()` resets neither.
   A new detector/session therefore inherits another stream's history.
3. `voice-activity-detector.cpp:55,57` uses `resize(size, 0)` on existing
   same-sized look-behind/probability vectors. This does **not** clear their old
   elements. The voice-end look-behind resize at line 197 also retains contents.

Inspected file hashes (supporting review inputs, not added to the JNI build):

| File under pinned `core/` | SHA-256 |
| --- | --- |
| `voice-activity-detector.cpp` | `8fab332566ed5b69e279dd0d6ab82921d5024070a7bb9730e1d4a4b4e023118d` |
| `voice-activity-detector.h` | `29c313f9a6592ae1c291953ffac9058294a809792d9d33d11469e83a6062f0ba` |
| `silero-vad.cpp` | `1fdf4f636a529a9a21f16a4124ce11a62f007bfddbfa4783a95089c13da1747e` |
| `silero-vad.h` | `9560c0c051d2d4a6be3f33ac7ba96949ae058bbf6676f3c710bb8e3627b9a50f` |

**Recommended separate core scope:** retain a safely initialized shared immutable
model/session only if supported, but give each stream its own recurrent state and
context, explicitly zero them and the smoothing/look-behind buffers at new-session
start, and test interleaved independent streams as well as reused/new detectors.
Same-stream Pause must not trigger these resets. A global reset per Start would
still corrupt another stream and is not the recommended fix. Core inference
failure propagation/resource cleanup also needs review before claiming safety.

Changing core behavior requires scoped source/dependency preparation, a core
rebuild and native tests, not merely another JNI-only AAR repack. That work is
not silently adopted or declared complete here.

## Next decisions

1. Review the new required-path patch and its limits before adopting an artifact.
2. Approve the separate second-session core-fix/rebuild scope, or explicitly bound
   any diagnostic experiment without claiming the issue resolved.
3. Retain the existing Stop/Pause, artifact identity/dependency graph, keep-rule,
   source/license and one-provider packaging gates in `SDK_FIX_PROPOSAL.md`.
4. Build/package approval and phone-install approval remain separate. Real mic
   capture, offline text, genuine Pause/Stop finals and repeated-session behavior
   have not been demonstrated.
