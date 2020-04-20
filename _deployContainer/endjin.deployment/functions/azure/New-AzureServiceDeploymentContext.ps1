function New-AzureServiceDeploymentContext
{
    [CmdletBinding()]
    param
    (
        $DeploymentContext,
        $ServiceApiSuffix,
        $ServiceShortName,
        $GitHubRelease,
        $TempFolder
    )

    $internalContext = [MarainServiceDeploymentContext]::new($this, $ServiceApiSuffix, $ServiceShortName, $GitHubRelease, $TempFolder)

    $context = @{
        DeploymentContext = $DeploymentContext
        GitHubRelease = $GitHubRelease
        TempFolder = $TempFolder

        AppNameRoot = $ServiceShortName.ToLower()
        AppName = $DeploymentContext.Prefix + $DeploymentContext.EnvironmentSuffix + $this.AppNameRoot
        AppServices = $internalContext.AppServices
        AdApps = $internalContext.AdApps
    }

    return $context
}