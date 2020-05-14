[CmdletBinding()]
param
(
    [string] [Parameter(Mandatory=$true)] $EnvironmentSuffix,
    [string] $Prefix = "mar"
)
$ErrorActionPreference = 'Continue'

Write-Warning "About delete ALL Azure resources: Prefix=$Prefix; Environment=$EnvironmentSuffix"
Read-Host "Press Key To Confirm"

$groups = @(
    "tenancy"
    "operations"
    "workflow"
    "instance"
)
$jobs = @()
foreach ($g in $groups) {
    $group = "{0}.{1}.{2}" -f $Prefix, $g, $EnvironmentSuffix
    Write-Host "Deleting resource group: $group ..."
    $jobs += Start-Job -Name $g -ScriptBlock { Remove-AzResourceGroup -Name $group -Force }
}
$jobs | % { Write-Host "Waiting for job: $($_.Name)"; Wait-Job $_ | Out-Null }
Write-Host "All jobs completed`n"

$aadApps = @(
    "tenancy"
    "operationscontrol"
    "workfloweng"
    "workflowmi"
    "tenantadmin"
)
foreach ($a in $aadApps) {
    $app = "{0}{1}{2}" -f $Prefix,  $EnvironmentSuffix, $a
    Write-Host "Deleting AAD app/principal: $app ..."
    Get-AzADApplication -DisplayName $app | Select -First 1 | Remove-AzADApplication -Force
}
