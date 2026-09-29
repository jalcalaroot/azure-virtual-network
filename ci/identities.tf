# Identidades de CI para GitHub Actions via OIDC - state propio, separado
# del root principal (VNet/Key Vault/Storage), para que este proyecto pueda
# destruirse y recrearse cuantas veces haga falta sin que el CI se rompa -
# mismo fix ya aplicado en azure-aks-cluster/aws-eks-cluster/
# azure-container-apps. Ver CLAUDE.md, seccion "Identidades de CI en state
# propio", para el detalle completo.
data "azurerm_resource_group" "shared" {
  name = "jalcalaroot"
}

resource "azurerm_user_assigned_identity" "ci_agent" {
  name                = "virtual-network-agent"
  resource_group_name = data.azurerm_resource_group.shared.name
  location            = data.azurerm_resource_group.shared.location
}

resource "azurerm_user_assigned_identity" "ci_plan" {
  name                = "virtual-network-plan"
  resource_group_name = data.azurerm_resource_group.shared.name
  location            = data.azurerm_resource_group.shared.location
}

# Subject claims segun el formato ACTUAL de GitHub para este repo
# (confirmado via `gh api repos/jalcalaroot/azure-virtual-network/actions/oidc/customization/sub`).
# Push a main y schedule (cron) presentan el MISMO subject claim
# (ref:refs/heads/main) - por eso una sola federated credential en "agent"
# alcanza para ambos triggers de terraform-apply.yml.
resource "azurerm_federated_identity_credential" "ci_agent_main" {
  name                      = "github-main"
  user_assigned_identity_id = azurerm_user_assigned_identity.ci_agent.id
  issuer                    = "https://token.actions.githubusercontent.com"
  audience                  = ["api://AzureADTokenExchange"]
  subject                   = "repo:jalcalaroot@22682982/azure-virtual-network@1354877757:ref:refs/heads/main"
}

resource "azurerm_federated_identity_credential" "ci_plan_pr" {
  name                      = "github-pull-request"
  user_assigned_identity_id = azurerm_user_assigned_identity.ci_plan.id
  issuer                    = "https://token.actions.githubusercontent.com"
  audience                  = ["api://AzureADTokenExchange"]
  subject                   = "repo:jalcalaroot@22682982/azure-virtual-network@1354877757:pull_request"
}
