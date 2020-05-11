# How to run Marain locally

## Introduction

Whilst it is preferable to develop against Marain instances hosted in the cloud, it will sometimes be necessary to run Marain locally for testing purposes. There are a couple of options here:
1. All Marain services are run locally
2. Only specific Marain services are run locally

This document explains the first of these options. The other will be covered in a separate guide.

## Overview

To run any of the services locally, you need to do the following:
1. Retrieve the code for the services you wish to run.
2. Apply appropriate configuration for each service
3. Run the service
4. For multi-tenanted services, create the appropriate service registrations in your local instance of `Marain.Tenancy`.
5. Create a client tenant to use when calling services.

Since you'll be running multiple services, it's preferable to do so without needing an instance of Visual Studio open for each one. As long as you don't need them running in Debug mode, you can do this using the Azure Functions Core Tools (if you don't have them installed, do so now from npm - https://www.npmjs.com/package/azure-functions-core-tools).

You will however need to open each solution in Visual Studio to apply configuration and build the code.

Before starting, ensure you have the Azure Storage emulator running - when running services locally, the easiest option for the Tenancy and Operations services is to store their data using the emulator. For the Workflow service, the simplest solution is to use the Cosmos DB emulator. You can however use "real" storage in Azure if you prefer. 

## Setting up the functions

### Marain.Tenancy

This solution contains both the function host and a CLI. To configure the function to use the Azure Storage emulator, simply copy `local.settings.template.json` as `local.settings.json`. Ensure the new file has `Copy to Output Directory` set to `Copy if newer` or `Always`.

To configure the CLI to use the locally hosted function, create a new `appsettings.json` file containing the following:

```json
{
  "TenancyClient:TenancyServiceBaseUri": "http://localhost:7071/"
}
```

Again, ensure the new file has `Copy to Output Directory` set to `Copy if newer` or `Always`.

Once the configuration files are present, build the Solution. You can then either run the service from Visual Studio, or close Visual Studio down and run the function from the command prompt by navigating to the `Marain.Tenancy\Solutions\Marain.Tenancy.Host.Functions\bin\Debug\netcoreapp3.1` folder and executing the command

```
func start --port 7071
```

**Note that you will need the Tenancy service running in order for the `marain` commands in subsequent sections to execute successfully.**

### Marain.TenantManagement

Once you've got the Tenancy service running, you will need to initialise it for use with Marain. This is done via the CLI in the Marain.TenantManagement solution.

As with the Marain.Tenancy CLI, configure the Tenant Management CLI by adding an `appsettings.json` file containing the following, and ensure `Copy to Output Directory` is set appropriately:

```json
{
  "TenancyClient:TenancyServiceBaseUri": "http://localhost:7071/"
}
```

Then build the solution.

You can now use a command prompt to execute the tool to initialise the local tenancy service. Navigate to the `Marain.TenantManagement\Solutions\Marain.TenantManagement.Cli\bin\Debug\netcoreapp3.1` folder and execute the command

```
marain init
```

It will be useful to keep a command prompt open in this folder as you'll need the CLI to create tenant registrations for other Marain services.

### Marain.Operations

The next Marain service you should set up is Operations. As with previous services, pull the code and open in Visual Studio. The Operations service contains two functions: the Control Host and the Status Host.

Create the `local.settings.json` files by copying the `local.settings.template.json` files in each function (`Marain.Operations.ControlHost.Functions` and `Marain.Operations.StatusHost.Functions`). You only need to update one setting in each file: `TenancyClient__TenancyServiceBaseUri` should be set to `http://localhost:7071/` to refer to the locally running Tenancy service. Ensure `Copy to Output Directory` is set appropriately for both config files then build the solution. As before, you can now run the functions from Visual Studio or the command line using the `func start` command. The Control function should run on port `7078` and the Status function on port `7077`.

You then need to register the Workflow service with the Tenancy service. Using the `marain` tool built in the previous section, execute the following command, replacing the path to the service manifest with the appropriate path for your local environment:

```
marain create-service c:\git\Marain.Operations\Solutions\ServiceManifests\OperationsServiceManifest.jsonc
```

You should see output like the following:
```
info: Marain.TenantManagement.Internal.TenantManagementService[0]
      Created new service tenant 'Operations v1' with Id '3633754ac4c9be44b55bfe791b1780f12429524fe7b6cc48a265a307407ec858'.
```

And if you then run 

```
marain show-hierarchy
```

You should see the newly created 'Operations v1' service tenant.

```
Root - (f26450ab1668784bb327951c8b08f347)
 |     [Type: Undefined]
 |
 |-> Service Tenants - (3633754ac4c9be44b55bfe791b1780f1)
 |     [Type: Undefined]
 |     |
 |     |-> Operations v1 - (3633754ac4c9be44b55bfe791b1780f12429524fe7b6cc48a265a307407ec858)
 |     |     [Type: Service]
 |
 |-> Client Tenants - (75b9261673c2714681f14c97bc0439fb)
 |     [Type: Undefined]
 ```

### Marain.Workflow

As with `Marain.Operations`, the Workflow service has two functions; the Message Processing host and the Engine host. 

For the Engine host, copy the `local.settings.template.json` file to `local.settings.json` then make the following modifications:

- Set `TenancyClient:TenancyServiceBaseUri` to `http://localhost:7071`
- Remove `TenancyClient:ResourceIdForMsiAuthentication`
- Set `Operations:ControlServiceBaseUrl` to `http://localhost:7078`
- Remove `Operations:ResourceIdForMsiAuthentication`

Repeat for the Message Processing host, making the same changes. Ensure that `Workflow:EngineClient:BaseUrl` is set to `http://localhost:7075` and that `Workflow:EngineClient:ResourceIdForAuthentication` is blank or absent completely.

The Solution can now be built and run either via Visual Studio or the `func start` command.

Again, as with the Operations service, the Workflow service must have a corresponding Service Tenant created for it, which is done via the Marain.TenantManagement CLI tool using the following command, replacing the path to the service manifest with the appropriate path for your local environment:

```
marain create-service c:\git\Marain.Workflow\Solutions\ServiceManifests\WorkflowServiceManifest.jsonc
```

### Running all the functions together

The script `Run-MarainServices.ps1`, found alongside this document, can be used to run all 5 of the Marain functions locally using the Azure Functions Core Tools. You will need to customise the paths to run it locally.

## Creating and enrolling a client tenant

Once you have your functions running, you will also need to create a Client tenant to access the functions, and enroll it to use those functions.

The simplest way to do this is to use the `marain` tool:

```
marain create-client "<client name here>"
```

This will return the Id of the new tenant, which you can then use to enroll it to use the Marain services.

When enrolling, you need to provide a JSON file with the appropriate configuration for the tenant to use the service. Example files are found in the `Solutions\ServiceManifests\Configuration` folders of the Operations and Workflow services; these contain configuration that will set the services up to use the Storage and Cosmos emulators respectively.

To register your client tenant to use the services, use the following commands:

### Workflow

```
marain enroll <your client tenant Id> 3633754ac4c9be44b55bfe791b1780f177b464860334774cabb2f9d1b95b0c18
--config "C:\git\Marain.Workflow\Solutions\ServiceManifests\Configuration\WorkflowConfigForStorageEmulator.json"
```

### Operations

```
marain enroll <your client tenant Id> 3633754ac4c9be44b55bfe791b1780f12429524fe7b6cc48a265a307407ec858
--config "C:\git\Marain.Operations\Solutions\ServiceManifests\Configuration\OperationsConfigForStorageEmulator.json"
```