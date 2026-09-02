# azure-virtual-network

Terraform module (not a deployable project) for the Azure network layer of the `jalcalaroot` account. Lives at the repo root (no `terraform/bootstrap`/`environments` split — that structure is for `jalcalaroot-azure`, which will consume this module).

## Conventions

- No state, no backend, no `provider` block here — a module never configures its own provider; the consumer's provider (with its own `subscription_id`, auth, tags) applies.
- Tag every resource with `tags = var.tags` (or similar) so the consumer can pass through its own tag module (see `jalcalaroot-azure/terraform/modules/tags`) — don't hardcode tags here.
- Version via git tags (`v0.1.0`, ...), consumers pin `?ref=<tag>` in their `source`. Never expect a consumer to track `main`.
- `examples/` (once it exists) is how this module gets validated in CI — `terraform validate`/`plan` needs a caller, a bare module has nothing to plan.

## Status

- 2026-09-02: Repo created (renamed from the old `xtratus/azure-virtual-network` mirror, which is now `jalcalaroot/azure-virtual-network-xtratus` — unrelated history, don't confuse the two). No module code yet.
