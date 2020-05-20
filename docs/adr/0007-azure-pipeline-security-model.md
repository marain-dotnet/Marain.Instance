# Azure pipeline security model

## Status

Proposed

## Context

This ADR defines an approach for a least-privilege Azure DevOps Pipeline that supports the automated deployment, teardown and re-deployment of a complete Marain instance.

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

The challenge here is to balance the varied benefits of having a self-sufficient, repeatable pipeline with the need for adequate security controls to minimise the risk of the pipeline becoming the source of a security incident.


## Decision




## Consequences
