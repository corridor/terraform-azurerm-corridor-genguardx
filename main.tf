# Terraform configuration moved to versions.tf

provider "azurerm" {
  features {}
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  
  tags = var.tags
}

# Container Apps configuration moved to container_apps.tf
# This provides Cloud Run-like auto-scaling with scale-to-zero capability
