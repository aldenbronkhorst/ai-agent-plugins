# No real Keychain, Secret Service, DPAPI or service-account access in this test.
param([switch]$LegacyAdapter)
$ErrorActionPreference = 'Stop'
$PSModuleAutoLoadingPreference = 'None'
Import-Module Microsoft.PowerShell.Management, Microsoft.PowerShell.Utility
Set-Variable IsMacOS -Value $true -Force
Set-Variable IsLinux -Value $false -Force
Set-Variable IsWindows -Value $false -Force

if ($LegacyAdapter) {
    Add-Type -TypeDefinition @'
public static class AgentGraphKeychain {
    public static string Access(string service, string account, string replacement) {
        throw new System.Exception("Unsafe legacy adapter was invoked");
    }
}
'@
} else {
    # Match the actual .NET string signatures: a PowerShell $null passed to Access
    # is converted to an empty string, exercising the historical destructive read.
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
public static class AgentGraphKeychain {
    public static readonly Dictionary<string, string> Store = new Dictionary<string, string>();
    public static int Reads;
    public static int Writes;
    public static string Read(string service, string account) {
        Reads++;
        return Store.TryGetValue(service + "/" + account, out var token) ? token : null;
    }
    public static void Write(string service, string account, string replacement) {
        Writes++;
        Store[service + "/" + account] = replacement;
    }
    public static string Access(string service, string account, string replacement) {
        if (replacement == null) return Read(service, account);
        Write(service, account, replacement);
        return null;
    }
}
'@
}
function Invoke-WebRequest { throw 'Network forbidden in token-cache tests' }
function Invoke-RestMethod { throw 'Network forbidden in token-cache tests' }
function Start-Process { throw 'Native processes forbidden in token-cache tests' }
function Add-Type { throw 'Real native provider load forbidden in token-cache tests' }
. (Join-Path $PSScriptRoot '../scripts/graph_token_cache.ps1')
function Assert-True($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }

if ($LegacyAdapter) {
    try { $null = Read-GraphRefreshToken 'fake-key'; throw 'Expected an upgrade error' }
    catch {
        Assert-True ($_.Exception.Message -like '*fresh PowerShell process*') 'Old in-memory adapter was not rejected safely'
    }
    Write-Host 'PASS old in-memory adapter stops before credential access'
    return
}

$service = 'ai-agent-plugins.microsoft-graph'
[AgentGraphKeychain]::Store["$service/existing"] = 'FAKE_REFRESH'
$token = Read-GraphRefreshToken 'existing'
Assert-True ($token -eq 'FAKE_REFRESH') 'A read failed to return the stored sign-in'
Assert-True ([AgentGraphKeychain]::Writes -eq 0) 'A read overwrote the stored sign-in'
Write-Host 'PASS a saved sign-in is read without writes through the actual PowerShell-to-.NET boundary'

$null = Read-GraphRefreshToken 'existing'
Assert-True ([AgentGraphKeychain]::Store["$service/existing"] -eq 'FAKE_REFRESH' -and [AgentGraphKeychain]::Writes -eq 0) 'Repeated reads changed the token'
Write-Host 'PASS repeated reads retain the sign-in'

$missing = Read-GraphRefreshToken 'missing'
Assert-True (-not $missing -and -not [AgentGraphKeychain]::Store.ContainsKey("$service/missing")) 'A missing read created a blank credential'
Write-Host 'PASS missing credentials remain missing without creation'

Save-GraphRefreshToken 'existing' 'FAKE_ROTATED_REFRESH'
Assert-True ([AgentGraphKeychain]::Writes -eq 1 -and (Read-GraphRefreshToken 'existing') -eq 'FAKE_ROTATED_REFRESH') 'Explicit save did not persist the rotated token'
Write-Host 'PASS explicit save is the only write operation'

foreach ($empty in @($null, '')) {
    try { Save-GraphRefreshToken 'existing' $empty; throw 'Expected empty-token rejection' }
    catch { Assert-True ($_.Exception.Message -like '*did not return refresh material*') 'Empty token was not rejected before storage' }
}
Assert-True ([AgentGraphKeychain]::Writes -eq 1) 'Empty save touched the store'
Write-Host 'PASS empty saves cannot erase the sign-in'

Save-GraphRefreshToken 'other' 'FAKE_OTHER_REFRESH'
Assert-True ((Read-GraphRefreshToken 'existing') -eq 'FAKE_ROTATED_REFRESH' -and (Read-GraphRefreshToken 'other') -eq 'FAKE_OTHER_REFRESH') 'Account stores were mixed'
Write-Host 'PASS accounts retain separate saved sign-ins'
