@{
    # Settings potentially common to all Marain components
    azureLocation = "northeurope"

    hostingPlatformType = 'Functions'

    appConfigurationStoreName = "marain-config-jdtest"
    appConfigurationStoreResourceGroupName = "marain-instance-jdtest-rg"
    appConfigurationStoreSubscriptionId = ""
    appConfigurationLabel = "jdtest"

    keyVaultSecretsReadersGroupObjectId = "8e25cffb-9150-473e-8917-8f10e432e4ed"
    keyVaultSecretsContributorsGroupObjectId = "78f0285a-0004-4b92-b2f8-e1c2cbcbe4f2"

    resourceTags = @{ environment = "jdtest" }

    # Instance-specific config
    useSharedMarainHosting = $false         # when true, this deployment will provision an App Service Plan which can then be used by the other services
    useExistingHostingPlatform = $false
    hostingPlatformName = ""
    hostingPlatformResourceGroupName = ""

    instanceResourceGroupName = "marain-instance-jdtest-rg"
    instanceKeyVaultName = "marainisntancejdtestkv"

    useExistingAppInsightsWorkspace = $false
    appInsightsWorkspaceName = "marainjdtestai"
    appInsightsWorkspaceResourceGroupName = ""
    appInsightsWorkspaceSubscriptionId = ""
}
