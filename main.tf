terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.41.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.36.0"
    }

  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_deleted_secrets_on_destroy = true
      recover_soft_deleted_secrets          = true
    }
  }
}

resource "azurerm_resource_group" "Olympic_project" {
  name     = var.resource_group_name
  location = "West Europe"
}

resource "azurerm_data_factory" "Data_factory_olympic_games" {
  name                = "Data-Factory-Olympic"
  location            = azurerm_resource_group.Olympic_project.location
  resource_group_name = azurerm_resource_group.Olympic_project.name
}

data "azuread_client_config" "current" {}
data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "kv_olympic_games" {
  name                = "Kv-Olympic"
  location            = azurerm_resource_group.Olympic_project.location
  resource_group_name = azurerm_resource_group.Olympic_project.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"
}

resource "azurerm_key_vault_access_policy" "kv_access_policy" {
  key_vault_id = azurerm_key_vault.kv_olympic_games.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  key_permissions = [
    "Delete", "Backup", "Get", "List", "Encrypt", "Decrypt", "Restore", "Recover", "Purge"
  ]
  secret_permissions = [
    "Get", "List", "Set", "Delete", "Backup", "Restore", "Recover,"Purge"
  ]
}




# Here I create the app in azure 
resource "azuread_application" "Olympic_app" {
  display_name = "Olympic_Games_App"
  owners       = [data.azuread_client_config.current.object_id]
}
# Here is the client secret which we have in azure console
resource "azuread_service_principal" "Olympic_principal" {
  application_id               = azuread_application.Olympic_app.application_id
  app_role_assignment_required = false
  owners                       = [data.azuread_client_config.current.object_id]
}

resource "time_rotating" "time_schedule" {
  rotation_days = 20
}
# secret client password
resource "azuread_service_principal_password" "secret_password" {
  display_name         = "Olympic_app"
  service_principal_id = azuread_service_principal.Olympic_principal.object_id
  rotate_when_changed = {
    rotation = time_rotating.time_schedule.id
  }
}

resource "azurerm_key_vault_secret" "store_secret_principal_key" {
  name         = "secret-principal-key"
  value        = azuread_service_principal_password.secret_password.value
  key_vault_id = azurerm_key_vault.kv_olympic_games.id
}


data "azurerm_subscription" "current" {}
resource "azurerm_role_assignment" "role_olympic_games" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.Olympic_principal.object_id
}

