# Android third-party inventory

This is the development inventory, not a completed redistribution notice bundle. Do not distribute the APK until exact packaged SDK/model notices and the accepted Gemma terms have been collected. No model weights are committed to this repository.

| Item | Exact selection | Publisher source / notice status |
| --- | --- | --- |
| Moonshine Android | `ai.moonshine:moonshine-voice:0.1.5`, source `234f60faa0eb388b01cdf7e60aca232af37aefda` | [Publisher license](https://github.com/moonshine-ai/moonshine/blob/v0.1.5/LICENSE); include its copyright/license and the native/transitive component notices |
| Speech weights | English Tiny Streaming `quantized_26_08_21` | Selected files/hashes in `model-manifest.json`; publisher license describes streaming/English models under MIT; preserve the applicable license text |
| Diarization weights | Moonshine `diarization-community1`, segmentation and embedding | [Publisher origin documentation](https://github.com/moonshine-ai/moonshine/blob/v0.1.5/docs/diarization-models.md) identifies pyannote community-1; obtain the corresponding upstream model notices/conditions rather than assuming the STT license covers these files |
| LiteRT-LM Android | `com.google.ai.edge.litertlm:litertlm-android:0.18.0` | [Publisher license](https://github.com/google-ai-edge/LiteRT-LM/blob/v0.18.0/LICENSE); Maven POM declares Apache-2.0; preserve native/transitive notices too |
| Gemma weights | `gemma3-1b-it-int4.litertlm`, revision `a6306a4e292016480083b73b8dc6f3f939ae04c3` | [Pinned model repository](https://huggingface.co/litert-community/Gemma3-1B-IT/tree/a6306a4e292016480083b73b8dc6f3f939ae04c3), [Gemma terms](https://ai.google.dev/gemma/terms); authorized acquisition and redistribution notice collection pending |

The LiteRT 0.18.0 POM resolves Gson 2.14.0, Kotlin reflect 2.4.0, and kotlinx-coroutines-android 1.11.0. This is publisher dependency metadata, not the final app's resolved dependency lock. Record the actual combined build and collect notices from its resolved artifacts, including Moonshine's native libraries.
