#Requires -Version 6.0
#Requires -Modules Microsoft.PowerShell.Archive

Param(
    [string] [Parameter(Mandatory=$true)] $AzureLocation,
    [string] [Parameter(Mandatory=$true)] $EnvironmentSuffix,
    # [string] [Parameter(Mandatory=$true)] $InstanceManifestPath,
    [string] [Parameter(Mandatory=$true)] $AadTenantId,
    [string] [Parameter(Mandatory=$true)] $SubscriptionId,
    [Hashtable] $AadAppIds = @{},
    [switch] $AadOnly,
    [switch] $SkipInstanceDeploy,
    [switch] $DoNotUseGraph, # Used for debugging to simulate the lack of access to the graph we get in ADO
    [string] $ResourceGroupNameRoot = "Marain",
    [string] $SingleServiceToDeploy, # Normally we deploy everything, but set this to deploy just one particular service's infrastructure
    [Hashtable] $DeploymentAssetLocalOverrides = @{}
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 4

$here = Split-Path -Parent $PSCommandPath


if (!$MarainServices -or $MarainServices.Keys.Count -eq 0) {
    Write-Error 'Missing Marain Services configuration'
}
$MarainServices.Keys | Where-Object {
    $_ -and $InstanceManifest.services.Keys -inotcontains $_ } | ForEach-Object {
            Write-Error "Instance manifest does not contain an entry for $_. (Define an entry setting `"omit`":true if you don't want to deploy this service)"
    }

$InstanceDeploymentContext = New-AzureDeploymentContext -AzureLocation $AzureLocation `
                                                        -EnvironmentSuffix $EnvironmentSuffix `
                                                        -Prefix "mar" `
                                                        -Name "instance" `
                                                        -AadTenantId $AadTenantId `
                                                        -SubscriptionId $SubscriptionId `
                                                        -AadAppIds $AadAppIds `
                                                        -DoNotUseGraph $DoNotUseGraph

if (-not $AadOnly -and (-not $SkipInstanceDeploy)) {
    if ((-not $SingleServiceToDeploy) -or ($SingleServiceToDeploy -eq 'Marain.Instance')) {
        Write-Host "Deploying shared Marain infrastructure"

        $DeploymentResult = DeployArmTemplate -ArtifactsFolderPath $here `
                                              -TemplateFileName 'azuredeploy.json' `
                                              -TemplateParameters @{} `
                                              -DeploymentContext $InstanceDeploymentContext

        $InstanceDeploymentContext.ApplicationInsightsInstrumentationKey = $DeploymentResult.Outputs.instrumentationKey.Value
        Write-Host "Shared Marain infrastructure deployment complete"
    }
}
if (-not $InstanceDeploymentContext.ApplicationInsightsInstrumentationKey -and (-not $AadOnly)) {
    $AiName = ("{0}{1}ai" -f $InstanceDeploymentContext.Prefix, $InstanceDeploymentContext.EnvironmentSuffix)
    $Ai = Get-AzApplicationInsights -ResourceGroupName $InstanceResourceGroupName -Name $AiName
    $InstanceDeploymentContext.ApplicationInsightsInstrumentationKey = $Ai.InstrumentationKey
}

ForEach ($key in $MarainServices.Keys) {
    $MarainServiceName = $key
    $MarainService = $MarainServices[$key]

    if ((-not $SingleServiceToDeploy) -or ($SingleServiceToDeploy -eq $MarainServiceName)) {
        $ServiceManifestEntry = $InstanceManifest.services.$MarainServiceName
        Write-Host "Starting infrastructure deployment for $MarainServiceName"
        $GitHubProject = $MarainService.gitHubProject
        Write-Host " GitHub project $GitHubProject"
        $ReleaseVersion = $ServiceManifestEntry.release
        Write-Host " Release version $ReleaseVersion"

        $ReleaseUrl = "https://api.github.com/repos/{0}/releases/tags/{1}" -f $GitHubProject, $ReleaseVersion
        Write-Host " Downloading from $ReleaseUrl..."
        $ReleaseResponse = Invoke-WebRequest -Uri $ReleaseUrl
        Write-Host " Download complete"
        $Release = ConvertFrom-Json $ReleaseResponse.Content
        $DeploymentAssets = $Release.assets | Where-Object  { $_.name.EndsWith(".Deployment.zip") }
        foreach ($asset in $DeploymentAssets) {
            Write-Host ("Processing asset {0}" -f $asset.name)
            $url = $asset.browser_download_url
            $TempDir = Join-Path $PSScriptRoot ("{0}-temp" -f $asset.name)
            $null = New-Item -Path $TempDir -ItemType Directory
            $DeploymentPackageDir = Join-Path $TempDir "DeploymentPackage"
            $null = New-Item -Path $DeploymentPackageDir -ItemType Directory
            try {
                $ZipPath = Join-Path $DeploymentPackageDir $asset.name

                if (-not ($DeploymentAssetLocalOverrides -and $DeploymentAssetLocalOverrides.ContainsKey($MarainServiceName))) {
                    Invoke-WebRequest -Uri $url -OutFile $ZipPath
                    Expand-Archive $ZipPath -DestinationPath $DeploymentPackageDir
                }

                # We create a new one of these for each deployment ZIP even though
                # the settings are the same across each one in the service, because
                # service-specific deployment scripts can add values to the
                # context's variables, so we need a new one each time to maintain
                # isolation
                $ServiceDeploymentContext = New-AzureServiceDeploymentContext -DeploymentContext $InstanceDeploymentContext `
                                                                              -ServiceApiSuffix $MarainService.apiPrefix `
                                                                              -ServiceShortName $MarainService.apiPrefix `
                                                                              -GitHubRelease $Release `
                                                                              -TempFolder $TempDir

                # This nested function enables us to . source each service's scripts. When
                # the nested function exits, everything it . sourced goes out of scope.
                Function LoadAndRun([string] $scriptName) {
                    if ($DeploymentAssetLocalOverrides -and $DeploymentAssetLocalOverrides.ContainsKey($MarainServiceName)) {
                        $ScriptPath = Join-Path $DeploymentAssetLocalOverrides[$MarainServiceName] $scriptName
                    } else {
                        $ScriptPath = Join-Path $DeploymentPackageDir $scriptName
                    }
                    if (Test-Path $ScriptPath) {
                        Write-Host " Running $scriptName"
                        . $ScriptPath
                        MarainDeployment $ServiceDeploymentContext
                    }
                }

                LoadAndRun "Marain-PreDeploy.ps1"
                if (-not $AadOnly) {
                    LoadAndRun "Marain-ArmDeploy.ps1"
                    LoadAndRun "Marain-PostDeployNoAad.ps1"

                    # This should go away. Now that we've split post-ARM-deployment steps
                    # clearly into with-AAD and not-AAD, we don't really want this ambiguously
                    # named script.
                    LoadAndRun "Marain-PostDeploy.ps1"
                }
                if (-not $DoNotUseGraph) {
                    LoadAndRun "Marain-PostDeployAad.ps1"                    
                }

            } finally {
                Remove-Item -Force -Recurse $TempDir
            }
        }
    }
}