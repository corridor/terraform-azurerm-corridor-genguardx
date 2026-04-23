# Quick Start Guide

Deploy Corridor GenGuardX on Azure in 5 steps.

## Prerequisites

Install Terraform and Azure CLI:

```bash
# macOS
brew install terraform azure-cli

# Linux
# Terraform: https://developer.hashicorp.com/terraform/install
# Azure CLI: curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

```

## Step 1: Get Credentials from Corridor

Contact **admin@genguardx.ai** for:
- `acr_login_server`
- `acr_sp_client_id` and `acr_sp_client_secret`
- `image_version` (e.g., `date-20260316-sha-7cf949f`)
- `corridor_license_key`

## Step 2: Login to Azure

```bash
az login
az account set --subscription "your-subscription-name"
```

## Step 3: Create Resource Group

```bash
az group create --name my-genguardx-rg --location eastus2
```

*Or use an existing one if you don't have create permissions.*

## Step 4: Create `main.tf`

```hcl
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

module "ggx" {
  source  = "corridor/ggx/azure"
  version = "~> 1.0"

  resource_group_name   = "my-genguardx-rg"
  create_resource_group = false
  location              = "eastus2"

  # From Corridor support
  acr_login_server     = "ggxsandbox.azurecr.io"
  acr_sp_client_id     = "your-client-id"
  acr_sp_client_secret = "your-client-secret"
  image_version        = "date-20260316-sha-7cf949f"
  corridor_license_key = "your-license-key"

  # Database password (choose your own)
  db_admin_password = "YourSecurePassword123!"

  client = "my-company"
}

output "app_url" {
  value = module.ggx.app_url
}
```

## Step 5: Deploy

```bash
terraform init
terraform apply
```

Type `yes` when prompted. Deployment takes ~25 minutes.

## Access Your App

```bash
terraform output app_url
```

Open the URL. First load may show a loading screen for 2-5 minutes.

---

## Optional: Store State in Azure

```bash
# Create storage
STORAGE_NAME="tfstate$RANDOM"
az storage account create --name $STORAGE_NAME --resource-group my-genguardx-rg --location eastus2 --sku Standard_LRS
az storage container create --name tfstate --account-name $STORAGE_NAME

echo "Add this to your main.tf terraform block:"
echo "  backend \"azurerm\" {"
echo "    resource_group_name  = \"my-genguardx-rg\""
echo "    storage_account_name = \"$STORAGE_NAME\""
echo "    container_name       = \"tfstate\""
echo "    key                  = \"genguardx.terraform.tfstate\""
echo "  }"
```

**Need help?** admin@genguardx.ai
