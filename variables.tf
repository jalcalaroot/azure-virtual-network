variable "location" {
  description = "Azure region to deploy resources"
  type        = string
  default     = "centralus"
}

variable "subscription_id" {
  description = "Subscription ID de Azure - requerido explícitamente por el provider azurerm >= 4.0. Sin default a propósito: pasarlo vía -var, un .tfvars gitignoreado, o la variable de entorno ARM_SUBSCRIPTION_ID"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group (dedicada a este proyecto - lifecycle propio, no compartida con otros proyectos)"
  type        = string
  default     = "rg-network"
}

variable "environment" {
  description = "Ambiente de despliegue (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "owner" {
  description = "Propietario/responsable del recurso"
  type        = string
  default     = "johan"
}

variable "project" {
  description = "Nombre del proyecto asociado"
  type        = string
  default     = "network"
}

variable "vnet_name" {
  description = "Name of the Virtual Network"
  type        = string
  default     = "vnet-ha"
}

variable "appgw_subnet_cidr" {
  description = "CIDR para la subnet dedicada de Application Gateway (unica, no una por AZ)"
  type        = string
  default     = "10.0.40.0/24"
}

variable "vnet_address_space" {
  description = "Address space for the VNet"
  type        = list(string)
  default     = ["10.0.0.0/16"]
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

variable "tags" {
  description = "Tags adicionales a fusionar con los tags base (ambiente, propietario, proyecto)"
  type        = map(string)
  default     = {}
}

# ============================================================================
# Observabilidad: Log Analytics, NSG Flow Logs, Diagnostic Settings
# ============================================================================

variable "log_analytics_workspace_name" {
  description = "Nombre del Log Analytics workspace donde llegan flow logs, traffic analytics y diagnostic settings"
  type        = string
  default     = "log-network-ha-vnet"
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
  default     = "stflowlogshavnet"
}
