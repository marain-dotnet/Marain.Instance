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

Since you'll be running multiple services, it's preferable to do so without needing an instance of Visual Studio open for each one. As long as you don't need them running in Debug mode, you can do this using the Azure Functions Core Tools (v3). If you don't have them installed, do so now from npm - https://www.npmjs.com/package/azure-functions-core-tools - if you do have them installed already, you can update using `npm update -g azure-functions-core-tools@3`. Note that the version of the tools that Visual Studio keeps up to date is a different one from this, so they can drift apart.

Before starting, ensure you have the Azure Storage emulator running - when running services locally, the easiest option for the Tenancy and Operations services is to store their data using the emulator. For the Workflow service, the simplest solution is to use the Cosmos DB emulator. You can however use "real" storage in Azure if you prefer.

You also need to ensure you have `git` (https://git-scm.com/downloads) and the `dotnet` CLI (https://docs.microsoft.com/en-us/dotnet/core/install/windows?tabs=netcore31) installed.

## Setting up the functions

You can run the following script

```powershell
./Setup-MarainServices.ps1 -BasePath <BasePath>
```

which will:

- `git clone` the Marain services repos
- create copies of the `local.settings.template.json` settings templates as `local.settings.json`
- update the values of `local.settings.json` to ensure that everything is configured for local development (e.g. URLs to services are set to the correct `localhost:<port>`)
- build the functions host projects using `dotnet`

You only need to run this script once, but you can run it again if you wish to update to later versions of the Marain repos.

For `<BasePath>`, choose the location where you want the Marain repos to be cloned. Each will be cloned into a subfolder at this location.

(*NOTE* - the script must be run using PowerShell 6.0+, as previous versions are unable to parse JSON files with comments)

## Running the functions

To run the functions, run the following script

```powershell
./Run-MarainServices.ps1 -BasePath <BasePath>
```

using the same `<BasePath>` used for `Setup-MarainServices`.

This will start up Tenancy, Claims, Operations, and Workflow.

The rest of the steps in this documentation only need to be run on initial setup. Once configured, you can just use the `Run-MarainServices` script in the future to start up the services.

## Initialising the tenant and creating the service tenants

Once you've got the Tenancy service running, you will need to initialise it for use with Marain, and each of the services need to be registered as service tenants with the Tenancy Service.

This is done via the CLI in the Marain.TenantManagement solution.

You can run the following script

```powershell
./Initialise-MarainServices.ps1 -BasePath <BasePath>
```

which wraps the calls to the CLI.

## Creating and enrolling a client tenant

Once you have your functions running, you will also need to create a Client tenant to access the functions, and enroll it to use those functions.

The simplest way to do this is to use the Marain.TenantManagement.CLI tool. Open a command prompt at `<BasePath>\Marain.TenantManagement\Solutions\Marain.TenantManagement.Cli\bin\Debug\netcoreapp3.1` and run:

```
marain create-client "<client name here>"
```

This will create the new tenant. To obtain the Id of the new tenant, which you can then use to enroll it to use the Marain services, run the following command:

```
marain show-hierarchy
```

and look under the `Client Tenants` section for the newly created tenant. The Id will be in brackets next to the name.

When enrolling, you need to provide a JSON file with the appropriate configuration for the tenant to use the service. Example files are found in the `Solutions\Marain.<Service>,Deployment\ServiceManifests\Configuration` folders of the Claims, Operations, and Workflow services; these contain configuration that will set the services up to use the Storage and Cosmos emulators respectively.

To register your client tenant to use the services, use the following commands:

### Claims

```
marain enroll <your client tenant Id> 3633754ac4c9be44b55bfe791b1780f1ca7153e8fbe1b54b9f44002217f1c51c
--config "<BasePath>\Marain.Claims\Solutions\Marain.Claims.Deployment\ServiceManifests\Configuration\ClaimsConfigForStorageEmulator.json"
```

### Operations

```
marain enroll <your client tenant Id> 3633754ac4c9be44b55bfe791b1780f12429524fe7b6cc48a265a307407ec858
--config "<BasePath>\Marain.Operations\Solutions\Marain.Operations.Deployment\ServiceManifests\Configuration\OperationsConfigForStorageEmulator.json"
```

### Workflow

```
marain enroll <your client tenant Id> 3633754ac4c9be44b55bfe791b1780f177b464860334774cabb2f9d1b95b0c18
--config "<BasePath>\Marain.Workflow\Solutions\Marain.Workflow.Deployment\ServiceManifests\Configuration\WorkflowConfigForStorageEmulator.json"
```

### User Notifications

```
marain enroll <your client tenant Id> 3633754ac4c9be44b55bfe791b1780f17ffa2f897c1169458ecb7240edb9f0c3
--config "<BasePath>\Marain.UserNotifications\Solutions\Marain.UserNotifications.Deployment\ServiceManifests\Configuration\UserNotificationsConfigForStorageEmulator.json"
```
