#!/usr/bin/env bash
# Deploy every phase of the Edge-to-App lab with one prefix.
# Usage:  ./create-all.sh [prefix]           (prefix defaults to "team1")
#
# Each phase is independent, so this just loops them in order. It is safe to
# re-run: Terraform only changes what drifted.

set -euo pipefail
cd "$(dirname "$0")"

PREFIX="${1:-team1}"
PHASES=(phase-1-dns-cdn phase-2-waf-appgw phase-3-load-balancer phase-4-api-gateway phase-5-private-app)

# --- sanity checks -----------------------------------------------------------
command -v terraform >/dev/null || { echo "terraform not found. Use Azure Cloud Shell or install it."; exit 1; }
command -v az >/dev/null        || { echo "azure cli (az) not found."; exit 1; }

if [[ -z "${ARM_SUBSCRIPTION_ID:-}" ]]; then
  ARM_SUBSCRIPTION_ID="$(az account show --query id -o tsv 2>/dev/null || true)"
  [[ -n "$ARM_SUBSCRIPTION_ID" ]] || { echo "Run 'az login' first (or export ARM_SUBSCRIPTION_ID)."; exit 1; }
  export ARM_SUBSCRIPTION_ID
fi
echo "▶ Subscription: $ARM_SUBSCRIPTION_ID"
echo "▶ Prefix:       $PREFIX"
echo

# --- deploy ------------------------------------------------------------------
for p in "${PHASES[@]}"; do
  echo "═══════════════════════════════════════════════════════"
  echo "  Deploying $p"
  echo "═══════════════════════════════════════════════════════"
  terraform -chdir="$p" init -input=false -no-color
  terraform -chdir="$p" apply -auto-approve -input=false -no-color -var="prefix=$PREFIX"
  echo
done

echo "✅ All phases deployed. Useful URLs:"
terraform -chdir=phase-2-waf-appgw     output -raw app_url   2>/dev/null && echo "   ← WAF-protected app" || true
terraform -chdir=phase-1-dns-cdn       output -raw frontdoor_url 2>/dev/null && echo "   ← Front Door edge" || true
terraform -chdir=phase-3-load-balancer output -raw lb_url    2>/dev/null && echo "   ← L4 load balancer" || true
echo
echo "⚠  This bills by the hour. Tear it all down with:  ./destroy-all.sh $PREFIX"
