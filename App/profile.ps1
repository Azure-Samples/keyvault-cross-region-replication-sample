# profile.ps1 — runs once per Function App worker start-up.
# Authenticates via system-assigned Managed Identity when running in Azure.
# When running locally with Azure CLI credentials, Connect-AzAccount is not needed.

if ($env:MSI_ENDPOINT -or $env:IDENTITY_ENDPOINT) {
    Connect-AzAccount -Identity | Out-Null
}
