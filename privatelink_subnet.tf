# --------------------------------------------------------------------------
# Private Endpoints subnet
#
# Private Endpoints are NOT zonal resources, so a single subnet (shared
# across all 3 AZs) is sufficient for the whole VNet.
#
# Private endpoint network policies must be disabled on this subnet so
# Private Endpoints can be created in it without NSG/route table conflicts
# on the private endpoint NICs themselves (NSGs on the subnet still apply
# to traffic going TO the endpoint).
# --------------------------------------------------------------------------

resource "azurerm_subnet" "privatelink" {
  name                 = "snet-privatelink"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.privatelink_subnet_cidr]

  private_endpoint_network_policies = "Disabled"
}

# NSG-PrivateLink: only allows traffic from App and Data subnets toward
# the Private Endpoints (Key Vault: 443, Storage: 443, SQL/Postgres: 1433/5432)
resource "azurerm_network_security_group" "privatelink" {
  name                = "nsg-privatelink"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  security_rule {
    name                       = "Allow-From-App-And-Data-Subnets"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["443", "1433", "5432"]
    source_address_prefixes    = [var.app_subnet_cidr, var.data_subnet_cidr]
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "Deny-All-Inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "privatelink" {
  subnet_id                 = azurerm_subnet.privatelink.id
  network_security_group_id = azurerm_network_security_group.privatelink.id
}
