function DeployArmTemplate
{
    [CmdletBinding()]
    param
    (
        [string]$ArtifactsFolderPath,
        [string]$TemplateFileName,
        [Hashtable]$TemplateParameters,
        [Hashtable]$DeploymentContext
    )

    $ArmTemplatePath = Join-Path $ArtifactsFolderPath $TemplateFileName -Resolve
    $OptionalParameters = @{marainPrefix=$DeploymentContext.Prefix;environmentSuffix=$DeploymentContext.EnvironmentSuffix}
    $ResourceGroupName = $DeploymentContext.DefaultResourceGroupName

    $ArtifactsLocationName = '_artifactsLocation'
    $ArtifactsLocationSasTokenName = '_artifactsLocationSasToken'

    $StorageResourceGroupName = 'ARM_Deploy_Staging'
    $StorageContainerName = $ResourceGroupName.ToLowerInvariant().Replace(".", "") + '-stageartifacts'

    $StorageAccount = Get-AzStorageAccount -ResourceGroupName $StorageResourceGroupName -Name $DeploymentContext.DeploymentStagingStorageAccountName -ErrorAction SilentlyContinue

    # Create the storage account if it doesn't already exist
    if ($null -eq $StorageAccount) {
        New-AzResourceGroup -Location $DeploymentContext.AzureLocation -Name $StorageResourceGroupName -Force
        $StorageAccount = New-AzStorageAccount -StorageAccountName $DeploymentContext.DeploymentStagingStorageAccountName `
                                               -Type 'Standard_LRS' `
                                               -ResourceGroupName $StorageResourceGroupName `
                                               -Location $DeploymentContext.AzureLocation
    }

    # Copy files from the local storage staging location to the storage account container
    New-AzStorageContainer -Name $StorageContainerName -Context $StorageAccount.Context -ErrorAction SilentlyContinue *>&1

    $ArtifactFilePaths = Get-ChildItem $ArtifactsFolderPath -Recurse -File | ForEach-Object -Process {$_.FullName}
    foreach ($SourcePath in $ArtifactFilePaths) {
        Set-AzStorageBlobContent `
            -File $SourcePath `
            -Blob $SourcePath.Substring($ArtifactsFolderPath.length + 1) `
            -Container $StorageContainerName `
            -Context $StorageAccount.Context `
            -Force | Out-Null
    }

    $OptionalParameters[$ArtifactsLocationName] = $StorageAccount.Context.BlobEndPoint + $StorageContainerName
    # Generate a 4 hour SAS token for the artifacts location if one was not provided in the parameters file
    $StagingSasToken = New-AzStorageContainerSASToken `
        -Name $StorageContainerName `
        -Context $StorageAccount.Context `
        -Permission r `
        -ExpiryTime (Get-Date).AddHours(4)
    $OptionalParameters[$ArtifactsLocationSasTokenName] = ConvertTo-SecureString -AsPlainText -Force $StagingSasToken

    # Create the resource group only when it doesn't already exist
    if ((Get-AzResourceGroup -Name $ResourceGroupName -Location $DeploymentContext.AzureLocation -Verbose -ErrorAction SilentlyContinue) -eq $null) {
        New-AzResourceGroup -Name $ResourceGroupName -Location $DeploymentContext.AzureLocation -Verbose -Force -ErrorAction Stop
    }

    $DeploymentResult = New-AzResourceGroupDeployment `
        -Name ((Get-ChildItem $ArmTemplatePath).BaseName + '-' + ((Get-Date).ToUniversalTime()).ToString('MMdd-HHmm')) `
        -ResourceGroupName $ResourceGroupName `
        -TemplateFile $ArmTemplatePath `
        @OptionalParameters `
        @TemplateParameters `
        -Force -Verbose `
        -ErrorVariable ErrorMessages

    return $DeploymentResult
}