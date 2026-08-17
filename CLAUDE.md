# azure-virtual-network

Network layer: VNet + one regional subnet per tier (public/app/data/aks/appgw/privatelink), NSGs, route tables, NAT Gateway, Key Vault + Storage Account behind Private Endpoints, and observability (Flow Logs, Traffic Analytics, diagnostic settings to Log Analytics).

## Design decisions worth knowing before changing anything

- **One subnet per tier, not one per AZ.** Subnets are regional in Azure (they already span all zones) — HA comes from the `zones` argument on the *resources* deployed into them (VMs, VMSS, node pools), not from splitting subnets per AZ. If you see a suggestion to add `snet-app-az2`-style resources, that's the old design; don't reintroduce it.
- **`appgw` and `privatelink` subnets stay single** — always were, no per-AZ version ever existed for those.

## Backend

Remote state in Azure Blob Storage, provisioned by the sibling `azure-tfstate-bootstrap` project (not this one — chicken-and-egg). `backend.tf` here uses literal values (RG/storage account/container name), not partial config — decided deliberately: those values aren't secrets (no auth data in them), and partial config adds friction for no real security gain here. Key: `network/terraform.tfstate`.

## `subscription_id`

No default on purpose. **Set it with `TF_VAR_subscription_id`, not `ARM_SUBSCRIPTION_ID`.** The provider block does `subscription_id = var.subscription_id` explicitly, so Terraform needs the *variable* populated — `ARM_SUBSCRIPTION_ID` alone does nothing here (it only auto-works if the provider block omits `subscription_id` entirely). Got this wrong twice already — don't repeat it.

## `prevent_destroy` on the resource group + VNet

Both have `lifecycle { prevent_destroy = true }`. To do a real full teardown: comment out both lifecycle blocks, `terraform destroy`, then **put them back** before the next apply. Don't leave them removed.

## Known destroy gotcha

Azure auto-creates `Microsoft.Insights/dataCollectionRules` and `dataCollectionEndpoints` (named `NWTA-...`) as a side effect of Traffic Analytics on the Flow Log. These are never in Terraform state, so `terraform destroy` gets to the very last step (deleting the resource group) and fails with "Resource Group still contains Resources". Fix: `az resource list -g rg-network`, find the `NWTA-*` entries, `az resource delete --ids <them>`, then the resource group delete goes through (either re-run `terraform destroy` or `az group delete -n rg-network --yes` directly).

## Key Vault soft-delete

`kv-ha-vnet-demo` has Azure's mandatory soft-delete (not purge protection, which is off). After a destroy, check `az keyvault list-deleted` before a re-apply if the name conflicts.

## Consumers — check before renaming subnets/outputs

Other projects in this workspace read this module's outputs directly (no `terraform_remote_state` data source, just copied values):

| Project | Reads |
|---|---|
| `azure-jumpbox-server` | `app_subnet_id` |
| `azure-mysql-database` | `data_subnet_id` |
| `azure-lb-webserver` | subnet names directly (`snet-appgw`, app subnet names) |
| `azure-aks-cluster` | own backend via `azure-tfstate-bootstrap`; may reference subnet/NSG outputs |

Renaming a subnet, changing an output name, or changing a CIDR here can silently break any of these if they've been applied. Check before assuming it's safe — don't guess.

## Git remotes — push to both, every time

- `origin` → `github.com:xstratus/azure-virtual-network` (public)
- `jalcalaroot` → `github.com:jalcalaroot/azure-virtual-network` (public)

Both should always carry identical history. `git push origin main && git push jalcalaroot main` after every commit. If they ever diverge again, prefer re-squashing to one clean commit + force-push over trying to merge unrelated histories.

## .gitignore convention

`*.tfstate*` and `*.tfvars` excluded (never commit real state/values). `.terraform.lock.hcl` **is** tracked intentionally (provider version reproducibility) — don't add it back to `.gitignore`. `.terraform/` (provider cache) excluded.

## If you find a secret in git history

Happened once already (a hardcoded `subscription_id`) — since these repos are small and young, squash to a single clean commit and force-push rather than trying to scrub individual commits. Confirm first (via `git log -S <the-secret>`) which commits actually contain it before deciding how deep the squash needs to go.
