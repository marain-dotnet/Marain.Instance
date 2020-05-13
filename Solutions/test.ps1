$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $PSCommandPath

$manifest = "$here/../InstanceManifests/Development.json"

$localAssets = @{
    'Marain.Tenancy'='D:/PROJECTS/Endjin/marain/Marain.Tenancy/Solutions/Marain.Tenancy.Deployment'
    'Marain.Workflow'='D:/PROJECTS/Endjin/marain/Marain.Workflow/Solutions/Marain.Workflow.Deployment'
    'Marain.Operations'='D:/PROJECTS/Endjin/marain/Marain.Operations/Solutions/Marain.Operations.Deployment'
}

# try {

    # MPN subscription
    # & $here/Deploy-MarainInstanceInfrastructure.ps1 `
    #     -AzureLocation uksouth `
    #     -EnvironmentSuffix jd `
    #     -InstanceManifestPath $manifest `
    #     -AadTenantId 0f621c67-98a0-4ed5-b5bd-31a35be41e29 `
    #     -SubscriptionId 13821a69-41a3-43ab-9577-1519963ea474 `
    #     -DeploymentAssetLocalOverrides $localAssets

    # endjin-dev subscription
    # & $here/Deploy-MarainInstanceInfrastructure.ps1 `
    #     -AzureLocation northeurope `
    #     -EnvironmentSuffix jd `
    #     -InstanceManifestPath $manifest `
    #     -AadTenantId 0f621c67-98a0-4ed5-b5bd-31a35be41e29 `
    #     -SubscriptionId 98333d29-7302-4f93-a51d-70c49ca7e180 `
    #     -DeploymentAssetLocalOverrides $localAssets

    # endjin dev subscription, no AAD access
    $existingAppIds = @{
        marjdtenancy='8e31b2dc-e55d-4480-b467-da3788cfff83'
        marjdoperationscontrol='79221476-653b-4898-8df7-5aad0364c479'
        marjdworkflowmi='61f22941-5cc4-4c15-b532-416ebd92ee16'
        marjdworkfloweng='6741e408-3531-4b7d-a703-b403d2d0d25d'
    }
    & $here/Deploy-MarainInstanceInfrastructure.ps1 `
        -AzureLocation northeurope `
        -EnvironmentSuffix jd `
        -InstanceManifestPath $manifest `
        -AadTenantId 0f621c67-98a0-4ed5-b5bd-31a35be41e29 `
        -SubscriptionId 98333d29-7302-4f93-a51d-70c49ca7e180 `
        -DeploymentAssetLocalOverrides $localAssets `
        -DoNotUseGraph `
        -AadAppIds $existingAppIds
# }
# catch {
#     Write-Warning $_.ScriptStackTrace
#     Write-Warning $_.InvocationInfo.PositionMessage
#     Write-Error ("Error calling Deploy-MarainInstanceInfrastructure.ps1: `n{0}" -f $_.Exception.Message)
# }
    # [Hashtable] $AadAppIds = @{},
    # [switch] $AadOnly,
    # [switch] $SkipInstanceDeploy,
    # [switch] $DoNotUseGraph, # Used for debugging to simulate the lack of access to the graph we get in ADO
    # [string] $ResourceGroupNameRoot = "Marain",
    # [string] $SingleServiceToDeploy, # Normally we deploy everything, but set this to deploy just one particular service's infrastructure
    # [Hashtable] $DeploymentAssetLocalOverrides = @{}

    # az rest --method post `
    #     --uri https://graph.microsoft.com/beta/users/$user/appRoleAssignments `
    #     --body "{\"appRoleId\": \"60743a6a-63b6-42e5-a464-a08698a0e9ed\",\"principalId\": \"$user\",\"resourceId\": \"$spObjectId\"}" `
    #     --headers "Content-Type=application/json"
