[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Account,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Tenant,

    [string]$ExchangeResource,
    [ValidateSet("O365Default", "O365China", "O365GermanyCloud", "O365USGovGCCHigh", "O365USGovDoD")]
    [string]$ExchangeEnvironmentName = "O365Default"
)

$ErrorActionPreference = "Stop"
$accountName = $Account.Trim()
$tenantName = $Tenant.Trim()
$accessToken = $null
$script:deviceLoginAttempted = $false
$originalAzureConfig = $env:AZURE_CONFIG_DIR

# Connection endpoints: https://learn.microsoft.com/powershell/module/exchangepowershell/connect-exchangeonline
# REST endpoint aliases: https://learn.microsoft.com/exchange/reference/admin-api-get-started
$environments = @{
    O365Default = @("AzureCloud", "https://login.microsoftonline.com", "https://outlook.office365.com")
    O365China = @("AzureChinaCloud", "https://login.partner.microsoftonline.cn", "https://partner.outlook.cn")
    O365GermanyCloud = @("AzureGermanCloud", "https://login.microsoftonline.de", "https://outlook.office.de")
    O365USGovGCCHigh = @("AzureUSGovernment", "https://login.microsoftonline.us", "https://outlook.office365.us")
    O365USGovDoD = @("AzureUSGovernment", "https://login.microsoftonline.us", "https://webmail.apps.mil")
}
$azureCloud, $authority, $connectionResource = $environments[$ExchangeEnvironmentName]
$connectionHosts = @(([uri]$connectionResource).Host)
if ($ExchangeEnvironmentName -eq 'O365China') { $connectionHosts += 'outlook.office365.cn' }
if ($ExchangeEnvironmentName -eq 'O365USGovDoD') { $connectionHosts += 'outlook-dod.office365.us' }
if (-not $ExchangeResource) { $ExchangeResource = $connectionResource }
$ExchangeResource = $ExchangeResource.TrimEnd('/')

if (-not (Get-Module ExchangeOnlineManagement)) {
    $exchangeModule = Get-Module ExchangeOnlineManagement -ListAvailable |
        Sort-Object Version -Descending |
        Select-Object -First 1
    if (-not $exchangeModule) {
        throw "ExchangeOnlineManagement is required. Install the current official module for this user and retry."
    }
    Import-Module $exchangeModule.Path
}

function Resolve-TenantId {
    $tenantId = [guid]::Empty
    if ([guid]::TryParse($tenantName, [ref]$tenantId)) { return $tenantId.ToString() }
    if ([Uri]::CheckHostName($tenantName) -ne [UriHostNameType]::Dns -or $tenantName -notmatch '\.') {
        throw "Tenant must be a tenant GUID or verified domain name."
    }
    # Public discovery resolves domain aliases without requiring an account or token.
    $metadata = Invoke-RestMethod -Uri "$authority/$tenantName/v2.0/.well-known/openid-configuration" -TimeoutSec 30
    $issuer = [uri]$metadata.issuer
    $issuerTenant = $issuer.AbsolutePath.Trim('/').Split('/')[0]
    if ($issuer.Scheme -ne 'https' -or $issuer.Host -ne ([uri]$authority).Host -or
        -not [guid]::TryParse($issuerTenant, [ref]$tenantId)) {
        throw "Microsoft tenant discovery did not return a verified tenant GUID."
    }
    return $tenantId.ToString()
}

function Test-ExchangeConnection($Connection) {
    if (-not $Connection -or $Connection.State -ne 'Connected' -or
        $Connection.IsEopSession -eq $true -or $Connection.Name -like 'ExchangeOnlineProtection*' -or
        $Connection.UserPrincipalName -ne $accountName -or $Connection.TenantID -ne $resolvedTenant) {
        return $false
    }
    $uri = $null
    if (-not [uri]::TryCreate([string]$Connection.ConnectionUri, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -ne 'https' -or $uri.Host -notin $connectionHosts) {
        return $false
    }
    if ($Connection.TokenStatus -and $Connection.TokenStatus -ne 'Active') { return $false }
    if ($Connection.TokenExpiryTimeUTC) {
        try { return [DateTimeOffset]$Connection.TokenExpiryTimeUTC -gt [DateTimeOffset]::UtcNow.AddMinutes(1) }
        catch { return $false }
    }
    return $Connection.TokenStatus -eq 'Active'
}

function Test-InteractionRequired([string]$Message) {
    return $Message -match '(?i)\b(interaction_required|login_required)\b|AADSTS(50058|50076|50079|50173|65001|700082|70043)\b|(?:please run|run) ["'']?az login|does not exist in MSAL token cache'
}

function Get-AzureContext {
    $output = & az account show --only-show-errors --output json 2>&1
    $json = ($output | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        if (Test-InteractionRequired $json) { return $null }
        throw "Azure CLI could not read its account context (exit $LASTEXITCODE). Resolve the CLI error before signing in again."
    }
    if (-not $json) { return $null }
    return $json | ConvertFrom-Json
}

function Test-AzureContext($Context) {
    if (-not $Context -or -not $Context.user) {
        return $false
    }
    if (-not [string]::Equals($Context.user.name, $accountName, [StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }
    return $Context.tenantId -eq $resolvedTenant -and $Context.environmentName -eq $azureCloud
}

function Invoke-AzureDeviceLogin {
    if ($script:deviceLoginAttempted) {
        throw "Exchange token acquisition still requires interaction after sign-in. Check consent and tenant policy; no second device login was started."
    }
    $helpText = (& az login --help 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0 -or $helpText -notmatch '--scope' -or $helpText -notmatch '--use-device-code') {
        throw "Azure CLI lacks the required login options. Update the official CLI and retry."
    }
    $loginArguments = @('login', '--use-device-code', '--tenant', $resolvedTenant,
        '--scope', "$ExchangeResource/.default", '--only-show-errors', '--output', 'none')
    if ($helpText -match '--skip-subscription-discovery') { $loginArguments += '--skip-subscription-discovery' }
    elseif ($helpText -match '--allow-no-subscriptions') { $loginArguments += '--allow-no-subscriptions' }
    else { throw "Azure CLI cannot sign in without a subscription. Update the official CLI and retry." }
    $script:deviceLoginAttempted = $true
    & az @loginArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Microsoft device-code sign-in did not complete."
    }
}

function Get-ExchangeAccessToken([string]$TenantId) {
    $output = & az account get-access-token `
        --tenant $TenantId `
        --resource $ExchangeResource `
        --query accessToken `
        --output tsv `
        --only-show-errors 2>&1
    $token = ($output | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        if (Test-InteractionRequired $token) { return $null }
        $errorCode = [regex]::Match($token, 'AADSTS\d+').Value
        throw "Azure CLI token acquisition failed (exit $LASTEXITCODE $errorCode). Check connectivity, service availability, and policy; no new sign-in was started."
    }
    if (-not $token) { throw "Azure CLI returned no Exchange access token." }
    return $token
}

function Get-IsolatedProfileDirectory {
    $localData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if (-not $localData) {
        throw "The current user has no local application-data directory."
    }
    $keyText = "$($accountName.ToLowerInvariant())`n$($tenantName.ToLowerInvariant())`n$($ExchangeResource.ToLowerInvariant())"
    # Preserve existing public-cloud profile paths while separating other environments.
    if ($ExchangeEnvironmentName -ne 'O365Default') { $keyText += "`n$ExchangeEnvironmentName" }
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
    $resolvedTenant = Resolve-TenantId
    $connection = Get-ConnectionInformation | Where-Object { Test-ExchangeConnection $_ } | Select-Object -Last 1
    if ($connection) {
        return [pscustomobject]@{
            Account = $connection.UserPrincipalName
            TenantId = $connection.TenantID
            State = $connection.State
            ConnectionId = $connection.ConnectionId
        }
    }
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        throw "Azure CLI is required. Install the current official Azure CLI and retry."
    }
    if (-not (Get-Command Connect-ExchangeOnline).Parameters.ContainsKey('AccessToken')) {
        throw "ExchangeOnlineManagement lacks AccessToken support. Update the official module and retry."
    }
    $context = Get-AzureContext
    if (-not (Test-AzureContext $context)) {
        $env:AZURE_CONFIG_DIR = Get-IsolatedProfileDirectory
        $null = New-Item -ItemType Directory -Path $env:AZURE_CONFIG_DIR -Force
        if (-not $IsWindows) {
            & chmod 700 $env:AZURE_CONFIG_DIR 2>$null
        }
        & az cloud set --name $azureCloud --only-show-errors
        if ($LASTEXITCODE -ne 0) { throw "Azure CLI could not select '$azureCloud' in the isolated profile." }
        $context = Get-AzureContext
    }

    if (-not (Test-AzureContext $context)) {
        Invoke-AzureDeviceLogin
        $context = Get-AzureContext
    }

    if (-not (Test-AzureContext $context)) {
        throw "Microsoft authenticated a different account, tenant, or cloud. Retry and choose '$accountName' in tenant '$resolvedTenant'."
    }

    $accessToken = Get-ExchangeAccessToken $resolvedTenant
    if (-not $accessToken) {
        Invoke-AzureDeviceLogin
        $context = Get-AzureContext
        if (-not (Test-AzureContext $context)) {
            throw "Microsoft authenticated a different account. Retry and choose '$accountName' on the device-login page."
        }
        $accessToken = Get-ExchangeAccessToken $resolvedTenant
        if (-not $accessToken) {
            throw "Azure CLI could not obtain an Exchange access token after reauthentication."
        }
    }

    # Supplied access tokens cannot refresh themselves: reconnect with the fresh token.
    # Do not disconnect other Exchange or compliance sessions in this process.
    $connectParameters = @{
        AccessToken = $accessToken
        UserPrincipalName = $accountName
        ShowBanner = $false
        ExchangeEnvironmentName = $ExchangeEnvironmentName
    }
    Connect-ExchangeOnline @connectParameters | Out-Null

    $connection = Get-ConnectionInformation |
        Where-Object { Test-ExchangeConnection $_ } |
        Select-Object -Last 1
    if (-not $connection) {
        throw "Exchange Online did not establish a healthy connection to the requested account, tenant, and environment."
    }

    [pscustomobject]@{
        Account = $connection.UserPrincipalName
        TenantId = $connection.TenantID
        State = $connection.State
        ConnectionId = $connection.ConnectionId
    }
}
finally {
    $accessToken = $null
    $env:AZURE_CONFIG_DIR = $originalAzureConfig
}
