# Port contract

Which service reaches which subnet and on which port. Inbound rules in `network.tf` open **only** these flows; everything else ends in `Deny-All-Inbound`. Outbound traffic is intentionally left open (the default `AllowInternetOutBound`).

NSGs cannot be attached to the NICs of managed PaaS services (AKS nodes, Container Apps, Function App, API Management, Private Endpoint NICs). The NSG of the service's subnet is the control. For Private Endpoints it applies only because the `privatelink` subnet has `private_endpoint_network_policies = "NetworkSecurityGroupEnabled"`.

| Consumer project | Subnet | Inbound allowed | Source | Basis |
|---|---|---|---|---|
| `azure-aks-cluster` | `snet-aks` | any port from the cluster itself and its virtual nodes; Azure Load Balancer; TCP 80 backend of the Application Gateway (AGIC) | `snet-aks`, `snet-aks-virtual-nodes`, `snet-appgw`, `AzureLoadBalancer` | Project code: backend and container port 80 |
| `azure-aks-cluster` | `snet-aks-virtual-nodes` | from AKS nodes and itself | `snet-aks`, itself | Delegated to ACI |
| `azure-container-apps` | `snet-containerapps` | 80, 443, 31080, 31443 from the Application Gateway; Azure Load Balancer; itself | `snet-appgw`, `AzureLoadBalancer`, itself | Project code: ingress `target_port` 80 and edge proxy |
| `azure-docs-assistant` | `snet-apim` | 443 from the internet; 3443 management | `Internet`, `ApiManagement` | API Management VNet requirements (not re-verified) |
| `azure-docs-assistant` | `snet-func` | none initiated from the VNet; itself | itself | Outbound-integration subnet |
| see below | `snet-privatelink` | **443**, one rule per service, to that service's ASG | per service (below); `snet-app` and `snet-data` keep a broad rule (443, 1433, 5432) | Private Endpoints |
| web tier | `snet-app` | 80, 443, 8080 from `snet-public` and `snet-appgw`; itself | as listed | |
| data tier | `snet-data` | from the application subnets and replication | see `nsg-data` | |

## Private Endpoints: one ASG per service

`snet-privatelink` hosts the private endpoints of many services, so each one has its own Application Security Group (`asg-<service>`) and its own rule. The ASG is the **destination**; the **source** stays a subnet CIDR because API Management, Function App and Container Apps cannot be ASG members.

| Rule (priority) | Source | Destination ASG | Port |
|---|---|---|---|
| `Allow-Apim-To-Function` (200) | `snet-apim` | `asg-function` | 443 |
| `Allow-Func-To-Cosmos` (300) | `snet-func` | `asg-cosmos` | 443 |
| `Allow-Func-To-Storage` (400) | `snet-func` | `asg-storage` | 443 |
| `Allow-Func-To-AIFoundry` (500) | `snet-func` | `asg-ai-foundry` | 443 |
| `Allow-Func-To-ContentSafety` (600) | `snet-func` | `asg-content-safety` | 443 |
| `Allow-Apps-To-KeyVault` (700) | `snet-containerapps`, `snet-aks` | `asg-keyvault` | 443 |

`asg-aks` is defined for the AKS node pool but no rule uses it yet (one node pool, one subnet).

**Consumers must associate their resources.** A private endpoint that is not a member of its ASG matches none of these rules and is blocked. The IDs come from the output `application_security_group_ids`:

- `azure-docs-assistant`: `application_security_group_associations` on the private endpoints of the Function App, its storage, Cosmos DB, AI Foundry and Content Safety (the AVM modules for Cosmos DB, the Function App, its storage and API Management accept it; AI Foundry and Content Safety use `azurerm_private_endpoint` directly, which needs `azurerm_private_endpoint_application_security_group_association`).
- `azure-aks-cluster`: `node_network_profile.application_security_group_ids` on the node pool (the repo does not use it yet).
- This repository associates its own Key Vault and storage endpoints.

Not ASG members (not possible): API Management, the Function App outbound integration, Container Apps, Application Gateway, NAT Gateway and Application Insights.

Flows are the intended design. They have not been validated on a deployment.
