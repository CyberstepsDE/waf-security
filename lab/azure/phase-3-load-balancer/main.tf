# =============================================================================
# Phase 4 · Load Balancer — L4  (distribution)
#
# A load balancer spreads traffic across healthy servers so no single box is
# overwhelmed, and skips any that fail. Two flavors:
#   L4 (this phase) routes by IP + port. Fast and simple, blind to the payload.
#   L7 (Phase 3's App Gateway) understands HTTP, routes by path, hosts the WAF.
#
# Here: an Azure Standard Load Balancer spreading :80 across TWO private
# container apps, with a health probe that drops any backend that stops answering.
# =============================================================================

terraform {
  required_version = ">= 1.5"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "prefix" {
  type        = string
  description = "Unique per-team prefix, e.g. team1."
  default     = "team1"
  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,10}$", var.prefix))
    error_message = "prefix must be 2-11 chars, lowercase letters/digits, starting with a letter."
  }
}

variable "location" {
  type        = string
  default     = "westeurope"
  description = "Azure region."
}

variable "backend_count" {
  type        = number
  default     = 2
  description = "How many app instances to spread traffic across."
}

locals {
  name = var.prefix
  tags = {
    lab   = "waf-edge-to-app"
    phase = "3-load-balancer"
    team  = var.prefix
  }
}

resource "azurerm_resource_group" "main" {
  name     = "${local.name}-lb-rg"
  location = var.location
  tags     = local.tags
}

resource "azurerm_virtual_network" "main" {
  name                = "${local.name}-lb-vnet"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  address_space       = ["10.30.0.0/16"]
  tags                = local.tags
}

resource "azurerm_subnet" "app" {
  name                 = "app-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.30.1.0/24"]

  delegation {
    name = "aci"
    service_delegation {
      name    = "Microsoft.ContainerInstance/containerGroups"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

# ---- The backends: N private container apps ----
resource "azurerm_container_group" "app" {
  count               = var.backend_count
  name                = "${local.name}-app-${count.index}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  ip_address_type     = "Private"
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

# ---- The load balancer: one public door, N backends ----
resource "azurerm_public_ip" "lb" {
  name                = "${local.name}-lb-pip"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_lb" "main" {
  name                = "${local.name}-lb"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "public"
    public_ip_address_id = azurerm_public_ip.lb.id
  }

  tags = local.tags
}

resource "azurerm_lb_backend_address_pool" "main" {
  name            = "app-pool"
  loadbalancer_id = azurerm_lb.main.id
}

# IP-based backend pool: add each container's private IP.
resource "azurerm_lb_backend_address_pool_address" "app" {
  count                   = var.backend_count
  name                    = "app-${count.index}"
  backend_address_pool_id = azurerm_lb_backend_address_pool.main.id
  virtual_network_id      = azurerm_virtual_network.main.id
  ip_address              = azurerm_container_group.app[count.index].ip_address
}

# Health probe: drop any backend that stops answering on :80.
resource "azurerm_lb_probe" "http" {
  name            = "http-probe"
  loadbalancer_id = azurerm_lb.main.id
  protocol        = "Http"
  port            = 80
  request_path    = "/"
}

# L4 rule: forward :80 across the pool. Routes by IP + port — no idea what HTTP says.
resource "azurerm_lb_rule" "http" {
  name                           = "http"
  loadbalancer_id                = azurerm_lb.main.id
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "public"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.main.id]
  probe_id                       = azurerm_lb_probe.http.id
}

output "lb_url" {
  value = "http://${azurerm_public_ip.lb.ip_address}"
}

output "backend_private_ips" {
  value = azurerm_container_group.app[*].ip_address
}
