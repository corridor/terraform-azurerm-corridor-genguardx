# Azure Container Apps Environment (required for Container Apps)
# When app_workload_profile is set (e.g. D4), workload profiles are added so the main app can use 16 Gi per replica.
# If the environment was created without workload profiles, adding them forces recreation (destroy + create) of the environment.
resource "azurerm_container_app_environment" "main" {
  name                       = "${replace(var.resource_group_name, "-", "")}-env"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  dynamic "workload_profile" {
    for_each = var.app_workload_profile != "" ? [1] : []
    content {
      name                  = "Consumption"
      workload_profile_type = "Consumption"
      minimum_count         = 0
      maximum_count         = 10
    }
  }

  dynamic "workload_profile" {
    for_each = var.app_workload_profile != "" ? [1] : []
    content {
      name                  = var.app_workload_profile
      workload_profile_type = var.app_workload_profile
      minimum_count         = 0
      maximum_count         = 3
    }
  }

  tags = var.tags
}

# Log Analytics Workspace (required for Container Apps Environment)
resource "azurerm_log_analytics_workspace" "main" {
  name                = "${replace(var.resource_group_name, "-", "")}-logs"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  
  tags = var.tags
}

# Storage for volume mounts (Azure Files)
resource "azurerm_container_app_environment_storage" "data" {
  name                         = "data"
  container_app_environment_id = azurerm_container_app_environment.main.id
  account_name                 = azurerm_storage_account.main.name
  share_name                   = azurerm_storage_share.data.name
  access_key                   = azurerm_storage_account.main.primary_access_key
  access_mode                  = "ReadWrite"
}

resource "azurerm_container_app_environment_storage" "uploads" {
  name                         = "uploads"
  container_app_environment_id = azurerm_container_app_environment.main.id
  account_name                 = azurerm_storage_account.main.name
  share_name                   = azurerm_storage_share.uploads.name
  access_key                   = azurerm_storage_account.main.primary_access_key
  access_mode                  = "ReadWrite"
}

resource "azurerm_container_app_environment_storage" "databases" {
  name                         = "databases"
  container_app_environment_id = azurerm_container_app_environment.main.id
  account_name                 = azurerm_storage_account.main.name
  share_name                   = azurerm_storage_share.databases.name
  access_key                   = azurerm_storage_account.main.primary_access_key
  access_mode                  = "ReadWrite"
}

resource "azurerm_container_app_environment_storage" "notebooks" {
  name                         = "notebooks"
  container_app_environment_id = azurerm_container_app_environment.main.id
  account_name                 = azurerm_storage_account.main.name
  share_name                   = azurerm_storage_share.notebooks.name
  access_key                   = azurerm_storage_account.main.primary_access_key
  access_mode                  = "ReadWrite"
}

resource "azurerm_container_app_environment_storage" "config" {
  name                         = "config"
  container_app_environment_id = azurerm_container_app_environment.main.id
  account_name                 = azurerm_storage_account.main.name
  share_name                   = azurerm_storage_share.config.name
  access_key                   = azurerm_storage_account.main.primary_access_key
  access_mode                  = "ReadWrite"
}

# Main Application Container App
resource "azurerm_container_app" "app" {
  name                         = "${replace(var.resource_group_name, "-", "")}-app"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"
  workload_profile_name        = var.app_workload_profile != "" ? var.app_workload_profile : null  # null = Consumption (4 Gi max); D4 = 16 Gi per replica

  registry {
    server   = var.acr_login_server
    username = var.acr_sp_client_id != "" ? var.acr_sp_client_id : var.acr_admin_username
    password_secret_name = "acr-password"
  }

  secret {
    name  = "acr-password"
    value = var.acr_sp_client_id != "" ? var.acr_sp_client_secret : var.acr_admin_password
  }

  # Add secret environment variables as secrets
  dynamic "secret" {
    for_each = var.secret_environment_variables
    content {
      name  = replace(secret.key, "-", "_")
      value = secret.value
    }
  }

  template {
    min_replicas     = 0  # Scale to zero when idle (app + worker scale together)
    max_replicas     = 1
    revision_suffix  = var.app_revision_suffix != "" ? var.app_revision_suffix : null  # Set to force new revision (restart); e.g. "restart-1" or timestamp()

    # Init container for database migrations (runs before main containers)
    init_container {
      name   = "db-migration"
      image  = "${var.acr_login_server}/${var.image_name}:${var.image_version}"
      cpu    = var.app_cpu
      memory = "${var.app_memory}Gi"

      env {
        name  = "CORRIDOR_ENV"
        value = var.environment
      }

      env {
        name  = "CORRIDOR_SQLALCHEMY_DATABASE_URI"
        value = var.database_connection_string != "" ? var.database_connection_string : "postgresql://${var.db_admin_username}:${urlencode(var.db_admin_password)}@${azurerm_postgresql_flexible_server.main.fqdn}:5432/${var.db_name}"
      }

      env {
        name  = "CORRIDOR_LICENSE_KEY"
        value = var.corridor_license_key
      }

      # Run database migration
      args = [
        "/bin/bash",
        "-c",
        "cd /opt/corridor && source venv/bin/activate && corridor-api db upgrade && echo 'Database migration completed'"
      ]
    }

    container {
      name   = "corridor-app"
      image  = "${var.acr_login_server}/${var.image_name}:${var.image_version}"
      cpu    = var.app_cpu
      memory = "${var.app_memory}Gi"

      env {
        name  = "CORRIDOR_ENV"
        value = var.environment
      }

      # Bind to all interfaces so nginx/worker in same replica can reach via localhost
      env {
        name  = "CORRIDOR_APP_HOST"
        value = "0.0.0.0"
      }

      env {
        name  = "CORRIDOR_APP_PROCESSES"
        value = "1"
      }

      env {
        name  = "CORRIDOR_REDIS_HOST"
        value = azurerm_container_app.redis.name
      }

      env {
        name  = "CORRIDOR_REDIS_PORT"
        value = "6379"
      }

      env {
        name  = "CORRIDOR_API_URL"
        value = "https://${replace(var.resource_group_name, "-", "")}-app.${azurerm_container_app_environment.main.default_domain}/corr-api"
      }

      env {
        name  = "CORRIDOR_SQLALCHEMY_DATABASE_URI"
        value = var.database_connection_string != "" ? var.database_connection_string : "postgresql://${var.db_admin_username}:${urlencode(var.db_admin_password)}@${azurerm_postgresql_flexible_server.main.fqdn}:5432/${var.db_name}"
      }

      env {
        name  = "CORRIDOR_LICENSE_KEY"
        value = var.corridor_license_key
      }

      env {
        name  = "CORRIDOR_CELERY_BROKER_URL"
        value = "redis://${azurerm_container_app.redis.name}:6379/0"
      }

      env {
        name  = "CORRIDOR_OUTPUT_DATA_LOCATION"
        value = "/opt/corridor/data/results/{}.parquet"
      }

      # Add secret environment variables
      dynamic "env" {
        for_each = var.secret_environment_variables
        content {
          name        = replace(env.key, "-", "_")
          secret_name = replace(env.key, "-", "_")
        }
      }

      volume_mounts {
        name = "data"
        path = "/opt/corridor/data"
      }

      volume_mounts {
        name = "uploads"
        path = "/opt/corridor/uploads"
      }

      volume_mounts {
        name = "databases"
        path = "/opt/corridor/databases"
      }

      volume_mounts {
        name = "config"
        path = "/opt/corridor/config"
      }

      # Liveness: if app stops responding on 5002, ACA restarts this container
      liveness_probe {
        transport             = "HTTP"
        port                  = 5002
        path                  = "/corr-api"
        initial_delay         = 60
        interval_seconds      = 30
        timeout               = 5
        failure_count_threshold = 3
      }

      # Startup command (migration already done by init container)
      args = [
        "/bin/bash",
        "-c",
        "cd /opt/corridor && source venv/bin/activate && exec venv/bin/corridor-app run"
      ]
    }

    # Worker container (sidecar - scales with app)
    container {
      name   = "corridor-worker"
      image  = "${var.acr_login_server}/${var.image_name}:${var.image_version}"
      cpu    = var.worker_cpu
      memory = "${var.worker_memory}Gi"

      env {
        name  = "CORRIDOR_ENV"
        value = var.environment
      }

      env {
        name  = "CORRIDOR_APP_HOST"
        value = "0.0.0.0"
      }

      env {
        name  = "CORRIDOR_APP_PROCESSES"
        value = "1"
      }

      env {
        name  = "CORRIDOR_REDIS_HOST"
        value = azurerm_container_app.redis.name
      }

      env {
        name  = "CORRIDOR_REDIS_PORT"
        value = "6379"
      }

      env {
        name  = "CORRIDOR_CELERY_BROKER_URL"
        value = "redis://${azurerm_container_app.redis.name}:6379/0"
      }

      env {
        name  = "CORRIDOR_API_URL"
        value = "https://${replace(var.resource_group_name, "-", "")}-app.${azurerm_container_app_environment.main.default_domain}/corr-api"
      }

      env {
        name  = "CORRIDOR_SQLALCHEMY_DATABASE_URI"
        value = var.database_connection_string != "" ? var.database_connection_string : "postgresql://${var.db_admin_username}:${urlencode(var.db_admin_password)}@${azurerm_postgresql_flexible_server.main.fqdn}:5432/${var.db_name}"
      }

      env {
        name  = "CORRIDOR_LICENSE_KEY"
        value = var.corridor_license_key
      }

      env {
        name  = "CORRIDOR_OUTPUT_DATA_LOCATION"
        value = "/opt/corridor/data/results/{}.parquet"
      }

      dynamic "env" {
        for_each = var.secret_environment_variables
        content {
          name        = replace(env.key, "-", "_")
          secret_name = replace(env.key, "-", "_")
        }
      }

      volume_mounts {
        name = "data"
        path = "/opt/corridor/data"
      }

      volume_mounts {
        name = "uploads"
        path = "/opt/corridor/uploads"
      }

      # Worker startup: wait for corridor-app on 127.0.0.1:5002 (shared localhost in same replica) then run
      args = [
        "/bin/bash",
        "-c",
        "cd /opt/corridor && source venv/bin/activate && for i in $(seq 1 90); do python3 -c \"import socket; s=socket.create_connection(('127.0.0.1',5002),timeout=2); s.close()\" 2>/dev/null && break; sleep 2; done && exec venv/bin/corridor-worker run"
      ]
    }

    # Jupyter container (sidecar - scales with app)
    container {
      name   = "corridor-jupyter"
      image  = "${var.acr_login_server}/${var.image_name}:${var.image_version}"
      cpu    = var.jupyter_cpu
      memory = "${var.jupyter_memory}Gi"

      env {
        name  = "CORRIDOR_ENV"
        value = var.environment
      }

      env {
        name  = "CORRIDOR_APP_HOST"
        value = "0.0.0.0"
      }

      env {
        name  = "CORRIDOR_APP_PROCESSES"
        value = "1"
      }

      env {
        name  = "CORRIDOR_REDIS_HOST"
        value = azurerm_container_app.redis.name
      }

      env {
        name  = "CORRIDOR_REDIS_PORT"
        value = "6379"
      }

      env {
        name  = "CORRIDOR_CELERY_BROKER_URL"
        value = "redis://${azurerm_container_app.redis.name}:6379/0"
      }

      env {
        name  = "CORRIDOR_API_URL"
        value = "https://${replace(var.resource_group_name, "-", "")}-app.${azurerm_container_app_environment.main.default_domain}/corr-api"
      }

      env {
        name  = "CORRIDOR_SQLALCHEMY_DATABASE_URI"
        value = var.database_connection_string != "" ? var.database_connection_string : "postgresql://${var.db_admin_username}:${urlencode(var.db_admin_password)}@${azurerm_postgresql_flexible_server.main.fqdn}:5432/${var.db_name}"
      }

      env {
        name  = "CORRIDOR_LICENSE_KEY"
        value = var.corridor_license_key
      }

      env {
        name  = "CORRIDOR_OUTPUT_DATA_LOCATION"
        value = "/opt/corridor/data/results/{}.parquet"
      }

      dynamic "env" {
        for_each = var.secret_environment_variables
        content {
          name        = replace(env.key, "-", "_")
          secret_name = replace(env.key, "-", "_")
        }
      }

      volume_mounts {
        name = "notebooks"
        path = "/opt/corridor/notebooks"
      }

      volume_mounts {
        name = "config"
        path = "/opt/corridor/config"
      }

      # Jupyter startup command
      args = [
        "/bin/bash",
        "-c",
        "cd /opt/corridor && source venv/bin/activate && exec venv/bin/corridor-jupyter run"
      ]
    }

    # Nginx container (sidecar - reverse proxy/routing)
    container {
      name   = "nginx"
      image  = "nginx:1.25-alpine"
      cpu    = 0.25
      memory = "0.5Gi"

      # Nginx proxies to:
      # - / -> localhost:5002 (corridor-app)
      # - /jupyter -> localhost:5003 (corridor-jupyter)
      # - /corr-api -> localhost:5002/corr-api (corridor-app)
      args = [
        "/bin/sh",
        "-c",
        "cat > /etc/nginx/nginx.conf << 'NGX'\nevents { worker_connections 1024; }\nhttp {\n  upstream app { server 127.0.0.1:5002; }\n  upstream jupyter { server 127.0.0.1:5003; }\n  server {\n    listen 80;\n    client_max_body_size 0;\n    proxy_connect_timeout 60s;\n    proxy_read_timeout 3600s;\n    proxy_send_timeout 3600s;\n    proxy_request_buffering off;\n    location = /health { default_type text/plain; return 200 'ok'; }\n    location /jupyter { proxy_pass http://jupyter; proxy_set_header Host $host; proxy_set_header X-Real-IP $remote_addr; proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto https; proxy_http_version 1.1; proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection \"upgrade\"; }\n    location /corr-api { proxy_pass http://app; proxy_set_header Host $host; proxy_set_header X-Real-IP $remote_addr; proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto https; }\n    location / { proxy_pass http://app; proxy_set_header Host $host; proxy_set_header X-Real-IP $remote_addr; proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto https; }\n  }\n}\nNGX\nexec nginx -g 'daemon off;'"
      ]
    }

    volume {
      name         = "data"
      storage_type = "AzureFile"
      storage_name = azurerm_container_app_environment_storage.data.name
    }

    volume {
      name         = "uploads"
      storage_type = "AzureFile"
      storage_name = azurerm_container_app_environment_storage.uploads.name
    }

    volume {
      name         = "databases"
      storage_type = "AzureFile"
      storage_name = azurerm_container_app_environment_storage.databases.name
    }

    volume {
      name         = "config"
      storage_type = "AzureFile"
      storage_name = azurerm_container_app_environment_storage.config.name
    }

    volume {
      name         = "notebooks"
      storage_type = "AzureFile"
      storage_name = azurerm_container_app_environment_storage.notebooks.name
    }
  }

        ingress {
          external_enabled = true
          target_port      = 80  # Nginx listens on port 80
          transport        = "http"
          allow_insecure_connections = false

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  tags = var.tags
}

# Worker, Jupyter, and Nginx are now sidecar containers in the app Container App above
# This ensures all containers scale together automatically

# Redis Container App (internal only, no ingress)
resource "azurerm_container_app" "redis" {
  name                         = "${replace(var.resource_group_name, "-", "")}-redis"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"

  template {
    min_replicas = 1  # Keep Redis running (small cost)
    max_replicas = 1

    container {
      name   = "redis"
      image  = "redis:6.2-alpine"
      cpu    = var.redis_cpu
      memory = "${var.redis_memory}Gi"

      args = ["redis-server", "--databases", "32"]
    }
  }

  # Internal ingress for service discovery (Redis is internal only)
  ingress {
    external_enabled = false
    target_port      = 6379
    transport        = "tcp"

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  tags = var.tags
}
