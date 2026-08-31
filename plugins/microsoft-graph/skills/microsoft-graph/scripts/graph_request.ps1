[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Account,

    [Parameter(Mandatory = $true)]
    [ValidateSet("GET", "POST", "PUT", "PATCH", "DELETE")]
    [string]$Method,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Uri,

    [string[]]$Scopes = @("User.Read"),
    [string]$TenantId,
    [string]$Environment = "Global",
    [string]$BodyJson,
    [string]$HeadersJson,
    [string]$OutputFilePath,
    [switch]$ForceSignIn
)

$ErrorActionPreference = "Stop"
& (Join-Path $PSScriptRoot "msal_request.ps1") @PSBoundParameters
if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
