# IP Address Allocation Reference

This document describes the IP address allocation scheme for the HomeLab infrastructure, including both IPv4 (ZeroTier overlay) and IPv6 (ULA) addresses.

## Design Principles

1. **Memorable IPv4 addresses** - Easy-to-remember patterns for quick troubleshooting
2. **Static IPv6 ULA** - No DHCP, all addresses are statically assigned
3. **Logical grouping** - IP ranges correspond to functional roles
4. **ZeroTier-first** - Physical IPs only used for initial bootstrap, then switch to ZeroTier

## IPv4 Address Scheme (ZeroTier: 10.147.17.0/24)

### Infrastructure Range (.1-.9)
- `.1` - **Reserved** (network address)
- `.2` - **Primary Proxmox host** (memorable: first infrastructure device)
- `.3` - **Secondary Proxmox host** (memorable: second infrastructure device)
- `.5` - **Primary DNS server** (Technitium)
- `.6-.9` - Reserved for future infrastructure

### Primary Site Kubernetes Nodes (.10-.19)
- `.10` - **Primary k3s server** (control plane)
- `.11` - **Primary k3s agent 1** (worker)
- `.12` - **Primary k3s agent 2** (worker)
- `.13-.19` - Reserved for additional primary site nodes

### Secondary Site Kubernetes Nodes (.20-.29)
- `.20` - **Secondary k3s server** (control plane)
- `.21` - **Secondary k3s agent 1** (worker)
- `.22` - **Secondary k3s agent 2** (worker)
- `.23-.24` - Reserved for additional secondary site nodes
- `.25` - **Secondary DNS server** (Technitium replica)
- `.26-.29` - Reserved for future use

### Shared Services VIPs (.100-.119)
LoadBalancer IPs for services accessible from both sites:
- `.100` - **Vault** (secrets management)
- `.101` - **Harbor Registry** (container registry)
- `.102` - **MinIO** (object storage)
- `.103-.109` - Reserved for additional shared storage/data services
- `.110` - **Authentik** (SSO/identity provider)
- `.111` - **Authentik LDAP** (LDAP outpost)
- `.112-.119` - Reserved for additional shared services

### Primary Site Services (.120-.139)
LoadBalancer IPs for primary site-specific services:
- `.120` - **Home Assistant** (primary site)
- `.121-.139` - Reserved for additional primary services

### Secondary Site Services (.140-.159)
LoadBalancer IPs for secondary site-specific services:
- `.121` - **Home Assistant** (secondary site - note: using .121 for consistency)
- `.140-.159` - Reserved for additional secondary services

### Special Purpose (.200+)
- `.200` - **Traefik/Proxy** (shared ingress controller)
- `.201-.254` - Dynamic/DHCP pool (if needed in future)
- `.255` - **Reserved** (broadcast address)

## IPv6 Address Scheme (ULA: fd42:147:17::/48)

### Subnet Allocation

Using RFC 4193 Unique Local Address (ULA) space with the locally-generated prefix `fd42:147:17::/48`.

#### Primary Site: `fd42:147:17:1::/64`
All primary site resources use this subnet:
- `fd42:147:17:1::5` - Primary DNS server
- `fd42:147:17:1::10` - Primary k3s server
- `fd42:147:17:1::11` - Primary k3s agent 1
- `fd42:147:17:1::12` - Primary k3s agent 2

#### Secondary Site: `fd42:147:17:2::/64`
All secondary site resources use this subnet:
- `fd42:147:17:2::20` - Secondary k3s server
- `fd42:147:17:2::21` - Secondary k3s agent 1
- `fd42:147:17:2::22` - Secondary k3s agent 2
- `fd42:147:17:2::25` - Secondary DNS server

#### Shared Services: `fd42:147:17:f::/64`
Cross-site services use the "f" (fifteen) subnet:
- `fd42:147:17:f::100` - Vault
- `fd42:147:17:f::101` - Harbor Registry
- `fd42:147:17:f::102` - MinIO
- `fd42:147:17:f::110` - Authentik
- `fd42:147:17:f::111` - Authentik LDAP
- `fd42:147:17:f::200` - Traefik/Proxy

### IPv6 Best Practices

1. **No DHCP** - All IPv6 addresses are statically assigned
2. **ULA prefix** - Uses `fd00::/8` as per RFC 4193 (not globally routable)
3. **Subnet per site** - Clear isolation and routing policies
4. **Interface IDs** - Mirror the IPv4 host portion for memorability
5. **DNS AAAA records** - All services have both A and AAAA records

## Proxmox Host IP Transition

### Bootstrap Workflow

The bootstrap process handles a critical transition for Proxmox hosts:

1. **Phase 1: Initial Access** (Physical Network)
   - Use `HOMELAB_PROXMOX_PRIMARY_INITIAL_HOST` (e.g., `root@192.168.1.10`)
   - Use `HOMELAB_PROXMOX_SECONDARY_INITIAL_HOST` (e.g., `root@192.168.2.10`)
   - Connect via physical LAN to install ZeroTier

2. **Phase 2: ZeroTier Installation**
   - Script installs ZeroTier client on Proxmox
   - Assigns static ZeroTier IPs:
     - Primary: `10.147.17.2` (via `HOMELAB_PROXMOX_PRIMARY_ZT_IP`)
     - Secondary: `10.147.17.3` (via `HOMELAB_PROXMOX_SECONDARY_ZT_IP`)
   - Joins configured ZeroTier network

3. **Phase 3: Switch to ZeroTier** (Overlay Network)
   - After authorization, all subsequent operations use ZeroTier IPs
   - `HOMELAB_PROXMOX_PRIMARY_HOST` automatically updates to `root@10.147.17.2`
   - `HOMELAB_PROXMOX_SECONDARY_HOST` automatically updates to `root@10.147.17.3`
   - **Physical IPs are never used again**

### Configuration Variables

```bash
# Physical IPs (used once for bootstrap)
HOMELAB_PROXMOX_PRIMARY_INITIAL_HOST="root@192.168.1.10"
HOMELAB_PROXMOX_SECONDARY_INITIAL_HOST="root@192.168.2.10"

# ZeroTier IPs (used for all operations after bootstrap)
HOMELAB_PROXMOX_PRIMARY_ZT_IP="10.147.17.2"
HOMELAB_PROXMOX_SECONDARY_ZT_IP="10.147.17.3"
```

## Quick Reference Table

| Device/Service | IPv4 | IPv6 | Notes |
|----------------|------|------|-------|
| **Infrastructure** |
| Primary Proxmox | 10.147.17.2 | - | Hypervisor (primary) |
| Secondary Proxmox | 10.147.17.3 | - | Hypervisor (secondary) |
| Primary DNS | 10.147.17.5 | fd42:147:17:1::5 | Technitium |
| Secondary DNS | 10.147.17.25 | fd42:147:17:2::25 | Technitium replica |
| **Primary Site Nodes** |
| k3s Server | 10.147.17.10 | fd42:147:17:1::10 | Control plane |
| k3s Agent 1 | 10.147.17.11 | fd42:147:17:1::11 | Worker node |
| k3s Agent 2 | 10.147.17.12 | fd42:147:17:1::12 | Worker node |
| **Secondary Site Nodes** |
| k3s Server | 10.147.17.20 | fd42:147:17:2::20 | Control plane |
| k3s Agent 1 | 10.147.17.21 | fd42:147:17:2::21 | Worker node |
| k3s Agent 2 | 10.147.17.22 | fd42:147:17:2::22 | Worker node |
| **Shared Services** |
| Vault | 10.147.17.100 | fd42:147:17:f::100 | Secrets |
| Harbor Registry | 10.147.17.101 | fd42:147:17:f::101 | Containers |
| MinIO | 10.147.17.102 | fd42:147:17:f::102 | Object storage |
| Authentik | 10.147.17.110 | fd42:147:17:f::110 | SSO/Auth |
| Authentik LDAP | 10.147.17.111 | fd42:147:17:f::111 | LDAP |
| Traefik | 10.147.17.200 | fd42:147:17:f::200 | Ingress |
| **Site Services** |
| Home Assistant (Primary) | 10.147.17.120 | - | Home automation |
| Home Assistant (Secondary) | 10.147.17.121 | - | Home automation |

## Adding New Services

### For Site-Specific Services

**Primary site:**
- Use range `.120-.139`
- Example: Next service would be `10.147.17.121`

**Secondary site:**
- Use range `.140-.159`
- Example: Next service would be `10.147.17.140`

### For Shared Services

- Use range `.100-.119`
- Add both IPv4 and IPv6 addresses
- Update DNS for both A and AAAA records

### Example: Adding Shared Monitoring Service

```bash
# In config.sh
export HOMELAB_PROMETHEUS_VIP="10.147.17.103"
export HOMELAB_PROMETHEUS_VIP6="fd42:147:17:f::103"

# In Kubernetes manifest
spec:
  type: LoadBalancer
  loadBalancerIP: 10.147.17.103
```

## See Also

- [CONFIGURATION.md](CONFIGURATION.md) - Full configuration reference
- [DNS-ARCHITECTURE.md](DNS-ARCHITECTURE.md) - DNS setup and service discovery
- [BOOTSTRAP-GUIDE.md](BOOTSTRAP-GUIDE.md) - Bootstrap process details
