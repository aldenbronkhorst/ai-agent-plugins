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
    [string]$Environment,
    [string]$BodyJson,
    [string]$HeadersJson,
    [string]$OutputFilePath
)

$ErrorActionPreference = "Stop"
$accountHint = $Account.Trim()
if (-not $accountHint) {
    throw "Account must contain the intended Microsoft sign-in identity."
}

$connectCommand = Get-Command Connect-MgGraph -ErrorAction SilentlyContinue
if (-not $connectCommand) {
    $module = Get-Module Microsoft.Graph.Authentication -ListAvailable |
        Sort-Object Version -Descending |
        Select-Object -First 1
    if (-not $module) {
        throw "Microsoft.Graph.Authentication 2.39.0 or later is required. Install it for the current user and retry."
    }
    Import-Module Microsoft.Graph.Authentication -MinimumVersion 2.39.0
    $connectCommand = Get-Command Connect-MgGraph -ErrorAction Stop
}

if (-not $connectCommand.Parameters.ContainsKey("LoginHint")) {
    throw "The installed Microsoft.Graph.Authentication module does not support per-account LoginHint records. Update it to 2.39.0 or later."
}

$connectParameters = @{
    Scopes       = $Scopes
    LoginHint    = $accountHint
    ContextScope = "CurrentUser"
    NoWelcome    = $true
    ErrorAction  = "Stop"
}
if ($TenantId) {
    $connectParameters.TenantId = $TenantId
}
if ($Environment) {
    $connectParameters.Environment = $Environment
}

Connect-MgGraph @connectParameters | Out-Null
$context = Get-MgContext
if (-not $context -or -not $context.Account) {
    throw "Microsoft Graph did not return an authenticated account context."
}
if (-not [string]::Equals([string]$context.Account, $accountHint, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Microsoft Graph authenticated '$($context.Account)' instead of the requested account '$accountHint'."
}

$genericTenantValues = @("common", "organizations", "consumers")
if (
    $TenantId -and
    $genericTenantValues -notcontains $TenantId.ToLowerInvariant() -and
    $context.TenantId -and
    -not [string]::Equals([string]$context.TenantId, $TenantId, [System.StringComparison]::OrdinalIgnoreCase)
) {
    throw "Microsoft Graph authenticated tenant '$($context.TenantId)' instead of '$TenantId'."
}

$requestParameters = @{
    Method      = $Method
    Uri         = $Uri
    ErrorAction = "Stop"
}
if ($BodyJson) {
    $null = $BodyJson | ConvertFrom-Json -ErrorAction Stop
    $requestParameters.Body = $BodyJson
    $requestParameters.ContentType = "application/json"
}
if ($HeadersJson) {
    $headers = $HeadersJson | ConvertFrom-Json -AsHashtable -ErrorAction Stop
    if ($headers -isnot [hashtable]) {
        throw "HeadersJson must be a JSON object."
    }
    $requestParameters.Headers = $headers
}
if ($OutputFilePath) {
    $requestParameters.OutputFilePath = $OutputFilePath
}

$response = Invoke-MgGraphRequest @requestParameters
if (-not $OutputFilePath -and $null -ne $response) {
    $response | ConvertTo-Json -Depth 100
}
