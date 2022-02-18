param resourceGroupName string

param useContainerApps bool
param useExistingAppEnvironment bool
param appEnvironmentName string
param appEnvironmentResourceGroupName string = resourceGroupName
param appEnvironmentSubscriptionId string = subscription().subscriptionId

param keyVaultName string
param keyVaultSecretsReadersGroupObjectId string = ''
param keyVaultSecretsContributorsGroupObjectId string = ''

param useExistingAppConfigurationStore bool = false
param appConfigurationStoreName string
param appConfigurationStoreResourceGroupName string = resourceGroupName
param appConfigurationStoreSubscription string = subscription().subscriptionId
param appConfigurationLabel string

param useExistingAppInsightsWorkspace bool = false
param appInsightsWorkspaceName string = '${appEnvironmentName}ai'
param appInsightsWorkspaceResourceGroupName string = resourceGroupName
param appInsightsWorkspaceSubscription string = subscription().subscriptionId

param location string = deployment().location
param includeAcr bool = false
param acrName string = '${appEnvironmentName}acr'
param acrSku string = 'Standard'
param tenantId string
param resourceTags object = {}


targetScope = 'subscription'


module rg 'br:endjintestacr.azurecr.io/bicep/modules/resource_group:0.1.0-initial-modules-and-build.33' = {
  name: 'marainRg'
  params: {
    location: location
    name: resourceGroupName
    resourceTags: resourceTags
  }
}

module app_env_rg 'br:endjintestacr.azurecr.io/bicep/modules/resource_group:0.1.0-initial-modules-and-build.33' = {
  name: 'appEnvRg'
  params: {
    location: location
    name: appEnvironmentResourceGroupName
    useExisting: useExistingAppEnvironment || appEnvironmentResourceGroupName == rg.outputs.name
    resourceTags: resourceTags
  }
}

module app_config_rg 'br:endjintestacr.azurecr.io/bicep/modules/resource_group:0.1.0-initial-modules-and-build.33' = {
  name: 'appConfigRg'
  params: {
    location: location
    name: resourceGroupName
    useExisting: useExistingAppConfigurationStore || appConfigurationStoreResourceGroupName == rg.outputs.name
    resourceTags: resourceTags
  }
}

module app_insights_rg 'br:endjintestacr.azurecr.io/bicep/modules/resource_group:0.1.0-initial-modules-and-build.33' = if (!useContainerApps) {
  name: 'appInsightsRg'
  params: {
    location: location
    name: appInsightsWorkspaceResourceGroupName
    useExisting: useExistingAppInsightsWorkspace || appInsightsWorkspaceResourceGroupName == rg.outputs.name
    resourceTags: resourceTags
  }
}


// ContainerApp hosting environment
module app_environment 'br:endjintestacr.azurecr.io/bicep/modules/container_app_environment_with_config_publish:0.1.0-initial-modules-and-build.33' = if (useContainerApps) {
  scope: resourceGroup(appEnvironmentSubscriptionId, appEnvironmentResourceGroupName)
  name: 'containerAppEnv'
  params: {
    name: appEnvironmentName
    location: location
    createContainerRegistry: includeAcr
    containerRegistryName: acrName
    containerRegistrySku: acrSku
    useExisting: useExistingAppEnvironment
    appConfigurationStoreName: app_config.outputs.name
    appConfigurationStoreResourceGroupName: appConfigurationStoreResourceGroupName
    appConfigurationStoreSubscription: appConfigurationStoreSubscription
    appConfigurationLabel: appConfigurationLabel
    keyVaultName: key_vault.outputs.name
    resourceTags: resourceTags
  }
  dependsOn: [
    app_env_rg
  ]
}

// Ensure an AppInsights workspace is provisioned when not hosting in Azure ContainerApps
module non_app_environment_ai 'br:endjintestacr.azurecr.io/bicep/modules/app_insights_with_config_publish:0.1.0-initial-modules-and-build.33' = if (!useContainerApps) {
  name: 'appInsightsStandalone'
  scope: resourceGroup(appInsightsWorkspaceSubscription, appInsightsWorkspaceResourceGroupName)
  params:{
    name: appInsightsWorkspaceName
    useExisting: useExistingAppInsightsWorkspace
    resourceGroupName: appInsightsWorkspaceResourceGroupName
    location: location
    keyVaultName: key_vault.outputs.name
    keyVaultResourceGroupName: rg.outputs.name
    keyVaultSubscriptionId: subscription().subscriptionId
    resourceTags: resourceTags
  }
  dependsOn: [
    app_insights_rg
  ]
}

module key_vault 'br:endjintestacr.azurecr.io/bicep/modules/key_vault_with_secrets_access_via_groups:0.1.0-initial-modules-and-build.33' = {
  scope: resourceGroup(resourceGroupName)
  name: 'keyVaultWithGroupsAccess'
  params: {
    name: keyVaultName
    enableDiagnostics: true
    secretsReadersGroupObjectId: keyVaultSecretsReadersGroupObjectId
    secretsContributorsGroupObjectId: keyVaultSecretsContributorsGroupObjectId
    enabledForTemplateDeployment: true
    tenantId: tenantId
    resourceTags: resourceTags
  }
  dependsOn: [
    rg
  ]
}

module app_config 'br:endjintestacr.azurecr.io/bicep/modules/app_configuration:0.1.0-initial-modules-and-build.33' = {
  name: 'appConfiguration'
  scope: resourceGroup(appConfigurationStoreResourceGroupName)
  params: {
    name: appConfigurationStoreName
    location: location
    useExisting: useExistingAppConfigurationStore
    resourceTags: resourceTags
  }
  dependsOn: [
    app_config_rg
  ]
}


output containerAppEnvironmentId string = useContainerApps ? app_environment.outputs.id : ''
output keyVaultId string = key_vault.outputs.id
output appConfigStoreId string = app_config.outputs.id
