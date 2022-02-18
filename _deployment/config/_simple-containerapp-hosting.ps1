#
# This sample represents the simplest Marain environment
#   - Dedicated Container App Environment, ACR & AppConfiguration
#   - Single key vault shared by all Marain services
#
@{
    AzureLocation = "northeurope"

    # Two AzureAD security groups can be used to control read & read/write access to key vault
    KeyVaultReadersGroupObjectId = "8e25cffb-9150-473e-8917-8f10e432e4ed"
    KeyVaultContributorsGroupObjectId = "78f0285a-0004-4b92-b2f8-e1c2cbcbe4f2"
    
    # Name overrides (otherwise names will be generated based on stack, instance & environment details)
    InstanceResourceGroupName = ""
    AppEnvironmentName = ""
    KeyVaultName = ""

    # use an existing app config store
    UseExistingAppConfigurationStore = $false       # When false, an AppConfig store will be provisioned in the 'marain' resource group
                                                    # When true, uncomment the settings below to configure the details
    # AppConfigurationStoreName = ""
    # AppConfigurationStoreResourceGroupName = ""
    # AppConfigurationStoreSubscriptionId = ""      # Only required if in a different subscription


    # Control hosting options
    UseContainerApps = $true
    UseExistingAppEnvironment = $false      # When false (and UseContainerApps=$true), a ContainerApp environment will be provisioned in the 'marain' resource group
                                            # When true, uncomment the settings below to configure the details
    # AppEnvironmentResourceGroupName = ""
    # AppEnvironmentSubscriptionId = ""

    # Config for using an Azure container registry (only relevant when 'UseContainerApps=$true')
    UseExistingAcr = $false     # When false, an ACR will be provisioned in the 'marain' resource group
                                # When true, uncomment the settings below to configure the details
    # AcrName = ""
    # AcrResourceGroupName = ""
    # AcrSubscriptionId = ""    # Only required if in a different subscription
 
    # Config for using a non-Azure container registry
    UseNonAzureContainerRegistry = $false   # When true, configure the settings below with the required details
                                            # When true, also implies 'UseExistingAcr=$true'
    ContainerRegistryServer = ""
    ContainerRegistryUser = ""
    ContainerRegistryKeySecretName = ""
}