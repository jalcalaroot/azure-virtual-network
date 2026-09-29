# Mismo storage account de tfstate que el resto de la cuenta, key propio
# para no pisar el state principal de este repo
# (virtual-network/terraform.tfstate). Root deliberadamente separado - ver
# CLAUDE.md, seccion "Identidades de CI en state propio".
terraform {
  backend "azurerm" {
    resource_group_name  = "jalcalaroot"
    storage_account_name = "sttfstatejalcalaroot"
    container_name       = "tfstate"
    key                  = "virtual-network-ci/terraform.tfstate"
    use_azuread_auth     = true
  }
}
