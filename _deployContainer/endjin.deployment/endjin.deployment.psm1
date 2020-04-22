# Dynamically populate the module
#
# NOTE:
#  1) Ignore any Pester test fixtures
#
[array]$classes = Get-ChildItem -Recurse $PSScriptRoot/classes -Include *.ps1 | `
				Where-Object { $_ -notmatch ".Tests.ps1" }

# dot source the individual scripts that make-up this module
foreach ($class in ($classes)) { . $class.FullName }


$functions = Get-ChildItem -Recurse $PSScriptRoot/functions -Include *.ps1 | `
                Where-Object { $_ -notmatch ".Tests.ps1" }
					
# dot source the individual scripts that make-up this module
foreach ($function in ($functions)) { . $function.FullName }

# setup variables to maintain module instance state - maybe not a permanent arrangement
$script:DeploymentContext = @{}
$script:ServiceDeploymentContext = @{}

# export the non-private functions (by convention, private function scripts must begin with an '_' character)
Export-ModuleMember -function ( $functions | 
									ForEach-Object { (Get-Item $_).BaseName } | 
									Where-Object { -not $_.StartsWith("_") }
							) `
					-variable @('DeploymentContext','ServiceDeploymentContext')
