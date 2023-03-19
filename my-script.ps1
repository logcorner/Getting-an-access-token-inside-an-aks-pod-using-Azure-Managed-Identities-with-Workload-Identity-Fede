Import-Module Az.Accounts

# Retrieve the managed identity's access token
Write-Host "AZURE_AUTHORITY_HOST :  $Env:AZURE_AUTHORITY_HOST"
Write-Host "AZURE_CLIENT_ID : $Env:AZURE_CLIENT_ID"
Write-Host "AZURE_TENANT_ID :  $Env:AZURE_TENANT_ID"
Write-Host "AZURE_FEDERATED_TOKEN_FILE :  $Env:AZURE_FEDERATED_TOKEN_FILE"

$azureAdTokenExchange=Get-Content $Env:AZURE_FEDERATED_TOKEN_FILE -Raw

Write-Host " AZURE AD TOKEN EXCHANGE : $azureAdTokenExchange"

Connect-AzAccount -ApplicationId $Env:AZURE_CLIENT_ID -TenantId $Env:AZURE_TENANT_ID -FederatedToken $azureAdTokenExchange

$azureAccessToken = Get-AzAccessToken -ResourceUrl "https://management.core.windows.net/"  | ConvertTo-Json

Write-Host " jwt token with audience https://management.core.windows.net  : $azureAccessToken"