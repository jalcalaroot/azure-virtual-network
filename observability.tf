# ============================================================================
# Observabilidad: Virtual Network Flow Logs + Traffic Analytics + Diagnostic
# Settings hacia Log Analytics.
#
# Network Watcher es un recurso único por región/suscripción, autogestionado
# por Azure - no se crea, se referencia el existente (NetworkWatcher_<region>
# en la RG NetworkWatcherRG).
# ============================================================================

data "azurerm_network_watcher" "this" {
  name                = "NetworkWatcher_${var.location}"
  resource_group_name = "NetworkWatcherRG"
}

resource "azurerm_log_analytics_workspace" "this" {
  name                = var.log_analytics_workspace_name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days
  tags                = var.tags
}

# Storage account dedicado al Flow Log, separado del storage de datos
# (azurerm_storage_account.this) para no depender de sus reglas de firewall -
# los Flow Logs no soportan Private Endpoint como destino.
resource "azurerm_storage_account" "flow_logs" {
  #checkov:skip=CKV_AZURE_33:este storage account no expone Queue service, no aplica.
  #checkov:skip=CKV_AZURE_206:LRS por costo - son logs operacionales no críticos, no datos de negocio (decisión cost-conscious consistente con el resto del proyecto).
  #checkov:skip=CKV2_AZURE_33:los Flow Logs no soportan Private Endpoint como destino (ver comentario arriba) - se restringe con network_rules + bypass=AzureServices en su lugar.
  #checkov:skip=CKV2_AZURE_40:no hay evidencia documentada de que Network Watcher pueda escribir Flow Logs en un storage account con Shared Key deshabilitado - se prioriza que la observabilidad funcione sobre este check (ver https://learn.microsoft.com/en-us/answers/questions/2153160/, que asume key access habilitado como troubleshooting step). Revisar si Microsoft documenta soporte AAD-only en el futuro.
  #checkov:skip=CKV2_AZURE_41:consecuencia directa del skip anterior - este check requiere Shared Key deshabilitado como precondición.
  #checkov:skip=CKV2_AZURE_1:CMK generaría costo de operaciones de Key Vault por un dato operacional (logs), no crítico - decisión cost-conscious consistente con el resto del proyecto.
  name                     = var.flow_logs_storage_account_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  # Cerrado a acceso público - Network Watcher escribe los flow logs como
  # servicio confiable de Azure (bypass=AzureServices lo cubre, no requiere
  # el storage account público). allow_nested_items_to_be_public es
  # independiente de shared_access_key: bloquea acceso anónimo a blobs/
  # contenedores sin afectar cómo Network Watcher escribe.
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

# Virtual Network Flow Log - sucesor de los NSG Flow Logs (retirados para
# creaciones nuevas desde junio 2025). Cubre toda la VNet con un solo
# recurso en vez de uno por NSG.
resource "azurerm_network_watcher_flow_log" "vnet" {
  #checkov:skip=CKV_AZURE_12:default de var.flow_log_retention_days es 30, no >90 - decisión cost-conscious (más retención = más storage $$); el consumidor puede subirlo si lo necesita.
  name                 = "flowlog-${var.vnet_name}"
  network_watcher_name = data.azurerm_network_watcher.this.name
  resource_group_name  = data.azurerm_network_watcher.this.resource_group_name

  target_resource_id = azurerm_virtual_network.this.id
  storage_account_id = azurerm_storage_account.flow_logs.id
  enabled            = true
  version            = 2

  retention_policy {
    enabled = true
    days    = var.flow_log_retention_days
  }

  traffic_analytics {
    enabled               = var.enable_traffic_analytics
    workspace_id          = azurerm_log_analytics_workspace.this.workspace_id
    workspace_region      = azurerm_log_analytics_workspace.this.location
    workspace_resource_id = azurerm_log_analytics_workspace.this.id
    interval_in_minutes   = 10
  }

  tags = var.tags
}

locals {
  nsgs = {
    public      = azurerm_network_security_group.public.id
    private     = azurerm_network_security_group.private.id
    data        = azurerm_network_security_group.data.id
    privatelink = azurerm_network_security_group.privatelink.id
    appgw       = azurerm_network_security_group.appgw.id
    aks         = azurerm_network_security_group.aks.id
  }
}

# Diagnostic settings: eventos/reglas de NSG (hits de reglas allow/deny).
resource "azurerm_monitor_diagnostic_setting" "nsg" {
  for_each = local.nsgs

  name                       = "diag-${each.key}"
  target_resource_id         = each.value
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "allLogs"
  }
}

resource "azurerm_monitor_diagnostic_setting" "vnet" {
  name                       = "diag-${var.vnet_name}"
  target_resource_id         = azurerm_virtual_network.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "key_vault" {
  name                       = "diag-key-vault"
  target_resource_id         = azurerm_key_vault.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "audit"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

# El storage account de datos solo expone métricas de transacción a nivel de
# cuenta - los logs de acceso viven en el sub-recurso blobServices.
resource "azurerm_monitor_diagnostic_setting" "storage_account" {
  name                       = "diag-storage-account"
  target_resource_id         = azurerm_storage_account.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_metric {
    category = "Transaction"
  }
}

resource "azurerm_monitor_diagnostic_setting" "storage_blob" {
  name                       = "diag-storage-blob"
  target_resource_id         = "${azurerm_storage_account.this.id}/blobServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "Transaction"
  }
}
