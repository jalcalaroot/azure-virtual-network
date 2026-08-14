# ============================================================================
# Route Tables (UDRs)
#
# Added for explicit, auditable routing instead of relying purely on Azure's
# implicit system routes. See README.md "Routing" section for the full
# explanation of how each tier reaches (or is blocked from) the Internet.
#
# IMPORTANT - NAT Gateway as next hop:
# Azure NAT Gateway CANNOT be referenced as a next_hop_type in a UDR. The
# only way for a subnet to route outbound traffic through a NAT Gateway is
# a direct subnet <-> NAT Gateway association (azurerm_subnet_nat_gateway_
# association). That association itself injects the effective "0.0.0.0/0 ->
# NAT Gateway" route - it cannot be expressed as a UDR route entry.
#
# Therefore:
#   - rt-public: explicit 0.0.0.0/0 -> Internet. This is the closest
#     equivalent to an AWS Internet Gateway route table entry - resources in
#     these subnets reach the Internet directly via their Public IPs.
#   - rt-app: no 0.0.0.0/0 UDR entry. Outbound-to-Internet for the App tier
#     is provided by associating the shared NAT Gateway to the App subnets
#     (see nat_gateway.tf). The route table here exists for VNet-local
#     routing visibility and future custom routes (e.g. forced tunneling to
#     a firewall).
#   - rt-data: explicit 0.0.0.0/0 -> None, blocking all Internet egress as a
#     defense-in-depth measure independent of NSG rules.
# ============================================================================

resource "azurerm_route_table" "public" {
  name                          = "rt-public"
  location                      = azurerm_resource_group.this.location
  resource_group_name           = azurerm_resource_group.this.name
  bgp_route_propagation_enabled = true
  tags                          = local.tags

  route {
    name           = "to-internet"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "Internet"
  }
}

resource "azurerm_route_table" "app" {
  name                          = "rt-app"
  location                      = azurerm_resource_group.this.location
  resource_group_name           = azurerm_resource_group.this.name
  bgp_route_propagation_enabled = true
  tags                          = local.tags

  # No 0.0.0.0/0 entry here - outbound Internet access for App subnets is
  # provided via direct NAT Gateway association (see nat_gateway.tf).
  # This table is reserved for VNet-local routes and future custom routes.
}

resource "azurerm_route_table" "data" {
  name                          = "rt-data"
  location                      = azurerm_resource_group.this.location
  resource_group_name           = azurerm_resource_group.this.name
  bgp_route_propagation_enabled = false
  tags                          = local.tags

  route {
    name           = "block-internet"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "None"
  }
}

# ----------------------------------------------------------------------------
# Route Table <-> Subnet associations
# ----------------------------------------------------------------------------

resource "azurerm_subnet_route_table_association" "public" {
  subnet_id      = azurerm_subnet.public.id
  route_table_id = azurerm_route_table.public.id
}

resource "azurerm_subnet_route_table_association" "app" {
  subnet_id      = azurerm_subnet.app.id
  route_table_id = azurerm_route_table.app.id
}

resource "azurerm_subnet_route_table_association" "data" {
  subnet_id      = azurerm_subnet.data.id
  route_table_id = azurerm_route_table.data.id
}
