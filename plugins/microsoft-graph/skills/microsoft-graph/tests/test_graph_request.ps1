$ErrorActionPreference = "Stop"
$scriptPath = Join-Path $PSScriptRoot "../scripts/graph_request.ps1"
$testRoot = Join-Path ([IO.Path]::GetTempPath()) "graph-request-$([Guid]::NewGuid().ToString('N'))"
$stateRoot = Join-Path $testRoot "state"
$authRecordPath = Join-Path $testRoot ".mg/mg.authrecord.json"
$null = New-Item -ItemType Directory -Path (Split-Path -Parent $authRecordPath) -Force
$env:MICROSOFT_GRAPH_PLUGIN_STATE_DIR = $stateRoot
$env:MICROSOFT_GRAPH_PLUGIN_AUTH_RECORD_PATH = $authRecordPath

$global:requestedAccount = $null
$global:requestedScopes = $null
$global:requestedDeviceAuthentication = $false
$global:requestMethod = $null
$global:requestUri = $null
$global:authenticatedAccount = "first@example.com"
$global:recordSeenByConnect = $null

function Connect-MgGraph {
    [CmdletBinding()]
    param(
        [string[]]$Scopes,
        [switch]$UseDeviceAuthentication,
        [string]$ContextScope,
        [switch]$NoWelcome,
        [string]$TenantId,
        [string]$Environment
    )
    $global:requestedScopes = $Scopes
    $global:requestedDeviceAuthentication = [bool]$UseDeviceAuthentication
    $global:recordSeenByConnect = if (Test-Path -LiteralPath $env:MICROSOFT_GRAPH_PLUGIN_AUTH_RECORD_PATH) {
        Get-Content -LiteralPath $env:MICROSOFT_GRAPH_PLUGIN_AUTH_RECORD_PATH -Raw
    }
    else {
        $null
    }
    $record = @{ username = $global:authenticatedAccount; tenant = $TenantId } | ConvertTo-Json -Compress
    Set-Content -LiteralPath $env:MICROSOFT_GRAPH_PLUGIN_AUTH_RECORD_PATH -Value $record -NoNewline
}

function Get-MgContext {
    [pscustomobject]@{
        Account = $global:authenticatedAccount
        TenantId = "tenant-one"
    }
}

function Invoke-MgGraphRequest {
    [CmdletBinding()]
    param(
        [string]$Method,
        [string]$Uri,
        [string]$Body,
        [string]$ContentType,
        [hashtable]$Headers,
        [string]$OutputFilePath
    )
    $global:requestMethod = $Method
    $global:requestUri = $Uri
    [pscustomobject]@{ id = "user-one"; displayName = "First User" }
}

try {
    Set-Content -LiteralPath $authRecordPath -Value '{"original":true}' -NoNewline

    $json = & $scriptPath `
        -Account "first@example.com" `
        -Method GET `
        -Uri "/v1.0/me" `
        -Scopes @("User.Read") `
        -TenantId "tenant-one"

    $result = $json | ConvertFrom-Json
    if (-not $global:requestedDeviceAuthentication) {
        throw "The helper did not use device authentication."
    }
    if ($global:requestedScopes -notcontains "User.Read") {
        throw "The helper did not pass the requested scopes."
    }
    if ($global:requestMethod -ne "GET" -or $global:requestUri -ne "/v1.0/me") {
        throw "The helper changed the Graph request."
    }
    if ($result.id -ne "user-one") {
        throw "The helper did not return the Graph response."
    }
    if ((Get-Content -LiteralPath $authRecordPath -Raw) -ne '{"original":true}') {
        throw "The helper did not restore the caller's Graph authentication record."
    }

    $savedRecords = @(Get-ChildItem -LiteralPath $stateRoot -Filter "account-*.authrecord.json")
    if ($savedRecords.Count -ne 1) {
        throw "The helper did not save exactly one account-specific authentication record."
    }

    $global:recordSeenByConnect = $null
    $null = & $scriptPath `
        -Account "first@example.com" `
        -Method GET `
        -Uri "/v1.0/me" `
        -Scopes @("User.Read") `
        -TenantId "tenant-one"
    if ($global:recordSeenByConnect -notlike '*first@example.com*') {
        throw "The helper did not restore the requested account's saved authentication record."
    }

    $global:authenticatedAccount = "second@example.com"
    $mismatchRejected = $false
    try {
        & $scriptPath `
            -Account "first@example.com" `
            -Method GET `
            -Uri "/v1.0/me" `
            -TenantId "tenant-one" | Out-Null
    }
    catch {
        $mismatchRejected = $_.Exception.Message -like "*instead of the requested account*"
    }
    if (-not $mismatchRejected) {
        throw "The helper did not reject an unexpected authenticated account."
    }

    Write-Output "graph_request.ps1 tests passed"
}
finally {
    Remove-Item Env:MICROSOFT_GRAPH_PLUGIN_STATE_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:MICROSOFT_GRAPH_PLUGIN_AUTH_RECORD_PATH -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
