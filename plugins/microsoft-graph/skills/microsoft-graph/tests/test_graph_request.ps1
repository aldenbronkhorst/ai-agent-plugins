$ErrorActionPreference = "Stop"
$scriptPath = Join-Path $PSScriptRoot "../scripts/graph_request.ps1"
$global:requestedAccount = $null
$global:requestedScopes = $null
$global:requestMethod = $null
$global:requestUri = $null

function Connect-MgGraph {
    [CmdletBinding()]
    param(
        [string[]]$Scopes,
        [string]$LoginHint,
        [string]$ContextScope,
        [switch]$NoWelcome,
        [string]$TenantId,
        [string]$Environment
    )
    $global:requestedAccount = $LoginHint
    $global:requestedScopes = $Scopes
}

function Get-MgContext {
    [pscustomobject]@{
        Account = "first@example.com"
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

$json = & $scriptPath `
    -Account "first@example.com" `
    -Method GET `
    -Uri "/v1.0/me" `
    -Scopes @("User.Read") `
    -TenantId "tenant-one"

$result = $json | ConvertFrom-Json
if ($global:requestedAccount -ne "first@example.com") {
    throw "The helper did not select the requested account."
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

function Get-MgContext {
    [pscustomobject]@{
        Account = "second@example.com"
        TenantId = "tenant-one"
    }
}

$mismatchRejected = $false
try {
    & $scriptPath -Account "first@example.com" -Method GET -Uri "/v1.0/me" | Out-Null
}
catch {
    $mismatchRejected = $_.Exception.Message -like "*instead of the requested account*"
}
if (-not $mismatchRejected) {
    throw "The helper did not reject an unexpected authenticated account."
}

Write-Output "graph_request.ps1 tests passed"
