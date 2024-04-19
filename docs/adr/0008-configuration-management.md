# Marain Configuration & Secrets Management

## Context

A set of functional Marain services have specific configuration requirements.  In the past this configuration was primarily handled on a per-service basis, with almost all the settings stored in configuration files.  This led to much duplication of the same settings across services, which was inefficient to maintain and potentially error prone.

We are adopting Azure AppConfiguration as means of centralising configuration and sharing it across multiple services.

We have identified 4 categories of configuration that have different characteristics with regards to how we manage them:

1. Static Configuration
1. Static Secrets
1. Dynamic Configuration
1. Dynamic Secrets

This ADR describes how each of the above types of configuration will be maintained and, where necessary, shared.


### Configuration vs Secrets

'Secrets' are settings that are explicitly security sensitive, for example:
    * Username/password
    * API token
    * Encryption key

Secrets must therefore never be included in the files that are committed to source control, unless said files are themselves encrypted.  However, such approaches increase the complexity due to the need to manage the associated encryption keys.

'Configuration' refers to any other settings that are not security sensitive in nature:
    * URL for a web service
    * Feature toggles that control a component's behaviour
    * Logging level

***NOTE**: Whilst all configuration could arguably be deemed sensitive from an infiltration reconnaissance perspective, this has been ignored for the purposes of this ADR*


### Static vs Dynamic

'Dynamic' refers to configuration or secrets that get their values as part of some other automated process.  For example, during an ARM deployment the following configuration/secrets would be generated:
    * The URL for an Azure web service
    * The access key for an Azure storage account

'Static' refers to configuration or secrets that have to be manually maintained, because they cannot be derived based on other information/processes or they are maintained by external parties.  For example:
    * Feature toggles that control a component's behaviour 
    * API key for a 3rd party service


### Shared vs Private

All configuration typically has a notion of being owned or maintained by a single component.  Such configuration should be maintained alongside the 'owning' component and that component is treated as the 'source of truth' for it.

'Private' refers to configuration that is only used by the 'owning' component, for example:
    * Feature toggles that control a component's behaviour
    * Number of threads to use for processing
    * Connection details to a dedicated storage account used only by the 'owning' component

'Shared' relates to configuration or secrets that are used by more than just the 'owning' component, for example:
    * Database connection string
    * Web service URL
    * API key

The Shared vs Private status of a particular configuration setting or secret is independent of whether it is Static or Dynamic.

Shared configuration and secrets will be published to an AppConfiguration store to make them available to other dependent components.  This publishing will happen as part of the deployment process for the 'owning' component which will ensure that


## Decision

Static Configuration
:   Will be stored in source-controlled files appropriate to the use case (e.g. JSON, YAML etc.), organised by environment

Static Secrets
:   Will be stored manually in AppConfiguration as Key Vault-backed items

Dynamic Configuration
:   Will be stored in AppConfiguration as part of the 'owning' component's CI/CD automation

Dynamic Secrets
:   Will be stored in AppConfiguration as Key Vault-backed items via the 'owning' component's CI/CD automation

Shared Configuration
:   Will be published to AppConfiguration via the 'owning' component's CI/CD automation


## Consequences

1. Components should require much less static configuration, due to the required settings being available via AppConfiguration
1. CI/CD processes will need to be update to support publishing the necessary configuration and secrets
1. Applications will need to be updated to support obtaining their configuration and secrets from AppConfiguration
1. A `Corvus` component will be needed to abstract and streamline the AppConfiguration integration
1. Static secrets will need to be documented to ensure that their provenance is understood by those maintaining the system, along with other useful metadata (e.g. the associated AppConfiguration key name)
1. The naming of AppConfiguration keys will be important to aid discoverability (though supporting documentation may still be necessary)
1. Where a single AppConfiguration store is used to support multiple deployed environments, AppConfiguration labels will be used to identity each environment's values
1. Additional tooling will be required to support offline development scenarios