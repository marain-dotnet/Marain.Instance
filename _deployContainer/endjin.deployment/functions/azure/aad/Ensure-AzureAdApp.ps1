function Ensure-AzureAdApp
{
    [CmdletBinding()]
    param
    (
        [string]$DisplayName,
        [string]$AppUri,
        [string[]]$ReplyUrls
    )

    Write-Host "`nEnsuring Azure AD application {$DisplayName} exists" -ForegroundColor Green

    $app = Get-AzADApplication -DisplayNameStartWith $DisplayName | `
                Where-Object {$_.DisplayName -eq $DisplayName}
    
    if ($app) {
        Write-Host "Found existing app with id $($app.ApplicationId)"
        $ReplyUrlsOk = $true
        ForEach ($ReplyUrl in $ReplyUrls) {
            if (-not $app.ReplyUrls.Contains($ReplyUrl)) {
                $ReplyUrlsOk = $false
                Write-Host "Reply URL $ReplyUrl not present in app"
            }
        }

        if (-not $ReplyUrlsOk) {
            Write-Host "Setting reply URLs: $replyUrls"
            $app = Update-AzADApplication -ObjectId $app.ObjectId `
                                          -ReplyUrl $ReplyUrls
        }
    } else {
        $app = New-AzADApplication -DisplayName $DisplayName `
                                   -IdentifierUris $AppUri `
                                   -HomePage $AppUri `
                                   -ReplyUrls $ReplyUrls
        Write-Host "Created new app with id $($app.ApplicationId)"
    }

    # return the native Az cmdlet application object
    return $app
}
