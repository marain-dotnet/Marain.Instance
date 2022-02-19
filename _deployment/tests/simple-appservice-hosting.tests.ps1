$here = Split-Path -Parent $PSCommandPath
$VerbosePreference = "SilentlyContinue"

$ctx = Get-AzContext

Describe "Infrastructure Tests" {

    Context "Simple - App Service Hosting" {

        $deployParams = @{
            SubscriptionId = $ctx.Subscription.Id
            AadTenantId = $ctx.Tenant.Id
            StackName = "marain"
            ServiceInstance = "appsvc"
            Environment = "_simple-appservice-hosting"
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