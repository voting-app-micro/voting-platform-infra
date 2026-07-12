# Resource Group Inside which our TfState storage account will exist
$rg = "tfstatestorage12125-rg"
# Storage account Name
$storageAccount = "tfstatestorage12125"

az group create -n $rg -l eastus
az storage account create -n $storageAccount -g $rg -l eastus --sku Standard_LRS
az storage account blob-service-properties update -g $rg --account-name $storageAccount --enable-versioning true --enable-delete-retention true --delete-retention-days 30
az storage container create -n tfstate --account-name $storageAccount
