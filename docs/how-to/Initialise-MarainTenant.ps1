param (
    [string] $BasePath
)

$marainTenantManagementCliExe = Join-Path $BasePath "\Marain.TenantManagement\Solutions\Marain.TenantManagement.Cli\bin\Debug\netcoreapp3.1\marain.exe"

. $marainTenantManagementCliExe init

. $marainTenantManagementCliExe create-service (Join-Path $BasePath "Marain.Claims\Solutions\Marain.Claims.Deployment\ServiceManifests\ClaimsServiceManifest.jsonc")
. $marainTenantManagementCliExe create-service (Join-Path $BasePath "Marain.Operations\Solutions\Marain.Operations.Deployment\ServiceManifests\OperationsServiceManifest.jsonc")
. $marainTenantManagementCliExe create-service (Join-Path $BasePath "Marain.Workflow\Solutions\Marain.Workflow.Deployment\ServiceManifests\WorkflowServiceManifest.jsonc")