[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Account,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string[]]$Scopes,

    [string]$TenantId = "common",
    [string]$Environment = "Global"
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

$resolvedScopes = @("User.Read") + @($Scopes) |
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
Add-Type -Path (Join-Path $module.ModuleBase "Dependencies/Core/Azure.Core.dll")
Add-Type -Path (Join-Path $module.ModuleBase "Dependencies/Azure.Identity.dll")

$graphEnvironment = Get-MgEnvironment -Name $Environment | Select-Object -First 1
if (-not $graphEnvironment) {
    throw "Microsoft Graph environment '$Environment' is not configured."
}

function Get-StateDirectory {
    if ($env:XDG_STATE_HOME) {
        return Join-Path $env:XDG_STATE_HOME "ai-agent-plugins/microsoft-graph"
    }

    $localData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if ($localData) {
        return Join-Path $localData "AI Agent Plugins/Microsoft Graph"
    }

    return Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)) ".ai-agent-plugins/microsoft-graph"
}

function Get-AccountKey {
    $keyText = "$($accountHint.ToLowerInvariant())`n$($tenant.ToLowerInvariant())`n$($Environment.ToLowerInvariant())"
    $keyBytes = [Text.Encoding]::UTF8.GetBytes($keyText)
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($keyBytes)).ToLowerInvariant()
}

$stateDirectory = Get-StateDirectory
$recordPath = Join-Path $stateDirectory "$(Get-AccountKey).authrecord.json"
$null = New-Item -ItemType Directory -Path $stateDirectory -Force

$cacheOptions = [Azure.Identity.TokenCachePersistenceOptions]::new()
$cacheOptions.Name = "ai-agent-plugins.microsoft-graph"

$deviceCodeCallback = [System.Func[Azure.Identity.DeviceCodeInfo, System.Threading.CancellationToken, System.Threading.Tasks.Task]] {
    param($code, $cancellationToken)
    [Console]::WriteLine($code.Message)
    return [System.Threading.Tasks.Task]::CompletedTask
}

$credentialOptions = [Azure.Identity.DeviceCodeCredentialOptions]::new()
$credentialOptions.ClientId = $graphPowerShellClientId
$credentialOptions.TenantId = $tenant
$credentialOptions.AuthorityHost = [Uri]$graphEnvironment.AzureADEndpoint
$credentialOptions.TokenCachePersistenceOptions = $cacheOptions
$credentialOptions.DeviceCodeCallback = $deviceCodeCallback

if (Test-Path -LiteralPath $recordPath) {
    $recordStream = [IO.File]::OpenRead($recordPath)
    try {
        $credentialOptions.AuthenticationRecord = [Azure.Identity.AuthenticationRecord]::DeserializeAsync($recordStream).GetAwaiter().GetResult()
    }
    finally {
        $recordStream.Dispose()
    }
}

$credential = [Azure.Identity.DeviceCodeCredential]::new($credentialOptions)
$tokenRequest = [Azure.Core.TokenRequestContext]::new([string[]]$resolvedScopes, $null, $null, $null, $true)
$cancellation = [Threading.CancellationTokenSource]::new([TimeSpan]::FromMinutes(15))

try {
    if (-not $credentialOptions.AuthenticationRecord) {
        $record = $credential.AuthenticateAsync($tokenRequest, $cancellation.Token).GetAwaiter().GetResult()

        if (
            $record.Username -and
            -not [string]::Equals($record.Username, $accountHint, [StringComparison]::OrdinalIgnoreCase)
        ) {
            throw "Microsoft authenticated '$($record.Username)' instead of '$accountHint'. Retry and choose the intended account on the device-login page."
        }

        $temporaryRecordPath = "$recordPath.$([Guid]::NewGuid().ToString('N')).tmp"
        $recordStream = [IO.File]::Open($temporaryRecordPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try {
            $record.SerializeAsync($recordStream).GetAwaiter().GetResult()
        }
        finally {
            $recordStream.Dispose()
        }
        Move-Item -LiteralPath $temporaryRecordPath -Destination $recordPath -Force

        if (-not $IsWindows) {
            try {
                [IO.File]::SetUnixFileMode(
                    $recordPath,
                    [IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite
                )
            }
            catch {
                # The record selects an account; tokens remain in the OS-protected cache.
            }
        }
    }

    # Use the same CAE-enabled request for sign-in and token acquisition. This
    # avoids the Graph SDK's current normal-token/CAE-token double prompt.
    $accessToken = $credential.GetTokenAsync($tokenRequest, $cancellation.Token).GetAwaiter().GetResult()
    $secureToken = ConvertTo-SecureString $accessToken.Token -AsPlainText -Force
    try {
        Connect-MgGraph -AccessToken $secureToken -Environment $Environment -NoWelcome
    }
    finally {
        $secureToken.Dispose()
    }
}
finally {
    $cancellation.Dispose()
}
