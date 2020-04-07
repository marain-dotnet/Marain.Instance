Feature: ARM deployment staging storage
    In order to deploy a Marain instance
    As a developer or administrator
    I want the deployment system to locate or create a suitable storage account to enable use of linked templates during deployment


# Containing resource group name. (Currently ARM_Deploy_Staging, but there may be location issues with this?)
# Location - need per-region accounts to support different instances living in different regions
# Creates new account if suitable one does not exist. Uses existing account otherwise.
# Creates resource-group-specific container
# Ability to copy all required files into storage.

# Produce suitable outputs to use as _artifactsLocation and _artifactsLocationSasToken
# SAS token has 4 hour lifetime
# Accept SAS token as incoming argument? (Code has support for this but only because it was based on what the Azure Deployment project template creates. Not sure we need it.)
