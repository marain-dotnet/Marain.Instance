# Adding a new Marain Instance

An 'instance' in Marain refers to one complete deployment of a set of Marain services. (This terminology is based on that used by Azure AD, which has separate instances for geopolitical reasons.)

To create a new instance, define a new instance manifest. You can find existing instance definitions in the `InstanceManifests` folder of this repository, but the file does not have to live there—you specify the instance manifest location as an argument to a script to deploy the instance.

The instance manifest determines which services are deployed, and which versions of the code get deployed to the services that are present. For example, this:

```json
{
  "services": {
    "Marain.Tenancy": {
      "release": "0.3.0-59-deployment-advertise-service.9"
    },
    "Marain.Operations": {
      "release": "0.9.0-68-clienttenantprovider.5"
    }
  }
}
```

would define an instance containing just the `Marain.Tenancy` and `Marain.Operations` services.

The `release` property refers to a GitHub release. All Marain services produce GitHub releases, which must work in the way described in  [/adding-services.md]()./adding-services.md).

Use the `Deploy-MarainInstanceInfrastructure.ps1` script to deploy your instance, e.g.:

```
Deploy-MarainInstanceInfrastructure.ps1 `
    -AzureLocation northeurope `
    -EnvironmentSuffix myenv `
    -AadTenantId $MyAadTenantId `
    -SubscriptionId $MyAzureSubscriptionId `
    -InstanceManifest $PathToMyInstanceManifest
```

The `EnvironmentSuffix` argument determines the name of various Azure resources, many of which have global uniqueness requirements, so this needs to be different from any other Marain instances that already exist (regardless of whether they may be in different Azure Subscriptions or different AAD tenants)

This script will create multiple resource groups in your Azure subscription, all starting with the name `mar.` and all ending with the name of your environment suffix. It creates one for common Marain resources (e.g., a shared Application Insights instance), and each Marain service typically adds one resource group of its own. This will run all of the Marain script in the deployment packages produced by the services you include in your manifest, which will typically also create AAD applications, and will upload code to App Services. So once the script completes, you should have a complete, usable Marain instance.