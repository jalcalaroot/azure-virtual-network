# 2 Storage Accounts, migrados a Azure/avm-res-storage-storageaccount/azurerm
# el 2026-09-28 - ver network.tf para el contexto completo de la migracion a
# AVM.
#
# shared_access_key_enabled: el default de esta AVM es false (RBAC-only) -
# distinto del default real del recurso azurerm_storage_account (true), que
# es lo que la cuenta de flow logs tenia implicitamente antes de esta
# migracion (nunca se seteaba a mano). Network Watcher todavia depende de
# acceso por key/SAS para escribir flow logs, asi que se fuerza a proposito
# en la cuenta de flow logs para no romperlo con el nuevo default de la
# AVM - la cuenta de datos si lo tenia en false explicito desde antes, sin
# cambios ahi.

resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = var.resource_group_name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  name                  = "link-blob-${var.vnet_name}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = module.vnet.resource_id
  registration_enabled  = false
  tags                  = local.tags
}

resource "azurerm_private_dns_zone" "dfs" {
  name                = "privatelink.dfs.core.windows.net"
  resource_group_name = var.resource_group_name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "dfs" {
  name                  = "link-dfs-${var.vnet_name}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.dfs.name
  virtual_network_id    = module.vnet.resource_id
  registration_enabled  = false
  tags                  = local.tags
}

module "storage_flowlogs" {
  #checkov:skip=CKV_TF_1:pinned por version semver del Terraform Registry, no un git tag - ver el mismo skip en network.tf para el detalle completo.
  source  = "Azure/avm-res-storage-storageaccount/azurerm"
  version = "0.10.0"

  #checkov:skip=CKV_AZURE_33:este storage account no expone Queue service, no aplica.
  #checkov:skip=CKV_AZURE_206:LRS por costo - son logs operacionales no criticos, no datos de negocio.
  #checkov:skip=CKV2_AZURE_33:los Flow Logs no soportan Private Endpoint como destino - se restringe con network_rules + bypass=AzureServices en su lugar.
  #checkov:skip=CKV2_AZURE_40:no hay evidencia documentada de que Network Watcher pueda escribir Flow Logs en un storage account con Shared Key deshabilitado - se prioriza que la observabilidad funcione sobre este check.
  #checkov:skip=CKV2_AZURE_41:consecuencia directa del skip anterior - este check requiere Shared Key deshabilitado como precondicion.
  #checkov:skip=CKV2_AZURE_1:CMK generaria costo de operaciones de Key Vault por un dato operacional (logs), no critico.
  name      = var.flow_logs_storage_account_name
  location  = var.location
  parent_id = data.azurerm_resource_group.this.id
  tags      = local.tags

  enable_telemetry = false

  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  public_network_access_enabled   = false
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = true # Network Watcher escribe flow logs via key/SAS - ver comentario arriba

  network_rules = {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }

  blob_properties = {
    delete_retention_policy           = { days = 7 }
    container_delete_retention_policy = { days = 7 }
  }

  sas_policy = {
    expiration_period = "01.00:00:00"
    expiration_action = "Log"
  }
}

module "storage_data" {
  #checkov:skip=CKV_TF_1:pinned por version semver del Terraform Registry, no un git tag - ver el mismo skip en network.tf para el detalle completo.
  source  = "Azure/avm-res-storage-storageaccount/azurerm"
  version = "0.10.0"

  #checkov:skip=CKV_AZURE_33:este storage account no expone Queue service, no aplica.
  #checkov:skip=CKV_AZURE_206:ZRS por costo - ya cubre el diseno multi-AZ del proyecto (HA viene de zones, no de subnets por AZ); GRS/geo-redundancia es un salto de costo (~2x) que el consumidor puede pedir explicitamente si lo necesita.
  #checkov:skip=CKV_AZURE_244:no se configuran local users/SFTP en ningun lado del modulo - is_hns_enabled=true es solo para habilitar Data Lake Gen2, no dispara SFTP.
  #checkov:skip=CKV2_AZURE_1:CMK generaria una dependencia circular con el Key Vault de este mismo modulo, ademas de costo de operaciones de Key Vault.
  name      = var.storage_account_name
  location  = var.location
  parent_id = data.azurerm_resource_group.this.id
  tags      = local.tags

  enable_telemetry = false

  account_tier                  = "Standard"
  account_replication_type      = "ZRS"
  is_hns_enabled                = true # ADLS Gen2
  min_tls_version               = "TLS1_2"
  shared_access_key_enabled     = false
  public_network_access_enabled = false

  network_rules = {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }

  blob_properties = {
    delete_retention_policy           = { days = 7 }
    container_delete_retention_policy = { days = 7 }
  }

  sas_policy = {
    expiration_period = "01.00:00:00"
    expiration_action = "Log"
  }

  # name explicito y distinto por entrada - sin esto, el modulo genera el
  # mismo nombre de private endpoint por defecto para ambas subresources
  # (blob y dfs sobre la MISMA storage account), y la segunda intenta
  # modificar la conexion de la primera en vez de crear un recurso nuevo -
  # error real encontrado en el primer apply:
  # "CannotChangePrivateLinkConnectionOnPrivateEndpoint".
  private_endpoints = {
    blob = {
      name                          = "pe-${var.storage_account_name}-blob"
      subnet_resource_id            = module.vnet.subnets["privatelink"].resource_id
      subresource_name              = "blob"
      private_dns_zone_resource_ids = [azurerm_private_dns_zone.blob.id]
    }
    dfs = {
      name                          = "pe-${var.storage_account_name}-dfs"
      subnet_resource_id            = module.vnet.subnets["privatelink"].resource_id
      subresource_name              = "dfs"
      private_dns_zone_resource_ids = [azurerm_private_dns_zone.dfs.id]
    }
  }

  # diagnostic_settings_storage_account / diagnostic_settings_blob
  # deliberadamente OMITIDOS (2026-09-28). Ambos usan azapi_resource
  # internamente (ARM PUT crudo) en vez de un azurerm_monitor_diagnostic_setting
  # nativo, y ese path golpeo "context deadline exceeded" -> 404
  # ResourceNotFound en el read-back en 3 intentos de apply distintos,
  # separados en el tiempo (no fue una race puntual). Parece un problema
  # real de latencia de propagacion de la API de Azure con este patron
  # especifico de azapi, no un error en la config. Telemetria no critica
  # (metricas de Transaction de la storage account) - se prefiere no
  # bloquear el resto del modulo reintentando indefinidamente contra un
  # endpoint que consistentemente tarda mas que el timeout del provider
  # azapi.
}
