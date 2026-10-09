#requires -Version 7.0
<#
.SYNOPSIS
Prepares pinned Android assets on a developer machine, or verifies them offline.
.DESCRIPTION
Downloads only public Moonshine assets. Gemma must be supplied as a local file
obtained by an authorized developer. This script is never invoked by the app.
#>
[CmdletBinding()]
param(
    [string]$ManifestPath = "$PSScriptRoot/../android/app/src/main/assets/revise/model-manifest.json",
    [string]$AssetRoot = "$PSScriptRoot/../android/app/src/main/assets/revise",
    [string]$GemmaPath,
    [switch]$SpeechOnly,
    [switch]$VerifyOnly
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot/ModelIntegrity.psm1"

function Assert-AssetIntegrity([string]$Path, $Entry) {
    if (-not [IO.File]::Exists($Path)) { throw "Missing model asset: $($Entry.path)" }
    $actual = Get-ModelIntegrity -LiteralPath $Path
    if ($actual.SizeBytes -ne $Entry.sizeBytes -or $actual.Sha256 -cne $Entry.sha256 -or
        ($null -ne $Entry.crc32c -and $actual.Crc32c -cne $Entry.crc32c)) {
        throw "Model integrity failed: $($Entry.path). Replace the missing/corrupt file with the pinned asset."
    }
}

function Assert-NoLinkedDirectory([string]$Directory) {
    # Do not write through symlinks/junctions hidden in an otherwise safe path.
    $current = $Directory
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Model destination contains a linked directory: $current"
            }
        }
        $current = [IO.Path]::GetDirectoryName($current)
    }
}

if ($GemmaPath -and ($VerifyOnly -or $SpeechOnly)) { throw 'GemmaPath cannot be combined with VerifyOnly or SpeechOnly.' }
$root = [IO.Path]::GetFullPath($AssetRoot)
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or $manifest.files.Count -ne 11) { throw 'Expected model manifest schema 1 with 11 assets.' }
$seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($entry in $manifest.files) {
    if ($entry.group -notin @('stt','diarization','llm') -or
        $entry.path -cnotmatch '^models/(stt|diarization|llm)/[a-zA-Z0-9_.-]+$' -or
        $entry.path -cnotlike "models/$($entry.group)/*" -or
        $entry.path.Split('/')[-1] -in @('.','..') -or
        -not $seen.Add($entry.path) -or $entry.sizeBytes -le 0 -or
        $entry.sha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'Invalid model manifest entry or duplicate asset path.' }
    if ($null -ne $entry.crc32c -and $entry.crc32c -cnotmatch '^[A-Za-z0-9+/]{6}==$') { throw 'Invalid CRC32C encoding.' }
    if ($entry.group -eq 'llm') {
        if ($entry.path -cne 'models/llm/gemma3-1b-it-int4.litertlm' -or $null -ne $entry.sourceUrl) {
            throw 'Gemma requires the pinned local file; automatic Gemma download is forbidden.'
        }
    } else {
        $url = [Uri]$entry.sourceUrl
        if ($url.Scheme -cne 'https' -or $url.Host -cne 'download.moonshine.ai' -or
            $url.UserInfo -or $url.Query -or $url.Fragment -or -not $url.IsDefaultPort -or
            $url.AbsolutePath -cnotmatch '^/model/(tiny-streaming-en/quantized_26_08_21|diarization-community1)/[a-zA-Z0-9_.-]+$' -or
            $url.Segments[-1] -cne $entry.path.Split('/')[-1]) { throw 'Unexpected Moonshine source URL.' }
    }
}
if (@($manifest.files | Where-Object group -eq 'stt').Count -ne 8 -or
    @($manifest.files | Where-Object group -eq 'diarization').Count -ne 2 -or
    @($manifest.files | Where-Object group -eq 'llm').Count -ne 1) { throw 'Required model groups are incomplete.' }
if ($GemmaPath) {
    $gemmaEntry = $manifest.files | Where-Object group -eq 'llm'
    Assert-AssetIntegrity ([IO.Path]::GetFullPath($GemmaPath)) $gemmaEntry
}

$selected = @($manifest.files | Where-Object { -not $SpeechOnly -or $_.group -ne 'llm' })
foreach ($entry in $selected) {
    $destination = [IO.Path]::GetFullPath((Join-Path $root $entry.path))
    $relative = [IO.Path]::GetRelativePath($root, $destination)
    if ($relative.StartsWith('..') -or [IO.Path]::IsPathRooted($relative)) { throw 'Asset path escapes destination.' }
    $directory = [IO.Path]::GetDirectoryName($destination)
    Assert-NoLinkedDirectory $directory
    if ((Test-Path -LiteralPath $destination) -and
        ((Get-Item -LiteralPath $destination -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Model destination is a linked file.'
    }
    if ($VerifyOnly) {
        Assert-AssetIntegrity $destination $entry
    } else {
        $valid = $false
        if ([IO.File]::Exists($destination)) {
            try { Assert-AssetIntegrity $destination $entry; $valid = $true } catch { $valid = $false }
        }
        if (-not $valid) {
            if ($entry.group -eq 'llm' -and -not $GemmaPath) {
                throw 'Gemma is missing/corrupt. Supply -GemmaPath with the authorized pinned file, or prepare speech assets with -SpeechOnly.'
            }
            [IO.Directory]::CreateDirectory($directory) | Out-Null
            $temporary = Join-Path $directory ('.' + [IO.Path]::GetFileName($destination) + '.' + [Guid]::NewGuid().ToString('N') + '.partial')
            try {
                if ($entry.group -eq 'llm') {
                    [IO.File]::Copy([IO.Path]::GetFullPath($GemmaPath), $temporary)
                } else {
                    Invoke-WebRequest -Uri $entry.sourceUrl -OutFile $temporary -TimeoutSec 300
                }
                Assert-AssetIntegrity $temporary $entry
                [IO.File]::Move($temporary, $destination, $true)
            } finally {
                # This is only the unique temporary file created by this call.
                if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
            }
        }
    }
    Write-Output "Verified $($entry.path)"
}
Write-Output "Verified $($selected.Count) assets."
