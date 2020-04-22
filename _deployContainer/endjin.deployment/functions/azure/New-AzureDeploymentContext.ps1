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
    
    $deployContext = @{
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

    $deployContext

    if ($IncludeServiceContext)
    {
        $internalServiceContext = [MarainServiceDeploymentContext]::new($internalDeployContext, $ServiceApiSuffix, $ServiceShortName, 'foo', 'foo')

        $ServiceContext = @{
            DeploymentContext = $deployContext
            GitHubRelease = 'foo'
            TempFolder = 'foo'

            AppNameRoot = $ServiceShortName.ToLower()
            AppName = $deployContext.Prefix + $deployContext.EnvironmentSuffix + $internalServiceContext.AppNameRoot
            AppServices = $internalServiceContext.AppServices
            AdApps = $internalServiceContext.AdApps
        }

        $ServiceContext
    }
}