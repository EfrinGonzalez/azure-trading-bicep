# Regulated Crypto Trading Platform — Azure Bicep Topology

This repository contains a modular Azure Bicep starter architecture for a regulated crypto trading, brokerage, custody-integration and market-data platform.

It is intentionally designed as an interview/architecture accelerator, not as a drop-in production baseline. Production use requires security review, landing-zone alignment, cost review, policy hardening, DR design, identity integration, and regulatory validation.

## Structure

```text
main.bicep
modules/
  network.bicep
  aks.bicep
  messaging.bicep
  data.bicep
  security.bicep
  observability.bicep
parameters/
  prod.bicepparam
```

## Resource groups

The subscription-level deployment creates:

- `rg-trading-prod-network`
- `rg-trading-prod-platform`
- `rg-trading-prod-data`
- `rg-trading-prod-security`
- `rg-trading-prod-observability`

## Architecture assumptions

The design assumes a hybrid, segmented, cloud-native trading platform:

- Hub-and-spoke network topology.
- Private AKS cluster for trading services.
- Azure Firewall as the egress/security choke point.
- Private endpoints for sensitive platform dependencies.
- Private DNS zones linked to hub and spoke VNets.
- Azure Service Bus for business workflows.
- Azure Event Hubs for high-throughput streaming such as market data and blockchain confirmations.
- Azure SQL for core transactional state.
- Redis for low-latency caching.
- Data Lake Gen2 for audit, analytics and reporting data.
- Cosmos DB as an optional high-throughput read-model store.
- Key Vault Premium and Managed HSM placeholder for custody-grade key management patterns.
- Azure Monitor, Log Analytics and Application Insights for observability.
- Azure Front Door, WAF and API Management as the edge/API layer.

## Deployment order

The deployment is orchestrated from `main.bicep`:

1. Resource groups
2. Observability
3. Network
4. Security
5. Data
6. Messaging
7. AKS / ACR / API edge

## Deploy

```bash
az login
az account set --subscription "<subscription-id>"

az deployment sub create \
  --location westeurope \
  --template-file main.bicep \
  --parameters parameters/prod.bicepparam
```

## Important production gaps to close

Before using this as a real platform baseline, refine:

- Management group hierarchy and Azure Policy initiative assignments.
- Exact firewall rules for exchanges, banks, custody providers and blockchain node providers.
- ExpressRoute/VPN gateway choice and routing model.
- API Management SKU and networking mode.
- AKS egress model and NAT/firewall integration.
- Key Vault/Managed HSM operational ceremony and break-glass access.
- Secrets rotation and workload identity federation.
- Full role assignments for least privilege.
- Backup, restore, geo-replication, and disaster recovery RTO/RPO.
- Cost model for Premium SKUs.
- Load testing for market data and order flow.
- Compliance controls, retention periods and immutable audit requirements.

## Interview explanation

The topology separates the platform into security domains: edge, trading compute, data, security, messaging and observability. Synchronous flows such as order submission and pre-trade checks should stay on tightly controlled API paths. Asynchronous flows such as execution reports, reconciliation, wallet events, audit events and blockchain confirmations are routed through Service Bus or Event Hubs. Sensitive dependencies are private-link only, and operational telemetry is centralized in Log Analytics and Application Insights.
