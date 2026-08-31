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
    [string]$Environment = "Global",
    [string]$BodyJson,
    [string]$HeadersJson,
    [string]$OutputFilePath,
    [switch]$ForceSignIn
)

$ErrorActionPreference = "Stop"

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

function Find-NodeRuntime {
    if ($env:MICROSOFT_GRAPH_PLUGIN_NODE_PATH) {
        return $env:MICROSOFT_GRAPH_PLUGIN_NODE_PATH
    }

    $command = Get-Command node -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $nativeRuntimeRoot = Split-Path $PSHOME -Parent
    $candidates = if ($IsWindows) {
        @(
            (Join-Path $nativeRuntimeRoot "node/node.exe"),
            (Join-Path ([Environment]::GetFolderPath("ProgramFiles")) "nodejs/node.exe")
        )
    }
    else {
        @(
            (Join-Path $nativeRuntimeRoot "node/bin/node"),
            (Join-Path $nativeRuntimeRoot "node/node")
        )
    }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }
    throw "Node.js 20 or later is required for Microsoft authentication. Install a current Node.js runtime for the user and retry."
}

function Find-PackageManager([string]$NodePath) {
    if ($env:MICROSOFT_GRAPH_PLUGIN_NPM_PATH) {
        return @{ Name = "npm"; Type = "Command"; Path = $env:MICROSOFT_GRAPH_PLUGIN_NPM_PATH }
    }

    $command = Get-Command npm -ErrorAction SilentlyContinue
    if ($command) {
        return @{ Name = "npm"; Type = "Command"; Path = $command.Source }
    }

    $nodeDirectory = Split-Path $NodePath -Parent
    $commandCandidates = if ($IsWindows) {
        @((Join-Path $nodeDirectory "npm.cmd"))
    }
    else {
        @((Join-Path $nodeDirectory "npm"))
    }
    foreach ($candidate in $commandCandidates) {
        if (Test-Path -LiteralPath $candidate) {
            return @{ Name = "npm"; Type = "Command"; Path = $candidate }
        }
    }

    $cliCandidates = @(
        (Join-Path $nodeDirectory "node_modules/npm/bin/npm-cli.js"),
        (Join-Path (Split-Path $nodeDirectory -Parent) "lib/node_modules/npm/bin/npm-cli.js")
    )
    foreach ($candidate in $cliCandidates) {
        if (Test-Path -LiteralPath $candidate) {
            return @{ Name = "npm"; Type = "NodeScript"; Path = $candidate }
        }
    }

    if ($env:MICROSOFT_GRAPH_PLUGIN_PNPM_PATH) {
        return @{ Name = "pnpm"; Type = "Command"; Path = $env:MICROSOFT_GRAPH_PLUGIN_PNPM_PATH }
    }
    $command = Get-Command pnpm -ErrorAction SilentlyContinue
    if ($command) {
        return @{ Name = "pnpm"; Type = "Command"; Path = $command.Source }
    }

    $nodeRoot = Split-Path $nodeDirectory -Parent
    $dependencyRoot = Split-Path $nodeRoot -Parent
    $pnpmCommandCandidates = if ($IsWindows) {
        @((Join-Path $dependencyRoot "bin/fallback/pnpm.cmd"))
    }
    else {
        @((Join-Path $dependencyRoot "bin/fallback/pnpm"))
    }
    foreach ($candidate in $pnpmCommandCandidates) {
        if (Test-Path -LiteralPath $candidate) {
            return @{ Name = "pnpm"; Type = "Command"; Path = $candidate }
        }
    }

    $pnpmCliCandidates = @(
        (Join-Path $nodeRoot "node_modules/pnpm/bin/pnpm.mjs"),
        (Join-Path $dependencyRoot "node/node_modules/pnpm/bin/pnpm.mjs")
    )
    foreach ($candidate in $pnpmCliCandidates) {
        if (Test-Path -LiteralPath $candidate) {
            return @{ Name = "pnpm"; Type = "NodeScript"; Path = $candidate }
        }
    }
    throw "npm or pnpm is required once to install Microsoft's pinned MSAL runtime. Install one for the current user and retry."
}

function Install-KeytarPrebuild([string]$NodePath, [string]$RuntimeDirectory) {
    $keytarDirectory = Join-Path $RuntimeDirectory "node_modules/keytar"
    $keytarBinary = Join-Path $keytarDirectory "build/Release/keytar.node"
    if (Test-Path -LiteralPath $keytarBinary) {
        return
    }

    $keytarPackage = Join-Path $keytarDirectory "package.json"
    $resolveScript = 'const {realpathSync}=require("node:fs"); const {createRequire}=require("node:module"); process.stdout.write(createRequire(realpathSync(process.argv[1])).resolve("prebuild-install/bin.js"));'
    $prebuildCli = (& $NodePath -e $resolveScript $keytarPackage).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $prebuildCli -or -not (Test-Path -LiteralPath $prebuildCli)) {
        throw "Microsoft's secure token-cache component is incomplete: prebuild-install is missing."
    }

    Push-Location $keytarDirectory
    try {
        & $NodePath $prebuildCli
        if ($LASTEXITCODE -ne 0) {
            throw "Microsoft's secure token-cache component installation failed with exit code $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location
    }
    if (-not (Test-Path -LiteralPath $keytarBinary)) {
        throw "Microsoft's secure token-cache component did not install its native binary."
    }
}

function Install-MsalRuntime([string]$NodePath, [string]$RuntimeDirectory) {
    $packageSource = Join-Path $PSScriptRoot "package.json"
    $lockSource = Join-Path $PSScriptRoot "package-lock.json"
    $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $lockSource).Hash.ToLowerInvariant()
    $markerPath = Join-Path $RuntimeDirectory ".package-lock.sha256"
    $installedHash = if (Test-Path -LiteralPath $markerPath) {
        (Get-Content -LiteralPath $markerPath -Raw).Trim()
    }
    else {
        ""
    }

    $msalModule = Join-Path $RuntimeDirectory "node_modules/@azure/msal-node/package.json"
    $extensionModule = Join-Path $RuntimeDirectory "node_modules/@azure/msal-node-extensions/package.json"
    $keytarModule = Join-Path $RuntimeDirectory "node_modules/keytar/package.json"
    if ($installedHash -eq $sourceHash -and (Test-Path $msalModule) -and (Test-Path $extensionModule) -and (Test-Path $keytarModule)) {
        Install-KeytarPrebuild $NodePath $RuntimeDirectory
        return
    }

    $null = New-Item -ItemType Directory -Path $RuntimeDirectory -Force
    Copy-Item -LiteralPath $packageSource -Destination (Join-Path $RuntimeDirectory "package.json") -Force
    Copy-Item -LiteralPath $lockSource -Destination (Join-Path $RuntimeDirectory "package-lock.json") -Force

    $packageManager = Find-PackageManager $NodePath
    if ($packageManager.Name -eq "npm") {
        $packageArguments = @("ci", "--omit=dev", "--no-audit", "--no-fund", "--prefix", $RuntimeDirectory)
    }
    else {
        $packageArguments = @("install", "--prod", "--ignore-workspace", "--ignore-scripts", "--dir", $RuntimeDirectory)
    }
    if ($packageManager.Type -eq "NodeScript") {
        & $NodePath $packageManager.Path @packageArguments
    }
    else {
        & $packageManager.Path @packageArguments
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Microsoft's MSAL runtime installation with $($packageManager.Name) failed with exit code $LASTEXITCODE."
    }
    Install-KeytarPrebuild $NodePath $RuntimeDirectory
    Set-Content -LiteralPath $markerPath -Value $sourceHash -NoNewline
}

$stateDirectory = Get-PluginStateDirectory
$runtimeDirectory = Join-Path $stateDirectory "msal-node-v1"
$nodePath = Find-NodeRuntime
$nodeVersionText = (& $nodePath --version).TrimStart("v")
if ([version]$nodeVersionText -lt [version]"20.0.0") {
    throw "Node.js 20 or later is required; found $nodeVersionText."
}

$originalPath = $env:PATH
$nodeDirectory = Split-Path $nodePath -Parent
$env:PATH = "$nodeDirectory$([IO.Path]::PathSeparator)$originalPath"
try {
    Install-MsalRuntime $nodePath $runtimeDirectory

    $nodeArguments = @(
        (Join-Path $PSScriptRoot "graph_request.mjs"),
        "--runtime-dir", $runtimeDirectory,
        "--state-dir", $stateDirectory,
        "--account", $Account,
        "--method", $Method,
        "--uri", $Uri,
        "--scopes-json", (ConvertTo-Json -InputObject @($Scopes) -Compress),
        "--environment", $Environment
    )
    if ($TenantId) { $nodeArguments += @("--tenant-id", $TenantId) }
    if ($BodyJson) { $nodeArguments += @("--body-json", $BodyJson) }
    if ($HeadersJson) { $nodeArguments += @("--headers-json", $HeadersJson) }
    if ($OutputFilePath) { $nodeArguments += @("--output-file-path", $OutputFilePath) }
    if ($ForceSignIn) { $nodeArguments += "--force-sign-in" }

    & $nodePath @nodeArguments
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}
finally {
    $env:PATH = $originalPath
}
