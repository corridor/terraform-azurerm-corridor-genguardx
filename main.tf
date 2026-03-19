# Terraform configuration moved to versions.tf

provider "azurerm" {
  features {}
}

# Data source for existing resource group (when create_resource_group = false)
data "azurerm_resource_group" "existing" {
  count = var.create_resource_group ? 0 : 1
  name  = var.resource_group_name
}

# Resource Group (when create_resource_group = true)
resource "azurerm_resource_group" "main" {
  count    = var.create_resource_group ? 1 : 0
  name     = var.resource_group_name
  location = var.location
  
  tags = var.tags
}

# Local to reference the correct resource group
locals {
  resource_group_name = var.create_resource_group ? azurerm_resource_group.main[0].name : data.azurerm_resource_group.existing[0].name
  location            = var.create_resource_group ? azurerm_resource_group.main[0].location : data.azurerm_resource_group.existing[0].location
}

# Container Apps configuration moved to container_apps.tf
# This provides Cloud Run-like auto-scaling with scale-to-zero capability
