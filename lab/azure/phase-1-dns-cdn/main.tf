# =============================================================================
# Phase 1 · DNS + CDN  (the edge / outer wall)
#
# DNS turns your name into an address. The CDN serves cached content from a
# location near the user and hides your origin's real address, so most traffic
# never reaches you. Here: Azure Front Door (Standard) + an optional Azure DNS
# zone. The edge handles reach and volume, not payloads.
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
  description = "Azure region for the resource group (Front Door itself is global)."
  default     = "westeurope"
}

variable "origin_host_name" {
  type        = string
  description = <<-DESC
    Public FQDN the CDN sits in front of. Default is a public HTTPS site so this
    deploys and works on its own. To chain it onto Phase 3, set this to that
    gateway's public IP and see the notes in README (switch the origin to HTTP).
  DESC
  default     = "learn.microsoft.com"
}

variable "dns_zone_name" {
  type        = string
  description = "Optional public DNS zone to create (e.g. lab.example.com). Empty = skip."
  default     = ""
}

locals {
  name = var.prefix
  tags = {
    lab   = "waf-edge-to-app"
    phase = "1-dns-cdn"
    team  = var.prefix
  }
}

resource "azurerm_resource_group" "main" {
  name     = "${local.name}-edge-rg"
  location = var.location
  tags     = local.tags
}

# ---- Azure DNS: turns your name into an address (optional) ----
resource "azurerm_dns_zone" "main" {
  count               = var.dns_zone_name == "" ? 0 : 1
  name                = var.dns_zone_name
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags
}

# ---- Front Door Standard: caches near users, hides the origin ----
resource "azurerm_cdn_frontdoor_profile" "fd" {
  name                = "${local.name}-fd"
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = "Standard_AzureFrontDoor"
  tags                = local.tags
}

resource "azurerm_cdn_frontdoor_endpoint" "fd" {
  name                     = "${local.name}-ep"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.fd.id
  tags                     = local.tags
}

resource "azurerm_cdn_frontdoor_origin_group" "fd" {
  name                     = "app-origin-group"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.fd.id
  session_affinity_enabled = false

  load_balancing {
    sample_size                 = 4
    successful_samples_required = 3
  }

  health_probe {
    path                = "/"
    protocol            = "Https"
    request_type        = "HEAD"
    interval_in_seconds = 100
  }
}

resource "azurerm_cdn_frontdoor_origin" "fd" {
  name                          = "app-origin"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.fd.id
  enabled                       = true

  # For a public HTTPS origin keep the cert check on. For an HTTP-only origin
  # (e.g. the Phase 3 gateway on :80) set this to false — see README.
  certificate_name_check_enabled = true

  host_name          = var.origin_host_name
  origin_host_header = var.origin_host_name
  http_port          = 80
  https_port         = 443
  priority           = 1
  weight             = 1000
}

resource "azurerm_cdn_frontdoor_route" "fd" {
  name                          = "default-route"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.fd.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.fd.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.fd.id]

  supported_protocols    = ["Http", "Https"]
  patterns_to_match      = ["/*"]
  forwarding_protocol    = "HttpsOnly"
  https_redirect_enabled = true
  link_to_default_domain = true

  cache {
    compression_enabled           = true
    query_string_caching_behavior = "IgnoreQueryString"
  }
}

output "frontdoor_endpoint_hostname" {
  description = "The CDN edge hostname users hit instead of your origin."
  value       = azurerm_cdn_frontdoor_endpoint.fd.host_name
}

output "frontdoor_url" {
  value = "https://${azurerm_cdn_frontdoor_endpoint.fd.host_name}"
}

output "dns_name_servers" {
  description = "If a DNS zone was created, delegate your domain to these name servers."
  value       = var.dns_zone_name == "" ? [] : azurerm_dns_zone.main[0].name_servers
}
