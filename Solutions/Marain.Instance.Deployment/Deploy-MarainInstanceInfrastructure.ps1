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

$marainGlobalToolName = 'marain'
$marainGlobalToolVersion = '0.1.0-cli-as-global-tool.21'

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
        $this.InstanceApps = @{}
        $this.DoNotUseGraph = $DoNotUseGraph

        # Note, we're using the Az module here.
        # If this fails ensure you run:
        #   Connect-AzAccount
        # and if that is unavailable, do this first:
        #   Install-Module Az
        if (-not $DoNotUseGraph) {
            $AzContext = Get-AzContext
            $AadGraphApiResourceId = "https://graph.windows.net/"

            # service principals with a graph tokens appear unassociated with a tenant
            $GraphToken = $AzContext.TokenCache.ReadItems() | Where-Object { (!($_.TenantId) -or $_.TenantId -eq $this.TenantId) -and $_.Resource -eq $AadGraphApiResourceId }
            if ($GraphToken) {
                $AuthToken = $GraphToken.AccessToken
                $AuthHeaderValue = "Bearer $AuthToken"
                $this.GraphHeaders = @{"Authorization" = $AuthHeaderValue; "Content-Type"="application/json"}
            }
            else {
                Write-Host "No graph token available. AAD operations will not be performed."
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
    [Hashtable]$InstanceApps
    [bool]$DoNotUseGraph

    [string]$DeploymentStagingStorageAccountName

    [string]$ApplicationInsightsInstrumentationKey
    [string]$KeyVaultName
    [string]$TenantAdminAppId
    [string]$TenantAdminObjectId
    [string]$TenantAdminSecret
    [string]$DeploymentUserObjectId

    [string]$MarainCliPath

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

    [MarainAppService]GetCommonAppService([string]$AppKey)
    {
        return $this.InstanceApps[$AppKey]
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
    }

    [MarainInstanceDeploymentContext]$InstanceContext
    [string]$AppNameRoot
    [string]$AppName
    [object]$GitHubRelease
    [string]$TempFolder
    [Hashtable]$AppServices = @{}
    [Hashtable]$AdApps = @{}

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

    [AzureAdApp]DefineAzureAdAppForAppService()
    {
        return $this.DefineAzureAdAppForAppService("")
    }

    [AzureAdApp]DefineAzureAdAppForAppService([string] $AppNameSuffix)
    {
        $AppNameWithSuffix = $this.AppName + $AppNameSuffix

        if (-not $this.InstanceContext.GraphHeaders) {
            $AppId = $this.InstanceContext.AadAppIds[$AppNameWithSuffix]
            if (-not $AppId) {
                Write-Error "AppId for $AppNameWithSuffix was not supplied in AadAppIds argument, and access to the Azure AD graph is not available (which it will not be when running on a build agent). Either run this in a context where graph access is available, or pass this app id in as an argument." 
            }
            $adApp = [AzureAdApp]::new($this, $AppId)
            $this.AdApps[$AppNameWithSuffix] = $adApp
            Write-Host ("AppId for {0} ({1}) is {2}" -f $AppNameWithSuffix, $AppNameWithSuffix, $AppId)
            return $adApp
        }

        $EasyAuthCallbackTail = ".auth/login/aad/callback"

        $AppUri = "https://" + $AppNameWithSuffix + ".azurewebsites.net/"

        # When we add APIM support, this would need to use the public-facing service root, assuming
        # we still actually want callback URI support.
        $ReplyUrls = @(($AppUri + $EasyAuthCallbackTail))
        $app = $this.FindOrCreateAzureAdApp($AppNameWithSuffix, $AppUri, $ReplyUrls)
        Write-Host ("AppId for {0} ({1}) is {2}" -f $AppNameWithSuffix, $AppNameWithSuffix, $app.AppId)
        $this.AdApps[$AppNameWithSuffix] = $app

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

    [string]GetAppId()
    {
        return $this.GetAppId("")
    }

    [string]GetAppId([string] $AppNameSuffix)
    {
        $AppNameWithSuffix = $this.AppName + $AppNameSuffix
        [AzureAdApp]$AdApp = $this.AdApps[$AppNameWithSuffix]
        return $AdApp.AppId
    }

    MakeAppServiceCommonService([string]$AppKey)
    {
        $this.MakeAppServiceCommonService($AppKey, "")
    }

    MakeAppServiceCommonService(
        [string]$AppKey,
        [string]$ClientAppSuffix
        )
    {
        $AppNameWithSuffix = $this.AppName + $ClientAppSuffix
        $this.InstanceContext.InstanceApps[$AppKey] = $this.AppServices[$AppNameWithSuffix]
    }

    SetAppServiceDetails([string]$ServicePrincipalId)
    {
        $this.SetAppServiceDetails($ServicePrincipalId, "", $null)
    }

    SetAppServiceDetails(
        [string]$ServicePrincipalId,
        [string]$ClientAppSuffix,
        [string]$BaseUrl
        )
    {
        $AppNameWithSuffix = $this.AppName + $ClientAppSuffix
        [AzureAdApp]$AdApp = $this.AdApps[$AppNameWithSuffix]
        $AppId = $null
        # We won't always have an AzureAdApp - if a service is open by design
        # (e.g. the Marain.Operations status service), there will be no app.
        if ($AdApp)
        {
            $AppId = $AdApp.AppId
        }
        if (-not $BaseUrl)
        {
            $BaseUrl = "https://$AppNameWithSuffix.azurewebsites.net/"
        }
        $Service = [MarainAppService]::new($AppId, $ServicePrincipalId, $BaseUrl)
        $this.AppServices[$AppNameWithSuffix] = $Service
    }

    AssignServicePrincipalToCommonServiceAppRole(
        [string] $TargetCommonAppKey,
        [string] $TargetAppRoleId,
        [string] $ClientAppSuffix
    )
    {
        # Since the application currently being configured is trying to use a common service, the
        # target application details should be available in the instance context (because the
        # common service in question will have called MakeAppServiceCommonService).
        [MarainAppService]$TargetAppService = $this.InstanceContext.GetCommonAppService($TargetCommonAppKey)
        $this.AssignServicePrincipalToAppRole($TargetAppService, $TargetAppRoleId, $ClientAppSuffix)
    }

    AssignServicePrincipalToInternalServiceAppRole(
        [string] $TargetAppSuffix,
        [string] $TargetAppRoleId,
        [string] $ClientAppSuffix
    )
    {
        $TargetAppNameWithSuffix = $this.AppName + $TargetAppSuffix
        [MarainAppService]$TargetAppService = $this.AppServices[$TargetAppNameWithSuffix]
        $this.AssignServicePrincipalToAppRole($TargetAppService, $TargetAppRoleId, $ClientAppSuffix)
    }

    AssignServicePrincipalToAppRole(
        [MarainAppService]$TargetAppService,
        [string] $TargetAppRoleId,
        [string] $ClientAppSuffix
    )
    {
        # This is what we would have done on classic Azure AD.
        # New-AzureADServiceAppRoleAssignment -ObjectId 0bbd7057-009f-414a-b0fa-9b811ea52b24 -PrincipalId 0bbd7057-009f-414a-b0fa-9b811ea52b24 -ResourceId $target.ObjectId -Id 7619c293-764c-437b-9a8e-698a26250efd
        # Aggravatingly, no equivalent is available on PowerShell Core today.
        # So for this task we end up having to use the az CLI's rest command.

        # This looks more complex than it seems like it should, but there's a reason. We typically
        # end up with three distinct Azure AD apps, and three corresponding service principals,
        # even though there are only two services involved.
        #
        # We use the term "target service" and "client service" to describe the two parties here.
        # The goal is to ensure that the client service is able to access the target service in the
        # required way by granting its identity membership of a particular App Role defined by the
        # target service. Let's look at what that means from an AD perspective.
        #
        # The client service will have a corresponding Service Principle in Azure. Normally this
        # will be a Managed Identity (although it doesn't have to be). All Service Principals have
        # an associated AD Application, but that's typically not very interesting. To avoid
        # ambiguity we refer to these as the Client Identity Service Principal and the Client
        # Identity AD Application. If you manage service identities manually (i.e., you choose not
        # to use Managed Identities), then the Client Identity AD Application's main purposes are:
        # 1) its existence is a prerequisite for defining the Service Principal, and 2) it is the
        # object against which the credentials enabling the client service to identify itself
        # as this Service Principal are defined. If you're using Managed Identity, both the
        # Client Identity Service Principal and the Client Identity AD Application are reated for
        # you; in this case, the AD app appears to be a hollowed-out shell of an application - it is
        # missing most of the properties you see when you define an AD application yourself.
        #
        # The target service will define an AD Application for the purpose of securing access. This
        # is where the App Role definitions live. If you are using Azure App Service Authentication
        # (aka EasyAuth) this Application's AppId appears in the Authentication section for the App
        # Service in the Azure Portal. To avoid ambiguity we refer to this as the Access Control AD
        # Application. What's potentially surprising is that there is a Service Principal
        # associated with the Access Control application, and this is usually NOT the same Service
        # Principal as the target service would use to identify itself when making outbound calls.
        # (In principle it could be but it typically isn't, and if you are using Managed Identities
        # it definitely won't be.) The purpose of this principal, which we will call the Access
        # Control Service Principal, is to hold tenant-specific settings for the Access Control AD
        # Application. Azure AD is designed to support multi-tenant applications, which introduces
        # potentially confusing complexity for applications that will never be multi-tenant - it's
        # the reason we end up with 3 Service Principals of interest in this scenario even though
        # there are only two services. The access control model with App Roles in AD is that role
        # membership is defined per-tenant. So if there were some multi-tenanted application in use
        # in both the endjin.com and the interact-sw.co.uk tenants, the role membership for those
        # two tenants needs to live in those two tenants. And so AD uses the Access Control Service
        # Principal for this. In this hypothetical multi-tenanted scenario, an Access Control AD
        # Application would be defined in one tenant (say, endjin.com) but would have two
        # associated Service Principals. There would be one in the endjin.com tenant, defining
        # which principals in the endjin tenant are in which roles for this app, and a second
        # Service Principal (associated with the same Access Control Application) defining which
        # principals in the interact tenant are in which roles for this app. Returning to the
        # particular scenario this code addresses, our Access Control AD Application is not in fact
        # multi-tenanted, but AD works the same way regardless, meaning that the role membership
        # still ends up living in a separated Access Control Service Principal associated with the
        # Access Control AD Application.
        #
        # There will typically be a third Service Principal (and therefore a corresponding AD
        # Application), acting as the target service's identity. This isn't actually interesting
        # in this particular scenario, because it only comes into play when the target service
        # makes outbound calls to other services. This code is concerned only with securing access
        # of calls into the target service. But it's important to be aware of this Service
        # Principal because it its existence can cause confusion. To avoid ambiguity, we refer to
        # these objects as the Target Identity Service Principal and the Target Identity AD
        # Application. When the following code retrieves the MarainAppService representing the
        # target service, that object has a ServicePrincipalId property, so it may seem odd that we
        # don't use it, and that we instead make a call into Azure AD to retrieve a service
        # principal object. We need to do that because the MarainAppService.ServicePrincipalId
        # identifies the Target Identity Service Principal, which is (normally) a different object
        # from the Access Control Service Principal. (If you managed your service identities
        # yourself then it is actually possible that these could be the same object. But if you are
        # using Managed Identities, which is usually the preferred approach, these will always be
        # two distinct Service Principals.) When it comes to app role assignment, we need to be
        # adding the Client Identity Service Principal to role membership list in the Access
        # Control Service Principal. MarainAppService.ServicePrincipalId identifies a different
        # service principal, so it's the wrong one to use.

        $ClientAppNameWithSuffix = $this.AppName + $ClientAppSuffix

        [MarainAppService]$ClientAppService = $this.AppServices[$ClientAppNameWithSuffix]
        if ($null -ne $ClientAppService) {
            $ClientIdentityServicePrincipalId = $ClientAppService.ServicePrincipalId
        }
        else {
            # When running in AAD-only mode, we won't yet have the service principle, because
            # that's something that comes out of the ARM deployment, so we have to look it up.

            # There are often multiple matching apps, because the client application will often
            # have defined its own access control application. (This is actually a 4th application,
            # not one of the three listed in the description above.) This will typically have the
            # same display name Client Identity AD Application, so both will come back when we try
            # to find the one we want. We want the one with a serviceType of ManagedIdentity but
            # there's no direct way to query for that (and Get-AzADServicePrincipal doesn't provide
            # that property because it uses the AD Graph API, not the Microsoft Graph), so instead
            # we look for a service principle name that includes a particular URL root that is
            # always present with managed identities.
            $apps = Get-AzADServicePrincipal -DisplayNameBeginsWith $ClientAppNameWithSuffix
            $app = $apps | where-object {$_.DisplayName -eq $ClientAppNameWithSuffix -and ($_.ServicePrincipalNames | Where-Object { $_.Contains("https://identity.azure.net") }) }
            $ClientIdentityServicePrincipalId = $app.Id
        }

        $TargetAppId = $TargetAppService.AuthAppId
        # Remember, $TargetAppService.ServicePrincipalId does NOT do what we want here.
        # That's the Target Identity Service Principal, but we want the target's Access Control
        # Service Principal.
        $TargetSp = Get-AzADServicePrincipal -ApplicationId $TargetAppId
        $TargetAccessControlServicePrincipalId = $TargetSp.Id

        Write-Host "Assigning role $TargetAppRoleId for app $TargetAppId sp: $TargetAccessControlServicePrincipalId to client $ClientAppNameWithSuffix (sp: $ClientIdentityServicePrincipalId)"
        $RequestBody = "{'appRoleId': '$TargetAppRoleId','principalId': '$ClientIdentityServicePrincipalId','resourceId': '$TargetAccessControlServicePrincipalId'}"
        Write-Host $RequestBody
        
        # az rest --method post --uri https://graph.microsoft.com/beta/servicePrincipals/$ClientIdentityServicePrincipalId/appRoleAssignments --body $RequestBody --headers "Content-Type=application/json"
        # if ($LASTEXITCODE -ne 0) {
        #     Write-Error "Unable to assign role $TargetAppRoleId for app $TargetAppId"
        # }

        # Test AzureAD.Standard.Preview module
        # install AzureAD Standard (preview) module
        if ( !(Get-PackageSource -Name 'Posh Test Gallery' -ErrorAction SilentlyContinue) ) {
            Register-PackageSource -Trusted -ProviderName 'PowerShellGet' -Name 'Posh Test Gallery' -Location 'https://www.poshtestgallery.com/api/v2/'
        }
        if ( !(Get-Module 'AzureAD.Standard.Preview' -ListAvailable -ErrorAction SilentlyContinue) ) {
            Install-Module -Name AzureAD.Standard.Preview -Force -Scope CurrentUser -SkipPublisherCheck -AllowClobber
        }
        $aadModule = Get-Module -ListAvailable AzureAD.Standard.Preview

        $ctx = Get-AzContext
        $AadGraphApiResourceId = "https://graph.windows.net/"
        $GraphToken = $ctx.TokenCache.ReadItems() | Where-Object { (!($_.TenantId) -or $_.TenantId -eq $this.InstanceContext.TenantId) -and $_.Resource -eq $AadGraphApiResourceId }
        # we need to run the AzureAD module in a different process due to assembly mismatches
        $script = @(
            "Import-Module $($aadModule.Path)"
            "Connect-AzureAD -AccountId $($ctx.Subscription) -TenantId $($ctx.Tenant) -AadAccessToken $($GraphToken.AccessToken)"
            "Write-Host 'DEBUG: Client=$ClientIdentityServicePrincipalId, Target=$TargetAccessControlServicePrincipalId, Role=$TargetAppRoleId'"
            "`$existing = Get-AzureADServiceAppRoleAssignment -ObjectId $TargetAccessControlServicePrincipalId | Where { `$_.PrincipalId -eq '$ClientIdentityServicePrincipalId' -and `$_.Id -eq '$TargetAppRoleId' }"
            "Write-Host 'DEBUG:'; `$existing"
            "if (`$null -eq `$existing) { Write-Host '`tRole assignment required...'; New-AzureADServiceAppRoleAssignment -ObjectId $ClientIdentityServicePrincipalId -PrincipalId $ClientIdentityServicePrincipalId -ResourceId $TargetAccessControlServicePrincipalId -Id $TargetAppRoleId }"
        )
        Write-Host "DEBUG: $($script -join '; ')"
        Write-Host "Checking role assignment $TargetAppRoleId for app $TargetAppId sp: $TargetAccessControlServicePrincipalId to client $ClientAppNameWithSuffix (sp: $ClientIdentityServicePrincipalId)"
        pwsh -c ([scriptblock]::Create($script -join '; '))
    }


    UploadReleaseAssetAsAppServiceSitePackage(
        [string]$AssetName,
        [string]$AppServiceName)
    {
        $WebApp = Get-AzWebApp -Name $AppServiceName
        if (-not $WebApp) {
            Write-Error "Did not find web app $AppServiceName"
            return
        }
        $ReleaseAssets = $this.GitHubRelease.assets | Where-Object  { $_.name -eq $AssetName }
        if ($ReleaseAssets.Count -ne 1) {
            Write-Error ("Expecting exactly one asset named {0}, found {1}" -f $AssetName, $ReleaseAssets.Count)
        }
        $ReleaseAsset = $ReleaseAssets[0]
        $url = $ReleaseAsset.browser_download_url
        $AssetPath = Join-Path $this.TempFolder $AssetName
        Write-Host "Will deploy file at $url to $AppServiceName"
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

class MarainAppService
{
    MarainAppService(
        [string]$AuthAppId,
        [string]$ServicePrincipalId,
        [string]$BaseUrl
    )
    {
        $this.AuthAppId = $AuthAppId
        $this.ServicePrincipalId = $ServicePrincipalId
        $this.BaseUrl = $BaseUrl
    }

    [string]$AuthAppId
    [string]$ServicePrincipalId
    [string]$BaseUrl
}

class AzureAdApp {
    AzureAdApp(
        [MarainServiceDeploymentContext] $ServiceDeploymentContext,
        [string]$appId)
    {

        $this.ServiceDeploymentContext = $ServiceDeploymentContext
        $this.InstanceDeploymentContext = $ServiceDeploymentContext.InstanceContext
        $this.AppId = $appId
    }

    [string]$AppId
        [MarainServiceDeploymentContext]$ServiceDeploymentContext
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

try {
    # ensure PowerShell Az modules are available
    $azAvailable = Get-Module Az -ListAvailable
    if ($null -eq $azAvailable) {
        Write-Error "Az PowerShell modules are not installed - they can be installed using 'Install-Module Az -AllowClobber -Force'"
    }

    # Ensure PowerShell Az is logged-in
    if ($null -eq (Get-AzContext) -and [Environment]::UserInteractive) {
        Connect-AzAccount -Subscription $SubscriptionId -Tenant $AadTenantId
    }
    elseif ($null -eq (Get-AzContext)) {
        Write-Error "When running non-interactively the process must already be logged-in to the Az PowerShell modules"
    }

    # Ensure we're connected to the correct subscription
    Set-AzContext -SubscriptionId $SubscriptionId -Tenant $AadTenantId | Out-Null


    # check that the azure-cli is installed
    try {
        Invoke-Expression 'az --version' | Out-Null
    }
    catch {
        Write-Error "The Azure-cli must be installed in order to run this deployment process"
    }

    # check that the azure-cli is logged-in
    try {
        $azCliToken = $(& az account get-access-token) | ConvertFrom-Json
        if ([datetime]$azCliToken.expiresOn -le [datetime]::Now) {
            throw   # force a login
        }
    }
    catch {
        # login with the typical environment variables, if available
        if ( (Test-Path env:\AZURE_CLIENT_ID) -and (Test-Path env:\AZURE_CLIENT_SECRET) ){
            & az login --service-principal -u "$env:AZURE_CLIENT_ID" -p "$env:AZURE_CLIENT_SECRET" --tenant $AadTenantId
            if ($LASTEXITCODE -ne 0) {
                Write-Error "There was a problem logging into the Azure-cli using environment variable configuration - check any previous messages"
            }
        }
        # Azure pipeline processes seem to report themselves as interactive - at least on linux agents
        elseif ( [Environment]::UserInteractive -and !(Test-Path env:\SYSTEM_TEAMFOUNDATIONSERVERURI) ) {
            & az login --tenant $AadTenantId | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Error "There was a problem logging into the Azure-cli - check any previous messages"
            }
        }
        else {
            Write-Error "When running non-interactively the process must already be logged-in to the Azure-cli or have the SPN details setup in environment variables"
        }
    }
    & az account set --subscription $SubscriptionId | Out-Null

    # perform an arbitrary AAD operation to force getting a graph api token
    $AadGraphApiResourceId = "https://graph.windows.net/"
    Get-AzADApplication -ApplicationId (New-Guid).Guid -ErrorAction SilentlyContinue | Out-Null
    # service principals with a graph tokens appear unassociated with a tenant
    $GraphToken = (Get-AzContext).TokenCache.ReadItems() | Where-Object { (!($_.TenantId) -or $_.TenantId -eq $AadTenantId) -and $_.Resource -eq $AadGraphApiResourceId }
    if (!$GraphToken) {
        Write-Warning "No graph token available. AAD operations will not be performed."
        $DoNotUseGraph = $True
    }

    # Fail early if we have no graph access and no predefined appId's
    if ($DoNotUseGraph -and (!$AadAppIds -or $AadAppIds.Count -eq 0)) {
        Write-Error "When running without access to AAD, you must specify the existing AAD applications in the 'AadAppIds' hashtable parameter"
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


    # ensure dotnet cli is available
    try {
        $dotnetCliOutput = & dotnet --version
    }
    catch {
        Write-Error "The dotnet cli is required, but not installed or otherwise not working:`n$_.Message`n$dotnetCliOutput"
    }
    
    # ensure marain cli is available
    $InstanceDeploymentContext.MarainCliPath = Join-Path $HOME ".dotnet/tools/marain"
    if ($IsWindows) {
        $InstanceDeploymentContext.MarainCliPath += '.exe'
    } 
    if ( !(Test-Path $InstanceDeploymentContext.MarainCliPath)) {
        & dotnet tool install -g $marainGlobalToolName --version $marainGlobalToolVersion
    }

    # Lookup the identity of the deployment user, as we need their objectId to grant keyvault access
    $currentContext = Get-AzContext
    if ($currentContext.Account.Id -imatch "@") {
        $currentUser = Get-AzAdUser -UserPrincipalName $currentContext.Account.Id
        $InstanceDeploymentContext.DeploymentUserObjectId = $currentUser.Id
    }
    else {
        $currentSp = Get-AzADServicePrincipal -ApplicationId $currentContext.Account.Id
        $InstanceDeploymentContext.DeploymentUserObjectId = $currentSp.Id
    }


    $InstanceResourceGroupName = $InstanceDeploymentContext.MakeResourceGroupName("instance")

    if (-not $AadOnly -and (-not $SkipInstanceDeploy)) {
        if ((-not $SingleServiceToDeploy) -or ($SingleServiceToDeploy -eq 'Marain.Instance')) {
            Write-Host "Deploying shared Marain infrastructure"

            $DeploymentResult = $InstanceDeploymentContext.DeployArmTemplate($PSScriptRoot, "azuredeploy.json", @{deployUserObjectId=$InstanceDeploymentContext.DeploymentUserObjectId}, $InstanceResourceGroupName)

            $InstanceDeploymentContext.ApplicationInsightsInstrumentationKey = $DeploymentResult.Outputs.instrumentationKey.Value
            $InstanceDeploymentContext.KeyVaultName = $DeploymentResult.Outputs.keyVaultName.Value
            Write-Host "Shared Marain infrastructure deployment complete"
        }
    }
    if (-not $InstanceDeploymentContext.ApplicationInsightsInstrumentationKey -and (-not $AadOnly)) {
        $AiName = ("{0}{1}ai" -f $InstanceDeploymentContext.Prefix, $InstanceDeploymentContext.EnvironmentSuffix)
        $Ai = Get-AzApplicationInsights -ResourceGroupName $InstanceResourceGroupName -Name $AiName
        $InstanceDeploymentContext.ApplicationInsightsInstrumentationKey = $Ai.InstrumentationKey
    }

    if (-not $InstanceDeploymentContext.KeyVaultName) {
        # TODO: shouldn't be more than 1 keyvault
        $keyVault = Get-AzKeyVault -ResourceGroupName $InstanceResourceGroupName | Select -First 1
        $InstanceDeploymentContext.KeyVaultName = $keyVault.VaultName
    }

    ForEach ($kv in $MarainServices.PSObject.Properties) {
        $MarainServiceName = $kv.Name
        $MarainService = $kv.Value

        if ((-not $SingleServiceToDeploy) -or ($SingleServiceToDeploy -eq $MarainServiceName)) {
            $ServiceManifestEntry = $InstanceManifest.services.$MarainServiceName
            if ($null -ne $ServiceManifestEntry.omit -and $ServiceManifestEntry.omit) {
                continue
            }
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
                New-Item -Path $TempDir -ItemType Directory | Out-Null
                $DeploymentPackageDir = Join-Path $TempDir "DeploymentPackage"
                New-Item -Path $DeploymentPackageDir -ItemType Directory 
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
                            Write-Host " Running $scriptName"
                            . $ScriptPath
                            MarainDeployment $ServiceDeploymentContext
                        }
                        else {
                            Write-Verbose "Skipping $scriptName - not found: $ScriptPath"
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
                    Remove-Item -Recurse -Force $TempDir
                }
            }
        }
    }
}
catch {
    Write-Warning $_.ScriptStackTrace
    Write-Warning $_.InvocationInfo.PositionMessage
    Write-Error ("Marain deployment error: `n{0}" -f $_.Exception.Message)
}

Write-Host -f green "Marain deployment complete."