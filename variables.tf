# --------------------------------------------------------------------------
# Resource group: this module does NOT create one. The jalcalaroot account
# uses a single shared resource group for every resource (unlike xtratus/,
# which gives each project its own) - pass in the existing one.
# --------------------------------------------------------------------------

variable "resource_group_name" {
  description = "Name of the existing resource group to deploy into (not created by this module)"
  type        = string
}

variable "location" {
  description = "Azure region to deploy resources (should match the resource group's region)"
  type        = string
}

# --------------------------------------------------------------------------
# Tags: this module does NOT build its own tag map. Pass in the consumer's
# tags (e.g. module.tags.tags from the consumer's own tags module) so every
# resource here stays consistent with everything else in the account.
# --------------------------------------------------------------------------

variable "tags" {
  description = "Tags applied to every resource this module creates"
  type        = map(string)
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
