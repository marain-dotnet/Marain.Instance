$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $PSCommandPath

Import-Module endjin.deployment

# load the interim config repo
. $here/config.ps1
Write-Host ($marainDeploymentConfig | Format-Table | Out-String)

#
# This script expects to be run from within the container setup by the 'test.ps1' script
#
./Deploy-MarainInstanceInfrastructure.ps1 @marainDeploymentConfig
