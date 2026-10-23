# Phase 2 · WAF on Application Gateway

> **This is the deck's core lab (`lab/azure/main.tf`).** If you run one phase, run this one.

A request's third stop. A network firewall asks *"which IP and port?"* A **web application
firewall** asks *"what is this request actually trying to do?"* It reads the URL, headers,
cookies and body and blocks known attack shapes — chiefly the OWASP Top 10.

## What this builds

```
  curl ──HTTP :80──▶  Application Gateway WAF_v2  ──private──▶  Container app
  (you)               (public IP + WAF policy)                 (no public IP)
                              │
                              └─▶ Log Analytics (every WAF decision)
```

- A VNet with **two subnets**: one for the gateway, one delegated to the app.
- A **private** container (`aci-helloworld`) — no public IP. The only way in is the gateway.
- A **WAF policy**: OWASP 3.2 managed rules + custom `BlockScanners` and `RateLimitPerIp`.
- An **Application Gateway WAF_v2** (L7 load balancer) with the policy attached.
- **Log Analytics** + a diagnostic setting capturing the WAF firewall log.

## Deploy — Round 1: Detection mode

```bash
export ARM_SUBSCRIPTION_ID=<sandbox-subscription-id>
cd phase-2-waf-appgw

terraform init
terraform apply -var="prefix=team1" -var="waf_mode=Detection"
# takes ~6-10 min (the gateway is the slow part) — explain the code meanwhile

URL=$(terraform output -raw app_url)
curl -i $URL      # expect 200 and the hello page
```

### Attack it

```bash
# SQL injection
curl -i -G $URL --data-urlencode "id=1' OR '1'='1"

# Cross-site scripting
curl -i -G $URL --data-urlencode "q=<script>alert(1)</script>"

# Path traversal
curl -i --path-as-is "$URL/../../etc/passwd"

# Scanner tool (caught by the BlockScanners custom rule)
curl -i -A "sqlmap/1.7" $URL
```

In **Detection** mode every attack still returns **200** — the app answers. But each one is
recorded. That's the point of Detection: you see what *would* be blocked without breaking
anyone.

### Find yourself in the logs (Log Analytics → Logs → KQL)

```kql
AzureDiagnostics
| where Category == "ApplicationGatewayFirewallLog"
| project TimeGenerated, clientIp_s, requestUri_s, ruleId_s, action_s, Message
| order by TimeGenerated desc
```

> Logs take a few minutes to appear. Each attack shows up with the **rule ID** that matched.

## Round 2: Prevention mode

Flip one variable and re-apply — only the WAF policy changes, in seconds:

```bash
terraform apply -var="prefix=team1" -var="waf_mode=Prevention"

# rerun the Round 1 attacks — now expect: 403 Forbidden, app never sees them

# rate limit: burst 150 requests, watch it switch from 200 to 403
for i in $(seq 1 150); do
  curl -s -o /dev/null -w "%{http_code}\n" $URL
done | sort | uniq -c
# expect a mix: 200s first, then 403s once you cross 100/min
```

|                | Detection | Prevention |
|----------------|-----------|------------|
| Response       | 200       | **403**    |
| Reaches the app| Yes       | **No**     |
| Logged         | Yes       | Yes        |
| Use it for     | Learning traffic | Protecting |

## Cleanup

```bash
terraform destroy -var="prefix=team1"
```

The gateway bills by the hour (~$0.40–0.50/hr). **Destroy it the same day.**

## AWS equivalent

`aws_wafv2_web_acl` (OWASP-style **AWS managed rule groups**) associated to an `aws_lb` (ALB).
`count {}` is AWS's Detection, `none {}` is Prevention; logs go to CloudWatch. See Phase 1's
note in the master [README](../README.md) — the AWS port is out of scope for now.

## Troubleshooting

- **`curl` hangs / 502** right after apply — the backend health probe needs a minute after the
  gateway comes up. Retry.
- **No logs** — give Log Analytics 2–5 minutes; confirm the diagnostic setting exists on the gateway.
- **Name collisions** — someone else used `team1`. Pick your own `prefix`.
