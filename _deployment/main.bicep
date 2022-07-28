param instanceResourceGroupName string

@allowed([
  'AppService'
  'ContainerApps'
  'Functions'
  'None'
])
param hostingPlatformType string = 'None'
param useSharedMarainHosting bool = false
param useExistingHostingPlatform bool = false
param hostingPlatformName string = ''
param hostingPlatformResourceGroupName string = instanceResourceGroupName
param hostingPlatformSubscriptionId string = subscription().subscriptionId

param instanceKeyVaultName string
param keyVaultSecretsReadersGroupObjectId string = ''
param keyVaultSecretsContributorsGroupObjectId string = ''

param useExistingAppConfigurationStore bool = false
param appConfigurationStoreName string
param appConfigurationStoreResourceGroupName string = instanceResourceGroupName
param appConfigurationStoreSubscriptionId string = subscription().subscriptionId
param appConfigurationLabel string

param useExistingAppInsightsWorkspace bool = false
param appInsightsWorkspaceName string
param appInsightsWorkspaceResourceGroupName string = instanceResourceGroupName
param appInsightsWorkspaceSubscriptionId string = subscription().subscriptionId

// workaround to simplify parameter handling when we run the ARM deployment
param azureLocation string = deployment().location
param location string = azureLocation

param resourceTags object


var useContainerApps = hostingPlatformType == 'ContainerApps'
var useAppService = hostingPlatformType == 'AppService' || hostingPlatformType == 'Functions'


targetScope = 'subscription'


module rg 'br:endjin.azurecr.io/bicep/general/resource-group:1.0.1' = {
  name: 'marainRg'
  params: {
    location: location
    name: instanceResourceGroupName
    resourceTags: resourceTags
  }
}

module hosting_env_rg 'br:endjin.azurecr.io/bicep/general/resource-group:1.0.1' = {
  name: 'appEnvRg'
  params: {
    location: location
    name: hostingPlatformResourceGroupName
    useExisting: useExistingHostingPlatform || hostingPlatformResourceGroupName == rg.outputs.name
    resourceTags: resourceTags
  }
}

module app_config_rg 'br:endjin.azurecr.io/bicep/general/resource-group:1.0.1' = {
  name: 'appConfigRg'
  params: {
    location: location
    name: instanceResourceGroupName
    useExisting: useExistingAppConfigurationStore || appConfigurationStoreResourceGroupName == rg.outputs.name
    resourceTags: resourceTags
  }
}

module app_insights_rg 'br:endjin.azurecr.io/bicep/general/resource-group:1.0.1' = if (!useContainerApps) {
  name: 'appInsightsRg'
  params: {
    location: location
    name: appInsightsWorkspaceResourceGroupName
    useExisting: useExistingAppInsightsWorkspace || appInsightsWorkspaceResourceGroupName == rg.outputs.name
    resourceTags: resourceTags
  }
}

// AppService for the shared hosting environment
module app_service_plan 'br:endjin.azurecr.io/bicep/general/app-service-plan:0.1.1' = if (useSharedMarainHosting && useAppService) {
  name: 'appServicePlan'
  scope: resourceGroup(hostingPlatformSubscriptionId, hostingPlatformResourceGroupName)
  params: {
    name: hostingPlatformName
    useExisting: useExistingHostingPlatform
    skuName: 'Y1'
    skuTier: 'Dynamic'
    location: location
  }
  dependsOn: [
    hosting_env_rg
  ]
}

// Ensure an AppInsights workspace is provisioned when not hosting in ContainerApps
module standalone_ai 'br:endjin.azurecr.io/bicep/general/app-insights-with-config-publish:0.1.1' = if (!useContainerApps) {
  name: 'appInsightsStandalone'
  scope: resourceGroup(appInsightsWorkspaceSubscriptionId, appInsightsWorkspaceResourceGroupName)
  params:{
    name: appInsightsWorkspaceName
    useExisting: useExistingAppInsightsWorkspace
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

module key_vault 'br:endjin.azurecr.io/bicep/general/key-vault-with-secrets-access-via-groups:1.0.3' = {
  scope: resourceGroup(instanceResourceGroupName)
  name: 'keyVaultWithGroupsAccess'
  params: {
    name: instanceKeyVaultName
    enableDiagnostics: true
    secretsReadersGroupObjectId: keyVaultSecretsReadersGroupObjectId
    secretsContributorsGroupObjectId: keyVaultSecretsContributorsGroupObjectId
    enabledForTemplateDeployment: true
    tenantId: tenant().tenantId
    resourceTags: resourceTags
  }
  dependsOn: [
    rg
  ]
}

module app_config 'br:endjin.azurecr.io/bicep/general/app-configuration:0.1.1' = {
  name: 'appConfiguration'
  scope: resourceGroup(appConfigurationStoreSubscriptionId, appConfigurationStoreResourceGroupName)
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

module app_service_publish_config 'br:endjin.azurecr.io/bicep/general/set-app-configuration-keys:1.0.1' = if (useSharedMarainHosting && useAppService) {
  scope: resourceGroup(appConfigurationStoreSubscriptionId, appConfigurationStoreResourceGroupName)
  name: 'appServiceConfigPublish'
  params: {
    appConfigStoreName: app_config.outputs.name
    label: appConfigurationLabel
    entries: [
      {
        name: 'AppServicePlanResourceId'
        value: useSharedMarainHosting && useAppService ? app_service_plan.outputs.id : ''
      }
    ]
  }
}


output hostPlatformResourceId string = useSharedMarainHosting && useAppService ? app_service_plan.outputs.id : ''
output keyVaultId string = key_vault.outputs.id
output appConfigStoreId string = app_config.outputs.id
