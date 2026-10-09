[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Write-Host ''
Write-Host 'ReVise: guided Gemma download' -ForegroundColor Cyan
Write-Host ''
Write-Host '1. Sign in to Hugging Face and open:'
Write-Host '   https://huggingface.co/litert-community/Gemma3-1B-IT'
Write-Host '   Accept this repository''s access/license conditions if requested.'
Write-Host '   Access to Google''s original model alone is not sufficient.'
Write-Host ''
Write-Host '2. In the SAME account, open:'
Write-Host '   https://huggingface.co/settings/tokens'
Write-Host '   Create a Read token and copy it. Never send the token in chat.'
Write-Host '   For a fine-grained token, enable read access to public gated repos'
Write-Host '   you can access, and ensure repository restrictions allow this model.'
Write-Host ''
Write-Host '3. At the hidden prompt, paste the hf_ token and press Enter.'
Write-Host '   Nothing will appear while you paste. This is normal.'
Write-Host '   The token is used in memory only, not saved or logged.'
Write-Host ''
$confirmation = Read-Host 'After completing steps 1 and 2, type READY (do NOT paste the token here)'
if ($confirmation.Trim() -ine 'READY') {
    Write-Host 'Download not started. No token was requested.'
    return
}

try {
    & (Join-Path $PSScriptRoot 'prepare-android-models-python.ps1') -DownloadGemma -AcceptGemmaTerms -PromptToken
    Write-Host ''
    Write-Host 'Models downloaded and verified. Close this window to notify the assistant.' -ForegroundColor Green
} catch {
    Write-Host ''
    Write-Host 'Download did not complete. Read the error above.' -ForegroundColor Yellow
    Write-Host 'If HTTP 401/403 is from huggingface.co: check model access and token permissions.'
    Write-Host 'If HTTP 403 is from a CDN: share only the error line with the assistant.'
    Write-Host 'Do not share your token. Close this window after noting the error.'
}
