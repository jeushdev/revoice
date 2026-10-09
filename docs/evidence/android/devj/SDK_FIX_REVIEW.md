# Independent review: Moonshine SDK fix candidate

October 10, 2026. Original checkout: `devj/android-captions-speakers`.
Reviewer did not author the proposal, patches, tests or candidate.

## Decision

**Accept the two narrow patches and JNI-only rebuild/repack as a feasibility
candidate, subject to the bounded follow-ups below. Reject production adoption,
M0 clearance and any claim of Android/native failure-path safety at this point.**

I found **no concrete newly introduced functional defect** in the modified
streaming-add RAII, start/add/stop status checks or explicit-update implementation.
There are concrete inherited defects and an incorrect packaging-evidence claim;
the supplied tests do not discharge the associated gates.

The next action is an author evidence/test correction, then a user/devS decision
on tail policy and candidate packaging. Only after that decision should a
separately authorized **build-only** integration check use the existing isolated
integration work. No production adapter or phone work is authorized by this review.

## Scope, sources and actual checks

Read `ANDROID_IMPLEMENTATION_PLAN.md`, `ANDROID_WORK_SPLIT.md`,
`SDK_ARTIFACT_REVIEW.md`, `SDK_FIX_PROPOSAL.md`, both `sdk-fix/*.patch`,
`CheckedBoundaryTest.java`, `jni_cleanup_test.cpp`, `review.py`, `inputs.json`,
`ndk-inputs.json`, the imported `check_boundary.py` stubs, prior
`WrapperBoundaryCheck.java`, and capture/device gate documents. Inspected candidate
Java/JNI source, C API declarations, relevant pinned core/VAD/diarization source,
published POM/module metadata, existing native logs and candidate archives.

Path abbreviations for source line references below:

- `T` = `C:\Users\jeush\AppData\Local\Temp\opencode`.
- `B` = `docs/evidence/android/devj/sdk-fix/` in this repository.
- `C` = `T\devj-moonshine-sdk-fix\candidate-r3\patched\` (candidate source).
- `U` = `T\devj-moonshine-0.1.5\` (existing immutable-revision source).
- `R` = `T\devj-sdk-artifact-review\` (published artifacts and saved inspection).

The source revision is `234f60faa0eb388b01cdf7e60aca232af37aefda`. Independently
verified all 12 `source-pins.json` inputs; the runner also verified the 22 fix
source inputs and both original artifact hashes. Supporting already-fetched
Silero/header texts and upstream commit JSON are source evidence, not an assertion
that every published native instruction reproduces from that revision.

Ran the **existing desktop suite once**, without cross-build:

```powershell
python -B docs/evidence/android/devj/sdk-fix/review.py --run-name independent-review-r1
```

Exit 0: ordinary patch checks/application in scratch, 16 host fake-JNI/core
scenarios and five Java fake-JNI groups passed. Logs/results are only in
`T\devj-moonshine-sdk-fix\independent-review-r1\`; the runner refused existing
run directories. This is not a JVM-native library test, ART test, compiled VAD
test, microphone test or inference result. No native rebuild was repeated.

Additional **read-only** archive/hash, `llvm-nm` and arm64 core disassembly
inspection established:

- All three existing candidate AARs are 24,288,174 bytes and SHA-256
  `3936002d9ff6e14cba0d41af7c3d1ccc4f7b4309f441f1d7029337e1cb700d3e`.
- Candidate-r3 has exactly the original non-directory payload names. Only
  `classes.jar` and the three `libmoonshine-jni.so` payloads differ. Within
  `classes.jar`, only `ai/moonshine/voice/Transcriber.class` differs. That class
  equals the candidate-r3 tested bytecode, SHA-256
  `cf9cddf78bb9a5005663b439dec2ab9ce047ad2408cb7bc9fb9901bc9b12c8bb`.
- All 43 exported `Java_*` names match the originals on each ABI. Candidate total
  exports are 43 versus original 65: internal/weak non-JNI exports were hidden;
  **not** a claim of identical total symbol tables.
- Manifest/resources/AAR metadata/core/ORT and other class bytes are preserved.
  **Neither archive contains consumer ProGuard rules**, discussed below.

An initial archive probe incorrectly requested nonexistent `proguard.txt` and
exited 1 after checking payload differences and manifest. A corrected read-only
inventory established the absence and completed the class comparison; it did not
change archives or repeat the desktop tests.

Only this review document was added to the repository. No downloads, installs,
SDK/pin changes, patch adoption, production/shared-config edits, app builds,
branch switches, staging/commits/pushes, subagents, public issues, ADB or device
calls. Existing evidence, candidate directories and integration worktrees were
not overwritten or removed. Redmi remains off.

## Findings and required disposition

Severity here measures adoption risk, not whether a defect was introduced by a
patch. **Inherited** findings are explicitly distinguished from candidate changes.

### R1 — High release gate / medium evidence defect: no consumer keep rules

`SDK_FIX_PROPOSAL.md:191–195` says ProGuard remains byte-identical. The published
and candidate AAR contain only `R.txt`, manifest, `classes.jar`, native libraries
and `META-INF/com/android/build/gradle/aar-metadata.properties`; there is no
`proguard.txt` or equivalent class-JAR metadata. Upstream
`U/language-bindings/android/build.gradle.kts:17` declares
`consumerProguardFiles("consumer-rules.pro")`, but that is **not evidence the
published artifact delivers it**.

This matters directly to the chosen streaming path:
`C/language-bindings/android/moonshine-jni/moonshine-jni.cpp:118–133,169–177,249–255,358–361`
looks up SDK class/constructor/field names as literal strings. R8 can remove or
rename these members without matching keep rules. Matching JNI export names or
a non-minified desktop compile does not test this.

**Author:** correct the preservation claim to state the inherited absence.
**devS:** explicitly provide/review needed native-name/member keep rules and
inspect the actual minified release output (or approve an explicit non-minified
feasibility build, without treating that as release proof). No candidate-code
change is demanded merely to preserve nonexistent rules.

### R2 — High inherited native gate: repaired add is not the whole streaming JNI path

`C/language-bindings/android/moonshine-jni/moonshine-jni.cpp:134–154` calls
`NewObject`, `NewStringUTF`, `NewFloatArray` and subsequent JNI setters without
checking allocation failure/pending exceptions. For example, a failed
`NewFloatArray` at line 151 is followed by `SetFloatArrayRegion` on its null result
at line 152. Ordinary setters/calls are not permitted while a Java exception is
pending. Depending on runtime checking this can abort/crash before Java's null
guard or `OutOfMemoryError` propagation gets control.

This converter is reached by the **required** add/update/Stop transcription path
at lines 693–703, not just an unrelated optional helper. The changed add function
obeys pending-exception rules; this retained converter does not establish that
safety for the complete operation. The normal file loader also still acquires
option/path UTF strings at lines 370–382 without matching releases. These are
pre-existing issues, not regressions caused by rebuilding JNI.

**Disposition:** retain an explicit JNI/runtime uncertainty gate; do not label the
candidate generally OOM-safe or leak-free. Any additional source fix requires a
separate narrow scope decision. Before production approval, resolve required-path
JNI allocation/exception handling and measure repeated local-load/feed/close/GC
behavior. Fake add-OOM tests cannot validate the converter or loader.

### R3 — Medium inherited consistency gap: automatic pass failure clears cadence first

`C/language-bindings/android/java/main/java/ai/moonshine/voice/Transcriber.java:454–468,514–529`
retains the upstream sequence: `isUpdateDue()` resets pending audio to zero
**before** transcribe; the add path updates pass cost **before** checking a null
transcript. Thus a successful native add followed by failed automatic transcribe
can leave pending=0 and a new cost despite failure. New explicit update and Stop
null guards correctly retain pending count on null, but that property is not
universal across the wrapper.

`B/CheckedBoundaryTest.java:80–98` tests null Stop/update, not a due automatic
add-pass failure. Also its listener throws on the first event, not specifically
on `LineCompleted`. It does not re-establish the previous test's exact-final
non-redelivery behavior against the candidate.

**Author:** add these precise regression cases and clarify cadence maps are not
an accepted-audio ledger. Either preserve/document terminal fail-closed behavior
or separately review counter changes; never retry/replay an append on the strength
of unchanged Java counters. A native call or callback can fail after mutation.
The proposed fail-closed adapter is compatible with this limitation, so this is
not grounds to reject the narrow patch as a feasibility repair.

### R4 — Medium evidence gap: tail fixture does not test the Stop policy boundary

`B/CheckedBoundaryTest.java:121–146` proves modulo arithmetic and one fragmented
fake append case. The all-residue loop never calls SDK Stop. Its fragmented case
always has nonzero padding and calls add unconditionally. It does not execute
zero-padding/no-new-audio Stop, Pause/resume accounting, rejected/throwing append,
failure after a successful add, duplicate Stop, or real VAD retention/consumption.

The `Long.MAX_VALUE` assertion at line 133 only proves the formula does not add
512 to the full tally. It does **not** prove the tally increment, `N + P`, or
timestamp arithmetic cannot overflow. After that input, `N + 1` overflows a
signed long. There is no production ledger in this bundle, so this is a coverage
and wording defect, not a discovered production implementation bug.

**Author:** add a review-only stateful ledger/ordering fixture covering P=0,
successful-native-add plus later failure, Pause samples, terminal failure,
duplicate Stop and overflow disposition. Document checked total arithmetic or
bounded rolling remainder plus separately checked timing counts. Actual native
no-new-audio and spoken-tail behavior remain phone gates.

### R5 — High adoption decision: repacked AAR does not preserve Maven dependency metadata

`B/review.py:154–176,208–215` deterministically repacks the AAR, not its POM/module
metadata. `R/moonshine-voice-0.1.5.pom:35–59` and module runtime variant
`:45–73` declare appcompat 1.6.1, Material 1.10.0, OkHttp 4.12.0 and work-runtime
2.9.1. Those metadata files are external to the AAR. A local `files(...)` AAR
replacement does not automatically carry this dependency graph. Retaining the
original Maven dependency alongside it instead risks duplicate SDK classes/native
libraries; `pickFirst` is not artifact identity validation.

The proposal already says packaging identity/substitution is unapproved; this
finding specifies what that gate must include. **devS/user:** choose a distinct
internal artifact identity and a metadata-preserving substitution/publication or
explicit reviewed dependency graph. Do not reuse Central 0.1.5 metadata/checksums
unchanged for new bytes. Record resolved transitives, exactly one SDK class/native
provider and notices. Author should make this caveat explicit before handoff.

## Changed-code assessment

### Streaming-add RAII: acceptable source-level repair

`B/0001-streaming-jni-lifetime.patch:7–37`, candidate JNI `:646–681`:

- Checks and preserves an existing exception before further ordinary JNI work;
  rejects null array/nonpositive rate; checks length and its exception before
  acquisition. A negative fixture length is impossible for a valid real array,
  but does not hurt defensive control flow.
- A capture-only lambda deleter and `unique_ptr` construction do not allocate.
  The acquired pointer is owned immediately; all normal/error returns and C++
  unwinds release it once with `JNI_ABORT`. Null acquisition is neither passed
  to core nor released. Short-circuiting the null check does not clear pending OOM.
- After acquisition with a pending exception, cleanup uses
  `ReleaseFloatArrayElements`, which is permitted with a pending exception.
  No ordinary JNI setter/call is added there. Standard and nonstandard C++ throws
  are caught. This does not promise recovery from signals or a throwing JNI stub.
- Valid `jsize` fits `size_t` on every packaged ABI and then the C API's uint64
  length. Positive-rate validation is not a finite-PCM/normalized-input check or
  approval to feed arbitrary hardware rates in the proposed adapter.

Input lifetime is compatible with inspected core consumption:
`U/core/moonshine-c-api.cpp:577–600` calls synchronous add;
`U/core/transcriber.cpp:764–777,1840–1848` copies input into a vector, resamples and
inserts owned samples. It does not retain the Java array pointer. Independently
inspected **published arm64** `TranscriberStream::add_to_new_audio_buffer` at
`0x59ca34`: allocation/memcpy at `0x59ca84/0x59ca9c`, resample at `0x59cab8`,
owned-vector insert at `0x59cad0`, temporary frees before return. Therefore
`JNI_ABORT` is appropriate; no input write-back is required. Other core ABIs were
not independently disassembled for this ownership path in this review.

Existing candidate disassembly corroborates release on all three ABIs and unwind
destructor calls: arm64 release table offset 0x628/mode 2 at `0xf52c–0xf540`, ARM
Thumb offset 0x314 at `0xa776–0xa782`, x86_64 offset 0x628 at `0xf3f9`.
The host test substitutes both JNI operations and core; it proves control flow,
not pin/copy/GC behavior or cross-DSO native exception handling.

### Status/update: acceptable within serialized, terminal-failure semantics

Candidate `Transcriber.java:398–421,443–449,471–496` rejects every nonzero status
before corresponding start/reset, add cadence, or Stop transcribe/callback work.
Checks for positive unexpected statuses are intentionally stricter than simply
testing negative values; the STT C API documents zero success/nonzero failure.
Empty-array rejection changes behavior intentionally; use update, not empty add,
to request a pass. Pending native Java errors propagate instead of becoming a
successful status operation.

Explicit update ORs FORCE_UPDATE with existing flags, checks nonnull before
resetting cadence/measuring cost, and uses existing notification order. It neither
changes stream/options/interval nor fabricates completion. A successful native
snapshot resets scheduling before callbacks: callback failure still fails the
operation, not the already-consumed native work. Existing
`Transcriber.java:553–560` records completion before listeners; multiple listeners
can consequently observe different delivery after one throws. Fail the session;
do not treat a repeated update/Stop as a reliable callback retry.

Force bypasses the **interval**, not the core's **has-new-audio** condition
(`U/core/transcriber.cpp:819–866`). A pass without new audio may only expose cached
data/speaker revisions and cannot force remaining VAD chunks or drain diarization.
Calls, callbacks and close must be serialized and non-reentrant; JNI conversion
reads transcriber-owned output valid only until the next call/free
(`C/core/moonshine-c-api.h:177–179`). Native create/free handling is still unchecked
in Java. In particular, pinned core start/add accesses `streams[id]` then
dereferences it (`U/core/transcriber.cpp:724,769–770`); invalid stream IDs need not
become recoverable statuses. Fake error returns are not proof of safe bad-handle
handling. Use a valid successfully-created stream; never free under active calls.

## Stop/Pause and retained-core limitations

**The exact-16-kHz/hop512 formula is correct under its stated invariant**, not a
general-rate fix. Let all successful SDK-fed samples since this stream's start,
including synthetic Pause samples, total N. Pending transcriber samples plus
retained VAD remainder account for the not-yet-hop-processed part of N. Appending
`P = (512 - N % 512) % 512`, only when P>0 and before checked Stop, makes total
hop-aligned. Pause batches of 8192 are themselves multiples of 512 but still
belong in the ledger and timestamp mapping.

Source VAD processes full hops and retains the remainder
(`U/core/voice-activity-detector.cpp:90–107`); flush/stop omit remainder padding
(`:62–78`). Published arm64 resampler at `0x594aa4` compares rates at `0x594ab4`
and copies the unchanged-length input at `0x594af4` when equal. This supports exact
16 kHz accounting independently of the proposal. The resampler implementation
text itself is not among either checked input manifest's files; this review does
not assert independently checked arbitrary-rate rounding semantics. Separate
per-append resampling means raw non-16-kHz capture counts cannot simply be used
as internal 16-kHz counts. Enforce actual fed rate and explicit hop, not requested
microphone rate; otherwise return the resampling/core-fix choice to devS/user.

For **no-new-audio Stop**, P=0 is valid only if all fed audio has been processed
and the remainder is therefore empty. P>0 adds new audio so Stop can consume
the padded pending/remainder hop. The core's no-new branch calls VAD stop rather
than flush (`U/core/transcriber.cpp:840–866`); padding only inside flush would miss
it. N=0 must not call empty add. Count success at the native-append boundary, not
merely after public `addAudio` returns: it may throw after append during automatic
transcribe/callback. Such an uncertain/failed operation must terminate, not
attempt a successful padded Stop using an incomplete ledger. Guard overflow,
shutdown/join/drain, and duplicate Stop in the eventual app-owned policy.

Padding proves VAD hop coverage, **not** recognition of a 1-sample utterance,
accurate timestamps or a hallucination-free synthetic tail. Clamp synthetic
ranges to the capture boundary, retain old mappings for delayed callbacks, and
test aligned/unaligned Stop after update and while paused.

Same-stream Pause remains an experiment, not an accepted lifecycle capability:

- Do an initial explicit real-audio pass even without a visible partial, then
  inspect incremental checked silence/update passes. Empty/missing partials are
  not proof all accepted speech finalized. Observed real-line completion plus
  successful ordered app delivery are necessary, not just a nonnull snapshot.
- Four 8192-sample batches cap **synthetic audio** at 2.048 s, not wall-clock
  inference or a guaranteed silence timeout. Automatic plus explicit passes can
  both run; the fixture's interval=1000 intentionally avoids that cost.
- Silero probabilities and smoothing, not a fixed zero-input deadline, drive VAD
  (`U/core/voice-activity-detector.cpp:149–204`). Diarizer append analyzes at most
  one complete window (`U/core/cpp-annote/src/cpp-annote-streaming.cpp:256–263`);
  full refresh/end-session drains at `:585–604` are not exposed by new update.
  Finals can have unknown/outdated speakers. No fabricated finals, Stop/start
  Pause, silence-as-guarantee or freeing underneath a blocked native call.
- **Source-confirmed second-session isolation defects remain unaddressed.**
  Global Silero model/state (`U/core/voice-activity-detector.cpp:20–37,50–60`;
  `U/core/silero-vad.cpp:48–49,158–161`) is not reset by a new VAD/Transcriber.
  Recreating the Java wrapper or serializing sessions does not reset that global
  recurrent state. The already-fetched upstream `4d38510f...` JSON explicitly
  fixes per-stream recurrent state; it is not included here. Reusing a VAD also
  uses same-size `resize(...,0)` rather than clearing existing probability/look-
  behind elements. These are retained-source mechanisms, not measured phone
  effects or an independent full binary audit. Do not present JNI-only repack as
  a second-session fix.

## Repack/runtime gates and minimal next step

`B/review.py:50–58` fixes ZIP ordering/time/attributes/compression; repeated local
archive hashes support deterministic output on the observed environment, not a
hermetic cross-machine guarantee. It records/hashes important NDK/link inputs,
but not the entire C++ header/tool runtime closure or test/stub-donor/JDK/Python/
zlib identities. Record those for final reproducibility; no tools need installation
for that documentation step. Runner's `assert` preservation checks must not be
disabled with Python optimization.

The JNI builds link to the original core/ORT; existing logs show API26, unchanged
SONAME/dependency names, RELRO/NOW, 0x4000 JNI LOAD alignment and no new
`libc++_shared.so` requirement. C ABI and matching NDK reduce risk, not prove
transcript-struct layouts, Android symbol resolution, static C++ runtime/exception
interaction, GC or loader behavior. All required native libraries and final
APK ZIP alignment need review; AAR ZIP serialization is not APK alignment.
Stub-only Android/AppCompat signatures are not the real Android classpath.

The byte-identical manifest still merges INTERNET and ACCESS_NETWORK_STATE,
minSdk26, RECORD_AUDIO and the permission activity. devS must enforce the planned
offline merged release manifest and backup policy. Preserving those original
permissions is archive fidelity, **not offline acceptance**.

### Before build-only integration

1. **Author:** correct the nonexistent-ProGuard wording, document external Maven
   metadata, add R3/R4 missing deterministic fixture cases, and qualify overflow/
   native/OOM claims. Keep these as review evidence; no covert production changes.
2. **User/devS:** approve exact SDK-fed 16 kHz/hop512 versus separately scoped
   resampling/core work; approve the bounded fail-closed Pause experiment and
   explicitly retain second-session/JNI required-path risks as unresolved gates.
3. **devS/user:** select candidate identity, dependency metadata/keep rules/license
   delivery and authorize one bounded compile/package check in existing isolated
   integration work. Verify real classpath, no duplicate stock SDK, merged
   manifest and release shrinker/native payloads. No app adoption or shared-config
   edits are inferred from this review.

### Phone gates remain separate and blocked

Only after a successful approved build and new phone/deployment authorization:
real Android load/link and CheckJNI/GC observations; short-tail/no-new-audio Stop;
Pause/resume/Stop paused and cap failure; ordered final callback/channel barrier;
2/4/unknown speakers and diarization lag; repeated sessions after silence and
speech (including synthetic-only hallucinations); local-load/disposal/resource
growth, actual rate/timestamps, offline operation and timing. Follow
`DEVICE_GATES.md`; don't claim M0 passed on fake or desktop results.

**Bottom line:** this bundle makes the narrow repair feasible to investigate. It
does not yet make the required Android recording lifecycle safe or proven.
