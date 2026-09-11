# Offline tests: both HTTP commands are mocked before loading helper definitions.
Import-Module Microsoft.PowerShell.Utility
Import-Module Microsoft.PowerShell.Management
$PSModuleAutoLoadingPreference = 'None'
$ErrorActionPreference = 'Stop'
$script:failure = $null
$script:httpCall = $null
$script:content = '{"access_token":"dummy-opaque-token","scope":"User.Read"}'

function Invoke-WebRequest {
    param($Method, $Uri, $ContentType, $Body, [switch]$SkipHttpErrorCheck, $MaximumRedirection, $TimeoutSec)
    $script:httpCall = $PSBoundParameters
    if ($script:failure) { throw $script:failure }
    return [pscustomobject]@{ StatusCode = 200; Content = $script:content }
}
function Invoke-RestMethod {
    param($Method, $Uri, $Headers, $MaximumRedirection, $TimeoutSec)
    $script:httpCall = $PSBoundParameters
    if ($script:failure) { throw $script:failure }
    return [pscustomobject]@{ id = 'dummy-user'; mail = 'test@example.invalid' }
}

. (Join-Path $PSScriptRoot '../scripts/graph_auth.ps1')

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Assert-SanitizedFailure([scriptblock]$Action) {
    $caught = $null
    try { & $Action | Out-Null }
    catch { $caught = $_.Exception.Message }
    Assert-True ([bool]$caught) 'Expected a transport failure'
    Assert-True ($caught -notmatch 'dummy-secret') 'Transport exception must not expose request secrets'
}

$response = Invoke-GraphOAuthPost 'https://login.example.invalid/token' @{ refresh_token = 'dummy-secret' }
Assert-True ($response.Content.access_token -eq 'dummy-opaque-token') 'Opaque tokens must remain opaque'
Assert-True ($script:httpCall.Method -eq 'Post') 'OAuth token request must remain POST'
Assert-True ($script:httpCall.MaximumRedirection -eq 0) 'OAuth secrets must not follow redirects'
Assert-True ($script:httpCall.TimeoutSec -gt 0) 'HTTP requests must be bounded'
Write-Host 'PASS OAuth transport preserves responses and refuses redirects'

$response = Invoke-GraphTokenIdentity 'https://graph.example.invalid/' 'dummy-opaque-token'
Assert-True ($response.id -eq 'dummy-user') 'Identity response must remain available'
Assert-True ($script:httpCall.Headers.Authorization -eq 'Bearer dummy-opaque-token') 'Identity call must use the supplied token in a header'
Assert-True ($script:httpCall.MaximumRedirection -eq 0) 'Identity credentials must not follow redirects'
Write-Host 'PASS identity transport preserves the result and refuses redirects'

$script:failure = 'Transport error containing dummy-secret'
Assert-SanitizedFailure { Invoke-GraphOAuthPost 'https://login.example.invalid/token' @{ refresh_token = 'dummy-secret' } }
Assert-SanitizedFailure { Invoke-GraphTokenIdentity 'https://graph.example.invalid' 'dummy-secret' }
Write-Host 'PASS both transport errors are sanitized'

$script:failure = $null
$script:content = 'invalid JSON containing dummy-secret'
Assert-SanitizedFailure { Invoke-GraphOAuthPost 'https://login.example.invalid/token' @{ refresh_token = 'dummy-secret' } }
Write-Host 'PASS malformed token responses do not echo secrets'
Write-Host '4 offline Graph transport regression tests passed.'
