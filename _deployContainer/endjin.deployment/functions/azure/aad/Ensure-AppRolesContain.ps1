function Ensure-AppRolesContain
{
    [CmdletBinding()]
    param
    (
        [string] $AppId,
        [string] $AppRoleId,
        [string] $DisplayName,
        [string] $Description,
        [string] $Value,
        [string[]] $AllowedMemberTypes
    )
    
    if (-not $script:DeploymentContext.GraphHeaders)
    {
        return $false
    }

    $AdApp = Get-AzADApplication -ApplicationId $AppId
    # $null,$AdApp = Invoke-AzCli -Command "ad app show --id $AppId" -TreatAsJson

    $GraphApiAppUri = ("https://graph.windows.net/{0}/applications/{1}?api-version=1.6" -f $script:DeploymentContext.TenantId, $AdApp.ObjectId)
    $Response = Invoke-WebRequest -Uri $GraphApiAppUri -Headers $script:DeploymentContext.GraphHeaders
    $appManifest = ConvertFrom-Json $Response.Content

    $AppRole = $null
    if ($appManifest.appRoles.Length -gt 0) {
        $AppRole = $appManifest.appRoles | Where-Object {$_.id -eq $AppRoleId}
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
        $AppRoles = $appManifest.appRoles + $AppRole

        $PatchAppRoles = @{appRoles=$AppRoles}
        $PatchAppRolesJson = ConvertTo-Json $PatchAppRoles -Depth 4
        $Response = Invoke-WebRequest -Uri $GraphApiAppUri -Method "PATCH" -Headers $script:DeploymentContext.GraphHeaders -Body $PatchAppRolesJson
        $Response = Invoke-WebRequest -Uri $GraphApiAppUri -Headers $script:DeploymentContext.GraphHeaders
        # $AdApp.Manifest = ConvertFrom-Json $Response.Content
    }

    return $true
}