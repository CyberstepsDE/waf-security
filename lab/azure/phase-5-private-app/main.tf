# =============================================================================
# Phase 6 · The app  (the thing being protected)
#
# The request's final destination — your code. In this lab it's a container with
# NO public IP, living in a private subnet. That one property is what makes every
# layer in front of it worth building: the only way to reach the app is through
# a gateway you control. If the app had its own public IP, an attacker would just
# skip the WAF and go straight there.
#
# Deploy this alone and prove it: there is nothing on the internet to curl.
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

locals {
  name = var.prefix
  tags = {
    lab   = "waf-edge-to-app"
    phase = "5-private-app"
    team  = var.prefix
  }
}

resource "azurerm_resource_group" "main" {
  name     = "${local.name}-app-rg"
  location = var.location
  tags     = local.tags
}

resource "azurerm_virtual_network" "main" {
  name                = "${local.name}-app-vnet"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  address_space       = ["10.60.0.0/16"]
  tags                = local.tags
}

resource "azurerm_subnet" "app" {
  name                 = "app-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.60.1.0/24"]

  delegation {
    name = "aci"
    service_delegation {
      name    = "Microsoft.ContainerInstance/containerGroups"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

# The app: private IP only. No public endpoint anywhere.
resource "azurerm_container_group" "app" {
  name                = "${local.name}-app"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  ip_address_type     = "Private" # <-- the whole point
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

output "app_private_ip" {
  description = "Reachable only from inside the VNet — nothing to find from the internet."
  value       = azurerm_container_group.app.ip_address
}
