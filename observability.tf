# Log Analytics Workspace + Flow Logs + diagnostic settings de las NSGs -
# nada de esto tiene un modulo AVM equivalente que cubra exactamente este
# uso (el flow log de VNet en particular no esta soportado por ninguna AVM,
# confirmado contra la doc de avm-res-network-virtualnetwork), asi que se
# mantienen como recursos planos, igual que antes de la migracion a AVM.
#
# Network Watcher en si no se crea aca - ya existe en NetworkWatcherRG,
# creado a mano una vez por consumidor (ver CLAUDE.md del consumidor).
data "azurerm_network_watcher" "this" {
  name                = "NetworkWatcher_${var.location}"
  resource_group_name = "NetworkWatcherRG"
}

resource "azurerm_log_analytics_workspace" "this" {
  name                = var.log_analytics_workspace_name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days
  tags                = local.tags
}

resource "azurerm_network_watcher_flow_log" "vnet" {
  #checkov:skip=CKV_AZURE_12:var.flow_log_retention_days default es 30, no >90 - decision cost-conscious (mas retencion = mas storage $$); el consumidor puede subirlo si lo necesita.
  name                 = "flowlog-${var.vnet_name}"
  network_watcher_name = data.azurerm_network_watcher.this.name
  resource_group_name  = data.azurerm_network_watcher.this.resource_group_name
  target_resource_id   = module.vnet.resource_id
  storage_account_id   = module.storage_flowlogs.resource_id
  enabled              = true
  version              = 2

  retention_policy {
    enabled = true
    days    = var.flow_log_retention_days
  }

  # Workaround para TAUserDoesNotHavePermissions
  # (hashicorp/terraform-provider-azurerm#31139) - problema conocido de
  # Azure/Terraform sin fix confirmado, ni con Contributor a nivel
  # suscripcion. El Flow Log en si sigue funcionando, solo se pierde el
  # dashboard de Traffic Analytics.
  traffic_analytics {
    enabled               = var.enable_traffic_analytics
    workspace_id          = azurerm_log_analytics_workspace.this.workspace_id
    workspace_region      = azurerm_log_analytics_workspace.this.location
    workspace_resource_id = azurerm_log_analytics_workspace.this.id
    interval_in_minutes   = 10
  }

  tags = local.tags
}

locals {
  # Mismos 6 NSGs que tenian diagnostic settings antes de la migracion.
  nsgs_with_diagnostics = {
    public      = azurerm_network_security_group.public.id
    private     = azurerm_network_security_group.private.id
    data        = azurerm_network_security_group.data.id
    privatelink = azurerm_network_security_group.privatelink.id
    appgw       = azurerm_network_security_group.appgw.id
    aks         = azurerm_network_security_group.aks.id
  }
}

resource "azurerm_monitor_diagnostic_setting" "nsg" {
  for_each = local.nsgs_with_diagnostics

  name                       = "diag-${each.key}"
  target_resource_id         = each.value
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "allLogs"
  }
}
