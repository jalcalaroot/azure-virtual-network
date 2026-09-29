# azure-virtual-network

[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/jalcalaroot/azure-virtual-network/badge)](https://scorecard.dev/viewer/?uri=github.com/jalcalaroot/azure-virtual-network)

The Azure network layer (VNet, subnets, NSGs, route tables, NAT Gateway, Key Vault + Storage behind Private Endpoints, Flow Logs) for the `jalcalaroot` account, and the dedicated subnets `azure-container-apps`/`azure-aks-cluster` need. Standalone Terraform project — own backend, own CI/CD, own state — same shape as those two consumers. **Until 2026-09-29 this was a bare Terraform module** consumed by `jalcalaroot-azure-bootstrap`; see CLAUDE.md ("De modulo a proyecto standalone") for why that changed. Design originally ported from `xtratus/azure-virtual-network`, adapted to not create its own resource group — `jalcalaroot` uses one shared resource group for everything.

## Stack

- **Cloud**: Azure, subscription `<subscription-id>`, region `eastus`
- **IaC**: Terraform. VNet, Key Vault, and both Storage Accounts build on [Azure Verified Modules](https://azure.github.io/Azure-Verified-Modules/); NSGs, route tables, NAT Gateway, private DNS zones, and observability stay as plain `azurerm_*` resources (no AVM equivalent fits this design).
- **Backend**: Same Blob Storage account as the rest of the account (`sttfstatejalcalaroot`, AAD auth, no storage account keys), key `virtual-network/terraform.tfstate`.
- **CI/CD**: GitHub Actions, OIDC (no stored credentials) — see "CI/CD" below.

## Usage

```bash
az login
export TF_VAR_subscription_id="<subscription-id>"

terraform init
terraform apply
```

`resource_group_name`/`location` default to `jalcalaroot`/`eastus` (the only real deployment target this project has). See `variables.tf` for the full set of inputs (subnet CIDRs, Key Vault/Storage Account names, etc. all have sensible defaults) and `outputs.tf` for what it exposes (subnet IDs, NAT Gateway, Key Vault/Storage IDs, Log Analytics workspace ID, plus `network_*`-prefixed aliases that `azure-container-apps`/`azure-aks-cluster` copy into their own GitHub variables — no `terraform_remote_state`, values are copied by hand). No Private Endpoint IP outputs since the Azure Verified Modules migration — the AVM modules for Key Vault/Storage don't expose them, and nothing needs them: DNS resolution via the Private DNS Zones already handles connectivity.

## Prerequisite: Network Watcher

The flow logs resource (`observability.tf`) references the subscription's `NetworkWatcher_<region>` in `NetworkWatcherRG` as a data source — Azure auto-creates this the first time *any* VNet (with flow logs/diagnostics) is deployed in that region for the subscription. On a brand-new subscription with no networking history, a `terraform plan` fails at that data source until Network Watcher exists — not a bug, just a one-time environment prerequisite. Deploying any VNet with Network Watcher enabled resolves it for every future deployment in that region/subscription.

## CI/CD

Two dedicated OIDC identities, in a persistent state root ([`./ci`](./ci)) separate from the main project — so destroying/recreating the network doesn't break CI, same pattern already used by `azure-container-apps`/`azure-aks-cluster`/`aws-eks-cluster`. See CLAUDE.md, "Identidades de CI en state propio".

| Workflow | Trigger | Identity | What it does |
|---|---|---|---|
| `terraform-plan.yml` | Pull request | `virtual-network-plan` (read-only) | `fmt -check`, `validate`, tflint, Checkov (blocking), `plan`, posts the plan as a PR comment |
| `terraform-apply.yml` | Push to `main` | `virtual-network-agent` | `plan` + `apply` |
| `gitleaks.yml` | PR / push to `main` | — | Secret scanning |

Required GitHub repository variables (Settings → Secrets and variables → Actions → Variables): `ARM_CLIENT_ID_AGENT`, `ARM_CLIENT_ID_PLAN`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID`.

## Status

- 2026-09-29 (latest): Converted from a bare Terraform module to a fully standalone project — own backend, own persistent CI identities, own CI/CD pipeline, the 2 bolt-on subnets (`azure-container-apps`, `azure-aks-cluster`) folded into the main `subnets` map, `examples/basic/` removed. See CLAUDE.md, "De modulo a proyecto standalone".
- 2026-09-28/29: Rebuilt on Azure Verified Modules (AVM) - VNet, Key Vault, and both Storage Accounts now go through `Azure/avm-res-network-virtualnetwork`, `Azure/avm-res-keyvault-vault`, and `Azure/avm-res-storage-storageaccount` internally instead of hand-written `azurerm_*` resources. `versions.tf`'s provider constraint narrowed to `>= 4.81.0, < 5.0.0` since none of those 3 AVM modules support azurerm v5.x yet. Tagged `v0.5.0`. See CLAUDE.md for the full migration writeup, including real bugs found and fixed along the way (a private-endpoint duplicate-naming bug, a `parent_id` vs `resource_group_name` inconsistency between AVM modules, and a persistent azapi timeout on 2 storage diagnostic settings that got dropped rather than fought indefinitely).
- 2026-09-05: All GitHub Actions pinned to commit SHA (supply-chain hardening), `dependabot.yml` now watches the `github-actions` ecosystem, and added [OSSF Scorecard](https://scorecard.dev/) (badge above) — results at [scorecard.dev/viewer/?uri=github.com/jalcalaroot/azure-virtual-network](https://scorecard.dev/viewer/?uri=github.com/jalcalaroot/azure-virtual-network).
- 2026-09-03: Checkov results now upload as SARIF to the GitHub Security tab (free — public repo). Added `.pre-commit-config.yaml` (gitleaks + `terraform fmt`, catches secrets/formatting before they leave your machine, not just in CI) — run `pip install pre-commit && pre-commit install` once per clone.
- 2026-09-02: CI hardened — `tflint` + Checkov (blocking) added alongside `fmt`+`validate`, plus `gitleaks` secret scanning. Branch protection enabled on `main`. Both storage accounts hardened (public blob access, TLS version, delete retention, SAS policy; shared-key auth also disabled on the data storage account). Tagged `v0.2.0`.
- 2026-09-02: Ported from `xtratus/azure-virtual-network`. Fixed for azurerm v5 (`azurerm_key_vault` now requires `rbac_authorization_enabled`, set to `true`; `azurerm_private_dns_zone_virtual_network_link` now uses `private_dns_zone_id` instead of `private_dns_zone_name`+`resource_group_name`). Validated end-to-end with a real `terraform plan` against the `jalcalaroot` subscription (55 resources, clean) — not yet applied/tagged.

See `CLAUDE.md` for design decisions and conventions.
