# Full pinned Moonshine native review

October 10, 2026. **Full native rebuild and real desktop inference passed;
review-only, not adopted or packaged.**
Base fix commit is `c1c00c5`; upstream remains
`234f60faa0eb388b01cdf7e60aca232af37aefda`. Patches 0001–0004 and the existing
source, AAR, ORT and NDK pins are unchanged. No app dependency, Flutter/UI/iOS
work, microphone, phone/ADB, installation or SDK publication is changed by this
milestone. The user subsequently authorized committing/pushing the review
scripts and evidence on `review/android-shell-devj-handoff`; no binaries or app
dependency adoption are included.

## Verified acquisition and route

The public exact-revision GitHub archive was acquired without credentials or a
gated model request: 176,944,864 bytes, SHA-256
`6bd927a48234dced3cc6f208522fe176c248686e9283273c51eddc8d7994e001`.
The raw recursive Git tree response is separately pinned in
`sdk-fix/full-core-inputs.json`; it is not truncated.

`sdk-fix/prepare_full_core.py` is offline and refuses to overwrite its output.
It verifies archive/tree/AAR hashes, **785 scoped upstream inputs** (82,239,862
bytes), Git blob IDs, existing source pins, and then all four patches together.
Resolved LFS data is checked against original pointer blob IDs **and** content
SHA-256/size. The pointer text is in `full-core-lfs-pointers.json`. Scoped inputs
include the complete core, vendored Eigen/kaldi/kissfft/UTF-8/utf8proc/JSON/ORT
headers, TTS sources, Android binding, root license and two public upstream WAVs.
Unrelated platform binaries are not extracted into the prepared build source.
The archive itself contains upstream LFS payloads; no separate gated download
was attempted.

- Real embedded header: `core/silero-vad-model-data.h`, 15,335,389 bytes,
  SHA-256 `df9af551f0c4a4afffed0c64fae265122fa55fcd8247df0f64cc37a0c8551884`.
- Its actual payload is **ORT format**, despite the historical `_onnx` symbol:
  2,421,272 bytes, `ORTM` identifier, SHA-256
  `a620103ef77fbdae23c7798b9271506a48a883997e55f851d2884551e0947437`.
  This is the exact upstream embedded model, not a regeneration or stand-in.
- All three Android ORT libraries match their original upstream LFS oids and the
  original pinned `0.1.5` AAR. Only those unchanged ORT dependencies are resolved
  from the AAR; **published `libmoonshine.so` is never a build input**.
- Windows ORT DLL/import library are exact archive/Git-verified inputs. DLL
  SHA-256: `dec964ab1ee36cc9b0ae247d13b376627992fc57dec0454354017ab8fd84f1ea`.
- `review_full_core.py` verifies the canonical prepared-file manifest and every
  patched input again. Additional build-tool pins are separate from unchanged
  `ndk-inputs.json`. These are representative tool hashes, not a complete
  hermetic pin of every system SDK/compiler header.

The CMake review wrapper adds the **unchanged upstream core build graph**, with
TTS enabled. Android builds upstream `moonshine-jni` and all its source-built
dependencies at API26 with static libc++. Host uses VS2019/MSVC x64 and links the
complete core into the real inference fixture. Each run has separate output
directories; no object/binary overlay, fake helper, fake ORT or
`vad_test_support` include is used. Native rebuilds do not themselves provide a
Java/AAR/package identity or establish adoption readiness. Reproducible commands
and verified inputs are the goal; byte-identical binaries across paths/machines
are not claimed.

The VS2019 review wrapper explicitly enables `/Zc:externConstexpr`, Microsoft's
standard-conforming linkage option. The first full host attempt without it
failed with C2370 in upstream generated Spanish Unicode tables. No generated
table, model, runtime or upstream source was rewritten to pass the compiler.
The selected Windows SDK is 10.0.26100.0. Upstream MSVC builds still emit their
existing warnings (including ignored `-fPIC`); only the added host fixture uses
`/W4 /WX`. Android retains upstream warnings-as-errors and scoped vendor-warning
exceptions. This is not a warning-free/full-sanitizer host claim.

## Reproduction

Acquire the two URLs in `full-core-inputs.json` as **raw bytes**, and acquire the
original AAR specified by unchanged `inputs.json`. Verify their listed hashes.
Use fresh output/run names and supply local tool paths where needed:

```powershell
python -B docs/evidence/android/devj/sdk-fix/prepare_full_core.py --archive <archive.tar.gz> --tree <upstream-tree.json> --aar <original-0.1.5.aar> --output <fresh-prepared-directory>
python -B docs/evidence/android/devj/sdk-fix/review_full_core.py --source-root <fresh-prepared-directory> --run-name full-core-android-review --android --jobs 4
python -B docs/evidence/android/devj/sdk-fix/review_full_core.py --source-root <fresh-prepared-directory> --run-name full-core-host-review --host --assets <existing-revise-asset-root> --jobs 4
python -B docs/evidence/android/devj/sdk-fix/audit_full_core.py --run-name full-core-android-review --source-root <fresh-prepared-directory>
```

The optional `--assets` root contains `model-manifest.json` and `models/stt/`.
The runner verifies all eight existing STT files against their manifest before
real C API speech tests. It never downloads models or writes to the asset root;
the Gemma/LLM assets are not used. Without `--assets`, only real Silero/VAD
inference is requested, with C API speech explicitly reported as not run.

## Actual results

Source preparation `full-core-inputs/prepared-r3` passed all input and combined
patch checks. Initial preparation r1 exposed archive-materialized LFS data
instead of pointer blobs; it was rejected rather than bypassing verification.
The reviewed offline route now verifies that data using the original pointers.

All eight existing tiny-streaming-en `quantized_26_08_21` STT assets passed a
fresh read-only size/SHA-256 check. Their existing manifest SHA-256 is
`eedfe7dacf31375206807b55e6f77a224490b94afb445e913e7a058636fe97c7`.

`full-core-android-r1` exited 0: complete core and JNI linked for **arm64-v8a,
armeabi-v7a and x86_64**, using the real model and unchanged ORT libraries.
The ELF audit passed correct machine/SONAME/dependencies, **43 JNI exports** and
**44 JNI Moonshine imports resolved against the rebuilt core**, for every ABI.
No shared libc++ dependency was introduced. The final audit-enabled runner is
also **complete** in fresh `full-core-android-r2`: all three full links and ELF
captures exited 0, and `audit_full_core.py` independently passed all three ABIs.
Each build compiles **120 translation units** across the full core/JNI/static
dependency graph: 45 Moonshine, 1 JNI, 5 ORT utilities, 4 Moonshine utilities,
1 tokenizer, 1 utf8proc, 40 TTS core and 23 TTS ORT. Its reviewed build graph
explicitly includes all seven reviewed VAD consumer/binding units together.

Final r2 unstripped review outputs (not an AAR, deployment or approved identity):

| ABI | Library | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| arm64-v8a | `libmoonshine.so` | 98,946,504 | `f15892eb0d4ca5c609d0b87cfc182b0e6d0ea1a64b5be8c2727c65c4b1c98f32` |
| arm64-v8a | `libmoonshine-jni.so` | 1,254,560 | `9d3c1ff1813a9d30f9b994e06e20981df7ec77b9bf2492ea6609bf9829f1c183` |
| armeabi-v7a | `libmoonshine.so` | 82,477,432 | `4108fddde3734913c930a8d969fb8d918f68f80bc421bf2a03e7cccd50ab644c` |
| armeabi-v7a | `libmoonshine-jni.so` | 982,824 | `d6a67c96f6e66787cee50deba5693612d3d84364d2c459b0ca2af62eb98338e0` |
| x86_64 | `libmoonshine.so` | 95,888,360 | `59b5d4a728b2890b0a8acfe66d72f8bbe0ab3cc24804b6b1a026ff1a016ae015` |
| x86_64 | `libmoonshine-jni.so` | 1,165,312 | `599639f02e598eef3237bb0b07ab96196cff83b8f6f4cd9df76f9ed6e5863f8c` |

The r2 command/input/output manifest `results.json` SHA-256 is
`a183d788e6b3e56bf2c391836461051fec4e25ae87bba581376dca9ce69a003e`.
Commands, logs, source hashes, compile-command databases, native binaries and
ELF audit summaries remain local under
`%LOCALAPPDATA%/Temp/opencode/devj-moonshine-sdk-fix/full-core-android-r2/`.
The initial r1 builds are retained separately. Debug/build paths affect bytes;
different r1/r2 output hashes are not a deterministic-byte reproduction claim.

`full-core-host-r1` failed at the upstream/MSVC generated-table linkage issue.
**`full-core-host-r2` exited 0** with the documented standard-conformance flag:
the complete static Moonshine core/TTS/dependencies linked into the host
fixture, and actual **ORT 1.23.2** inference passed:

- Eight concurrent first-use detectors, with the real singleton/session.
- Real speech probabilities, 256 recurrent floats and 64 context samples agree
  between isolated and interleaved streams; explicit reset agrees with a fresh
  state. Invalid chunks reject without changing that history.
- **20 reused stop/start VAD sessions** agree with fresh per-hop segment/audio
  baselines, including a fresh B after A. Speech detection is required, not just
  empty-output equality.
- Interleaved per-hop VAD segment/audio/timing/flag outputs agree with isolated
  runs. Restarting A does not perturb B.
- A capture-only feed gap with **265 pending samples**, while another session
  runs, agrees with uninterrupted feeding. No Pause start/stop/reset is used.
- Existing hash-verified tiny-streaming-en models produce real nonempty text:
  **three repeated C API sessions** and interleaved A/B per-update outputs agree
  with isolated baselines for text, timing and completion. Stream-specific line
  IDs, latency and event-change flags are not compared/certified by this check.
- A real unsupported-hop VAD exception reaches the C API as
  `MOONSHINE_ERROR_UNKNOWN`, with the initialized output pointer still null.
  The failed stream is freed terminally; accepted audio is not retried/replayed
  and no successful final transcript is fabricated. This is not a real ORT OOM
  or kernel-fault injection test.

The fixture uses two pinned public upstream WAVs, real decode/resampling helpers,
the real embedded VAD model and the user's existing eight pinned STT assets.
It uses no fake ORT/helper/model implementations or private-state test overrides.
Audio after preparation is 192,512 / 192,000 samples at 16 kHz, in exact hops,
with 64 silence hops appended. This deliberate fixture framing does **not**
resolve arbitrary Stop tails or establish natural Pause caption finalization.
Speaker identification is disabled: diarization source is rebuilt, but real
diarization/speaker-session inference is not validated here.

Host review output hashes:

| Output | Bytes | SHA-256 |
| --- | ---: | --- |
| Full `moonshine.lib` | 106,497,840 | `e6499a94c352edd40adf53c9cc32a76b2e576ee42dba3ed87188aa4b7f944cbc` |
| Linked `real-vad-review.exe` | 12,391,424 | `961024766cc259e3a4b2585e30888b92d896e8b5edaccc5d9c3378e61fc045ec` |

The copied ORT DLL matches its pinned source hash above. Host `results.json`
SHA-256 is `8e0a8ad02f11d764f0dd332ed0f8f9346c8b226052823103b347cd8acbe2e8a6`;
real-inference log SHA-256 is
`cf5a24670c26481cce0da4da24a64a111f4b8168ab84530d41a23a4860446543`.
Full commands/input/output hashes and logs remain under
`%LOCALAPPDATA%/Temp/opencode/devj-moonshine-sdk-fix/full-core-host-r2/`.

The previous ten fake-ORT host groups, singleton retry, three
negative mutations, six Android object builds, 16 JNI scenarios, 403 required-path
cases and ten Java groups remain historical evidence—not real inference proof.

## Review limits

[`SDK_CORE_ERROR_REVIEW.md`](SDK_CORE_ERROR_REVIEW.md) records the real core →
C API → JNI error route and the unresolved **unchecked Java create-stream
handle** blocker. No fifth patch or SDK adoption is silently added.

No AAR repack, app build/adoption, Android runtime inference, ART/GC, sanitizer,
microphone, device or M0 acceptance is established by source acquisition or a
desktop test. Stop-tail, capture-only Pause, diarization/speaker identity,
callback/final caption delivery, distinct packaging identity/dependency graph,
one-provider and shrinker gates remain open before microphone integration.
