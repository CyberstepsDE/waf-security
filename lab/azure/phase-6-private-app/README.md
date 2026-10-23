# Phase 6 · The app (the thing being protected)

The request's final destination: **your code**. Every layer in front of it exists to make sure it
only ever meets clean traffic. In this lab the app is a container with **no public IP**, in a
private subnet. Deploy it on its own and the lesson is immediate — there is nothing on the internet
to attack.

## What this builds

- A VNet with a delegated subnet.
- A **private** container app (`aci-helloworld`) with a **private IP only**.

## Deploy

```bash
export ARM_SUBSCRIPTION_ID=<sandbox-subscription-id>
cd phase-6-private-app

terraform init
terraform apply -var="prefix=team1"

terraform output app_private_ip     # e.g. 10.60.1.4 — a private address
```

## Prove it's unreachable

Ask the class: *how would you find the app's IP, and reach it?*

```bash
IP=$(terraform output -raw app_private_ip)
curl --max-time 5 http://$IP     # from your laptop / Cloud Shell: times out. It's a private address.
```

There's no public IP, no DNS name, no open port on the internet. The only way in is from **inside**
the VNet — which is exactly where a gateway you control (Phase 3) sits. That's the whole reason the
WAF works: **the easiest way around a WAF is to skip it**, and here there's nothing to skip to.

## Why this is its own phase

It's the first thing you build and the last thing a request reaches. Standing it up alone makes the
rule concrete before you add any defense: *the app never gets its own public door.* Phase 3 bundles
this same app with a gateway in front; this phase is the "before" picture.

> **Debrief question:** what breaks if the app gets its own public IP? (Answer: every layer in front
> of it becomes optional for an attacker — they route straight to the app and the WAF never sees them.)

## Cleanup

```bash
terraform destroy -var="prefix=team1"
```

## AWS equivalent

An app in a **private subnet** with no public IP / no Internet Gateway route — reachable only via an
ALB or API Gateway in the public subnets. Same principle: the workload never faces the internet directly.
