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

## Secret scanning: two independent layers

1. **gitleaks** (ours) — runs in CI (`gitleaks.yml`) and locally via pre-commit. Covers all 4 repos in the workspace.
2. **GitHub's own native secret scanning + push protection** — confirmed `enabled` on this repo via the API (`security_and_analysis.secret_scanning.status`), free for public repos, zero setup from us. Push protection rejects a push containing a recognized secret pattern *before* it lands, not just flags it after. View at Settings → Security → Secret scanning alerts.

Not available on the 2 private bootstrap repos — same GitHub Advanced Security gate as Code scanning/SARIF. gitleaks is the only coverage there.

## Gotcha: `#checkov:skip` doesn't dismiss the Security-tab alert

Checkov's SARIF export doesn't mark skipped/accepted findings as suppressed — GitHub's code scanning shows them as regular **open** alerts regardless of the inline `#checkov:skip` comment and justification in the `.tf` file. All 15 existing ones were manually dismissed via the API (`gh api -X PATCH repos/jalcalaroot/azure-virtual-network/code-scanning/alerts/<n> -f state=dismissed -f dismissed_reason="..." -f dismissed_comment="..."`) with a reason (`false positive` for genuine Checkov limitations, `won't fix` for deliberate cost/design decisions) and a comment pointing back to the `.tf` justification. **If a future PR adds a new `#checkov:skip`, its alert will show up open in the Security tab and needs the same manual dismiss** — nothing automates this yet.

## Supply-chain hardening (2026-09-05)

Every third-party GitHub Action in this repo's workflows is now pinned to a full commit SHA (with a `# vX.Y.Z` comment for readability), per [GitHub's own Actions hardening guide](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions) — a tag like `@v4` is mutable; if that upstream repo is ever compromised and the tag moved, our CI would silently run malicious code with our OIDC credentials on the next push. `dependabot.yml` now also watches the `github-actions` ecosystem so these pins get bumped (new SHA + comment) automatically instead of going stale.

## Gotcha: tflint's unauthenticated GitHub API rate limit (real, hit in production)

`tflint --init` fetches the `azurerm` ruleset plugin from the GitHub API. Without a token, that's capped at 60 requests/hour **per IP** — and GitHub-hosted runners share IP pools across every repo/org using them, so this limit gets exhausted by unrelated traffic, not just ours. This broke a real CI run on `main` on 2026-09-05 with `403 API rate limit exceeded`. Fix: pass `GITHUB_TOKEN: ${{ github.token }}` as an env var on the `tflint` step (raises the limit to 5000/hour) — already applied here.

**Related bug this exposed**: the SARIF-upload step had `if: always()`, meant to survive a *Checkov* failure (`soft_fail: false` exits non-zero on findings) — but it also ran when an *earlier, unrelated* step failed (tflint's rate limit), and choked on `results.sarif` not existing, masking the real error. Fixed by giving the Checkov step `id: checkov` and changing the upload condition to `if: always() && steps.checkov.outcome != 'skipped'`.

Added `scorecard.yml` ([OSSF Scorecard](https://scorecard.dev/)) — free for public repos, uploads to the same Security tab as Checkov. Audits exactly this kind of practice (pinned dependencies, branch protection, token permissions, dangerous workflow patterns, etc.) automatically on every push, so a future unpinned Action gets flagged without anyone having to remember to check.

## Status

- 2026-09-05: Supply-chain hardening - all Actions pinned by SHA, Dependabot watching `github-actions`, OSSF Scorecard added. See section above.
- 2026-09-03: Checkov → SARIF → GitHub Security tab (free, public repo). `.pre-commit-config.yaml` added (gitleaks + `terraform fmt`) so secrets/formatting get caught locally, not just in CI. All 15 pre-existing Checkov exceptions dismissed in the Security tab with reasons/comments (see gotcha above) — 0 open alerts.
- 2026-09-02: DevSecOps hardening - tflint+Checkov+gitleaks in CI, branch protection on `main`, both storage accounts hardened (public access, TLS, retention, SAS policy, shared-key auth on the data storage account). Tagged `v0.2.0`.
- 2026-09-02: Repo created (renamed from the old `xtratus/azure-virtual-network` mirror, which is now `jalcalaroot/azure-virtual-network-xtratus` — unrelated history, don't confuse the two). Full design ported and validated with a real `terraform plan` against the `jalcalaroot` subscription (55 resources, clean, not yet applied). Tagged `v0.1.0`. Not yet wired into `jalcalaroot-azure-bootstrap/environments/dev` — that's the next step whenever real deployment is wanted (creates a NAT Gateway, Key Vault, Storage Account - real cost).
