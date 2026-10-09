# Portable integration preparation

These text patches preserve the v2 authored integration work. They do **not**
contain the Flutter shell, model/toolchain binaries, or a committed merge.

Inputs at preparation time:

- devS: `559267737b8c7a72a2233123b10957f31493287b`.
- `jai-flutter`: `73db4b676faff8f6e336fd7ad663f87198a4d17d`.

## Apply through the reviewed integration flow

1. Merge the existing shell and latest devS work in an isolated feature branch.
2. Resolve the plugin conflict with devS's real `ReviseEnginePlugin.kt`, not the
   shell's placeholder. Union `.gitignore` entries and retain both README sections.
   `conflict-resolutions.patch` records the final ignore/README content **relative
   to devS 5592677**, for comparison/manual resolution; it is not an automatic patch
   against an already merged or newer README/ignore file.
3. `shell-wiring.patch` is relative to the shell's three unmodified files. After
   merging/resolving, run from the project root:

   ```powershell
   git apply --check docs/evidence/android/devj/integration/shell-wiring.patch
   git apply docs/evidence/android/devj/integration/shell-wiring.patch
   ```

   It adds the documented backend Gradle apply line, main manifest network/backup
   controls, and a truthful MainActivity factory-status comment. If files have
   evolved, review/adapt the hunks instead of forcing/reverting anyone's changes.
4. Review the merged manifest, dependencies, asset packaging and default speech
   rejection; restore ignored wrapper/local setup and run actual app checks.

The portable wiring patch has been apply-checked against temporary copies of the
exact shell inputs. This is not a build, SDK adoption or device test. Evidence and
historical worktree/index state are in `../INTEGRATION_PREP.md`.
