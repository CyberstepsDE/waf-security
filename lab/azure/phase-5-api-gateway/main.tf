# =============================================================================
# Phase 5 · API Gateway  (the front desk)
#
# Last stop before your code. The API gateway is the front desk for your APIs:
#   who are you  -> validates tokens / keys (authentication)
#   how much     -> rate limits and quotas (stops credential stuffing, scraping)
#   one door     -> a single watched entry point, with logs and metrics
#
# Here: Azure API Management on the Consumption tier (serverless, fast, cheap),
# fronting a public echo backend, with a subscription key required and a
# rate-limit policy of 5 calls/minute so you can trip it by hand.
# =============================================================================

terraform {
  required_version = ">= 1.5"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
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

variable "publisher_name" {
  type        = string
  default     = "WAF Edge-to-App Lab"
  description = "APIM publisher display name."
}

variable "publisher_email" {
  type        = string
  default     = "lab@example.com"
  description = "APIM publisher contact email."
}

# APIM service names are globally unique; add a random suffix.
resource "random_string" "suffix" {
  length  = 5
  special = false
  upper   = false
}

locals {
  name = var.prefix
  tags = {
    lab   = "waf-edge-to-app"
    phase = "5-api-gateway"
    team  = var.prefix
  }
}

resource "azurerm_resource_group" "main" {
  name     = "${local.name}-apim-rg"
  location = var.location
  tags     = local.tags
}

# ---- The API gateway (Consumption tier: serverless, pay-per-call) ----
resource "azurerm_api_management" "main" {
  name                = "${local.name}-apim-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  publisher_name      = var.publisher_name
  publisher_email     = var.publisher_email
  sku_name            = "Consumption_0"
  tags                = local.tags
}

# ---- An API fronting a public echo backend ----
resource "azurerm_api_management_api" "echo" {
  name                  = "echo-api"
  resource_group_name   = azurerm_resource_group.main.name
  api_management_name   = azurerm_api_management.main.name
  revision              = "1"
  display_name          = "Echo API"
  path                  = "echo"
  protocols             = ["https"]
  service_url           = "https://httpbin.org"
  subscription_required = true # <-- "who are you": a key is mandatory
}

resource "azurerm_api_management_api_operation" "get" {
  operation_id        = "get-anything"
  api_name            = azurerm_api_management_api.echo.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name
  display_name        = "GET /get"
  method              = "GET"
  url_template        = "/get"

  response {
    status_code = 200
  }
}

# ---- "How much": rate-limit every caller to 5 requests / minute ----
resource "azurerm_api_management_api_policy" "ratelimit" {
  api_name            = azurerm_api_management_api.echo.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name

  xml_content = <<XML
<policies>
  <inbound>
    <base />
    <rate-limit calls="5" renewal-period="60" />
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
XML
}

# ---- A subscription so you have a key to call with ----
resource "azurerm_api_management_subscription" "lab" {
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name
  display_name        = "lab-key"
  api_id              = azurerm_api_management_api.echo.id
  state               = "active"
  allow_tracing       = true
}

output "api_base_url" {
  value = "${azurerm_api_management.main.gateway_url}/echo/get"
}

output "subscription_key" {
  description = "Pass as header: Ocp-Apim-Subscription-Key"
  value       = azurerm_api_management_subscription.lab.primary_key
  sensitive   = true
}
