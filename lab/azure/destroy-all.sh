#!/usr/bin/env bash
# Tear down every phase of the Edge-to-App lab for one prefix.
# Usage:  ./destroy-all.sh [prefix]          (prefix defaults to "team1")
#
# Destroys in reverse order. Phases that were never deployed (no state) are
# skipped. Run this at the end of every session — the gateway bills by the hour.

set -euo pipefail
cd "$(dirname "$0")"

PREFIX="${1:-team1}"
# reverse order of create-all
PHASES=(phase-5-private-app phase-4-api-gateway phase-3-load-balancer phase-2-waf-appgw phase-1-dns-cdn)

command -v terraform >/dev/null || { echo "terraform not found."; exit 1; }

if [[ -z "${ARM_SUBSCRIPTION_ID:-}" ]]; then
  ARM_SUBSCRIPTION_ID="$(az account show --query id -o tsv 2>/dev/null || true)"
  [[ -n "$ARM_SUBSCRIPTION_ID" ]] || { echo "Run 'az login' first (or export ARM_SUBSCRIPTION_ID)."; exit 1; }
  export ARM_SUBSCRIPTION_ID
fi
echo "▶ Destroying everything for prefix: $PREFIX"
echo

for p in "${PHASES[@]}"; do
  if [[ ! -f "$p/terraform.tfstate" ]] && [[ -z "$(ls -A "$p"/*.tfstate 2>/dev/null || true)" ]]; then
    echo "⏭  $p — no state, skipping"
    continue
  fi
  echo "═══════════════════════════════════════════════════════"
  echo "  Destroying $p"
  echo "═══════════════════════════════════════════════════════"
  terraform -chdir="$p" destroy -auto-approve -input=false -no-color -var="prefix=$PREFIX"
  echo
done

echo "✅ Done. Confirm in the portal that the resource groups are gone."
