# Moonshine 0.1.5: review-only fix candidate

October 10, 2026. **Prepared, not adopted. User + devS review required. M0 remains
blocked on SDK/policy approval and phone verification.** Original checkout stayed
on `devj/android-captions-speakers`. Only this proposal and `sdk-fix/` review bundle
were added. Existing findings, plans, shared files, dependencies/pins and production
adapter were not changed. No staging/commit/push, public issue, install, ADB,
instrumentation, inference, model acquisition or tool installation.

## Proposed review decision

Accept the two narrow source patches **for review**, with the JNI-only rebuild
below as a feasible candidate route. Do not approve application adoption yet.
Approve separately whether the initial adapter must feed exact **16 kHz, hop 512**
with ledger-based Stop padding, or whether a core remainder fix is necessary.
Same-stream Pause still requires fail-closed completion/device evidence.

| Candidate | Actual preparation proof | Not established |
| --- | --- | --- |
| RAII streaming JNI cleanup | 16 compiled host scenarios; Android JNI cross-builds for all three ABIs; release present in candidate disassembly | ART/GC behavior, Android loader safety, real core exception behavior |
| Checked start/add/stop and explicit update | Original five Java test groups passed with fake JNI; follow-up adds automatic-null and exact-final regression cases; candidate Java compiled against published JNI/classes | Real inference/callback completeness, Android app build |
| Stop-tail policy | Stateful review fixture invokes SDK Stop on all 512 residues; checks terminal failures, ordering, synthetic accounting, duplicate Stop and overflow | Real VAD retention/consumption, spoken tail recognition, non-16-kHz coverage, timestamp accuracy |
| Pause scheduling | Forced update bypasses gates without stop/start or fabricated final; bounded four-batch fixture | Silence finalization, unseen pending speech, diarization drain/stability |

## Review bundle and immutable inputs

Under `docs/evidence/android/devj/sdk-fix/`:

- `0001-streaming-jni-lifetime.patch`: one JNI streaming-add function only.
- `0002-checked-java-and-explicit-update.patch`: start/add/stop checks, Stop null
  guard, two explicit update methods and a small status-check helper.
- `CheckedBoundaryTest.java`, `StopLedgerFixture.java`, `jni_cleanup_test.cpp`:
  review tests, no app code.
- `review.py`: offline hash verification, scratch patch application, tests,
  optional three-ABI JNI cross-build and deterministic review AAR repack.
- `inputs.json`: immutable source and original Maven AAR/source-JAR hashes.
- `ndk-inputs.json`: observed compiler/linker/JNI-header and link-dependency hashes.

Base source is exactly **`234f60faa0eb388b01cdf7e60aca232af37aefda`**, not an
unreleased branch. Bounded raw source preparation totals **285,962 bytes**;
previously verified Java/JNI files were copied, only necessary small C API/UTF-8
headers, license and CMake text were fetched. HTTP HEAD and 150 KB/file read caps
were used; no repository archive, model or third-party SDK download.

Original published AAR SHA-256:
`ee2d95c21150683c743db8f3aef66281fd5408bcefc94be3ca1d2545ada1f571`.
Original source-JAR SHA-256:
`b2a5a53dff132acdddf4f481f8a7f75b49168637f9a4efef8e49faf091ccba63`.
Per-core/ORT ABI hashes remain those in `SDK_ARTIFACT_REVIEW.md`; the runner checks
the complete original AAR before extracting them, and verifies byte preservation.
Source checksums, including C API and all seven vendored UTF-8 headers, are in
`inputs.json`; no external sources are vendored into the repository bundle.

Final patch SHA-256 identities:

- JNI patch: `670e91a3df4f3b9b9f4c4082fd4503b75691d820be151a633d642b2e2867fe6b`.
- Java patch: `40c6dd7d3f28aaae9a9c9d1ee4b20d9ce25eeeb2cee4e42ccc61655f57199190`.

Both apply with ordinary `git apply --check` / `git apply` in scratch. Initial
hunk-count formatting was normalized after the first run; verified ordinary
application produces exactly the tested source bytes. No semantic change there.

## Patch behavior and intentional limits

### JNI

Check a pending Java exception first; preserve it rather than clearing/replacing
it. Reject null array/nonpositive rate; get/check length **before** acquisition;
reject empty/invalid length. Acquire into `unique_ptr<jfloat, lambda-deleter>`
without an intervening allocation. On each acquired-pointer normal return,
native error return, pending-exception return, or C++ unwind, release exactly once
with **JNI_ABORT**. Core takes const input and synchronously copies/resamples it,
so no Java array write-back is needed. Null acquisition is never passed to core
and never released; OOM stays pending. Unknown/non-std C++ exceptions are caught.

Tests compile the **exact patched function extracted from source**, with real
JDK JNI types/function table and C API declarations, fake JNI operations and fake
core. Tested success/four error statuses; standard/nonstandard throws; null/rate;
zero/negative fixture length; existing/length/acquisition exceptions; null acquire
with/without pending OOM. Assertions cover release count, JNI_ABORT, ordering and
preserved exception. This is source-native control-flow proof, **not JVM/ART**.

Candidate arm64 normal cleanup is at `0xf52c/0xf540` (table offset 0x628, mode 2),
with unwind cleanup at `0xf55c` to RAII destructor. That destructor also releases
at 0x628 with mode 2. ARM Thumb normal release is `0xa776/0xa782` (0x314); x86_64
is `0xf3f9` (0x628). All three also contain unwind destructor calls. The disassembly
and host tests corroborate cleanup, but no Android exception path was executed.

**Inherited required-path gate (independent review R2):** other JNI functions are
deliberately unchanged, including the transcript converter reached by the required
automatic add/update/Stop path. Its `NewObject`, `NewStringUTF`, `NewFloatArray` and
subsequent setters are not uniformly checked for allocation failure/pending
exceptions. In particular, a null `NewFloatArray` can be followed by
`SetFloatArrayRegion`. Android may abort before a Java null guard or OOM handler
gets control; the isolated add-OOM fixture does not test this converter.

The required file loader also retains path/option UTF acquisitions without matching
releases. Repeated local-load/feed/close/GC, converter allocation/exception handling,
native handle validity and cross-DSO lifetime are unresolved gates, not merely
optional-helper concerns. Successful fake status returns do not prove invalid
stream handles are safe: pinned native accesses can dereference an invalid stream.
This candidate is **not generally OOM-safe, JNI-safe or leak-free**. Fixing these
inherited paths needs a separate narrow approval; no such patch was added here.

### Java

Fail on any nonzero native start/add/stop status **before** changing wrapper
counters or delivering corresponding callbacks. Failed Stop does not transcribe
cached data. Stop null transcript fails explicitly before resetting pending count.
Invalid/empty input is rejected before JNI; empty arrays are not a flush API.
Pending JNI `OutOfMemoryError` is not swallowed. Callback exceptions still
propagate; the upstream completed-ID-before-listener behavior is not changed.

`updateStream(int)` / `update()` force a checked nonnull transcription snapshot,
bypassing Java cadence and native interval through FORCE_UPDATE, without changing
the stream, options or update interval. A successful pass resets pending cadence
and measures native-pass cost. It does **not** claim completion or full speaker
drain. Explicit-update null cannot report success or clear pending count. FORCE_UPDATE
bypasses the native interval, **not its has-new-audio condition**; with no new audio
the result can be cached data/speaker revisions rather than remaining-tail processing.

**Cadence is not an accepted-audio ledger (R3).** `pendingSeconds` and
`lastPassSeconds` are scheduling maps only. The inherited automatic due-add path
clears pending cadence in `isUpdateDue()` **before** native transcribe, and writes
the pass cost **before** checking for null. Thus native append can succeed while
the later automatic pass fails with pending=0 and a new cost. This differs from
Stop/explicit-update null guards. Successful snapshots also change scheduling
before callbacks; a callback failure cannot roll back accepted/consumed audio.
No counter behavior was patched to enlarge the approved source change.

The new exact regression tests capture successful native append followed by a
due automatic null result, and a listener throwing specifically on `LineCompleted`.
The completion ID was already recorded: a deliberate isolated SDK repeat snapshot
does not redeliver that final, and a later listener can miss it entirely. That repeat
is a regression probe, **not permitted session recovery**. Fail the session and do
not replay audio, retry callbacks, or pad a purported successful Stop from stale
cadence maps.

There is no automatic retry: native failure may have partially mutated internal
state, even though the Java wrapper no longer counts a failed add. Treat a failure
as an interrupted/failed operation, not permission to replay audio. Stream-handle
creation/free checks, concurrency, disposal and other APIs are outside this patch;
serialize calls and never free under active inference. No reflection in candidate
code (only test introspection of private counters).

## Stop tail: prefer explicit 16-kHz policy, not a covert core edit

**Proposed minimal route preserving the published core:** require actual SDK-fed
PCM at 16 kHz and explicit hop 512. After microphone stop/join and accepted real
queue drain, let `N` be the complete per-stream accepted sample tally, including
previous synthetic Pause samples. Append `P = (512 - N % 512) % 512` zeros if
`P > 0` (never an empty add), then checked Stop. P is **0–511 samples, at most
31.9375 ms**. Retain timestamp ranges and clamp synthetic padding to capture
boundary. Repeated Stop must be app-owned idempotent, with no duplicate padding.

At equal input/output rate, pinned resampler returns input samples unchanged;
both pending transcriber audio and VAD remainder therefore retain exact tally.
Stop then processes an integral-hop total. The policy covers the VAD remainder;
it is not a promise of recognition accuracy. The review-only stateful fixture feeds
fragmented samples and invokes patched SDK Stop for **all 512 residues**, asserting
optional pad -> native Stop -> forced snapshot order at a fake boundary. It covers
P=0 without empty add, N=0, aligned Stop after update with no new fake audio,
synthetic Pause/resumed real samples, duplicate successful Stop and failure after
padding, native Stop, transcribe or final callback. This is **not compiled VAD or
native no-new-audio proof**, and is not a production adapter.

The fixture preflights totals/padding/synthetic counts with `Math.addExact`;
Long.MAX_VALUE residue arithmetic alone is **not** overflow protection. A total
or N+P overflow makes the operation terminal before SDK entry. Virtual seeded
boundary cases also cover the largest aligned total; they do not represent real
SDK processing of those counts. Timestamp conversions need separately checked
arithmetic/range limits in any eventual adapter; no timestamps are implemented here.

Its known ledger commits after a public void append returns successfully. Because
that call can throw after native acceptance, **any** append/pass/Stop exception
invalidates the ledger and transitions to terminal FAILED: no later append,
update, padded Stop or replay, even if the error source clears. Fake native counters
show accepted samples beyond the last known total in the transcribe/callback-failure
cases; the old known total is deliberately not authoritative after failure. A
production ledger must observe the checked native-acceptance boundary if exposed,
or use this conservative invalidation policy, never infer acceptance from cadence.

**Do not apply this formula to arbitrary capture rates.** Native resampling is
per append and rounds output length. Request either separately reviewed explicit
resampling/accounting or a narrow core patch if verified 16 kHz cannot be fed.
Do not silently assume the requested hardware rate succeeded.

**Alternative core fix (not patched/built here):** consume the retained VAD
remainder as one zero-padded hop exactly once at terminal Stop, including Stop's
no-new-audio path. A flush-only edit is insufficient when transcribe routes directly
to `stop()`. Review segment transitions, synthetic sample time, exceptions,
repeated-stop behavior and Silero state. This requires rebuilding core across
approved ABIs and broader VAD tests, rather than importing the unchanged published
core. Choosing it needs separate scope approval; no speculative core patch is
bundled merely to look complete.

## Pause: explicit scheduling, still fail-closed

Keep one stream and speaker registry. Following mic shutdown/drain, perform at
least one explicit pass to expose pending real speech; then trial incremental
8192-zero batches, inspecting actual line completion/delivery after each pass.
At most four batches = **32,768 samples / 2.048 s synthetic audio**. This is an
application experiment budget, not Silero's guaranteed timeout or wall-clock bound.

Call `update()` explicitly after each checked append even if the normal adaptive
gate defers it. Automatic add may itself run a pass: without suppressing cadence,
there can be up to four automatic plus four explicit passes during four batches,
in addition to initial real-audio drain/pass. The fixture uses a large interval to
isolate explicit scheduling, not a claimed product configuration. Any future
temporary cadence suppression must be serialized and restored in `finally`.

An empty/cached transcript or missing previously visible partial is **not proof
all accepted speech finalized**. Require observed real-line completion, ordered
delivery and device evidence; fail at cap/error, never mark a partial final or call
stop/start for Pause. Diarization backlog may leave unknown/outdated attribution.
Neither JNI repair nor FORCE_UPDATE solves that. No watchdog may free resources
underneath a blocked synchronous call.

## JNI-only rebuild/repack feasibility and candidate identity

**Feasible, actually compiled/linked; not runtime verified.** Existing NDK r28c
`28.2.13676358` (Clang 19.0.1), JDK 26.0.2.1, Python 3.14, and host MSYS2 GCC
15.2.0 were reused. NDK API **26**, C++20, -O2, hidden internal visibility,
static libc++/libc++abi/unwind, SONAME `libmoonshine-jni.so`, no-undefined link,
RELRO/NOW, and 16 KiB maximum ELF page alignment. The bundle records checksums
for compiler/linker, headers and actual static archives/API stubs/CRT dependencies.
These are observed installed-tool identities, not verification of the entire
toolchain's distributor signature or a hermetic environment attestation.

Compiled the **whole patched upstream JNI translation unit**, not a hand-written
replacement streaming shim. Linked each ABI to the original published
`libmoonshine.so` and `libonnxruntime.so`. All 43 exported Java JNI names match
original binaries. Dynamic dependency names remain Moonshine, ORT, Android, log,
m/dl/c; no new `libc++_shared.so` packaging requirement. SONAME preserved. Candidate
JNI LOAD alignment is 0x4000; full app/native page-size compatibility is untested.

Candidate Java was compiled against the **original published JNI and SDK classes**,
not fake JNI; only `Transcriber.class` replaced. Final tests assert byte-for-byte
identity between candidate and test `Transcriber.class`. Small Android/AppCompat compile
signature stubs were used because the full pinned appcompat build classpath was
not resolved. These stubs are **not packaged**; a real Android/Gradle build remains
required. No fake JNI/test class enters the candidate archive.

Repacked AAR changes exactly four payload entries: `classes.jar` and three
`libmoonshine-jni.so` files. Core/ORT, manifest, resources, AAR metadata and other
classes/payloads remain byte-identical. **Neither published nor candidate AAR has
consumer ProGuard/keep rules**; the earlier ProGuard-preservation claim was incorrect
(R1). An upstream Gradle declaration of consumer rules does not establish their
presence in the published artifact. ZIP serialization differs and is deterministic.
Manifest network permissions are inherited unchanged; devS's offline packaging
gate is not bypassed. This archive is **not published Central 0.1.5** and has no
approved Maven coordinate, dependency substitution or app adoption.

Three scratch runs produced identical candidate AAR and native/class hashes. The
second added normalized patch checks, NDK hash gates and scratch-only compiler
temporary files; the final run corrected a fake dependency-helper signature to
match published JNI and asserted identical candidate/test bytecode. No SDK source
semantics changed between these runs.

| Review output | Bytes | SHA-256 |
| --- | ---: | --- |
| `moonshine-voice-0.1.5-revise-review-r1.aar` | 24,288,174 | `3936002d9ff6e14cba0d41af7c3d1ccc4f7b4309f441f1d7029337e1cb700d3e` |
| arm64 JNI | 130,248 | `5617c2306c1599c894118b88f5feafcaec3f3bd7231dddf813259ae5e3e9a759` |
| ARMv7 JNI | 76,984 | `1bc313e05fb5e739f8e5b65787b29206a4f52d71b3f0f0ebfe3af8f8c6ac9904` |
| x86_64 JNI | 127,536 | `401d20b1741423380e50220595d3dc63aef999d3edf8e96b02e7f4e09fb84253` |
| `Transcriber.class` | 13,896 | `cf9cddf78bb9a5005663b439dec2ab9ce047ad2408cb7bc9fb9901bc9b12c8bb` |

Patched source hashes: JNI `a0d2d6d3b293f068bebf97885329f8d8554fa76bcd5c533dfe0807dfb4cbb16d`;
Java `5cbac694d2eba6e72f662921759340165dcbeacc03339f3ac1c23ee4ed3a2033`.
Archives and full command/output logs reside only under
`C:\Users\jeush\AppData\Local\Temp\opencode\devj-moonshine-sdk-fix\candidate-r{1,2,3}`.

**Why not full SDK rebuild now:** the inspected upstream core CMake builds
tokenizer/ORT utilities, TTS, diarization and vendored dependencies, and expects
platform ORT headers/libraries. The partial text workspace is intentionally not
that complete build graph. Existing NDK/CMake tools are present, but no complete
source/dependency inventory or full build has been resolved/tested. This limited
JNI candidate avoids downloading/rebuilding those components. It also preserves
known core risks (Silero cross-session state, races, VAD tail policy); choosing a
full/core rebuild requires separate bounded dependency/source preparation review,
not an assertion that it is impossible or already verified.

## Packaging approval requirements (R1/R5; no adoption performed)

POM and Gradle `.module` dependency metadata are **external to the AAR** and were
not repacked. Publisher runtime declarations are appcompat **1.6.1**, Material
**1.10.0**, OkHttp **4.12.0**, work-runtime **2.9.1**. Those four declarations are
not a resolved transitive graph. A local `files(candidate.aar)` alone loses that
metadata; keeping the stock SDK dependency alongside it to borrow dependencies
can duplicate SDK classes/native binaries. `pickFirst` does not prove identity.

devS/user must explicitly select and authorize one route before build-only use:

1. **Metadata-preserving internal publication/substitution:** a distinct internal
   group/artifact/version with its own POM carrying reviewed publisher-equivalent
   dependency declarations (and refreshed Gradle module variants/hashes if supplied).
   Source/patch/notices delivery must identify the changed source. Replace the stock
   SDK provider; do not reuse Central 0.1.5 identity, POM/module checksums or source
   artifact identity for changed bytes. No coordinate/repository/publication chosen here.
2. **Explicit local-AAR feasibility graph:** devS supplies the reviewed four direct
   dependencies and resolves/records the complete graph explicitly, without also
   resolving the stock Moonshine AAR. This is a deliberate metadata replacement,
   not preservation automatically supplied by a `files(...)` dependency. Local
   packaging/signatures/classpath still need the isolated compile/package check.

For either route, approval must name the candidate hash, identity and exactly
**one class provider and one native-library provider per ABI**; check resolved
dependency/artifact reports and packaged payloads, not just matching filenames.
Retain ABI/core/ORT identities and notices, and verify real Android/AppCompat
classpath, merged offline permissions/backup rules, all native payloads and final
APK alignment. These app/shared checks belong to devS, not this bundle.

**Shrinker decision must be explicit.** JNI converters use literal SDK class,
constructor and field names. devS must review/deliver matching keep rules and
inspect the actual minified release output. App-owned keep rules or a separately
approved SDK consumer-rules addition are options, but adding rules to the AAR
would create a new payload/hash requiring fresh review; it was not done here.
Alternatively approve a specifically **non-minified feasibility build**, without
calling it a release-shrinker pass or production approval. Non-minification cannot
repair required-path JNI converter/loader allocation/lifetime defects.

No POM/module, consumer rules, Gradle changes, dependency substitution, SDK adoption
or integration build was produced by these documentation/test follow-ups.

## Reproduction and acceptance gates

Prior native-build command, repository root (historical, **not repeated** for the
author follow-ups):

```powershell
python -B docs/evidence/android/devj/sdk-fix/review.py --cross-build --run-name candidate-r3
```

Runner downloads nothing, refuses an existing run directory, and writes only
beneath the approved SDK-fix scratch root. Reproduction uses a new run name.
Supply the pinned source tree at `--source-root` and original AAR/source-JAR at
`--artifact-root` if defaults are unavailable. Restore missing text files only
from `https://raw.githubusercontent.com/moonshine-ai/moonshine/234f60faa0eb388b01cdf7e60aca232af37aefda/<inputs.json path>`,
check size before reading and SHA-256 against the manifest. No models are needed.
Without `--cross-build`, run only patch/desktop checks (existing host C++ + JDK).

`review.py` contains exact compiler/linker arguments and per-ABI targets;
each run's `results.json` records actual full argv, exit code and log paths.
All three builds/check suites exited 0. Per-ABI `*-elf.log` / `*-add-disassembly.log`
provide notes, dependencies, alignment and binary evidence. Additional first-run
`*-jni-driver.log` (-###, no build), `arm64-unwind-cleanup.log` and
`build-dependencies.json` record linker expansion/cleanup/dependency identity.
Host compiler requires its existing MSYS2 DLL search path; runner supplies it,
without installation or machine-wide PATH change.

### Author follow-ups to independent review

Read `SDK_FIX_REVIEW.md` fully. Addressed author R1/R3/R4/R5 through this proposal
and test/review bundle only. Independent review, artifact findings, the two narrow
patches and existing candidate archives were not edited. R2 remains an explicit
required-path native gate, not a source repair within this scope.

Actual targeted follow-up command, **one host-suite run**, exit 0:

```powershell
python -B docs/evidence/android/devj/sdk-fix/review.py --run-name author-followups-r1
```

New logs/results are beneath the approved scratch SDK-fix directory at
`author-followups-r1/`; prior directories preserved. Ordinary patch checks and
16 host fake-JNI/core scenarios passed. Ten Java output groups passed, including
the exact automatic-null/cadence and `LineCompleted` non-redelivery regressions,
512 residue SDK-Stop/order executions, P=0/empty/no-new fake audio, Pause accounting,
rejected/throwing/post-acceptance failures, terminal no replay, duplicate Stop and
checked overflow disposition. Fake `newAudioSamples`/call tracing is observability
only, **not a native VAD model or production acceptance hook**.
Read-only post-run comparison verified the tested `Transcriber.class` remains
byte-identical to candidate-r3, and both patch hashes and the prior AAR hash match.

Only the test instrumentation/runner and documentation changed; no native or Java
SDK source/payload changed. The prior candidate AAR hash
`3936002d9ff6e14cba0d41af7c3d1ccc4f7b4309f441f1d7029337e1cb700d3e` remains applicable;
published input AAR hash remains `ee2d95c21150683c743db8f3aef66281fd5408bcefc94be3ca1d2545ada1f571`.
This follow-up is **not a rebuilt native result**. Python optimization is now
explicitly refused so preservation assertions cannot be disabled. Full tool/header/
runtime/JDK/Python/zlib/stub-donor closure identity remains a final reproducibility
gate; observed prior repeated hashes are not a hermetic cross-machine guarantee.

Before any adoption, devS/user must review:

1. JNI release/exception semantics and Java API/status/empty-input changes; validate
   with real Android dependency classpath, all JNI exports and Android load/link.
2. Exact 16-kHz/hop512 Stop padding policy versus separately scoped core fix;
   explicit timestamps, idempotence and fail-closed Pause scheduling.
3. The packaging/shrinker route above: distinct internal identity, POM/module or
   explicit graph, resolved transitives, one class/native provider, consumer rules
   or explicitly non-minified feasibility scope, source/patch/license delivery and
   final reproducibility. Redistribution/disclosures remain incomplete.
4. Preserved 0.1.5 core risks: second-session Silero state and free/in-flight races;
   strict serialized lifecycle is necessary but does not fix recurrent state.
5. Separately authorized phone gates: real tail speech, Pause/resume/Stop paused,
    unknown/2/4 speakers, repeated sessions, no synthetic hallucinations, callback
    barrier, required JNI converter/loader failure/lifetime/GC behavior, disposal,
    memory growth, timing, offline and native compatibility. Required-path fixes
    and recurrent-state fixes need separate scoped review before production approval.

**Smallest next gate:** user/devS record approval of exact SDK-fed 16-kHz/hop512
versus separately scoped resampling/core work, bounded fail-closed Pause trial,
candidate identity/dependency graph/one-provider packaging, and keep-rule versus
explicitly non-minified feasibility scope. Explicitly retain required JNI-path
and second-session risks; then separately authorize **one isolated build-only
compile/package check** in the existing integration work. No production adapter,
M0 clearance or phone work follows automatically. Integration/Flutter work remains
with its separate owners.
No dependency adoption or production adapter is inferred from “Prepare reviewed
fix.” Redmi remains off; deployment/device testing needs new explicit permission.
