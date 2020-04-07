Feature: Orchestrate instance deployment
    In order to deploy a Marain instance
    As a developer or administrator
    I want all the necessary steps to be executed in the correct order automatically

# skip instance deployment (app insights key handling in this case?)
# passing of app insights key (although perhaps this would be better handled in a general-purpose way - do we really need the instance bits to be a special case if we get dependency handling correct?)
# deploy individual service; service scripts must be able to request:
#  ARM template deployment
#  App Service ZIP package deployment to deploy code to all relevant app services.
# Driven by instance manifest - deploys all described services, fetches releases described in manifest
# AAD steps
# Passing in AAD details when AAD steps not being performed
# Enable selection between using local deployment assets vs download from GitHub

# Common app service handling - services that want to call other services (e.g., Marain.Operations using Marain.Tenancy) need to be able to discover the other service's:
#  Base URL
#  Resource ID to use when authenticating (the audience in the OAuth2 bearer token - this will be the App ID of the app the target service uses to authenticate incoming requests)
#  Assign calling service's Service Identity to roles in the target service's app

# Intra-service app auth - when a Marain service has multiple hosts (e.g., Marain.Operations is implemented as two Azure Functions), we need some of the same features as above.
# (Base URL and Resource ID might possibly be handled directly within the ARM template, but adding services to app roles can't be done that way.)


# Dependency handling?

# For each service, run appropriate scripts. ("Appropriate" is defined by which particular deployment mode we're in.)