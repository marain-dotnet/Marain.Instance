#Requires -Version 6.0
#Requires -Modules Microsoft.PowerShell.Archive

Param(
    [string] [Parameter(Mandatory=$true)] $AzureLocation,
    [string] [Parameter(Mandatory=$true)] $EnvironmentSuffix,
    [string] [Parameter(Mandatory=$true)] $InstanceManifestPath,
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

class MarainInstanceDeploymentContext {
    MarainInstanceDeploymentContext(
        [string]$AzureLocation,
        [string]$EnvironmentSuffix,
        [string]$Prefix,
        [string]$AadTenantId,
        [string]$SubscriptionId,
        [Hashtable]$AadAppIds,
        [bool]$DoNotUseGraph
        )
    {
        $this.AzureLocation = $AzureLocation
        $this.Prefix = $Prefix.ToLower()
        $this.EnvironmentSuffix = $EnvironmentSuffix.ToLower()
        $this.TenantId = $AadTenantId
        $this.SubscriptionId = $SubscriptionId
        $this.AadAppIds = $AadAppIds

        # Note, we're using the Az module here.
        # If this fails ensure you run:
        #   Connect-AzAccount
        # and if that is unavailable, do this first:
        #   Install-Module Az
        if (-not $DoNotUseGraph) {
            $AzContext = Get-AzContext
            $AadGraphApiResourceId = "https://graph.windows.net/"

            $GraphToken = $AzContext.TokenCache.ReadItems() | Where-Object { $_.TenantId -eq $this.TenantId -and $_.Resource -eq $AadGraphApiResourceId }
            if ($GraphToken) {
                $AuthToken = $GraphToken.AccessToken
                $AuthHeaderValue = "Bearer $AuthToken"
                $this.GraphHeaders = @{"Authorization" = $AuthHeaderValue; "Content-Type"="application/json"}
            }
        }

        $this.DeploymentStagingStorageAccountName = ('stage' + $AzureLocation + $this.SubscriptionId).Replace('-', '').substring(0, 24)
    }

    [string]$AzureLocation
    [string]$Prefix
    [string]$EnvironmentSuffix
    [string]$AppNameRoot
    [string]$AppName

    [string]$TenantId
    [hashtable]$GraphHeaders
    [string]$SubscriptionId
    [Hashtable]$AadAppIds

    [string]$DeploymentStagingStorageAccountName

    [string]$ApplicationInsightsInstrumentationKey

    [MarainServiceDeploymentContext]CreateServiceDeploymentContext (
        [string]$ServiceApiSuffix,
        [string]$ServiceShortName,
        [object]$GitHubRelease,
        [string]$TempFolder
    )
    {
        return [MarainServiceDeploymentContext]::new(
            $this, $ServiceApiSuffix, $ServiceShortName, $GitHubRelease, $TempFolder)
    }

    [string]MakeResourceGroupName([string]$ShortName) {
         return ("{0}.{1}.{2}" -f $this.Prefix, $ShortName, $this.EnvironmentSuffix)
    }

    [object]DeployArmTemplate(
        [string]$ArtifactsFolderPath,
        [string]$TemplateFileName,
        [Hashtable]$TemplateParameters,
        [string]$ResourceGroupName
    )
    {
        $ArmTemplatePath = Join-Path $ArtifactsFolderPath $TemplateFileName -Resolve
        $OptionalParameters = @{marainPrefix=$this.Prefix;environmentSuffix=$this.EnvironmentSuffix}

        $ArtifactsLocationName = '_artifactsLocation'
        $ArtifactsLocationSasTokenName = '_artifactsLocationSasToken'
    
        $StorageResourceGroupName = 'ARM_Deploy_Staging'
        $StorageContainerName = $ResourceGroupName.ToLowerInvariant().Replace(".", "") + '-stageartifacts'

        $StorageAccount = Get-AzStorageAccount -ResourceGroupName $StorageResourceGroupName -Name $this.DeploymentStagingStorageAccountName -ErrorAction SilentlyContinue

        # Create the storage account if it doesn't already exist
        if ($StorageAccount -eq $null) {
            New-AzResourceGroup -Location $this.AzureLocation -Name $StorageResourceGroupName -Force
            $StorageAccount = New-AzStorageAccount -StorageAccountName $this.DeploymentStagingStorageAccountName  -Type 'Standard_LRS' -ResourceGroupName $StorageResourceGroupName -Location $this.AzureLocation
        }

        # Copy files from the local storage staging location to the storage account container
        New-AzStorageContainer -Name $StorageContainerName -Context $StorageAccount.Context -ErrorAction SilentlyContinue *>&1

        $ArtifactFilePaths = Get-ChildItem $ArtifactsFolderPath -Recurse -File | ForEach-Object -Process {$_.FullName}
        foreach ($SourcePath in $ArtifactFilePaths) {
            Set-AzStorageBlobContent `
                -File $SourcePath `
                -Blob $SourcePath.Substring($ArtifactsFolderPath.length + 1) `
                -Container $StorageContainerName `
                -Context $StorageAccount.Context `
                -Force
        }

        $OptionalParameters[$ArtifactsLocationName] = $StorageAccount.Context.BlobEndPoint + $StorageContainerName
        # Generate a 4 hour SAS token for the artifacts location if one was not provided in the parameters file
        $StagingSasToken = New-AzStorageContainerSASToken `
            -Name $StorageContainerName `
            -Context $StorageAccount.Context `
            -Permission r `
            -ExpiryTime (Get-Date).AddHours(4)
        $OptionalParameters[$ArtifactsLocationSasTokenName] = ConvertTo-SecureString -AsPlainText -Force $StagingSasToken

        # Create the resource group only when it doesn't already exist
        if ((Get-AzResourceGroup -Name $ResourceGroupName -Location $this.AzureLocation -Verbose -ErrorAction SilentlyContinue) -eq $null) {
            New-AzResourceGroup -Name $ResourceGroupName -Location $this.AzureLocation -Verbose -Force -ErrorAction Stop
        }

        $DeploymentResult = New-AzResourceGroupDeployment `
            -Name ((Get-ChildItem $ArmTemplatePath).BaseName + '-' + ((Get-Date).ToUniversalTime()).ToString('MMdd-HHmm')) `
            -ResourceGroupName $ResourceGroupName `
            -TemplateFile $ArmTemplatePath `
            @OptionalParameters `
            @TemplateParameters `
            -Force -Verbose `
            -ErrorVariable ErrorMessages

        return $DeploymentResult
    }
}

class MarainServiceDeploymentContext {
    MarainServiceDeploymentContext(
        [MarainInstanceDeploymentContext]$InstanceContext,
        [string]$ServiceApiSuffix,
        [string]$ServiceShortName,
        [object]$GitHubRelease,
        [string]$TempFolder)
    {
        $this.InstanceContext = $InstanceContext
        $this.GitHubRelease = $GitHubRelease
        $this.TempFolder = $TempFolder

        $this.AppNameRoot = $ServiceShortName.ToLower()
        $this.AppName = $this.InstanceContext.Prefix + $this.InstanceContext.EnvironmentSuffix + $this.AppNameRoot

        $this.Variables = @{}
    }

    [MarainInstanceDeploymentContext]$InstanceContext
    [string]$AppNameRoot
    [string]$AppName
    [object]$GitHubRelease
    [string]$TempFolder

    # Enables early stages of deployment to pass information to later ones. E.g., app ids
    # determined prior to ARM deployment can be passed to the ARM deployment stage
    [Hashtable]$Variables

    [AzureAdApp]FindOrCreateAzureAdApp(
        [string]$DisplayName,
        [string]$appUri,
        [string[]]$replyUrls)
    {
        Write-Host "`nEnsuring Azure AD application {$DisplayName} exists" -ForegroundColor Green

        $app = Get-AzADApplication -DisplayNameStartWith $DisplayName | Where-Object {$_.DisplayName -eq $DisplayName}
        if ($app) {
            Write-Host "Found existing app with id $($app.ApplicationId)"
            $ReplyUrlsOk = $true
            ForEach ($ReplyUrl in $replyUrls) {
                if (-not $app.ReplyUrls.Contains($ReplyUrl)) {
                    $ReplyUrlsOk = $false
                    Write-Host "Reply URL $ReplyUrl not present in app"
                }
            }
    
            if (-not $ReplyUrlsOk) {
                Write-Host "Setting reply URLs: $replyUrls"
                $app = Update-AzADApplication -ObjectId $app.ObjectId -ReplyUrl $replyUrls
            }
        } else {
            $app = New-AzADApplication -DisplayName $DisplayName -IdentifierUris $appUri -HomePage $appUri -ReplyUrls $replyUrls
            Write-Host "Created new app with id $($app.ApplicationId)"
        }

        return [AzureAdAppWithGraphAccess]::new($this, $app.ApplicationId, $app.ObjectId)
    }

    [AzureAdApp]DefineAzureAdAppForAppService(
        [string] $AppNameSuffix,
        [string] $AppIdKey
    )
    {
        $AppNameWithSuffix = $this.AppName + $AppNameSuffix

        if (-not $this.InstanceContext.GraphHeaders) {
            $AppId = $this.InstanceContext.AadAppIds[$AppIdKey]
            if (-not $AppId) {
                Write-Error ("AppId for {0} ({1}) was not supplied in AadAppIds argument, and access to the Azure AD graph is not available (which it will not be when running on a build agent). Either run this in a context where graph access is available, or pass this app id in as an argument." -f $AppNameSuffix, $AppId)
            }
            $this.Variables[$AppIdKey] = $AppId
            Write-Host ("AppId for {0} ({1}) is {2}" -f $AppNameWithSuffix, $AppIdKey, $AppId)
            return [AzureAdApp]::new($this, $AppId)
        }

        $EasyAuthCallbackTail = ".auth/login/aad/callback"

        $AppUri = "https://" + $AppNameWithSuffix + ".azurewebsites.net/"

        # When we add APIM support, this would need to use the public-facing service root, assuming
        # we still actually want callback URI support.
        $ReplyUrls = @(($AppUri + $EasyAuthCallbackTail))
        $app = $this.FindOrCreateAzureAdApp($AppNameWithSuffix, $AppUri, $ReplyUrls)
        Write-Host ("AppId for {0} ({1}) is {2}" -f $AppNameWithSuffix, $AppIdKey, $app.AppId)
        $this.Variables[$AppIdKey] = $app.AppId

        $Principal = Get-AzAdServicePrincipal -ApplicationId $app.AppId
        if (-not $Principal)
        {
            New-AzAdServicePrincipal -ApplicationId $app.AppId -DisplayName $AppNameWithSuffix
        }

        $GraphApiAppId = "00000002-0000-0000-c000-000000000000"
        $SignInAndReadProfileScopeId = "311a71cc-e848-46a1-bdf8-97ff7156d8e6"
        $app.EnsureRequiredResourceAccessContains($GraphApiAppId, @([ResourceAccessDescriptor]::new($SignInAndReadProfileScopeId, "Scope")))

        return $app
    }


    UploadReleaseAssetAsAppServiceSitePackage(
        [string]$AssetName,
        [string]$AppServiceName)
    {
        $WebApp = Get-AzWebApp -Name $AppServiceName
        $ReleaseAssets = $this.GitHubRelease.assets | Where-Object  { $_.name -eq $AssetName }
        if ($ReleaseAssets.Count -ne 1) {
            Write-Error ("Expecting exactly one asset named {0}, found {1}" -f $AssetName, $ReleaseAssets.Count)
        }
        $ReleaseAsset = $ReleaseAssets[0]
        $url = $ReleaseAsset.browser_download_url
        $AssetPath = Join-Path $this.TempFolder $AssetName
        Invoke-WebRequest -Uri $url -OutFile $AssetPath
        Publish-AzWebApp `
            -Force `
            -ArchivePath $AssetPath `
            -WebApp $WebApp
    }
}

class ResourceAccessDescriptor {
    ResourceAccessDescriptor(
        [string]$id,
        [string]$type) {
        $this.Id = $id
        $this.Type = $type
    }

    [string]$Id
    [string]$Type
}

class AzureAdApp {
    AzureAdApp(
        [MarainServiceDeploymentContext] $ServiceDeploymentContext,
        [string]$appId) {

        $this.InstanceDeploymentContext = $ServiceDeploymentContext.InstanceContext
        $this.AppId = $appId
    }

    [string]$AppId
    [MarainInstanceDeploymentContext]$InstanceDeploymentContext

    # If these base class methods get invoked, it means we're running in the mode
    # where we don't have permission to do anything with Graph API, and just have
    # to presume it was all set up already.
    # When we do have access to the Graph (e.g. because the script is being run
    # locally) these will be overridden.

    EnsureRequiredResourceAccessContains(
        [string]$ResourceId,
        [ResourceAccessDescriptor[]] $accessRequirements)
    {
    }

    EnsureAppRolesContain(
        [string] $AppRoleId,
        [string] $DisplayName,
        [string] $Description,
        [string] $Value,
        [string[]] $AllowedMemberTypes)
    {
    }
}

class AzureAdAppWithGraphAccess : AzureAdApp {
    AzureAdAppWithGraphAccess(
        [MarainServiceDeploymentContext] $ServiceDeploymentContext,
        [string]$appId,
        [string]$objectId) : base($ServiceDeploymentContext, $appId) {

        $this.ObjectId = $objectId

        $this.GraphApiAppUri = ("https://graph.windows.net/{0}/applications/{1}?api-version=1.6" -f $this.InstanceDeploymentContext.TenantId, $objectId)
        $Response = Invoke-WebRequest -Uri $this.GraphApiAppUri -Headers $this.InstanceDeploymentContext.GraphHeaders
        $this.Manifest = ConvertFrom-Json $Response.Content
    }

    [string]$ObjectId
    [string]$GraphApiAppUri
    $Manifest

    EnsureRequiredResourceAccessContains(
        [string]$ResourceId,
        [ResourceAccessDescriptor[]] $accessRequirements)
    {
        $MadeChange = $false
        $RequiredResourceAccess = $this.Manifest.requiredResourceAccess
        $ResourceEntry = $RequiredResourceAccess | Where-Object {$_.resourceAppId -eq $ResourceId }
        if (-not $ResourceEntry) {
            $MadeChange = $true
            $ResourceEntry = @{resourceAppId=$ResourceId;resourceAccess=@()}
            $RequiredResourceAccess += $ResourceEntry
        }
        
        foreach ($access in $accessRequirements) {
            $RequiredAccess = $ResourceEntry.resourceAccess| Where-Object {$_.id -eq $access.Id -and $_.type -eq $access.Type}
            if (-not $RequiredAccess) {
                Write-Host "Adding '$ResourceId : $($access.id)' required resource access"
        
                $RequiredAccess = @{id=$access.Id;type="Scope"}
                $ResourceEntry.resourceAccess += $RequiredAccess
                $MadeChange = $true
            }
        }

        if ($MadeChange) {
            $PatchRequiredResourceAccess = @{requiredResourceAccess=$RequiredResourceAccess}
            $PatchRequiredResourceAccessJson = ConvertTo-Json $PatchRequiredResourceAccess -Depth 4
            $Response = Invoke-WebRequest -Uri $this.GraphApiAppUri -Method "PATCH" -Headers $this.InstanceDeploymentContext.GraphHeaders -Body $PatchRequiredResourceAccessJson
            $Response = Invoke-WebRequest -Uri $this.GraphApiAppUri -Headers $this.InstanceDeploymentContext.GraphHeaders
            $this.Manifest = ConvertFrom-Json $Response.Content
        }
    }

    EnsureAppRolesContain(
        [string] $AppRoleId,
        [string] $DisplayName,
        [string] $Description,
        [string] $Value,
        [string[]] $AllowedMemberTypes)
    {
        $AppRole = $null
        if ($this.Manifest.appRoles.Length -gt 0) {
            $AppRole = $this.Manifest.appRoles | Where-Object {$_.id -eq $AppRoleId}
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
            $AppRoles = $this.Manifest.appRoles + $AppRole
    
            $PatchAppRoles = @{appRoles=$AppRoles}
            $PatchAppRolesJson = ConvertTo-Json $PatchAppRoles -Depth 4
            $Response = Invoke-WebRequest -Uri $this.GraphApiAppUri -Method "PATCH" -Headers $this.InstanceDeploymentContext.GraphHeaders -Body $PatchAppRolesJson
            $Response = Invoke-WebRequest -Uri $this.GraphApiAppUri -Headers $this.InstanceDeploymentContext.GraphHeaders
            $this.Manifest = ConvertFrom-Json $Response.Content
        }
    }
}

function ParseJsonC([string] $path) {
    # As of PowerShell 6, ConvertFrom-Json handles comments in JSON out of the box, so this is now
    # just a helper for loading JSON or JSONC from a path.
    return (Get-Content $path -raw) | ConvertFrom-Json
}

$MarainServicesPath = Join-Path -Resolve $PSScriptRoot "../MarainServices.jsonc"
$MarainServices = ParseJsonC $MarainServicesPath

# Looks like PowerShell doesn't have a direct equivalent to .NET's ability to combine two paths
# in a way that just ignores the first path if the second is absolute
$InstanceManifestPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, $InstanceManifestPath))
$InstanceManifest = ParseJsonC $InstanceManifestPath

# Check we've got an entry for each known service.
ForEach ($kv in $MarainServices.PSObject.Properties) {
    $MarainServiceName = $kv.Name
    if (-not (Get-Member -InputObject $InstanceManifest.services -name $MarainServiceName)) {
        Write-Error "Instance manifest does not contain an entry for $MarainServiceName. (Define an entry setting \"omit\":true if you don't want to deploy this service)"
    }
}

$InstanceDeploymentContext = [MarainInstanceDeploymentContext]::new(
    $AzureLocation,
    $EnvironmentSuffix,
    "mar",
    $AadTenantId,
    $SubscriptionId,
    $AadAppIds,
    $DoNotUseGraph)

$InstanceResourceGroupName = $InstanceDeploymentContext.MakeResourceGroupName("instance")

if (-not $AadOnly -and (-not $SkipInstanceDeploy)) {
    if ((-not $SingleServiceToDeploy) -or ($SingleServiceToDeploy -eq 'Marain.Instance')) {
        Write-Host "Deploying shared Marain infrastructure"

        $DeploymentResult = $InstanceDeploymentContext.DeployArmTemplate($PSScriptRoot, "azuredeploy.json", @{}, $InstanceResourceGroupName)

        $InstanceDeploymentContext.ApplicationInsightsInstrumentationKey = $DeploymentResult.Outputs.instrumentationKey.Value
        Write-Host "Shared Marain infrastructure deployment complete"
    }
}
if (-not $InstanceDeploymentContext.ApplicationInsightsInstrumentationKey -and (-not $AadOnly)) {
    $AiName = ("{0}{1}ai" -f $InstanceDeploymentContext.Prefix, $InstanceDeploymentContext.EnvironmentSuffix)
    $Ai = Get-AzApplicationInsights -ResourceGroupName $InstanceResourceGroupName -Name $AiName
    $InstanceDeploymentContext.ApplicationInsightsInstrumentationKey = $Ai.InstrumentationKey
}

ForEach ($kv in $MarainServices.PSObject.Properties) {
    $MarainServiceName = $kv.Name
    $MarainService = $kv.Value

    if ((-not $SingleServiceToDeploy) -or ($SingleServiceToDeploy -eq $MarainServiceName)) {
        $ServiceManifestEntry = $InstanceManifest.services.$MarainServiceName
        Write-Host "Starting infrastructure deployment for $MarainServiceName"
        $GitHubProject = $MarainService.gitHubProject
        Write-Host " GitHub project $GitHubProject"
        $ReleaseVersion = $ServiceManifestEntry.release
        Write-Host " Release version $ReleaseVersion"

        $ReleaseUrl = "https://api.github.com/repos/{0}/releases/tags/{1}" -f $GitHubProject, $ReleaseVersion
        $ReleaseResponse = Invoke-WebRequest -Uri $ReleaseUrl
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
                Invoke-WebRequest -Uri $url -OutFile $ZipPath
                Expand-Archive $ZipPath -DestinationPath $DeploymentPackageDir

                # We create a new one of these for each deployment ZIP even though
                # the settings are the same across each one in the service, because
                # service-specific deployment scripts can add values to the
                # context's Variables, so we need a new one each time to maintain
                # isolation
                $ServiceDeploymentContext = $InstanceDeploymentContext.CreateServiceDeploymentContext(
                    $MarainService.apiPrefix,
                    $MarainService.apiPrefix,
                    $Release,
                    $TempDir)

                # This nested function enables us to . source each service's scripts. When
                # the nested function exits, everything it . sourced goes out of scope.
                Function LoadAndRun([string] $scriptName) {
                    if ($DeploymentAssetLocalOverrides -and $DeploymentAssetLocalOverrides.ContainsKey($MarainServiceName)) {
                        $ScriptPath = Join-Path $DeploymentAssetLocalOverrides[$MarainServiceName] $scriptName
                    } else {
                        $ScriptPath = Join-Path $DeploymentPackageDir $scriptName
                    }
                    if (Test-Path $ScriptPath) {
                        . $ScriptPath
                        MarainDeployment $ServiceDeploymentContext
                    }
                }

                LoadAndRun "Marain-PreDeploy.ps1"
                if (-not $AadOnly) {
                    LoadAndRun "Marain-ArmDeploy.ps1"
                    LoadAndRun "Marain-PostDeploy.ps1"
                }

            } finally {
                Remove-Item -Recurse $TempDir
            }
        }
    }
}