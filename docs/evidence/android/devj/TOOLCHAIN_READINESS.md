# Android toolchain readiness (host only)

October 10, 2026. **Verified side-by-side Flutter installed; Dart toolchain gate
cleared. No app build attempted.** Strict offline backend builds remain blocked
by absent customary Maven caches and the original checkout's missing shell.
Initial observations below are historical; see the approved follow-up first.
The Redmi can remain off. The initial review changed only this document; it did not
access the integration-prep checkout, execute Gradle/Flutter builds, probe devices,
install/download tools or SDKs, change configuration, switch branches, or stage.
Small public release-document/metadata requests were made, not binary downloads.

## Approved side-by-side follow-up (October 10)

User approved the large official Flutter SDK download plus ordinary Flutter cache
provisioning, preserving the existing installation and global PATH/configuration.
No integration checkout access, app build, model/Android SDK/JDK installation or
device operation is included.

- Correct publisher metadata endpoint discovered in the official archive page's
  deferred code, `https://docs.flutter.dev/main.client.dart.js_3.part.js`:
  **`https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json`**.
  HTTP **200** through local PowerShell. Earlier URL with `/flutter/releases/`
  still returned **404**, independently checked through webfetch and PowerShell.
  The earlier failure was not proof that a compatible release was unavailable.
- Selected official stable Windows **x64 Flutter 3.47.6**, Dart metadata **3.13.5**,
  framework **`5fc346839b5d0eef006ed8404392afb4dfae428d`**, release timestamp
  **`2026-10-01T19:02:49.167367Z`**. This is now publisher metadata, not the
  earlier secondary-index inference. No guessed release URL was used.
- Official archive URL:
  `https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.47.6-stable.zip`.
  HEAD HTTP **200**, advertised bytes **1,933,193,895**.
  Publisher SHA-256:
  **`a01bb0d26de91bc23c97cd9ccfaad281a612fb8304213fdd5df1119a09404796`**.
- Approved distinct installation root:
  `C:\Users\jeush\AppData\Local\Temp\opencode\flutter-toolchain-3.47.6`;
  **accepted SDK path**:
  **`C:\Users\jeush\AppData\Local\Temp\opencode\flutter-toolchain-3.47.6\flutter`**.
  Root did not exist before download. Exact byte count and SHA-256 matched before
  extraction; a second `Get-FileHash` of the stored ZIP independently matched the
  publisher SHA-256 above. ZIP retained: **1,933,193,895 bytes**, **23,085 entries**,
  **3,485,959,573 bytes uncompressed** (archive inventory, not allocated disk size).
- **Actual acceptance:** direct bundled `dart.exe --version` exited 0:
  `Dart SDK version: 3.13.5 (stable) ... on "windows_x64"`.
  Flutter CLI `--suppress-analytics --no-version-check --version --machine` exited
  **0**, reports **3.47.6**, Dart **3.13.5**, framework hash above, engine
  **`692136cb6582dbfc5af3fb33c2515a069f2f66d0`**, and the exact accepted root.
  The first CLI attempt timed out at **120 seconds** rebuilding the Flutter tool;
  no lingering Dart process for this SDK was found. Retry with a 600-second
  budget completed successfully. This was tool bootstrap, **not an app build**.
- Ordinary Flutter tool bootstrap resolved/downloaded its pub dependencies into
  isolated `flutter-toolchain-3.47.6\pub-cache`: **10,318 files / 118,764,282 bytes**.
  The post-bootstrap SDK contains **18,816 files / 3,483,767,773 bytes**. These are
  file-byte sums, not allocated disk sizes; the retained ZIP is additional storage.
- Explicit `precache --android` exited **0**, with publisher storage forced to
  `https://storage.googleapis.com` process-locally. The bundle already provides
  all ten inspected Android ABI/mode directories and its matching Android engine
  stamps. No additional artifact path or changed artifact file size appeared
  relative to the bundle. Post-provision artifact inventory: **167 files /
  1,833,932,878 bytes**. Local per-file SHA-256 manifest
  `artifact-files-sha256.json` has SHA-256
  `7edc37b815768f1474397a32e6b289cb896956efb115f0826396c78ddc5ea74f`;
  these local hashes are not separate publisher attestations.
- All Flutter CLI attempts used an isolated `verification-profile` for
  `USERPROFILE`, `HOME`, `APPDATA`, `LOCALAPPDATA`, the isolated pub cache, `CI=true`,
  telemetry suppression and no version freshness check. Selected JBR/Android
  paths were process-local. Version dispatch and explicit precache avoid device
  discovery; no doctor, devices, adb, run, instrumentation or app build executed.
- Publisher metadata, `selected-release.json`, `archive-verification.json`,
  `flutter-version-runtime.json`, `android-precache.log`, `cache-summary.json`,
  `artifact-files-sha256.json` and `runtime-acceptance.json` are retained under the
  installation root. Only this owned evidence document changed in the checkout.
- Preservation baseline: existing `develop\flutter\bin\cache\flutter.version.json`
  SHA-256 `3c0331fa8781f925ac39fcce1bac25fc5b14c05b9682980208c5c78be6a9adfd`.
  Post-install metadata hash is **unchanged**. Ordinary `Get-Command flutter/dart`
  still resolves `develop\flutter\bin`; Java resolves Oracle `javapath`.
  User `.flutter_settings` remains absent; a fresh shell still has unset
  `JAVA_HOME`/`ANDROID_HOME`. No global PATH/config or old Flutter installation
  was edited. Branch remains `devj/android-captions-speakers`; evidence unstaged.

**Host readiness now:** existing JBR **25.0.2**, SDK API **36**, build-tools
**36.0.0**, NDK **28.2.13676358**, cached Gradle **9.3.1**, and the accepted Flutter
above form the minimum-install tool selection. New SDK defaults were inspected
again: compile/target 36, min 24, NDK 28.2.13676358. New SDK also contains cached
wrapper scripts/JAR for devS's reviewed restoration. A coordinated host build
can be *attempted after the integration owner authorizes that next task*, but
this review does not claim it passes or authorize changing integration-prep.
Original checkout still has no pubspec. Moonshine/LiteRT-LM customary Gradle cache
directories were rechecked and are still absent: fully offline backend resolution
is **not ready**. No model, Android SDK or JDK installation was performed.

Executed version/cache entry points (with the isolated environment described
above; no app or Gradle execution):

```powershell
$flutterRoot = 'C:\Users\jeush\AppData\Local\Temp\opencode\flutter-toolchain-3.47.6\flutter'
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:ANDROID_HOME = 'C:\Users\jeush\AppData\Local\Android\Sdk'
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
& "$flutterRoot\bin\cache\dart-sdk\bin\dart.exe" --version
& "$flutterRoot\bin\flutter.bat" --suppress-analytics --no-version-check --version --machine
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.googleapis.com'
& "$flutterRoot\bin\flutter.bat" --suppress-analytics --no-version-check precache --android
```

## Initial read-only checks actually performed

Read `ANDROID_IMPLEMENTATION_PLAN.md`, `ANDROID_WORK_SPLIT.md` and
`M0_FINDINGS.md`. Original checkout remains `devj/android-captions-speakers`, HEAD
`cf88c8689ffdeb9e9e336a77c27a9502e323bca2`; no integrated root Flutter project.
Inspected shell through `git show`/`git ls-tree`, not a mutable worktree:
`origin/jai-flutter` = `73db4b676faff8f6e336fd7ad663f87198a4d17d`.

| Component | Actual local evidence | Selection / consequence |
| --- | --- | --- |
| Flutter | PATH `C:\Users\jeush\develop\flutter\bin\flutter.bat`; cached version JSON: stable **3.47.2**, framework `d3b14c876900e553bc736ca19295fc09e3853e8e`, engine `a804b261645ef8c13eb3d5c44a5c2fb0340c5539` | Not sufficient for unchanged shell. Version JSON read; Flutter CLI not executed. |
| Dart | Direct bundled `bin\cache\dart-sdk\bin\dart.exe --version`: **3.13.2** | Shell pubspec **and lockfile** require `>=3.13.5 <4.0.0`. Hard resolver blocker; standalone newer Dart does not upgrade Flutter's bundled Dart. |
| PATH Java | `C:\Program Files\Java\jdk-26.0.2.1\bin\java.exe -version`: **26.0.2.1**; PATH resolves Oracle `javapath` | **Do not run Gradle 9.3.1 with this JVM**: Java 26 unsupported. |
| Existing usable JDK | `C:\Program Files\Android\Android Studio\jbr\bin\java.exe -version` and `javac.exe -version`: **25.0.2** | Minimum-install option: explicitly select this JBR. Gradle 9.3.1 supports Java 17–25; app bytecode target 17 is separate from host JVM. Android task compatibility still requires a real build. |
| Android SDK | `C:\Users\jeush\AppData\Local\Android\Sdk` | Existing API **36** platform revision 2 (`android.jar` present), build-tools **36.0.0** (`aapt2.exe` present), NDK **28.2.13676358 / r28c**, cmdline-tools **23.0** under `latest`; platform-tools and sdkmanager files present, not invoked. Other platform folders: 34/35/37.0. No SDK install indicated by these pins. |
| Gradle | Cached launcher `C:\Users\jeush\.gradle\wrapper\dists\gradle-9.3.1-all\9ot9r568e8zfvvd4mn8rbu1j0\gradle-9.3.1\bin\gradle.bat`; launcher/wrapper JARs present | ZIP `.ok` marker plus read-only JAR build receipt confirms **9.3.1**, non-snapshot, commit `44f4e8d3122ee6e7cbf5a248d7e20b4ca666bda3`. No Gradle execution/build proof. No PATH Gradle needed. |
| Project wrapper | Shell tracks only `android/gradle/wrapper/gradle-wrapper.properties`, URL `gradle-9.3.1-all.zip` | `gradlew`, `gradlew.bat`, wrapper JAR **not tracked**. Existing Flutter cache contains all three under `bin\cache\artifacts\gradle_wrapper`; devS must approve/provide wrapper restoration, not regenerate an app. |
| Dependency caches | AGP **9.1.0** and KGP **2.4.0** POM/JAR files present. Every hosted package/version in shell's lockfile has a cached pubspec. Existing Flutter cache has Android ABI/mode directories. | Presence is not full cache integrity/resolution proof. Normal Maven cache has **no `ai.moonshine:moonshine-voice` or `com.google.ai.edge.litertlm:litertlm-android` directory**. Strict offline backend resolution is blocked at this snapshot. |

`JAVA_HOME`, `ANDROID_HOME`, `ANDROID_SDK_ROOT`, `FLUTTER_ROOT` and
`GRADLE_USER_HOME` were unset; no PATH `gradle`/`kotlinc`. No JDK/SDK selection
override found in customary Flutter settings or user Gradle properties locations.
`licenses/android-sdk-license` exists; acceptance/completeness was not tested.
Bounded customary checks covered `develop`, common Flutter roots, FVM roots,
user `.jdks`/Gradle `jdks`, and common Java vendor installation directories.
Only the Flutter SDK above, Oracle 26 and Studio JBR 25 were found; **no JDK 17/21
or compatible alternate Flutter found in those locations** (not a whole-disk claim).

## Pins and minimum viable decision

- Retain shell **AGP 9.1.0 / KGP 2.4.0 / Gradle 9.3.1-all**, Java/Kotlin target
  **17**, namespace `com.larpcode.revise`. Flutter's official 3.47 release matrix
  names this Android trio; Kotlin's current matrix also supports it.
- Installed Flutter defaults are compile/target **36**, min **24**, NDK
  **28.2.13676358** (`FlutterExtension.kt` inspected). devS must set minSdk
  **at least 26**, then validate merged requirements against the resolved backend.
- Shell has `android.newDsl=false` and `android.builtInKotlin=false`, KGP declared
  `apply false` in settings, no explicit app KGP application. Local Flutter code
  contains fallback KGP application for this case. This is **not proven broken**;
  preserve/review with devS rather than casually changing AGP/Kotlin flags.
- **Initial recommendation, superseded by approved follow-up above:** provide a side-by-side pinned compatible Flutter SDK,
  not an in-place `flutter upgrade` and not a lower Dart constraint. Candidate:
  **Flutter 3.47.6**, official framework tag commit
  `5fc346839b5d0eef006ed8404392afb4dfae428d`, engine
  `692136cb6582dbfc5af3fb33c2515a069f2f66d0`. Secondary release index reports
  bundled **Dart 3.13.5**; official tag/engine confirmed, but the official archive's
  Windows JSON returned 404 and its table was dynamic. **Verify official bundle
  metadata/checksum and actual bundled Dart before accepting this candidate.**
  Initial proposed `develop\flutter-3.47.6` location was **not used**; approved
  destination is under `Temp\opencode`, as recorded above.
- **No JDK installation currently necessary:** try existing JBR 25.0.2 explicitly.
  If Android build tasks reject it, request approval for a side-by-side pinned
  **JDK 17** (AGP's documented default); do not upgrade Gradle to accommodate Java 26.
- devS owns reviewed shell integration, ignored local properties/wrapper, exact
  native dependencies **Moonshine 0.1.5 / LiteRT-LM 0.18.0**, minSdk and packaging.
  Missing Maven artifacts/transitives and any new Flutter engine artifacts need
  **approved cache preparation/downloads** before a reproducible offline build.
  SDK-artifact defects in `M0_FINDINGS.md` remain a separate review gate; this
  document neither repairs them nor certifies the other agent's artifact work.

## Proposed deterministic host checks (NOT executed)

SDK acceptance is complete. The commands below remain **unexecuted** and require
approval for host checks, integration into this original checkout, wrapper/local setup
by devS, and coordination with the other build owner. Run in a fresh PowerShell
at the integrated project root. These selections are process-local, not global:

```powershell
$ErrorActionPreference = 'Stop'
$flutterRoot = 'C:\Users\jeush\AppData\Local\Temp\opencode\flutter-toolchain-3.47.6\flutter'
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:ANDROID_HOME = 'C:\Users\jeush\AppData\Local\Android\Sdk'
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$env:PUB_CACHE = 'C:\Users\jeush\AppData\Local\Pub\Cache' # earlier locked app packages
$env:PATH = "$env:JAVA_HOME\bin;$flutterRoot\bin;$env:PATH"
$gradle = 'C:\Users\jeush\.gradle\wrapper\dists\gradle-9.3.1-all\9ot9r568e8zfvvd4mn8rbu1j0\gradle-9.3.1\bin\gradle.bat'
if (!(Test-Path '.\pubspec.yaml')) { throw 'Reviewed shell not integrated' }
$v = Get-Content "$flutterRoot\bin\cache\flutter.version.json" -Raw | ConvertFrom-Json
if ($v.frameworkVersion -ne '3.47.6' -or $v.dartSdkVersion -ne '3.13.5' -or
    $v.frameworkRevision -ne '5fc346839b5d0eef006ed8404392afb4dfae428d') {
    throw 'Candidate SDK metadata mismatch; obtain approved exact selection'
}
& "$flutterRoot\bin\cache\dart-sdk\bin\dart.exe" --version
if ($LASTEXITCODE) { throw 'Dart check failed' }
& "$env:JAVA_HOME\bin\java.exe" -version
if ($LASTEXITCODE) { throw 'JBR check failed' }
& $gradle --version
if ($LASTEXITCODE) { throw 'Gradle check failed' }
& "$flutterRoot\bin\flutter.bat" --suppress-analytics --no-version-check pub get --offline --enforce-lockfile
if ($LASTEXITCODE) { throw 'Offline/locked pub resolution failed; do not upgrade lockfile' }
& "$flutterRoot\bin\flutter.bat" --suppress-analytics --no-version-check analyze --no-pub
if ($LASTEXITCODE) { throw 'Analysis failed' }
& "$flutterRoot\bin\flutter.bat" --suppress-analytics --no-version-check test --no-pub
if ($LASTEXITCODE) { throw 'Flutter tests failed' }
& $gradle -p .\android --offline --no-daemon `
    "-Dorg.gradle.java.home=$env:JAVA_HOME" `
    '-Dorg.gradle.java.installations.auto-download=false' `
    '-Pandroid.builder.sdkDownload=false' `
    '-Ptarget-platform=android-arm64' '-Ptarget=lib/main.dart' `
    :app:testDebugUnitTest :app:lintDebug :app:assembleDebug
if ($LASTEXITCODE) { throw 'Android host checks failed; record exact first failure' }
```

Before those commands, devS supplies ignored `android/local.properties` containing
the following (reconcile existing entries; **do not overwrite another owner's file**):

```properties
sdk.dir=C:/Users/jeush/AppData/Local/Android/Sdk
flutter.sdk=C:/Users/jeush/AppData/Local/Temp/opencode/flutter-toolchain-3.47.6/flutter
```

The cached launcher avoids a wrapper bootstrap download for initial checks.
After devS restores/reviews the wrapper, replace `& $gradle -p .\android` with
`& .\android\gradlew.bat -p .\android` using the same arguments. Pin the wrapper's
`distributionSha256Sum` to publisher value
`17f277867f6914d61b1aa02efab1ba7bb439ad652ca485cd8ca6842fccec6e43`
(text checksum endpoint read; cached distribution itself not rehashed).
`--offline` does not provision missing dependencies; stop rather than silently
retry online. Flutter may need missing engine/tool artifacts even with offline
pub; those must already be provisioned by the approved SDK setup.

No `flutter doctor` (device discovery), `flutter run`, `adb`, install task,
connected instrumentation, or data operation is proposed here. Host APK/test
success would not prove native inference, JNI safety, microphone behavior or M0.
If “desktop build” means a Windows app, the inspected shell has **no Windows
runner** and this Android backend is not a desktop implementation; no runner
generation is authorized or needed for host Android APK builds.

## Authoritative references consulted

- [Gradle 9.3.1 JVM compatibility](https://docs.gradle.org/9.3.1/userguide/compatibility.html): 17–25, not 26.
- [AGP 9.1 release notes](https://developer.android.com/build/releases/agp-9-1-0-release-notes): Gradle 9.3.1, build-tools 36.0.0, default NDK 28.2.13676358, JDK minimum/default 17. Page currently headed 9.1.1; exact 9.1.0 trio corroborated by Flutter below.
- [Flutter 3.47 official Android matrix](https://flutter.dev/blog/whats-new-in-flutter-3-47), [KGP supported matrix](https://kotlinlang.org/docs/gradle-configure-project.html), [Flutter Kotlin migration guidance](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers).
- [Official Flutter 3.47.6 tag](https://github.com/flutter/flutter/releases/tag/3.47.6), [engine pin](https://raw.githubusercontent.com/flutter/flutter/3.47.6/bin/internal/engine.version), [SDK archive](https://docs.flutter.dev/install/archive), [current official Windows release metadata](https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json). Earlier secondary Dart mapping was only a candidate lead; acceptance used publisher metadata, archive SHA-256 and actual binaries.
- [Gradle distribution checksum](https://services.gradle.org/distributions/gradle-9.3.1-all.zip.sha256).
