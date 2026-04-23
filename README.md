# Terraform Module: Corridor GenGuardX on Azure (Container Apps)

Deploy Corridor GenGuardX (app, worker, Jupyter, Redis, PostgreSQL, Nginx) on **Azure Container Apps** with scale-to-zero, Azure Files, and optional Dedicated workload profiles.

## Quick Start

**New to this module?** See [QUICKSTART.md](QUICKSTART.md) for step-by-step instructions including:
- Installing prerequisites (Terraform, Azure CLI, Docker)
- Getting credentials from Corridor support
- Creating Azure resources
- Migrating images from AWS ECR to Azure ACR
- Complete deployment walkthrough

## Usage

**As a module** (from Terraform Registry):

```hcl
module "ggx" {
  source  = "corridor/ggx/azure"
  version = "~> 1.0"

  resource_group_name  = "my-genguardx-rg"
  location             = "eastus"
  acr_login_server    = "myregistry.azurecr.io"
  acr_sp_client_id     = "..."
  acr_sp_client_secret = "..."
  image_name           = "genguardx"   # container image (repository) in ACR
  image_version        = "latest"      # image tag (e.g. date-20260123-sha-abc123)
  corridor_license_key = "..."
  db_admin_password    = "..."

  # Optional: D4 workload profile for 16 Gi per replica
  app_workload_profile = ""  # Consumption (2 vCPU, 4 Gi) or "D4"
}
```

**Standalone** (clone this repo):

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init
terraform plan
terraform apply
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.0 |
| azurerm | ~> 3.0 |

## Providers

| Name | Version |
|------|---------|
| azurerm | ~> 3.0 |

## Inputs

See [variables.tf](variables.tf). Main inputs:

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| resource_group_name | Name of the resource group | string | "genguardx-rg" | no |
| location | Azure region | string | "eastus" | no |
| acr_login_server | ACR login server (get from Corridor support) | string | n/a | yes |
| acr_sp_client_id | Service Principal Client ID for ACR (get from Corridor support) | string | "" | yes* |
| acr_sp_client_secret | Service Principal Client Secret for ACR (get from Corridor support) | string | "" | yes* |
| image_name | Container image name in ACR | string | "genguardx" | no |
| image_version | Container image tag (get from Corridor support) | string | "latest" | no |
| corridor_license_key | License key for corridor-api (get from Corridor support) | string | "" | yes |
| app_workload_profile | "" = Consumption (2 vCPU, 4 Gi); "D4" = Dedicated 16 Gi | string | "" | no |
| db_admin_username | PostgreSQL admin username | string | "postgres" | no |
| db_admin_password | PostgreSQL admin password | string | n/a | yes |
| db_name | PostgreSQL database name | string | "genguardx" | no |
| db_zone | Optional PostgreSQL AZ override ("1","2","3"); null lets Azure choose | string | null | no |
| tags | Tags to apply to resources | map(string) | See variables.tf | no |


(Full list and descriptions are in [variables.tf](variables.tf).)

## Outputs

| Name | Description |
|------|-------------|
| app_url | HTTPS URL of the application |
| jupyter_url | HTTPS URL for JupyterHub (/jupyter) |
| app_fqdn | FQDN of the main Container App |
| jupyter_fqdn | FQDN of JupyterHub (same as app, via /jupyter) |
| resource_group_name | Resource group name |
| container_app_environment_name | Container App Environment name |
| storage_account_name | Storage account name |
| database_fqdn | PostgreSQL server FQDN |
| database_name | PostgreSQL database name |
| database_connection_string | PostgreSQL connection string (sensitive) |

(Full list in [outputs.tf](outputs.tf).)

## Backend (state)

This module does **not** configure a backend. Configure the backend in the root module that uses this module, or when using this repo standalone uncomment the `backend "azurerm"` block in [versions.tf](versions.tf) and set your Azure Storage details.
