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
        [bool]$DoNotUseGraph
    )

    # $here = Split-Path -Parent $PSCommandPath

    # . $here/../../classes/AzureDeployment.ps1

    $internalContext = [MarainInstanceDeploymentContext]::new($AzureLocation,$EnvironmentSuffix,"mar",$AadTenantId,$SubscriptionId,$AadAppIds,$DoNotUseGraph)
    
    $context = @{
        AzureLocation = $AzureLocation
        Prefix = $Prefix.ToLower()
        Name = $Name
        EnvironmentSuffix = $EnvironmentSuffix.ToLower()
        TenantId = $AadTenantId
        SubscriptionId = $SubscriptionId
        AadAppIds = $AadAppIds
        InstanceApps = @{}
        GraphHeaders = $null
        DeploymentStagingStorageAccountName = ('stage' + $AzureLocation + $SubscriptionId).Replace('-', '').substring(0, 24)
        DefaultResourceGroupName = $internalContext.MakeResourceGroupName($Name)
        ApplicationInsightsInstrumentationKey = $null
    }

    return $context
}