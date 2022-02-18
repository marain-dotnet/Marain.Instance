$here = Split-Path -Parent $PSCommandPath

$ctx = Get-AzContext

Describe "Infrastructure Tests" {

    Context "Simple - Container App Hosting" {

        $deployParams = @{
            SubscriptionId = $ctx.Subscription.Id
            AadTenantId = $ctx.Tenant.Id
            StackName = "marain"
            ServiceInstance = "conapp"
            Environment = "_simple-containerapp-hosting"
        }

        It "should be logged-in to Azure PowerShell" {
            $ctx | Should -Not -Be $null
        }
    
        It "should deploy successfully" {
            & $here/../deploy.ps1 @deployParams | Out-Null
        }

        It "should cleardown successfully" {
            & $here/../deploy.ps1 @deployParams -Cleardown | Out-Null
        }
    }
}