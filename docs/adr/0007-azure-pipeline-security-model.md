# Azure pipeline security model

## Status

Proposed


## Context

This ADR defines an approach for a least-privilege Azure DevOps Pipeline, using a Microsoft-hosted agent, that supports the automated deployment, teardown and re-deployment of a typical Azure PaaS-based solution.

The challenge here is to balance the varied benefits of having a self-sufficient, repeatable pipeline with the need for adequate security controls to minimise the risk of the pipeline becoming the source of a security incident.

Such a deployment pipeline needs to be able to perform the following actions:

1. Create resources in the target subscription
1. Query AAD for existing applications & service principals
1. Perform ARM role assignments in the target subscription
1. Create and manage new AAD applications & service principals

### Create resources in the target subscription
By default, the 'Service Connections' that Azure Pipelines use to authenticate with Azure only provide #1 of the above.

### Perform ARM role assignments in the target subscription
Typically this is achieved by granting the identity behind the service connection the 'owner' role in the target subscription.

### Query AAD for existing applications & service principals
The main pipeline is restructured to expect the required information to be provided as manually-maintained configuration.

### Create and manage new AAD applications & service principals
This is commonly handled in one of three ways:

* an entirely seperate pipeline running under a different identity which does have the necessary permissions
* running a subset of the main pipeline, under a different identity which does have the necessary permissions, such that only  the tasks that require the elevate privileges are run
* an out-of-band process whereby an individual with the appropriate permissions executes the necessary steps (either manually or using a script)

>NOTE: This functionality may have to run multiple times in the case of on-going application permission management.


## Decision

In order to ensure the principle of least privilege, whilst still enabling a fully-automated process the following steps are proposed.

1. Each Marain environment has its own dedicated Azure AD identity that the pipeline executes under
1. Each Azure subscription that hosts a Marain environment requires a custom AzureRM role, that grants:
    * `MicrosoftAuthorization/RoleAssignment/*` (Read/Write/Delete)
1. Each identity is granted the following permissions:
    * Subscription scope:
        * `Contributor`
        * The custom role for the associated subscription
    * Azure Active Directory Graph scope:
        * `Directory.Read.All`
        * `Application.ReadWrite.Owned`
1. AzureAD administrators get approval oversight of the additional Graph permissions, via the 'admin consent' mechanism
1. An Azure Pipelines service connection is created for each of the above identities
1. The owner of the Azure Pipelines service connection gets approval oversight of any pipelines wishing to use it (first time only)
1. By using YAML-based pipelines, any changes can be subjected to review via a Pull Request process


## Consequences

### Postive
A pipeline is able to perform all the required automation tasks, with the following security controls in-place:

1. All pipelines wishing to use this identity require initial approval
1. A pipeline will not be able to access AzureAD application identities that it has not created
    * This mitigates a 'dev' pipeline inadvertently changing an identity used in 'prod' (for example)
    * NOTE: This means that all AzureAD application identities *must* be created via the pipeline
1. A pipeline will have its ability to make role assignment changes constrained to its target subscription
    * If required, further auditing or a security policy could be implemented to try and catch 'unexpected' role assignment operations
1. All actions associated with a pipeline will be performed by a single identity, which provides a clear audit trail

### Negative
- Attempts to subvert the pipeline from within a feature branch would get no pull request oversight
- A credential key-rotation policy on such identities would require the associated Azure DevOps service connection to be kept in-sync
