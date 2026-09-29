terraform {
  required_version = ">= 1.5.0"

  required_providers {
    # Bajado de ">= 5.0" (sin límite superior) el 2026-09-28 al migrar a
    # Azure Verified Modules: avm-res-network-virtualnetwork (hasta 0.22.2)
    # y avm-res-storage-storageaccount (hasta 0.10.0) todavía piden azurerm
    # < 5.0; avm-res-keyvault-vault (0.11.0) pide >= 4.81. El rango de abajo
    # es la intersección real de los 3, verificada contra la doc de cada
    # módulo antes de escribir esto, no adivinada. Ya no es "el consumidor
    # decide" - un módulo con AVM adentro impone su propio piso real, y el
    # consumidor tiene que respetarlo. Subir el límite superior cuando los 3
    # módulos soporten azurerm 5.x.
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.81.0, < 5.0.0"
    }
  }
}
