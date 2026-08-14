# --------------------------------------------------------------------------
# NAT Gateway (single, shared across all 3 AZs)
#
# NOTE: NAT Gateway IS a zonal resource in Azure. Deploying it without a
# "zones" argument places it in "no zone" (regional, non-zonal), which is
# the typical choice when sharing one NAT Gateway across multiple AZs - if
# you pin it to a single zone (e.g. zones = ["1"]) and that zone fails, the
# other AZs lose outbound connectivity through this NAT Gateway.
#
# For true zonal resilience, deploy one NAT Gateway per AZ (zones = ["1"],
# ["2"], ["3"]) and associate each with only that AZ's public subnet.
# --------------------------------------------------------------------------

# Public IP for the NAT Gateway (this is what provides "Internet Gateway"-like
# connectivity - in Azure, Internet access is a property of the public IP,
# not a separate gateway object attached to the VNet)
resource "azurerm_public_ip" "nat" {
  name                = "pip-nat-gateway"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_nat_gateway" "this" {
  name                    = "nat-gw-shared"
  location                = azurerm_resource_group.this.location
  resource_group_name     = azurerm_resource_group.this.name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 4
  tags                    = local.tags
}

resource "azurerm_nat_gateway_public_ip_association" "this" {
  nat_gateway_id       = azurerm_nat_gateway.this.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

# --------------------------------------------------------------------------
# NAT Gateway <-> Subnet associations
#
# The shared NAT Gateway is associated with the App subnet. Public subnets
# get their Internet egress via rt-public (0.0.0.0/0 -> Internet, the
# closest equivalent to an AWS Internet Gateway route), combined with
# resources in that subnet holding Public IPs.
# --------------------------------------------------------------------------

resource "azurerm_subnet_nat_gateway_association" "app" {
  subnet_id      = azurerm_subnet.app.id
  nat_gateway_id = azurerm_nat_gateway.this.id
}
