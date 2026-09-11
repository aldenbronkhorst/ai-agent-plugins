#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Account,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string[]]$Scopes,
    [string]$TenantId = 'common',
    [string]$Environment = 'Global',
    [switch]$ForceDeviceCode
)

. (Join-Path $PSScriptRoot 'graph_auth.ps1')
Connect-GraphAccount @PSBoundParameters
