[CmdletBinding()]
param
(
    [Parameter(Mandatory=$true)]
    [string] $name,

    [Parameter(Mandatory=$true)]
    [string] $azureSubscriptionId,

    [Parameter(Mandatory=$true)]
    [string] $azureTenantId,

    [Parameter(Mandatory=$true)]
    [string] $adoOrg,
    
    [Parameter(Mandatory=$true)]
    [string] $adoProject
)

Set-StrictMode -Version 4.0
$ErrorActionPreference = 'Stop'

function Invoke-AzCli {
    param (
        [string] $command,
        [switch] $asJson,
        [int] $expectedExitCode = 0
    )

    $cmd = "az $command"
    if ($asJson) { $cmd = "$cmd -o json" }
    Write-Verbose "azcli cmd: $cmd"
    $res = Invoke-Expression $cmd
    if ($LASTEXITCODE -ne $expectedExitCode) {
        Write-Error "azure-cli failed with exit code: $LASTEXITCODE"
    }

    if ($asJson) {
        return ($res | ConvertFrom-Json)
    }
}

function Ensure-AzCliLogin {
    try {
        # check whether already logged-in
        $currentToken = Invoke-AzCli "account get-access-token --subscription $azureSubscriptionId" -asJson
        if ([datetime]$currentToken.expiresOn -le [datetime]::Now) {
            throw
        }
    }
    catch {
        Write-Host 'You need to login'
        Invoke-AzCli "login --tenant $azureTenantId"
        if ($LASTEXITCODE -ne 0) { throw "azure-cli login failure" }
    }

    Invoke-AzCli "account set --subscription $azureSubscriptionId"
    return (Invoke-AzCli "account show" -asJson)
}

function Ensure-Spn {
    # create a new service principal
    $spSecret = $null
    $existingSp = Invoke-AzCli "ad sp list --display-name $name" -asJson
    if (!$existingSp) {
        Write-Host "Registering new SPN..."
        $newSp = Invoke-AzCli "ad sp create-for-rbac -n $name" -asJson
        Write-Host ("`tComplete - ApplicationId={1}" -f $name, $newSp.appId)
        $existingSp = Invoke-AzCli "ad sp list --display-name $name" -asJson
        $spSecret = $newSp.password
    }
    else {
        Write-Host ("SPN '{0}' already exists - skipping" -f $existingSp.appDisplayName)
    }

    return $existingSp,$spSecret
}

function Ensure-CustomRole {
    # setup custom role
    $roleDefinition = [ordered]@{
        Name = $customRoleName
        Description = "Can manage SPN role assignments in $($azureAccount.name)"
        Actions = @(
            "Microsoft.Authorization/roleAssignments/read"
            "Microsoft.Authorization/roleAssignments/write"
            "Microsoft.Authorization/roleAssignments/delete"
        )
        NotActions = @()
        DataActions = @()
        NotDataActions = @()
        AssignableScopes = @(
            "/subscriptions/$($azureAccount.id)"
        )
    }

    $existingRole = Invoke-AzCli "role definition list --custom-role-only true --query `"[?roleName=='$customRoleName']`"" -asJson
    if ($null -eq $existingRole) {
        # role doesn't exist
        $roleJsonFile = New-TemporaryFile
        Set-Content -Path $roleJsonFile -Value ($roleDefinition | ConvertTo-Json)
        Write-Host "Registering new custom role definition..."
        Invoke-AzCli ("role definition create --role-definition `"@{0}`"" -f $roleJsonFile)
        Remove-Item $roleJsonFile
        $existingRole = Invoke-AzCli "role definition list --custom-role-only --query `"[?roleName=='$customRoleName']`"" -asJson
        Write-Host ("`tComplete - RoleId={0}" -f $existingRole.name)
    }
    else {
        Write-Host ("Custom role definition '{0}' already exists - skipping" -f $existingRole.roleName)
    }

    return $existingRole
}

function Ensure-RolePermissions {
    # assign the custom role to the service principal
    $existingAssignment = Invoke-AzCli "role assignment list --assignee $($existingSp.appId)" -asJson
    if ( [array]($existingAssignment.roleDefinitionName) -inotcontains $customRoleName ) {
        Write-Host "Assigning new SPN to custom role..."
        $newAssignment = Invoke-AzCli "role assignment create --role $($existingRole.name) --assignee $($existingSp.appId) --scope /subscriptions/$($azureAccount.id)" -asJson
        Write-Host "`tComplete"
    }
    else {
        Write-Host "The SPN already has the required role assignment."
    }
}

function Ensure-GraphPermissions {

    # grant service principal graph access
    $requiredApiPermissions = @(
        "5778995a-e1bf-45b8-affa-663a9f3f4d04"      # readDirDataPermissionId
        "824c81eb-e3f8-4ee6-8f6d-de7f50d565b7"      # manageOwnAppsPermissionId
    )

    $updated = $false
    $existingApiPermissions = Invoke-AzCli "ad app permission list --id $($existingSp.appId)" -asJson
    foreach($apiPerm in $requiredApiPermissions) {
        if ( !$existingApiPermissions -or ([array]($existingApiPermissions.resourceAccess.id) -inotcontains $apiPerm) ) {
            $permArgs = @(
                "--id {0}" -f $existingSp.appId
                "--api 00000002-0000-0000-c000-000000000000"
                "--api-permissions $apiPerm=Role"
            )
            Write-Host ("Granting API permission: {0}" -f $apiPerm)
            Invoke-AzCli ("ad app permission add {0}" -f ($permArgs -join " "))
            Write-Host "`tComplete"
            $updated = $true
        }
        else {
            Write-Host ("API permission '{0}' already assigned - skipping" -f $apiPerm)
        }
    }

    if ($updated) {
        Write-Warning "An AAD admin will need to run:`n`taz ad app permission grant --id $($existingSp.appId) --api 00000002-0000-0000-c000-000000000000`nor consent the permissions in the Azure Portal"
    }
}

function Register-AdoServiceConnection {
    # register ADO service connection
    if ($existingSp -and !$spSecret) {
        Write-Warning "The service principal already existed - to proceed its password must be reset"
        Read-Host "Press <RETURN> to reset the password for the '$name' SPN or <CTRL-C> to cancel"

        $newSp = Invoke-AzCli "ad sp credential reset --name $($existingSp.appId)" -asJson
        $spSecret = $newSp.password
    }

    $env:AZURE_DEVOPS_EXT_AZURE_RM_SERVICE_PRINCIPAL_KEY = $spSecret
    $adoUrl = "https://dev.azure.com/{0}" -f $adoOrg
    $adoArgs = @(
        "--name $name"
        "--azure-rm-service-principal-id {0}" -f $existingSp.appId
        "--azure-rm-subscription-id {0}" -f $azureAccount.id
        "--azure-rm-subscription-name `"{0}`"" -f $azureAccount.name
        "--azure-rm-tenant-id {0}" -f $newSp.tenant
        "--organization `"$adoUrl`""
        "--project `"{0}`"" -f $adoProject
    )
    Write-Host "Registering new ADO Service Connection..."
    Invoke-AzCli ("devops service-endpoint azurerm create {0}" -f ($adoArgs -join ' '))
    Write-Host ("`tComplete - see {0}/{1}/_settings/adminservices" -f $adoUrl, $adoProject)
}

#
# Main entrypoint
#

try {
    $azureAccount = Ensure-AzCliLogin

    $banner = @"
*************************************************************
This scripts uses the Azure-CLI to:

1) Create a new custom role scoped to the current subscription that permits managing role assignments
2) Create a new SPN called '$name'
3) Assigns the above custom role to the new SPN
4) Grants the SPN permission to query the Azure Graph and create & manage new SPNs
5) Creates a new service connection in Azure DevOps called '$name' that uses the above SPN
*************************************************************

*** ACTIVE SUBSCRIPTION: $($azureAccount.name) ***

"@

    Write-Host $banner
    Read-Host "Press <RETURN> to continue or <CTRL-C> to cancel"

    $customRoleName = "Assign Roles to SPN ($($azureAccount.id))"
    $existingRole = Ensure-CustomRole

    $existingSp,$spSecret = Ensure-Spn
    Ensure-RolePermissions
    Ensure-GraphPermissions

    Register-AdoServiceConnection
}
catch {
    Write-Warning $_.ScriptStackTrace
    Write-Warning $_.InvocationInfo.PositionMessage
    Write-Error $_.Exception.Message
}





