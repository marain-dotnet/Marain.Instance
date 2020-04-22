function New-AzureServiceDeploymentContext
{
    [CmdletBinding()]
    param
    (
        $ServiceApiSuffix,
        $ServiceShortName,
        $GitHubRelease,
        $TempFolder
    )

    $AppName = '{0}{1}{2}' -f $script:DeploymentContext.Prefix, $script:DeploymentContext.EnvironmentSuffix, $ServiceShortName.ToLower()
        
    $script:ServiceDeploymentContext = @{
        DeploymentContext = $script:DeploymentContext
        GitHubRelease = 'foo'
        TempFolder = 'foo'

        AppNameRoot = $ServiceShortName.ToLower()
        AppName = $AppName
        AppServices = @{}
        AdApps = @{}
    }
}