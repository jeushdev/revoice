#requires -Version 7.0
<#
.SYNOPSIS
Runs the native backend's dependency-free JVM checks without Flutter, a phone or Gemma.
.DESCRIPTION
Use -LiteRtClassesJar and -AndroidJar to additionally compile the Android/LiteRT adapters.
This is not a Gradle, APK, instrumentation, or real-inference test.
#>
[CmdletBinding()]
param(
    [string]$KotlinCompiler = 'C:/Program Files/Android/Android Studio/plugins/Kotlin/kotlinc/bin/kotlinc.bat',
    [string]$Java = 'C:/Program Files/Android/Android Studio/jbr/bin/java.exe',
    [string]$LiteRtClassesJar,
    [string]$AndroidJar,
    [string]$FlutterEmbeddingJar
)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath("$PSScriptRoot/..")
$source = "$repo/android/app/src/main/kotlin/com/larpcode/revise/backend"
$scratch = "$repo/work/kotlin-tests"
[IO.Directory]::CreateDirectory($scratch) | Out-Null
$core = @(Get-ChildItem -LiteralPath $source -Filter '*.kt' | Where-Object Name -NotIn @('LiteRtCrmRuntime.kt','AndroidModelAssets.kt') | ForEach-Object FullName)
& $KotlinCompiler @core "$repo/tests/kotlin/BackendTests.kt" -jvm-target 17 -include-runtime -d "$scratch/backend-tests.jar"
if ($LASTEXITCODE -ne 0) { throw 'Kotlin core/test compilation failed.' }
& $Java -jar "$scratch/backend-tests.jar"
if ($LASTEXITCODE -ne 0) { throw 'Kotlin backend checks failed.' }
if ($LiteRtClassesJar -or $AndroidJar) {
    if (-not $LiteRtClassesJar -or -not $AndroidJar) { throw 'Supply both LiteRtClassesJar and AndroidJar.' }
    $all = @(Get-ChildItem -LiteralPath $source -Filter '*.kt' | ForEach-Object FullName)
    $classpath = "$LiteRtClassesJar;$AndroidJar"
    if ($FlutterEmbeddingJar) {
        $all += "$repo/android/app/src/main/kotlin/com/larpcode/revise/ReviseEnginePlugin.kt"
        $classpath += ";$FlutterEmbeddingJar"
    }
    & $KotlinCompiler @all -jvm-target 17 -classpath $classpath -d "$scratch/android-api-check.jar"
    if ($LASTEXITCODE -ne 0) { throw 'Pinned Android/LiteRT API compilation failed.' }
    Write-Output 'Android and pinned LiteRT API compilation passed (no native execution).'
}
