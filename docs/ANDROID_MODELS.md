# Android model preparation

This is development-time asset setup, not an Android runtime or a completed M0
device gate. No Flutter project or second app is generated.

## Pinned models

- Moonshine English Tiny Streaming, quantized `26_08_21`, SDK `0.1.5`:
  eight files, **45,233,659 bytes**. No word-attention decoder or spelling model.
- Moonshine's pyannote community-1 diarization conversion: two files,
  **8,570,000 bytes**.
- Gemma 3 1B IT INT4, generic `gemma3-1b-it-int4.litertlm`, LiteRT-LM `0.18.0`:
  **584,417,280 bytes**.

Total: **638,220,939 bytes (608.7 MiB)**, excluding code/native libraries and any
second copy extracted from the APK. Sizes are not memory/performance measurements.
Exact URLs, revisions, publisher sizes/checksums and local SHA-256 pins are in
`models/android-models.lock.json`. Canonical publisher metadata is preserved under
`models/provenance/`.

## Prepare on Windows

Two development entry points share the same native manifest schema:

- `scripts/prepare-android-models.ps1`: PowerShell 7, no Python dependency;
  `-SpeechOnly`, `-GemmaPath`, and `-VerifyOnly`. It downloads only public speech
  files and imports a verified local Gemma file.
- `scripts/prepare-android-models-python.ps1`: preserves devJ's Python 3.10+
  workflow below, including explicitly requested authenticated Gemma download.
  No pip packages are needed; pass `-PythonExecutable` if Python is not on PATH.

Run the Python workflow from the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/prepare-android-models-python.ps1 -MoonshineOnly
```

For Gemma, sign in and accept the publisher conditions in your own browser, then
download **only** `gemma3-1b-it-int4.litertlm` from this
[pinned revision](https://huggingface.co/litert-community/Gemma3-1B-IT/tree/a6306a4e292016480083b73b8dc6f3f939ae04c3).
Do not select `.task`, web, INT8, or chipset-specific files. Import your download:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/prepare-android-models-python.ps1 -GemmaFile "$HOME\Downloads\gemma3-1b-it-int4.litertlm" -AcceptGemmaTerms
```

The source download stays untouched. Gemma must match size **584417280** and SHA-256
**1325ae366d31950f137c9c357b9fa89448b176d76998180c08ceaca78bba98be**.
Alternatively, the script can download Gemma with your authorized Hugging Face
access after you have accepted the conditions:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/prepare-android-models-python.ps1 -DownloadGemma -AcceptGemmaTerms -PromptToken
```

Enter a read token from <https://huggingface.co/settings/tokens> at the hidden local
prompt. It is held in memory, never saved or printed. Without `-PromptToken`, the
script reads an existing `HF_TOKEN` environment variable or Hugging Face token
cache (`HF_TOKEN_PATH` / `HF_HOME` supported). Authentication is sent only to
HTTPS Hugging Face, and is stripped from redirects to CDN hosts. Download
requests still need access granted to your account; the flag does not accept
website terms or bypass the publisher's gate.

If Hugging Face returns `401`/`403`, confirm access to the **deployment repository**
`litert-community/Gemma3-1B-IT` using the same account that owns your token.
Accepting Google's original Gemma repository alone is not sufficient. A normal
Read token works with your account's granted access; for fine-grained tokens,
enable read access to public gated repositories you can access (and any relevant
repository restrictions). Errors identify the responding host without logging
signed download URLs, tokens, or response bodies. A CDN `403` can have a different
cause from Hugging Face authorization.

Do not paste access tokens into chat or source control. This development-only
download option is never invoked by the application.

Prepared files land at:

```text
android/app/src/main/assets/revise/
  model-manifest.json
  models/stt/            # eight files
  models/diarization/    # segmentation.ort and embedding.ort
  models/llm/            # gemma3-1b-it-int4.litertlm
```

The script checks lengths and publisher CRC32C (Moonshine) / SHA-256 (Gemma),
records SHA-256 for every prepared file, and publishes only verified temporary
files. Existing valid assets are reused; corrupt or unknown files are rejected,
not overwritten. On failure, verified binaries remain reusable; never treat an old
preparation report's `complete` value as a substitute for checking actual files.
The shared runtime inventory uses `group`, `sizeBytes`, `sha256`, `crc32c`, and
`sourceUrl`, matching Kotlin/Gradle/PowerShell. Gemma's runtime `sourceUrl` is null;
its acquisition URL stays in the development lock. Local `complete`/`verified`
flags live in ignored `work/android-model-preparation-report.json`, outside the
packaged assets. Partial Moonshine-only preparation reports `complete=false`.

## Offline verification / packaging preflight

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/prepare-android-models-python.ps1 -VerifyOnly
python -m unittest discover -s scripts/tests -v
```

`-VerifyOnly` performs no downloads/writes and exits nonzero if **any** required
asset is absent or fails integrity checks. `-MoonshineOnly -VerifyOnly` checks just
the speech/speaker stack, not full packaging readiness. The future Android build
must wire the full check (or equivalent Gradle verification) into its packaging
gate; there is no Gradle build in this checkout yet.

Model binaries are ignored by Git. Commit manifests, setup code, provenance and
notices only. A fresh clone must run preparation again.

## Loading and release handoff

devS's native extractor, CRM/controller/channel code and build checks are described
in [android-backend.md](android-backend.md). Shared-shell/speech integration and
real-device acceptance remain pending.

- Extract packaged files atomically into app-private storage with integrity and
  free-space checks. Use local file-based SDK loaders only.
- Moonshine: `MOONSHINE_MODEL_ARCH_TINY_STREAMING`, `identify_speakers=true`,
  `diarization_model_dir` pointing to the extracted diarization directory.
- LiteRT-LM: local `.litertlm` file, CPU baseline; release STT/diarization first.
- Package applicable license texts/notices from `THIRD_PARTY_NOTICES.md` alongside
  the assets. Confirm attribution/use restrictions before distributing an APK.
- Still pending: agreed Flutter shell, runtime integration, on-device loading,
  pause/flush proof, CRM fixtures, offline fresh-install and performance tests.
