# Migrado a Azure Verified Modules (AVM) el 2026-09-28. AVM's
# Azure/avm-res-network-virtualnetwork/azurerm NO crea NSGs, NAT Gateway ni
# route tables por si solo (confirmado contra la doc oficial, los propios
# ejemplos del modulo usan recursos azurerm_* crudos para eso y los
# referencian por ID dentro de cada subnet) - se mantienen como recursos
# planos, igual que antes de esta migracion.
#
# parent_id quiere el ID del resource group, NO el nombre (a diferencia de
# la mayoria de recursos azurerm crudos) - confirmado contra la doc del
# modulo antes de escribir esto, gotcha real de esta AVM especifica. Este
# modulo solo recibe var.resource_group_name (un nombre, no lo crea), asi
# que se resuelve el ID con un data source.
data "azurerm_resource_group" "this" {
  name = var.resource_group_name
}

# ============================================================================
# NAT Gateway - compartido por app/aks. public/appgw/data no lo usan (ver
# motivo de cada uno abajo).
# ============================================================================

resource "azurerm_public_ip" "nat" {
  name                = "pip-nat-gateway"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_nat_gateway" "this" {
  name                    = "nat-gw-shared"
  location                = var.location
  resource_group_name     = var.resource_group_name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 4
  tags                    = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "this" {
  nat_gateway_id       = azurerm_nat_gateway.this.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

# ============================================================================
# Network Security Groups - una por subnet, mismas reglas que antes de esta
# migracion (nada cambia a nivel de seguridad real).
# ============================================================================

resource "azurerm_network_security_group" "public" {
  #checkov:skip=CKV_AZURE_160:80 se mantiene por diseño para el redirect HTTP->HTTPS que hace App Gateway - el trafico plano no llega a los backends, App Gateway lo redirige antes.
  name                = "nsg-public"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  security_rule {
    name                       = "Allow-HTTPS-Inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "Internet"
    destination_address_prefix = "VirtualNetwork"
  }
  security_rule {
    name                       = "Allow-HTTP-Inbound"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "Internet"
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

resource "azurerm_network_security_group" "appgw" {
  #checkov:skip=CKV_AZURE_160:80 se mantiene por diseño para el redirect HTTP->HTTPS que hace App Gateway - mismo motivo que nsg-public.
  name                = "nsg-appgw"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  security_rule {
    name                       = "Allow-GatewayManager"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "65200-65535"
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "Allow-Internet-HTTP"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "Allow-Internet-HTTPS"
    priority                   = 111
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "Allow-AzureLoadBalancer"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
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

resource "azurerm_network_security_group" "private" {
  name                = "nsg-private"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  security_rule {
    name                       = "Allow-From-Public-Subnets"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443", "8080"]
    source_address_prefixes    = [var.public_subnet_cidr, var.appgw_subnet_cidr]
    destination_address_prefix = "VirtualNetwork"
  }
  security_rule {
    name                       = "Allow-VNet-Inbound"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
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

resource "azurerm_network_security_group" "data" {
  name                = "nsg-data"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  security_rule {
    name                       = "Allow-From-App-Subnets"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["3306", "5432", "1433", "6379", "27017", "9092", "9093", "9200", "9042"]
    source_address_prefixes    = [var.app_subnet_cidr]
    destination_address_prefix = "VirtualNetwork"
  }
  security_rule {
    name                       = "Allow-VNet-Replication"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["3306", "5432", "1433", "6379", "27017", "9092", "9093", "9200", "9042"]
    source_address_prefix      = "VirtualNetwork"
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

resource "azurerm_network_security_group" "aks" {
  name                = "nsg-aks"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  security_rule {
    name                       = "Allow-AzureLoadBalancer"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "Allow-VNet-Inbound"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
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

# ============================================================================
# Route tables - solo donde hace falta desviar del ruteo default de Azure.
# appgw/privatelink no tienen (dependen del outbound default o van por NAT
# Gateway sin necesitar una ruta explicita).
# ============================================================================

resource "azurerm_route_table" "public" {
  name                          = "rt-public"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  bgp_route_propagation_enabled = true
  tags                          = var.tags

  route {
    name           = "to-internet"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "Internet"
  }
}

resource "azurerm_route_table" "app" {
  name                          = "rt-app"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  bgp_route_propagation_enabled = true
  tags                          = var.tags
}

resource "azurerm_route_table" "data" {
  name                          = "rt-data"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  bgp_route_propagation_enabled = false
  tags                          = var.tags

  route {
    name           = "block-internet"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "None"
  }
}

resource "azurerm_route_table" "aks" {
  name                          = "rt-aks"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  bgp_route_propagation_enabled = true
  tags                          = var.tags
}

# ============================================================================
# VNet + subnets via Azure Verified Module.
# ============================================================================

module "vnet" {
  #checkov:skip=CKV_TF_1:pinned por version semver del Terraform Registry (no un git tag movible) - Azure Verified Module oficial, publicado por Microsoft, versiones inmutables una vez publicadas en el registry.
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "0.22.2"

  name          = var.vnet_name
  location      = var.location
  parent_id     = data.azurerm_resource_group.this.id
  address_space = var.vnet_address_space
  tags          = var.tags

  enable_telemetry = false

  diagnostic_settings = {
    sendToLogAnalytics = {
      workspace_resource_id = azurerm_log_analytics_workspace.this.id
    }
  }

  subnets = {
    public = {
      name                            = "snet-public"
      address_prefixes                = [var.public_subnet_cidr]
      default_outbound_access_enabled = true # ya tiene ruta explicita a Internet via rt-public
      network_security_group          = { id = azurerm_network_security_group.public.id }
      route_table                     = { id = azurerm_route_table.public.id }
    }
    appgw = {
      name                            = "snet-appgw"
      address_prefixes                = [var.appgw_subnet_cidr]
      default_outbound_access_enabled = true # sin NAT Gateway ni route table propia - necesita el outbound default de Azure
      network_security_group          = { id = azurerm_network_security_group.appgw.id }
    }
    app = {
      name                            = "snet-app"
      address_prefixes                = [var.app_subnet_cidr]
      default_outbound_access_enabled = true
      network_security_group          = { id = azurerm_network_security_group.private.id }
      route_table                     = { id = azurerm_route_table.app.id }
      nat_gateway                     = { id = azurerm_nat_gateway.this.id }
    }
    data = {
      name                            = "snet-data"
      address_prefixes                = [var.data_subnet_cidr]
      default_outbound_access_enabled = true # el route table (block-internet) es lo que realmente bloquea el egreso, no este flag
      network_security_group          = { id = azurerm_network_security_group.data.id }
      route_table                     = { id = azurerm_route_table.data.id }
    }
    aks = {
      name                            = "snet-aks"
      address_prefixes                = [var.aks_subnet_cidr]
      default_outbound_access_enabled = true
      network_security_group          = { id = azurerm_network_security_group.aks.id }
      route_table                     = { id = azurerm_route_table.aks.id }
      nat_gateway                     = { id = azurerm_nat_gateway.this.id }
    }
    privatelink = {
      name                              = "snet-privatelink"
      address_prefixes                  = [var.privatelink_subnet_cidr]
      default_outbound_access_enabled   = true
      network_security_group            = { id = azurerm_network_security_group.privatelink.id }
      private_endpoint_network_policies = "Disabled"
    }
  }
}
