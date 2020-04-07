Feature: Deploy common resources
    In order to deploy a Marain instance
    As a developer or administrator
    I want to be able to deploy common Azure resources shared across services in a Marain instance

# Currently the only shared resource is an Application Insights instance

# location
# "mar" resource group prefix
# "instance" root name
# environment suffix
# subscription id
# tenant id
# Puts relevant templates in staging storage
# Kicks off ARM deployment
# report app insights key

Scenario: 