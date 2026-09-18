#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Account,
    [ValidateNotNullOrEmpty()][string[]]$Scopes = @('User.Read'),
    [string]$TenantId = 'common',
    [string]$Environment = 'Global',
    [switch]$ForceDeviceCode,
    [switch]$ReuseOnly
)

. (Join-Path $PSScriptRoot 'graph_auth.ps1')
Connect-GraphAccount @PSBoundParameters
