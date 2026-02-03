output "container_app_environment_name" {
  description = "Name of the Container App Environment"
  value       = azurerm_container_app_environment.main.name
}

output "app_url" {
  description = "URL to access the application (HTTPS, auto-scales to zero)"
  value       = "https://${azurerm_container_app.app.latest_revision_fqdn}"
}

output "jupyter_url" {
  description = "URL to access JupyterHub via nginx (HTTPS, auto-scales to zero)"
  value       = "https://${azurerm_container_app.app.latest_revision_fqdn}/jupyter"
}

output "app_fqdn" {
  description = "FQDN of the main application (includes app, worker, jupyter, nginx)"
  value       = azurerm_container_app.app.latest_revision_fqdn
}

output "jupyter_fqdn" {
  description = "FQDN of JupyterHub (same as app, accessed via /jupyter path)"
  value       = azurerm_container_app.app.latest_revision_fqdn
}

output "resource_group_name" {
  description = "Resource group name"
  value       = azurerm_resource_group.main.name
}

output "storage_account_name" {
  description = "Storage account name"
  value       = azurerm_storage_account.main.name
}

output "database_fqdn" {
  description = "PostgreSQL server FQDN"
  value       = azurerm_postgresql_flexible_server.main.fqdn
}

output "database_name" {
  description = "PostgreSQL database name"
  value       = azurerm_postgresql_flexible_server_database.main.name
}

output "database_connection_string" {
  description = "PostgreSQL connection string"
  value       = "postgresql://${var.db_admin_username}:${var.db_admin_password}@${azurerm_postgresql_flexible_server.main.fqdn}:5432/${var.db_name}"
  sensitive   = true
}
