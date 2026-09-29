locals {
  base_tags = {
    Project     = "jalcalaroot"
    Environment = var.environment
    Owner       = var.owner
    ManagedBy   = "terraform"
  }

  tags = merge(local.base_tags, var.tags)
}
