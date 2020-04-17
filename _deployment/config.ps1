$MarainServices = @{
    'Marain.Tenancy' = @{
        gitHubProject = 'marain-dotnet/Marain.Tenancy'
        apiPrefix = 'tenancy'
    }
    # 'Marain.Operations' = @{
    #     gitHubProject = 'marain-dotnet/Marain.Operations'
    #     apiPrefix = 'operations'
    # }
    # 'Marain.Workflow' = @{
    #     gitHubProject = 'marain-dotnet/Marain.Workflow'
    #     apiPrefix = 'workflow'
    # }
}

$InstanceManifest = @{
    services = @{
        'Marain.Tenancy' = @{
            release = '0.3.0-59-deployment-advertise-service.9'
        }
        # 'Marain.Operations' = @{
        #     release = '0.9.0-68-clienttenantprovider.5'
        # }
        # 'Marain.Workflow' = @{
        #     release = '0.2.0-preview.12'
        # }
    }
}

$marainDeploymentConfig = @{
    AzureLocation = 'uksouth'
    EnvironmentSuffix = 'jd'
    AadTenantId = '0f621c67-98a0-4ed5-b5bd-31a35be41e29'
    SubscriptionId = '13821a69-41a3-43ab-9577-1519963ea474'
    AadAppIds = @{
        'marjdtenancy'='b1556de5-5bc6-4632-b813-2ef4881506a7'
    }
    AadOnly = $false
    SkipInstanceDeploy = $false
    DoNotUseGraph = $false
    ResourceGroupNameRoot = 'Marain'
    SingleServiceToDeploy = ''
    DeploymentAssetLocalOverrides = @{}
}