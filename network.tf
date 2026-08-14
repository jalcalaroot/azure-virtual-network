locals {
  base_tags = {
    ambiente    = var.environment
    propietario = var.owner
    proyecto    = var.project
  }

  tags = merge(local.base_tags, var.tags)
}

# Resource group containing all networking resources
resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

# Virtual Network (equivalent to AWS VPC)
resource "azurerm_virtual_network" "this" {
  name                = var.vnet_name
  address_space       = var.vnet_address_space
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags

  lifecycle {
    prevent_destroy = true
  }
}
