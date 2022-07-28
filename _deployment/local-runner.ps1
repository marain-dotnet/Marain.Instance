[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory = $true)]
    [string] $Environment
)
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $PSCommandPath

$ctx = Get-AzContext
$ctx | fl | Out-String | Write-Host
Read-Host "Correct Subscription? (CTRL-C to abort)"

Write-Host "Deploying Marain.Instance..."
./deploy.ps1 -SubscriptionId $ctx.Subscription.Id `
                      -AadTenantId $ctx.Tenant.Id `
                      -Environment $Environment `
                      -ConfigPath "$here/config" `
                      -WhatIf:$WhatIfPreference