terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.0" # piso alineado con jalcalaroot-azure (~> 5.0) - sin límite superior a propósito, así el consumidor decide la versión exacta
    }
  }
}
