# Adding new Marain services

If you want to define a new Marain service that can be included in any Marain instance you will need do to the following:

 - Produce a GitHub release containing a suitable-structured deployment ZIP
 - Add the GitHub repository to the `MarainServices.jsonc` list
 - Specify the specific release you want to deploy in the manifests for the instances that you want to deploy the service to (e.g. `InstanceManifests/Development.json` in this repo)

 When you then run `Deploy-MarainInstanceInfrastructure.ps1` for a manifest that describes which version of the service to deploy, it will deploy this newly added service.

 ## Deployment ZIP in GitHub release

`Deploy-MarainInstanceInfrastructure.ps1` expects services to be published as GitHub releases. 

We use a convention: the release must contain one or more assets with a name ending in `.Deployment.zip`. Each matching asset will be downloaded and processed.

These deployment ZIPs will be unzipped, and then `Deploy-MarainInstanceInfrastructure.ps1` checks for various files, and runs them (if present) in this order:

 - `Marain.PreDeploy.ps1`
 - `Marain-ArmDeploy.ps1` (skipped if `-AadOnly`)
 - `Marain-PostDeployNoAad.ps1` (skipped if `-AadOnly`)
 - `Marain-PostDeploy.ps1` (skipped if `-AadOnly`)
 - `Marain-PostDeployAad.ps1` (skipped when AAD not available, e.g. when deployment running in Azure DevOps)

Each of these files must conform to the same structure. They must define a single function thus:

```
Function MarainDeployment([MarainServiceDeploymentContext] $ServiceDeploymentContext) {
    # service-specific contents
}
```

Each of these files typically performs a particular job.

`Marain.PreDeploy.ps1` describes the Azure AD Applications that must be created before Azure resources can be created. If just one is required, this is sufficient:

```
$app = $ServiceDeploymentContext.DefineAzureAdAppForAppService()
```

If you have multiple functions apps in the service and they each need AAD Apps, do this:

```
$app = $ServiceDeploymentContext.DefineAzureAdAppForAppService("foo")
$app = $ServiceDeploymentContext.DefineAzureAdAppForAppService("bar")
```


`Marain-ArmDeploy.ps1` runs the ARM deployment. It typically consists of three phases:

 1. fetching information required as template parameters
 2. running the deployment
 3. making outputs from the deployment (e.g. MSI principal ids) available to later stages

e.g.:

```
[MarainAppService]$TenancyService = $ServiceDeploymentContext.InstanceContext.GetCommonAppService("Marain.Tenancy")

$OperationsControlAppId = $ServiceDeploymentContext.GetAppId("control")
$TemplateParameters = @{
    appName="operations"
    controlFunctionEasyAuthAadClientId=$OperationsControlAppId
    tenancyServiceResourceIdForMsiAuthentication=$TenancyService.AuthAppId
    tenancyServiceBaseUri=$TenancyService.BaseUrl
    appInsightsInstrumentationKey=$ServiceDeploymentContext.InstanceContext.ApplicationInsightsInstrumentationKey
}
$InstanceResourceGroupName = $InstanceDeploymentContext.MakeResourceGroupName("operations")
$DeploymentResult = $ServiceDeploymentContext.InstanceContext.DeployArmTemplate(
    $PSScriptRoot,
    "deploy.json",
    $TemplateParameters,
    $InstanceResourceGroupName)

$ServiceDeploymentContext.SetAppServiceDetails($DeploymentResult.Outputs.controlFunctionServicePrincipalId.Value, "status", $null)
$ServiceDeploymentContext.SetAppServiceDetails($DeploymentResult.Outputs.statusFunctionServicePrincipalId.Value, "control", $null)
```

`Marain-PostDeployNoAad.ps1` run after ARM deployment, performing any work that can be done without AAD access. Note: currently nothing uses this.


`Marain-PostDeploy.ps1` run after ARM deployment. Performs tasks that can be done only after ARM deployment has occurred. This should not include tasks that will be run even in AAD-only runs. It typically involves uploading code ZIPs for Azure Functions, e.g.:

```
Write-Host 'Uploading function code packages'

$ServiceDeploymentContext.UploadReleaseAssetAsAppServiceSitePackage(
    "Marain.Workflow.Api.MessageProcessingHost.zip",
    $ServiceDeploymentContext.AppName + "mi"
)
$ServiceDeploymentContext.UploadReleaseAssetAsAppServiceSitePackage(
    "Marain.Workflow.Api.EngineHost.zip",
    $ServiceDeploymentContext.AppName + "eng"
)

```


`Marain-PostDeployAad.ps1` run after ARM deployment, including in AAD-only mode. Typically assigns service principals to application roles, e.g.:

```
Write-Host "Assigning application service principals to the tenancy service app's reader role"

$EngineControllerAppRoleId = "37a5c4e2-38e2-47de-8576-6b1ce7cc0ca2"
$ServiceDeploymentContext.AssignServicePrincipalToCommonServiceAppRole(
    "Marain.Workflow.Hack.Engine",
    $EngineControllerAppRoleId,
    "mi"
)

$ControllerAppRoleId = "77d9c620-a258-4f0b-945c-a7128e82f3ec"
$ServiceDeploymentContext.AssignServicePrincipalToCommonServiceAppRole(
    "Marain.Tenancy.Operations.Control",
    $ControllerAppRoleId,
    "mi"
)
```


# MarainServices.jsonc

The GitHub organization and repository details are stored in `MarainServices.jsonc`, e.g.:

```json
"Marain.Operations": {
    "gitHubProject": "marain-dotnet/Marain.Operations",
    "apiPrefix": "operations"
}
```

(The `apiPrefix` is for use in deployment scenarios in which the services are all behind a shared API management interface—it defines the API prefix for this particular service.)


# Instance Manifests

The specific release version is determined by the instance manifest. (Different instances can deploy different versions. We typically deploy new versions to development before production.) For example:

```json
{
  "services": {
...
    "Marain.Operations": {
      "release": "0.9.0-68-clienttenantprovider.5"
    }
....
  }
}
```

This indicates that the for the `Marain.Operations` service, this instance wants to deploy the release with tag `0.9.0-68-clienttenantprovider.5`.
