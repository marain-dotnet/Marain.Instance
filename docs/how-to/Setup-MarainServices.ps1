param (
    [string] $BasePath
)

function updatePropertyIfExists($inputObj, $prop, $value) {
    if (Get-Member -inputobject $inputObj -name $prop -Membertype Properties) {
        $inputObj.$prop = $value
    }
}

function cloneOrPull($repoDir, $name) {
    if (!(Test-Path -Path $repoDir)) {
        Write-Host "Cloning repo..."
        git clone "https://github.com/marain-dotnet/$name.git" $repoDir
    }
    else {
        Write-Host "Pulling latest..."
        Push-Location $repoDir
        git pull
        Pop-Location
    }
}

$MarainServices = @(
    @{ 
        name     = "Marain.Tenancy"; 
        projects = @(
            @{ name = "Marain.Tenancy.Host.Functions"; type = "functionsHost" }
        ) 
    },
    @{ 
        name     = "Marain.Claims"; 
        projects = @(
            @{ name = "Marain.Claims.Host.Functions"; type = "functionsHost" }
        ) 
    },
    @{ 
        name     = "Marain.Operations"; 
        projects = @(
            @{ name = "Marain.Operations.ControlHost.Functions"; type = "functionsHost" }, 
            @{ name = "Marain.Operations.StatusHost.Functions"; type = "functionsHost" }
        ) 
    },
    @{ 
        name     = "Marain.Workflow"; 
        projects = @(
            @{ name = "Marain.Workflow.Api.EngineHost"; type = "functionsHost" }, 
            @{ name = "Marain.Workflow.Api.MessageProcessingHost"; type = "functionsHost" }
        ) 
    }
    @{ 
        name     = "Marain.TenantManagement"; 
        projects = @(
            @{ name = "Marain.TenantManagement.Cli"; type = "cliTool" }
        ) 
    }
)

$MarainServices | ForEach-Object {
    $name = $_.name
    $repoDir = Join-Path $BasePath $name

    cloneOrPull $repoDir $name

    $_.projects | ForEach-Object {
        $projName = $_.name
        $projDir = Join-Path $repoDir "Solutions/$projName"

        switch ($_.type) {
            "functionsHost" {
                $settingsTemplate = Join-Path $projDir "local.settings.template.json"
                $settings = Join-Path $projDir "local.settings.json"
            }
            "cliTool" {
                $settingsTemplate = Join-Path $projDir "appsettings.template.json"
                $settings = Join-Path $projDir "appsettings.json"
            }
            Default {
                throw "Unknown proejct type."
            }
        }
       
        $csproj = Join-Path $projDir "$projName.csproj"

        Write-Host "Copying $settingsTemplate to $settings"
        Copy-Item -Path $settingsTemplate -Destination $settings -Force

        $settingsJson = Get-Content $settings -raw | ConvertFrom-Json

        switch ($_.type) {
            "functionsHost" {
                $values = $settingsJson.Values
            }
            "cliTool" {
                $values = $settingsJson
            }
            Default {
                throw "Unknown proejct type."
            }
        }

        updatePropertyIfExists $values "AzureServicesAuthConnectionString" ""
        updatePropertyIfExists $values "TenancyClient:TenancyServiceBaseUri" "http://localhost:7071"
        updatePropertyIfExists $values "TenancyClient:ResourceIdForMsiAuthentication" ""
        updatePropertyIfExists $values "Workflow:EngineClient:BaseUrl" "http://localhost:7075"
        updatePropertyIfExists $values "Workflow:EngineClient:ResourceIdForAuthentication" ""
        updatePropertyIfExists $values "Operations:ControlServiceBaseUrl" "http://localhost:7073"
        updatePropertyIfExists $values "Operations:ResourceIdForMsiAuthentication" ""
        updatePropertyIfExists $values "ExternalServices__OperationsStatus" "http://localhost:7072"

        $settingsJson | ConvertTo-Json -Depth 32 | Set-Content $settings

        dotnet build $csproj -c Debug
    }
}