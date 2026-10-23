# WAF Security — From the Edge to Your App

A hands-on security session: follow one request as it runs a gauntlet of defenses before it
reaches your code. Six layers, each dropping a different class of threat — built as real
Terraform you deploy, attack, and tear down. Azure first, with AWS equivalents noted per layer.

## What's here

| Path | What it is |
|------|------------|
| [`site/index.html`](./site/index.html) | Standalone companion website — the journey, the session plan, the WAF demo, and the Red/Blue challenge. Open it directly or host it anywhere static. |
| [`lab/azure/`](./lab/azure/) | The lab: one self-contained Terraform project per layer. See its [README](./lab/azure/README.md). |

## The six phases

| # | Layer | Azure service | AWS equivalent | Folder |
|---|-------|---------------|----------------|--------|
| 1 | DNS + CDN (edge) | Front Door + Azure DNS | Route 53 + CloudFront | `lab/azure/phase-1-dns-cdn/` |
| 2 | DDoS | DDoS Protection | AWS Shield | `lab/azure/phase-2-ddos/` |
| 3 | **WAF (L7)** | **App Gateway WAF_v2** | **AWS WAF + ALB** | `lab/azure/phase-3-waf-appgw/` |
| 4 | Load balancer (L4) | Azure Load Balancer | NLB | `lab/azure/phase-4-load-balancer/` |
| 5 | API gateway | API Management | API Gateway | `lab/azure/phase-5-api-gateway/` |
| 6 | The app | Container Instances | Private subnet | `lab/azure/phase-6-private-app/` |

**Phase 3 is the core lab.** If you run one phase, run that one.

## Quick start

```bash
az login
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)

cd lab/azure/phase-3-waf-appgw
terraform init
terraform apply -var="prefix=team1" -var="waf_mode=Detection"
```

Everything bills by the hour — **destroy it the same day** with
`terraform destroy -var="prefix=team1"`. See each phase's README for the attack commands,
log queries, and cleanup. A WAF reduces risk; it does not replace validation and
authorization in your code.
