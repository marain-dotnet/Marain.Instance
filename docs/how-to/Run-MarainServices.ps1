Start-Process `
    -WorkingDirectory "C:\git\Marain.Tenancy\Solutions\Marain.Tenancy.Host.Functions\bin\Debug\netcoreapp3.1" `
    -FilePath "func.cmd" `
    -ArgumentList "start","--port 7071"

Start-Process `
    -WorkingDirectory "C:\git\Marain.Operations\Solutions\Marain.Operations.ControlHost.Functions\bin\Debug\netcoreapp3.1" `
    -FilePath "func.cmd" `
    -ArgumentList "start","--port 7078"

Start-Process `
    -WorkingDirectory "C:\git\Marain.Operations\Solutions\Marain.Operations.StatusHost.Functions\bin\Debug\netcoreapp3.1" `
    -FilePath "func.cmd" `
    -ArgumentList "start","--port 7077"

Start-Process `
    -WorkingDirectory "C:\git\Marain.Workflow\Solutions\Marain.Workflow.Api.EngineHost\bin\Debug\netcoreapp3.1" `
    -FilePath "func.cmd" `
    -ArgumentList "start","--port 7075"

Start-Process `
    -WorkingDirectory "C:\git\Marain.Workflow\Solutions\Marain.Workflow.Api.MessageProcessingHost\bin\Debug\netcoreapp3.1" `
    -FilePath "func.cmd" `
    -ArgumentList "start","--port 7073"