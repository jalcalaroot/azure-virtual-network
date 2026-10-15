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
| any | `snet-privatelink` | **443** to Private Endpoints | `snet-apim`, `snet-func`, `snet-containerapps`, `snet-aks` | Cosmos DB, AI Foundry, Content Safety, Key Vault, storage, Function App; 1433 and 5432 also allowed from `snet-app` and `snet-data` |
| web tier | `snet-app` | 80, 443, 8080 from `snet-public` and `snet-appgw`; itself | as listed | |
| data tier | `snet-data` | from the application subnets and replication | see `nsg-data` | |

Flows are the intended design. They have not been validated on a deployment.
