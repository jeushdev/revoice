# Preserved publisher metadata

Retrieved October 9, 2026. Files are reference metadata, not executable project
code. The preparation script validates its lock against the two canonical
size/checksum sources without needing network access during verification.

| Snapshot | Publisher URL |
| --- | --- |
| `moonshine-model-file-metadata.generated.cpp` | <https://raw.githubusercontent.com/moonshine-ai/moonshine/234f60faa0eb388b01cdf7e60aca232af37aefda/core/moonshine-model-file-metadata.generated.cpp> |
| `moonshine-model-catalog.cpp` | <https://raw.githubusercontent.com/moonshine-ai/moonshine/234f60faa0eb388b01cdf7e60aca232af37aefda/core/moonshine-model-catalog.cpp> |
| `gemma-metadata.json` | <https://huggingface.co/api/models/litert-community/Gemma3-1B-IT/revision/a6306a4e292016480083b73b8dc6f3f939ae04c3?blobs=true> |
| `pyannote-metadata.json` | <https://huggingface.co/api/models/pyannote/speaker-diarization-community-1/revision/3533c8cf8e369892e6b79ff1bf80f7b0286a54ee> |

The Moonshine catalog defines the required file lists; its generated metadata
provides the corresponding lengths and CRC32C values. Gemma's LFS metadata
provides its size and SHA-256. Upstream pyannote metadata records model licensing;
the actual diarization binaries are pinned by Moonshine's checksums.

Moonshine SHA-256 values in the lock were computed from the actual downloads
after their sizes and publisher CRC32C values passed verification. They are local
reproducibility pins, not SHA-256 values published by Moonshine.

License snapshots: Moonshine's `LICENSE` and `core/cpp-annote/LICENSE` at the same
commit, CC-BY-4.0 text from <https://github.com/creativecommons/legalcode/blob/main/by_4.0.txt>,
and official Google Gemma terms/prohibited-use pages. See
`THIRD_PARTY_NOTICES.md` for applicability.
