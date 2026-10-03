# azure-virtual-network

Standalone Terraform project for the Azure network layer of the `jalcalaroot` account - VNet, subnets, NSGs, route tables, NAT Gateway, Key Vault + Storage behind Private Endpoints, Flow Logs, and the two subnets (`azure-container-apps`, `azure-aks-cluster`) that used to live as bolt-ons elsewhere. Deployed independently, own backend/state/CI-CD, same shape as `azure-container-apps`/`azure-aks-cluster`. **Was a bare Terraform module (no backend, consumed via `source = "git::...?ref=vX.Y.Z"` from `jalcalaroot-azure-bootstrap`) until 2026-09-29** - see "De modulo a proyecto standalone" below for why and what changed. Originally ported from `xtratus/azure-virtual-network`, minus resource-group creation.

## README structure (standard across all `jalcalaroot` Azure repos, 2026-09-30)

README.md is a presentation page, not a design doc — exactly 7 sections, in this order: **Architecture** (diagram), **Resources deployed** (table: Resource | Purpose | Docs, one real Azure-docs link per row), **Prerequisites**, **Usage** (concise, commands over prose), **Configuration**, **Outputs**, **CI/CD**. Nothing else — no Cost, Status, Design notes, or changelog sections, and no cross-repo references to other cloud accounts' projects (don't expose the AWS side's footprint from an Azure repo, or vice versa). All narrative — rationale, history, gotchas, incidents — belongs here in CLAUDE.md instead, linked from the README's closing line.

## Key difference from the source it was ported from

`xtratus/azure-virtual-network` creates its own resource group (one RG per project, that account's convention). This project does **not** — `jalcalaroot` uses a single shared resource group for everything, so `resource_group_name`/`location` are input variables (with defaults matching the only real deployment target), not resources managed here.

## De modulo a proyecto standalone (2026-09-29)

Disparado por una pregunta directa del usuario: "para que quedaria bootstrap si sacamos la vnet?" - la respuesta confirmo que la red nunca debio depender del ciclo de vida de `jalcalaroot-azure-bootstrap`, ni siquiera como llamada a modulo desde ahi. Cambios reales:

- **Backend propio** (`backend.tf`, key `virtual-network/terraform.tfstate`, mismo storage account que el resto de la cuenta) y **provider propio** (`providers.tf`) - ya no es "sin state, sin provider, el consumidor decide" (la vieja convencion de modulo, ver abajo).
- **Identidades de CI persistentes** (`ci_identities.tf` + root separado `./ci`) - mismo patron ya aplicado en `azure-container-apps`/`azure-aks-cluster`/`aws-eks-cluster`: este proyecto puede destruirse y recrearse sin que el CI se rompa, porque las identidades viven en un state que nunca se destruye junto con la red.
- **Pipeline de CI/CD propio** (`terraform-plan.yml`/`terraform-apply.yml`, reemplazando el viejo `terraform-validate.yml` de modulo) - PR con `plan` comentado + Checkov/tflint bloqueantes, push a `main` dispara `apply` real vía OIDC.
- **`examples/basic/` eliminado** - ya no hace falta un caller ficticio para validar, este proyecto se valida a si mismo con su propio backend real.
- **Las 2 subnets bolt-on (`containerapps`, `aks_virtual_nodes`) se unificaron en el mismo mapa `subnets` del modulo AVM de VNet.** Hasta ahora vivian AFUERA de este modulo (en el repo consumidor) especificamente para no forzar un bump de version de un git tag por una necesidad puntual de un solo proyecto - esa razon dejo de aplicar en cuanto este repo dejo de ser una libreria versionada consumida por otros; un cambio aca ya no tiene mas consumidores a los que romper.
- **`variables.tf`**: `resource_group_name`/`location` ganaron defaults (`jalcalaroot`/`eastus`, el unico deployment real de este proyecto). `tags` (antes un mapa completo requerido) paso a ser tags EXTRA que se mergean con una base (`Project`/`Environment`/`Owner`/`ManagedBy`) construida en `main.tf` a partir de `var.owner`/`var.environment` - mismo patron que `azure-container-apps`, en vez de forzar al consumidor a construir el mapa completo el mismo.

## Conventions (superseded en 2026-09-29 para los primeros 2 puntos - dejado para contexto historico)

- ~~No state, no backend, no `provider` block here~~ - ya no aplica, ver seccion de arriba.
- ~~No `tags` default here either~~ - ya no aplica, ver seccion de arriba.
- Provider version constraint: `>= 4.81.0, < 5.0.0` desde la migracion a AVM (ver "Rebuilt on Azure Verified Modules" abajo) - las AVM modules usadas internamente imponen ese piso/techo real, no es negociable sin chequear la constraint de cada modulo primero.
- ~~Version via git tags, consumers pin `?ref=<tag>`~~ - ya no aplica, este repo ya no se consume como modulo.
- ~~`examples/basic/` is how this module gets validated~~ - eliminado, ver seccion de arriba.

## azurerm v5 fixes made during the port

The source module predates azurerm v5 in places the upgrade guide didn't flag:
- `azurerm_key_vault` now requires `rbac_authorization_enabled` — set to `true` (RBAC over legacy access policies, current MS/HashiCorp recommendation).
- `azurerm_private_dns_zone_virtual_network_link` replaced `private_dns_zone_name` + `resource_group_name` with a single `private_dns_zone_id`.

## Known prerequisite

`observability.tf` reads the subscription's `NetworkWatcher_<region>` (auto-created by Azure on first VNet/flow-log deployment in a region) as a data source. On a subscription with zero networking history, `plan` fails there until it exists — see README.

## DevSecOps CI hardening (2026-09-02, `v0.1.0` → `v0.2.0`)

Workspace-wide audit found this repo's CI running only `fmt`+`validate` — same gap as `aws-vpc`, for the same reason (module repos got the weakest gates of any repo despite defining the actual resources). Added `tflint` (azurerm ruleset v0.32.0) + Checkov (blocking) to `terraform-validate.yml`, plus a standalone `gitleaks` workflow. Enabled GitHub branch protection on `main` (free — public repo) requiring `fmt + validate` and `gitleaks`.

tflint's `azurerm_resources_missing_prevent_destroy` rule is disabled in `.tflint.hcl` — at the time, the reasoning was "a reusable module shouldn't force `prevent_destroy` on every consumer." Since 2026-09-29 this isn't a module anymore, so that specific reasoning is retired, but the rule stays disabled for the same practical outcome under new reasoning: this project is meant to be destroyed/recreated on demand (see "Removed `prevent_destroy` from the VNet" right below), so a lint rule pushing toward `prevent_destroy` would still be fighting the design, just for a single deployment instead of many consumers.

## Removed `prevent_destroy` from the VNet (2026-09-06, `v0.4.0` → `v0.4.1`)

`network.tf` actually still had `lifecycle { prevent_destroy = true }` on `azurerm_virtual_network.this`, contradicting the design note directly above this one - real module code should never hardcode it, exactly for the reason already documented (consumers doing frequent spin-up/teardown cycles, like `jalcalaroot-azure-bootstrap`'s `environments/dev`, shouldn't have to fight the module to destroy their own throwaway environment). Removed it. If a consumer wants destroy protection, apply an [Azure Resource Lock](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/lock-resources) (`CanNotDelete`) at their own level instead - unlike a Terraform `lifecycle` block, a lock is a real Azure resource that can be conditionally created per environment (e.g. only in prod).

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

## Rebuilt on Azure Verified Modules (2026-09-28/29, `v0.4.1` → `v0.5.0`) - the "still a module consumed from elsewhere" framing below is superseded, see "De modulo a proyecto standalone" above for what's actually true today

User decision: from now on, everything built in Azure uses Azure Verified Modules (AVM) where an equivalent exists, instead of hand-written `azurerm_*` resources. `network.tf`, `keyvault.tf` (new file), and `storage.tf` (new file) now build the VNet/subnets, Key Vault, and both Storage Accounts on top of `Azure/avm-res-network-virtualnetwork/azurerm` (0.22.2), `Azure/avm-res-keyvault-vault/azurerm` (0.11.0), and `Azure/avm-res-storage-storageaccount/azurerm` (0.10.0) respectively. NSGs, route tables, NAT Gateway, private DNS zones, and observability (Log Analytics/Flow Log/diagnostic settings) stay as raw resources in `network.tf`/`observability.tf` - none of those have an AVM equivalent that fits this design.

**This was briefly attempted as an inline rewrite directly inside `jalcalaroot-azure-bootstrap` instead of here** (same day) - reverted once the actual intent was clarified: `jalcalaroot-azure-bootstrap` is the account's orchestrator (backend state, CI identities), not where infrastructure code should live. At the time this section was written, the plan was "the network stays its own module, consumed the same way it always was" - **that itself didn't last the day either**: a few hours later this repo stopped being a module entirely (see "De modulo a proyecto standalone" above).

**Real bugs found and fixed during the port** (all confirmed against real `terraform init`/`validate`/`plan` output or the actually-downloaded module source, never assumed from the Registry's docs, which were repeatedly stale or self-contradictory across all 3 AVM modules used):
- **`parent_id` vs `resource_group_name` inconsistency between AVM modules.** The VNet and Storage AVMs take `parent_id` (a resource group **ID**), while the Key Vault AVM takes `resource_group_name` (a **name**) - each AVM module has its own convention, don't assume they're consistent with each other just because they're all "AVM."
- **Duplicate private-endpoint name bug**, in `storage.tf`'s `private_endpoints` map: the `blob` and `dfs` entries need explicit, distinct `name` fields - without them, the module generates the same default name for both (same storage account, two subresources), and the second entry tries to overwrite the first's connection instead of creating a new one. Real error hit: `CannotChangePrivateLinkConnectionOnPrivateEndpoint`.
- **`diagnostic_settings_blob`/`diagnostic_settings_storage_account` need an explicit `name`** despite the module's schema listing it as `optional(string, null)` - omitting it fails with "argument name is required" from the module's internal `azapi_resource`.
- **Persistent azapi timeout on those same 2 diagnostic settings, dropped rather than fought indefinitely.** Both use `azapi_resource` internally (a raw ARM PUT) rather than a native `azurerm_monitor_diagnostic_setting`, and that path hit `context deadline exceeded` -> 404 `ResourceNotFound` on read-back across 3 separate apply attempts, spread out in time - looks like a real Azure API propagation-latency issue with this specific azapi pattern, not a config error. Non-critical telemetry (Transaction metrics on the storage account); not worth blocking the rest of the module retrying indefinitely against an endpoint that consistently outlasts the azapi provider's timeout. Both blocks are omitted from `storage.tf` with the reasoning inline.
- **No Private Endpoint IP outputs anymore** - the Key Vault/Storage AVM modules only expose `id`/`name`/`role_assignments` per private endpoint, not the assigned IP (unlike the hand-written resources this replaces). Dropped `key_vault_private_endpoint_ip`/`storage_blob_private_endpoint_ip`/`storage_dfs_private_endpoint_ip` from `outputs.tf` - nothing needs a raw IP when Private DNS Zone resolution (already wired up) handles connectivity, and no documented consumer read them.

`versions.tf`'s provider constraint narrowed from `>= 5.0` (no upper bound, "the consumer decides") to `>= 4.81.0, < 5.0.0` - the real intersection of what the 3 AVM modules support, verified against each module's own docs. At the time, this meant a module with AVM inside it imposes a real floor/ceiling on whatever consumes it (Terraform aggregates constraints across the whole module tree), and `examples/basic/main.tf` (used for CI's `terraform validate`) was updated to match. **Both of those are historical** - `examples/basic/` was deleted and there's no longer a consumer to impose a constraint on, see "De modulo a proyecto standalone" above. The `>= 4.81.0, < 5.0.0` constraint itself is still real and current, just now declared directly in this repo's own `versions.tf` for its own sake.

Verified end-to-end against the real `jalcalaroot` subscription: applied cleanly, then fully torn down again the same day (2026-09-29) as a deliberate cost-conscious teardown, not left running idle, then applied for real again after the standalone-project conversion later that day. `terraform plan` from empty state showed a clean 56-to-add with this version, no drift. (At the time this paragraph was first written, this was verified "via `jalcalaroot-azure-bootstrap` (its actual consumer)" - no longer true, see above.)

## Identidades de CI en state propio

`virtual-network-agent`/`virtual-network-plan` (`azurerm_user_assigned_identity` + sus `azurerm_federated_identity_credential`) viven en un root de Terraform separado, [`./ci`](./ci) - state propio (`virtual-network-ci/terraform.tfstate`, mismo storage account), en el resource group compartido `jalcalaroot` (nunca se destruye), no en el state principal de este repo. Este proyecto puede destruirse y recrearse cuantas veces haga falta sin que las identidades de CI se vean afectadas - `ARM_CLIENT_ID_AGENT`/`ARM_CLIENT_ID_PLAN` (GitHub variables) se configuran una sola vez.

`ci_identities.tf` (en el root principal) no crea las identidades - las referencia via `data "azurerm_user_assigned_identity"` (por nombre/RG) para poder seguir otorgandoles los `azurerm_role_assignment` de RBAC sobre los recursos de ESTE root (resource group, backend de state, Network Watcher), que si se destruyen/recrean con el ciclo de vida normal del proyecto.

**Aplicar `./ci` es un paso manual, no un workflow de CI** - se hace una sola vez, con credenciales locales amplias, igual que el primer `apply` de cualquier proyecto nuevo.

Mismo fix ya aplicado en `azure-container-apps`/`azure-aks-cluster`/`aws-eks-cluster` (mismo problema: las identidades vivian en el mismo state que la infraestructura destruible, y un teardown se las llevaba puestas, rompiendo el CI hasta el proximo redeploy). Este repo lo tuvo resuelto desde el dia que se convirtio en proyecto standalone - nunca llego a pisar el bug en production porque el `./ci` se armo junto con todo lo demas el mismo 2026-09-29.

## Subnet nueva `func`, delegada a Microsoft.App/environments (2026-09-30, delegacion corregida 2026-10-03)

Gap real encontrado escribiendo `azure-agent-platform` (proyecto nuevo, RAG platform): ese repo necesita VNet integration (outbound) para un Function App en plan Flex Consumption, y **ninguna subnet existente hasta ese momento tenia delegation a `Microsoft.Web/serverFarms`** - cada subnet solo admite una sola delegation, asi que ni `privatelink` (delegada a Private Endpoints) ni `appgw` (sin delegation pero reservada para Application Gateway) servian. Se agrego una subnet nueva siguiendo exactamente el mismo patron ya usado para `containerapps`/`aks_virtual_nodes` (bolt-on delegado, con su propia NSG minima - `Allow-VNet-Inbound` + `Deny-All-Inbound` - y asociada al NAT Gateway compartido para egress controlado, sin route table propia):

- `func_subnet_cidr` default `10.0.73.0/24` (el siguiente bloque libre despues de `aks_virtual_nodes_subnet_cidr`, que termina en `10.0.72.255`)
- `nsg-func`, mismo criterio que `nsg-aks-virtual-nodes` (subnet delegada, sin trafico inbound iniciado desde afuera de la VNet)
- `delegations = [{ name = "funcDelegation", service_delegation = { name = "Microsoft.App/environments" } }]`
- Outputs nuevos: `func_subnet_id` y `network_func_subnet_id` (este ultimo es el que copia `azure-agent-platform` a su variable `network_function_app_subnet_id`)

Aplicado contra la VNet ya desplegada - agrega 1 subnet + 1 NSG, no destruye ni reemplaza nada existente.

**Correccion 2026-10-03 (error mio, encontrado en el primer apply real de `azure-agent-platform`):** la subnet se creo delegada a `Microsoft.Web/serverFarms`, que es la delegacion de los planes Premium y Dedicated. **Flex Consumption exige `Microsoft.App/environments`** (doc "Create and Manage Function Apps in a Flex Consumption Plan": "Delegate the subnet to `Microsoft.App/environments`. This delegation differs from Premium and Dedicated plans, which use `Microsoft.Web/serverFarms`"). Con la delegacion equivocada el Function App fallaba con `ServiceAssociationLink ... Unable to integrate function app with subnet`. Otras restricciones de esa doc: el resource provider `Microsoft.App` debe estar registrado, el nombre de la subnet no puede llevar `_`, la subnet no puede tener Private Endpoints ni service endpoints, y no se comparte con un entorno de Container Apps (`snet-containerapps` es una subnet aparte). Se cambio la delegacion en el codigo y se aplico contra la VNet real; los textos de arriba que dicen `Microsoft.Web/serverFarms` describen la decision original y quedan solo como historia.

## Subnet nueva `apim`, para API Management en modo VNet External (2026-10-03)

`azure-agent-platform` cambia su capa de entrada de Application Gateway + WAF a **API Management tier Developer** (~$48/mes, el mas barato que soporta VNet injection) delante del Function App privado. Developer en modo **External** deja el gateway publico y le permite llegar a backends privados (el Function App por Private Endpoint), asi que necesita su propia subnet dentro de esta VNet:

- `apim_subnet_cidr` default `10.0.74.0/24` (siguiente bloque libre despues de `func`, 10.0.73.0/24). Minimo exigido por Microsoft: /29; con el tier Developer usa una sola IP.
- **Sin delegation** - la doc de APIM dice explicitamente que la subnet "shouldn't have any delegations enabled" (a diferencia de `func`, `containerapps` y `aks_virtual_nodes`).
- `nsg-apim` con las reglas minimas de entrada para modo External: `Internet` -> 443 y `ApiManagement` -> 3443 (plano de administracion), **sin** `Deny-All-Inbound` (ver correccion abajo). El outbound que APIM necesita (Storage, SQL, Key Vault, Azure Monitor, Entra ID) lo cubre el allow-all por defecto de Azure, mismo criterio que el resto de NSGs de este archivo, que no definen reglas de salida. `AzureLoadBalancer`:6390 no hace falta en Developer.
- Sin NAT Gateway ni route table asociados: APIM con IP publica gestionada por Azure sale por su propia IP, y no hay motivo para forzarlo por el NAT compartido.
- Outputs nuevos: `apim_subnet_id` y `network_apim_subnet_id` (el que copia `azure-agent-platform` a `network_apim_subnet_id`).


**Correccion 2026-10-03:** `nsg-apim` se creo con un `Deny-All-Inbound` (4096) como el resto de NSGs de este archivo, y API Management fallo dos veces seguidas con `ActivationFailed` (primero con IP gestionada, luego con IP publica propia, sin detalle en el activity log). Un deny explicito anula las reglas por defecto de Azure `AllowVnetInBound` y `AllowAzureLoadBalancerInBound`, que la plataforma de APIM usa para los health probes de su load balancer interno y el trafico entre nodos - aunque la doc diga que `AzureLoadBalancer`:6390 "no se requiere" en Developer. Se quito el deny de `nsg-apim` (Internet sigue bloqueado por la regla por defecto `DenyAllInbound` 65500, salvo el 443 y el 3443 permitidos). Aplicado contra la VNet real (1 cambio, solo esa NSG, via `-target`).

Solo codigo - no aplicado: la VNet esta destruida en Azure desde 2026-09-30. Mergear a `main` dispara `terraform-apply.yml` y recrea toda la red.

## Status

- 2026-10-03 (latest): Delegacion de la subnet `func` corregida a `Microsoft.App/environments` (Flex Consumption). Subnet `apim` agregada en codigo (rama `add-apim-subnet`, apilada sobre `add-func-subnet` / PR #32, que sigue abierto). Sin aplicar. Ver seccion arriba.
- 2026-09-30: Subnet `func` agregada (delegada a `Microsoft.Web/serverFarms`), para la VNet integration del Function App de `azure-agent-platform`. Ver seccion arriba. Aplicado contra la VNet real, sin downtime ni destroy de recursos existentes.
- 2026-09-29: Converted from a bare Terraform module (consumed by `jalcalaroot-azure-bootstrap`) to a fully standalone project - own backend, own persistent CI identities (`./ci`), own CI/CD pipeline, the 2 bolt-on subnets folded into the main `subnets` map, `examples/basic/` removed. See "De modulo a proyecto standalone" above. Applied for real against the `jalcalaroot` subscription.
- 2026-09-28/29: Rebuilt on Azure Verified Modules. See section above. Tagged `v0.5.0`.
- 2026-09-05: Supply-chain hardening - all Actions pinned by SHA, Dependabot watching `github-actions`, OSSF Scorecard added. See section above.
- 2026-09-03: Checkov → SARIF → GitHub Security tab (free, public repo). `.pre-commit-config.yaml` added (gitleaks + `terraform fmt`) so secrets/formatting get caught locally, not just in CI. All 15 pre-existing Checkov exceptions dismissed in the Security tab with reasons/comments (see gotcha above) — 0 open alerts.
- 2026-09-02: DevSecOps hardening - tflint+Checkov+gitleaks in CI, branch protection on `main`, both storage accounts hardened (public access, TLS, retention, SAS policy, shared-key auth on the data storage account). Tagged `v0.2.0`.
- 2026-09-02: Repo created (renamed from the old `xtratus/azure-virtual-network` mirror, which is now `jalcalaroot/azure-virtual-network-xtratus` — unrelated history, don't confuse the two). Full design ported and validated with a real `terraform plan` against the `jalcalaroot` subscription (55 resources, clean, not yet applied). Tagged `v0.1.0`. Not yet wired into `jalcalaroot-azure-bootstrap/environments/dev` — that's the next step whenever real deployment is wanted (creates a NAT Gateway, Key Vault, Storage Account - real cost).
