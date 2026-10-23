# Phase 3 · Load Balancer — L4 (distribution)

A request's fourth stop. A load balancer spreads traffic across healthy servers so no single box
is overwhelmed, and skips any that fail. Two flavors:

- **L4 · transport (this phase)** — routes by **IP and port**. Fast and simple, but blind to what
  the request contains.
- **L7 · application** — understands HTTP: routes by path, terminates TLS, hosts the WAF. *That's
  Phase 2's Application Gateway.* For web apps you usually want L7.

This phase stands up the **L4** flavor so you can see the other half of the picture.

## What this builds

```
  curl ──:80──▶  Azure Standard Load Balancer  ──┬──▶  app-0 (private)
                 (one public IP, L4 rule)         └──▶  app-1 (private)
                        │ health probe drops any backend that stops answering
```

- Two **private** container apps (configurable via `backend_count`).
- A **Standard Load Balancer** with a public IP, an IP-based backend pool, a health probe and an
  L4 rule forwarding `:80`.

## Deploy

```bash
export ARM_SUBSCRIPTION_ID=<sandbox-subscription-id>
cd phase-3-load-balancer

terraform init
terraform apply -var="prefix=team1"

URL=$(terraform output -raw lb_url)
curl -i $URL         # answered by one of the backends
```

## See it spread and self-heal

- **Spread:** both backends serve the same page, so you won't see the difference in the body. Watch
  it in the portal: **Load balancer → Metrics → Data path availability / SNAT**, or scale
  `backend_count` up and watch new backends join the pool.
- **Self-heal:** stop one container (`az container stop -g <rg> -n team1-app-0`). The probe marks it
  down within seconds and the LB routes only to the healthy one. `curl` keeps returning 200.

## L4 vs L7 — the point of this phase

| | L4 (this phase) | L7 (Phase 2) |
|---|---|---|
| Routes by | IP + port | URL path, headers |
| Understands HTTP? | No | Yes |
| Can host a WAF? | No | Yes |
| TLS termination | No | Yes |
| Azure service | Load Balancer | Application Gateway |
| Use it for | Raw TCP/UDP, extreme throughput | Web apps (usually this) |

An L4 balancer can't help a WAF because it never reads the request. That's exactly why the WAF
lives on the **L7** Application Gateway in Phase 2.

## Cleanup

```bash
terraform destroy -var="prefix=team1"
```

## AWS equivalent

**Network Load Balancer (NLB)** is L4; **Application Load Balancer (ALB)** is L7 and is where
AWS WAF attaches — the same split as Azure Load Balancer vs Application Gateway.
