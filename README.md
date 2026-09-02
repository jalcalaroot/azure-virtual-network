# azure-virtual-network

Reusable Terraform module for the Azure network layer (VNet, subnets, NSGs, route tables, NAT Gateway, Key Vault + Storage behind Private Endpoints, Flow Logs) used by the `jalcalaroot` account's projects. Ported from `xtratus/azure-virtual-network`'s proven design, adapted to not create its own resource group — `jalcalaroot` uses one shared resource group for everything.

## Stack

- **IaC**: Terraform module, consumed via `source = "git::https://github.com/jalcalaroot/azure-virtual-network.git?ref=<tag>"` — this repo has no backend or state of its own.
- **Consumer**: `jalcalaroot-azure-bootstrap` (and future projects in that account).

## Usage

```hcl
module "network" {
  source = "git::https://github.com/jalcalaroot/azure-virtual-network.git?ref=v0.1.0"

  resource_group_name = "jalcalaroot"
  location             = "eastus"
  tags                 = module.tags.tags # from the consumer's own tags module
}
```

See `variables.tf` for the full set of inputs (subnet CIDRs, Key Vault/Storage Account names, etc. all have sensible defaults) and `outputs.tf` for what it exposes (subnet IDs, NAT Gateway, Key Vault/Storage Private Endpoint IPs, Log Analytics workspace ID, ...).

`examples/basic/` is a minimal caller used to validate the module in CI (`terraform validate` — a bare module has nothing to plan without a caller).

## Prerequisite: Network Watcher

The flow logs resource (`observability.tf`) references the subscription's `NetworkWatcher_<region>` in `NetworkWatcherRG` as a data source — Azure auto-creates this the first time *any* VNet (with flow logs/diagnostics) is deployed in that region for the subscription. On a brand-new subscription with no networking history, a `terraform plan` against this module fails at that data source until Network Watcher exists — not a module bug, just a one-time environment prerequisite. Deploying any VNet with Network Watcher enabled resolves it for every future deployment in that region/subscription.

## Status

- 2026-09-02: Ported from `xtratus/azure-virtual-network`. Fixed for azurerm v5 (`azurerm_key_vault` now requires `rbac_authorization_enabled`, set to `true`; `azurerm_private_dns_zone_virtual_network_link` now uses `private_dns_zone_id` instead of `private_dns_zone_name`+`resource_group_name`). Validated end-to-end with a real `terraform plan` against the `jalcalaroot` subscription (55 resources, clean) — not yet applied/tagged.

See `CLAUDE.md` for conventions.
