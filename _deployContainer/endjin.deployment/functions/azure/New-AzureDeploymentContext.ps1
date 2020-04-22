function New-AzureDeploymentContext
{
    [CmdletBinding()]
    param
    (
        [string]$AzureLocation,
        [string]$EnvironmentSuffix,
        [string]$Prefix,
        [string]$Name,
        [string]$AadTenantId,
        [string]$SubscriptionId,
        [Hashtable]$AadAppIds,
        [bool]$DoNotUseGraph,

        [switch]$IncludeServiceContext,
        [string]$ServiceApiSuffix,
        [string]$ServiceShortName
    )

    $internalDeployContext = [MarainInstanceDeploymentContext]::new($AzureLocation,$EnvironmentSuffix,"mar",$AadTenantId,$SubscriptionId,$AadAppIds,$DoNotUseGraph)
    
    $script:DeploymentContext = @{
        AzureLocation = $AzureLocation
        Prefix = $Prefix.ToLower()
        Name = $Name
        EnvironmentSuffix = $EnvironmentSuffix.ToLower()
        TenantId = $AadTenantId
        SubscriptionId = $SubscriptionId
        AadAppIds = $AadAppIds
        InstanceApps = @{}
        GraphHeaders = $internalDeployContext.GraphHeaders
        DeploymentStagingStorageAccountName = ('stage' + $AzureLocation + $SubscriptionId).Replace('-', '').substring(0, 24)
        DefaultResourceGroupName = $internalDeployContext.MakeResourceGroupName($Name)
        ApplicationInsightsInstrumentationKey = $null
    }

    # return $script:DeploymentContext

    # if ($IncludeServiceContext)
    # {
    #     # $internalServiceContext = [MarainServiceDeploymentContext]::new($internalDeployContext, $ServiceApiSuffix, $ServiceShortName, 'foo', 'foo')

    #     $AppName = '{0}{1}{2}' -f $script:DeploymentContext.Prefix, $script:DeploymentContext.EnvironmentSuffix, $ServiceShortName.ToLower()
        
    #     $script:ServiceContext = @{
    #         DeploymentContext = $script:DeploymentContext
    #         GitHubRelease = 'foo'
    #         TempFolder = 'foo'

    #         AppNameRoot = $ServiceShortName.ToLower()
    #         AppName = $AppName
    #         AppServices = $internalServiceContext.AppServices
    #         AdApps = $internalServiceContext.AdApps
    #     }

    #     $ServiceContext
    # }
}