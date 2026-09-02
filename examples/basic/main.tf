# Minimal example, exercised in CI via `terraform validate` (no apply - a
# bare module has nothing to plan without a caller like this one).

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.0"
    }
  }
}

variable "subscription_id" {
  type = string
}

provider "azurerm" {
  subscription_id = var.subscription_id
  features {}
}

module "network" {
  source = "../.."

  resource_group_name = "jalcalaroot"
  location            = "eastus"
  tags = {
    Project     = "jalcalaroot"
    Environment = "dev"
    Owner       = "johan"
    ManagedBy   = "terraform"
  }
}
