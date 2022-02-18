$here = Split-Path -Parent $PSCommandPath

$ctx = Get-AzContext

Describe "Infrastructure Tests" {

    Context "Simple - No Hosting" {

        $deployParams = @{
            SubscriptionId = $ctx.Subscription.Id
            AadTenantId = $ctx.Tenant.Id
            StackName = "marain"
            ServiceInstance = "nohost"
            Environment = "_simple-no-hosting"
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