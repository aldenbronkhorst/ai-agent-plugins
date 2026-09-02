[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Account,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Tenant,

    [string]$ExchangeResource = "https://outlook.office365.com",
    [string]$ExchangeEnvironmentName = "O365Default"
)

$ErrorActionPreference = "Stop"
$accountName = $Account.Trim()
$tenantName = $Tenant.Trim()
$accessToken = $null
$originalAzureConfig = $env:AZURE_CONFIG_DIR

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Azure CLI is required. Install the current official Azure CLI and retry."
}

$exchangeModule = Get-Module ExchangeOnlineManagement -ListAvailable |
    Sort-Object Version -Descending |
    Select-Object -First 1
if (-not $exchangeModule) {
    throw "ExchangeOnlineManagement is required. Install the current official module for this user and retry."
}
Import-Module $exchangeModule.Path -Force

function Get-AzureContext {
    $json = & az account show --only-show-errors --output json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $json) {
        return $null
    }
    return $json | ConvertFrom-Json
}

function Test-AzureContext($Context) {
    if (-not $Context -or -not $Context.user) {
        return $false
    }
    if (-not [string]::Equals($Context.user.name, $accountName, [StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }
    if ($tenantName -match '^[0-9a-fA-F-]{36}$') {
        return [string]::Equals($Context.tenantId, $tenantName, [StringComparison]::OrdinalIgnoreCase)
    }
    if ($Context.tenantDefaultDomain) {
        return [string]::Equals($Context.tenantDefaultDomain, $tenantName, [StringComparison]::OrdinalIgnoreCase)
    }
    return $false
}

function Invoke-AzureDeviceLogin {
    & az login `
        --use-device-code `
        --tenant $tenantName `
        --scope "$ExchangeResource/.default" `
        --skip-subscription-discovery `
        --only-show-errors `
        --output none
    if ($LASTEXITCODE -ne 0) {
        throw "Microsoft device-code sign-in did not complete."
    }
}

function Get-ExchangeAccessToken([string]$TenantId) {
    $token = & az account get-access-token `
        --tenant $TenantId `
        --resource $ExchangeResource `
        --query accessToken `
        --output tsv `
        --only-show-errors 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $token) {
        return $null
    }
    return $token
}

function Get-IsolatedProfileDirectory {
    $localData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if (-not $localData) {
        throw "The current user has no local application-data directory."
    }
    $keyText = "$($accountName.ToLowerInvariant())`n$($tenantName.ToLowerInvariant())`n$($ExchangeResource.ToLowerInvariant())"
    $keyBytes = [Text.Encoding]::UTF8.GetBytes($keyText)
    try {
        $key = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($keyBytes)).ToLowerInvariant()
    }
    finally {
        [Array]::Clear($keyBytes, 0, $keyBytes.Length)
    }
    return Join-Path $localData "AI Agent Plugins/Microsoft Auth/Azure CLI/$key"
}

try {
    $context = Get-AzureContext
    if (-not (Test-AzureContext $context)) {
        $env:AZURE_CONFIG_DIR = Get-IsolatedProfileDirectory
        $null = New-Item -ItemType Directory -Path $env:AZURE_CONFIG_DIR -Force
        if (-not $IsWindows) {
            & chmod 700 $env:AZURE_CONFIG_DIR 2>$null
        }
        $context = Get-AzureContext
    }

    if (-not (Test-AzureContext $context)) {
        if ($context) {
            & az account clear --only-show-errors
        }
        Invoke-AzureDeviceLogin
        $context = Get-AzureContext
    }

    if (-not (Test-AzureContext $context)) {
        throw "Microsoft authenticated a different account. Retry and choose '$accountName' on the device-login page."
    }

    $resolvedTenant = $context.tenantId
    $accessToken = Get-ExchangeAccessToken $resolvedTenant
    if (-not $accessToken) {
        Invoke-AzureDeviceLogin
        $context = Get-AzureContext
        if (-not (Test-AzureContext $context)) {
            throw "Microsoft authenticated a different account. Retry and choose '$accountName' on the device-login page."
        }
        $resolvedTenant = $context.tenantId
        $accessToken = Get-ExchangeAccessToken $resolvedTenant
        if (-not $accessToken) {
            throw "Azure CLI could not obtain an Exchange access token after reauthentication."
        }
    }

    $existing = Get-ConnectionInformation -ErrorAction SilentlyContinue |
        Where-Object {
            $_.State -eq "Connected" -and
            [string]::Equals($_.UserPrincipalName, $accountName, [StringComparison]::OrdinalIgnoreCase) -and
            [string]::Equals($_.TenantID, $resolvedTenant, [StringComparison]::OrdinalIgnoreCase)
        } |
        Select-Object -First 1

    if (-not $existing) {
        $connectParameters = @{
            AccessToken = $accessToken
            UserPrincipalName = $accountName
            ShowBanner = $false
        }
        if ($ExchangeEnvironmentName -ne "O365Default") {
            $connectParameters.ExchangeEnvironmentName = $ExchangeEnvironmentName
        }
        Connect-ExchangeOnline @connectParameters | Out-Null
    }

    $connection = Get-ConnectionInformation |
        Where-Object {
            $_.State -eq "Connected" -and
            [string]::Equals($_.UserPrincipalName, $accountName, [StringComparison]::OrdinalIgnoreCase) -and
            [string]::Equals($_.TenantID, $resolvedTenant, [StringComparison]::OrdinalIgnoreCase)
        } |
        Select-Object -First 1
    if (-not $connection) {
        throw "Exchange Online connected with an unexpected account or tenant."
    }

    [pscustomobject]@{
        Account = $connection.UserPrincipalName
        TenantId = $connection.TenantID
        State = $connection.State
    }
}
finally {
    $accessToken = $null
    $env:AZURE_CONFIG_DIR = $originalAzureConfig
}
