# azure-virtual-network

[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/jalcalaroot/azure-virtual-network/badge)](https://scorecard.dev/viewer/?uri=github.com/jalcalaroot/azure-virtual-network)

The Azure network layer (VNet, subnets, NSGs, route tables, NAT Gateway, Key Vault + Storage behind Private Endpoints, Flow Logs) for the `jalcalaroot` account, and the dedicated subnets [`azure-container-apps`](https://github.com/jalcalaroot/azure-container-apps)/[`azure-aks-cluster`](https://github.com/jalcalaroot/azure-aks-cluster) need. Standalone Terraform project — own backend, own CI/CD, own state. History and design rationale in [CLAUDE.md](CLAUDE.md).

## Resources deployed

| Resource | Purpose | Docs |
|---|---|---|
| Virtual Network + 8 subnets | Core network, one subnet per workload tier | [Azure VNet overview](https://learn.microsoft.com/en-us/azure/virtual-network/virtual-networks-overview) |
| Network Security Groups | Per-subnet traffic rules | [NSG overview](https://learn.microsoft.com/en-us/azure/virtual-network/network-security-groups-overview) |
| Route Tables | Custom routing per subnet | [Route tables](https://learn.microsoft.com/en-us/azure/virtual-network/virtual-networks-udr-overview) |
| NAT Gateway | Outbound internet for private subnets | [NAT Gateway overview](https://learn.microsoft.com/en-us/azure/nat-gateway/nat-overview) |
| Key Vault + 2 Storage Accounts (Private Endpoints) | Shared secrets/state storage, no public network access | [Private Link overview](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-overview) |
| Log Analytics Workspace + Flow Logs | Network traffic observability | [NSG flow logs](https://learn.microsoft.com/en-us/azure/network-watcher/network-watcher-nsg-flow-logging-overview) |
| Private DNS Zones | Resolution for the Private Endpoints above | [Azure Private DNS](https://learn.microsoft.com/en-us/azure/dns/private-dns-overview) |

VNet, Key Vault, and both Storage Accounts build on [Azure Verified Modules](https://azure.github.io/Azure-Verified-Modules/); the rest are plain `azurerm_*` resources (no AVM equivalent fits this design).

## Stack

- **Cloud**: Azure, subscription `<subscription-id>`, region `eastus`
- **Backend**: Same Blob Storage account as the rest of the account (`sttfstatejalcalaroot`, AAD auth, no storage account keys), key `virtual-network/terraform.tfstate`.
- **CI/CD**: GitHub Actions, OIDC (no stored credentials) — see "CI/CD" below.

## Usage

```bash
az login
export TF_VAR_subscription_id="<subscription-id>"

terraform init
terraform apply
```

`resource_group_name`/`location` default to `jalcalaroot`/`eastus`. All inputs (subnet CIDRs, Key Vault/Storage Account names) have sensible defaults — see `variables.tf`. Outputs (subnet IDs, NAT Gateway, Key Vault/Storage IDs, Log Analytics workspace ID) are copied by hand into consumer repos' GitHub variables, no `terraform_remote_state` — see `outputs.tf`.

## Prerequisite: Network Watcher

The flow logs resource references the subscription's `NetworkWatcher_<region>` — Azure auto-creates this the first time any VNet with flow logs is deployed in that region. On a brand-new subscription, the first `terraform plan` fails until it exists; a one-time environment prerequisite, not a bug.

## CI/CD

Two dedicated OIDC identities in a persistent state root ([`./ci`](./ci)), separate from the main project — destroying/recreating the network doesn't break CI. See CLAUDE.md, "Identidades de CI en state propio".

| Workflow | Trigger | Identity | What it does |
|---|---|---|---|
| `terraform-plan.yml` | Pull request | `virtual-network-plan` (read-only) | `fmt -check`, `validate`, tflint, Checkov (blocking), `plan`, posts the plan as a PR comment |
| `terraform-apply.yml` | Push to `main` | `virtual-network-agent` | `plan` + `apply` |
| `gitleaks.yml` | PR / push to `main` | — | Secret scanning |

Required GitHub repository variables (Settings → Secrets and variables → Actions → Variables): `ARM_CLIENT_ID_AGENT`, `ARM_CLIENT_ID_PLAN`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID`.

## Status

Standalone project since 2026-09-29 (own backend, own persistent CI identities, own pipeline), rebuilt on Azure Verified Modules the same week. **Currently torn down** — no live deployment. Full history and design decisions in [CLAUDE.md](CLAUDE.md).
