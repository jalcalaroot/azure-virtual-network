# Migrado a Azure/avm-res-keyvault-vault/azurerm el 2026-09-28 - ver
# network.tf para el contexto completo de la migracion a AVM.
#
# Gotcha real de esta AVM (no como la de red): usa resource_group_name
# (nombre), NO parent_id (ID) - cada modulo AVM tiene su propia convencion,
# no asumir que todas comparten la misma.
#
# No existe una variable rbac_authorization_enabled - RBAC es el modo por
# defecto del modulo, alcanza con dejar legacy_access_policies_enabled en
# su default (false).
data "azurerm_client_config" "current" {}

resource "azurerm_private_dns_zone" "vaultcore" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "vaultcore" {
  name                  = "link-vaultcore-${var.vnet_name}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.vaultcore.name
  virtual_network_id    = module.vnet.resource_id
  registration_enabled  = false
  tags                  = var.tags
}

module "key_vault" {
  #checkov:skip=CKV_TF_1:pinned por version semver del Terraform Registry, no un git tag - ver el mismo skip en network.tf para el detalle completo.
  source  = "Azure/avm-res-keyvault-vault/azurerm"
  version = "0.11.0"

  #checkov:skip=CKV_AZURE_110:purge protection deliberadamente off (ver comentario de la linea de abajo) - habilitarla es irreversible y bloquea el ciclo destroy/recreate frecuente de este proyecto.
  #checkov:skip=CKV_AZURE_42:mismo motivo que CKV_AZURE_110 - "recuperable" implica purge protection, que esta off a proposito aca.
  name                = var.key_vault_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  tags                = var.tags

  enable_telemetry = false

  sku_name                      = "standard"
  purge_protection_enabled      = false
  soft_delete_retention_days    = 7
  public_network_access_enabled = false

  network_acls = {
    bypass         = "AzureServices"
    default_action = "Deny"
  }

  private_endpoints = {
    vault = {
      subnet_resource_id            = module.vnet.subnets["privatelink"].resource_id
      private_dns_zone_resource_ids = [azurerm_private_dns_zone.vaultcore.id]
    }
  }

  diagnostic_settings = {
    sendToLogAnalytics = {
      workspace_resource_id = azurerm_log_analytics_workspace.this.id
    }
  }
}
