# =============================================================================
# Phase 3 · WAF on Application Gateway  (the deck's core lab = lab/azure/main.tf)
#
# Builds an L7 load balancer (Application Gateway WAF_v2) with a WAF policy in
# front of a container app that has NO public IP. Students attack it in
# Detection mode, read the logs, then flip to Prevention and attack again.
# =============================================================================

terraform {
  required_version = ">= 1.5"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "azurerm" {
  features {}
  # ARM_SUBSCRIPTION_ID is read from the environment. See the lab README.
}

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------
variable "prefix" {
  type        = string
  description = "Unique per-team prefix, e.g. team1, team2."
  default     = "team1"
  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,10}$", var.prefix))
    error_message = "prefix must be 2-11 chars, lowercase letters/digits, starting with a letter."
  }
}

variable "waf_mode" {
  type        = string
  description = "Detection = log only. Prevention = log and block (403)."
  default     = "Detection"
  validation {
    condition     = contains(["Detection", "Prevention"], var.waf_mode)
    error_message = "waf_mode must be Detection or Prevention."
  }
}

variable "location" {
  type        = string
  description = "Azure region."
  default     = "westeurope"
}

locals {
  name = var.prefix
  tags = {
    lab   = "waf-edge-to-app"
    phase = "2-waf-appgw"
    team  = var.prefix
  }
}

# ---------------------------------------------------------------------------
# Resource group + network: one subnet for the gateway, one for the app
# ---------------------------------------------------------------------------
resource "azurerm_resource_group" "main" {
  name     = "${local.name}-waf-rg"
  location = var.location
  tags     = local.tags
}

resource "azurerm_virtual_network" "main" {
  name                = "${local.name}-vnet"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  address_space       = ["10.10.0.0/16"]
  tags                = local.tags
}

resource "azurerm_subnet" "appgw" {
  name                 = "appgw-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.10.1.0/24"] # the gateway lives here
}

resource "azurerm_subnet" "app" {
  name                 = "app-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.10.2.0/24"] # the app lives here

  delegation {
    name = "aci"
    service_delegation {
      name    = "Microsoft.ContainerInstance/containerGroups"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

# ---------------------------------------------------------------------------
# The app: a private container, no public IP.
# This is the most important idea in the lab. If the app had its own public IP,
# an attacker would simply skip the WAF.
# ---------------------------------------------------------------------------
resource "azurerm_container_group" "app" {
  name                = "${local.name}-app"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  ip_address_type     = "Private" # <-- no public IP
  subnet_ids          = [azurerm_subnet.app.id]

  container {
    name   = "hello"
    image  = "mcr.microsoft.com/azuredocs/aci-helloworld:latest"
    cpu    = "0.5"
    memory = "1.0"
    ports {
      port     = 80
      protocol = "TCP"
    }
  }

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Public IP for the gateway's frontend (the only public door).
# A DNS label gives it a free, resolvable hostname:
#   <prefix>-waf-<suffix>.<region>.cloudapp.azure.com
# ---------------------------------------------------------------------------
resource "random_string" "dns" {
  length  = 4
  special = false
  upper   = false
}

resource "azurerm_public_ip" "gw" {
  name                = "${local.name}-gw-pip"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = "${var.prefix}-waf-${random_string.dns.result}"
  tags                = local.tags
}

# ---------------------------------------------------------------------------
# WAF policy: OWASP managed rules + two custom rules.
#   - mode switches Detection <-> Prevention via var.waf_mode
#   - BlockScanners   : drops known scanner tools by User-Agent
#   - RateLimitPerIp  : 100 requests / minute / client IP
# Students add their own custom rules here during the challenge.
# ---------------------------------------------------------------------------
resource "azurerm_web_application_firewall_policy" "waf" {
  name                = "${local.name}-waf-policy"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  policy_settings {
    enabled            = true
    mode               = var.waf_mode # Detection = log only, Prevention = log + block
    request_body_check = true
  }

  managed_rules {
    managed_rule_set {
      type    = "OWASP" # SQL injection, XSS, path traversal, ...
      version = "3.2"
    }
  }

  custom_rules {
    name      = "BlockScanners"
    priority  = 1
    rule_type = "MatchRule"
    action    = "Block"
    match_conditions {
      match_variables {
        variable_name = "RequestHeaders"
        selector      = "User-Agent"
      }
      operator           = "Contains"
      negation_condition = false
      match_values       = ["sqlmap", "nikto", "nmap", "dirbuster"]
    }
  }

  custom_rules {
    name                 = "RateLimitPerIp"
    priority             = 2
    rule_type            = "RateLimitRule"
    action               = "Block"
    rate_limit_duration  = "OneMin"
    rate_limit_threshold = 100
    group_rate_limit_by  = "ClientAddr"
    match_conditions {
      match_variables {
        variable_name = "RemoteAddr"
      }
      operator           = "IPMatch"
      negation_condition = false
      match_values       = ["0.0.0.0/0"] # applies to every client
    }
  }

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Application Gateway WAF_v2: the L7 load balancer that hosts the WAF.
# Frontend = public IP on :80. Backend = the app's PRIVATE IP.
# ---------------------------------------------------------------------------
locals {
  gw_name       = "${local.name}-appgw"
  fe_ip_name    = "public-frontend"
  fe_port_name  = "port80"
  be_pool_name  = "app-backend-pool"
  be_http_name  = "app-http-settings"
  listener_name = "http-listener"
  routing_name  = "route-to-app"
  ipcfg_name    = "appgw-ipcfg"
}

resource "azurerm_application_gateway" "gw" {
  name                = local.gw_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  firewall_policy_id  = azurerm_web_application_firewall_policy.waf.id

  sku {
    name     = "WAF_v2"
    tier     = "WAF_v2"
    capacity = 1
  }

  gateway_ip_configuration {
    name      = local.ipcfg_name
    subnet_id = azurerm_subnet.appgw.id
  }

  frontend_port {
    name = local.fe_port_name
    port = 80
  }

  frontend_ip_configuration {
    name                 = local.fe_ip_name
    public_ip_address_id = azurerm_public_ip.gw.id
  }

  backend_address_pool {
    name         = local.be_pool_name
    ip_addresses = [azurerm_container_group.app.ip_address] # the private app
  }

  backend_http_settings {
    name                  = local.be_http_name
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 30
  }

  http_listener {
    name                           = local.listener_name
    frontend_ip_configuration_name = local.fe_ip_name
    frontend_port_name             = local.fe_port_name
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = local.routing_name
    rule_type                  = "Basic"
    priority                   = 100 # required on WAF_v2 / v2 SKUs
    http_listener_name         = local.listener_name
    backend_address_pool_name  = local.be_pool_name
    backend_http_settings_name = local.be_http_name
  }

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Logs: ship every WAF decision to Log Analytics.
# No logs, no defense — a WAF you cannot see is a WAF you cannot tune.
# ---------------------------------------------------------------------------
resource "azurerm_log_analytics_workspace" "lab" {
  name                = "${local.name}-logs"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

resource "azurerm_monitor_diagnostic_setting" "waf_logs" {
  name                       = "waf-diagnostics"
  target_resource_id         = azurerm_application_gateway.gw.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.lab.id

  enabled_log {
    category = "ApplicationGatewayFirewallLog"
  }
  enabled_log {
    category = "ApplicationGatewayAccessLog"
  }
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------
output "app_url" {
  description = "Public URL of the app, through the gateway (DNS hostname)."
  value       = "http://${azurerm_public_ip.gw.fqdn}"
}

output "app_fqdn" {
  description = "Resolvable DNS name of the gateway."
  value       = azurerm_public_ip.gw.fqdn
}

output "app_url_ip" {
  description = "Same thing by raw IP."
  value       = "http://${azurerm_public_ip.gw.ip_address}"
}

output "gateway_public_ip" {
  value = azurerm_public_ip.gw.ip_address
}

output "app_private_ip" {
  description = "The app's private IP — unreachable from the internet."
  value       = azurerm_container_group.app.ip_address
}

output "log_analytics_workspace" {
  value = azurerm_log_analytics_workspace.lab.name
}

output "waf_mode" {
  value = var.waf_mode
}
