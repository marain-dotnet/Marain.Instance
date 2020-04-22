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

        # Note, we're using the Az module here.
        # If this fails ensure you run:
        #   Connect-AzAccount
        # and if that is unavailable, do this first:
        #   Install-Module Az
        if (-not $DoNotUseGraph) {
            $AzContext = Get-AzContext
            # if ($AzContext.GetType().ToString() -is [Microsoft.Azure.Commands.Profile.Models.Core.PSAzureContext])) {
            if ($null -eq $AzContext) {
                Write-Error 'Please run Connect-AzAccount'
            }
            $AadGraphApiResourceId = "https://graph.windows.net/"

            $GraphToken = $AzContext.TokenCache.ReadItems() | Where-Object { $_.TenantId -eq $this.TenantId -and $_.Resource -eq $AadGraphApiResourceId }
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

    [AzureAdApp]DefineAzureAdAppForAppService()
    {
        return $this.DefineAzureAdAppForAppService("")
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
        $ClientIdentityServicePrincipalId = $ClientAppService.ServicePrincipalId
        
        if (-not $ClientIdentityServicePrincipalId) {
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
        az rest --method post --uri https://graph.microsoft.com/beta/servicePrincipals/$ClientIdentityServicePrincipalId/appRoleAssignments --body $RequestBody --headers "Content-Type=application/json"
        Write-Host "Note, if you just saw an error of the form 'One or more properties are invalid.' it may be because the role assignments already exist. Command line tooling for managing role assignments is currently somewhat lacking in cross-platform environments."
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
}
