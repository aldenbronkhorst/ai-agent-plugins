# Definitions only. The entrypoint opts into authentication explicitly.
. (Join-Path $PSScriptRoot 'graph_token_cache.ps1')

function Get-GraphUtcNow { return [DateTimeOffset]::UtcNow }

function ConvertTo-GraphScopeName([string]$Scope, [string]$GraphEndpoint) {
    $name = $Scope.Trim()
    $prefix = $GraphEndpoint.TrimEnd('/') + '/'
    if ($name.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { $name = $name.Substring($prefix.Length) }
    return $name
}

function Test-GraphTenant([string]$Requested, [string]$Actual) {
    if ($Requested -eq 'common') { return $true }
    $consumerTenant = '9188040d-6c67-4c5b-b112-36a304b66dad'
    if ($Requested -eq 'consumers') { return $Actual -eq $consumerTenant }
    if ($Requested -eq 'organizations') { return $Actual -and $Actual -ne $consumerTenant }
    return [string]::Equals($Requested, $Actual, [StringComparison]::OrdinalIgnoreCase)
}

function Test-GraphAccount($Me, [string]$Account) {
    return [bool](@($Me.userPrincipalName, $Me.mail) | Where-Object {
        $_ -and [string]::Equals($_.ToString().Trim(), $Account, [StringComparison]::OrdinalIgnoreCase)
    })
}

function Invoke-GraphOAuthPost([string]$Uri, [hashtable]$Body) {
    try {
        $response = Invoke-WebRequest -Method Post -Uri $Uri -ContentType 'application/x-www-form-urlencoded' `
            -Body $Body -SkipHttpErrorCheck -MaximumRedirection 0 -TimeoutSec 30
        $content = if ($response.Content) { $response.Content | ConvertFrom-Json } else { $null }
        return [pscustomobject]@{StatusCode=[int]$response.StatusCode; Content=$content}
    }
    catch { throw 'The Microsoft authentication request failed before a usable response was received. No additional sign-in was started; check connectivity and retry the same helper when ready.' }
}

function Invoke-GraphTokenIdentity([string]$GraphEndpoint, [string]$AccessToken) {
    try {
        return Invoke-RestMethod -Method Get -Uri ($GraphEndpoint.TrimEnd('/') + '/v1.0/me?$select=id,displayName,userPrincipalName,mail') `
            -Headers @{Authorization="Bearer $AccessToken"} -MaximumRedirection 0 -TimeoutSec 30
    }
    catch { throw 'Microsoft Graph could not verify the acquired identity with /me. The previous SDK context and cached sign-ins were preserved.' }
}

function Connect-GraphAccount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Account,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string[]]$Scopes,
        [string]$TenantId='common',
        [string]$Environment='Global',
        [switch]$ForceDeviceCode
    )
    $ErrorActionPreference = 'Stop'
    $accountHint = $Account.Trim()
    $tenant = $TenantId.Trim()
    if (-not $accountHint -or -not $tenant) { throw 'Account and TenantId must not be blank.' }
    if ($tenant -notmatch '^[A-Za-z0-9.-]+$') { throw 'TenantId must be a Microsoft tenant ID, verified domain, common, organizations, or consumers.' }
    $module = Get-Module Microsoft.Graph.Authentication -ListAvailable |
        Where-Object Version -GE ([version]'2.37.0') | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $module) { throw 'Microsoft.Graph.Authentication 2.37.0 or newer is required. Install the current module for this user and retry.' }
    Import-Module $module.Path
    $graphEnvironment = Get-MgEnvironment -Name $Environment | Select-Object -First 1
    if (-not $graphEnvironment) { throw "Microsoft Graph environment '$Environment' is not configured." }
    foreach ($endpoint in @($graphEnvironment.GraphEndpoint, $graphEnvironment.AzureADEndpoint)) {
        $parsed = $null
        if (-not [uri]::TryCreate($endpoint, [UriKind]::Absolute, [ref]$parsed) -or
            $parsed.Scheme -ne 'https' -or $parsed.UserInfo -or $parsed.Query -or $parsed.Fragment) {
            throw 'Configured Graph and Microsoft authentication endpoints must be absolute HTTPS URLs without credentials, query strings, or fragments.'
        }
    }
    $graphEndpoint = $graphEnvironment.GraphEndpoint.Trim().TrimEnd('/')
    $graphScopes = @(@('User.Read') + $Scopes | ForEach-Object { ConvertTo-GraphScopeName $_ $graphEndpoint } | Where-Object { $_ } | Select-Object -Unique)
    if (@($graphScopes | Where-Object { $_ -eq '.default' -or $_ -match '[\s/:]' }).Count) {
        throw 'Use named delegated Microsoft Graph scopes for device authentication; do not combine .default or another resource with them.'
    }

    # Preserve an already active SDK session and its automatic refresh. The
    # persisted SDK last-account record is never probed through interactive login.
    $context = Get-MgContext
    if (-not $ForceDeviceCode -and $context -and $context.AuthType -eq 'Delegated' -and
        $context.Environment -eq $Environment -and (Test-GraphTenant $tenant $context.TenantId) -and
        (-not $context.Account -or [string]::Equals($context.Account, $accountHint, [StringComparison]::OrdinalIgnoreCase))) {
        $contextScopes = @($context.Scopes | Where-Object { $_ } | ForEach-Object { ConvertTo-GraphScopeName $_ $graphEndpoint })
        $missing = @($graphScopes | Where-Object { $contextScopes -notcontains $_ })
        if (-not $contextScopes.Count -or -not $missing.Count) {
            try { $me = Invoke-MgGraphRequest -Method GET -Uri 'v1.0/me?$select=id,displayName,userPrincipalName,mail' }
            catch { throw 'The existing Graph SDK session could not be verified. Diagnose that request before starting another sign-in; its cached authorization was preserved.' }
            if (Test-GraphAccount $me $accountHint) {
                return [pscustomobject]@{
                    Account=$accountHint; UserId=$me.id; TenantId=$context.TenantId; RequestedTenant=$tenant
                    Scopes=$contextScopes; ScopeVerification=$(if ($contextScopes.Count) {'Verified'} else {'Unavailable'})
                    Authentication='SdkManaged'; ExpiresAtUtc=$null; RefreshAfterUtc=$null
                }
            }
        }
    }

    $cacheKey = Get-GraphCacheKey $accountHint $tenant $Environment
    # Reading first also detects a locked/unavailable store before a forced login.
    # Force bypasses use of the token; it never removes saved data.
    $refreshToken = Read-GraphRefreshToken $cacheKey
    if ($ForceDeviceCode) { $refreshToken = $null }
    $authority = $graphEnvironment.AzureADEndpoint.Trim().TrimEnd('/')
    $tokenEndpoint = "$authority/$tenant/oauth2/v2.0/token"
    $clientId = '14d82eec-204b-4c2f-b7e8-296a70dab67e'
    $scopeText = (@('openid', 'profile', 'offline_access') + $graphScopes | Select-Object -Unique) -join ' '
    $tokenResult = $null
    $refreshTokenToSave = $null
    if ($refreshToken) {
        $refresh = Invoke-GraphOAuthPost $tokenEndpoint @{
            client_id=$clientId; grant_type='refresh_token'; refresh_token=$refreshToken; scope=$scopeText
        }
        if ($refresh.StatusCode -eq 200) {
            $tokenResult = $refresh.Content
            $refreshTokenToSave = if ($tokenResult.refresh_token) { $tokenResult.refresh_token } else { $refreshToken }
        }
        elseif ($refresh.Content.error -notin @('invalid_grant', 'interaction_required', 'consent_required')) {
            throw "Microsoft token refresh failed (HTTP $($refresh.StatusCode), $($refresh.Content.error)). The cache was preserved; no new sign-in was started."
        }
    }
    if (-not $tokenResult) {
        $device = Invoke-GraphOAuthPost "$authority/$tenant/oauth2/v2.0/devicecode" @{client_id=$clientId; scope=$scopeText}
        if ($device.StatusCode -ne 200) { throw "Microsoft device-code request failed (HTTP $($device.StatusCode), $($device.Content.error)). Diagnose the returned error before changing scopes or starting another attempt." }
        if (-not $device.Content.device_code -or [int]$device.Content.expires_in -le 0) { throw 'Microsoft returned an incomplete device authorization response.' }
        [Console]::WriteLine($device.Content.message)
        $interval = [Math]::Max([int]$device.Content.interval, 5)
        $deviceExpiresAt = (Get-GraphUtcNow).AddSeconds([int]$device.Content.expires_in)
        while ((Get-GraphUtcNow) -lt $deviceExpiresAt) {
            $remaining = ($deviceExpiresAt - (Get-GraphUtcNow)).TotalSeconds
            if ($remaining -le 0) { break }
            Start-Sleep -Seconds ([Math]::Min($interval, [Math]::Ceiling($remaining)))
            if ((Get-GraphUtcNow) -ge $deviceExpiresAt) { break }
            $poll = Invoke-GraphOAuthPost $tokenEndpoint @{
                client_id=$clientId; grant_type='urn:ietf:params:oauth:grant-type:device_code'; device_code=$device.Content.device_code
            }
            if ($poll.StatusCode -eq 200) {
                $tokenResult = $poll.Content
                $refreshTokenToSave = $tokenResult.refresh_token
                break
            }
            switch ($poll.Content.error) {
                'authorization_pending' { }
                'slow_down' { $interval += 5 }
                'authorization_declined' { throw 'Microsoft sign-in was declined.' }
                'expired_token' { throw 'The Microsoft device code expired before sign-in completed.' }
                default { throw "Microsoft device-code sign-in failed (HTTP $($poll.StatusCode), $($poll.Content.error)). The saved sign-ins were preserved." }
            }
        }
        if (-not $tokenResult) { throw 'The Microsoft device code expired before sign-in completed.' }
    }

    if (-not $tokenResult.access_token -or [int]$tokenResult.expires_in -le 0) { throw 'Microsoft returned an incomplete access-token response.' }
    $expiresAt = (Get-GraphUtcNow).AddSeconds([int]$tokenResult.expires_in)
    # OAuth response scopes also work with opaque personal-account tokens.
    $grantedScopes = @()
    $scopeVerification = 'Unavailable'
    if ($tokenResult.scope) {
        $grantedScopes = @($tokenResult.scope -split '\s+' | Where-Object { $_ } | ForEach-Object { ConvertTo-GraphScopeName $_ $graphEndpoint } | Select-Object -Unique)
        $missing = @($graphScopes | Where-Object { $grantedScopes -notcontains $_ })
        if ($missing.Count) { throw "Microsoft did not grant all requested Graph permissions: $($missing -join ', '). Existing cached authorization was preserved." }
        $scopeVerification = 'Verified'
    }
    $me = Invoke-GraphTokenIdentity $graphEndpoint $tokenResult.access_token
    if (-not (Test-GraphAccount $me $accountHint)) { throw "Microsoft authenticated a different account. Choose '$accountHint' on the next device-login attempt; existing contexts and saved sign-ins were preserved." }
    Save-GraphRefreshToken $cacheKey $refreshTokenToSave
    $secureToken = ConvertTo-SecureString $tokenResult.access_token -AsPlainText -Force
    try { Connect-MgGraph -AccessToken $secureToken -Environment $Environment -NoWelcome }
    finally { $secureToken.Dispose() }
    $connected = Get-MgContext
    return [pscustomobject]@{
        Account=$accountHint; UserId=$me.id; TenantId=$connected.TenantId; RequestedTenant=$tenant
        Scopes=$grantedScopes; ScopeVerification=$scopeVerification; Authentication='ProvidedToken'
        ExpiresAtUtc=$expiresAt; RefreshAfterUtc=$expiresAt.AddMinutes(-5)
    }
}
