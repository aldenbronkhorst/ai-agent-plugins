# Run with: pwsh -NoProfile -File ./test_connect_exchange.ps1
# Only built-in utility modules are loaded. Every service command is shadowed
# BEFORE the helper runs; unexpected CLI commands fail closed.
Import-Module Microsoft.PowerShell.Utility
Import-Module Microsoft.PowerShell.Management
$PSModuleAutoLoadingPreference = 'None'
$ErrorActionPreference = 'Stop'
$helper = Join-Path $PSScriptRoot '../scripts/connect_exchange.ps1'
$testAccount = 'operator@example.invalid'
$testTenant = '11111111-2222-3333-4444-555555555555'
$savedAzureConfig = $env:AZURE_CONFIG_DIR
$passed = 0

function New-TestContext([string]$Cloud = 'AzureCloud', [string]$User = $testAccount) {
    return [pscustomobject]@{ user = @{ name = $User }; tenantId = $testTenant; environmentName = $Cloud }
}

function New-TestConnection([string]$Uri = 'https://outlook.office365.com') {
    return [pscustomobject]@{
        ConnectionId = [guid]::NewGuid().ToString()
        Name = 'ExchangeOnline_1'
        State = 'Connected'
        UserPrincipalName = $testAccount
        TenantID = $testTenant
        ConnectionUri = $Uri
        IsEopSession = $false
        TokenStatus = 'Active'
        TokenExpiryTimeUTC = [DateTimeOffset]::UtcNow.AddHours(1)
    }
}

function Reset-Scenario {
    $script:scenario = @{
        Events = [Collections.Generic.List[string]]::new()
        AzureCalls = [Collections.Generic.List[object]]::new()
        Connections = @()
        Contexts = @((New-TestContext))
        ContextIndex = 0
        TokenResults = @(@{ Code = 0; Text = 'dummy-access-token' })
        TokenIndex = 0
        LoginHelp = '--scope --use-device-code --skip-subscription-discovery --allow-no-subscriptions'
        LoginCount = 0
        ConnectCount = 0
        MetadataIssuer = $null
        ConnectionOverride = $null
        ModuleLoaded = $true
    }
    $env:AZURE_CONFIG_DIR = 'synthetic-original-profile'
}

# These mocks are installed before any helper invocation, including module discovery.
function Get-Module {
    param($Name, [switch]$ListAvailable)
    if ($ListAvailable -or $scenario.ModuleLoaded) {
        [pscustomobject]@{ Path = 'mock-exchange-module'; Version = [version]'3.9.0' }
    }
}
function Import-Module { param($Name) $scenario.ModuleLoaded = $true }
function New-Item { param($ItemType, $Path, [switch]$Force) $scenario.Events.Add('create-profile') }
function chmod { $global:LASTEXITCODE = 0 }
function Get-ConnectionInformation {
    [CmdletBinding()]param()
    $scenario.Events.Add('connections')
    return $scenario.Connections
}
function Connect-ExchangeOnline {
    [CmdletBinding()]param($AccessToken, $UserPrincipalName, [bool]$ShowBanner, $ExchangeEnvironmentName)
    $scenario.Events.Add('connect')
    $scenario.ConnectCount++
    $scenario.LastConnect = $PSBoundParameters
    $endpoints = @{
        O365Default = 'https://outlook.office365.com'
        O365China = 'https://partner.outlook.cn'
        O365GermanyCloud = 'https://outlook.office.de'
        O365USGovGCCHigh = 'https://outlook.office365.us'
        O365USGovDoD = 'https://webmail.apps.mil'
    }
    $connection = New-TestConnection $endpoints[$ExchangeEnvironmentName]
    if ($scenario.ConnectionOverride) { $connection = $scenario.ConnectionOverride }
    $scenario.Connections += $connection
}
function Disconnect-ExchangeOnline { throw 'Unexpected disconnect; test will not resolve the real cmdlet.' }
function Connect-IPPSSession { throw 'Unexpected compliance sign-in; test will not resolve the real cmdlet.' }
function Invoke-RestMethod {
    param($Uri, $TimeoutSec)
    $scenario.Events.Add('metadata')
    $scenario.MetadataUri = $Uri
    $issuer = $scenario.MetadataIssuer
    if (-not $issuer) { $issuer = "https://$(([uri]$Uri).Host)/$testTenant/v2.0" }
    return [pscustomobject]@{ issuer = $issuer }
}
function az {
    $cliArgs = @($args)
    $scenario.AzureCalls.Add(@{ Arguments = $cliArgs; Profile = $env:AZURE_CONFIG_DIR })
    $scenario.Events.Add("az $($cliArgs[0]) $($cliArgs[1])")
    $global:LASTEXITCODE = 0
    if ($cliArgs[0] -eq 'account' -and $cliArgs[1] -eq 'show') {
        $index = [Math]::Min($scenario.ContextIndex++, $scenario.Contexts.Count - 1)
        $context = $scenario.Contexts[$index]
        if ($null -eq $context) {
            $global:LASTEXITCODE = 1
            return "ERROR: Please run 'az login' to setup account."
        }
        return $context | ConvertTo-Json -Depth 5
    }
    if ($cliArgs[0] -eq 'account' -and $cliArgs[1] -eq 'get-access-token') {
        $index = [Math]::Min($scenario.TokenIndex++, $scenario.TokenResults.Count - 1)
        $result = $scenario.TokenResults[$index]
        $global:LASTEXITCODE = $result.Code
        return $result.Text
    }
    if ($cliArgs[0] -eq 'cloud' -and $cliArgs[1] -eq 'set') { return }
    if ($cliArgs[0] -eq 'login' -and $cliArgs[1] -eq '--help') { return $scenario.LoginHelp }
    if ($cliArgs[0] -eq 'login') { $scenario.LoginCount++; return }
    throw "Unexpected mocked az command: $($cliArgs -join ' ')"
}

function Assert-Equal($Actual, $Expected, [string]$Message) {
    if ($Actual -ne $Expected) { throw "$Message (expected $Expected; got $Actual)" }
}
function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Invoke-HelperFailure([hashtable]$Parameters = @{}) {
    try { & $helper -Account $testAccount -Tenant $testTenant @Parameters | Out-Null }
    catch { return $_.Exception.Message }
    throw 'Expected helper to fail.'
}
function Invoke-Test([string]$Name, [scriptblock]$Body) {
    Reset-Scenario
    & $Body
    Assert-Equal $env:AZURE_CONFIG_DIR 'synthetic-original-profile' 'Helper must restore the caller profile'
    $script:passed++
    Write-Host "PASS $Name"
}

try {
    Invoke-Test 'healthy Exchange connection is reused before any Azure CLI operation' {
        $scenario.Connections = @((New-TestConnection))
        $result = & $helper -Account $testAccount -Tenant $testTenant
        Assert-Equal $result.ConnectionId $scenario.Connections[0].ConnectionId 'Existing connection should be returned'
        Assert-Equal $scenario.AzureCalls.Count 0 'Healthy reuse must not inspect Azure accounts or fetch tokens'
    }

    Invoke-Test 'expired access-token connection is reconnected silently' {
        $connection = New-TestConnection
        $connection.TokenStatus = 'Expired'
        $scenario.Connections = @($connection)
        $result = & $helper -Account $testAccount -Tenant $testTenant
        Assert-Equal $scenario.Events[0] 'connections' 'Exchange health must precede token work'
        Assert-Equal $scenario.ConnectCount 1 'Fresh token must be passed to Connect-ExchangeOnline'
        Assert-Equal $scenario.LoginCount 0 'Cached refresh must not trigger login'
        Assert-True ($result.ConnectionId -ne $connection.ConnectionId) 'Expired connection must not be returned'
    }

    Invoke-Test 'token expiry timestamp overrides stale Active status' {
        $connection = New-TestConnection
        $connection.TokenExpiryTimeUTC = [DateTimeOffset]::UtcNow.AddMinutes(-1)
        $scenario.Connections = @($connection)
        & $helper -Account $testAccount -Tenant $testTenant | Out-Null
        Assert-Equal $scenario.ConnectCount 1 'Expired timestamp must trigger silent reconnect'
    }

    Invoke-Test 'transient token failure does not trigger device login' {
        $scenario.TokenResults = @(@{ Code = 1; Text = 'HTTPSConnectionPool: connection timed out' })
        $message = Invoke-HelperFailure
        Assert-True ($message -like '*no new sign-in*') 'Transport error should be distinguished from interaction requirements'
        Assert-Equal $scenario.LoginCount 0 'No login should run on transient failure'
        Assert-Equal $scenario.ConnectCount 0 'No connection should run without a token'
    }

    Invoke-Test 'revoked cached refresh authorization permits one device login' {
        $scenario.TokenResults = @(@{ Code = 1; Text = 'AADSTS700082: refresh token expired' }, @{ Code = 0; Text = 'dummy-refreshed-token' })
        & $helper -Account $testAccount -Tenant $testTenant | Out-Null
        Assert-Equal $scenario.LoginCount 1 'A verified refresh rejection should allow login'
        Assert-Equal $scenario.TokenIndex 2 'Token acquisition should resume once after login'
        Assert-Equal $scenario.ConnectCount 1 'Only one Exchange connection should be created'
    }

    Invoke-Test 'compliance session is excluded and preserved' {
        $connection = New-TestConnection 'https://nam12b.ps.compliance.protection.outlook.com'
        $connection.IsEopSession = $true
        $connection.Name = 'ExchangeOnlineProtection_1'
        $scenario.Connections = @($connection)
        $result = & $helper -Account $testAccount -Tenant $testTenant
        Assert-Equal $scenario.ConnectCount 1 'Compliance connection cannot substitute for Exchange'
        Assert-Equal $scenario.Connections.Count 2 'Compliance connection must remain'
        Assert-True ($result.ConnectionId -ne $connection.ConnectionId) 'Return the Exchange session'
    }

    Invoke-Test 'domain resolves to canonical tenant even without tenantDefaultDomain' {
        $result = & $helper -Account $testAccount -Tenant 'example.onmicrosoft.com'
        Assert-Equal $result.TenantId $testTenant 'Domain should resolve through public discovery'
        Assert-Equal $scenario.LoginCount 0 'Verified domain alias should accept the cached GUID context'
    }

    Invoke-Test 'foreign issuer is rejected before account or token operations' {
        $scenario.MetadataIssuer = "https://foreign.example.invalid/$testTenant/v2.0"
        $message = $null
        try { & $helper -Account $testAccount -Tenant 'example.onmicrosoft.com' | Out-Null }
        catch { $message = $_.Exception.Message }
        Assert-True ($message -like '*verified tenant GUID*') 'Foreign issuer must be rejected'
        Assert-Equal $scenario.AzureCalls.Count 0 'No CLI call before tenant verification'
    }

    Invoke-Test 'government profile selects cloud and preserves unrelated public context' {
        $unrelated = New-TestConnection
        $scenario.Connections = @($unrelated)
        $scenario.Contexts = @((New-TestContext), (New-TestContext 'AzureUSGovernment'))
        & $helper -Account $testAccount -Tenant $testTenant -ExchangeEnvironmentName O365USGovGCCHigh | Out-Null
        $cloudCall = @($scenario.AzureCalls | Where-Object { $_.Arguments[0] -eq 'cloud' })[0]
        Assert-True ($cloudCall.Arguments -contains 'AzureUSGovernment') 'Isolated profile must select government cloud'
        Assert-True ($cloudCall.Profile -ne 'synthetic-original-profile') 'Shared profile cloud must not be changed'
        Assert-Equal $scenario.LoginCount 0 'Existing matching government cache should be reused'
        Assert-Equal $scenario.LastConnect.ExchangeEnvironmentName 'O365USGovGCCHigh' 'Connect must use the same environment'
        Assert-Equal $scenario.Connections[0].ConnectionId $unrelated.ConnectionId 'Existing public connection must remain'
    }

    Invoke-Test 'matching sovereign cached context needs no profile change or login' {
        $scenario.Contexts = @((New-TestContext 'AzureUSGovernment'))
        & $helper -Account $testAccount -Tenant $testTenant -ExchangeEnvironmentName O365USGovDoD | Out-Null
        Assert-Equal @($scenario.AzureCalls | Where-Object { $_.Arguments[0] -eq 'cloud' }).Count 0 'Matching cloud must remain selected'
        Assert-Equal $scenario.LoginCount 0 'Valid cached account should avoid login'
    }

    Invoke-Test 'China tenant resolution and native cloud endpoints are consistent' {
        $scenario.Contexts = @((New-TestContext 'AzureChinaCloud'))
        & $helper -Account $testAccount -Tenant 'example.partner.onmschina.cn' -ExchangeEnvironmentName O365China | Out-Null
        Assert-True ($scenario.MetadataUri -like 'https://login.partner.microsoftonline.cn/*') 'China must use its OIDC authority'
        $tokenCall = @($scenario.AzureCalls | Where-Object { $_.Arguments[1] -eq 'get-access-token' })[0]
        Assert-True ($tokenCall.Arguments -contains 'https://partner.outlook.cn') 'Token resource must match China'
    }

    Invoke-Test 'custom token audience does not change service endpoint validation' {
        & $helper -Account $testAccount -Tenant $testTenant -ExchangeResource 'https://outlook.office.com/' | Out-Null
        $tokenCall = @($scenario.AzureCalls | Where-Object { $_.Arguments[1] -eq 'get-access-token' })[0]
        Assert-True ($tokenCall.Arguments -contains 'https://outlook.office.com') 'Explicit token resource must be honored'
        Assert-Equal $scenario.ConnectCount 1 'Standard Exchange endpoint remains valid'
    }

    Invoke-Test 'older Azure CLI supports domain login without subscriptions' {
        $scenario.Contexts = @($null, $null, (New-TestContext))
        $scenario.LoginHelp = '--scope --use-device-code --allow-no-subscriptions'
        & $helper -Account $testAccount -Tenant 'example.onmicrosoft.com' | Out-Null
        $loginCall = @($scenario.AzureCalls | Where-Object { $_.Arguments[0] -eq 'login' -and $_.Arguments[1] -ne '--help' })[0]
        Assert-True ($loginCall.Arguments -contains '--allow-no-subscriptions') 'Older compatible flag must be used'
        Assert-True ($loginCall.Arguments -notcontains '--skip-subscription-discovery') 'Unsupported flag must be omitted'
        Assert-True ($loginCall.Arguments -contains $testTenant) 'Login must use resolved tenant GUID'
        Assert-Equal $scenario.LoginCount 1 'One login is sufficient without subscription metadata'
    }

    Invoke-Test 'fresh login cannot start a second login when token still requires interaction' {
        $scenario.Contexts = @($null, $null, (New-TestContext))
        $scenario.TokenResults = @(@{ Code = 1; Text = 'AADSTS65001: consent required' })
        $message = Invoke-HelperFailure
        Assert-Equal $scenario.LoginCount 1 'Must never issue a second device code in one invocation'
        Assert-True ($message -like '*no second device login*') 'Explain the remaining consent or policy requirement'
    }

    Invoke-Test 'unsupported CLI login capabilities fail before starting sign-in' {
        $scenario.Contexts = @($null, $null)
        $scenario.LoginHelp = '--use-device-code --allow-no-subscriptions'
        $message = Invoke-HelperFailure
        Assert-True ($message -like '*required login options*') 'Missing capability should identify the prerequisite'
        Assert-Equal $scenario.LoginCount 0 'No login may start with unsupported arguments'
    }

    Invoke-Test 'unexpected post-login account is rejected without clearing any account cache' {
        $wrongContext = New-TestContext 'AzureCloud' 'other@example.invalid'
        $scenario.Contexts = @($wrongContext, $wrongContext, $wrongContext)
        $message = Invoke-HelperFailure
        Assert-True ($message -like '*different account*') 'Wrong identity should be rejected explicitly'
        Assert-Equal $scenario.TokenIndex 0 'No token should be requested for the wrong identity'
        Assert-Equal $scenario.LoginCount 1 'There should be no sign-in loop'
    }

    Invoke-Test 'post-connect verification rejects an unexpected environment' {
        $scenario.ConnectionOverride = New-TestConnection 'https://outlook.office365.us'
        $message = Invoke-HelperFailure
        Assert-True ($message -like '*did not establish a healthy connection*') 'Wrong environment cannot be reported as success'
    }
    Write-Host "$passed offline Exchange regression tests passed."
}
finally {
    $env:AZURE_CONFIG_DIR = $savedAzureConfig
}
