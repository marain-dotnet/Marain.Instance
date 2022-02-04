param name string
param resourceGroupName string
param location string
param useExisting bool


targetScope = 'subscription'


resource app_config_rg 'Microsoft.Resources/resourceGroups@2021-04-01' = if (!useExisting) {
  name: resourceGroupName
  location: location
}

module app_config 'br:endjintestacr.azurecr.io/bicep/modules/app_configuration:0.1.0-beta.01' = {
  name: 'appConfigDeploy'
  scope: app_config_rg
  params: {
    name: name
    location: location
    useExisting: useExisting
  }
}

output id string = app_config.outputs.id
output name string = app_config.outputs.name

output appConfigStoreResource object = app_config.outputs.appConfigStoreResource
