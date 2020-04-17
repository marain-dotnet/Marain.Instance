$ErrorActionPreference = 'Stop'
$VerbosePreference = 'Continue'

$here = Split-Path -Parent $PSCommandPath
$marainDeploymentScript = Join-Path $here '../Solutions/Marain.Instance.Deployment/Deploy-MarainInstanceInfrastructure.ps1'
Import-Module -Force $here/../_deployContainer/endjin.deployment

# load the interim config repo
. $here/config.ps1
Write-Host ($marainDeploymentConfig | Format-Table | Out-String)

. $marainDeploymentScript @marainDeploymentConfig
