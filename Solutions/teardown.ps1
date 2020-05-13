$ErrorActionPreference = 'Stop'

Start-Job -Name tenancy -ScriptBlock { Remove-AzResourceGroup -Name mar.tenancy.jd -Force }
Start-Job -Name operations -ScriptBlock { Remove-AzResourceGroup -Name mar.operations.jd -Force }
Start-Job -Name workflow -ScriptBlock { Remove-AzResourceGroup -Name mar.workflow.jd -Force }
Start-Job -Name instance -ScriptBlock { Remove-AzResourceGroup -Name mar.instance.jd -Force }

Receive-Job -Name instance
Receive-Job -Name tenancy
Receive-Job -Name operations
Receive-Job -Name workflow

Get-AzADApplication -DisplayName marjdtenancy | Select -First 1 | Remove-AzADApplication -Force
Get-AzADApplication -DisplayName marjdoperationscontrol | Select -First 1 | Remove-AzADApplication -Force
Get-AzADApplication -DisplayName marjdworkfloweng | Select -First 1 | Remove-AzADApplication -Force
Get-AzADApplication -DisplayName marjdworkflowmi | Select -First 1 | Remove-AzADApplication -Force
Get-AzADApplication -DisplayName marjdtenantadmin | Select -First 1 | Remove-AzADApplication -Force
