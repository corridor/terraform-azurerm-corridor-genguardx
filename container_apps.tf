# Azure Container Apps Environment (required for Container Apps)
# When app_workload_profile is set (e.g. D4), workload profiles are added so the main app can use 16 Gi per replica.
# If the environment was created without workload profiles, adding them forces recreation (destroy + create) of the environment.
resource "azurerm_container_app_environment" "main" {
  name                       = "${replace(replace(var.resource_group_name, "-", ""), "_", "")}-env"
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
  name                = "${replace(replace(var.resource_group_name, "-", ""), "_", "")}-logs"
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
  name                         = "${replace(replace(var.resource_group_name, "-", ""), "_", "")}-app"
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

    container {
      name   = "corridor-app"
      image  = "${var.acr_login_server}/${var.image_name}:${var.image_version}"
      # Single-app mode: give corridor-app the full Consumption budget minus nginx sidecar.
      cpu    = 1.75
      memory = "3.5Gi"

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
        value = azurerm_redis_cache.main.hostname
      }

      env {
        name  = "CORRIDOR_REDIS_PORT"
        value = "6379"
      }

      env {
        name  = "CORRIDOR_API_URL"
        value = "https://${replace(replace(var.resource_group_name, "_", ""), "-", "")}-app.${azurerm_container_app_environment.main.default_domain}/corr-api"
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
        value = "redis://:${urlencode(azurerm_redis_cache.main.primary_access_key)}@${azurerm_redis_cache.main.hostname}:6379/0"
      }

      env {
        name  = "CORRIDOR_OUTPUT_DATA_LOCATION"
        value = "/opt/corridor/data/results/{}.parquet"
      }

      env {
        name  = "CORRIDOR_SENTRY_CONFIG__environment"
        value = var.client
      }

      env {
        name  = "TMPDIR"
        value = "/tmp"
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
    /*
    # Jupyter container (sidecar)
    container {
      name   = "corridor-jupyter"
      ...
    }
    */
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
        <<-EOT
        cat > /usr/share/nginx/html/502.html << 'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Application Loading</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            color: #fff;
        }
        .container {
            text-align: center;
            padding: 2rem;
            max-width: 600px;
        }
        .logo {
            font-size: 3rem;
            margin-bottom: 2rem;
            animation: pulse 2s ease-in-out infinite;
        }
        h1 {
            font-size: 2.5rem;
            margin-bottom: 1rem;
            font-weight: 600;
        }
        p {
            font-size: 1.2rem;
            margin-bottom: 1.5rem;
            opacity: 0.95;
            line-height: 1.6;
        }
        .spinner {
            width: 50px;
            height: 50px;
            border: 4px solid rgba(255, 255, 255, 0.3);
            border-top-color: #fff;
            border-radius: 50%;
            animation: spin 1s linear infinite;
            margin: 2rem auto;
        }
        .contact {
            margin-top: 2rem;
            padding: 1.5rem;
            background: rgba(255, 255, 255, 0.1);
            border-radius: 10px;
            backdrop-filter: blur(10px);
        }
        .contact a {
            color: #fff;
            text-decoration: none;
            font-weight: 600;
            border-bottom: 2px solid rgba(255, 255, 255, 0.5);
            transition: border-color 0.3s;
        }
        .contact a:hover {
            border-bottom-color: #fff;
        }
        @keyframes spin {
            to { transform: rotate(360deg); }
        }
        @keyframes pulse {
            0%, 100% { transform: scale(1); opacity: 1; }
            50% { transform: scale(1.05); opacity: 0.8; }
        }
    </style>
    <script>
        setTimeout(function() {
            location.reload();
        }, 10000);
    </script>
</head>
<body>
    <div class="container">
        <div class="logo">🚀</div>
        <h1>Application Loading</h1>
        <p>Your application is starting up. This typically takes 2-5 minutes.</p>
        <div class="spinner"></div>
        <p style="font-size: 1rem; opacity: 0.8;">The page will automatically refresh in a few seconds...</p>
        <div class="contact">
            <p style="font-size: 1rem; margin-bottom: 0.5rem;">If the issue persists after 5 minutes:</p>
            <p style="font-size: 1rem;">Contact support at <a href="mailto:support@corridorplatforms.com">support@corridorplatforms.com</a></p>
        </div>
    </div>
</body>
</html>
HTML
        cat > /etc/nginx/nginx.conf << 'NGX'
events { worker_connections 1024; }
http {
  upstream app { server 127.0.0.1:5002; }
  upstream jupyter { server 127.0.0.1:5003; }
  server {
    listen 80;
    client_max_body_size 0;
    proxy_connect_timeout 60s;
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
    proxy_request_buffering off;
    error_page 502 503 504 /502.html;
    location = /502.html {
      root /usr/share/nginx/html;
      internal;
    }
    location = /health { default_type text/plain; return 200 'ok'; }
    location /jupyter { proxy_pass http://jupyter; proxy_set_header Host $host; proxy_set_header X-Real-IP $remote_addr; proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto https; proxy_http_version 1.1; proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection "upgrade"; }
    location /corr-api { proxy_pass http://app; proxy_set_header Host $host; proxy_set_header X-Real-IP $remote_addr; proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto https; }
    location / { proxy_pass http://app; proxy_set_header Host $host; proxy_set_header X-Real-IP $remote_addr; proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto https; }
  }
}
NGX
        exec nginx -g 'daemon off;'
        EOT
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

# Azure Cache for Redis
resource "azurerm_redis_cache" "main" {
  name                = "${replace(replace(var.resource_group_name, "-", ""), "_", "")}-redis"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  capacity            = 0
  family              = "C"
  sku_name            = var.redis_sku_name
  enable_non_ssl_port = true
  minimum_tls_version = "1.2"

  redis_configuration {}

  tags = var.tags
}

# Worker Container App
resource "azurerm_container_app" "worker" {
  name                         = "${replace(replace(var.resource_group_name, "-", ""), "_", "")}-worker"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"

  registry {
    server               = var.acr_login_server
    username             = var.acr_sp_client_id != "" ? var.acr_sp_client_id : var.acr_admin_username
    password_secret_name = "acr-password"
  }

  secret {
    name  = "acr-password"
    value = var.acr_sp_client_id != "" ? var.acr_sp_client_secret : var.acr_admin_password
  }

  secret {
    name  = "redis-password"
    value = azurerm_redis_cache.main.primary_access_key
  }

  dynamic "secret" {
    for_each = var.secret_environment_variables
    content {
      name  = replace(secret.key, "-", "_")
      value = secret.value
    }
  }

  template {
    min_replicas = 0
    max_replicas = var.worker_max_replicas

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
        name  = "CORRIDOR_REDIS_HOST"
        value = azurerm_redis_cache.main.hostname
      }

      env {
        name  = "CORRIDOR_REDIS_PORT"
        value = "6379"
      }

      env {
        name  = "CORRIDOR_CELERY_BROKER_URL"
        value = "redis://:${urlencode(azurerm_redis_cache.main.primary_access_key)}@${azurerm_redis_cache.main.hostname}:6379/0"
      }

      env {
        name  = "CORRIDOR_API_URL"
        value = "https://${replace(replace(var.resource_group_name, "_", ""), "-", "")}-app.${azurerm_container_app_environment.main.default_domain}/corr-api"
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

      env {
        name  = "CORRIDOR_SENTRY_CONFIG__environment"
        value = var.client
      }

      env {
        name  = "TMPDIR"
        value = "/tmp"
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

      args = [
        "/bin/bash",
        "-c",
        "cd /opt/corridor && source venv/bin/activate && exec venv/bin/corridor-worker run"
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

    custom_scale_rule {
      name             = "celery-queue"
      custom_rule_type = "redis"
      metadata = {
        address    = "${azurerm_redis_cache.main.hostname}:6379"
        listName   = "celery"
        listLength = "1"
      }
      authentication {
        secret_name       = "redis-password"
        trigger_parameter = "password"
      }
    }
  }

  tags = var.tags
}
