# HomeLab Configuration Reference

This document describes all configurable constants for the HomeLab multi-site deployment.

## Configuration File

All configuration is centralized in `boostrap/config.sh`. Override defaults by:
1. Setting environment variables before running scripts
2. Creating `~/.homelab.conf` with your overrides
3. Editing `boostrap/config.sh` directly (not recommended for version control)

## Site Configuration

### Site Identifiers

```bash
# Primary site (default: "primary")
export HOMELAB_PRIMARY_SITE_ID="primary"
export HOMELAB_PRIMARY_SITE_NAME="Home"  # Human-readable short name
export HOMELAB_PRIMARY_SITE_LOCATION="Home Lab"  # Full description

# Secondary site (default: "secondary")
export HOMELAB_SECONDARY_SITE_ID="secondary"
export HOMELAB_SECONDARY_SITE_NAME="Remote"  # Human-readable short name
export HOMELAB_SECONDARY_SITE_LOCATION="Remote Location"  # Full description
```

**Usage Examples:**
- Ansible inventory groups: `k3s_servers_primary`, `k3s_agents_secondary`
- Node names: `k3s-primary-server-1`, `k3s-secondary-agent-2`
- DNS subdomains: `argocd.primary.homelab.internal`

### Customization Examples

**Example 1: Home office + Colo**
```bash
export HOMELAB_PRIMARY_SITE_ID="home"
export HOMELAB_PRIMARY_SITE_NAME="HomeOffice"
export HOMELAB_PRIMARY_SITE_LOCATION="Home Office - Seattle"

export HOMELAB_SECONDARY_SITE_ID="colo"
export HOMELAB_SECONDARY_SITE_NAME="Colo"
export HOMELAB_SECONDARY_SITE_LOCATION="Colocation - OVH"
```

**Example 2: Two family locations**
```bash
export HOMELAB_PRIMARY_SITE_ID="seattle"
export HOMELAB_PRIMARY_SITE_NAME="Seattle"

export HOMELAB_SECONDARY_SITE_ID="portland"
export HOMELAB_SECONDARY_SITE_NAME="Portland"
```

## DNS Configuration

### Domain Names

```bash
# Base domain (default: homelab.internal)
export HOMELAB_DNS_DOMAIN="homelab.internal"

# Auto-generated subdomains (based on site IDs)
# primary.homelab.internal
# secondary.homelab.internal
# shared.homelab.internal
```

**Service DNS Examples:**
```bash
# Site-specific services
vault.primary.homelab.internal
argocd.secondary.homelab.internal

# Shared services
vault.shared.homelab.internal
registry.shared.homelab.internal

# Shortcuts (via proxy)
vault.homelab.internal
argocd.homelab.internal
```

### DNS Server IPs

```bash
# Primary DNS server (Technitium)
export HOMELAB_PRIMARY_DNS_IP="10.147.17.5"

# Secondary DNS server (Technitium replica)
export HOMELAB_SECONDARY_DNS_IP="10.147.17.25"
```

## IP Allocation

### ZeroTier Network

```bash
# ZeroTier subnet
export HOMELAB_ZEROTIER_SUBNET="10.147.17.0/24"

# IP ranges per site
export HOMELAB_PRIMARY_IP_RANGE="10.147.17.10-19"      # Primary site nodes
export HOMELAB_SECONDARY_IP_RANGE="10.147.17.20-29"    # Secondary site nodes
export HOMELAB_SHARED_IP_RANGE="10.147.17.100-109"     # Shared service VIPs
```

### Node IPs

```bash
# Primary site
export HOMELAB_PRIMARY_SERVER_IP="10.147.17.10"   # k3s-primary-server-1
export HOMELAB_PRIMARY_AGENT1_IP="10.147.17.11"   # k3s-primary-agent-1
export HOMELAB_PRIMARY_AGENT2_IP="10.147.17.12"   # k3s-primary-agent-2

# Secondary site
export HOMELAB_SECONDARY_SERVER_IP="10.147.17.20"  # k3s-secondary-server-1
export HOMELAB_SECONDARY_AGENT1_IP="10.147.17.21"  # k3s-secondary-agent-1
export HOMELAB_SECONDARY_AGENT2_IP="10.147.17.22"  # k3s-secondary-agent-2
```

### Shared Service VIPs

```bash
# Virtual IPs for shared services (managed by keepalived/kube-vip)
export HOMELAB_VAULT_VIP="10.147.17.100"      # Vault (secrets)
export HOMELAB_REGISTRY_VIP="10.147.17.101"   # Container registry
export HOMELAB_MINIO_VIP="10.147.17.102"      # MinIO (object storage)
export HOMELAB_PROXY_VIP="10.147.17.200"      # Service proxy (Traefik)
```

## k3s Configuration

```bash
# k3s version
export HOMELAB_K3S_VERSION="v1.28.4+k3s2"

# Cluster networking
export HOMELAB_K3S_CLUSTER_CIDR="10.42.0.0/16"   # Pod CIDR
export HOMELAB_K3S_SERVICE_CIDR="10.43.0.0/16"   # Service CIDR

# Node counts per site
export HOMELAB_K8S_CONTROL_PLANE_COUNT="1"  # Servers per site
export HOMELAB_K8S_WORKER_COUNT="2"         # Agents per site
```

## Node Resource Allocation

```bash
# Server (control plane) resources
export HOMELAB_CONTROL_PLANE_CORES="2"
export HOMELAB_CONTROL_PLANE_MEMORY="4096"  # MB
export HOMELAB_CONTROL_PLANE_DISK="32"      # GB

# Agent (worker) resources
export HOMELAB_WORKER_CORES="4"
export HOMELAB_WORKER_MEMORY="8192"  # MB
export HOMELAB_WORKER_DISK="64"      # GB
```

## Helper Functions

### Generate Node Name

```bash
source boostrap/config.sh

# Usage: generate_node_name <site_id> <role> <number>
node_name=$(generate_node_name primary server 1)
# Result: k3s-primary-server-1

node_name=$(generate_node_name secondary agent 2)
# Result: k3s-secondary-agent-2
```

### Get Service DNS

```bash
source boostrap/config.sh

# Usage: get_service_dns <service> <scope>
# Scope: primary, secondary, shared, or empty for shortcut

dns=$(get_service_dns vault shared)
# Result: vault.shared.homelab.internal

dns=$(get_service_dns argocd primary)
# Result: argocd.primary.homelab.internal

dns=$(get_service_dns grafana "")
# Result: grafana.homelab.internal (shortcut)
```

## Using Configuration in Ansible

Configuration is automatically available in Ansible through `group_vars/all.yml`:

```yaml
# Ansible can access these variables:
- debug:
    msg: "Site ID: {{ primary_site_id }}"  # "primary"

- debug:
    msg: "DNS: {{ dns_domain }}"  # "homelab.internal"

- debug:
    msg: "k3s version: {{ k3s_version }}"  # "v1.28.4+k3s2"
```

## Using Configuration in Terraform

Set environment variables before running Terraform:

```bash
source boostrap/config.sh

# Terraform will see these as TF_VAR_* variables
export TF_VAR_primary_site_id="${HOMELAB_PRIMARY_SITE_ID}"
export TF_VAR_secondary_site_id="${HOMELAB_SECONDARY_SITE_ID}"
export TF_VAR_zerotier_network_id="$(cat .zerotier-network-id)"
```

## Configuration Display

View current configuration:

```bash
source boostrap/config.sh
show_config
```

Output:
```
HomeLab Bootstrap Configuration:
================================

Sites:
  Primary:   Home (primary)
  Secondary: Remote (secondary)

DNS Domains:
  Base:      homelab.internal
  Primary:   primary.homelab.internal
  Secondary: secondary.homelab.internal
  Shared:    shared.homelab.internal

Repository: https://github.com/markjpickering/HomeLab
Install Dir: /root/homelab
ZeroTier Network: HomeLabK8s
ZeroTier Subnet: 10.147.17.0/24
k3s Version: v1.28.4+k3s2
Control Plane: 1 node(s) per site
Workers: 2 node(s) per site
```

## User Overrides

Create `~/.homelab.conf` to override defaults:

```bash
# ~/.homelab.conf
# Personal configuration overrides

# Customize site names
export HOMELAB_PRIMARY_SITE_NAME="Garage"
export HOMELAB_SECONDARY_SITE_NAME="Attic"

# Use different IPs
export HOMELAB_PRIMARY_SERVER_IP="10.147.17.15"

# Bump k3s version
export HOMELAB_K3S_VERSION="v1.29.0+k3s1"
```

This file is automatically sourced by `config.sh` if it exists.

## Best Practices

1. **Don't modify `config.sh` directly** - Use environment variables or `~/.homelab.conf`
2. **Site IDs should be short** - Used in hostnames and DNS (e.g., "primary", "home", "colo")
3. **Site names can be descriptive** - Used for human-readable output (e.g., "Home Office", "Seattle")
4. **Keep IPs within allocated ranges** - Prevents IP conflicts
5. **Document custom configurations** - If you override defaults, document why

## Configuration Validation

Before deploying, validate your configuration:

```bash
source boostrap/config.sh

# Check site names are set
echo "Primary: ${HOMELAB_PRIMARY_SITE_NAME}"
echo "Secondary: ${HOMELAB_SECONDARY_SITE_NAME}"

# Check DNS subdomains resolve correctly
echo "Primary DNS: $(get_service_dns test primary)"
echo "Shared DNS: $(get_service_dns test shared)"

# Display full config
show_config
```

## See Also

- [BOOTSTRAP-GUIDE.md](BOOTSTRAP-GUIDE.md) - Bootstrap process overview
- [MULTI-SITE-ARCHITECTURE.md](MULTI-SITE-ARCHITECTURE.md) - Architecture details
- [DNS-ARCHITECTURE.md](DNS-ARCHITECTURE.md) - DNS setup and service discovery
