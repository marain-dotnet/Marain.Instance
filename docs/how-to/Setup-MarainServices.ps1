param (
    [string] $BasePath
)

function updatePropertyIfExists($inputObj, $prop, $value) {
    if (Get-Member -inputobject $inputObj -name $prop -Membertype Properties){
        $inputObj.$prop = $value
    }
}

$MarainServices = @(
    @{ name = "Marain.Tenancy"; functionsHosts = @("Marain.Tenancy.Host.Functions") },
    @{ name = "Marain.Claims"; functionsHosts = @("Marain.Claims.Host.Functions") },
    @{ name = "Marain.Operations"; functionsHosts = @("Marain.Operations.ControlHost.Functions", "Marain.Operations.StatusHost.Functions") },
    @{ name = "Marain.Workflow"; functionsHosts = @("Marain.Workflow.Api.EngineHost", "Marain.Workflow.Api.MessageProcessingHost") }
)

$MarainServices | ForEach-Object {
    $name = $_.name
    $repoDir = Join-Path $BasePath $name

    if (!(Test-Path -Path $repoDir)){
        Write-Host "Cloning repo..."
        git clone "https://github.com/marain-dotnet/$name.git" $repoDir
    }
    else{
        Write-Host "Pulling latest..."
        Push-Location $repoDir
        git pull
        Pop-Location
    }

    $_.functionsHosts | ForEach-Object {
        $projDir = Join-Path $repoDir "Solutions/$_"
        $settingsTemplate = Join-Path $projDir "local.settings.template.json"
        $settings = Join-Path $projDir "local.settings.json"
        $csproj = Join-Path $projDir "$_.csproj"

        Write-Host "Copying $settingsTemplate to $settings"
        Copy-Item -Path $settingsTemplate -Destination $settings -Force

        $settingsJson = Get-Content $settings -raw | ConvertFrom-Json

        updatePropertyIfExists $settingsJson.Values "AzureServicesAuthConnectionString" ""
        updatePropertyIfExists $settingsJson.Values "TenancyClient:TenancyServiceBaseUri" "http://localhost:7071"
        updatePropertyIfExists $settingsJson.Values "TenancyClient:ResourceIdForMsiAuthentication" ""
        updatePropertyIfExists $settingsJson.Values "Workflow:EngineClient:BaseUrl" "http://localhost:7075"
        updatePropertyIfExists $settingsJson.Values "Workflow:EngineClient:ResourceIdForAuthentication" ""
        updatePropertyIfExists $settingsJson.Values "Operations:ControlServiceBaseUrl" "http://localhost:7073"
        updatePropertyIfExists $settingsJson.Values "Operations:ResourceIdForMsiAuthentication" ""
        updatePropertyIfExists $settingsJson.Values "ExternalServices__OperationsStatus" "http://localhost:7072"

        $settingsJson | ConvertTo-Json -Depth 32 | Set-Content $settings

        dotnet build $csproj -c Debug
    }
}
