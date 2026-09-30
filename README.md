# azure-virtual-network

[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/jalcalaroot/azure-virtual-network/badge)](https://scorecard.dev/viewer/?uri=github.com/jalcalaroot/azure-virtual-network)

The Azure network layer (VNet, subnets, NSGs, route tables, NAT Gateway, Key Vault + Storage behind Private Endpoints, Flow Logs) for the `jalcalaroot` account, and the dedicated subnets [`azure-container-apps`](https://github.com/jalcalaroot/azure-container-apps)/[`azure-aks-cluster`](https://github.com/jalcalaroot/azure-aks-cluster) need. Standalone Terraform project — own backend, own CI/CD, own state.

## Architecture

```
                    Internet
                       │
                  NAT Gateway (outbound only)
                       │
        ───── Virtual Network (vnet-jalcalaroot) ─────
                       │
  ┌────────┬─────────┬────────┬────────┬─────────────┐
  │ public │  app     │  data  │  aks   │ containerapps│
  │ subnet │ subnet   │ subnet │ subnet │   subnet     │
  └────────┴─────────┴────────┴────────┴─────────────┘
  + privatelink subnet (Key Vault + Storage Private Endpoints)
  + aks-virtual-nodes subnet (delegated to ACI)
                       │
        NSG + Route Table per subnet, Flow Logs → Log Analytics
```

## Resources deployed

| Resource | Purpose | Docs |
|---|---|---|
| Virtual Network + 8 subnets | Core network, one subnet per workload tier; built on [`Azure/avm-res-network-virtualnetwork` v0.22.2](https://registry.terraform.io/modules/Azure/avm-res-network-virtualnetwork/azurerm/0.22.2) | [Azure VNet overview](https://learn.microsoft.com/en-us/azure/virtual-network/virtual-networks-overview) |
| Network Security Groups | Per-subnet traffic rules | [NSG overview](https://learn.microsoft.com/en-us/azure/virtual-network/network-security-groups-overview) |
| Route Tables | Custom routing per subnet | [Route tables](https://learn.microsoft.com/en-us/azure/virtual-network/virtual-networks-udr-overview) |
| NAT Gateway | Outbound internet for private subnets | [NAT Gateway overview](https://learn.microsoft.com/en-us/azure/nat-gateway/nat-overview) |
| Key Vault (Private Endpoint) | Shared secrets storage, no public network access; built on [`Azure/avm-res-keyvault-vault` v0.11.0](https://registry.terraform.io/modules/Azure/avm-res-keyvault-vault/azurerm/0.11.0) | [Private Link overview](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-overview) |
| 2 Storage Accounts (Private Endpoints) | Data + flow-logs storage, no public network access; built on [`Azure/avm-res-storage-storageaccount` v0.10.0](https://registry.terraform.io/modules/Azure/avm-res-storage-storageaccount/azurerm/0.10.0) | [Private Link overview](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-overview) |
| Log Analytics Workspace + Flow Logs | Network traffic observability | [NSG flow logs](https://learn.microsoft.com/en-us/azure/network-watcher/network-watcher-nsg-flow-logging-overview) |
| Private DNS Zones | Resolution for the Private Endpoints above | [Azure Private DNS](https://learn.microsoft.com/en-us/azure/dns/private-dns-overview) |

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.5.0
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli), logged in via `az login` with Contributor-or-better on the subscription
- Network Watcher must already exist in the target region/subscription (Azure auto-creates it the first time any VNet with flow logs is deployed there — on a brand-new subscription, the first `terraform plan` fails until it exists)

## Usage

```bash
az login
export TF_VAR_subscription_id="<subscription-id>"

terraform init
terraform apply
```

`resource_group_name`/`location` default to `jalcalaroot`/`eastus`. Every other input has a sensible default — override only what you need to change.

## Configuration

| Variable | Default | Notes |
|---|---|---|
| `subscription_id` | — | via `TF_VAR_subscription_id` |
| `resource_group_name` / `location` | `jalcalaroot` / `eastus` | |
| `vnet_name` / `vnet_address_space` | `vnet-jalcalaroot` / `10.0.0.0/16` | |
| `public_subnet_cidr` / `app_subnet_cidr` / `data_subnet_cidr` | `10.0.0.0/22` / `10.0.8.0/22` / `10.0.20.0/22` | |
| `appgw_subnet_cidr` / `aks_subnet_cidr` | `10.0.40.0/24` / `10.0.60.0/24` | |
| `containerapps_subnet_cidr` / `aks_virtual_nodes_subnet_cidr` | `10.0.70.0/23` / `10.0.72.0/24` | |
| `privatelink_subnet_cidr` | `10.0.30.0/24` | Key Vault + Storage Private Endpoints |
| `key_vault_name` / `storage_account_name` | `kv-jalcalaroot-net` / `stjalcalarootnet` | globally unique |
| `flow_logs_storage_account_name` | `stflowlogsjalcalaroot` | globally unique |
| `log_analytics_workspace_name` | `log-network-jalcalaroot` | |
| `log_analytics_retention_days` / `flow_log_retention_days` | `30` / `30` | |
| `enable_traffic_analytics` | `true` | |

## Outputs

| Output | Description |
|---|---|
| `vnet_id` | Full Virtual Network resource ID |
| `public_subnet_id` / `app_subnet_id` / `data_subnet_id` / `privatelink_subnet_id` | Subnet IDs |
| `network_appgw_subnet_id` / `network_aks_subnet_id` / `network_aks_virtual_nodes_subnet_id` / `network_containerapps_subnet_id` | Subnet IDs copied by consumer repos into their own GitHub variables |
| `nsg_public_id` / `nsg_private_id` / `nsg_data_id` | NSG IDs |
| `route_table_public_id` / `route_table_app_id` / `route_table_data_id` | Route table IDs |
| `nat_gateway_id` / `nat_gateway_public_ip` | NAT Gateway resource ID and its egress IP |
| `key_vault_id` / `storage_account_id` | Shared Key Vault / Storage Account IDs |
| `network_log_analytics_workspace_id` | For other projects' diagnostic settings |

No `terraform_remote_state` — consumers copy these values by hand into their own GitHub repository variables.

## CI/CD

GitHub Actions, authenticated to Azure via OIDC (Workload Identity Federation) — no secrets or static credentials stored in GitHub.

| Workflow | Trigger | Identity | What it does |
|---|---|---|---|
| `terraform-plan.yml` | Pull request | `virtual-network-plan` (read-only) | `fmt -check`, `validate`, tflint, Checkov (blocking), `plan`, posts the plan as a PR comment |
| `terraform-apply.yml` | Push to `main` | `virtual-network-agent` | `plan` + `apply` |
| `gitleaks.yml` | PR / push to `main` | — | Secret scanning |

Both identities live in a persistent Terraform root ([`./ci`](./ci)), separate from this project's destroyable state — destroying/recreating the network doesn't break CI. Required GitHub repository variables: `ARM_CLIENT_ID_AGENT`, `ARM_CLIENT_ID_PLAN`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID`.

See [CLAUDE.md](CLAUDE.md) for design decisions, RBAC breakdown, and full project history.
