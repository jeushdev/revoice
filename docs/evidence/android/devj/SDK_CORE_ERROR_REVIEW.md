# Full-core error propagation review

October 10, 2026. Review of upstream `234f60faa0eb388b01cdf7e60aca232af37aefda`
with unchanged patches 0001–0004. This is **not SDK adoption or Android runtime
acceptance**. See `SDK_FULL_CORE_REBUILD.md` for actual build/inference results.

## Required streaming route

- Patch 0004 throws fixed `std::runtime_error` / `std::invalid_argument` messages
  on Silero API, model-load, tensor, Run, output-access and chunk-size failures.
  Status objects and partial tensors are released. The shared singleton retries
  initialization after a failed constructor. No model paths or audio are added
  to these exception messages.
- `Transcriber::create_stream()` constructs the detector. A constructor failure
  reaches `moonshine_create_stream()`'s `std::exception` handler and becomes
  `MOONSHINE_ERROR_UNKNOWN` (-1), not a valid stream handle. A consumed stream ID
  can leave a gap, which callers must not interpret as an array index.
- **Append is buffering, not VAD inference.**
  `moonshine_transcribe_add_audio_to_stream()` calls `add_audio_to_stream()`;
  inference occurs later in `Transcriber::transcribe_stream()`, after the pending
  audio has been swapped into a local snapshot. The VAD exception reaches
  `moonshine_transcribe_stream()`'s `std::exception` handler and returns -1.
  The snapshot may already be consumed and detector clocks/look-behind advanced.
  Do not retry/replay accepted audio, even though recurrent history was not
  committed by the failed Silero prediction.
- The patched JNI update initializes its transcript pointer to null, checks the
  C API status **before conversion**, returns null on failure, and has a catch-all
  exception boundary. Thus this failure cannot become a converted cached
  transcript. Patch 0002's checked Java update rejects null; the default
  successful-return path is not permission to ignore this failure.
- JNI create/start/stop return C API integer statuses. Java create still returns
  its result **without checking a negative handle**; start/stop check nonzero
  status only after the native call returns. Patch 0001's
  append returns status and releases Java array storage on all paths.

The known Silero standard exceptions are caught by the C API, but **Java stream
creation is an unresolved adoption blocker**, not fully safe propagation.
`getDefaultStreamHandle()` can cache a negative create result and then pass it to
start. `Transcriber::start_stream()` uses map `operator[]` and dereferences the
result, so an invalid handle can cause a null dereference, not a catchable C++
exception. A direct JNI adapter must reject negative create results before any
start/update/free call; a separately reviewed Java/native handle correction is
needed before declaring the SDK wrapper safe. Patches 0001–0004 are preserved;
this review does not silently add or adopt a fifth patch.

The real desktop negative case intentionally uses a
256-sample VAD hop (unsupported by this fixed 512-sample model) to exercise the
complete rebuilt core → C API path, not a fake ORT failure or a supported app
configuration. JNI's corresponding null/status behavior is source-reviewed and
covered by the existing fake-boundary suite, **not run under ART here**.

## Limits that remain gates

- A C API caller must initialize/ignore its output pointer on error. The current
  C API catch does not explicitly null an arbitrary caller's preexisting pointer.
  JNI does initialize its local pointer. Never treat any transcript as valid
  after a failing status.
- No native "failed stream" latch is added. The adapter must terminate the
  operation on append/update/conversion failure, serialize lifecycle/feed calls,
  and prevent successful Pause/Stop delivery from stale data. Free is cleanup,
  not a successful final inference. JNI `moonshineFreeStream` is still a void
  wrapper that discards the C API free status.
- These C API handlers catch `std::exception`, not arbitrary non-standard C++
  exceptions. The known new Silero failures are standard exceptions. This is
  not a whole-C-ABI exception-safety claim.
- Invalid handles, general allocation failures elsewhere, optional model reload,
  nonstreaming JNI array lifetime, and free/in-flight races are not repaired or
  certified. No broad safety rewrite is included in this milestone.
- Stop-tail, capture-only Pause, diarization/speaker identity, final caption
  delivery, one-provider packaging, distinct artifact identity/dependency graph,
  and shrinker/runtime/device gates remain open.
