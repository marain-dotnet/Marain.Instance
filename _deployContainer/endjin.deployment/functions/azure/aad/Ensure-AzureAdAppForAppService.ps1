function Ensure-AzureAdAppForAppService
{
    [CmdletBinding()]
    param (
        [Hashtable] $ServiceDeploymentContext
        # [string] $AppNameSuffix
    )

    $AppNameWithSuffix = $ServiceDeploymentContext.AppName #+ $AppNameSuffix

    $AdAppForAppService = @{
        Application = $null
        Principal = $null
    }

    if (-not $ServiceDeploymentContext.DeploymentContext.GraphHeaders) {
        $AppId = $ServiceDeploymentContext.DeploymentContext.AadAppIds[$AppNameWithSuffix]
        if (-not $AppId) {
            Write-Error "AppId for $AppNameWithSuffix was not supplied in AadAppIds argument, and access to the Azure AD graph is not available (which it will not be when running on a build agent). Either run this in a context where graph access is available, or pass this app id in as an argument." 
        }
        # $adApp = [AzureAdApp]::new($ServiceDeploymentContext.DeploymentContext, $AppId)
        $adApp = Get-AzADApplication -ApplicationId $AppId
        # $ServiceDeploymentContext.AdApps += @{ $AppNameWithSuffix = $adApp }
        $ServiceDeploymentContext.AdApps[$AppNameWithSuffix] = $adApp
        Write-Host ("AppId for {0} ({1}) is {2}" -f $AppNameWithSuffix, $AppNameWithSuffix, $AppId)
        
        $AdAppForAppService.Application =  $adApp
        return $AdAppForAppService
    }

    $EasyAuthCallbackTail = ".auth/login/aad/callback"

    $AppDisplayName = $AppNameWithSuffix + '.azurewebsites.net'
    $AppUri = "https://" + $AppDisplayName

    # When we add APIM support, this would need to use the public-facing service root, assuming
    # we still actually want callback URI support.
    $ReplyUrls = @(($AppUri + $EasyAuthCallbackTail))
    # $app = $ServiceDeploymentContext.FindOrCreateAzureAdApp($AppNameWithSuffix, $AppUri, $ReplyUrls)
    $app = Ensure-AzureAdApp -DisplayName $AppDisplayName `
                             -AppUri $AppUri `
                             -ReplyUrls $ReplyUrls

    Write-Host ("AppId for {0} ({1}) is {2}" -f $AppNameWithSuffix, $AppDisplayName, $app.ApplicationId)
    $ServiceDeploymentContext.AdApps[$AppNameWithSuffix] = $app
    $AdAppForAppService.Application = $app

    $Principal = Get-AzAdServicePrincipal -ApplicationId $app.ApplicationId
    if (-not $Principal)
    {
        New-AzAdServicePrincipal -ApplicationId $app.ApplicationId -DisplayName $AppDisplayName
    }

    $GraphApiAppId = "00000002-0000-0000-c000-000000000000"
    $SignInAndReadProfileScopeId = "311a71cc-e848-46a1-bdf8-97ff7156d8e6"
    # $app.EnsureRequiredResourceAccessContains(
    #                         $GraphApiAppId,
    #                         @([ResourceAccessDescriptor]::new($SignInAndReadProfileScopeId, "Scope"))
    #                     )

    $AdAppForAppService.Principal = $Principal
    
    return $AdAppForAppService
}