# Functions only: sourcing this file must not load a provider or access a cache.
function Get-GraphCacheKey([string]$Account, [string]$Tenant, [string]$Environment) {
    $bytes = [Text.Encoding]::UTF8.GetBytes("$($Account.ToLowerInvariant())`n$($Tenant.ToLowerInvariant())`n$($Environment.ToLowerInvariant())")
    try { return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant() }
    finally { [Array]::Clear($bytes, 0, $bytes.Length) }
}

function Get-GraphTokenPath([string]$Key) {
    $localData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if (-not $localData) { throw 'The current user has no local application-data directory.' }
    return Join-Path $localData "AI Agent Plugins/Microsoft Graph/$Key.refresh-token"
}

function Invoke-GraphSecretTool([string[]]$Arguments, [string]$InputText) {
    $tool = Get-Command secret-tool -CommandType Application -ErrorAction SilentlyContinue
    if (-not $tool) { throw 'Persistent Graph sign-in requires secret-tool (libsecret) and an unlocked Secret Service session on Linux. Configure that local store before retrying.' }
    $start = [Diagnostics.ProcessStartInfo]::new($tool.Source)
    $start.UseShellExecute = $false
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        $null = $process.Start()
        $output = $process.StandardOutput.ReadToEndAsync()
        $errorText = $process.StandardError.ReadToEndAsync()
        if ($null -ne $InputText) { $process.StandardInput.Write($InputText) }
        $process.StandardInput.Close()
        if (-not $process.WaitForExit(30000)) {
            $process.Kill()
            throw 'Graph Secret Service access timed out. Unlock or repair the local store before retrying.'
        }
        return [pscustomobject]@{ ExitCode=$process.ExitCode; Output=$output.GetAwaiter().GetResult(); ErrorText=$errorText.GetAwaiter().GetResult() }
    }
    finally { $process.Dispose() }
}

function Initialize-GraphKeychain {
    if (-not ('AgentGraphKeychain' -as [type])) {
        Add-Type -Path (Join-Path $PSScriptRoot 'graph_keychain.cs')
    }
}

function Read-GraphRefreshToken([string]$Key) {
    if ($IsMacOS) {
        Initialize-GraphKeychain
        return [AgentGraphKeychain]::Access('ai-agent-plugins.microsoft-graph', $Key, $null)
    }
    if ($IsLinux) {
        $result = Invoke-GraphSecretTool -Arguments @('lookup', 'service', 'ai-agent-plugins.microsoft-graph', 'account', $Key)
        if ($result.ExitCode -eq 0) { return $result.Output.TrimEnd("`r", "`n") }
        if ($result.ExitCode -eq 1 -and -not $result.ErrorText.Trim()) { return $null }
        throw "Graph Secret Service lookup failed (exit $($result.ExitCode)). Repair the local store before retrying; the cached sign-in was preserved."
    }
    if (-not $IsWindows) { throw 'Persistent Graph authentication is supported on Windows, macOS, and Linux.' }
    Add-Type -AssemblyName System.Security.Cryptography.ProtectedData
    $path = Get-GraphTokenPath $Key
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $protected = $plain = $entropy = $null
    try {
        $protected = [IO.File]::ReadAllBytes($path)
        $entropy = [Text.Encoding]::UTF8.GetBytes("ai-agent-plugins.microsoft-graph:$Key")
        $plain = [Security.Cryptography.ProtectedData]::Unprotect($protected, $entropy, [Security.Cryptography.DataProtectionScope]::CurrentUser)
        return [Text.Encoding]::UTF8.GetString($plain)
    }
    catch { throw 'The protected Graph cache could not be read. Repair local cache access before retrying; it has not been deleted.' }
    finally {
        foreach ($bytes in @($protected, $plain, $entropy)) { if ($null -ne $bytes) { [Array]::Clear($bytes, 0, $bytes.Length) } }
    }
}

function Save-GraphRefreshToken([string]$Key, [string]$Token) {
    if (-not $Token) { throw 'Microsoft did not return refresh material for persistent sign-in.' }
    if ($IsMacOS) {
        Initialize-GraphKeychain
        $null = [AgentGraphKeychain]::Access('ai-agent-plugins.microsoft-graph', $Key, $Token)
        return
    }
    if ($IsLinux) {
        $result = Invoke-GraphSecretTool -Arguments @('store', '--label=Microsoft Graph', 'service', 'ai-agent-plugins.microsoft-graph', 'account', $Key) -InputText $Token
        if ($result.ExitCode -ne 0) { throw "Graph Secret Service save failed (exit $($result.ExitCode)). Repair the local store before retrying." }
        return
    }
    if (-not $IsWindows) { throw 'Persistent Graph authentication is supported on Windows, macOS, and Linux.' }
    Add-Type -AssemblyName System.Security.Cryptography.ProtectedData
    $path = Get-GraphTokenPath $Key
    $null = New-Item -ItemType Directory -Path (Split-Path $path) -Force
    $temporaryPath = "$path.$([Guid]::NewGuid().ToString('N')).tmp"
    $plain = $protected = $entropy = $null
    try {
        $plain = [Text.Encoding]::UTF8.GetBytes($Token)
        $entropy = [Text.Encoding]::UTF8.GetBytes("ai-agent-plugins.microsoft-graph:$Key")
        $protected = [Security.Cryptography.ProtectedData]::Protect($plain, $entropy, [Security.Cryptography.DataProtectionScope]::CurrentUser)
        [IO.File]::WriteAllBytes($temporaryPath, $protected)
        Move-Item -LiteralPath $temporaryPath -Destination $path -Force
    }
    finally {
        foreach ($bytes in @($plain, $protected, $entropy)) { if ($null -ne $bytes) { [Array]::Clear($bytes, 0, $bytes.Length) } }
        if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue }
    }
}
