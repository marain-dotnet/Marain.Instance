[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory = $true)]
    [string] $SubscriptionId,
    
    [Parameter(Mandatory = $true)]
    [string] $AadTenantId,

    [Parameter(Mandatory = $true)]
    [string] $StackName,

    [Parameter(Mandatory = $true)]
    [string] $ServiceInstance,

    [Parameter(Mandatory = $true)]
    [string] $Environment,

    [Parameter()]
    [string] $ConfigPath
)

$ErrorActionPreference = 'Stop'
$InformationPreference = $InformationAction ? $InformationAction : 'Continue'

$here = Split-Path -Parent $PSCommandPath

if (!$ConfigPath) { $ConfigPath = Join-Path $here "config" }

# Install/Import Corvus.Deployment
$minCorvusVersion = "0.3.18"
Install-Module Corvus.Deployment -MinimumVersion $minCorvusVersion -Scope CurrentUser -Force -Repository PSGallery
Import-Module Corvus.Deployment -MinimumVersion $minCorvusVersion -Force
Connect-CorvusAzure -SubscriptionId $SubscriptionId -AadTenantId $AadTenantId

function toResourceName($configValue, $serviceName, $resourceShortCode, $uniqueSuffix) {
    return [string]::IsNullOrEmpty($configValue) ? ("{0}{1}{2}" -f $serviceName, $resourceShortCode, $uniqueSuffix): $configValue
}

#region Placeholder Configuration
$deploymentConfig = Read-CorvusDeploymentConfig -ConfigPath $ConfigPath  `
                                                -EnvironmentConfigName $Environment `
                                                -Verbose

$ServiceName = $deploymentConfig.ServiceName
$uniqueSuffix = Get-CorvusUniqueSuffix -SubscriptionId $SubscriptionId `
                                       -StackName $StackName `
                                       -ServiceInstance $ServiceInstance `
                                       -Environment $Environment

$instanceResourceGroupName = toResourceName $deploymentConfig.InstanceResourceGroupName $serviceName "rg" $uniqueSuffix
$keyVaultName = toResourceName $deploymentConfig.KeyVaultName $serviceName "kv" $uniqueSuffix

$appEnvironmentName = toResourceName $deploymentConfig.AppEnvironmentName $serviceName "kubeenv" $uniqueSuffix
$appEnvironmentResourceGroupName = [string]::IsNullOrEmpty($deploymentConfig.AppEnvironmentResourceGroupName) ? $instanceResourceGroupName : $deploymentConfig.AppEnvironmentResourceGroupName
$appEnvironmentSubscriptionId = [string]::IsNullOrEmpty($deploymentConfig.AppEnvironmentSubscriptionId) ? (Get-AzContext).Subscription.Id : $deploymentConfig.AppEnvironmentSubscriptionId

$appConfigStoreName = toResourceName $deploymentConfig.AppConfigurationStoreName $serviceName "cfg" $uniqueSuffix
$appConfigStoreResourceGroupName = [string]::IsNullOrEmpty($deploymentConfig.AppConfigurationStoreResourceGroupName) ? $instanceResourceGroupName : $deploymentConfig.AppConfigurationStoreResourceGroupName
$appConfigurationLabel = "$Environment-$StackName"
# $acrName = toResourceName [string]::IsNullOrEmpty($deploymentConfig.AcrName) ? "$($appEnvironmentName)acr" : $deploymentConfig.AcrName
# $acrResourceGroupName = [string]::IsNullOrEmpty($deploymentConfig.AcrResourceGroupName) ? $appEnvironmentResourceGroupName : $deploymentConfig.AcrResourceGroupName
# $acrSubscriptionId = [string]::IsNullOrEmpty($deploymentConfig.AcrSubscriptionId) ? (Get-AzContext).Subscription.Id : $deploymentConfig.AcrSubscriptionId


# Tags
$defaultTags = @{
    serviceName = $ServiceName
    serviceInstance = $ServiceInstance
    stackName = $StackName
    environment = $Environment
}
#endregion

# ARM template parameters
$armDeployment = @{
    TemplatePath = Join-Path -Resolve $here "main.bicep"
    Location = $deploymentConfig.AzureLocation
    Scope = "Subscription"
    TemplateParameters = @{
        resourceGroupName = $instanceResourceGroupName
        keyVaultName = $keyVaultName

        useExistingAppConfigurationStore = $deploymentConfig.UseExistingAppConfigurationStore
        appConfigurationStoreName = $appConfigStoreName
        appConfigurationStoreResourceGroupName = $appConfigStoreResourceGroupName
        appConfigurationLabel = $appConfigurationLabel

        useContainerApps = $deploymentConfig.UseContainerApps
        useExistingAppEnvironment = $deploymentConfig.UseExistingAppEnvironment
        appEnvironmentName = $appEnvironmentName
        appEnvironmentResourceGroupName = $appEnvironmentResourceGroupName
        appEnvironmentSubscriptionId = $appEnvironmentSubscriptionId
        
        includeAcr = !$deploymentConfig.UseNonAzureContainerRegistry -and !$deploymentConfig.UseExistingAcr
        tenantId = $AadTenantId
        resourceTags = $defaultTags
    }
}

Invoke-CorvusArmTemplateDeployment `
    -BicepVersion "0.4.1124" `
    -DeploymentScope $armDeployment.Scope `
    -Location $armDeployment.Location `
    -ArmTemplatePath $armDeployment.TemplatePath `
    -TemplateParameters $armDeployment.TemplateParameters `
    -NoArtifacts `
    -MaxRetries 1 `
    -Verbose `
    -WhatIf:$WhatIfPreference
