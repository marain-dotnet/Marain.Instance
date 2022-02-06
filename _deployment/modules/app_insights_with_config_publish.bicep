param name string
param resourceGroupName string
param subscriptionId string
param location string
param keyVaultName string
param keyVaultResourceGroupName string
param keyVaultSubscriptionId string

targetScope = 'subscription'

module non_app_environment_ai 'br:endjintestacr.azurecr.io/bicep/modules/app_insights:0.1.0-beta.01' = {
  name: 'appInsights'
  scope: resourceGroup(subscriptionId, resourceGroupName)
  params:{
    name: name
    location: location
  }
}

module aikey_secret 'br:endjintestacr.azurecr.io/bicep/modules/key_vault_secret:0.1.0-beta.01' = {
  name: 'aiKeySecretDeploy'
  scope: resourceGroup(keyVaultSubscriptionId, keyVaultResourceGroupName)
  params: {
    keyVaultName: keyVaultName
    secretName: 'AppInsightsInstrumentationKey'
    contentValue: non_app_environment_ai.outputs.instrumentationKey
    contentType: 'text/plain'
  }
}

output id string = non_app_environment_ai.outputs.id
output instrumentationKey string = non_app_environment_ai.outputs.instrumentationKey

output appInsightsWorkspaceResource object = non_app_environment_ai.outputs.appInsightsWorkspaceResource
