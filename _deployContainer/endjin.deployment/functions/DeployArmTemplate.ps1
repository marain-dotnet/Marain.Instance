function DeployArmTemplate
{
    [CmdletBinding()]
    param
    (
        [string]$ArtifactsFolderPath,
        [string]$TemplateFileName,
        [Hashtable]$TemplateParameters,
        [string]$ResourceGroupName
    )

    $ArmTemplatePath = Join-Path $ArtifactsFolderPath $TemplateFileName -Resolve
    $OptionalParameters = @{marainPrefix=$this.Prefix;environmentSuffix=$this.EnvironmentSuffix}

    $ArtifactsLocationName = '_artifactsLocation'
    $ArtifactsLocationSasTokenName = '_artifactsLocationSasToken'

    $StorageResourceGroupName = 'ARM_Deploy_Staging'
    $StorageContainerName = $ResourceGroupName.ToLowerInvariant().Replace(".", "") + '-stageartifacts'

    $StorageAccount = Get-AzStorageAccount -ResourceGroupName $StorageResourceGroupName -Name $this.DeploymentStagingStorageAccountName -ErrorAction SilentlyContinue

    # Create the storage account if it doesn't already exist
    if ($null -eq $StorageAccount) {
        New-AzResourceGroup -Location $this.AzureLocation -Name $StorageResourceGroupName -Force
        $StorageAccount = New-AzStorageAccount -StorageAccountName $this.DeploymentStagingStorageAccountName  -Type 'Standard_LRS' -ResourceGroupName $StorageResourceGroupName -Location $this.AzureLocation
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
            -Force
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
    if ((Get-AzResourceGroup -Name $ResourceGroupName -Location $this.AzureLocation -Verbose -ErrorAction SilentlyContinue) -eq $null) {
        New-AzResourceGroup -Name $ResourceGroupName -Location $this.AzureLocation -Verbose -Force -ErrorAction Stop
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