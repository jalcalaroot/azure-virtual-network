# Identidades de CI para GitHub Actions via OIDC (Workload Identity
# Federation) - sin ningun secreto de Azure almacenado en GitHub. Mismo
# patron que azure-container-apps/azure-aks-cluster: "agent" (apply, push a
# main) y "plan" (solo lectura, PRs), RBAC acotado recurso por recurso.
#
# Los identity/federated_identity_credential YA NO se crean aca - viven en
# el root separado ./ci (state propio, nunca se destruye junto con la red).
# Ver CLAUDE.md, seccion "Identidades de CI en state propio", para el
# porque. Este archivo solo referencia esas identidades via data source
# para poder seguir otorgandoles RBAC sobre los recursos de ESTE root, que
# si se destruyen/recrean con el ciclo de vida normal del proyecto.
data "azurerm_user_assigned_identity" "ci_agent" {
  name                = "virtual-network-agent"
  resource_group_name = "jalcalaroot"
}

data "azurerm_user_assigned_identity" "ci_plan" {
  name                = "virtual-network-plan"
  resource_group_name = "jalcalaroot"
}

data "azurerm_storage_account" "tfstate" {
  name                = "sttfstatejalcalaroot"
  resource_group_name = "jalcalaroot"
}

# data.azurerm_network_watcher.this ya esta declarado en observability.tf -
# reutilizado aca, no redeclarado.

# --------------------------------------------------------------------------
# RBAC - acotado recurso por recurso.
# --------------------------------------------------------------------------

resource "azurerm_role_assignment" "ci_agent_rg_contributor" {
  scope                = data.azurerm_resource_group.this.id
  role_definition_name = "Contributor"
  principal_id         = data.azurerm_user_assigned_identity.ci_agent.principal_id
}

resource "azurerm_role_assignment" "ci_plan_rg_reader" {
  scope                = data.azurerm_resource_group.this.id
  role_definition_name = "Reader"
  principal_id         = data.azurerm_user_assigned_identity.ci_plan.principal_id
}

# Backend remoto: Storage Blob Data Owner (data plane, lease de locking) +
# Reader (management plane, para que el data source azurerm_storage_account
# pueda leer el objeto ARM). "Storage Blob Data Contributor" NO ALCANZA -
# su dataActions ([delete, read, write, move/action, add/action]) no
# incluye blobs/lease/action, confirmado contra la definicion real del rol
# el 2026-10-03 cuando esto rompio drift-detection.yml de
# jalcalaroot-azure-bootstrap con AuthorizationPermissionMismatch. "Owner"
# si lo cubre (dataActions = blobs/* via wildcard) - es el minimo real,
# Azure no tiene un rol que de solo "lease" sin tambien delete/move/add.
# Mismo fix en jalcalaroot-azure-bootstrap/azure-container-apps/azure-aks-cluster.
resource "azurerm_role_assignment" "ci_agent_state_write" {
  scope                = data.azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = data.azurerm_user_assigned_identity.ci_agent.principal_id
}

resource "azurerm_role_assignment" "ci_plan_state_write" {
  scope                = data.azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = data.azurerm_user_assigned_identity.ci_plan.principal_id
}

resource "azurerm_role_assignment" "ci_agent_state_reader" {
  scope                = data.azurerm_storage_account.tfstate.id
  role_definition_name = "Reader"
  principal_id         = data.azurerm_user_assigned_identity.ci_agent.principal_id
}

resource "azurerm_role_assignment" "ci_plan_state_reader" {
  scope                = data.azurerm_storage_account.tfstate.id
  role_definition_name = "Reader"
  principal_id         = data.azurerm_user_assigned_identity.ci_plan.principal_id
}

# Network Watcher vive en NetworkWatcherRG, fuera del resource group
# compartido donde el agent/plan ya tienen Contributor/Reader - necesita su
# propio role assignment escopeado al recurso puntual. "Network Contributor"
# alcanza para crear el Flow Log, pero NO para habilitar Traffic Analytics
# sobre el (ver enable_traffic_analytics default = false en variables.tf) -
# mismo gap ya documentado en jalcalaroot-azure-bootstrap.
resource "azurerm_role_assignment" "ci_agent_network_watcher_contributor" {
  scope                = data.azurerm_network_watcher.this.id
  role_definition_name = "Contributor"
  principal_id         = data.azurerm_user_assigned_identity.ci_agent.principal_id
}

resource "azurerm_role_assignment" "ci_plan_network_watcher_reader" {
  scope                = data.azurerm_network_watcher.this.id
  role_definition_name = "Reader"
  principal_id         = data.azurerm_user_assigned_identity.ci_plan.principal_id
}
