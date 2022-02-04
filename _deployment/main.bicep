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

param location string = deployment().location
param includeAcr bool = false
param acrName string = '${appEnvironmentName}acr'
param acrSku string = 'Standard'
param tenantId string
param resourceTags object = {}


targetScope = 'subscription'


resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupName
  location: location
  tags: resourceTags
}

// ContainerApp hosting environment
module app_environment 'br:endjintestacr.azurecr.io/bicep/modules/container_app_environment:0.1.0-beta.01' = if (useContainerApps) {
  scope: resourceGroup(appEnvironmentSubscriptionId, appEnvironmentResourceGroupName)
  name: 'containerAppEnv'
  params: {
    name: appEnvironmentName
    appInsightsName: '${appEnvironmentName}ai'
    logAnalyticsName: '${appEnvironmentName}la'
    location: location
    createContainerRegistry: includeAcr
    containerRegistryName: acrName
    containerRegistrySku: acrSku
    useExisting: useExistingAppEnvironment
    resourceTags: resourceTags
  }
}

// Ensure an AppInsights workspace is provisioned when not hosting in Azure ContainerApps
module non_app_environment_ai 'br:endjintestacr.azurecr.io/bicep/modules/app_insights:0.1.0-beta.01' = if (!useContainerApps) {
  scope: rg
  name: 'appInsights'
  params:{
    name: '${appEnvironmentName}ai'
    location: location
  }
}

module key_vault './modules/key_vault_with_groups.bicep' = {
  scope: rg
  name: 'keyVault'
  params: {
    name: keyVaultName
    secretsReadersGroupObjectId: keyVaultSecretsReadersGroupObjectId
    secretsContributorsGroupObjectId: keyVaultSecretsContributorsGroupObjectId
    tenantId: tenantId
    resourceTags: resourceTags
  }
}

module app_config './modules/app_config_with_rg.bicep' = if (!useExistingAppConfigurationStore) {
  name: 'appConfigDeploy'
  params: {
    name: appConfigurationStoreName
    resourceGroupName: appConfigurationStoreResourceGroupName
    location: location
    useExisting: useExistingAppConfigurationStore
  }
}

module kubeenv_app_config_key 'br:endjintestacr.azurecr.io/bicep/modules/set_app_configuration_keys:0.1.0-beta.01' = if (useContainerApps) {
  scope: resourceGroup(appConfigurationStoreSubscription, appConfigurationStoreResourceGroupName)
  name: 'kubeenvAppConfigKeyDeploy'
  params: {
    appConfigStoreName: app_config.outputs.name
    label: appConfigurationLabel
    entries: [
      {
        name: 'ContainerAppEnvironmentResourceId'
        value: app_environment.outputs.id
      }
    ]
  }
}

module aikey_secret 'br:endjintestacr.azurecr.io/bicep/modules/key_vault_secret:0.1.0-beta.01' = {
  name: 'aiKeySecretDeploy'
  scope: rg
  params: {
    keyVaultName: keyVaultName
    secretName: 'AppInsightsInstrumentationKey'
    contentValue: useContainerApps ? app_environment.outputs.appinsights_instrumentation_key : non_app_environment_ai.outputs.instrumentationKey
    contentType: 'text/plain'
  }
}

output containerAppEnvironmentId string = app_environment.outputs.id
output keyVaultId string = key_vault.outputs.id
output appConfigStoreId string = app_config.outputs.id
