# --------------------------------------------------------------------------
# Current client/tenant data (needed for Key Vault access policy)
# --------------------------------------------------------------------------
data "azurerm_client_config" "current" {}

# ============================================================================
# Key Vault + Private Endpoint
# ============================================================================

resource "azurerm_key_vault" "this" {
  #checkov:skip=CKV_AZURE_110:purge protection deliberadamente off (ver comentario de la línea de abajo) - habilitarla es irreversible y bloquea el ciclo destroy/recreate frecuente de este proyecto demo.
  #checkov:skip=CKV_AZURE_42:mismo motivo que CKV_AZURE_110 - "recuperable" implica purge protection, que está off a propósito acá.
  name                       = var.key_vault_name
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  purge_protection_enabled   = false # set to true for production
  soft_delete_retention_days = 7
  rbac_authorization_enabled = true # Azure RBAC over legacy access policies - current MS/HashiCorp recommendation

  # Disable public network access - only reachable via Private Endpoint
  public_network_access_enabled = false

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
  }

  tags = var.tags
}

resource "azurerm_private_endpoint" "key_vault" {
  name                = "pe-key-vault"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = azurerm_subnet.privatelink.id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-key-vault"
    private_connection_resource_id = azurerm_key_vault.this.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.key_vault.id]
  }
}

resource "azurerm_private_dns_zone" "key_vault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "key_vault" {
  name                 = "link-key-vault"
  private_dns_zone_id  = azurerm_private_dns_zone.key_vault.id
  virtual_network_id   = azurerm_virtual_network.this.id
  registration_enabled = false
  tags                 = var.tags
}

# ============================================================================
# Storage Account (Blob + DFS for Data Lake Gen2) + Private Endpoints
# ============================================================================

resource "azurerm_storage_account" "this" {
  #checkov:skip=CKV_AZURE_33:este storage account no expone Queue service, no aplica.
  #checkov:skip=CKV_AZURE_206:ZRS por costo - ya cubre el diseño multi-AZ del proyecto (ver CLAUDE.md, "HA viene de zones, no de subnets por AZ"); GRS/geo-redundancia es un salto de costo (~2x) que el consumidor puede pedir explícitamente si lo necesita.
  #checkov:skip=CKV_AZURE_244:no se configuran local users/SFTP en ningún lado del módulo - is_hns_enabled=true es solo para habilitar Data Lake Gen2, no dispara SFTP.
  #checkov:skip=CKV2_AZURE_1:CMK generaría una dependencia circular con el Key Vault de este mismo módulo, además de costo de operaciones de Key Vault - decisión cost-conscious consistente con el resto del proyecto.
  name                     = var.storage_account_name
  location                 = var.location
  resource_group_name      = var.resource_group_name
  account_tier             = "Standard"
  account_replication_type = "ZRS" # zone-redundant, matches our multi-AZ design
  is_hns_enabled           = true  # enables Data Lake Gen2 (hierarchical namespace)
  min_tls_version          = "TLS1_2"

  # Solo autenticación Azure AD/RBAC, sin account keys - consistente con
  # rbac_authorization_enabled=true en el Key Vault de este mismo módulo.
  shared_access_key_enabled = false

  # Disable public network access - only reachable via Private Endpoint
  public_network_access_enabled   = false
  allow_nested_items_to_be_public = false

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }

  blob_properties {
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }

  sas_policy {
    expiration_period = "01.00:00:00"
    expiration_action = "Log"
  }

  tags = var.tags
}

# Private Endpoint for Blob sub-resource
resource "azurerm_private_endpoint" "storage_blob" {
  name                = "pe-storage-blob"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = azurerm_subnet.privatelink.id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-storage-blob"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.storage_blob.id]
  }
}

# Private Endpoint for DFS sub-resource (Data Lake Gen2 / ADLS Gen2 API)
resource "azurerm_private_endpoint" "storage_dfs" {
  name                = "pe-storage-dfs"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = azurerm_subnet.privatelink.id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-storage-dfs"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = ["dfs"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.storage_dfs.id]
  }
}

resource "azurerm_private_dns_zone" "storage_blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "storage_dfs" {
  name                = "privatelink.dfs.core.windows.net"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "storage_blob" {
  name                 = "link-storage-blob"
  private_dns_zone_id  = azurerm_private_dns_zone.storage_blob.id
  virtual_network_id   = azurerm_virtual_network.this.id
  registration_enabled = false
  tags                 = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "storage_dfs" {
  name                 = "link-storage-dfs"
  private_dns_zone_id  = azurerm_private_dns_zone.storage_dfs.id
  virtual_network_id   = azurerm_virtual_network.this.id
  registration_enabled = false
  tags                 = var.tags
}
