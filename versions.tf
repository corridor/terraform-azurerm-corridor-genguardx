terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }

  # Backend: not set in the module. Configure in the root module that uses this module
  # (or when using this as a standalone repo, uncomment and set your Azure Storage details).
  # backend "azurerm" {
  #   resource_group_name  = "terraform-state-rg"
  #   storage_account_name = "genguardxtfstate"
  #   container_name       = "tfstate"
  #   key                  = "genguardx.terraform.tfstate"
  # }
}
