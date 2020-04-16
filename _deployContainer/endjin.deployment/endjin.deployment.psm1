# Dynamically populate the module
#
# NOTE:
#  1) Ignore any Pester test fixtures
#
$functions = Get-ChildItem -Recurse $PSScriptRoot -Include *.ps1 | `
                Where-Object { $_ -notmatch ".Tests.ps1" }

# dot source the individual scripts that make-up this module
foreach ($function in $functions) { . $function.FullName }

# export the non-private functions (by convention, private function scripts must begin with an '_' character)
Export-ModuleMember -function ( $functions | 
									ForEach-Object { (Get-Item $_).BaseName } | 
									Where-Object { -not $_.StartsWith("_") }
							)