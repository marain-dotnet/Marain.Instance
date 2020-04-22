function Set-AppServiceCommonService
{
    [CmdletBinding()]
    param
    (
        $AppKey,
        $ClientAppSuffix = ''
    )

    $AppNameWithSuffix = '{0}{1}' -f $script:ServiceDeploymentContext.AppName, $ClientAppSuffix
    $script:DeploymentContext.InstanceApps[$AppKey] = $script:ServiceDeploymentContext.AppServices[$AppNameWithSuffix]
}