# From the Edge to Your App — Azure Lab

Terraform companion to the deck **"From the Edge to Your App."** It builds, phase by
phase, the gauntlet a request survives before it reaches your code — on Azure.

> One request, many layers. Each layer removes a different class of threat, so your app
> only ever meets clean traffic. Learn the layer, and the cloud product is just a name.

Each phase is a **self-contained Terraform project** you can deploy and destroy on its
own. Phase 2 is the heart of the lab (WAF on Application Gateway in front of a private
app) and works end-to-end. The others let you stand up and poke at each remaining layer.

---

## The journey (and where each phase lives)

| # | Layer | What it does | Azure service | AWS equivalent | Folder |
|---|-------|--------------|---------------|----------------|--------|
| 1 | DNS + CDN (edge) | Caches near users, hides your origin | Azure DNS + Front Door | Route 53 + CloudFront | [`phase-1-dns-cdn/`](./phase-1-dns-cdn/) |
| 2 | **WAF (L7 LB)** | **Reads HTTP, blocks OWASP attacks** | **App Gateway WAF_v2** | **AWS WAF + ALB** | [`phase-2-waf-appgw/`](./phase-2-waf-appgw/) |
| 3 | Load balancer (L4) | Spreads traffic by IP/port | Azure Load Balancer | NLB | [`phase-3-load-balancer/`](./phase-3-load-balancer/) |
| 4 | API gateway | Checks auth, rate-limits callers | API Management | API Gateway | [`phase-4-api-gateway/`](./phase-4-api-gateway/) |
| 5 | The app | The thing being protected — no public IP | Container Instances | — | [`phase-5-private-app/`](./phase-5-private-app/) |

**Phase 2 is the deck's `lab/azure/main.tf`.** It is the one to run if you only run one.

> The DDoS layer from the deck isn't built here — Azure DDoS Network Protection bills a flat
> ~$2,900/month per plan, which isn't worth it for a lab. The deck still covers it conceptually;
> on Azure it's one toggle (`ddos_protection_plan { enable = true }`) on a VNet.

---

## Prerequisites (read once)

- **A sandbox subscription.** Never a shared or production one.
- **Azure Cloud Shell** (portal → `>_`) already has Terraform and the Azure CLI — nothing
  to install. A local shell works too with `az login` + Terraform ≥ 1.5.
- **One prefix per team.** Pass `-var="prefix=team1"`, `team2`, … so resources never
  collide. The prefix is validated (2–11 lowercase chars, starts with a letter).
- **Set your subscription** so Terraform knows where to build:

  ```bash
  export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
  ```

Every phase follows the same loop:

```bash
cd phase-N-...
terraform init
terraform apply -var="prefix=team1"
# ... try it out ...
terraform destroy -var="prefix=team1"
```

Or do the lot at once with the helper scripts:

```bash
./create-all.sh team1     # deploy every phase
./destroy-all.sh team1    # tear every phase down
```

---

## Cost & time — read before you deploy

Everything bills by the hour. **Destroy the same day.**

| Phase | Deploy time | Rough cost while running |
|-------|-------------|--------------------------|
| 1 · Front Door | ~3–5 min | pennies/hour (Standard) |
| 2 · App Gateway WAF | ~6–10 min | ~$0.40–0.50 / hour |
| 3 · Load Balancer | ~3–5 min | pennies/hour |
| 4 · API Management (Consumption) | ~5–10 min | pay-per-call, near-zero idle |
| 5 · Private app | ~1–2 min | pennies/hour |

The provider is pinned to **azurerm `~> 5.0`**.

---

## Tear everything down

`./destroy-all.sh team1`, or run `terraform destroy -var="prefix=team1"` in each phase folder
you deployed.

---

## The one lesson

A WAF reduces risk. It does **not** replace input validation and authorization in your
code. No single control is the answer — the stack is.

> AWS versions of these labs are intentionally out of scope for now (we're sticking with
> Azure). The AWS equivalent for each layer is named in the table above and in each
> phase's README so the port is straightforward later.
