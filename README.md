# Azure HA Virtual Network - Network Layer

Terraform module for the network layer of a highly available Azure VNet spanning all 3 Availability Zones (AZs) in the region, with a 3-tier subnet design (Public, App, Data), a dedicated subnet for AKS, a dedicated subnet for Private Endpoints, a dedicated subnet for Application Gateway, and full network observability (Flow Logs, Traffic Analytics, diagnostic settings).

## Architecture overview

```
                              Internet
                                 |
                    Application Gateway (snet-appgw)
                                 |
                         NAT Gateway (shared)
                                 |
        -----------------------------------------------------
        |                    |                    |
Public subnet          App subnet            AKS subnet
(NSG-Public)          (NSG-Private)          (NSG-AKS)
        |                    |
        |              Data subnet
        |              (NSG-Data)
        -----------------------------------------------------
                                 |
                    snet-privatelink (NSG-PrivateLink)
                                 |
                -------------------------------------
                |                |                   |
          Key Vault         Storage Blob       Storage DFS
        (Private Endpoint) (Private Endpoint) (Private Endpoint)
                |                |                   |
              Private DNS Zones (linked to the VNet)
```

Every subnet is regional and already spans all 3 AZs; high availability is achieved by deploying resources (VMs, VMSS, AKS node pools) with the `zones` argument, not by splitting subnets per zone.

## What this deploys

| Resource | Count | Notes |
|---|---|---|
| Resource Group | 1 | `rg-network` |
| Virtual Network | 1 | `10.0.0.0/16` |
| Public / App / Data subnets | 1 each | Regional, span all 3 AZs; HA via `zones` on the resources deployed into them |
| AKS subnet | 1 | Flat subnet, no per-AZ split; pod IPs come from the CNI Overlay range, not this subnet |
| Application Gateway subnet | 1 | Not zonal - shared across AZs via the `zones` argument on the Application Gateway resource itself |
| Private Endpoints subnet | 1 | Shared across the VNet, not zonal |
| Network Security Groups | 6 | `NSG-Public`, `NSG-Private`, `NSG-Data`, `NSG-PrivateLink`, `NSG-AppGW`, `NSG-AKS` |
| NAT Gateway | 1 | Shared, associated to the App and AKS subnets |
| Public IP | 1 | Associated with the NAT Gateway |
| Route Tables | 4 | `rt-public`, `rt-app`, `rt-data`, `rt-aks` |
| Key Vault | 1 | Public access disabled, Private Endpoint only |
| Storage Account | 1 | Data Lake Gen2 (HNS), ZRS, public access disabled |
| Private Endpoints | 3 | Key Vault, Storage Blob, Storage DFS |
| Private DNS Zones | 3 | One per PaaS service, linked to the VNet |
| Log Analytics Workspace | 1 | Destination for Flow Logs, Traffic Analytics, and diagnostic settings |
| Storage Account (Flow Logs) | 1 | Separate from the data Storage Account — Flow Logs don't support Private Endpoint destinations |
| Virtual Network Flow Log | 1 | Covers the whole VNet with Traffic Analytics enabled |
| Diagnostic Settings | 10 | One per NSG (6), plus VNet, Key Vault, Storage Account, and Storage Blob service |

## Design notes

- **Subnets aren't zonal in Azure.** Each tier gets a single regional subnet that already spans all 3 AZs; actual zone placement happens at the resource level (`zones` argument on VMs, VMSS, node pools, etc.).
- **NSGs are applied per functional tier** — one NSG per tier (public, app, data, AKS), associated to that tier's single subnet.
- **Single shared NAT Gateway** for cost efficiency. Trade-off: if its zone fails, the whole region loses outbound internet through it. One NAT Gateway per AZ (paired with per-AZ subnets) gives full zonal resilience instead.
- **Application Gateway subnet is single** — the resource can only reference one subnet in its `gateway_ip_configuration`; multi-AZ resiliency is achieved via the `zones` argument on the Application Gateway itself.
- **AKS subnet is flat, not per-AZ.** With Azure CNI Overlay, pod IPs come from a separate overlay range, not this subnet; node pool HA is via the node pool's own `zones` argument (set in the `azure-aks-cluster` project, not here).
- **Private Endpoints subnet is shared** across the VNet (Private Endpoints aren't zonal).
- **Key Vault and Storage Account** are reachable only via Private Endpoint, never over the public internet or NAT Gateway.
- **Remote state.** This project's state lives in Azure Blob Storage, provisioned by the sibling `azure-tfstate-bootstrap` project (see `backend.tf`). It is not local.

## NSG summary

| NSG | Applies to | Allows |
|---|---|---|
| `NSG-Public` | Public subnet | HTTP/HTTPS from Internet |
| `NSG-Private` | App subnet | HTTP/HTTPS/8080 from the Public subnet CIDR and the Application Gateway subnet CIDR |
| `NSG-Data` | Data subnet | Traffic from the App subnet CIDR on DB ports |
| `NSG-PrivateLink` | Private Endpoints subnet | Traffic from the App/Data subnet CIDRs on 443/1433/5432 |
| `NSG-AppGW` | Application Gateway subnet | GatewayManager (65200-65535), HTTP/HTTPS from Internet, AzureLoadBalancer |
| `NSG-AKS` | AKS subnet | AzureLoadBalancer (health probes), VNet-internal traffic |

All NSGs deny all other inbound traffic by default (`Deny-All-Inbound`, priority 4096).

## Routing

| Tier | Route Table | `0.0.0.0/0` | Egress |
|---|---|---|---|
| Public | `rt-public` | `Internet` | Direct via subnet's own Public IPs |
| App | `rt-app` | *(none)* | Shared NAT Gateway, associated directly to the App subnet |
| Data | `rt-data` | `None` | Internet egress blocked (defense in depth) |
| AKS | `rt-aks` | *(none)* | Shared NAT Gateway, associated directly to the AKS subnet |

NAT Gateway can't be a route table next hop in Azure — egress is set via direct subnet association instead, which is why `rt-app` and `rt-aks` have no explicit `0.0.0.0/0` entry. Private Endpoint traffic uses system routes injected automatically, no UDR changes needed.

## Observability

- **Virtual Network Flow Log** (`flowlog-vnet-ha`) — covers the whole VNet with a single resource (successor to per-NSG Flow Logs, retired for new deployments since June 2025), with Traffic Analytics enabled (10-minute interval) and its own dedicated Storage Account (`stflowlogshavnet`, separate from the data Storage Account since Flow Logs don't support Private Endpoint destinations).
- **Diagnostic Settings** forward `allLogs` (and `AllMetrics` where applicable) from every NSG, the VNet itself, the Key Vault, and the Storage Account (account-level transaction metrics + blob-service-level logs) to the shared Log Analytics Workspace.
- **Log Analytics Workspace** (`log-network-ha-vnet`) is exposed via the `log_analytics_workspace_id` output so other projects (e.g. `azure-aks-cluster`) can send their own diagnostic settings to the same workspace.
- Network Watcher itself is referenced, not created — it's a per-region/subscription singleton Azure auto-manages (`NetworkWatcher_<region>` in `NetworkWatcherRG`).

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.5.0
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli), logged in via `az login`
- An active Azure subscription
- The `azure-tfstate-bootstrap` project applied first (this project's backend depends on the storage account/container it creates)

## Usage

`subscription_id` has no default (kept out of the repo on purpose) — export it as `TF_VAR_subscription_id` or pass `-var subscription_id=<id>` on every `plan`/`apply`.

```bash
az login
export TF_VAR_subscription_id="<your-subscription-id>"
terraform init
terraform validate
terraform plan
terraform apply
```

```bash
terraform destroy   # tear down
```

## Configuration

| Variable | Default | Description |
|---|---|---|
| `location` | `centralus` | Azure region |
| `subscription_id` | — | Azure subscription ID (required explicitly by azurerm >= 4.0) |
| `resource_group_name` | `rg-network` | Resource group name (dedicated to this project, own lifecycle) |
| `environment` | `prod` | Deployment environment, merged into resource tags |
| `owner` | `johan` | Resource owner, merged into resource tags |
| `project` | `network` | Project name, merged into resource tags |
| `vnet_name` | `vnet-ha` | VNet name |
| `vnet_address_space` | `["10.0.0.0/16"]` | VNet CIDR |
| `public_subnet_cidr` | `10.0.0.0/22` | Single regional subnet, spans all AZs |
| `app_subnet_cidr` | `10.0.8.0/22` | Single regional subnet, spans all AZs |
| `data_subnet_cidr` | `10.0.20.0/22` | Single regional subnet, spans all AZs |
| `aks_subnet_cidr` | `10.0.60.0/24` | Single flat subnet, no per-AZ split |
| `privatelink_subnet_cidr` | `10.0.30.0/24` | Shared, Private Endpoints |
| `appgw_subnet_cidr` | `10.0.40.0/24` | Shared, Application Gateway |
| `key_vault_name` | `kv-ha-vnet-demo` | Must be globally unique, 3-24 alphanumeric chars |
| `storage_account_name` | `stahavnetdemo` | Must be globally unique, 3-24 lowercase alphanumeric chars |
| `log_analytics_workspace_name` | `log-network-ha-vnet` | Workspace receiving Flow Logs, Traffic Analytics, and diagnostic settings |
| `log_analytics_retention_days` | `30` | Log retention in the workspace |
| `flow_log_retention_days` | `30` | Flow Log retention in its dedicated storage account |
| `flow_logs_storage_account_name` | `stflowlogshavnet` | Must be globally unique; dedicated to Flow Logs, separate from the data Storage Account |
| `tags` | `{}` | Extra tags merged with the base tags (`environment`/`owner`/`project`) |

Override with a `terraform.tfvars` file or `-var` flags. `key_vault_name`, `storage_account_name`, and `flow_logs_storage_account_name` must be set to unique values before `apply` if the defaults are already taken.

## Outputs

| Output | Description |
|---|---|
| `resource_group_name` | Name of the resource group (pass to consuming projects, e.g. jumpbox) |
| `vnet_id` | ID of the VNet |
| `public_subnet_id` / `app_subnet_id` / `data_subnet_id` | Subnet ID per tier |
| `aks_subnet_id` / `aks_subnet_cidr` | AKS subnet |
| `appgw_subnet_id` / `appgw_subnet_cidr` | Application Gateway subnet |
| `privatelink_subnet_id` | Private Endpoints subnet |
| `nat_gateway_id` / `nat_gateway_public_ip` | NAT Gateway |
| `nsg_public_id` / `nsg_private_id` / `nsg_data_id` | NSG IDs |
| `route_table_public_id` / `route_table_app_id` / `route_table_data_id` | Route Tables |
| `key_vault_id` / `key_vault_private_endpoint_ip` | Key Vault |
| `storage_account_id` / `storage_blob_private_endpoint_ip` / `storage_dfs_private_endpoint_ip` | Storage Account |
| `log_analytics_workspace_id` | Log Analytics Workspace, for other projects to send their own diagnostic settings to |

## Consumers

Sibling projects in this workspace read this module's outputs (via `terraform output` or a hardcoded subnet ID/name) rather than a `terraform_remote_state` data source:

| Project | What it reads from here |
|---|---|
| `azure-jumpbox-server` | `app_subnet_id` (management VM placement) |
| `azure-mysql-database` | `data_subnet_id` (Private Endpoint placement) |
| `azure-lb-webserver` | Subnet names directly (`snet-appgw`) plus a configurable list of app subnet names |
| `azure-aks-cluster` | Reads `azure-tfstate-bootstrap`'s backend config for its own remote state; may reference this project's subnet/NSG outputs for node pool placement |

If you change a subnet name, CIDR, or output name here, check whether any of these have already been applied against the old values before assuming it's safe.

## Cost considerations

Main ongoing costs: NAT Gateway (hourly + per-GB), Standard Public IPs, Private Endpoints (per-endpoint hourly), Key Vault (per-operation), Storage Account (capacity + transactions, ZRS premium over LRS), Application Gateway (hourly + capacity units), Log Analytics Workspace (ingestion + retention beyond the free tier), Flow Logs storage account (capacity + transactions, LRS). Estimate with the [Azure Pricing Calculator](https://azure.microsoft.com/en-us/pricing/calculator/).

## Next steps

Covered: network layer, core PaaS connectivity, Application Gateway subnet/NSG, AKS subnet/NSG/route table, network observability. Not yet covered here (see sibling projects):

- AKS cluster itself (`azure-aks-cluster`)
- Jumpbox / management VM (`azure-jumpbox-server`)
- Load-balanced web servers (`azure-lb-webserver`)
- Relational database service (`azure-mysql-database`)
- Azure Firewall / centralized policy management
- Additional PaaS Private Endpoints (ACR, Event Hub, Cosmos DB, etc.)
