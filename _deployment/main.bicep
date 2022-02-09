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
module app_environment 'br:endjintestacr.azurecr.io/bicep/modules/container_app_environment:0.1.0-beta.02' = if (useContainerApps) {
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
module non_app_environment_ai 'br:endjintestacr.azurecr.io/bicep/modules/app_insights_with_config_publish:0.1.0-beta.02' = if (!useContainerApps) {
  scope: rg
  name: 'appInsights'
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

module key_vault 'br:endjintestacr.azurecr.io/bicep/modules/key_vault_with_secrets_access_via_groups:0.1.0-beta.02' = {
  scope: rg
  name: 'keyVault'
  params: {
    name: keyVaultName
    enableDiagnostics: true
    secretsReadersGroupObjectId: keyVaultSecretsReadersGroupObjectId
    secretsContributorsGroupObjectId: keyVaultSecretsContributorsGroupObjectId
    enabledForTemplateDeployment: true
    tenantId: tenantId
    resourceTags: resourceTags
  }
}

module app_config 'br:endjintestacr.azurecr.io/bicep/modules/app_configuration_with_rg:0.1.0-beta.02' = if (!useExistingAppConfigurationStore) {
  // Since this is subscription-scoped deployment give it a name that will make it obviously associated to this deployment
  name: '${deployment().name}-appConfig'
  params: {
    name: appConfigurationStoreName
    resourceGroupName: appConfigurationStoreResourceGroupName
    location: location
    useExisting: useExistingAppConfigurationStore
    resourceTags: resourceTags
  }
}


output containerAppEnvironmentId string = useContainerApps ? app_environment.outputs.id : ''
output keyVaultId string = key_vault.outputs.id
output appConfigStoreId string = app_config.outputs.id
