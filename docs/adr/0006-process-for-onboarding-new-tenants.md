# Process for onboarding new tenants and enrolling them to use Marain services

## Status

Proposed

## Context

We have defined (in ADR 0006) the way in which we intend to implement Tenancy in Marain instances using the `Marain.Tenancy` service. As noted in that ADR, managing the desired model by hand would be excessively error prone and as such, we need to design tooling that will allow us to create and manage new tenants, and to allow them to use the Marain services they are licenced for.

Before we can build that tooling we need to design the underlying process by which tenant onboarding, enrollment and offboarding will work. This needs to allow new Client Tenants to be onboarded into Marain services without tightly coupling the services so some central "thing" that knows everything about them.

## Decision

We are envisaging a central control-plane API (referred to for the remainder of this document as the "Management API") for Marain which primarily builds on top of the Tenancy service. This will provide the standard operations such as creating new tenants and enrolling them to use Marain services.

It will also need to allow us to manage licencing, but we anticipate that this will be via an as-yet nonexistent API, as it will be a central service much like tenancy, used by all other services (either directly or via something like APIM).

### Onboarding

Onboarding is a relatively simple part of the process where we create a new Tenant for the client. We will need to determine how we intend licencing to work and what part, if any, the Management API plays..

### Enrollment

Service enrollment is a more interesting aspect of the process. In order to avoid tightly coupling Marain services to the Management API, we need two things:
- A means of discovering the available services.
- A means of requesting that a service enroll a Tenant to use it.

As described in ADR 0005, we are envisaging that each service has a Tenant created for it, under a single parent for all Service Tenants. These tenants can then underpin the discovery mechanism that allows the management API to enumerate services that tenants can be enrolled into. Part of the data attached to each tenant will be the URIs at which the endpoints they expose can be found.

Once we have provided a discovery mechanism, we need to define a way in which a service can be asked to enroll a tenant. The simplest way for this to work is to require all Marain services to have a control plane API that implements a set of standard endpoints. We can provide a standard OpenAPI document that defines the endpoints needed, which we would currently expect to be:
- Request the configuration that is needed to enroll a tenant to the service
- Enroll a tenant to the service
- Unenroll a tenant from the service

The idea being that once the Management API has discovered a service, it can request the information that would be required to enroll a tenant to it. This will be a list of required configuration settings, in a known form that allows them to be easily captured and validated before passing them to the enrollment endpoint.

The enrollment endpoint for a service will do two things:
- Firstly, it will attach the relevent configuration to the tenant that's being enrolled.
- Secondly, if the service that's being enrolled in has dependencies on other services, it will create a new sub-tenant of it's own Service Tenant that will be used to access those dependent services. This new subtenant will then be enrolled for the dependent service.

Whilst we did not wish to tightly couple the Marain services to the Management API, this restriction does not apply for services that depend upon other services. As such if a service does have a dependency, the location of that service (i.e. it's URI) will be part of the configuration for that service, making it easy for the enrollment endpoint of a service to create a new tenant and enroll it for the dependent service.

### Example

Consider a scenario when we have two clients and three services:

Root tenant
 |
 +-> Client Tenants
 |     |
 |     +-> Contoso
 |     |
 |     +-> Litware
 |     
 +-> Service Tenants
       |
       +-> WORKFLOW
       |
       +-> OPERATIONS
       |
       +-> FOOBAR
```

The dependency tree for the services looks like this:


```
                          +------------+
                          |            |
                  +-------> Workflow   +------+-----------------+
+---------+       |       |            |      |                 |
|         +-------+       +-^----------+      |                 |
| Contoso |                 |                 |                 |
|         |                 |                 |                 |
+----+----+                 |           +-----v------+          |
     |                      |           |            |          |
     |                      |     +-----> Operations +----+     |
     |      +---------+     |     |     |            |    |     |
     |      |         +-----+     |     +------------+    |     |
     |      | Litware |           |                       |     |
     |      |         +-----------+                       |     |
     |      +---------+                               +---v-----v--+
     |                                                |            |
     +------------------------------------------------> FooBar     |
                                                      |            |
                                                      +------------+
```

As can be seen from this diagram:
- Contoso is licenced to use `Workflow` and `FooBar`
- Litware is licenced to use `Workflow` and `Operations`
- `Workflow` has dependencies on `Operations` and `FooBar`
- `Operations` has a dependency on `FooBar`

Let's assume that each of the three services require storage configuration, and have a look at what happens when Litware is enrolled to use Workflow.

Firstly, we will request the list of required configuration to enroll a tenant for use with Workflow. Workflow "knows" it needs storage configuration, and because it's dependent on Operations and FooBar, it also requests the required configuration for those services. Operations does the same with FooBar, so the total list of required configuration for Workflow is the sum of those four things: Workflow storage config, Operations storage config, FooBar storage config when invoked from Workflow, and FooBar storage config when invoked from Operations.

Then, we will assemble this information and make the call to the enrollment endpoint for Workflow. The workflow service will attach it's storage configuration to the Litware tenant, and then create a sub-tenant of it's own Service Tenant with which it will call it's dependencies:

```
Root tenant
 |
 +-> Contoso
 |
 +-> Litware
 |     +-> (Workflow storage configuration)
 |     +-> (The Id of the WORKFLOW+Litware sub-tenant for the Workflow service to use)
 |
 +-> WORKFLOW
 |     |
 |     +-> WORKFLOW+Litware
 |
 +-> OPERATIONS
 |
 +-> FOOBAR
```

Next, the workflow service needs to enroll the new WORKFLOW+Litware tenant with the Operations and FooBar services.

It calls the enrollment endpoint for Operations, passing through the storage configuration supplied by the call to Workflow enrollment. This results in a similar outcome: the Operations endpoint adds it's configuration to the tenant, then creates a sub-tenant it will use to call it's own dependencies:

```
Root tenant
 |
 +-> Contoso
 |
 +-> Litware
 |     +-> (Workflow storage configuration)
 |     +-> (The Id of the WORKFLOW+Litware sub-tenant for the Workflow service to use)
 |
 +-> WORKFLOW
 |     |
 |     +-> WORKFLOW+Litware
 |           +-> (Operations storage configuration)
 |           +-> (The Id of the OPERATIONS+WORKFLOW+Litware sub-tenant for the Operations service to use)
 |
 +-> OPERATIONS
 |     |
 |     +-> OPERATIONS+WORKFLOW+Litware
 |
 +-> FOOBAR
```

Now, the Operations service calls FooBar's enrollment endpoint to enroll the OPERATIONS+WORKFLOW+Litware tenant, again passing through the configuration it received when the Workflow service invoked it. The FooBar service has no dependencies so does not need to create any further tenants; it simply attaches it's storage configuration to the tenant being enrolled and returns. This also completes the WORKFLOW+Litware tenant's enrollment for Operations.

```
Root tenant
 |
 +-> Contoso
 |
 +-> Litware
 |     +-> (Workflow storage configuration)
 |     +-> (The Id of the WORKFLOW+Litware sub-tenant for the Workflow service to use)
 |
 +-> WORKFLOW
 |     |
 |     +-> WORKFLOW+Litware
 |           +-> (Operations storage configuration)
 |           +-> (The Id of the OPERATIONS+WORKFLOW+Litware sub-tenant for the Operations service to use)
 |
 +-> OPERATIONS
 |     |
 |     +-> OPERATIONS+WORKFLOW+Litware
 |           +-> (FooBar storage configuration)
 |
 +-> FOOBAR
```

Next, the Workflow service continues it's enrollment process by enrolling the new WORKFLOW+Litware tenant in it's other dependency, FooBar. As with the Operations service enrolling OPERATIONS+WORKFLOW+Litware with FooBar, this does not result in any further tenants being created, just the FooBar config being attached to WORKFLOW+Litware:

```
Root tenant
 |
 +-> Contoso
 |
 +-> Litware
 |     +-> (Workflow storage configuration)
 |     +-> (The Id of the WORKFLOW+Litware sub-tenant for the Workflow service to use)
 |
 +-> WORKFLOW
 |     |
 |     +-> WORKFLOW+Litware
 |           +-> (Operations storage configuration)
 |           +-> (The Id of the OPERATIONS+WORKFLOW+Litware sub-tenant for the Operations service to use)
 |           +-> (FooBar storage configuration)
 |
 +-> OPERATIONS
 |     |
 |     +-> OPERATIONS+WORKFLOW+Litware
 |           +-> (FooBar storage configuration)
 |
 +-> FOOBAR
```

This completes Litware's enrollment for the Workflow service. As can be seen, this has resulted in multiple service-specific Litware tenants being created. However, there is a further step: Litware also needs to be enrolled in the Operations service. At present, it is able to indirectly use the service via Workflow, but also needs to be able to use it directly. So, the process we went through for Workflow is repeated: the management API requests the description of the configuration that must be provided to enroll Litware in the Operations service - which is storage configuration for Operations and FooBar - and then supplies that configuration to the Operations service's enrollment endpoint.

As with Workflow, the first thing that happens is that the Operations service will attach it's storage configuration to the Litware tenant, and then create a sub-tenant of it's own Service Tenant with which it will call it's dependencies:

```
Root tenant
 |
 +-> Contoso
 |
 +-> Litware
 |     +-> (Workflow storage configuration)
 |     +-> (The Id of the WORKFLOW+Litware sub-tenant for the Workflow service to use)
 |     +-> (Operations storage configuration)
 |     +-> (The Id of the OPERATIONS+Litware sub-tenant for the Operations service to use)
 |
 +-> WORKFLOW
 |     |
 |     +-> WORKFLOW+Litware
 |           +-> (Operations storage configuration)
 |           +-> (The Id of the OPERATIONS+WORKFLOW+Litware sub-tenant for the Operations service to use)
 |           +-> (FooBar storage configuration)
 |
 +-> OPERATIONS
 |     |
 |     +-> OPERATIONS+WORKFLOW+Litware
 |     |     +-> (FooBar storage configuration)
 |     |
 |     +-> OPERATIONS+Litware
 |
 +-> FOOBAR
```

Then, the Operations service will call out to the FooBar service to enroll the OPERATIONS+Litware service. As with enrolling the OPERATIONS+WORKFLOW+Litware service, this results in FooBar storage configuration being attached to the OPERATIONS+Litware service:

```
Root tenant
 |
 +-> Contoso
 |
 +-> Litware
 |     +-> (Workflow storage configuration)
 |     +-> (The Id of the WORKFLOW+Litware sub-tenant for the Workflow service to use)
 |     +-> (Operations storage configuration)
 |     +-> (The Id of the OPERATIONS+Litware sub-tenant for the Operations service to use)
 |
 +-> WORKFLOW
 |     |
 |     +-> WORKFLOW+Litware
 |           +-> (Operations storage configuration)
 |           +-> (The Id of the OPERATIONS+WORKFLOW+Litware sub-tenant for the Operations service to use)
 |           +-> (FooBar storage configuration)
 |
 +-> OPERATIONS
 |     |
 |     +-> OPERATIONS+WORKFLOW+Litware
 |     |     +-> (FooBar storage configuration)
 |     |
 |     +-> OPERATIONS+Litware
 |           +-> (FooBar storage configuration)
 |
 +-> FOOBAR
```

This completes the enrollment of Litware to the Workflow and Operations services. As can be seen from the above, there are three different paths through which Litware make indirect use of the FooBar service, and it's possible for the client to use separate storage for each. In fact, this will be the default; even if the client is using Marain storage, the data for their three different usage scenarios for FooBar will be stored in different containers.

### Offboarding

Offboarding needs to be considered further; there are many questions about what happens to client data if they stop using Marain, and these will likely depend on the licencing agreements we put in place. As a result this will be considered at a later date.

## Consequences

The obvious consequence of this ADR is that it requires a standard enrollment API to be supplied by each Marain service. It's likely that most of these services would need to provide both control- and data-plane APIs anyway, but this ADR essentially mandates the existence of a control-plane API with a minimum set of endpoints.

Whilst this ADR addresses how tenants are created and configured as part of enrollment, it does not yet cover how they are updated should a new version of a service be deployed that requires different configuration. In this scenario, all tenants that used that service would potentially need to be updated with the new configuration. This may be dealt with by versioning, requiring each tenant to be enrolled for a specific version of each service. This would require us to take a side-by-side approach to versioning in Marain, but would likely make it much more straightforward to deploy updates and move tenants onto new versions. As such, we are deferring further work on this until we have a better answer to the question of versioning.