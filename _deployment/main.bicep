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
module app_environment './modules/app_environment_with_config_publish.bicep' = if (useContainerApps) {
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
}

// Ensure an AppInsights workspace is provisioned when not hosting in Azure ContainerApps
module non_app_environment_ai './modules/app_insights_with_config_publish.bicep' = if (!useContainerApps) {
  name: 'nonAppEnvAppInsights'
  params:{
    name: '${appEnvironmentName}ai'
    resourceGroupName: resourceGroupName
    subscriptionId: subscription().subscriptionId
    location: location
    keyVaultName: key_vault.outputs.name
    keyVaultResourceGroupName: resourceGroupName
    keyVaultSubscriptionId: subscription().subscriptionId
    // TODO: use existing pattern!
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


output containerAppEnvironmentId string = useContainerApps ? app_environment.outputs.id : ''
output keyVaultId string = key_vault.outputs.id
output appConfigStoreId string = app_config.outputs.id
