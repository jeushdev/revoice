# Moonshine 0.1.5: published Android artifact review

October 10, 2026 (PHT; HTTP server date October 9 UTC). **SDK gate remains blocked;
M0 is not passed.** Review performed in the original checkout on
`devj/android-captions-speakers`. Only this evidence document is added. No branch
switch, production adapter, pin change, SDK build, tool installation, staging,
commit, model download, ADB command, phone access or deployment.

## Decision summary

The suspected defects are **not merely differences in tag source**:

| Finding | Published-artifact evidence | Consequence / remaining gate |
| --- | --- | --- |
| Discarded start/add/stop statuses | **Confirmed Java binary:** each JNI integer result is immediately `pop`ped in AAR `Transcriber.class`. Published sources match tag. | A checked wrapper is required; catching exceptions around stock `Transcriber` is insufficient. |
| Missing `ReleaseFloatArrayElements` | **Confirmed JNI binary:** reviewed streaming-add function in all three packaged ABIs acquires array elements, calls core, returns without release; exception path also lacks release. | Stock artifact is not acceptable for production streaming. ART copying/pinning, growth and practical severity are **not measured**. |
| Sub-hop Stop tail | **Confirmed arm64 core binary mechanism:** complete-hop loop retains short remainder; flush closes existing segment without processing/padding that remainder. Stop/transcribe routes to this flush. | With the pinned 512 hop, 0–511 internal 16 kHz samples can remain outside VAD analysis. Actual recognition impact is unmeasured. Approve/test padding or a reviewed core fix. Other core ABIs not audited for this behavior. |
| Pause update throttle | **Confirmed Java binary and fake-JNI test:** adaptive gate can reach 5 s at default 0.5 s, hiding the proposed 2.048 s silence budget. | Explicit checked pass scheduling/gate bypass is needed; requesting a pass is not finalization. |
| Silence-finalization / same-stream speaker continuity | Arm64 VAD disassembly corroborates model probability averaging and threshold transitions, not a fixed silence timer. | No unconditional bound or successful same-stream Pause proven. Silero-on-zeros, pending unseen speech, diarization backlog, frozen spans, timestamps and repeated Pause still require authorized device tests. |

**Safe next step:** devS/Jeush choose a reviewed SDK resolution below. Desktop
shell/toolchain/asset preparation may continue independently, but do not resume
production capture implementation or call M0 cleared. The powered-off Redmi
remains untouched. Phone feasibility can resume only after the SDK resolution is
approved and separately authorized deployment/device access becomes available.

## Publisher artifacts and identity

Authoritative repository:
`https://repo.maven.apache.org/maven2/ai/moonshine/moonshine-voice/`.
Checked directory listing and HTTP HEAD **before downloading**. AAR is
24,321,396 bytes (~23.2 MiB), not a model bundle or a full SDK/toolchain.
Downloaded only the following files into
`C:\Users\jeush\AppData\Local\Temp\opencode\devj-sdk-artifact-review` (`R` below).
Each versioned file's computed SHA-256 matches its Maven `.sha256` sidecar;
AAR/source identities also match Gradle module metadata. This is checksum
verification over HTTPS, **not independent publisher-signature verification**.

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| `maven-metadata.xml` | 1,287 | `b5d1c3b89fc70bfbed70bb45b37960c2ab49c8ccb35e67d11bfed98414374cf0` |
| `moonshine-voice-0.1.5.pom` | 2,308 | `7d3139c1bf92df6892bbb4e393d50712863179c3df04d4c2978fd485d45154e4` |
| `moonshine-voice-0.1.5.module` | 4,219 | `7346e15215a5def7763c665b1679c8888fc1e781eac122f7d5df6010a60ce184` |
| `moonshine-voice-0.1.5-sources.jar` | 68,388 | `b2a5a53dff132acdddf4f481f8a7f75b49168637f9a4efef8e49faf091ccba63` |
| `moonshine-voice-0.1.5.aar` | 24,321,396 | `ee2d95c21150683c743db8f3aef66281fd5408bcefc94be3ca1d2545ada1f571` |

Metadata reports latest/release **0.1.5**, lastUpdated `20260824210140`.
POM/module coordinates are `ai.moonshine:moonshine-voice:0.1.5`, packaging AAR;
module publisher Gradle **8.13**. POM SCM URL does **not** identify a source commit.
Published source JAR contains Java, not JNI/core C++ or a native source/build map.
The seven Java files in existing `source-pins.json` match the published source
JAR **byte-for-byte**, including `Transcriber.java` SHA-256
`2f8e8f1545eb950790f5aa5c408f18b26b3908a17df7721954582b4b4b1c7e15`.
This does not establish whole-native-library reproducibility from the tag.

AAR `classes.jar`: 103,888 bytes, SHA-256
`8df6b3dbec3010159fdeffd4c19715b48703c67c62170e169d194074f26b8b10`.
`Transcriber.class`: SHA-256
`8079321e2b8d3a349cf146825c73e4ec7331211331016dc8bcbe7c197873dfcb`.

Packaged ABI inventory (all contain JNI, Moonshine core and ONNX Runtime):

| ABI / file | Bytes | SHA-256 |
| --- | ---: | --- |
| arm64-v8a / `libmoonshine-jni.so` | 104,520 | `08f81c6f173df3929a5a4977db7fa8488358038dafdadd3ac0b17df233f2d357` |
| arm64-v8a / `libmoonshine.so` | 11,112,456 | `922eddb6a0316f94091f40c5304db152e1b33ac4ad36db97823157dd402e19e0` |
| arm64-v8a / `libonnxruntime.so` | 6,291,928 | `86e85022fc539963177e478c8e9a8a8219bc3b0d7515bf5297a62986dbc45e7a` |
| armeabi-v7a / `libmoonshine-jni.so` | 57,848 | `f3629e5f722845de5663baac0d6c0990ce9fe976dab4260ea94306098db48295` |
| armeabi-v7a / `libmoonshine.so` | 9,413,624 | `f2ed8cbaaf1133dbe57a22c5694dccb692972cb5f4e013affefb91ac15a17285` |
| armeabi-v7a / `libonnxruntime.so` | 3,865,652 | `a312010c875759084ec1b8da57f289abbf5f5be6b2cad9469ff7653dbb605037` |
| x86_64 / `libmoonshine-jni.so` | 107,352 | `ed5f999e08b69fe89ab80873420778f82c7f854713c9fca78ea5dbe6c5703688` |
| x86_64 / `libmoonshine.so` | 11,427,872 | `1dd94038e151b8f515c5dfce7c7aa7f836c56d4eb2527414de3cf6f9317be4db` |
| x86_64 / `libonnxruntime.so` | 6,673,840 | `887bcdac57e4020ebe95c62200677b0f63a977be628a7a0231c7a6a8d8ab9c5c` |

Arm64 JNI/core ELF build IDs respectively:
`ba01dcf25bfcc889c7b5632b064388715bf4fe50` /
`6dd5f202cdafb115e14bceb1b1ee5217c7c928d3`.
Both Android ELF notes identify API 26, NDK r28c / build `13676358`.
Arm64 `moonshine_get_version` return instruction is `mov w0,#0x7530` = **30000**,
matching published Java `MOONSHINE_HEADER_VERSION`. This is a C API/header version,
**not evidence of a different Maven release or an executed native call**.

AAR manifest minSdk **26**; it declares INTERNET, ACCESS_NETWORK_STATE and
RECORD_AUDIO. devS must explicitly remove unwanted network permissions and verify
the merged release manifest. Direct declared runtime dependencies: appcompat
1.6.1, Material 1.10.0, OkHttp 4.12.0, work-runtime 2.9.1. No transitive Gradle
resolution, app build, load/link, 16 KiB page-size or device ABI compatibility
claim is made by this standalone archive inspection.

## Binary proofs and limits

### Java status handling and Pause gate

`javap -c -p` on extracted AAR classes shows:

- `startStream(int)`: JNI start at bytecode 5; `pop` at 8.
- `stopStream(int)`: JNI stop at 5; `pop` at 8; forced transcribe at 20; forwards
  transcript to notification without the explicit null guard used by add.
- `addAudioToStream`: JNI add at 11; `pop` at 14; then counts samples toward
  update scheduling even when native add returned failure.
- `isUpdateDue`: computes `min(max(updateInterval,lastPassSeconds),10*interval)`;
  nonpositive interval bypasses only this Java gate.

Ran existing `WrapperBoundaryCheck.java` **once against the unchanged published
class**, not a recompilation of upstream `Transcriber.java`. Extracted AAR classes
except JNI, compiled the existing Android signatures/fake JNI and scenario class,
verified `Transcriber.class` still exactly matches the archive, then ran the four
scenario groups: inline order/final dedup/force flag; ignored native statuses;
throttle/bypass without completion; null Stop/non-retried listener failure.
All four printed PASS; compilation and execution exited 0. These PASSes reproduce
defects, **not repaired behavior**. No native library was loaded. Existing tests
and evidence were not edited; no additional repository test was necessary.

### JNI array lifetime

Disassembled `Java_ai_moonshine_voice_JNI_moonshineAddAudioToStream`:

- arm64 entry `0xc1c8`: JNIEnv table acquisition at `0xc200/0xc20c`, offset
  **0x5e8**; length at `0xc218/0xc224`, offset **0x558**; core call `0xc240`;
  normal return `0xc260`. Catch path logs, ends catch and returns -1.
- x86_64 entry `0xc240`: acquisition `0xc26b` at **0x5e8**; length `0xc27d` at
  **0x558**; core call `0xc297`; return `0xc2b1`; catch returns -1.
- armeabi-v7a entry `0x755c` (Thumb): acquisition `0x7572/0x757c` at **0x2f4**;
  length `0x7582/0x758a` at **0x2ac**; core call `0x75a0`; return `0x75b0`.

JNI table slots verified from installed JDK `include/jni.h`: GetArrayLength=171,
GetFloatArrayElements=189, ReleaseFloatArrayElements=197. Release would be offset
**0x628** on 64-bit or **0x314** on 32-bit. No such call, release helper or cleanup
exists on the reviewed acquisition/return/exception paths. Core receives handles,
raw float pointer, length/rate/flags, **not JNIEnv/Java array needed for release**.
This is positive call-flow inspection, not an unreliable search for a missing
dynamic symbol (JNI table calls do not need imported symbol names).

Thus streaming add in this actual AAR violates array lifetime rules. Whether ART
copies or pins, and its observable memory/GC effect, remain untested. A Java status
wrapper, batching, silence cap, or `return_audio_data=false` does not repair it.

### Stop remainder and Pause finalization

Reviewed arm64 core exported routines, not just JNI:

- `Transcriber::stop_stream` calls VAD deactivate at `0x59c704`.
- `Transcriber::transcribe_stream` stopped branch calls VAD flush at `0x59cdac`;
  no-new-audio stopped branch calls stop at `0x59cd84`.
- VAD `process_audio` loads retained remainder at object offset 0x98, inserts
  resampled audio, compares available samples against hop at `0x58fd4c`, exits
  when less at `0x58fd50`, processes full chunks at `0x58fd60`, and writes remaining
  samples back at `0x58fd98`.
- VAD flush `0x58fb28` optionally calls `process_audio` at `0x58fb50`, then inlined
  stop closes the previous voice using current segment buffer/sample count. It
  contains no pad or remainder-processing step. VAD stop `0x58fa54` likewise
  closes current segment without consuming remainder.

This establishes the short-tail mechanism in the **published arm64 binary**.
Do not conflate the transcriber's pending new-audio buffer with VAD's sub-hop
remainder, or diarizer tail padding with VAD coverage. The exact 511-sample maximum
assumes approved hop 512 and internal 16 kHz; a resampling strategy introduces
additional boundary considerations. No actual spoken tail loss was measured.

VAD chunk binary calls shared `SileroVad::predict` at `0x58ff98`, averages its
probability ring, and compares against threshold at `0x590094`; segment-length
fade arithmetic is also present. This corroborates inspected algorithm structure,
but **does not prove probabilities on zeros or a successful Pause**. The proposed
four 8192-zero batches remain a fail-closed experiment, not a guaranteed bound.
This review did not fully audit native diarizer refresh/clustering or prove
speaker preservation; those conclusions in `M0_FINDINGS.md` remain tagged-source
reasoning pending device verification. No source-to-binary equivalence for the
entire SDK is asserted.

## Upstream fixes checked (read-only)

- Maven metadata and GitHub release list both expose **0.1.5 as latest published
  release**. No verified newer Maven patch can currently be selected.
- [b210b330](https://github.com/moonshine-ai/moonshine/commit/b210b3307f6e3fea18b5d6b651544eae0c7a5454)
  adds post-deactivate flush and is already represented in this AAR. It fixes
  previously unprocessed transcriber audio after Stop, **not the sub-hop VAD
  remainder**. Its source test is not our native/device result.
- Inspected `dev-v0.1.6` at immutable tip
  `9b05faab8adf4367e3c81bf05cd49207d3788e8e`. JNI file SHA-256 is **identical** to
  the pinned 0.1.5 source (`5d21e752...84ee8f`); Java still discards these statuses
  and retains the adaptive gate. No resolution by merely choosing this branch.
- [4d38510f](https://github.com/moonshine-ai/moonshine/commit/4d38510f91aa111b3a97edc9bdc4ab21adbc6e9e)
  (September 30) gives each VAD recurrent state reset at new-stream start. It is
  relevant to second-session isolation, **not a same-stream Pause guarantee**, and
  is not a published Android artifact verified here.
- [498fd45a](https://github.com/moonshine-ai/moonshine/commit/498fd45a4a61bcaa0703c1d7df3d8db9181c60c5)
  addresses destruction races; [open PR #227](https://github.com/moonshine-ai/moonshine/pull/227)
  addresses free_stream versus in-flight transcribe. Neither repairs these
  reviewed JNI/status/tail issues. Retain serialized calls and awaited disposal.
- GitHub issue/PR searches for `ReleaseFloatArrayElements` and `JNI leak` each
  returned 0. This limited search is **not proof no issue exists**; no issue posted.

## Explicit approval choices for devS / Jeush

1. **Preferred if available: upstream verified patch release.** Request/await a
   publisher fix for JNI release and checked statuses; verify the actual new
   Maven AAR/checksums/ABIs and tail policy, then explicitly approve a pin/plan
   change. No such release was found today; an unreleased commit is insufficient.
2. **If schedule requires it: separately authorize a reproducible reviewed SDK
   rebuild.** Start from an immutable approved revision, narrowly repair streaming
   JNI acquisition/release on all paths (including null acquisition/exception),
   check Java statuses/null transcripts, and review the VAD tail policy. Record
   patch, tools/options, licenses, native/core/ORT identities, ABIs and output
   hashes under a distinct internal artifact identity; do not relabel it the
   unchanged Central 0.1.5. No rebuild or native shim is authorized/performed here.
   Include second-session Silero-state fix review rather than assuming isolation.
3. **Checked application wrapper is necessary but NOT sufficient alone.** Stock
   handles/notification helper are private: simple delegation/subclassing cannot
   recover discarded return codes. Review either a narrowly patched Java wrapper
   or an explicit handle-owning public-JNI boundary; no reflection, double calls,
   catch-only facade, or silent event-contract replacement. Check every operation
   before accepting samples/final snapshots and propagate callback failures.
   This option must be paired with repaired native JNI from choice 1 or 2.
4. **Tail/Pause policy approval remains separate.** Minimal Stop mitigation to
   review at actual 16 kHz is padding to the next 512-sample boundary **before**
   checked Stop (0–511 zeros, known complete fed-sample accounting); otherwise
   review native remainder padding. Clamp synthetic timestamps to capture boundary.
   Neither padding nor forced updates proves Pause. Approve a bounded same-stream
   silence trial with checked pass scheduling and observed completion, retaining
   speaker state; fail visibly at cap. No fake final, stop/start Pause, model
   substitution, or unapproved native shortcut.

After approval: desktop failure-path tests of the chosen repair; build-only
integration; then separately authorized real Tiny+diarization tests for short
tails, pause/resume/Stop-while-paused, 2/4 speakers, repeated sessions, callback
barrier, resource growth and native compatibility. **M0 cannot safely resume
stock-SDK capture, cannot pass while the phone is unavailable, and production
adapter work stays gated.**

## Reproduction commands / local audit outputs

Existing tools only: Python 3.14, JDK `C:\Program Files\Java\jdk-26.0.2.1\bin`,
NDK `28.2.13676358` installed LLVM tools. Run from repository root. Download step
used Python urllib HEAD, a 30 MB per-file ceiling, exact Content-Length and
SHA-256 sidecar comparison for the five listed files; no Gradle dependency build.
Initial size command actually run:

```powershell
curl.exe -sSIL https://repo.maven.apache.org/maven2/ai/moonshine/moonshine-voice/0.1.5/moonshine-voice-0.1.5.aar
```

Archive extraction/hash inspection used Python `zipfile.ZipFile`,
`hashlib.sha256`; only AAR classes/manifest/metadata/native files were extracted.
Source JAR Java was extracted separately. Equivalent binary inspection commands:

```powershell
$R = "$env:LOCALAPPDATA\Temp\opencode\devj-sdk-artifact-review"
$J = 'C:\Program Files\Java\jdk-26.0.2.1\bin'
$L = "$env:LOCALAPPDATA\Android\Sdk\ndk\28.2.13676358\toolchains\llvm\prebuilt\windows-x86_64\bin"
Get-FileHash "$R\moonshine-voice-0.1.5.aar" -Algorithm SHA256
& "$J\javap.exe" -classpath "$R\aar\classes.jar" -c -p ai.moonshine.voice.Transcriber
& "$J\javap.exe" -classpath "$R\aar\classes.jar" -c -p ai.moonshine.voice.JNI
& "$L\llvm-readelf.exe" -h -n "$R\aar\jni\arm64-v8a\libmoonshine.so"
& "$L\llvm-nm.exe" -D -C "$R\aar\jni\arm64-v8a\libmoonshine.so"
& "$L\llvm-objdump.exe" -d --disassemble-symbols=Java_ai_moonshine_voice_JNI_moonshineAddAudioToStream "$R\aar\jni\arm64-v8a\libmoonshine-jni.so"
& "$L\llvm-objdump.exe" -d --disassemble-symbols=Java_ai_moonshine_voice_JNI_moonshineAddAudioToStream "$R\aar\jni\x86_64\libmoonshine-jni.so"
& "$L\llvm-objdump.exe" -d --triple=thumbv7a-linux-android --disassemble-symbols=Java_ai_moonshine_voice_JNI_moonshineAddAudioToStream "$R\aar\jni\armeabi-v7a\libmoonshine-jni.so"
& "$L\llvm-objdump.exe" -d --disassemble-symbols=_ZN21VoiceActivityDetector5flushEPKfmi,_ZN21VoiceActivityDetector13process_audioEPKfmi,_ZN21VoiceActivityDetector4stopEv,_ZN21VoiceActivityDetector19process_audio_chunkEPKfm,_ZN11Transcriber11stop_streamEi,_ZN11Transcriber17transcribe_streamEijPP12transcript_t "$R\aar\jni\arm64-v8a\libmoonshine.so"
& "$L\llvm-objdump.exe" -d --disassemble-symbols=moonshine_get_version "$R\aar\jni\arm64-v8a\libmoonshine.so"
```

Saved scratch outputs: `Transcriber.javap.txt`, `JNI.javap.txt`,
`arm64-v8a-jni-add.txt`, `x86_64-jni-add.txt`,
`armeabi-v7a-jni-add-thumb.txt`, `arm64-vad-stop.txt`, ELF notes/symbol lists,
`binary-wrapper-test-result.txt`. Initial ARM disassembly without explicit Thumb
decoded incorrectly; **only corrected Thumb output was used as evidence**.
Initial demangled-symbol-filter attempt yielded no routines; the subsequent
mangled-symbol command produced the reviewed disassembly, not an inferred result.

Binary test reproduction after this review's prepared scratch extraction:

```powershell
# Scratch classes retain all published SDK classes except JNI; existing test's
# fake JNI/Android signatures and WrapperBoundaryCheck are compiled into them.
& "$J\javac.exe" --release 11 -classpath "$R\binary-wrapper-test\classes" -d "$R\binary-wrapper-test\classes" "$R\binary-wrapper-test\stubs\android\content\res\AssetManager.java" "$R\binary-wrapper-test\stubs\android\util\Log.java" "$R\binary-wrapper-test\stubs\androidx\appcompat\app\AppCompatActivity.java" "$R\binary-wrapper-test\stubs\ai\moonshine\voice\JNI.java" docs/evidence/android/devj/WrapperBoundaryCheck.java
& "$J\java.exe" -classpath "$R\binary-wrapper-test\classes" com.larpcode.revise.m0.WrapperBoundaryCheck
```

For clean reproduction, extract AAR `classes.jar` entries into a scratch classes
directory excluding `ai/moonshine/voice/JNI.class`, write the existing
`check_boundary.py` `STUBS` entries under scratch `stubs/`, then run those two
commands and compare published/test `Transcriber.class` bytes. Import with Python
`-B` to avoid writing bytecode caches into the evidence directory. Merely running
the original source-compiling runner does **not** reproduce this binary test.
This document records the single actual run; commands above are reproduction,
not a claim of additional runs. Scratch archives/logs are not repository deliverables.
