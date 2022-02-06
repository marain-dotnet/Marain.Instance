param name string
param location string
param createContainerRegistry bool
param containerRegistryName string
param containerRegistrySku string
param useExisting bool
param appConfigurationStoreName string
param appConfigurationStoreResourceGroupName string
param appConfigurationStoreSubscription string
param appConfigurationLabel string
param keyVaultName string
param resourceTags object = {}


// ContainerApp hosting environment
module app_environment 'br:endjintestacr.azurecr.io/bicep/modules/container_app_environment:0.1.0-beta.01' = {
  name: 'containerAppEnv'
  params: {
    name: name
    appInsightsName: '${name}ai'
    logAnalyticsName: '${name}la'
    location: location
    createContainerRegistry: createContainerRegistry
    containerRegistryName: containerRegistryName
    containerRegistrySku: containerRegistrySku
    useExisting: useExisting
    resourceTags: resourceTags
  }
}

module kubeenv_app_config_key 'br:endjintestacr.azurecr.io/bicep/modules/set_app_configuration_keys:0.1.0-beta.01' = {
  scope: resourceGroup(appConfigurationStoreSubscription, appConfigurationStoreResourceGroupName)
  name: 'kubeenvAppConfigKeyDeploy'
  params: {
    appConfigStoreName: appConfigurationStoreName
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
  params: {
    keyVaultName: keyVaultName
    secretName: 'AppInsightsInstrumentationKey'
    contentValue: app_environment.outputs.appinsights_instrumentation_key
    contentType: 'text/plain'
  }
}

output id string = app_environment.outputs.id
output name string = app_environment.name
output acrId string = createContainerRegistry ? app_environment.outputs.acrId : ''
output acrUsername string = createContainerRegistry ? app_environment.outputs.acrUsername : ''
output acrLoginServer string = createContainerRegistry ? app_environment.outputs.acrLoginServer : ''

output appEnvironmentResource object = app_environment.outputs.appEnvironmentResource

