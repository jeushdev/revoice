[CmdletBinding()]
param(
    [string]$GemmaFile,
    [switch]$DownloadGemma,
    [switch]$PromptToken,
    [switch]$MoonshineOnly,
    [switch]$VerifyOnly,
    [switch]$AcceptGemmaTerms
)

$ErrorActionPreference = 'Stop'
$pythonArgs = @((Join-Path $PSScriptRoot 'prepare_android_models.py'))
if ($GemmaFile) { $pythonArgs += @('--gemma-file', $GemmaFile) }
if ($DownloadGemma) { $pythonArgs += '--download-gemma' }
if ($PromptToken) { $pythonArgs += '--prompt-token' }
if ($MoonshineOnly) { $pythonArgs += '--moonshine-only' }
if ($VerifyOnly) { $pythonArgs += '--verify-only' }
if ($AcceptGemmaTerms) { $pythonArgs += '--accept-gemma-terms' }
& python @pythonArgs
if ($LASTEXITCODE -ne 0) { throw "Model preparation failed (exit $LASTEXITCODE)." }
