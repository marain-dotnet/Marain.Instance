[CmdletBinding()]
param
(
    [string] [Parameter(Mandatory=$true)] $EnvironmentSuffix,
    [string] $Prefix = "mar"
)
$ErrorActionPreference = 'Stop'

Write-Warning "About to delete ALL Marain resources:`n`tSubscription: $((Get-AzContext).Name)`n`tPrefix: $Prefix`n`tEnvironment: $EnvironmentSuffix"
Read-Host "Press Key To Confirm"

$ErrorActionPreference = 'Continue'
$groups = @(
    "tenancy"
    "operations"
    "workflow"
    "instance",
    "claims",
    "notifications"
)
$jobs = @()
foreach ($g in $groups) {
    $group = "{0}.{1}.{2}" -f $Prefix, $g, $EnvironmentSuffix
    Write-Host "Deleting resource group: $group ..."
    $jobs += Start-Job -Name $g -ScriptBlock { Remove-AzResourceGroup -Name $using:group -Force }
}
$jobs | % {
    Write-Host "Waiting for job: $($_.Name)"
    Wait-Job $_ | Out-Null
    Receive-Job $_
}
Write-Host "All jobs completed`n"

$aadApps = @(
    "tenancy"
    "operationscontrol"
    "workfloweng"
    "workflowmi"
    "claims"
    "tenantadmin"
    "usrnotidel"
    "usrnotimng"
)
foreach ($a in $aadApps) {
    $app = "{0}{1}{2}" -f $Prefix,  $EnvironmentSuffix, $a
    Write-Host "Deleting AAD app/principal: $app ..."
    Get-AzADApplication -DisplayName $app | Select -First 1 | Remove-AzADApplication -Force
}
