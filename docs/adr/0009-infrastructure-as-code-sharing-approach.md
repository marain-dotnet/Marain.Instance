# infrastructure-as-code-sharing-approach

## Status

Proposed

## Context

* The current version of Marain uses ARM templates to automate the infrastructure deployment for each Marain service.
* The deployment templates resides alongside the code for each service
* There is significant commonality/duplication of ARM templates between services
* We wish to migrate to using Bicep to define the Marain infrastructure deployments
* A desire to minimise duplication and utilise shared Bicep modules
* Ideally, the overall Marain deployment process should be as low-friction as the current "'git clone' & deploy" approach

Given this context and goals, the challenge is how to combine the use of shared Bicep modules (to de-duplicate the infrastructure-as-code) whilst still having a low friction means of deploying the Marain stack.  The absence of a defacto public Bicep module repository that can host the Marain-specific modules means there isn't an obvious way to share these modules without additional work.

***NOTE**: A more general, but related, Bicep reuse [ADR](https://github.com/endjin/Endjin.RecommendedPractices.Bicep/blob/main/docs/adr/0002-sharing-bicep-modules.md) was written before it became clear that the public Bicep registry would not be 'open to all', for publishing, in the same way that nuget.org or Docker Hub are.*

In the ideal world the Marain deployment would use Bicep modules in the [Endjin.RecommendedPractices.Bicep repository](https://github.com/endjin/Endjin.RecommendedPractices.Bicep) so as to avoid duplication as well as a set of Marain-specific modules that are re-usable across different Marain services.  This means that the envisioned deployment process would need to interact with 3 sets of Bicep modules:

1. Shared/Common - non-Marain specific functionality 
1. Marain shared - functionality common to multiple Marain services
1. Marain service-specific - functionality tailored to an individual Marain service

This ADR considers the following options:

1. Hosting a public Bicep registry
1. Supporting internal Bicep registries
1. Shipping pre-compiled ARM templates

## Options

### Hosting a public Bicep registry

This option involves us hosting an Azure Container Registry that we make publicly available and publishing the Marain Bicep modules to it as part of the overall Marain release process.

#### Advantages
* Simplest and lowest friction option for the Marain consumer.
* Easy to integrate with our existing release process.
* Some flexibility for where the source for the shared Bicep modules is stored, as they won't be primarily consumed as 'source' artefacts.
    * Since the deployment tooling can reference a public distribution point, the modules would not have to be available alongside the source repository in order to support the "'git clone' & deploy" approach
* The ACR could also be used to release & host Marain container images in the future.

#### Disadvantages
* Costs associated with operating the ACR, both resource and bandwidth costs
    * Basic service: ~£20 per month (based on ACR Standard SKU)
    * Resilient service: ~£85 per month (based on ACR Premium SKU with geo-replication)
* The Marain deployment process becomes dependent on network connectivity to the public registry - although this is arguably no different to the current requirement for access to GitHub (needed to download release artefacts).


### Supporting internal Bicep registries

This option assumes that a Marain consumer will have access to an Azure Container Registry (ACR) that can be populated with the required Bicep modules.

* We would provide tooling to provision the basic ACR infrastructure and/or publish the required Bicep modules.
* The deployment tooling would need to support customising the ACR details.

#### Advantages
* No ongoing hosting costs for the Marain maintainers.
* Provides consumers with an internalised deployment solution.

#### Disadvantages
* Additional steps/friction for the consumer before they can deploy Marain.
* Additional effort required provide the tooling to provision/populate the Bicep module registry.
* Requires a method of bundling the required modules to support the process of populating the internal registry.
* The need to bundle may conflict with the desire to keep the Bicep source alongside the associated service.
* The above may lead us to using Git submodules


### Shipping pre-compiled ARM templates

This option relies on using ARM templates for the deployment, whilst using Bicep for their development.

The release process for each service would include generating an ARM template from its Bicep source files, which the deployment tooling would use.

#### Advantages

* No ongoing hosting costs for the Marain maintainers or consumers.
* The required Bicep modules need only be accessible during the build/release process, so no bundling required.

#### Disadvantages

* The Bicep source files in the various repos would not be useable by someone cloning the repo (without access to a populated module registry).
* The generated ARM templates would potentially need to be committed to the git repo as part of the build/release process to ensure they were available to someone cloning the repo (alternatively they could be treated as release artefacts like the current ZIP deployment packages).
* Marain consumers needing to troubleshoot a deployment issue would have to debug a single large ARM template.


## Decision

The following hybrid approach will be taken:

* Shared Bicep modules will be hosted on a non-public ACR
* Source references to such modules will use an [alias](https://github.com/MicrosoftDocs/azure-docs/blob/main/articles/azure-resource-manager/bicep/bicep-config-modules.md#aliases-for-modules) to de-couple them from the hosted ACR infrastructure
* The hosted ACR will adopt a repository structure that will support logical grouping of modules with different security requirements (e.g. public, restricted, private etc.)
* 3rd parties entitled to access the hosted modules will do so via ACR [repository-scoped](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-repository-scoped-permissions) access tokens
* OSS repositories that consume these hosted modules should contain guidance on:
    * Where to find the source code for these modules
    * How to request access to our 'convenience' hosted Bicep module registry (exact process and requirements TBC)
* Closed-source scenarios that require access to these hosted modules will be handled as part of the underlying engagement or procured service. For example:
    * Access to hosted ACR provided by default
    * Access to underlying private GitHub repos provided on request

## Consequences

### Positive
* Everything will work the same as currently developed (i.e. referencing our internal ACR)
* Minimises upfront work to support what may be a lightly used scenario (i.e. unknown parties using our OSS IP), by not needing to build a complex re-packaging solution
* Only requires a single container registry to support external access as there is no need for a truly public/anonymous ACR - this minimises costs.

### Negative
* Requires assigning each repository to a [scope map](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-repository-scoped-permissions#concepts) as ACR does not currently support a wildcard-style approach.  This would likely be added to the Bicep module CI/CD process.
