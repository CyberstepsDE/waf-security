# From the Edge to Your App — Azure Lab

Terraform companion to the deck **"From the Edge to Your App."** It builds, phase by
phase, the gauntlet a request survives before it reaches your code — on Azure.

> One request, many layers. Each layer removes a different class of threat, so your app
> only ever meets clean traffic. Learn the layer, and the cloud product is just a name.

Each phase is a **self-contained Terraform project** you can deploy and destroy on its
own. Phase 3 is the heart of the lab (WAF on Application Gateway in front of a private
app) and works end-to-end. The others let you stand up and poke at each remaining layer.

---

## The journey (and where each phase lives)

| # | Layer | What it does | Azure service | AWS equivalent | Folder |
|---|-------|--------------|---------------|----------------|--------|
| 1 | DNS + CDN (edge) | Caches near users, hides your origin | Azure DNS + Front Door | Route 53 + CloudFront | [`phase-1-dns-cdn/`](./phase-1-dns-cdn/) |
| 2 | DDoS | Absorbs and scrubs traffic floods | DDoS Protection | AWS Shield | [`phase-2-ddos/`](./phase-2-ddos/) |
| 3 | **WAF (L7 LB)** | **Reads HTTP, blocks OWASP attacks** | **App Gateway WAF_v2** | **AWS WAF + ALB** | [`phase-3-waf-appgw/`](./phase-3-waf-appgw/) |
| 4 | Load balancer (L4) | Spreads traffic by IP/port | Azure Load Balancer | NLB | [`phase-4-load-balancer/`](./phase-4-load-balancer/) |
| 5 | API gateway | Checks auth, rate-limits callers | API Management | API Gateway | [`phase-5-api-gateway/`](./phase-5-api-gateway/) |
| 6 | The app | The thing being protected — no public IP | Container Instances | — | [`phase-6-private-app/`](./phase-6-private-app/) |

**Phase 3 is the deck's `lab/azure/main.tf`.** It is the one to run if you only run one.

---

## Prerequisites (read once)

- **A sandbox subscription.** Never a shared or production one.
- **Azure Cloud Shell** (portal → `>_`) already has Terraform and the Azure CLI — nothing
  to install. A local shell works too with `az login` + Terraform ≥ 1.5.
- **One prefix per team.** Pass `-var="prefix=team1"`, `team2`, … so resources never
  collide. The prefix is validated (2–11 lowercase chars, starts with a letter).
- **Set your subscription** so Terraform knows where to build:

  ```bash
  export ARM_SUBSCRIPTION_ID=<sandbox-subscription-id>
  # or: az account set --subscription <sandbox-subscription-id>
  ```

Every phase follows the same loop:

```bash
cd phase-N-...
terraform init
terraform apply -var="prefix=team1"
# ... try it out ...
terraform destroy -var="prefix=team1"
```

---

## Cost & time — read before you deploy

Everything bills by the hour. **Destroy the same day.**

| Phase | Deploy time | Rough cost while running | Leave running? |
|-------|-------------|--------------------------|----------------|
| 1 · Front Door | ~3–5 min | Pennies/hour (Standard) | OK briefly |
| 2 · **DDoS Protection** | ~2 min | **~$2,900 / month per plan** | ❌ **Destroy immediately** |
| 3 · App Gateway WAF | ~6–10 min | ~$0.40–0.50 / hour | Same day only |
| 4 · Load Balancer | ~3–5 min | Pennies/hour | Same day only |
| 5 · API Management (Consumption) | ~5–10 min | Pay-per-call, near-zero idle | OK briefly |
| 6 · Private app | ~1–2 min | Pennies/hour | Same day only |

> ⚠️ **Phase 2 (DDoS Network Protection) is the expensive one.** A protection *plan* is
> billed at a flat monthly rate the moment it exists. It is included so you can see the
> one line that enables it — deploy it, read the output, then `terraform destroy`.

---

## Tear everything down

Run `terraform destroy -var="prefix=team1"` in **each** phase folder you deployed. A quick
sweep from `lab/azure/`:

```bash
for d in phase-*/ ; do
  ( cd "$d" && [ -f terraform.tfstate ] && terraform destroy -auto-approve -var="prefix=team1" )
done
```

---

## The one lesson

A WAF reduces risk. It does **not** replace input validation and authorization in your
code. No single control is the answer — the stack is.

> AWS versions of these labs are intentionally out of scope for now (we're sticking with
> Azure). The AWS equivalent for each layer is named in the table above and in each
> phase's README so the port is straightforward later.
