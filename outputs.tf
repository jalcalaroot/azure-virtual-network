output "resource_group_name" {
  description = "Name of the resource group (pass this to the jumpbox project's resource_group_name variable)"
  value       = azurerm_resource_group.this.name
}

output "vnet_id" {
  description = "ID of the created Virtual Network"
  value       = azurerm_virtual_network.this.id
}

output "appgw_subnet_id" {
  description = "ID de la subnet dedicada de Application Gateway"
  value       = azurerm_subnet.appgw.id
}

output "appgw_subnet_cidr" {
  description = "CIDR de la subnet dedicada de Application Gateway"
  value       = var.appgw_subnet_cidr
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = azurerm_subnet.public.id
}

output "app_subnet_id" {
  description = "ID of the app subnet"
  value       = azurerm_subnet.app.id
}

output "data_subnet_id" {
  description = "ID of the data subnet"
  value       = azurerm_subnet.data.id
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
  value       = azurerm_subnet.privatelink.id
}

output "aks_subnet_id" {
  description = "ID de la subnet dedicada de AKS"
  value       = azurerm_subnet.aks.id
}

output "aks_subnet_cidr" {
  description = "CIDR de la subnet dedicada de AKS"
  value       = var.aks_subnet_cidr
}

output "key_vault_id" {
  description = "ID of the Key Vault"
  value       = azurerm_key_vault.this.id
}

output "key_vault_private_endpoint_ip" {
  description = "Private IP address assigned to the Key Vault Private Endpoint"
  value       = azurerm_private_endpoint.key_vault.private_service_connection[0].private_ip_address
}

output "storage_account_id" {
  description = "ID of the Storage Account"
  value       = azurerm_storage_account.this.id
}

output "storage_blob_private_endpoint_ip" {
  description = "Private IP address assigned to the Storage Account Blob Private Endpoint"
  value       = azurerm_private_endpoint.storage_blob.private_service_connection[0].private_ip_address
}

output "storage_dfs_private_endpoint_ip" {
  description = "Private IP address assigned to the Storage Account DFS (ADLS Gen2) Private Endpoint"
  value       = azurerm_private_endpoint.storage_dfs.private_service_connection[0].private_ip_address
}

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
  description = "ID del Log Analytics workspace de la red, para que otros proyectos (AKS, etc.) puedan enviar sus propios diagnostic settings ahí"
  value       = azurerm_log_analytics_workspace.this.id
}
