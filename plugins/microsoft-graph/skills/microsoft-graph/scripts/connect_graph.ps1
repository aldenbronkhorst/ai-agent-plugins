[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Account,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string[]]$Scopes,

    [string]$TenantId = "common",
    [string]$Environment = "Global",
    [switch]$ForceDeviceCode
)

$ErrorActionPreference = "Stop"
$graphPowerShellClientId = "14d82eec-204b-4c2f-b7e8-296a70dab67e"
$minimumModuleVersion = [version]"2.37.0"
$accountHint = $Account.Trim()
$tenant = $TenantId.Trim()

if (-not $accountHint) {
    throw "Account must identify the intended Microsoft sign-in."
}
if (-not $tenant) {
    throw "TenantId cannot be empty. Use common, organizations, consumers, or a tenant ID."
}

$graphScopes = @("User.Read") + @($Scopes) |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ } |
    Select-Object -Unique

$module = Get-Module Microsoft.Graph.Authentication -ListAvailable |
    Where-Object Version -GE $minimumModuleVersion |
    Sort-Object Version -Descending |
    Select-Object -First 1

if (-not $module) {
    throw "Microsoft.Graph.Authentication $minimumModuleVersion or newer is required. Install the current module for this user and retry."
}

Import-Module $module.Path -Force
$graphEnvironment = Get-MgEnvironment -Name $Environment | Select-Object -First 1
if (-not $graphEnvironment) {
    throw "Microsoft Graph environment '$Environment' is not configured."
}

# The official SDK path is reliable on non-Windows systems and keeps its own
# secure cache. Windows uses the protocol path below to avoid WAM and the
# SDK's current normal-token/CAE double device-code acquisition.
if (-not $IsWindows) {
    Connect-MgGraph `
        -Scopes $graphScopes `
        -TenantId $tenant `
        -Environment $Environment `
        -UseDeviceCode `
        -ContextScope CurrentUser `
        -NoWelcome
    return
}

Add-Type -AssemblyName System.Security.Cryptography.ProtectedData

function Get-StateDirectory {
    $localData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if (-not $localData) {
        throw "The current Windows account has no local application-data directory."
    }
    return Join-Path $localData "AI Agent Plugins/Microsoft Graph"
}

function Get-AccountKey {
    $keyText = "$($accountHint.ToLowerInvariant())`n$($tenant.ToLowerInvariant())`n$($Environment.ToLowerInvariant())"
    $keyBytes = [Text.Encoding]::UTF8.GetBytes($keyText)
    try {
        return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($keyBytes)).ToLowerInvariant()
    }
    finally {
        [Array]::Clear($keyBytes, 0, $keyBytes.Length)
    }
}

$stateDirectory = Get-StateDirectory
$accountKey = Get-AccountKey
$refreshTokenPath = Join-Path $stateDirectory "$accountKey.refresh-token"
$entropy = [Text.Encoding]::UTF8.GetBytes("ai-agent-plugins.microsoft-graph:$accountKey")
$null = New-Item -ItemType Directory -Path $stateDirectory -Force

function Read-RefreshToken {
    if (-not (Test-Path -LiteralPath $refreshTokenPath)) {
        return $null
    }

    try {
        $protectedBytes = [IO.File]::ReadAllBytes($refreshTokenPath)
        $plainBytes = [Security.Cryptography.ProtectedData]::Unprotect(
            $protectedBytes,
            $entropy,
            [Security.Cryptography.DataProtectionScope]::CurrentUser
        )
        try {
            return [Text.Encoding]::UTF8.GetString($plainBytes)
        }
        finally {
            [Array]::Clear($plainBytes, 0, $plainBytes.Length)
            [Array]::Clear($protectedBytes, 0, $protectedBytes.Length)
        }
    }
    catch {
        Remove-Item -LiteralPath $refreshTokenPath -Force -ErrorAction SilentlyContinue
        return $null
    }
}

function Save-RefreshToken([string]$RefreshToken) {
    if (-not $RefreshToken) {
        throw "Microsoft did not return the refresh token required for persistent sign-in."
    }

    $plainBytes = [Text.Encoding]::UTF8.GetBytes($RefreshToken)
    $protectedBytes = [Security.Cryptography.ProtectedData]::Protect(
        $plainBytes,
        $entropy,
        [Security.Cryptography.DataProtectionScope]::CurrentUser
    )
    $temporaryPath = "$refreshTokenPath.$([Guid]::NewGuid().ToString('N')).tmp"

    try {
        [IO.File]::WriteAllBytes($temporaryPath, $protectedBytes)
        Move-Item -LiteralPath $temporaryPath -Destination $refreshTokenPath -Force
    }
    finally {
        [Array]::Clear($plainBytes, 0, $plainBytes.Length)
        [Array]::Clear($protectedBytes, 0, $protectedBytes.Length)
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Clear-RefreshToken {
    Remove-Item -LiteralPath $refreshTokenPath -Force -ErrorAction SilentlyContinue
}

function Invoke-OAuthPost([string]$Uri, [hashtable]$Body) {
    $response = Invoke-WebRequest `
        -Method Post `
        -Uri $Uri `
        -ContentType "application/x-www-form-urlencoded" `
        -Body $Body `
        -SkipHttpErrorCheck

    $content = $null
    if ($response.Content) {
        $content = $response.Content | ConvertFrom-Json
    }

    return [pscustomobject]@{
        StatusCode = [int]$response.StatusCode
        Content = $content
    }
}

$authority = $graphEnvironment.AzureADEndpoint.TrimEnd("/")
$deviceCodeEndpoint = "$authority/$tenant/oauth2/v2.0/devicecode"
$tokenEndpoint = "$authority/$tenant/oauth2/v2.0/token"
$oauthScopes = @("openid", "profile", "offline_access") + $graphScopes | Select-Object -Unique
$scopeText = $oauthScopes -join " "
$tokenResult = $null
$refreshTokenToSave = $null

if ($ForceDeviceCode) {
    Clear-RefreshToken
}

$refreshToken = Read-RefreshToken
if ($refreshToken) {
    $refreshResult = Invoke-OAuthPost -Uri $tokenEndpoint -Body @{
        client_id = $graphPowerShellClientId
        grant_type = "refresh_token"
        refresh_token = $refreshToken
        scope = $scopeText
    }

    if ($refreshResult.StatusCode -eq 200) {
        $tokenResult = $refreshResult.Content
        $refreshTokenToSave = if ($tokenResult.refresh_token) {
            $tokenResult.refresh_token
        }
        else {
            $refreshToken
        }
    }
    elseif ($refreshResult.Content.error -in @("invalid_grant", "interaction_required", "consent_required")) {
        Clear-RefreshToken
    }
    else {
        throw "Microsoft token refresh failed: $($refreshResult.Content.error)."
    }
}

if (-not $tokenResult) {
    $deviceResult = Invoke-OAuthPost -Uri $deviceCodeEndpoint -Body @{
        client_id = $graphPowerShellClientId
        scope = $scopeText
    }

    if ($deviceResult.StatusCode -ne 200) {
        throw "Microsoft device-code request failed: $($deviceResult.Content.error)."
    }

    [Console]::WriteLine($deviceResult.Content.message)
    $pollInterval = [Math]::Max([int]$deviceResult.Content.interval, 5)
    $expiresAt = [DateTimeOffset]::UtcNow.AddSeconds([int]$deviceResult.Content.expires_in)

    while ([DateTimeOffset]::UtcNow -lt $expiresAt) {
        Start-Sleep -Seconds $pollInterval
        $pollResult = Invoke-OAuthPost -Uri $tokenEndpoint -Body @{
            client_id = $graphPowerShellClientId
            grant_type = "urn:ietf:params:oauth:grant-type:device_code"
            device_code = $deviceResult.Content.device_code
        }

        if ($pollResult.StatusCode -eq 200) {
            $tokenResult = $pollResult.Content
            $refreshTokenToSave = $tokenResult.refresh_token
            break
        }

        switch ($pollResult.Content.error) {
            "authorization_pending" { continue }
            "slow_down" {
                $pollInterval += 5
                continue
            }
            "authorization_declined" { throw "Microsoft sign-in was declined." }
            "expired_token" { throw "The Microsoft device code expired before sign-in completed." }
            default { throw "Microsoft device-code sign-in failed: $($pollResult.Content.error)." }
        }
    }

    if (-not $tokenResult) {
        throw "The Microsoft device code expired before sign-in completed."
    }
}

$secureAccessToken = ConvertTo-SecureString $tokenResult.access_token -AsPlainText -Force
try {
    Connect-MgGraph -AccessToken $secureAccessToken -Environment $Environment -NoWelcome
}
finally {
    $secureAccessToken.Dispose()
}

$me = Invoke-MgGraphRequest -Method GET -Uri 'v1.0/me?$select=id,displayName,userPrincipalName,mail'
$authenticatedNames = @($me.userPrincipalName, $me.mail) |
    Where-Object { $_ } |
    ForEach-Object { $_.ToString().Trim() }

if (-not ($authenticatedNames | Where-Object {
    [string]::Equals($_, $accountHint, [StringComparison]::OrdinalIgnoreCase)
})) {
    Clear-RefreshToken
    Disconnect-MgGraph | Out-Null
    throw "Microsoft authenticated a different account. Retry and choose '$accountHint' on the device-login page."
}

Save-RefreshToken -RefreshToken $refreshTokenToSave
[Array]::Clear($entropy, 0, $entropy.Length)

[pscustomobject]@{
    Account = $authenticatedNames | Select-Object -First 1
    UserId = $me.id
    TenantId = (Get-MgContext).TenantId
    Scopes = (Get-MgContext).Scopes
}
