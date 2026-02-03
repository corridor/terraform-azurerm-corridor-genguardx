# Storage Account for Azure Files
resource "azurerm_storage_account" "main" {
  name                     = "${replace(var.resource_group_name, "-", "")}sa"
  resource_group_name     = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  tags = var.tags
}

# File Shares
resource "azurerm_storage_share" "data" {
  name                 = "data"
  storage_account_name  = azurerm_storage_account.main.name
  quota                = 100  # GB
}

resource "azurerm_storage_share" "uploads" {
  name                 = "uploads"
  storage_account_name  = azurerm_storage_account.main.name
  quota                = 50  # GB
}

resource "azurerm_storage_share" "databases" {
  name                 = "databases"
  storage_account_name  = azurerm_storage_account.main.name
  quota                = 10  # GB
}

resource "azurerm_storage_share" "notebooks" {
  name                 = "notebooks"
  storage_account_name  = azurerm_storage_account.main.name
  quota                = 20  # GB
}

resource "azurerm_storage_share" "config" {
  name                 = "config"
  storage_account_name  = azurerm_storage_account.main.name
  quota                = 1  # GB
}
