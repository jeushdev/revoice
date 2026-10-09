# Android model notices

Asset selection/preparation only. Runtime dependency and APK license inventories
must be completed after the Android build exists. Preserve these notices and the
applicable complete license texts in any distributed installation.

## Moonshine English Tiny Streaming

- Publisher: Moonshine AI / Useful Sensors, Inc.
- SDK/source: `v0.1.5`, commit `234f60faa0eb388b01cdf7e60aca232af37aefda`.
- Weights: `tiny-streaming-en/quantized_26_08_21`, downloaded unchanged.
- License: **MIT**, copyright (c) 2025 Useful Sensors, Inc. (dba Moonshine AI).
- Preserved publisher text: `models/licenses/MOONSHINE-LICENSE.txt`.
  The file also describes other, unselected non-streaming models' Community
  License; those restrictions do not apply to the selected English streaming STT.
- Source: <https://github.com/moonshine-ai/moonshine/tree/v0.1.5>.

## Diarization models (not covered merely by the STT license)

- Source models: **pyannote speaker-diarization-community-1**.
- Original publisher license: **Creative Commons Attribution 4.0 International**
  (`CC-BY-4.0`), as declared in preserved publisher metadata
  `models/provenance/pyannote-metadata.json` (revision
  `3533c8cf8e369892e6b79ff1bf80f7b0286a54ee`). This revision documents upstream
  licensing, not a claim about the exact original weights' conversion revision.
- Source: <https://huggingface.co/pyannote/speaker-diarization-community-1>.
- License: <https://creativecommons.org/licenses/by/4.0/>; full text in
  `models/licenses/CC-BY-4.0.txt`.
- Changes: Moonshine converted the segmentation and speaker-embedding models to
  ORT format; ReVise uses Moonshine's `diarization-community1/segmentation.ort`
  and `embedding.ort` unchanged. See the pinned
  [Moonshine diarization documentation](https://github.com/moonshine-ai/moonshine/blob/v0.1.5/docs/diarization-models.md).
- Attribution from the upstream model card:
  - Alexis Plaquet and Herve Bredin, *Powerset multi-class cross entropy loss for
    neural speaker diarization*, INTERSPEECH 2023 (segmentation).
  - Hongji Wang et al., *Wespeaker: A research and production oriented speaker
    embedding learning toolkit*, ICASSP 2023 (embedding).
  - Federico Landini et al., *Bayesian HMM clustering of x-vector sequences (VBx)
    in speaker diarization: theory, implementation and analysis on standard
    tasks*, Computer Speech & Language, 2022 (clustering).
- The cpp-annote implementation has a separate MIT notice, copyright (c) 2026
  Useful Sensors, Inc. (dba Moonshine AI), preserved in
  `models/licenses/CPP-ANNOTE-LICENSE.txt`. It is not a replacement for the
  upstream models' attribution/license.

## Gemma 3 1B IT INT4

- Original model publisher: Google. LiteRT deployment repository:
  `litert-community/Gemma3-1B-IT`.
- Revision: `a6306a4e292016480083b73b8dc6f3f939ae04c3`.
- Selected converted file: `gemma3-1b-it-int4.litertlm`; no additional ReVise
  conversion/fine-tuning or binary modification.
- License: **Gemma Terms of Use**, not MIT or Apache for these model weights.
- Official terms: <https://ai.google.dev/gemma/terms>.
- Prohibited-use policy: <https://ai.google.dev/gemma/prohibited_use_policy>.
- Complete publisher pages preserved on October 9, 2026 as
  `models/licenses/GEMMA-TERMS.html` and `GEMMA-PROHIBITED-USE.html`.
- Required Notice text under the terms:

  > Gemma is provided under and subject to the Gemma Terms of Use found at
  > ai.google.dev/gemma/terms

  Also preserved verbatim in `models/licenses/GEMMA-NOTICE.txt` for packaging.

The authorized developer obtains access and accepts terms personally. ReVise
must provide the agreement/Notice and reflect applicable use restrictions in
downstream distribution terms before distributing the model in an APK. A local
checksum pass is not legal clearance or inference verification.
