

# Private Endpoints subnet (single, not zonal - shared across the VNet)
variable "privatelink_subnet_cidr" {
  description = "CIDR block for the shared Private Endpoints subnet"
  type        = string
  default     = "10.0.30.0/24"
}

# Key Vault settings
variable "key_vault_name" {
  description = "Name of the Key Vault (must be globally unique, 3-24 alphanumeric chars)"
  type        = string
  default     = "kv-ha-vnet-demo"
}

# Storage Account settings
variable "storage_account_name" {
  description = "Name of the Storage Account (must be globally unique, 3-24 lowercase alphanumeric chars)"
  type        = string
  default     = "stahavnetdemo"
}
