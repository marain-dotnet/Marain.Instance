function ParseJsonC
{
    [CmdletBinding()]
    param
    (
        [string] $path
    )

    # As of PowerShell 6, ConvertFrom-Json handles comments in JSON out of the box, so this is now
    # just a helper for loading JSON or JSONC from a path.
    return (Get-Content $path -raw) | ConvertFrom-Json
}
