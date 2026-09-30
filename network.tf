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
  tags                = local.tags
}

resource "azurerm_nat_gateway" "this" {
  name                    = "nat-gw-shared"
  location                = var.location
  resource_group_name     = var.resource_group_name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 4
  tags                    = local.tags
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
  tags                = local.tags

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
  tags                = local.tags

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
  tags                = local.tags

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
  tags                = local.tags

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
  tags                = local.tags

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
  tags                = local.tags

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

# containerapps/aks_virtual_nodes: hasta 2026-09-29 vivian como bolt-ons
# fuera de este modulo (en el repo consumidor), para no forzar un bump de
# version del modulo por una necesidad puntual de un solo proyecto. Al
# convertir este repo de "modulo versionado por git tag" a proyecto
# standalone (ver CLAUDE.md), esa razon dejo de aplicar - un cambio aca ya
# no tiene otros consumidores a los que romper, asi que se unificaron en el
# mismo mapa subnets de abajo, igual que public/appgw/app/data/aks/privatelink.
resource "azurerm_network_security_group" "containerapps" {
  name                = "nsg-containerapps"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.tags

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
  # Container Apps Environment (azure-container-apps) es internal-only a
  # proposito - todo el trafico entrante real pasa por snet-appgw, nunca
  # directo a este subnet.
  security_rule {
    name                       = "Allow-AppGateway-To-Edge-Proxy"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443", "31080", "31443"]
    source_address_prefix      = var.appgw_subnet_cidr
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "Allow-VNet-Inbound"
    priority                   = 120
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

resource "azurerm_network_security_group" "aks_virtual_nodes" {
  name                = "nsg-aks-virtual-nodes"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.tags

  security_rule {
    name                       = "Allow-VNet-Inbound"
    priority                   = 100
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

# Agregada 2026-09-30: ningun subnet existente hasta ahora tenia delegation
# a Microsoft.Web/serverFarms - gap real encontrado escribiendo
# azure-agent-platform (Function App Flex Consumption, VNet integration
# outbound), cada subnet solo admite UNA delegation asi que ni privatelink
# ni appgw sirven. Mismo patron minimo que aks_virtual_nodes (subnet
# delegada, sin trafico inbound iniciado desde afuera de la VNet).
resource "azurerm_network_security_group" "func" {
  name                = "nsg-func"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.tags

  security_rule {
    name                       = "Allow-VNet-Inbound"
    priority                   = 100
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

# ============================================================================
# Route tables - solo donde hace falta desviar del ruteo default de Azure.
# appgw/privatelink/aks_virtual_nodes no tienen (dependen del outbound
# default o van por NAT Gateway sin necesitar una ruta explicita).
# ============================================================================

resource "azurerm_route_table" "public" {
  name                          = "rt-public"
  location                      = var.location
  resource_group_name           = var.resource_group_name
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
  location                      = var.location
  resource_group_name           = var.resource_group_name
  bgp_route_propagation_enabled = true
  tags                          = local.tags
}

resource "azurerm_route_table" "data" {
  name                          = "rt-data"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  bgp_route_propagation_enabled = false
  tags                          = local.tags

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
  tags                          = local.tags
}

resource "azurerm_route_table" "containerapps" {
  name                          = "rt-containerapps"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  bgp_route_propagation_enabled = true
  tags                          = local.tags
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
  tags          = local.tags

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
    containerapps = {
      name                            = "snet-containerapps"
      address_prefixes                = [var.containerapps_subnet_cidr]
      default_outbound_access_enabled = true
      network_security_group          = { id = azurerm_network_security_group.containerapps.id }
      route_table                     = { id = azurerm_route_table.containerapps.id }
      nat_gateway                     = { id = azurerm_nat_gateway.this.id }
      delegations = [{
        name = "containerapps-delegation"
        service_delegation = {
          name = "Microsoft.App/environments"
        }
      }]
    }
    aks_virtual_nodes = {
      name                            = "snet-aks-virtual-nodes"
      address_prefixes                = [var.aks_virtual_nodes_subnet_cidr]
      default_outbound_access_enabled = true
      network_security_group          = { id = azurerm_network_security_group.aks_virtual_nodes.id }
      nat_gateway                     = { id = azurerm_nat_gateway.this.id }
      delegations = [{
        name = "aciDelegation"
        service_delegation = {
          name = "Microsoft.ContainerInstance/containerGroups"
        }
      }]
    }
    func = {
      name                            = "snet-func"
      address_prefixes                = [var.func_subnet_cidr]
      default_outbound_access_enabled = true
      network_security_group          = { id = azurerm_network_security_group.func.id }
      nat_gateway                     = { id = azurerm_nat_gateway.this.id }
      delegations = [{
        name = "funcDelegation"
        service_delegation = {
          name = "Microsoft.Web/serverFarms"
        }
      }]
    }
  }
}
