# DNS Domain Configuration

## Overview

The HomeLab supports **site-specific DNS domains**, allowing each site to have its own independent domain name. This provides maximum flexibility for DNS management and allows different naming strategies per site.

## Domain Types

### 1. Site-Specific Domains

Each site has its own domain that can be completely independent:

**Primary Site Domain:**
- Variable: `HOMELAB_PRIMARY_DNS_DOMAIN`
- Default: `pickers.hl`
- Services: `service.pickers.hl`

**Secondary Site Domain:**
- Variable: `HOMELAB_SECONDARY_DNS_DOMAIN`
- Default: `sheila.hl`
- Services: `service.sheila.hl`

### 2. Shared Services Domain

Shared services accessible from both sites:

**Shared Domain:**
- Variable: `HOMELAB_SHARED_DNS_DOMAIN`
- Default: `services.hl`
- Services: `service.services.hl`

### 3. Base Domain

Used for proxy shortcuts and shared resources:

**Base Domain:**
- Variable: `HOMELAB_DNS_DOMAIN`
- Default: `hl.internal`
- Services: `service.hl` (shortcuts/proxies)

## Configuration

### Setting Domain Names

Edit `boostrap/config.sh`:

```bash
# Site-specific domains (consistent .hl pattern)
export HOMELAB_PRIMARY_DNS_DOMAIN="${HOMELAB_PRIMARY_DNS_DOMAIN:-pickers.hl}"
export HOMELAB_SECONDARY_DNS_DOMAIN="${HOMELAB_SECONDARY_DNS_DOMAIN:-sheila.hl}"

# Shared services domain
export HOMELAB_SHARED_DNS_DOMAIN="${HOMELAB_SHARED_DNS_DOMAIN:-services.hl}"

# Base domain (for shortcuts)
export HOMELAB_DNS_DOMAIN="${HOMELAB_DNS_DOMAIN:-hl.internal}"
```

### Example Configurations

#### Consistent .hl Pattern (Default)
```bash
export HOMELAB_PRIMARY_DNS_DOMAIN="pickers.hl"
export HOMELAB_SECONDARY_DNS_DOMAIN="sheila.hl"
export HOMELAB_SHARED_DNS_DOMAIN="services.hl"
export HOMELAB_DNS_DOMAIN="hl.internal"
```

#### Subdomain-Based (Traditional)
```bash
export HOMELAB_PRIMARY_DNS_DOMAIN="primary.homelab.local"
export HOMELAB_SECONDARY_DNS_DOMAIN="secondary.homelab.local"
export HOMELAB_SHARED_DNS_DOMAIN="shared.homelab.local"
export HOMELAB_DNS_DOMAIN="homelab.local"
```

#### Public Domains
```bash
export HOMELAB_PRIMARY_DNS_DOMAIN="home.pickering.family"
export HOMELAB_SECONDARY_DNS_DOMAIN="home.sheila.family"
export HOMELAB_SHARED_DNS_DOMAIN="shared.homelab.internal"
export HOMELAB_DNS_DOMAIN="homelab.internal"
```

## DNS Zone Structure

With the default configuration (`pickers.hl` / `sheila.hl`):

### Primary Site Zone (pickers.hl)
```
pickers.hl                SOA, NS records
├── argocd.pickers.hl    A → 10.147.17.10
├── grafana.pickers.hl   A → 10.147.17.11
├── vault.pickers.hl     A → 10.147.17.12
└── *.pickers.hl         Wildcard for k8s ingress
```

### Secondary Site Zone (sheila.hl)
```
sheila.hl                 SOA, NS records
├── argocd.sheila.hl     A → 10.147.17.20
├── grafana.sheila.hl    A → 10.147.17.21
├── vault.sheila.hl      A → 10.147.17.22
└── *.sheila.hl          Wildcard for k8s ingress
```

### Shared Zone (services.hl)
```
services.hl                     SOA, NS records
├── vault.services.hl          A → 10.147.17.100 (VIP)
├── registry.services.hl       A → 10.147.17.101 (VIP)
├── minio.services.hl          A → 10.147.17.102 (VIP)
└── auth.services.hl           A → 10.147.17.110 (Authentik)
```

### Base Zone (hl.internal)
```
hl.internal                            SOA, NS records
├── vault.hl                 CNAME → vault.services.hl
├── argocd.hl                CNAME → argocd.pickers.hl
└── grafana.hl               CNAME → grafana.pickers.hl
```

## Service Access Examples

### Accessing Site-Specific Services

**Primary Site:**
- ArgoCD: `https://argocd.pickers.hl`
- Grafana: `https://grafana.pickers.hl`
- Traefik Dashboard: `https://traefik.pickers.hl/dashboard/`

**Secondary Site:**
- ArgoCD: `https://argocd.sheila.hl`
- Grafana: `https://grafana.sheila.hl`
- Traefik Dashboard: `https://traefik.sheila.hl/dashboard/`

### Accessing Shared Services

Direct access via shared domain:
- Vault: `https://vault.services.hl`
- Registry: `https://registry.services.hl`
- MinIO: `https://minio.services.hl`
- Authentik: `https://auth.services.hl`

### Accessing via Shortcuts

Convenient shortcuts using base domain:
- Vault: `https://vault.hl` → routes to `vault.services.hl`
- ArgoCD: `https://argocd.hl` → routes to active site
- Grafana: `https://grafana.hl` → routes to unified dashboard

## DNS Server Configuration

### Primary DNS Server (10.147.17.5)

**Authoritative Zones:**
- `pickers.hl` - Primary site zone (authoritative)
- `services.hl` - Shared services (authoritative)
- `hl.internal` - Base domain with shortcuts (authoritative)

**Zone Transfers:**
- Allows transfers to secondary DNS (10.147.17.25)
- Transfers: `services.hl`, `hl.internal`

### Secondary DNS Server (10.147.17.25)

**Authoritative Zones:**
- `sheila.hl` - Secondary site zone (authoritative)

**Replicated Zones:**
- `services.hl` - From primary DNS
- `hl.internal` - From primary DNS

## Kubernetes Integration

### external-dns Configuration

Each site's external-dns is configured to manage its own domain:

**Primary Site:**
```yaml
args:
  - --domain-filter=pickers.hl
  - --txt-owner-id=primary
env:
  - name: TECHNITIUM_DNS_SERVER
    value: "http://10.147.17.5:5380"
```

**Secondary Site:**
```yaml
args:
  - --domain-filter=sheila.hl
  - --txt-owner-id=secondary
env:
  - name: TECHNITIUM_DNS_SERVER
    value: "http://10.147.17.25:5380"
```

**Shared Services:**
```yaml
args:
  - --domain-filter=services.hl
  - --txt-owner-id=shared
env:
  - name: TECHNITIUM_DNS_SERVER
    value: "http://10.147.17.5:5380"
```

### Service Annotations

**Primary Site Service:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: argocd-server
  namespace: argocd
  annotations:
    external-dns.alpha.kubernetes.io/hostname: "argocd.pickers.hl"
spec:
  type: LoadBalancer
  loadBalancerIP: 10.147.17.10
```

**Secondary Site Service:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: argocd-server
  namespace: argocd
  annotations:
    external-dns.alpha.kubernetes.io/hostname: "argocd.sheila.hl"
spec:
  type: LoadBalancer
  loadBalancerIP: 10.147.17.20
```

**Shared Service:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: vault
  namespace: vault
  annotations:
    external-dns.alpha.kubernetes.io/hostname: "vault.services.hl"
spec:
  type: LoadBalancer
  loadBalancerIP: 10.147.17.100
```

## Helper Functions

The `boostrap/config.sh` provides helper functions for DNS:

### get_service_dns

Generate proper DNS names for services:

```bash
# Usage: get_service_dns <service> <scope>
# Scope: primary, secondary, shared, or empty for shortcut

# Examples:
get_service_dns "argocd" "primary"    # → argocd.pickers.hl
get_service_dns "argocd" "secondary"  # → argocd.sheila.hl
get_service_dns "vault" "shared"      # → vault.services.hl
get_service_dns "grafana" ""          # → grafana.hl
```

## Migration Guide

### Changing Domain Names

If you need to change domain names after initial setup:

1. **Update configuration:**
   ```bash
   # Edit boostrap/config.sh
   export HOMELAB_PRIMARY_DNS_DOMAIN="new-domain.local"
   ```

2. **Update DNS zones in Technitium:**
   - Create new zone with new domain name
   - Migrate records from old zone
   - Update zone transfer settings

3. **Update external-dns:**
   ```bash
   # Update domain-filter in external-dns deployment
   kubectl edit deployment external-dns -n kube-system
   # Change --domain-filter=old-domain to --domain-filter=new-domain
   ```

4. **Update service annotations:**
   ```bash
   # Update all services with external-dns annotations
   kubectl annotate service <service-name> \
     external-dns.alpha.kubernetes.io/hostname="service.new-domain.local" \
     --overwrite
   ```

5. **Update Ingress/IngressRoute resources:**
   ```bash
   # Update host rules in Traefik IngressRoutes
   # Or update Ingress host fields
   ```

6. **Test resolution:**
   ```bash
   dig service.new-domain.local @10.147.17.5
   ```

## TLD Considerations

### Private TLDs

For internal-only use, you can use any TLD:
- `.hl` (HomeLab)
- `.home`
- `.local`
- `.internal`
- `.lan`

**Pros:**
- Complete control
- No external dependencies
- Fast resolution

**Cons:**
- Not resolvable outside your network
- May conflict with future ICANN TLDs
- Requires careful DNS configuration

### Public Domains

Use actual registered domains:
- `home.yourdomain.com`
- `lab.yourdomain.com`

**Pros:**
- Can get valid SSL certificates (Let's Encrypt)
- Resolvable anywhere
- Professional appearance

**Cons:**
- Requires domain registration
- DNS records publicly visible
- Need to manage external DNS

### Recommended Approach

**For most homelabs:**
Use private TLDs (`.hl`, `.home`, `.local`) for internal services and keep external access via VPN or ZeroTier.

**For advanced setups:**
Use public subdomains with split-horizon DNS (internal IPs inside network, external IPs or VPN outside).

## Troubleshooting

### DNS Not Resolving

```bash
# Check DNS server is accessible
ping 10.147.17.5

# Test DNS query directly
dig argocd.pickers.hl @10.147.17.5

# Check Technitium web UI
open http://10.147.17.5:5380
```

### Service Not Registered

```bash
# Check external-dns logs
kubectl logs -n kube-system deployment/external-dns

# Verify service annotation
kubectl get service <name> -o yaml | grep external-dns

# Check Technitium API token
kubectl get secret technitium-token -n kube-system -o jsonpath='{.data.token}' | base64 -d
```

### Wrong Domain in DNS Records

```bash
# Check external-dns domain filter
kubectl get deployment external-dns -n kube-system -o yaml | grep domain-filter

# Verify configuration matches
cat boostrap/config.sh | grep DNS_DOMAIN

# Recreate service to trigger re-registration
kubectl delete service <name>
kubectl apply -f <service.yaml>
```

## Best Practices

1. **Keep domains short** - Easier to type and remember
2. **Use consistent naming** - Same pattern across sites
3. **Document custom domains** - Especially if using non-standard TLDs
4. **Test DNS resolution** - Before deploying services
5. **Use wildcard records** - For k8s ingress flexibility
6. **Backup zone files** - Regular exports from Technitium
7. **Monitor DNS health** - Set up alerts for DNS failures

## Related Documentation

- [DNS Architecture](DNS-ARCHITECTURE.md) - Complete DNS infrastructure
- [Configuration Reference](CONFIGURATION.md) - All configuration variables
- [Multi-Site Architecture](MULTI-SITE-ARCHITECTURE.md) - Overall architecture
- [Bootstrap Usage](BOOTSTRAP-USAGE.md) - Bootstrap process
