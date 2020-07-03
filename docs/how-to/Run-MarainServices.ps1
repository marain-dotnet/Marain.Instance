param (
    [string] $BasePath
)

$hosts = @(
    @{ service = "Marain.Tenancy"; name = "Marain.Tenancy.Host.Functions"; port = 7071 },
    @{ service = "Marain.Claims"; name = "Marain.Claims.Host.Functions"; port = 7076 },
    @{ service = "Marain.Operations"; name = "Marain.Operations.ControlHost.Functions"; port = 7078 },
    @{ service = "Marain.Operations"; name = "Marain.Operations.StatusHost.Functions"; port = 7077 },
    @{ service = "Marain.Workflow"; name = "Marain.Workflow.Api.EngineHost"; port = 7075 },
    @{ service = "Marain.Workflow"; name = "Marain.Workflow.Api.MessageProcessingHost"; port = 7073 }
)

$hosts | ForEach-Object {
    $service = $_.service
    $name = $_.name
    $port = $_.port

    Start-Process pwsh `
        -WorkingDirectory (Join-Path $BasePath "$service\Solutions\$name\bin\Debug\netcoreapp3.1") `
        -ArgumentList "-command `$a`=(get-host).ui.rawui;`$a.windowtitle`='$name';func.cmd start --port $port"
        -RedirectStandardError (Join-Path $BasePath "$name.stderr.txt")
}