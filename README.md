# azure-virtual-network

Reusable Terraform module for the Azure network layer (VNet, subnets, NSGs, NAT Gateway) used by the `jalcalaroot` account's projects.

## Stack

- **IaC**: Terraform module, consumed via `source = "git::https://github.com/jalcalaroot/azure-virtual-network.git?ref=<tag>"` — this repo has no backend or state of its own.
- **Consumer**: `jalcalaroot-azure` (and future projects in that account).

## Usage

Not implemented yet — see Status below.

## Status

Early stage — repo scaffolding only, no module code yet. Design pending.

See `CLAUDE.md` for conventions.
