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
  name                     = var.flow_logs_storage_account_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  tags = var.tags
}

# Virtual Network Flow Log - sucesor de los NSG Flow Logs (retirados para
# creaciones nuevas desde junio 2025). Cubre toda la VNet con un solo
# recurso en vez de uno por NSG.
resource "azurerm_network_watcher_flow_log" "vnet" {
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
    enabled               = true
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
