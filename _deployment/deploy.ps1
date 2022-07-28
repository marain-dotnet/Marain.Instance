[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory = $true)]
    [string] $SubscriptionId,
    
    [Parameter(Mandatory = $true)]
    [string] $AadTenantId,

    [Parameter(Mandatory = $true)]
    [string] $Environment,

    [Parameter()]
    [string] $ConfigPath,

    [Parameter()]
    [switch] $Cleardown
)

$ErrorActionPreference = 'Stop'
$InformationPreference = $InformationAction ? $InformationAction : 'Continue'

$here = Split-Path -Parent $PSCommandPath

if (!$ConfigPath) { $ConfigPath = Join-Path $here "config" }

# Install/Import an appropriate version of Corvus.Deployment
$minCorvusVersion = "0.4.0"
if (!(Get-Module -ListAvailable Corvus.Deployment | Select-Object Version | Where-Object { $_.Version -ge ([version]$minCorvusVersion) })) {
    Install-Module Corvus.Deployment -MinimumVersion $minCorvusVersion -Scope CurrentUser -Force -Repository PSGallery
}
Import-Module Corvus.Deployment -MinimumVersion $minCorvusVersion -Force
Connect-CorvusAzure -SubscriptionId $SubscriptionId -AadTenantId $AadTenantId

#region Configuration
$deploymentConfig = Read-CorvusDeploymentConfig -ConfigPath $ConfigPath  `
                                                -EnvironmentConfigName $Environment `
                                                -Verbose

# Remove any config settings with no value, this will allow any defaults
# defined in the ARM template to be used
$configKeysToIgnore = @("RequiredConfiguration")
$parametersWithValues = @{}
$deploymentConfig.Keys |
    Where-Object {
        !([string]::IsNullOrEmpty($deploymentConfig[$_])) -and $_ -notin $configKeysToIgnore
    } |
    ForEach-Object {
        $parametersWithValues += @{ $_ = $deploymentConfig[$_]
    }
}
$parametersWithValues | Format-Table | out-string | Write-Host

Read-Host "Continue?"
# ARM template parameters
$armDeploymentArgs = @{
    ArmTemplatePath = Join-Path -Resolve $here "main.bicep"
    Location = $deploymentConfig.azureLocation
    DeploymentScope = "Subscription"
    TemplateParameters = $parametersWithValues
}


if ($Cleardown) {
    Write-Information "Running Cleardown..."
    Remove-AzResourceGroup -Name $deploymentConfig.instanceResourceGroupName -Force -Verbose
    Remove-AzKeyVault -VaultName $deploymentConfig.instanceKeyVaultName `
                      -Location $deploymentConfig.azureLocation `
                      -InRemovedState `
                      -Force `
                      -Verbose
}
else {
    Invoke-CorvusArmTemplateDeployment `
        -BicepVersion "0.8.9" `
        @armDeploymentArgs `
        -NoArtifacts `
        -MaxRetries 1 `
        -Verbose `
        -WhatIf:$WhatIfPreference
}
