$ErrorActionPreference = 'Stop'

Set-StrictMode -Version 3.0

$here = Split-Path -Parent $PSCommandPath
$marainDeploymentScript = Join-Path $here '../Solutions/Marain.Instance.Deployment/Deploy-MarainInstanceInfrastructure.ps1'

docker build -t endjin-deploy ../_deployContainer

$cmd = @(
    'docker run -it --rm'
    '-v "{0}/config.ps1:/deploy/config.ps1"' -f $here
    '-v "{0}/deploy.ps1:/deploy/deploy.ps1"' -f $here
    '-v "{0}:/deploy/{1}"' -f $marainDeploymentScript,(Split-Path -Leaf $marainDeploymentScript)
    '-w /deploy'
    'endjin-deploy'
    'pwsh -Command "cls; & ./deploy.ps1"'
)

Write-Host "cmd: $cmd"
Invoke-Expression ("& {0}" -f ($cmd -join ' '))
