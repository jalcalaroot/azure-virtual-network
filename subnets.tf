# --------------------------------------------------------------------------
# Subnets
# Azure subnets are NOT zonal objects (unlike AWS subnets). They are logical
# IP ranges within the VNet that already span all 3 zones in the region.
# High availability comes from the "zones" argument on the RESOURCES deployed
# into these subnets (VMs, VMSS, node pools) - not from having one subnet per
# zone.
# --------------------------------------------------------------------------

resource "azurerm_subnet" "public" {
  name                 = "snet-public"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.public_subnet_cidr]
}

resource "azurerm_subnet" "appgw" {
  name                 = "snet-appgw"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.appgw_subnet_cidr]
}

resource "azurerm_subnet" "app" {
  name                 = "snet-app"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.app_subnet_cidr]
}

resource "azurerm_subnet" "data" {
  name                 = "snet-data"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.data_subnet_cidr]

  # Optional: enable service endpoints for PaaS data services if needed
  # service_endpoints = ["Microsoft.Sql", "Microsoft.Storage"]
}
