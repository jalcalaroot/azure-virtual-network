output "vnet_id" {
  description = "ID of the created Virtual Network"
  value       = module.vnet.resource_id
}

output "appgw_subnet_id" {
  description = "ID de la subnet dedicada de Application Gateway"
  value       = module.vnet.subnets["appgw"].resource_id
}

output "appgw_subnet_cidr" {
  description = "CIDR de la subnet dedicada de Application Gateway"
  value       = var.appgw_subnet_cidr
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = module.vnet.subnets["public"].resource_id
}

output "app_subnet_id" {
  description = "ID of the app subnet"
  value       = module.vnet.subnets["app"].resource_id
}

output "data_subnet_id" {
  description = "ID of the data subnet"
  value       = module.vnet.subnets["data"].resource_id
}

output "nat_gateway_id" {
  description = "ID of the shared NAT Gateway"
  value       = azurerm_nat_gateway.this.id
}

output "nat_gateway_public_ip" {
  description = "Public IP address used by the NAT Gateway for outbound traffic"
  value       = azurerm_public_ip.nat.ip_address
}

output "nsg_public_id" {
  description = "ID of the NSG applied to the public subnet"
  value       = azurerm_network_security_group.public.id
}

output "nsg_private_id" {
  description = "ID of the NSG applied to the app subnet"
  value       = azurerm_network_security_group.private.id
}

output "nsg_data_id" {
  description = "ID of the NSG applied to the data subnet"
  value       = azurerm_network_security_group.data.id
}

output "privatelink_subnet_id" {
  description = "ID of the shared Private Endpoints subnet"
  value       = module.vnet.subnets["privatelink"].resource_id
}

output "aks_subnet_id" {
  description = "ID de la subnet dedicada de AKS"
  value       = module.vnet.subnets["aks"].resource_id
}

output "aks_subnet_cidr" {
  description = "CIDR de la subnet dedicada de AKS"
  value       = var.aks_subnet_cidr
}

output "key_vault_id" {
  description = "ID of the Key Vault"
  value       = module.key_vault.resource_id
}

output "storage_account_id" {
  description = "ID of the Storage Account"
  value       = module.storage_data.resource_id
}

# Sin output de IP de los private endpoints (existia antes de la migracion
# a AVM) - las AVM de Key Vault/Storage solo exponen id/name/role_assignments
# por private endpoint, no la IP asignada. Tampoco hace falta: la resolucion
# real pasa por la Private DNS Zone (privatelink.vaultcore.azure.net / .blob.
# / .dfs.core.windows.net, linkeadas a esta VNet), no por consumir la IP
# cruda desde otro repo - ningun consumidor documentado (ver CLAUDE.md) las
# leia de todas formas.

output "route_table_public_id" {
  description = "ID of the route table applied to the public subnet (0.0.0.0/0 -> Internet)"
  value       = azurerm_route_table.public.id
}

output "route_table_app_id" {
  description = "ID of the route table applied to the app subnet (Internet egress via NAT Gateway association)"
  value       = azurerm_route_table.app.id
}

output "route_table_data_id" {
  description = "ID of the route table applied to the data subnet (0.0.0.0/0 -> None, Internet egress blocked)"
  value       = azurerm_route_table.data.id
}

output "log_analytics_workspace_id" {
  description = "ID del Log Analytics workspace de la red, para que otros proyectos (AKS, etc.) puedan enviar sus propios diagnostic settings ahi"
  value       = azurerm_log_analytics_workspace.this.id
}
