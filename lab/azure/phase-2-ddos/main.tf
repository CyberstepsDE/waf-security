# =============================================================================
# Phase 2 · DDoS Protection  (volume)
#
# A DDoS attack is not clever, it is just huge: thousands of machines send junk
# traffic until real users cannot get through. Azure DDoS Network Protection
# absorbs and scrubs the flood on infrastructure far larger than yours, upstream
# of your network, and passes only clean traffic through.
#
# ⚠️  COST WARNING: a DDoS Network Protection PLAN is billed at a flat monthly
#     rate (~US$2,900/month) the moment it exists — it is NOT hourly and NOT
#     free-tier. This phase exists to show the one line that turns it on.
#     Deploy it, read the output, then `terraform destroy` immediately.
# =============================================================================

terraform {
  required_version = ">= 1.5"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
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

# Safety switch: the plan is expensive, so you must opt in explicitly.
variable "i_understand_ddos_billing" {
  type        = bool
  default     = false
  description = "Set true to confirm you accept the ~US$2,900/month plan charge."
  validation {
    condition     = var.i_understand_ddos_billing == true
    error_message = "Refusing to create a DDoS plan. Re-run with -var=\"i_understand_ddos_billing=true\" once you understand the monthly charge."
  }
}

locals {
  name = var.prefix
  tags = {
    lab   = "waf-edge-to-app"
    phase = "2-ddos"
    team  = var.prefix
  }
}

resource "azurerm_resource_group" "main" {
  name     = "${local.name}-ddos-rg"
  location = var.location
  tags     = local.tags
}

# ---- The DDoS protection plan (the expensive bit) ----
resource "azurerm_network_ddos_protection_plan" "main" {
  name                = "${local.name}-ddos-plan"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = local.tags
}

# ---- A VNet protected by the plan. The whole feature is these three lines. ----
resource "azurerm_virtual_network" "main" {
  name                = "${local.name}-protected-vnet"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  address_space       = ["10.20.0.0/16"]

  ddos_protection_plan {
    id     = azurerm_network_ddos_protection_plan.main.id
    enable = true # <-- the whole feature
  }

  tags = local.tags
}

output "ddos_plan_id" {
  value = azurerm_network_ddos_protection_plan.main.id
}

output "protected_vnet" {
  value = azurerm_virtual_network.main.name
}

output "reminder" {
  value = "DESTROY THIS NOW. The DDoS plan bills ~US$2,900/month while it exists."
}
