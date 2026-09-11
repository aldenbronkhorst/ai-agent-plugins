# Run: pwsh -NoLogo -NoProfile -File tests/test_connect_graph.ps1
# This test process must never resolve real Graph commands or native stores.
$ErrorActionPreference = 'Stop'
$PSModuleAutoLoadingPreference = 'None'
Import-Module Microsoft.PowerShell.Management, Microsoft.PowerShell.Utility, Microsoft.PowerShell.Security

# Install every service guard BEFORE sourcing any helper. Unexpected calls fail.
function Get-Module { [pscustomobject]@{Path='mock-graph-module'; Version=[version]'2.37.0'} }
function Import-Module { param($Name) if ($Name -ne 'mock-graph-module') { throw 'Unexpected module import' } }
function Add-Type { throw 'Native provider load forbidden in auth tests' }
function Get-MgEnvironment { param($Name) @{Name=$Name; GraphEndpoint=$script:case.GraphEndpoint; AzureADEndpoint=$script:case.AzureADEndpoint} }
function Get-MgContext { return $script:case.Context }
function Connect-MgGraph {
    param($AccessToken, $Environment, [switch]$NoWelcome)
    if ($AccessToken -isnot [Security.SecureString]) { throw 'Expected an in-memory SecureString' }
    $script:case.Events.Add('sdk-connect')
    $script:case.Context = @{AuthType='UserProvidedAccessToken'; TenantId=$script:case.Tenant; Scopes=$null; Environment=$Environment}
}
function Disconnect-MgGraph { throw 'Disconnect must never be called' }
function Invoke-MgGraphRequest {
    param($Method, $Uri)
    $script:case.Events.Add('sdk-me')
    if ($script:case.SdkFailure) { throw 'mock transport failure' }
    @{id='mock-user'; userPrincipalName=$script:case.SdkAccount; mail=$script:case.SdkAccount}
}
function Invoke-WebRequest { throw 'Real HTTP forbidden in tests' }
function Invoke-RestMethod { throw 'Real HTTP forbidden in tests' }
function Start-Process { throw 'Native process launch forbidden in tests' }
function security { throw 'Native Keychain forbidden in tests' }
function secret-tool { throw 'Native Secret Service forbidden in tests' }
function Start-Sleep { param($Seconds) $script:case.Now=$script:case.Now.AddSeconds($Seconds) }

. (Join-Path $PSScriptRoot '../scripts/graph_auth.ps1')

# Replace the internal I/O boundaries before calling the sourced implementation.
function Get-GraphUtcNow { $script:case.Now }
function Read-GraphRefreshToken {
    param($Key)
    $script:case.Events.Add("cache-read:$Key")
    if ($script:case.StoreFailure) { throw 'mock locked store' }
    return $script:case.Cache[$Key]
}
function Save-GraphRefreshToken {
    param($Key, $Token)
    if (-not $Token) { throw 'mock missing refresh token' }
    $script:case.Events.Add("cache-save:$Key")
    $script:case.Cache[$Key]=$Token
}
function Initialize-GraphKeychain { throw 'Native Keychain forbidden in tests' }
function Invoke-GraphSecretTool { throw 'Native Secret Service forbidden in tests' }
function Get-GraphTokenPath { throw 'Native cache path access forbidden in tests' }
function Invoke-GraphTokenIdentity {
    param($GraphEndpoint, $AccessToken)
    $script:case.Events.Add('token-me')
    if ($script:case.IdentityFailure) { throw 'mock identity verification failure' }
    @{id='mock-user'; userPrincipalName=$script:case.TokenAccount; mail=$script:case.TokenAccount}
}
function Invoke-GraphOAuthPost {
    param($Uri, $Body)
    if ($Uri.EndsWith('/devicecode')) {
        $script:case.Events.Add('device-code')
        return @{StatusCode=200; Content=@{device_code='MOCK_DEVICE'; message='MOCK DEVICE CODE'; expires_in=$script:case.DeviceLifetime; interval=5}}
    }
    $script:case.Events.Add($Body.grant_type)
    if ($Body.grant_type -eq 'refresh_token') {
        if ($script:case.RefreshFailure) { throw 'mock network failure' }
        if ($script:case.RefreshError) { return @{StatusCode=400; Content=@{error=$script:case.RefreshError}} }
    } else {
        $script:case.Polls++
        if ($script:case.PollError) { return @{StatusCode=400; Content=@{error=$script:case.PollError}} }
        if ($script:case.Polls -lt $script:case.SuccessAfterPoll) { return @{StatusCode=400; Content=@{error='authorization_pending'}} }
    }
    $script:case.TokenCount++
    return @{StatusCode=200; Content=@{
        access_token='MOCK_OPAQUE_TOKEN'; refresh_token="MOCK_REFRESH_$($script:case.TokenCount)";
        expires_in=3600; scope=$script:case.GrantedScopes
    }}
}

function Reset-Case {
    $script:case = @{
        Events=[Collections.Generic.List[string]]::new(); Cache=@{}; Context=$null;
        Account='alice@example.test'; SdkAccount='alice@example.test'; TokenAccount='alice@example.test';
        Tenant='11111111-2222-3333-4444-555555555555'; Now=[DateTimeOffset]'2026-01-01T00:00:00Z';
        GrantedScopes='User.Read Mail.Read'; DeviceLifetime=900; SuccessAfterPoll=1; Polls=0; TokenCount=0;
        GraphEndpoint='https://graph.example.test'; AzureADEndpoint='https://login.example.test'
    }
    $script:accountKey = Get-GraphCacheKey $script:case.Account $script:case.Tenant 'Global'
    $script:case.Cache[$script:accountKey]='MOCK_EXISTING_REFRESH'
}
function Connect-Test { param([switch]$ForceDeviceCode) Connect-GraphAccount -Account $script:case.Account -TenantId $script:case.Tenant -Scopes @('User.Read','Mail.Read') -ForceDeviceCode:$ForceDeviceCode }
function Assert-True($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Assert-Fails([scriptblock]$Action, [string]$Pattern) {
    try { $null=& $Action } catch {
        if ($_.Exception.Message -like $Pattern) { return }
        throw
    }
    throw "Expected failure: $Pattern"
}
function New-SdkContext($Scopes) { @{AuthType='Delegated'; Environment='Global'; TenantId=$script:case.Tenant; Account=$script:case.Account; Scopes=$Scopes} }
function Run-Case([string]$Name, [scriptblock]$Action) {
    Reset-Case
    & $Action
    $script:passed++
    Write-Host "PASS $Name"
}

$script:passed=0
Run-Case 'reuse verified active SDK session without touching a token store' {
    $script:case.Context=New-SdkContext @('User.Read','Mail.Read')
    $result=Connect-Test
    Assert-True ($result.Authentication -eq 'SdkManaged' -and $result.ScopeVerification -eq 'Verified') 'SDK context not reused'
    Assert-True (($script:case.Events -join ',') -eq 'sdk-me') 'Existing SDK context touched a cache or prompted'
}
Run-Case 'unknown SDK scopes stay unknown without rejecting valid personal identity' {
    $script:case.Context=New-SdkContext $null
    $result=Connect-Test
    Assert-True ($result.Authentication -eq 'SdkManaged' -and $result.ScopeVerification -eq 'Unavailable' -and -not $result.Scopes.Count) 'Unknown scopes misrepresented'
    Assert-True (($script:case.Events -join ',') -eq 'sdk-me') 'Unknown metadata caused authentication'
}
Run-Case 'known missing SDK scope requires a new token and is never claimed granted' {
    $script:case.Context=New-SdkContext @('User.Read')
    $script:case.GrantedScopes='User.Read'
    Assert-Fails { Connect-Test } '*did not grant*Mail.Read*'
    Assert-True (-not $script:case.Events.Contains('sdk-connect')) 'Connected despite missing permission'
    Assert-True ($script:case.Cache[$script:accountKey] -eq 'MOCK_EXISTING_REFRESH') 'Replaced known cache after denied scope'
}
Run-Case 'opaque token uses OAuth response scopes instead of SDK JWT metadata' {
    $result=Connect-Test
    Assert-True ($result.ScopeVerification -eq 'Verified' -and $result.Scopes -contains 'Mail.Read') 'Opaque token scopes not verified'
    Assert-True ($script:case.Context.Scopes -eq $null) 'Mock must keep SDK scopes absent'
    Assert-True (-not $script:case.Events.Contains('device-code')) 'Cached token caused device login'
}
Run-Case 'absent OAuth scope metadata returns Unavailable without inventing grants' {
    $script:case.GrantedScopes=$null
    $result=Connect-Test
    Assert-True ($result.ScopeVerification -eq 'Unavailable' -and -not $result.Scopes.Count) 'Absent metadata interpreted as consent'
}
Run-Case 'account B refresh selection preserves active and cached account A' {
    $script:case.Context=New-SdkContext @('User.Read','Mail.Read')
    $script:case.Context.Account='other@example.test'
    $otherKey=Get-GraphCacheKey 'other@example.test' $script:case.Tenant 'Global'
    $script:case.Cache[$otherKey]='MOCK_OTHER_REFRESH'
    $null=Connect-Test
    Assert-True ($script:case.Cache[$otherKey] -eq 'MOCK_OTHER_REFRESH') 'Other account cache changed'
    Assert-True ($script:case.Events.Contains("cache-read:$script:accountKey") -and -not $script:case.Events.Contains('sdk-me')) 'Wrong identity selected'
}
Run-Case 'ForceDeviceCode bypasses refresh without deleting existing cache' {
    $script:case.PollError='authorization_declined'
    Assert-Fails { Connect-Test -ForceDeviceCode } '*declined*'
    Assert-True ($script:case.Events.Contains('device-code') -and -not $script:case.Events.Contains('refresh_token')) 'Force flag ignored'
    Assert-True ($script:case.Cache[$script:accountKey] -eq 'MOCK_EXISTING_REFRESH') 'Forced failed login erased cache'
}
Run-Case 'device authentication can finish after 120 seconds' {
    $script:case.SuccessAfterPoll=30
    $result=Connect-Test -ForceDeviceCode
    Assert-True ($script:case.Polls -eq 30 -and $script:case.Now -eq [DateTimeOffset]'2026-01-01T00:02:30Z') 'Client stopped at SDK timeout'
    Assert-True ($result.ScopeVerification -eq 'Verified') 'Long device flow did not finish'
}
Run-Case 'device expiry follows server lifetime and never polls expired code' {
    $script:case.DeviceLifetime=10
    $script:case.SuccessAfterPoll=30
    Assert-Fails { Connect-Test -ForceDeviceCode } '*device code expired*'
    Assert-True ($script:case.Polls -eq 1 -and $script:case.Now -eq [DateTimeOffset]'2026-01-01T00:00:10Z') 'Incorrect device expiry'
}
Run-Case 'locked store fails before any forced device login' {
    $script:case.StoreFailure=$true
    Assert-Fails { Connect-Test -ForceDeviceCode } '*locked store*'
    Assert-True (-not $script:case.Events.Contains('device-code')) 'Locked store triggered sign-in'
}
Run-Case 'refresh transport failure never starts interactive login or clears cache' {
    $script:case.RefreshFailure=$true
    Assert-Fails { Connect-Test } '*network failure*'
    Assert-True (-not $script:case.Events.Contains('device-code')) 'Network error triggered login'
    Assert-True ($script:case.Cache[$script:accountKey] -eq 'MOCK_EXISTING_REFRESH') 'Network error erased cache'
}
Run-Case 'invalid scope refresh error does not become a new consent attempt' {
    $script:case.RefreshError='invalid_scope'
    Assert-Fails { Connect-Test } '*invalid_scope*'
    Assert-True (-not $script:case.Events.Contains('device-code')) 'Invalid scope triggered another login'
}
Run-Case 'rejected refresh authorization permits exactly one device attempt' {
    $script:case.RefreshError='invalid_grant'
    $null=Connect-Test
    Assert-True (@($script:case.Events | Where-Object {$_ -eq 'device-code'}).Count -eq 1) 'Wrong reauthorization count'
}
Run-Case 'wrong acquired account preserves original context and every cache' {
    $script:case.TokenAccount='wrong@example.test'
    $original=New-SdkContext @('User.Read')
    $script:case.Context=$original
    Assert-Fails { Connect-Test } '*different account*'
    Assert-True ([object]::ReferenceEquals($original,$script:case.Context)) 'Wrong account replaced active context'
    Assert-True ($script:case.Cache[$script:accountKey] -eq 'MOCK_EXISTING_REFRESH') 'Wrong account replaced cache'
}
Run-Case 'a provided-token session refreshes silently when helper runs again' {
    $first=Connect-Test
    $script:case.Now=$first.RefreshAfterUtc
    $second=Connect-Test
    Assert-True ($script:case.TokenCount -eq 2 -and -not $script:case.Events.Contains('device-code')) 'Token not refreshed silently'
    Assert-True ($second.ExpiresAtUtc -gt $first.ExpiresAtUtc) 'Expiry not advanced'
    Assert-True (@($script:case.Events | Where-Object {$_ -eq 'sdk-connect'}).Count -eq 2) 'Fresh token not connected'
}
Run-Case 'fully qualified Graph scope metadata matches requested short names' {
    $script:case.GrantedScopes='https://graph.example.test/User.Read https://graph.example.test/Mail.Read'
    $result=Connect-Test
    Assert-True ($result.ScopeVerification -eq 'Verified') 'Equivalent scope spellings rejected'
}
Run-Case 'failed existing SDK verification never guesses a new login' {
    $script:case.Context=New-SdkContext @('User.Read','Mail.Read')
    $script:case.SdkFailure=$true
    Assert-Fails { Connect-Test } '*existing Graph SDK session could not be verified*'
    Assert-True (($script:case.Events -join ',') -eq 'sdk-me') 'Failed SDK verification touched cache'
}
Run-Case 'tenant and cloud differences keep distinct cache keys' {
    $same=Get-GraphCacheKey 'ALICE@EXAMPLE.TEST' $script:case.Tenant 'GLOBAL'
    $tenant=Get-GraphCacheKey $script:case.Account 'another.example.test' 'Global'
    $cloud=Get-GraphCacheKey $script:case.Account $script:case.Tenant 'USGov'
    Assert-True ($same -eq $script:accountKey -and $tenant -ne $same -and $cloud -ne $same) 'Account cache isolation is inconsistent'
}
Run-Case 'insecure Graph endpoint fails before any identity or cache operation' {
    $script:case.GraphEndpoint='http://graph.example.test'
    Assert-Fails { Connect-Test } '*absolute HTTPS*'
    Assert-True ($script:case.Events.Count -eq 0) 'Insecure endpoint reached an account or cache'
}
Run-Case 'insecure authority fails before any identity or cache operation' {
    $script:case.AzureADEndpoint='http://login.example.test'
    Assert-Fails { Connect-Test } '*absolute HTTPS*'
    Assert-True ($script:case.Events.Count -eq 0) 'Insecure authority reached an account or cache'
}

# Deliberately compile only: no constructor, static method, native API or store is
# invoked. Explicit qualification selects the already loaded compiler cmdlet.
Microsoft.PowerShell.Utility\Add-Type -Path (Join-Path $PSScriptRoot '../scripts/graph_keychain.cs')
Assert-True ($null -ne ('AgentGraphKeychain' -as [type])) 'Keychain adapter did not compile'
Write-Host "PASS native Keychain declaration compiles without invoking it"
Write-Host "$script:passed authentication regression cases passed; native stores and live accounts were not used."
