function UploadReleaseAssetAsAppServiceSitePackage
{
    [CmdletBinding()]
    param
    (
        [string]$AssetName,
        [string]$AppServiceName
    )

    $WebApp = Get-AzWebApp -Name $AppServiceName
    if (-not $WebApp) {
        Write-Error "Did not find web app $AppServiceName"
        return
    }
    $ReleaseAssets = $this.GitHubRelease.assets | Where-Object  { $_.name -eq $AssetName }
    if ($ReleaseAssets.Count -ne 1) {
        Write-Error ("Expecting exactly one asset named {0}, found {1}" -f $AssetName, $ReleaseAssets.Count)
    }
    $ReleaseAsset = $ReleaseAssets[0]
    $url = $ReleaseAsset.browser_download_url
    $AssetPath = Join-Path $this.TempFolder $AssetName
    Write-Host "Will deploy file at $url to $AppServiceName"
    Invoke-WebRequest -Uri $url -OutFile $AssetPath
    Publish-AzWebApp `
        -Force `
        -ArchivePath $AssetPath `
        -WebApp $WebApp
}