# Multi-Site HomeLab Architecture

This document describes the multi-site architecture for a geographically distributed HomeLab with automatic failover and data reconciliation.

## Overview

The HomeLab spans **two physical sites** connected via ZeroTier overlay network:
- **Site A**: Primary location (e.g., home)
- **Site B**: Secondary location (e.g., remote/family/colo)

Each site runs a **k3s cluster** (lightweight Kubernetes). Shared services provide high availability with automatic failover when inter-site connectivity is lost.

**Why k3s?**
- Lightweight (single binary, <100MB)
- Built-in components (Traefik, ServiceLB, local storage)
- Perfect for HomeLab and edge deployments
- Full Kubernetes API compatibility
- Multi-node support with embedded etcd

## Architecture Principles

1. **ZeroTier as the fabric**: All inter-site communication over encrypted ZeroTier overlay
2. **Site autonomy**: Each site can operate independently during network partition
3. **Shared services resilience**: Critical shared services fail over automatically
4. **Eventual consistency**: Data reconciles when connectivity is restored
5. **No external dependencies**: GitHub is the only external service

## Network Topology

```
┌─────────────────────────────────────────────────────────────────┐
│                        ZeroTier Network                         │
│                      (10.147.17.0/24)                           │
│                                                                 │
│  ├─────────────────────────┐  ┌─────────────────────────┐    │
│  │      Site A             │  │      Site B             │    │
│  │   (Primary Location)    │  │  (Secondary Location)   │    │
│  │                         │  │                         │    │
│  │  k3s Cluster A          │  │  k3s Cluster B          │    │
│  │  - 1 server (master)    │  │  - 1 server (master)    │    │
│  │  - 2 agents (workers)   │  │  - 2 agents (workers)   │    │
│  │  - 10.147.17.10-19      │  │  - 10.147.17.20-29      │    │
│  │                         │  │                         │    │
│  │  Shared Services (A)    │  │  Shared Services (B)    │    │
│  │  - Vault (active)       │  │  - Vault (standby)      │    │
│  │  - MinIO (node 1-2)     │  │  - MinIO (node 3-4)     │    │
│  │  - Prometheus           │  │  - Prometheus           │    │
│  │  - Registry (primary)   │  │  - Registry (mirror)    │    │
│  └─────────────────────────┘  └─────────────────────────┘    │
│                                                                 │
│  ┌─────────────────────────┐                                   │
│  │   ztnet Controller      │                                   │
│  │   (Runs at Site A)      │                                   │
│  │   - Accessible from     │                                   │
│  │     both sites          │                                   │
│  └─────────────────────────┘                                   │
└─────────────────────────────────────────────────────────────────┘

External:
  GitHub (source control, image hosting)
```

## IP Allocation

### Site A (10.147.17.10-19)
- `10.147.17.10` - k3s-a-server-1 (control plane)
- `10.147.17.11` - k3s-a-agent-1 (worker)
- `10.147.17.12` - k3s-a-agent-2 (worker)
- `10.147.17.15` - ztnet controller (optional dedicated node)

### Site B (10.147.17.20-29)
- `10.147.17.20` - k3s-b-server-1 (control plane)
- `10.147.17.21` - k3s-b-agent-1 (worker)
- `10.147.17.22` - k3s-b-agent-2 (worker)

### Shared Services VIPs (Virtual IPs)
- `10.147.17.100` - Vault (floats between sites)
- `10.147.17.101` - Container Registry (floats between sites)

## Service Placement Strategy

### Site-Local Services (Per Cluster)

These run independently in each cluster and do NOT fail over:

| Service | Purpose | Notes |
|---------|---------|-------|
| **ArgoCD** | GitOps deployment | Each cluster has own instance, same repo |
| **Traefik** | Ingress controller | Built-in to k3s, configured per cluster |
| **Cert-Manager** | TLS certificates | Let's Encrypt per cluster |
| **Local Storage** | PersistentVolumes | k3s built-in local-path provisioner |
| **ServiceLB** | LoadBalancer provider | k3s built-in (Klipper-lb) |
| **Flannel** | CNI | k3s built-in (or replace with Calico) |

### Active/Passive Shared Services

**One active instance, automatic failover to standby.**

#### 1. HashiCorp Vault (Secrets Management)
- **Mode**: Active/Passive with Raft storage
- **Primary**: Site A
- **Secondary**: Site B (standby, syncs via Raft)
- **Failover**: Automatic via Raft leader election
- **VIP**: `10.147.17.100` (DNS or external-dns)
- **Reconciliation**: Raft consensus (automatic)

**Implementation:**
- Vault Raft cluster spans both sites (5 nodes: 3xA, 2xB)
- Auto-unseal using transit secrets
- Clients connect to VIP or multi-endpoint

#### 2. Container Registry
- **Mode**: Active/Passive with mirroring
- **Primary**: Site A (Harbor or Docker Registry v2)
- **Secondary**: Site B (read-only mirror)
- **Failover**: DNS switch or multi-endpoint clients
- **Reconciliation**: Rsync or registry replication when reconnected

**Implementation:**
- Harbor replication policy: Site A → Site B
- Site B becomes read/write on failover (manual promotion)
- GitHub Container Registry (ghcr.io) as ultimate fallback

### Active/Active Shared Services

**Both sites run simultaneously, distributed queries/writes.**

#### 3. Prometheus (Monitoring)
- **Mode**: Active/Active with federation
- **Deployment**: Each cluster scrapes local metrics
- **Federation**: Thanos or Prometheus federation
- **Query**: Thanos Query aggregates both sites
- **Reconciliation**: Not needed (time-series immutable)

**Implementation:**
- Prometheus per cluster scrapes local targets
- Thanos Sidecar ships blocks to MinIO (distributed storage)
- Thanos Query provides global view
- Grafana queries Thanos

#### 4. Loki (Logging)
- **Mode**: Active/Active distributed
- **Deployment**: Loki per cluster, shared object storage
- **Query**: Loki Gateway queries all instances
- **Reconciliation**: Not needed (logs are immutable)

**Implementation:**
- Loki writes to MinIO (distributed storage)
- Promtail per node ships logs
- Grafana queries via Loki Gateway

#### 5. MinIO (Object Storage)
- **Mode**: Active/Active distributed
- **Deployment**: Multi-node across both sites
- **Erasure Coding**: 4 nodes (2 per site), EC:2 (tolerates 1 site failure)
- **Reconciliation**: MinIO handles automatically

**Implementation:**
```yaml
# 4-node MinIO cluster
Site A: minio-1, minio-2
Site B: minio-3, minio-4
Erasure Set: EC:2 (2 data + 2 parity)
```
- Survives 1 site failure (2 nodes down)
- Automatic healing when site reconnects

### Special Case: ztnet Controller

- **Deployment**: Single instance at Site A
- **Accessibility**: Available over ZeroTier from both sites
- **Failover**: Manual (move controller identity to Site B)
- **Impact**: Network continues during outage (members stay connected)

**Why this works:**
- ZeroTier clients maintain connections even if controller is unreachable
- Controller only needed for network changes (add/remove members)
- Can manually fail over by copying `/var/lib/zerotier-one/controller.d/` to Site B

## Failover Scenarios

### Scenario 1: Site A Network Partition

**What happens:**
1. Site A loses internet/ZeroTier connectivity
2. Site A cluster continues running local workloads
3. Site B cluster continues running local workloads
4. Shared services:
   - **Vault**: Site B Raft nodes elect new leader → Site B active
   - **Registry**: Clients fail over to Site B mirror (becomes R/W)
   - **MinIO**: EC:2 still functional with Site B nodes + replicated data
   - **Prometheus/Loki**: Site B continues collecting, partial data visible
   - **ztnet**: Unreachable, but network continues functioning

**User impact:**
- Site A local services: DOWN
- Site B local services: UP
- Shared services: UP (running from Site B)

### Scenario 2: Site A Total Failure (Power/Hardware)

Same as Scenario 1, but Site A cluster is completely offline.

### Scenario 3: Inter-Site Link Flapping

**What happens:**
1. ZeroTier connection unstable between sites
2. Vault Raft may flip-flop leaders (use stable witness/tiebreaker)
3. MinIO healing repeatedly triggers (configure backoff)
4. Prometheus/Loki unaffected (writes are async)

**Mitigation:**
- Vault Raft: Deploy 5th witness node in cloud (DigitalOcean, etc.)
- MinIO: Increase healing interval
- Use ZeroTier route metrics to prefer stable paths

### Scenario 4: Connectivity Restored

**What happens:**
1. ZeroTier connectivity resumes
2. **Vault**: Raft automatically syncs, standby nodes catch up
3. **Registry**: Replication resumes (Site A pulls Site B changes)
4. **MinIO**: Automatic healing reconciles objects
5. **Prometheus/Loki**: No action needed (immutable time-series)

**Manual steps:**
- Verify Vault Raft cluster health
- Trigger registry replication sync
- Check MinIO healing status

## Implementation Phases

### Phase 1: Foundation (Existing)
- ✅ Single-site bootstrap with ztnet
- ✅ ZeroTier overlay network
- ✅ Single k3s cluster
- ✅ Terraform + Ansible automation

### Phase 2: Second Site Provisioning
1. **Extend Terraform** to provision Site B nodes (1 server + 2 agents)
2. **Site B nodes join same ZeroTier network**
3. **Deploy second k3s cluster** at Site B via Ansible
4. **Test inter-site connectivity** (ping, kubectl)

**Deliverables:**
- `k8s-infra/terraform/site-b.tf`
- `k8s-infra/ansible/roles/k3s-server/` (control plane role)
- `k8s-infra/ansible/roles/k3s-agent/` (worker role)
- `k8s-infra/ansible/inventory/hosts-site-b.ini`
- Updated `bootstrap-infrastructure.sh` for multi-site

### Phase 3: Shared Services - Active/Passive
1. **Deploy Vault Raft cluster** (3 nodes Site A, 2 nodes Site B)
2. **Setup Container Registry** with replication
3. **Configure DNS/VIPs** for failover endpoints
4. **Test failover scenarios** (simulate Site A failure)

**Deliverables:**
- `k8s-apps/vault/vault-raft-multi-site.yaml`
- `k8s-apps/registry/harbor-replication.yaml`
- Failover testing scripts

### Phase 4: Shared Services - Active/Active
1. **Deploy MinIO distributed** (4 nodes, 2 per site)
2. **Deploy Thanos/Prometheus** with federation
3. **Deploy Loki** with MinIO backend
4. **Setup Grafana** with multi-cluster views

**Deliverables:**
- `k8s-apps/storage/minio-distributed.yaml`
- `k8s-apps/monitoring/thanos-stack.yaml`
- `k8s-apps/logging/loki-distributed.yaml`

### Phase 5: Automation & Observability
1. **Automated failover testing** (chaos engineering)
2. **Monitoring of site connectivity**
3. **Alerting on split-brain scenarios**
4. **Runbooks for manual interventions**

**Deliverables:**
- `docs/FAILOVER-RUNBOOK.md`
- `k8s-apps/monitoring/site-health-checks.yaml`
- Litmus chaos experiments

## Technology Choices

### Why Vault with Raft (not etcd)?
- Native Raft clustering across WAN
- Auto-unseal capabilities
- Secrets replication built-in
- Simpler than external etcd cluster

### Why MinIO (not Ceph/Rook)?
- Lightweight for HomeLab
- Native erasure coding across sites
- S3-compatible API
- Works well over WAN (ZeroTier)

### Why Thanos (not Cortex)?
- Simpler deployment model
- Works with existing Prometheus
- No central coordinator needed
- Good for small-scale multi-cluster

### Why Harbor (not plain registry)?
- Built-in replication
- Vulnerability scanning
- RBAC and project management
- Helm chart registry

## Configuration Examples

### Vault Raft Storage (vault-config.hcl)
```hcl
storage "raft" {
  path = "/vault/data"
  node_id = "vault-a-1"
  
  retry_join {
    leader_api_addr = "http://vault-a-2:8200"
  }
  retry_join {
    leader_api_addr = "http://vault-a-3:8200"
  }
  retry_join {
    leader_api_addr = "http://vault-b-1:8200"
  }
  retry_join {
    leader_api_addr = "http://vault-b-2:8200"
  }
}

listener "tcp" {
  address = "0.0.0.0:8200"
  tls_disable = false
  tls_cert_file = "/vault/tls/cert.pem"
  tls_key_file = "/vault/tls/key.pem"
}

api_addr = "https://10.147.17.10:8200"
cluster_addr = "https://10.147.17.10:8201"
ui = true
```

### MinIO Distributed (4 nodes)
```bash
# Site A
minio-1: http://10.147.17.11:9000/data1
minio-2: http://10.147.17.12:9000/data1

# Site B
minio-3: http://10.147.17.21:9000/data1
minio-4: http://10.147.17.22:9000/data1

# Start command (each node)
minio server \
  http://10.147.17.{11,12,21,22}:9000/data1 \
  --address ":9000" \
  --console-address ":9001"
```

### Thanos Query (Global View)
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: thanos-query
spec:
  template:
    spec:
      containers:
      - name: thanos-query
        image: quay.io/thanos/thanos:v0.32.0
        args:
        - query
        - --http-address=0.0.0.0:9090
        - --store=dnssrv+_grpc._tcp.thanos-store-site-a.monitoring.svc.cluster.local
        - --store=dnssrv+_grpc._tcp.thanos-store-site-b.monitoring.svc.cluster.local
```

## DNS and Service Discovery

### Option 1: ExternalDNS (Recommended)
- Deploy ExternalDNS in each cluster
- Update private DNS zone (Cloudflare/Route53/Pi-hole)
- Services get DNS entries automatically

**Example:**
- `vault.homelab.internal` → 10.147.17.100 (VIP)
- `registry.homelab.internal` → 10.147.17.101 (VIP)

### Option 2: CoreDNS Forwarding
- Each cluster's CoreDNS forwards to central DNS
- Central DNS managed by ExternalDNS or manual
- Works without external DNS provider

### Option 3: /etc/hosts + Ansible
- Simplest for small deployments
- Ansible template manages /etc/hosts on all nodes
- No DNS server needed

## Monitoring Site Health

### Key Metrics
- **ZeroTier link status**: ping latency between sites
- **Vault Raft status**: leader location, peer sync
- **MinIO healing**: ongoing operations
- **Prometheus federation lag**: time difference in metrics

### Alerting Rules
```yaml
# Site connectivity alert
- alert: SiteConnectivityLost
  expr: up{job="zerotier-ping", site="b"} == 0
  for: 5m
  annotations:
    summary: "Site B unreachable from Site A"

# Vault leadership
- alert: VaultLeaderChanged
  expr: changes(vault_core_leader{instance=~".*site-a.*"}[5m]) > 0
  annotations:
    summary: "Vault leader changed (possible failover)"

# MinIO healing
- alert: MinIOHealingActive
  expr: minio_heal_objects_heal_total > 1000
  for: 30m
  annotations:
    summary: "MinIO healing in progress (site reconnected?)"
```

## Security Considerations

### Inter-Site Encryption
- ZeroTier provides encryption (P2P AES-256)
- Additional TLS for application traffic (defense in depth)
- Mutual TLS (mTLS) for service-to-service

### Secrets Management
- Vault for all secrets (API keys, DB passwords, certificates)
- SOPS for secrets-at-rest in Git (Terraform/Ansible secrets)
- No plain-text secrets in cluster

### Network Segmentation
- Each cluster has own network policies
- Shared services in dedicated namespace
- ZeroTier flow rules for additional filtering

## Cost Considerations

### Compute Resources (k3s Lightweight)
- **Site A Server**: 1 VM (4GB RAM, 2 vCPU) - k3s control plane
- **Site A Agents**: 2 VMs (4GB RAM, 2 vCPU each) - workers
- **Site B Server**: 1 VM (4GB RAM, 2 vCPU) - k3s control plane
- **Site B Agents**: 2 VMs (4GB RAM, 2 vCPU each) - workers
- **Shared Services**: Run on existing agent nodes
- **Total**: ~24GB RAM, 12 vCPU across both sites

**k3s is much lighter than full Kubernetes:**
- Control plane: ~512MB RAM (vs 2GB+ for kubeadm)
- Per-node overhead: ~200MB RAM
- Can run on Raspberry Pi, VPS, or minimal hardware

### Storage
- **MinIO**: 4x 100GB = 400GB raw, 200GB usable (EC:2)
- **Prometheus**: 50GB per site (short retention) + MinIO long-term
- **Loki**: Minimal local, bulk in MinIO
- **Registry**: 100GB per site

### Bandwidth
- **Replication**: <10GB/month (images, small objects)
- **Metrics**: <1GB/month (Thanos)
- **Logs**: <5GB/month (Loki)
- Works fine on residential internet (both sites)

## Troubleshooting

### Split-Brain Detection
```bash
# Check Vault Raft peers
vault operator raft list-peers

# Check MinIO cluster status
mc admin info minio-cluster

# Check ZeroTier connectivity
zerotier-cli peers | grep 10.147.17
```

### Force Failover (Testing)
```bash
# Simulate Site A failure
# On Site A nodes:
sudo systemctl stop zerotier-one

# Watch Vault fail over
kubectl logs -n vault vault-b-1 -f

# Restore connectivity
sudo systemctl start zerotier-one
```

### Data Reconciliation Check
```bash
# Vault Raft
vault operator raft autopilot state

# MinIO healing status
mc admin heal minio-cluster --verbose

# Registry sync
harbor-cli replication list
```

## Next Steps

1. **Review this architecture** - Validate assumptions and service choices
2. **Start with Phase 2** - Provision Site B infrastructure
3. **Implement incrementally** - One shared service at a time
4. **Test thoroughly** - Simulate failures before production use
5. **Document operations** - Create runbooks for common tasks

## References

- [HashiCorp Vault Raft Storage](https://developer.hashicorp.com/vault/docs/configuration/storage/raft)
- [MinIO Distributed Mode](https://min.io/docs/minio/linux/operations/install-deploy-manage/deploy-minio-multi-node-multi-drive.html)
- [Thanos Documentation](https://thanos.io/tip/thanos/design.md/)
- [Harbor Replication](https://goharbor.io/docs/2.9.0/administration/configuring-replication/)
- [ZeroTier Manual](https://docs.zerotier.com/zerotier/manual/)
