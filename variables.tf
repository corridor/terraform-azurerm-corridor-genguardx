variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "genguardx-rg"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "container_group_name" {
  description = "Name of the container group"
  type        = string
  default     = "genguardx-group"
}

variable "dns_name_label" {
  description = "DNS label (not used with Container Apps - FQDN is auto-generated, kept for compatibility)"
  type        = string
  default     = ""
}

variable "acr_login_server" {
  description = "Azure Container Registry login server (e.g., ggxsandbox.azurecr.io)"
  type        = string
}

# Service Principal credentials (recommended for cross-account access)
variable "acr_sp_client_id" {
  description = "Service Principal Client ID for ACR pull access (recommended)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "acr_sp_client_secret" {
  description = "Service Principal Client Secret for ACR pull access (recommended)"
  type        = string
  sensitive   = true
  default     = ""
}

# Admin credentials (fallback, not recommended for production)
variable "acr_admin_username" {
  description = "ACR admin username (only if not using service principal)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "acr_admin_password" {
  description = "ACR admin password (only if not using service principal)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "image_name" {
  description = "Container image name (repository) in ACR (e.g., genguardx)"
  type        = string
  default     = "genguardx"
}

variable "image_version" {
  description = "Container image version tag (e.g., date-20260123-sha-c5cd8eb)"
  type        = string
  default     = "latest"
}

variable "environment" {
  description = "Environment name (development, staging, production)"
  type        = string
  default     = "production"
}

variable "app_revision_suffix" {
  description = "Set to force a new Container App revision (restart). Use a new value each time you want to restart (e.g. restart-1, restart-2, or a timestamp). Leave empty to skip."
  type        = string
  default     = ""
}

# Workload profile for the main app: empty = Consumption (pay-per-use, max 2 vCPU + 4 Gi per replica); D4 = Dedicated (16 Gi, reserved billing).
variable "app_workload_profile" {
  description = "Workload profile for the main Container App. Leave empty for Consumption (max 2 vCPU + 4 Gi per replica). Set to D4 for Dedicated 16 Gi. Options: \"\", \"D4\", \"D8\", \"D16\", \"D32\"."
  type        = string
  default     = ""
}

variable "corridor_license_key" {
  description = "License key for corridor-api (required for API to start). Passed as env var CORRIDOR_LICENSE_KEY."
  type        = string
  default     = ""
  sensitive   = true
}

variable "database_connection_string" {
  description = "PostgreSQL connection string (optional - will be auto-generated if database is created)"
  type        = string
  sensitive   = true
  default     = ""
}

# Database creation variables
variable "db_admin_username" {
  description = "PostgreSQL admin username"
  type        = string
  default     = "postgres"
}

variable "db_admin_password" {
  description = "PostgreSQL admin password"
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "genguardx"
}

variable "db_sku_name" {
  description = "PostgreSQL SKU"
  type        = string
  default     = "B_Standard_B1ms"
}

variable "db_storage_mb" {
  description = "PostgreSQL storage in MB"
  type        = number
  default     = 32768  # 32GB
}

variable "secret_environment_variables" {
  description = "Secret environment variables"
  type        = map(string)
  default     = {}
  sensitive   = true
}

# Resource sizing
variable "app_cpu" {
  description = "CPU cores for corridor-app"
  type        = number
  default     = 2
}

variable "app_memory" {
  description = "Memory (GB) for corridor-app"
  type        = number
  default     = 6
}

variable "worker_cpu" {
  description = "CPU cores for corridor-worker"
  type        = number
  default     = 2
}

variable "worker_memory" {
  description = "Memory (GB) for corridor-worker"
  type        = number
  default     = 8
}

variable "jupyter_cpu" {
  description = "CPU cores for corridor-jupyter"
  type        = number
  default     = 2
}

variable "jupyter_memory" {
  description = "Memory (GB) for corridor-jupyter"
  type        = number
  default     = 8
}

variable "redis_cpu" {
  description = "CPU cores for Redis"
  type        = number
  default     = 0.5
}

variable "redis_memory" {
  description = "Memory (GB) for Redis"
  type        = number
  default     = 1
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
