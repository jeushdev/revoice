#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath("$PSScriptRoot/../..")
Import-Module "$repo/scripts/ModelIntegrity.psm1"
$scratch = Join-Path $repo ('work/model-tests/' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($scratch) | Out-Null
$template = Get-Content "$repo/android/app/src/main/assets/revise/model-manifest.json" -Raw
$passes = 0
function Assert([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Expect-Failure([scriptblock]$Action, [string]$Message) {
    try { & $Action | Out-Null } catch {
        if ($_.Exception.Message -notlike "*$Message*") { throw "Wrong failure: $($_.Exception.Message)" }
        return
    }
    throw "Expected failure containing: $Message"
}
function New-Fixture([string]$Name) {
    $root = Join-Path $scratch $Name
    $manifest = $template | ConvertFrom-Json
    foreach ($entry in $manifest.files) {
        $path = Join-Path $root $entry.path
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path)) | Out-Null
        [IO.File]::WriteAllText($path, '123456789', [Text.UTF8Encoding]::new($false))
        $integrity = Get-ModelIntegrity $path
        $entry.sizeBytes = $integrity.SizeBytes
        $entry.sha256 = $integrity.Sha256
        if ($entry.group -ne 'llm') { $entry.crc32c = $integrity.Crc32c }
    }
    $manifestPath = Join-Path $root 'manifest.json'
    $manifest | ConvertTo-Json -Depth 8 | Set-Content $manifestPath -Encoding utf8NoBOM
    @{ Root=$root; Manifest=$manifest; Path=$manifestPath }
}
function Save-Manifest($Fixture) { $Fixture.Manifest | ConvertTo-Json -Depth 8 | Set-Content $Fixture.Path -Encoding utf8NoBOM }
function Verify($Fixture, [switch]$SpeechOnly) {
    & "$repo/scripts/prepare-android-models.ps1" -ManifestPath $Fixture.Path -AssetRoot $Fixture.Root -VerifyOnly -SpeechOnly:$SpeechOnly
}
function Pass([string]$Name) { $script:passes++; Write-Output "PASS $Name" }

$fixture = New-Fixture 'valid'
$vector = Get-ModelIntegrity (Join-Path $fixture.Root $fixture.Manifest.files[0].path)
Assert ($vector.Crc32c -ceq '4waSgw==') 'CRC32C failed the standard 123456789 vector.'
Assert ($vector.Sha256 -ceq '15e2b0d3c33891ebb0f1ef609ec419420c20e320ce94c65fbc8c3312448eb225') 'SHA-256 vector failed.'
Pass 'independent SHA-256 and CRC32C known vector'
Verify $fixture | Out-Null
Pass 'complete local assets verify without network'

[IO.File]::WriteAllText((Join-Path $fixture.Root $fixture.Manifest.files[0].path), '923456789')
Expect-Failure { Verify $fixture } 'integrity failed'
Pass 'same-length corruption rejected'

$fixture = New-Fixture 'missing-llm'
[IO.File]::Delete((Join-Path $fixture.Root 'models/llm/gemma3-1b-it-int4.litertlm'))
Expect-Failure { Verify $fixture } 'Missing model asset'
Verify $fixture -SpeechOnly | Out-Null
Pass 'missing Gemma fails full check but allows explicit speech-only check'

foreach ($case in @('path','hash','duplicate','url')) {
    $fixture = New-Fixture $case
    switch ($case) {
        path { $fixture.Manifest.files[0].path = 'models/stt/../../escaped.ort'; $message = 'Invalid model manifest' }
        hash { $fixture.Manifest.files[0].sha256 = 'bad'; $message = 'Invalid model manifest' }
        duplicate { $fixture.Manifest.files[1].path = $fixture.Manifest.files[0].path; $message = 'duplicate asset path' }
        url { $fixture.Manifest.files[0].sourceUrl = 'https://example.com/adapter.ort'; $message = 'Unexpected Moonshine' }
    }
    Save-Manifest $fixture
    Expect-Failure { Verify $fixture } $message
    Pass "invalid $case rejected before preparation"
}

$fixture = New-Fixture 'gemma-import'
$localGemma = Join-Path $scratch 'authorized-local-fixture.litertlm'
[IO.File]::WriteAllText($localGemma, '123456789')
$packagedGemma = Join-Path $fixture.Root 'models/llm/gemma3-1b-it-int4.litertlm'
[IO.File]::WriteAllText($packagedGemma, 'bad')
& "$repo/scripts/prepare-android-models.ps1" -ManifestPath $fixture.Path -AssetRoot $fixture.Root -GemmaPath $localGemma | Out-Null
Verify $fixture | Out-Null
Assert ([IO.File]::ReadAllText($localGemma) -ceq '123456789') 'Source Gemma file changed.'
Assert (@(Get-ChildItem $fixture.Root -Recurse -Filter '*.partial' -Force).Count -eq 0) 'Temporary files remained.'
Pass 'verified local Gemma replaces corrupt target and preserves source'

[IO.File]::WriteAllText($localGemma, 'corrupt!!')
Expect-Failure { & "$repo/scripts/prepare-android-models.ps1" -ManifestPath $fixture.Path -AssetRoot $fixture.Root -GemmaPath $localGemma } 'integrity failed'
Verify $fixture | Out-Null
Pass 'corrupt input Gemma cannot replace valid packaged file'

$missingRoot = Join-Path $scratch 'not-created'
Expect-Failure { & "$repo/scripts/prepare-android-models.ps1" -ManifestPath $fixture.Path -AssetRoot $missingRoot -VerifyOnly } 'Missing model asset'
Assert (-not (Test-Path $missingRoot)) 'VerifyOnly created directories.'
Pass 'offline VerifyOnly performs no directory creation'
Write-Output "$passes checks passed."
