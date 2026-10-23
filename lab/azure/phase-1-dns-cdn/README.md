# Phase 1 · DNS + CDN (the edge)

A request's first stop. **DNS** turns your name into an address — the first thing an attacker
looks up, and a common single point of failure. The **CDN / edge** serves cached content near
the user and hides your origin's real address, so most traffic never reaches you.

> **Takeaway:** the edge handles reach and volume, not payloads. It stops floods, not clever HTTP.

## What this builds

- An **Azure Front Door (Standard)** profile, endpoint, origin group, origin and route — the CDN.
- An **optional Azure DNS zone** (set `dns_zone_name` to create it).

Front Door gives you a global edge hostname (`<something>.azurefd.net`). Users hit that; your
origin's real address stays hidden behind it.

## Deploy

```bash
export ARM_SUBSCRIPTION_ID=<sandbox-subscription-id>
cd phase-1-dns-cdn

terraform init
terraform apply -var="prefix=team1"

URL=$(terraform output -raw frontdoor_url)
curl -i $URL          # served from the edge; caches on repeat hits
```

By default the origin is a public HTTPS site so it works standalone. The point to show is that
clients only ever see the Front Door hostname — never the origin.

## Chain it onto Phase 2 (optional)

Put the edge in front of your WAF gateway:

1. Deploy Phase 2, grab its IP: `terraform -chdir=../phase-2-waf-appgw output -raw gateway_public_ip`
2. Re-apply here with that origin, and switch the origin to HTTP (the gateway listens on :80):
   ```bash
   terraform apply -var="prefix=team1" -var="origin_host_name=<gateway-ip>"
   ```
   Then in `main.tf` set `certificate_name_check_enabled = false` and the route's
   `forwarding_protocol = "HttpOnly"`, since the gateway has no TLS cert in this lab.

## Create a DNS zone

```bash
terraform apply -var="prefix=team1" -var="dns_zone_name=lab.example.com"
terraform output dns_name_servers   # delegate your domain to these
```

## Note on WAF at the edge

Front Door can also host a WAF (`azurerm_cdn_frontdoor_firewall_policy`). The **managed** OWASP
(DRS) rule set requires the **Premium** tier; **Standard** supports custom rules only. We run the
WAF on Application Gateway in Phase 2 to keep this phase cheap and focused on the edge.

## Cleanup

```bash
terraform destroy -var="prefix=team1"
```

## AWS equivalent

**Route 53** (DNS) + **CloudFront** (CDN). CloudFront distributions hide the origin the same way.
