# Azure Database for PostgreSQL Flexible Server
resource "azurerm_postgresql_flexible_server" "main" {
  name                   = "${replace(var.resource_group_name, "-", "")}-postgres"
  resource_group_name    = azurerm_resource_group.main.name
  location               = azurerm_resource_group.main.location
  version                = "15"
  delegated_subnet_id    = null  # Use public access for simplicity
  private_dns_zone_id    = null
  administrator_login    = var.db_admin_username
  administrator_password = var.db_admin_password
  zone                   = "1"

  storage_mb = var.db_storage_mb

  sku_name = var.db_sku_name

  backup_retention_days        = 7
  geo_redundant_backup_enabled = false

  # Allow public access (for cost-effective setup)
  public_network_access_enabled = true

  tags = var.tags
}

# Firewall rule to allow Azure services
resource "azurerm_postgresql_flexible_server_firewall_rule" "allow_azure" {
  name             = "AllowAzureServices"
  server_id        = azurerm_postgresql_flexible_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# Firewall rule to allow all IPs (for simplicity - can be restricted later)
resource "azurerm_postgresql_flexible_server_firewall_rule" "allow_all" {
  name             = "AllowAll"
  server_id        = azurerm_postgresql_flexible_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "255.255.255.255"
}

# Database
resource "azurerm_postgresql_flexible_server_database" "main" {
  name      = var.db_name
  server_id = azurerm_postgresql_flexible_server.main.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# Server parameters to avoid "out of shared memory" on small Basic tier (2GB)
# - max_prepared_transactions=0: frees shared memory (disables server-side prepared statements)
# - max_connections=20: reduces per-connection shared memory usage
resource "azurerm_postgresql_flexible_server_configuration" "max_prepared_transactions" {
  name      = "max_prepared_transactions"
  server_id = azurerm_postgresql_flexible_server.main.id
  value     = "0"
}

resource "azurerm_postgresql_flexible_server_configuration" "max_connections" {
  name      = "max_connections"
  server_id = azurerm_postgresql_flexible_server.main.id
  value     = "25"  # Minimum allowed by Azure Flexible Server (25-5000)
}

# Increase lock table size so migrations with many tables don't hit "out of shared memory"
# (HINT: You might need to increase max_locks_per_transaction). Default 64; 256 gives headroom.
resource "azurerm_postgresql_flexible_server_configuration" "max_locks_per_transaction" {
  name      = "max_locks_per_transaction"
  server_id = azurerm_postgresql_flexible_server.main.id
  value     = "256"
}
