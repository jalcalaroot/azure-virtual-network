# azure-virtual-network

Terraform module (not a deployable project) for the Azure network layer of the `jalcalaroot` account. Lives at the repo root (no `terraform/bootstrap`/`environments` split — that structure is for `jalcalaroot-azure-bootstrap`, which consumes this module). Ported from `xtratus/azure-virtual-network`, minus resource-group creation.

## Key difference from the source it was ported from

`xtratus/azure-virtual-network` creates its own resource group (one RG per project, that account's convention). This module does **not** — `jalcalaroot` uses a single shared resource group for everything, so `resource_group_name`/`location` are required input variables, not resources this module manages.

## Conventions

- No state, no backend, no `provider` block here — a module never configures its own provider; the consumer's provider (with its own `subscription_id`, auth) applies.
- No `tags` default here either — `tags` is a required variable, always passed through from the consumer's own tags module (`jalcalaroot-azure-bootstrap/terraform/modules/tags`). Don't hardcode tags in this repo.
- Provider version constraint is intentionally loose (`>= 5.0`, no upper bound) — the consumer's own `~> 5.0` pin governs the actual resolved version. Don't tighten this to `~>` here; that's how version conflicts happen when a module is more restrictive than its consumer.
- Version via git tags (`v0.1.0`, ...), consumers pin `?ref=<tag>` in their `source`. Never expect a consumer to track `main`.
- `examples/basic/` is how this module gets validated (`terraform validate`/`plan` needs a caller — a bare module has nothing to plan on its own).

## azurerm v5 fixes made during the port

The source module predates azurerm v5 in places the upgrade guide didn't flag:
- `azurerm_key_vault` now requires `rbac_authorization_enabled` — set to `true` (RBAC over legacy access policies, current MS/HashiCorp recommendation).
- `azurerm_private_dns_zone_virtual_network_link` replaced `private_dns_zone_name` + `resource_group_name` with a single `private_dns_zone_id`.

## Known prerequisite

`observability.tf` reads the subscription's `NetworkWatcher_<region>` (auto-created by Azure on first VNet/flow-log deployment in a region) as a data source. On a subscription with zero networking history, `plan` fails there until it exists — see README.

## DevSecOps CI hardening (2026-09-02, `v0.1.0` → `v0.2.0`)

Workspace-wide audit found this repo's CI running only `fmt`+`validate` — same gap as `aws-vpc`, for the same reason (module repos got the weakest gates of any repo despite defining the actual resources). Added `tflint` (azurerm ruleset v0.32.0) + Checkov (blocking) to `terraform-validate.yml`, plus a standalone `gitleaks` workflow. Enabled GitHub branch protection on `main` (free — public repo) requiring `fmt + validate` and `gitleaks`.

tflint's `azurerm_resources_missing_prevent_destroy` rule is disabled in `.tflint.hcl` — `lifecycle` blocks can't take variables, so baking `prevent_destroy` into a reusable module would force it on every consumer including throwaway dev environments. That's a per-consumer decision (same call `xtratus/azure-virtual-network` makes at its own level, not inside a module).

Real fixes made getting Checkov clean: both storage accounts (`flow_logs`, `this`) now set `allow_nested_items_to_be_public = false`, `min_tls_version = "TLS1_2"`, blob delete-retention (7d), and a SAS expiration policy. `azurerm_storage_account.this` also gets `shared_access_key_enabled = false` — consistent with `rbac_authorization_enabled = true` already set on this module's own Key Vault, AAD-only auth throughout.

15 Checkov exceptions, documented inline — most notably: Key Vault purge protection stays off (already a deliberate, pre-existing decision — see the `# set to true for production` comment right next to it), HTTP 80 stays open on the `public`/`appgw` NSGs for App Gateway's HTTP→HTTPS redirect, several cost-conscious calls (LRS/ZRS over GRS, no CMK, 30-day flow log retention — consistent with this workspace's cost-conscious-by-default convention established on the AWS side), and `shared_access_key_enabled` was deliberately **left on** for the `flow_logs` storage account specifically — no documented confirmation that Azure Network Watcher can write flow logs to an AAD-only storage account, so functioning observability took priority over that one check. Revisit if Microsoft ever documents AAD-only support for flow log destinations.

## Status

- 2026-09-03: Checkov → SARIF → GitHub Security tab (free, public repo). `.pre-commit-config.yaml` added (gitleaks + `terraform fmt`) so secrets/formatting get caught locally, not just in CI.
- 2026-09-02: DevSecOps hardening - tflint+Checkov+gitleaks in CI, branch protection on `main`, both storage accounts hardened (public access, TLS, retention, SAS policy, shared-key auth on the data storage account). Tagged `v0.2.0`.
- 2026-09-02: Repo created (renamed from the old `xtratus/azure-virtual-network` mirror, which is now `jalcalaroot/azure-virtual-network-xtratus` — unrelated history, don't confuse the two). Full design ported and validated with a real `terraform plan` against the `jalcalaroot` subscription (55 resources, clean, not yet applied). Tagged `v0.1.0`. Not yet wired into `jalcalaroot-azure-bootstrap/environments/dev` — that's the next step whenever real deployment is wanted (creates a NAT Gateway, Key Vault, Storage Account - real cost).
