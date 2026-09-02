# Virtual Network (equivalent to AWS VPC). Deployed into the existing
# resource group passed in via var.resource_group_name - this module never
# creates or manages a resource group itself.
resource "azurerm_virtual_network" "this" {
  name                = var.vnet_name
  address_space       = var.vnet_address_space
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  lifecycle {
    prevent_destroy = true
  }
}
