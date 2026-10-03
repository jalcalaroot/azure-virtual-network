variable "subscription_id" {
  description = "Subscription ID de Azure - requerido explicitamente por el provider azurerm >= 4.0. Sin default a proposito: pasarlo via -var, un .tfvars gitignoreado, o TF_VAR_subscription_id (NO usar ARM_SUBSCRIPTION_ID, el provider no lo lee)."
  type        = string
}

# --------------------------------------------------------------------------
# Resource group: this project does NOT create one. The jalcalaroot account
# uses a single shared resource group for every resource (unlike xtratus/,
# which gives each project its own) - pass in the existing one. Defaults
# match the only real deployment target this repo has (2026-09-29, once it
# stopped being a bare module consumed from jalcalaroot-azure-bootstrap).
# --------------------------------------------------------------------------

variable "resource_group_name" {
  description = "Name of the existing resource group to deploy into (not created by this project)"
  type        = string
  default     = "jalcalaroot"
}

variable "location" {
  description = "Azure region to deploy resources (should match the resource group's region)"
  type        = string
  default     = "eastus"
}

variable "owner" {
  description = "Owner tag applied to every resource"
  type        = string
  default     = "johan"
}

variable "environment" {
  description = "Environment tag applied to every resource"
  type        = string
  default     = "dev"
}

variable "tags" {
  description = "Tags extra a mergear con las base (Project/Environment/Owner/ManagedBy) - no hace falta pasar las base a mano."
  type        = map(string)
  default     = {}
}

variable "vnet_name" {
  description = "Name of the Virtual Network"
  type        = string
  default     = "vnet-jalcalaroot"
}

variable "vnet_address_space" {
  description = "Address space for the VNet"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "appgw_subnet_cidr" {
  description = "CIDR para la subnet dedicada de Application Gateway (unica, no una por AZ)"
  type        = string
  default     = "10.0.40.0/24"
}

# Subnet CIDR blocks per tier.
# Subnets are regional in Azure (they already span all zones in the
# region), so each tier gets a single subnet sized to cover what used to
# be split across 3 AZ-specific /24s (768 addresses) - a /22 (1024
# addresses) per tier, with room to spare for growth.
variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.0.0/22"
}

variable "app_subnet_cidr" {
  description = "CIDR block for the app subnet"
  type        = string
  default     = "10.0.8.0/22"
}

variable "data_subnet_cidr" {
  description = "CIDR block for the data subnet"
  type        = string
  default     = "10.0.20.0/22"
}

variable "aks_subnet_cidr" {
  description = "CIDR para la subnet dedicada de AKS (unica, no una por AZ - HA se maneja via zones del node pool)"
  type        = string
  default     = "10.0.60.0/24"
}

variable "containerapps_subnet_cidr" {
  description = "CIDR para la subnet delegada a Microsoft.App/environments (azure-container-apps)"
  type        = string
  default     = "10.0.70.0/23"
}

variable "aks_virtual_nodes_subnet_cidr" {
  description = "CIDR para la subnet delegada a Microsoft.ContainerInstance/containerGroups (AKS Virtual Nodes, azure-aks-cluster)"
  type        = string
  default     = "10.0.72.0/24"
}

variable "func_subnet_cidr" {
  description = "CIDR para la subnet delegada a Microsoft.App/environments (VNet integration outbound de Function Apps en plan Flex Consumption - azure-agent-platform)"
  type        = string
  default     = "10.0.73.0/24"
}

variable "apim_subnet_cidr" {
  description = "CIDR para la subnet de API Management en modo VNet External (azure-agent-platform). Sin delegation - APIM la prohibe. Minimo /29, un /24 deja margen."
  type        = string
  default     = "10.0.74.0/24"
}

# ============================================================================
# Observabilidad: Log Analytics, VNet Flow Logs, Diagnostic Settings
# ============================================================================

variable "log_analytics_workspace_name" {
  description = "Nombre del Log Analytics workspace donde llegan flow logs, traffic analytics y diagnostic settings"
  type        = string
  default     = "log-network-jalcalaroot"
}

variable "log_analytics_retention_days" {
  description = "Días de retención de logs en el workspace"
  type        = number
  default     = 30
}

variable "flow_log_retention_days" {
  description = "Días de retención del Virtual Network Flow Log en el storage account dedicado"
  type        = number
  default     = 30
}

variable "flow_logs_storage_account_name" {
  description = "Nombre del storage account dedicado al Flow Log (debe ser único globalmente). Separado del storage account de datos para no depender de las reglas de firewall/private endpoint de ese storage"
  type        = string
  default     = "stflowlogsjalcalaroot"
}

variable "enable_traffic_analytics" {
  description = <<-EOT
    Habilitar Traffic Analytics sobre el VNet Flow Log. Default true (recomendado
    por el Well-Architected Framework), pero hay un problema conocido y sin
    solución confirmada de Azure/Terraform (TAUserDoesNotHavePermissions) donde
    la creación del Flow Log falla al intentar habilitar Traffic Analytics,
    incluso con roles amplios (Contributor, Monitoring Contributor) a nivel
    suscripción - ver hashicorp/terraform-provider-azurerm#31139, sin fix
    confirmado en el hilo. Si eso pasa, poner esto en false como workaround:
    el Flow Log en sí (captura cruda a storage) sigue funcionando normal, solo
    se pierde el dashboard agregado de Traffic Analytics.
  EOT
  type        = bool
  default     = true
}
