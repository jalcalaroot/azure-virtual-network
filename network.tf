# Virtual Network (equivalent to AWS VPC). Deployed into the existing
# resource group passed in via var.resource_group_name - this module never
# creates or manages a resource group itself.
resource "azurerm_virtual_network" "this" {
  name                = var.vnet_name
  address_space       = var.vnet_address_space
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  # Cifra en tránsito el tráfico entre VMs que lo soportan (series D/E v4+ con
  # Accelerated Networking) dentro de esta VNet y entre VNets peered - gratis,
  # y AllowUnencrypted (el único modo disponible en GA) no rompe nada para VMs
  # que no lo soporten, el tráfico hacia esas simplemente queda sin cifrar.
  # Recomendado explícitamente por el Well-Architected Framework de Azure.
  encryption {
    enforcement = "AllowUnencrypted"
  }

  lifecycle {
    prevent_destroy = true
  }
}
