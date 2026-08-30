[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Account,

    [Parameter(Mandatory = $true)]
    [ValidateSet("GET", "POST", "PUT", "PATCH", "DELETE")]
    [string]$Method,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Uri,

    [string[]]$Scopes = @("User.Read"),
    [string]$TenantId,
    [string]$Environment,
    [string]$BodyJson,
    [string]$HeadersJson,
    [string]$OutputFilePath,
    [switch]$ForceSignIn
)

$ErrorActionPreference = "Stop"
$compatibleModuleVersion = [version]"2.33.0"
$accountHint = $Account.Trim()
if (-not $accountHint) {
    throw "Account must contain the intended Microsoft sign-in identity."
}

function Import-CompatibleGraphAuthentication {
    $existingCommand = Get-Command Connect-MgGraph -ErrorAction SilentlyContinue
    if ($existingCommand -and $existingCommand.CommandType -eq "Function") {
        return
    }

    $loadedModule = Get-Module Microsoft.Graph.Authentication
    if ($loadedModule -and $loadedModule.Version -ne $compatibleModuleVersion) {
        Remove-Module Microsoft.Graph.Authentication -Force
    }

    $module = Get-Module Microsoft.Graph.Authentication -ListAvailable |
        Where-Object Version -EQ $compatibleModuleVersion |
        Select-Object -First 1

    if (-not $module) {
        $installPsResource = Get-Command Install-PSResource -ErrorAction SilentlyContinue
        if ($installPsResource) {
            Install-PSResource `
                -Name Microsoft.Graph.Authentication `
                -Version $compatibleModuleVersion.ToString() `
                -Scope CurrentUser `
                -TrustRepository `
                -AcceptLicense `
                -Quiet
        }
        else {
            $installModule = Get-Command Install-Module -ErrorAction SilentlyContinue
            if (-not $installModule) {
                throw "PowerShell package installation is unavailable. Install Microsoft.Graph.Authentication $compatibleModuleVersion for the current user and retry."
            }
            Install-Module `
                -Name Microsoft.Graph.Authentication `
                -RequiredVersion $compatibleModuleVersion `
                -Scope CurrentUser `
                -Repository PSGallery `
                -Force `
                -AllowClobber `
                -Confirm:$false
        }
    }

    Import-Module Microsoft.Graph.Authentication -RequiredVersion $compatibleModuleVersion -Force
}

function Get-PluginStateDirectory {
    if ($env:MICROSOFT_GRAPH_PLUGIN_STATE_DIR) {
        return $env:MICROSOFT_GRAPH_PLUGIN_STATE_DIR
    }
    if ($IsWindows) {
        return Join-Path ([Environment]::GetFolderPath("LocalApplicationData")) "AI Agent Plugins/Microsoft Graph"
    }
    if ($env:XDG_STATE_HOME) {
        return Join-Path $env:XDG_STATE_HOME "ai-agent-plugins/microsoft-graph"
    }
    return Join-Path ([Environment]::GetFolderPath("UserProfile")) ".local/state/ai-agent-plugins/microsoft-graph"
}

function Get-GraphAuthRecordPath {
    if ($env:MICROSOFT_GRAPH_PLUGIN_AUTH_RECORD_PATH) {
        return $env:MICROSOFT_GRAPH_PLUGIN_AUTH_RECORD_PATH
    }
    return Join-Path ([Environment]::GetFolderPath("UserProfile")) ".mg/mg.authrecord.json"
}

function Get-AccountRecordName {
    $tenantKey = if ($TenantId) { $TenantId.Trim().ToLowerInvariant() } else { "default" }
    $key = "$($accountHint.ToLowerInvariant())`n$tenantKey"
    $bytes = [Text.Encoding]::UTF8.GetBytes($key)
    $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
    return "account-$hash.authrecord.json"
}

function Open-StateLock([string]$LockPath) {
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    do {
        try {
            return [IO.File]::Open($LockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        }
        catch [IO.IOException] {
            if ([DateTime]::UtcNow -ge $deadline) {
                throw "Another Microsoft Graph operation is still selecting an account. Retry after it finishes."
            }
            Start-Sleep -Milliseconds 200
        }
    } while ($true)
}

Import-CompatibleGraphAuthentication

$stateDirectory = Get-PluginStateDirectory
$authRecordPath = Get-GraphAuthRecordPath
$authRecordDirectory = Split-Path -Parent $authRecordPath
$accountRecordPath = Join-Path $stateDirectory (Get-AccountRecordName)

$null = New-Item -ItemType Directory -Path $stateDirectory -Force
$null = New-Item -ItemType Directory -Path $authRecordDirectory -Force
$stateLock = Open-StateLock (Join-Path $stateDirectory "auth.lock")

$hadOriginalRecord = Test-Path -LiteralPath $authRecordPath
$originalRecord = if ($hadOriginalRecord) { [IO.File]::ReadAllBytes($authRecordPath) } else { $null }

try {
    if ($ForceSignIn -and (Test-Path -LiteralPath $accountRecordPath)) {
        Remove-Item -LiteralPath $accountRecordPath -Force
    }

    if (Test-Path -LiteralPath $accountRecordPath) {
        Copy-Item -LiteralPath $accountRecordPath -Destination $authRecordPath -Force
    }
    elseif (Test-Path -LiteralPath $authRecordPath) {
        Remove-Item -LiteralPath $authRecordPath -Force
    }

    $connectParameters = @{
        Scopes                   = $Scopes
        UseDeviceAuthentication = $true
        ContextScope             = "CurrentUser"
        NoWelcome                = $true
        ErrorAction              = "Stop"
    }
    if ($TenantId) {
        $connectParameters.TenantId = $TenantId
    }
    if ($Environment) {
        $connectParameters.Environment = $Environment
    }

    Connect-MgGraph @connectParameters | Out-Null
    $context = Get-MgContext
    if (-not $context -or -not $context.Account) {
        throw "Microsoft Graph did not return an authenticated account context."
    }
    if (-not [string]::Equals([string]$context.Account, $accountHint, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Microsoft Graph authenticated '$($context.Account)' instead of the requested account '$accountHint'. Run again and choose the requested identity on Microsoft's device-login page."
    }

    $genericTenantValues = @("common", "organizations", "consumers")
    if (
        $TenantId -and
        $genericTenantValues -notcontains $TenantId.ToLowerInvariant() -and
        $context.TenantId -and
        -not [string]::Equals([string]$context.TenantId, $TenantId, [StringComparison]::OrdinalIgnoreCase)
    ) {
        throw "Microsoft Graph authenticated tenant '$($context.TenantId)' instead of '$TenantId'."
    }

    if (-not (Test-Path -LiteralPath $authRecordPath)) {
        throw "Microsoft Graph authenticated but did not create its reusable authentication record."
    }
    $temporaryRecordPath = "$accountRecordPath.$([Guid]::NewGuid().ToString('N')).tmp"
    Copy-Item -LiteralPath $authRecordPath -Destination $temporaryRecordPath -Force
    Move-Item -LiteralPath $temporaryRecordPath -Destination $accountRecordPath -Force

    if (-not $IsWindows) {
        try {
            [IO.File]::SetUnixFileMode(
                $accountRecordPath,
                [IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite
            )
        }
        catch {
            # Authentication records contain account-selection metadata, not access or refresh tokens.
        }
    }

    $requestParameters = @{
        Method      = $Method
        Uri         = $Uri
        ErrorAction = "Stop"
    }
    if ($BodyJson) {
        $null = $BodyJson | ConvertFrom-Json -ErrorAction Stop
        $requestParameters.Body = $BodyJson
        $requestParameters.ContentType = "application/json"
    }
    if ($HeadersJson) {
        $headers = $HeadersJson | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        if ($headers -isnot [hashtable]) {
            throw "HeadersJson must be a JSON object."
        }
        $requestParameters.Headers = $headers
    }
    if ($OutputFilePath) {
        $requestParameters.OutputFilePath = $OutputFilePath
    }

    $response = Invoke-MgGraphRequest @requestParameters
    if (-not $OutputFilePath -and $null -ne $response) {
        $response | ConvertTo-Json -Depth 100
    }
}
finally {
    if ($hadOriginalRecord) {
        [IO.File]::WriteAllBytes($authRecordPath, $originalRecord)
    }
    elseif (Test-Path -LiteralPath $authRecordPath) {
        Remove-Item -LiteralPath $authRecordPath -Force
    }
    $stateLock.Dispose()
}
