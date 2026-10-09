# Android model preparation evidence

October 10, 2026. Development-time asset verification only; this does not pass
the Android M0 runtime/device gate.

## Verified assets

| Stack | Files | Bytes | Integrity checks |
| --- | ---: | ---: | --- |
| Moonshine English Tiny Streaming, quantized `26_08_21` | 8 | 45,233,659 | Publisher lengths/CRC32C and pinned local SHA-256 |
| Moonshine community-1 diarization conversion | 2 | 8,570,000 | Publisher lengths/CRC32C and pinned local SHA-256 |
| Gemma 3 1B IT INT4, generic `.litertlm` | 1 | 584,417,280 | Publisher length and SHA-256 |
| **Total** | **11** | **638,220,939** | **All passed** |

Locations:

- `android/app/src/main/assets/revise/models/{stt,diarization,llm}/`
- Packaging inventory: `android/app/src/main/assets/revise/model-manifest.json`
- Reproducibility pins: `models/android-models.lock.json`
- Publisher metadata: `models/provenance/`
- License snapshots and attribution: `models/licenses/`, `THIRD_PARTY_NOTICES.md`

Gemma revision: `a6306a4e292016480083b73b8dc6f3f939ae04c3`.
Verified file: `gemma3-1b-it-int4.litertlm`.
SHA-256: `1325ae366d31950f137c9c357b9fa89448b176d76998180c08ceaca78bba98be`.

## Checks

From the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/prepare-android-models.ps1 -VerifyOnly
```

Result:

```text
Verified 11 files, 638,220,939 bytes. All Android model assets ready: True
```

Verification is offline and reads actual files rather than trusting the manifest's
readiness flags. The binaries are ignored by Git and have not been committed.
Credentials are not part of the asset inventory or evidence.

Setup tests:

```powershell
python -m unittest discover -s scripts/tests -v
```

Result: **16 tests passed**. Both PowerShell scripts also passed parser syntax
validation, and Git ignore checks confirmed the STT and Gemma binaries are excluded.

The tests cover integrity rejection, atomic publication, preservation of existing
files, canonical metadata pins, partial readiness, local hidden-token handling,
credential redirection restrictions, and sanitized HTTP diagnostics. They do not
exercise native inference or prove publisher access for another account.

## Remaining M0 work

- Obtain the team's agreed Flutter shell and pin the Android toolchain.
- Validate local-file Moonshine Tiny + diarization loading on the intended phone,
  with no SDK download worker or runtime network dependency.
- Prove pause/flush behavior while retaining speaker state.
- Load the selected Gemma file through LiteRT-LM CPU and test bounded context,
  output cap, cancellation/timeout, and the CRM fixtures.
- Preserve/package applicable license notices and confirm redistribution terms.
- Measure real device memory/storage/latency; no measurements are inferred from
  binary sizes. Fresh-install offline verification remains pending.
