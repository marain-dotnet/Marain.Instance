param name string
param secretsReadersGroupObjectId string
param secretsContributorsGroupObjectId string
param tenantId string
param resourceTags object = {}


targetScope = 'resourceGroup'


var readerAccessPolicy = (!empty(secretsReadersGroupObjectId)) ? {
  objectId: secretsReadersGroupObjectId
  tenantId: tenantId
  permissions: {
    secrets: [
      'get'
    ]
  }
} : {}

var contributorAccessPolicy = (!empty(secretsContributorsGroupObjectId)) ? {
  objectId: secretsContributorsGroupObjectId
  tenantId: tenantId
  permissions: {
    secrets: [
      'get'
      'set'
    ]
  }
} : {}

var accessPolicies = [
  readerAccessPolicy
  contributorAccessPolicy
]

module key_vault 'br:endjintestacr.azurecr.io/bicep/modules/key_vault:0.1.0-beta.01' = {
  name: name
  params: {
    name: name
    enable_diagnostics: true
    access_policies: accessPolicies
    enabledForTemplateDeployment: true
    tenantId: tenantId
    useExisting: false
    resource_tags: resourceTags
  }
}

output id string = key_vault.outputs.id
output name string = key_vault.outputs.name

output keyVaultResource object =  key_vault.outputs.keyVaultResource
