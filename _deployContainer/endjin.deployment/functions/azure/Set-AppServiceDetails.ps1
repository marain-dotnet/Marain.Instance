function Set-AppServiceDetails
{
    [CmdletBinding()]
    param
    (
        $ServicePrincipalId,
        $ClientAppSuffix = '',
        $BaseUrl = $null
    )

    $AppName = $script:ServiceDeploymentContext.AppName
    $AppNameWithSuffix = '{0}{1}' -f $AppName, $ClientAppSuffix
    
    $script:ServiceDeploymentContext.AppServices[$AppName] = @{
                            AuthAppId = $script:ServiceDeploymentContext.AdApps[$AppNameWithSuffix].ApplicationId.ToString()
                            ServicePrincipalId = $ServicePrincipalId
                            BaseUrl = $BaseUrl
                        }
}