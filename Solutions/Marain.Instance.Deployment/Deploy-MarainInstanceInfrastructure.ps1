#Requires -Version 7.0
#Requires -Modules Microsoft.PowerShell.Archive
#Requires -Modules @{ ModuleName = "Az.Accounts"; ModuleVersion = "2.7.4" }
#Requires -Modules @{ ModuleName = "Az.Resources"; ModuleVersion = "5.4.0" }

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
    [Hashtable] $DeploymentAssetLocalOverrides = @{},
    [string] $Prefix = "mar"
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'       # the progress message output can mask part of the error handling output
Set-StrictMode -Version 4

$marainGlobalToolName = 'marain'
$marainGlobalToolDefaultVersion = '1.1.2'

function Test-AzureGraphAccess
{
    [CmdletBinding()]
    param
    (
    )

    # perform an arbitrary AAD operation to see if we have read access to the graph API
    try {
        Get-AzADApplication -ApplicationId (New-Guid).Guid -ErrorAction Stop
    }
    catch {
        if ($_.Exception.Message -match "Insufficient privileges") {
            return $False
        }
        else {
            throw $_
        }
    }

    return $True
}
function Invoke-CommandWithRetry
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [scriptblock] $Command,

        [int] $RetryCount = 5,

        [int] $RetryDelay = 5
    )

    $currentRetry = 0
    $success = $false

    # Private functions for mocking purposes
    function _logWarning($delay)
    {
        Write-Warning ("Command failed - retrying in {0} seconds" -f $delay)
    }

    do
    {
        Write-Verbose ("Executing command with retry:`n{0}" -f ($Command | Out-String))
        try
        {
            $result = Invoke-Command $command -ErrorAction Stop
            Write-Verbose ("Command succeeded." -f $Command)
            $success = $true
        }
        catch
        {   
            if ($currentRetry -ge $RetryCount) {
                throw ("Exceeded retry limit when running command [{0}]" -f $Command)
            }
            else {
                _logWarning $RetryDelay
                Start-Sleep -s $RetryDelay
            }
            $currentRetry++
        }
    } while (!$success);

    return $result
}


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
        $this.GraphAccess = $false

        # Note, we're using the Az module here.
        # If this fails ensure you run:
        #   Connect-AzAccount
        # and if that is unavailable, do this first:
        #   Install-Module Az
        if (-not $DoNotUseGraph) {
            $this.GraphAccess = Test-AzureGraphAccess
            if (!$this.GraphAccess) {
                Write-Host "No graph token available. AAD operations will not be performed."
            }
        }

        $this.DeploymentStagingResourceGroupName = 'ARM_Deploy_Staging_' + $this.AzureLocation.Replace(" ", "_")
        $this.DeploymentStagingStorageAccountName = ('stg' + $this.AzureLocation + $this.SubscriptionId).Replace('-', '').substring(0, 24)
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
    [bool]$GraphAccess

    [string]$DeploymentStagingResourceGroupName
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
    
        $StorageContainerName = $ResourceGroupName.ToLowerInvariant().Replace(".", "") + '-stageartifacts'

        $StorageAccount = Get-AzStorageAccount -ResourceGroupName $this.DeploymentStagingResourceGroupName -Name $this.DeploymentStagingStorageAccountName -ErrorAction SilentlyContinue

        # Create the storage account if it doesn't already exist
        if ($StorageAccount -eq $null) {
            New-AzResourceGroup -Location $this.AzureLocation -Name $this.DeploymentStagingResourceGroupName -Force
            $StorageAccount = New-AzStorageAccount -StorageAccountName $this.DeploymentStagingStorageAccountName  -Type 'Standard_LRS' -ResourceGroupName $this.DeploymentStagingResourceGroupName -Location $this.AzureLocation
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
        if ($null -eq (Get-AzResourceGroup -Name $ResourceGroupName -Location $this.AzureLocation -Verbose -ErrorAction SilentlyContinue)) {
            New-AzResourceGroup -Name $ResourceGroupName -Location $this.AzureLocation -Verbose -Force -ErrorAction Stop
        }

        # Deploy the ARM template with a built-in retry loop to try and limit the disruption from spurious ARM errors
        $retries = 1
        $maxRetries = 3
        $DeploymentResult = $null
        $success = $false
        while (!$success -and $retries -le $maxRetries) {
            if ($retries -gt 1) { Write-Host "Waiting 30secs before retry..."; Start-Sleep -Seconds 30 }

            $deployName = "{0}-{1}-{2}" -f (Get-ChildItem $ArmTemplatePath).BaseName, `
                                            ((Get-Date).ToUniversalTime()).ToString('MMdd-HHmm'), `
                                            $retries
            try {
                Write-Host "Deploying ARM template ($ArmTemplatePath)..."
                $DeploymentResult = New-AzResourceGroupDeployment `
                    -Name $deployName `
                    -ResourceGroupName $ResourceGroupName `
                    -TemplateFile $ArmTemplatePath `
                    @OptionalParameters `
                    @TemplateParameters `
                    -Force `
                    -Verbose `
                    -ErrorAction Stop

                # The template deployed successfully, drop out of retry loop
                $success = $true
                Write-Host "ARM template deployment successful"
            }
            catch {
                if ($_.Exception.Message -match "Code=InvalidTemplate") {
                    Write-Host "Invalid ARM template error detected - skipping retries"
                    throw $_
                }
                elseif ($retries -ge $maxRetries) {
                    Write-Host "Unable to deploy ARM template - retry attempts exceeded"
                    throw $_
                }
                Write-Host ("Attempt {0}/{1} failed: {2}" -f $retries, $maxRetries, $_.Exception.Message)
                $retries++
            }
        }

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
            Write-Host "Found existing app with id $($app.AppId)"
            $ReplyUrlsOk = $true
            ForEach ($ReplyUrl in $replyUrls) {
                if (-not $app.Web.RedirectUri.Contains($ReplyUrl)) {
                    $ReplyUrlsOk = $false
                    Write-Host "Reply URL $ReplyUrl not present in app"
                }
            }
    
            if (-not $ReplyUrlsOk) {
                Write-Host "Setting reply URLs: $replyUrls"
                $app = Update-AzADApplication -ObjectId $app.Id -ReplyUrl $replyUrls
            }
        } else {
            $app = New-AzADApplication -DisplayName $DisplayName -HomePage $appUri -ReplyUrls $replyUrls
            # Azure no longer allows the '.azurewebsites.net' DNS name to be used as an Identifier URI
            $appIdUri = "api://$($app.AppId)"
            Set-AzADApplication -ApplicationId $app.AppId -IdentifierUris $appIdUri
            Write-Host "Created new app with id $($app.AppId)"
        }

        return [AzureAdAppWithGraphAccess]::new($this, $app.AppId, $app.Id)
    }

    [AzureAdApp]DefineAzureAdAppForAppService()
    {
        return $this.DefineAzureAdAppForAppService("")
    }

    [AzureAdApp]DefineAzureAdAppForAppService([string] $AppNameSuffix)
    {
        $AppNameWithSuffix = $this.AppName + $AppNameSuffix

        if (-not $this.InstanceContext.GraphAccess) {
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
            $sp = New-AzAdServicePrincipal -AppId $app.AppId
            Write-Host ("Service Principal Id for {0} ({1}) is {2}" -f $AppNameWithSuffix, $sp.AppId, $sp.Id)
        }

        $requiredApiPermissions = @(
            @{
                # Azure Graph
                GraphApiAppId = "00000002-0000-0000-c000-000000000000"
                Scope = "311a71cc-e848-46a1-bdf8-97ff7156d8e6"  # [User.Read] Sign in and read user profile
            }
            @{
                # Microsoft Graph
                GraphApiAppId = "00000003-0000-0000-c000-000000000000"
                Scope = "e1fe6dd8-ba31-4d61-89e7-88639da4683d"  # [User.Read] Sign in and read user profile
            }
        )
        $requiredApiPermissions | ForEach-Object {
            $app.EnsureRequiredResourceAccessContains($_.GraphApiAppId, @([ResourceAccessDescriptor]::new($_.Scope, "Scope")))
        }

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
       
        $existingAppRoleAssignmentsResp = Invoke-AzRestMethod -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$TargetAccessControlServicePrincipalId/appRoleAssignedTo"
        if ($existingAppRoleAssignmentsResp.StatusCode -ge 400) {
            throw "Error querying AppRole assignments for appId $TargetAppId : $($existingAppRoleAssignmentsResp.Content)"
        }

        $existingAppRoleAssignment = $existingAppRoleAssignmentsResp.Content |
                                        ConvertFrom-Json -Depth 100 |
                                        Select-Object -ExpandProperty Value |
                                        ? { $_.principalId -eq $ClientIdentityServicePrincipalId -and $_.appRoleId -eq $TargetAppRoleId }
        if (!$existingAppRoleAssignment) {
            $body = @{
                appRoleId = $TargetAppRoleId
                principalId = $ClientIdentityServicePrincipalId
                resourceId = $TargetAccessControlServicePrincipalId
            }
            $addAppRoleAssignmentResp = Invoke-AzRestMethod -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$TargetAccessControlServicePrincipalId/appRoleAssignedTo"
            if ($addAppRoleAssignmentResp.StatusCode -ge 400) {
                throw "Error trying to assign principal $ClientIdentityServicePrincipalId the AppRole $TargetAppRoleId appId $TargetAppId : $($addAppRoleAssignmentResp.Content)"
            }
        }
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

        # We have now migrated away from using the deprecated Azure Graph API, using Microsoft Graph instead
        $this.GraphApiAppUri = "https://graph.microsoft.com/v1.0/applications/$objectId"

        $this.Manifest = Get-AzADApplication -ObjectId $objectId
    }

    [string]$ObjectId
    [string]$GraphApiAppUri
    $Manifest

    EnsureRequiredResourceAccessContains(
        [string]$ResourceId,
        [ResourceAccessDescriptor[]] $accessRequirements)
    {
        $MadeChange = $false

        [array]$RequiredResourceAccess = $this.Manifest | Select-Object -ExpandProperty RequiredResourceAccess

        # Create top-level object for any APIs that are not currently
        $ResourceEntry = $RequiredResourceAccess | Where-Object { $_ -and $_.ResourceAppId -eq $ResourceId }
        if (-not $ResourceEntry) {
            $MadeChange = $true
            $ResourceEntry = @{
                ResourceAccess = @()
                ResourceAppId = $ResourceId
            }
            $RequiredResourceAccess += $ResourceEntry
        }
        
        # Add any requiredResourceAccess entries that are not configured on the application object
        foreach ($access in $accessRequirements) {
            $RequiredAccess = $ResourceEntry.ResourceAccess |
                                Where-Object {
                                    $_.Id -eq $access.Id -and `
                                    $_.Type -eq $access.Type
                                }
            if (-not $RequiredAccess) {
                Write-Host "Adding '$ResourceId : $($access.Id)' required resource access"
        
                $RequiredAccess = @{
                    Id = $access.Id
                    Type = "Scope"
                }
                $ResourceEntry.ResourceAccess += $RequiredAccess
                $MadeChange = $true
            }
        }

        if ($MadeChange) {
            Update-AzADApplication -Id $this.Manifest.Id -RequiredResourceAccess $RequiredResourceAccess
            $this.Manifest = Get-AzADApplication -ObjectId $this.Manifest.Id
        }
    }

    EnsureAppRolesContain(
        [string] $AppRoleId,
        [string] $DisplayName,
        [string] $Description,
        [string] $Value,
        [string[]] $AllowedMemberTypes)
    {
        $existingAppRole = $null
        if ($this.Manifest.AppRole.Length -gt 0) {
            $existingAppRole = $this.Manifest.AppRole |
                                Where-Object { $_.Id -eq $AppRoleId }
        }
        if (-not $existingAppRole) {
            Write-Host "Adding $Value app role"
    
            $newAppRole = @{
                DisplayName = $DisplayName
                Id = $AppRoleId
                IsEnabled = $true
                Description = $Description
                Value = $Value
                AllowedMemberType = $AllowedMemberTypes
            }
            $this.Manifest.AppRole += $newAppRole

            Update-AzADApplication -Id $this.Manifest.Id -AppRole $this.Manifest.AppRole
            $this.Manifest = Get-AzADApplication -Id $this.Manifest.Id
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

    if (!(Test-AzureGraphAccess)) {
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
        $Prefix,
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

    # Resolve which version of the Marain CLI we should be using
    # Query the optional '$InstanceManifest.tools' configuration in a StrictMode-friendly way
    $marainGlobalToolVersionFromConfig = $InstanceManifest |
                                                Select-Object -ExpandProperty tools -ErrorAction Ignore |
                                                Select-Object -ExpandProperty marain -ErrorAction Ignore |
                                                Select-Object -ExpandProperty release -ErrorAction Ignore
    $requiredMarainGlobalToolVersion = $marainGlobalToolVersionFromConfig ? $marainGlobalToolVersionFromConfig : $marainGlobalToolDefaultVersion
    if ($marainGlobalToolVersionFromConfig) {
        Write-Host "Resolved 'marain' .NET global tool version from config"
    } else {
        Write-Host "Using default 'marain' .NET global tool version"
    }

    # Check what version is already installed, if any
    $existingMarainGlobalTool = & dotnet tool list -g | ? { $_ -match 'marain' }
    $existingMarainGlobalToolVersion = ""
    if ($existingMarainGlobalTool) {
        $existingMarainGlobalToolVersion = $existingMarainGlobalTool.Replace('marain','').Replace(' ','')
    }

    if ($existingMarainGlobalToolVersion -ne $requiredMarainGlobalToolVersion) {
        if ($existingMarainGlobalToolVersion) {
            Write-Host "Uninstalling existing 'marain' .NET global tool v$requiredMarainGlobalToolVersion"
            & dotnet tool uninstall -g $marainGlobalToolName
        }
        Write-Host "Installing 'marain' .NET global tool v$requiredMarainGlobalToolVersion"
        & dotnet tool install -g $marainGlobalToolName --version $requiredMarainGlobalToolVersion
    }
    else {
        Write-Host "Using existing version of 'marain' .NET global tool v$((dotnet tool list -g | ? { $_ -match 'marain' }).Replace('marain','').Replace(' ',''))"
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
        # This currently throws a deprecation warning, since Az PowerShell v4.6.1, but we are not using the
        # 'SecretValueText' property that the message says is being removed in a later version.
        $keyVault = Get-AzKeyVault -ResourceGroupName $InstanceResourceGroupName | Select -First 1
        $InstanceDeploymentContext.KeyVaultName = $keyVault.VaultName
    }

    ForEach ($kv in $MarainServices.PSObject.Properties) {
        $MarainServiceName = $kv.Name
        $MarainService = $kv.Value

        if ((-not $SingleServiceToDeploy) -or ($SingleServiceToDeploy -eq $MarainServiceName)) {
            $ServiceManifestEntry = $InstanceManifest.services.$MarainServiceName
            if ( ($ServiceManifestEntry | Get-Member omit) -and $ServiceManifestEntry.omit) {
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
                New-Item -Path $DeploymentPackageDir -ItemType Directory | Out-Null
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