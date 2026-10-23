# Phase 5 · API Gateway (the front desk)

The last stop before your code. The API gateway is the front desk for your APIs. It checks **who
you are** (authentication), enforces **how much** you can call (rate limits and quotas), and gives
you **one door** — a single, watched entry point for every API, with logs and metrics in one place.
It stops credential stuffing and quota abuse.

## What this builds

- **Azure API Management** on the **Consumption** tier (serverless — fast to deploy, pay-per-call).
- An **Echo API** fronting a public backend (`httpbin.org`), with a **subscription key required**.
- A **rate-limit policy**: 5 calls/minute per caller, so you can trip it by hand.
- A **subscription** so you have a key to call with.

## Deploy

```bash
export ARM_SUBSCRIPTION_ID=<sandbox-subscription-id>
cd phase-5-api-gateway

terraform init
terraform apply -var="prefix=team1"    # ~5-10 min (Consumption is far faster than Developer tier)
```

## Try the three jobs of a gateway

```bash
URL=$(terraform output -raw api_base_url)
KEY=$(terraform output -raw subscription_key)

# 1. WHO ARE YOU — no key is rejected
curl -i $URL
# -> 401 Unauthorized  ("Access denied due to missing subscription key")

# with a valid key, it reaches the backend
curl -i -H "Ocp-Apim-Subscription-Key: $KEY" $URL
# -> 200, httpbin echoes your request

# 2. HOW MUCH — trip the rate limit (6th call within a minute)
for i in $(seq 1 6); do
  curl -s -o /dev/null -w "%{http_code}\n" -H "Ocp-Apim-Subscription-Key: $KEY" $URL
done
# -> 200 200 200 200 200 429   (429 Too Many Requests)

# 3. ONE DOOR — every call above is logged in APIM (Analytics / Azure Monitor),
#    one place to watch auth failures and rate-limit hits.
```

## How it maps to the policy

- **Authentication** — `subscription_required = true` on the API. No key, no entry (401).
- **Rate limit** — the `<rate-limit calls="5" renewal-period="60" />` inbound policy (429 on the 6th).
- **One door** — a single gateway URL; add more APIs behind the same APIM and they share the desk.

Tighten it as an exercise: change `calls` / `renewal-period`, add `<quota>` for a daily cap, or
add `<ip-filter>` to allow-list callers.

## Where this sits vs the WAF

The WAF (Phase 3) asks *"is this request shaped like an attack?"* The API gateway asks *"are you
allowed to call, and how often?"* Different questions — you usually want both. In a full design the
gateway sits behind the WAF/App Gateway, so traffic is scrubbed **before** the front desk checks ID.

## Cleanup

```bash
terraform destroy -var="prefix=team1"
```

Consumption tier costs almost nothing at idle, but tear it down anyway to keep the sandbox clean.

## AWS equivalent

**Amazon API Gateway** — API keys / usage plans for auth and throttling, Lambda/HTTP integrations
for the backend, the same "who and how much" role.

## Note

The Consumption tier doesn't support every APIM feature (no built-in cache, no VNet integration).
It's chosen here because it provisions in minutes; the **Developer** tier is fuller but takes ~45
minutes to deploy and costs more.
