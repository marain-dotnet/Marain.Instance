Feature: Perform required AAD configuration steps
    In order to deploy a Marain instance
    As a developer or administrator
    I want to be able to automate all the necessary AAD configuration steps while conforming to customer constraints

# There are two phases:
#   Before ARM deploy
#   After ARM deploy

# Want options:
#   Fully automate within tool (requires tool to have access to credentials with all necessary privileges)
#   Generate scripts which, when run, perform all the necessary steps for each phase (enables admins to look at what the scripts are doing)
#   Describe steps without performing them?

# We also want to be able to automate the process of extracting the information that is required when running the rest of a deployment in "no AAD" mode.
# (I.e., the ability to collect all required App IDs, and any other info that would need to be passed as input to the tool when running in this mode.)
# We'd probably want the script that does the actual setup to do this anyway. And since we'd need the scripts to be able to be idempotent, arguably
# all we need is the one set of scripts. However, there may be merit in the ability to generate scripts that make no attempt to change anything, and
# just report what is there. (These could be run by people with fewer privileges.)

# Actual operations that we need to be able to perform:
#   Ensure app exists, and report its ID
#   Ensure all required app roles exist
#   Configure callback URL if required. (Note: while we often don't need this for normal operations, it can be very handy as a way of obtaining a token during development.)
#   Create corresponding Enterprise App entry (technically a Service Principal, but not because the apps created by this system will ever be used as identities; it's because AAD's multi-tenant-capable model requires all apps (multi-tenant or not) to have a tenant-specific entry in addition to their app registration, and AAD conflates concerns by using the same type of directory object for that as it uses for a service principal)
#   Add standard Graph API "sign in and read profile" scope when necessary (do we always need this, or only to support interactive login?)
#   Do we need to be able to add other API access? Either on-behalf-of style (i.e., with all the usual AAD user consent stuff), or granting permission directly to the service principal?
#   Assign a service principal to an app role (either an SP from one of the service's own components, or from another app entirely; e.g., we need to be able to say that the Marain.Operations status service principal has read access to Marain.Tenancy)

# In the "set up inbound AAD apps" phase (or is that the pre-deployment AAD configuration phase?) we could want to run in any of the following modes:
#   * Just go ahead and create everything
#   * Find all the AAD IDs, and tell me if anything is missing
#   * I'm going to tell you all the AAD IDs, but please let me know if anything is missing
# Orthogonally to this, we might want to:
#   * Have the app talk directly to the graph API when necessary
#   * Generate a script containing commands that do all the necessary work
#   * Do not interact with graph (read existing and describe what needs to be done if not all info has been supplied)
# So there are two dimensions here:
#   * the level of authority in AAD (create/modify apps, read-only, or no access)
#   * the mechanism (do it, generate script that does it, describe)
# But not all combinations are valid? If we're in "I'm telling you" mode, 
# There's also the question of how information flows into the next stage. When using
# "app talks directly to graph" mode, all the information is going to be available at the end
# and with "I'll tell you", the information is available from the start. But with the script
# generation modes, the scripts need to run to produce the output, and that output would then
# be used as input to the next step.
# One question: is "find AAD IDs and tell me what's missing" actually a different mode
# than "I'll tell you the AAD IDs", or are these actually the same thing just with a different
# mechanism?

Scenario: Create required inbound authentication applications
    Given a service that reports two applications, 'triggers' and 'engine'
    When the inbound application creation phase of AAD configuration runs
    Then the


Scenario: Discover existing inbound authentication applications
    Given a service that reports two applications, 'triggers' and 'engine'
    When the application creation phase

# A service's deployment script needs to be able to tell Marain when a particular app is intended for use purely within this service, or across service boundaries (e.g., Marain.Tenancy needs to be used by other Marain services)

# Services may need a way to tell the Marain instance stuff the Service Principal OIDs for their managed identities.
# (We want to use managed identities where possible, meaning that the Marain Instance deployment system won't actually be
# responsible for creating all of the AAD objects. But the existing PowerShell scripts do keep track of this. We need
# to clarify the requirements around that.)

# Cross cutting requirements:
#   Handle naming conventions (e.g., default app name when a Marain Service needs only one app; convention for when it has more than one, e.g., like Operations)
#   APIM considerations?