# Phase 2 · DDoS Protection (volume)

> ⚠️ **This is the expensive phase.** A DDoS Network Protection **plan** is billed at a flat
> **~US$2,900/month** the moment it exists — not hourly, not free-tier. Deploy it only to see
> how it's wired, read the output, then **destroy it immediately.**

A request's second stop. A DDoS attack is not clever, it's just huge: thousands of machines
send junk traffic at once, your servers spend everything answering noise, and real users get
errors. The cloud absorbs the flood on infrastructure far larger than yours, scrubs it upstream,
and passes only clean traffic through.

## What this builds

- An **Azure DDoS Network Protection plan**.
- A **VNet associated to the plan** — the whole feature is three lines:

  ```hcl
  ddos_protection_plan {
    id     = azurerm_network_ddos_protection_plan.main.id
    enable = true
  }
  ```

That's the lesson: DDoS protection isn't something you build, it's something you *switch on* for
a network. Azure's scrubbing capacity does the rest.

## Deploy (only if you accept the charge)

There is a deliberate safety switch — apply fails unless you opt in:

```bash
export ARM_SUBSCRIPTION_ID=<sandbox-subscription-id>
cd phase-2-ddos

terraform init
terraform apply -var="prefix=team1" -var="i_understand_ddos_billing=true"

terraform output            # read it...
terraform destroy -var="prefix=team1" -var="i_understand_ddos_billing=true"   # ...then tear it down
```

## Why no attack demo here

You cannot (and must not) actually DDoS anything from the lab — that's abuse, and the mitigation
happens inside Azure's backbone where you can't see it directly. In a real tenant you'd watch the
**DDoS Protection** metrics (`Under DDoS attack or not`, inbound packets dropped) in Azure Monitor.
This phase is about the wiring and the economics, not a live flood.

## Cheaper alternative for everyday use

**Azure DDoS IP Protection** protects a single public IP and bills per-IP per-month (far less than a
network plan) — a better fit for one gateway. The network *plan* in this lab protects an entire VNet
and is priced accordingly.

## Cleanup

```bash
terraform destroy -var="prefix=team1" -var="i_understand_ddos_billing=true"
```

Confirm in the portal that the plan is gone — this is the one resource you never want to forget.

## AWS equivalent

**AWS Shield.** *Shield Standard* is automatic and free on CloudFront/ALB; *Shield Advanced* is the
paid tier (~US$3,000/month) comparable to this plan.
