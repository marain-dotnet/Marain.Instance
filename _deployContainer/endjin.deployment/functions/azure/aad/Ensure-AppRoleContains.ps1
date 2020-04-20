function Ensure-AppRolesContain
{
    param
    (
        [string] $AppId,
        [string] $AppRoleId,
        [string] $DisplayName,
        [string] $Description,
        [string] $Value,
        [string[]] $AllowedMemberTypes
    )

    $AdApp = Get-AzADApplication -ApplicationId $AppId

    $AppRole = $null
    if ($AdApp.Manifest.appRoles.Length -gt 0) {
        $AppRole = $AdApp.Manifest.appRoles | Where-Object {$_.id -eq $AppRoleId}
    }
    if (-not $AppRole) {
        Write-Host "Adding $Value app role"

        $AppRole = @{
            displayName = $DisplayName
            id = $AppRoleId
            isEnabled = $true
            description = $Description
            value = $Value
            allowedMemberTypes = $AllowedMemberTypes
        }
        $AppRoles = $AdApp.Manifest.appRoles + $AppRole

        $PatchAppRoles = @{appRoles=$AppRoles}
        $PatchAppRolesJson = ConvertTo-Json $PatchAppRoles -Depth 4
        $Response = Invoke-WebRequest -Uri $AdApp.GraphApiAppUri -Method "PATCH" -Headers $AdApp.InstanceDeploymentContext.GraphHeaders -Body $PatchAppRolesJson
        $Response = Invoke-WebRequest -Uri $AdApp.GraphApiAppUri -Headers $AdApp.InstanceDeploymentContext.GraphHeaders
        $AdApp.Manifest = ConvertFrom-Json $Response.Content
    }
}