# Opt-in macOS integration test. Only synthetic data in a separate test service;
# no Microsoft requests or real account credentials. Removes its own test entries.
param([switch]$ReadProbe, [string]$TestAccount)
$ErrorActionPreference = 'Stop'
if (-not $IsMacOS) { Write-Host 'SKIP native Keychain test requires macOS'; return }
Add-Type -Path (Join-Path $PSScriptRoot '../scripts/graph_keychain.cs')
$service = 'ai-agent-plugins.microsoft-graph.selftest'
$fakeToken = 'FAKE_GRAPH_REFRESH_NOT_A_CREDENTIAL'
function Assert-True($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }

if ($ReadProbe) {
    Assert-True ($TestAccount -cmatch '^selftest-[a-f0-9]{32}$') 'Invalid synthetic test account'
    Assert-True ([AgentGraphKeychain]::Read($service, $TestAccount) -eq $fakeToken) 'Fresh-process read failed'
    Write-Host 'PASS real Keychain retains synthetic sign-in across PowerShell processes'
    return
}

$account = 'selftest-' + [Guid]::NewGuid().ToString('N')
try {
    [AgentGraphKeychain]::Write($service, $account, $fakeToken)
    foreach ($attempt in 1..3) {
        Assert-True ([AgentGraphKeychain]::Read($service, $account) -eq $fakeToken) 'Repeated native read changed the stored value'
    }
    Write-Host 'PASS repeated real Keychain reads preserve synthetic sign-in'
    & (Join-Path $PSHOME 'pwsh') -NoLogo -NoProfile -File $PSCommandPath -ReadProbe -TestAccount $account
    Assert-True ($LASTEXITCODE -eq 0) 'Fresh-process Keychain probe failed'

    foreach ($empty in @($null, '')) {
        try { [AgentGraphKeychain]::Write($service, $account, $empty); throw 'Expected empty-token rejection' }
        catch { Assert-True ($_.Exception.Message -like '*empty refresh token*') 'Native adapter did not reject empty write' }
    }
    Assert-True ([AgentGraphKeychain]::Read($service, $account) -eq $fakeToken) 'Empty write damaged the stored value'
    Write-Host 'PASS native adapter rejects empty writes without modifying the sign-in'

    Assert-True ($null -eq [AgentGraphKeychain]::Read($service, "$account-missing")) 'Missing read returned data'
    & /usr/bin/security find-generic-password -s $service -a "$account-missing" *> $null
    Assert-True ($LASTEXITCODE -eq 44) 'Missing read created a Keychain entry'
    Write-Host 'PASS missing native reads create no Keychain entry'
}
finally {
    foreach ($testKey in @($account, "$account-missing")) {
        & /usr/bin/security delete-generic-password -s $service -a $testKey *> $null
        if ($LASTEXITCODE -notin @(0, 44)) { throw 'Could not remove a synthetic Keychain test entry' }
    }
}
Write-Host 'PASS synthetic Keychain test entries removed'
exit 0
