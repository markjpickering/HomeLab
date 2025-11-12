# DNS Architecture for Multi-Site HomeLab (k3s)

This document describes the DNS infrastructure for automatic service discovery across both k3s sites with memorable URLs via proxy.

**k3s Integration:**
- Leverages k3s built-in Traefik for ingress/proxy
- Uses k3s ServiceLB (Klipper-lb) for LoadBalancer services
- Deploys via k3s manifests and HelmChart CRDs

## Overview

**DNS Server**: Technitium DNS Server (Web GUI, API, Docker-friendly)
**Service Discovery**: Automatic DNS registration via external-dns
**Naming Convention**: Prefix-based with proxy shortcuts
**Deployment**: Active/Passive with zone replication

## Why Technitium?

✅ **Web GUI** - Easy management interface
✅ **API-driven** - Automation via external-dns
✅ **Zone replication** - Primary/secondary setup
✅ **DHCP integration** - Optional for physical devices
✅ **Docker/Kubernetes ready** - Easy deployment
✅ **Split DNS** - Different answers for internal/external
✅ **Lightweight** - .NET, low resource usage

**Alternatives considered:**
- Pi-hole (DNS + ad-blocking, but limited API)
- PowerDNS (powerful but more complex)
- CoreDNS (Kubernetes-native but no GUI)
- BIND9 (traditional but no modern GUI)

## DNS Zones and Naming Convention

### Domain Structure

The HomeLab uses **site-specific domains** for maximum flexibility:

- **Primary site domain**: `pickers.hl` (configurable via `HOMELAB_PRIMARY_DNS_DOMAIN`)
- **Secondary site domain**: `sheila.hl` (configurable via `HOMELAB_SECONDARY_DNS_DOMAIN`)
- **Shared services domain**: `services.hl.internal` (configurable via `HOMELAB_SHARED_DNS_DOMAIN`)
- **Base domain**: `homelab.internal` (configurable via `HOMELAB_DNS_DOMAIN`)

Each site has its own independent DNS zone, allowing:
- Different TLDs per site (`.hl`, `.home`, `.local`, etc.)
- Separate zone management
- Site-specific DNS policies
- Easy migration or domain changes per site

**Configuration**: Set in `boostrap/config.sh`:
```bash
export HOMELAB_PRIMARY_DNS_DOMAIN="pickers.hl"
export HOMELAB_SECONDARY_DNS_DOMAIN="sheila.hl"
export HOMELAB_SHARED_DNS_DOMAIN="services.hl.internal"
export HOMELAB_DNS_DOMAIN="homelab.internal"  # Base/fallback
```

### Service Naming Convention

#### Site-Specific Services
Format: `<service>.<site-domain>`

Examples:
- `argocd.pickers.hl` → 10.147.17.10:8080 (Primary site)
- `argocd.sheila.hl` → 10.147.17.20:8080 (Secondary site)
- `grafana.pickers.hl` → 10.147.17.11:3000
- `grafana.sheila.hl` → 10.147.17.21:3000

#### Shared Services
Format: `<service>.services.hl.internal`

Examples:
- `vault.services.hl.internal` → 10.147.17.100 (VIP)
- `registry.services.hl.internal` → 10.147.17.101 (VIP)
- `minio.services.hl.internal` → 10.147.17.102 (distributed endpoint)

#### Proxy Shortcuts (Memorable URLs)
Format: `<service>.homelab.internal` (uses base domain)

Examples:
- `vault.homelab.internal` → Proxy → `vault.services.hl.internal`
- `argocd.homelab.internal` → Proxy → Active site's ArgoCD
- `grafana.homelab.internal` → Proxy → Unified view (Thanos/multi-cluster)

### DNS Record Structure

```
# Primary site zone (pickers.hl)
pickers.hl                          SOA, NS records
├── argocd.pickers.hl               A record → 10.147.17.10
├── grafana.pickers.hl              A record → 10.147.17.11
├── traefik.pickers.hl              A record → 10.147.17.11
└── *.pickers.hl                    Wildcard for k8s ingress

# Secondary site zone (sheila.hl)
sheila.hl                           SOA, NS records
├── argocd.sheila.hl                A record → 10.147.17.20
├── grafana.sheila.hl               A record → 10.147.17.21
├── traefik.sheila.hl               A record → 10.147.17.21
└── *.sheila.hl                     Wildcard for k8s ingress

# Shared services zone (services.hl.internal)
services.hl.internal             SOA, NS records
├── vault.services.hl.internal   A record → 10.147.17.100
├── registry.services.hl.internal A record → 10.147.17.101
└── minio.services.hl.internal   A record → 10.147.17.102

# Base zone for shortcuts (homelab.internal)
homelab.internal                    SOA, NS records
├── vault.homelab.internal          CNAME → vault.services.hl.internal
├── argocd.homelab.internal         CNAME → argocd.pickers.hl (or load balanced)
└── grafana.homelab.internal        CNAME → grafana.pickers.hl
```

**Note**: Each site uses an independent DNS zone. This allows complete isolation and different domain strategies per site.

## Architecture Components

### 1. Technitium DNS Server

**Deployment**: 
- Primary instance at Site A (Docker or k8s pod)
- Secondary instance at Site B (zone replication)
- Both accessible via ZeroTier

**Configuration:**
```yaml
# Primary DNS (Site A)
IP: 10.147.17.5
Role: Primary authoritative for pickers.hl, services.hl.internal, homelab.internal
Zones: pickers.hl (primary site), services.hl.internal, homelab.internal
Zone Transfer: Allow 10.147.17.25 (Site B secondary)

# Secondary DNS (Site B)
IP: 10.147.17.25
Role: Primary authoritative for sheila.hl; Secondary for shared zones
Zones: sheila.hl (secondary site), services.hl.internal (replicated), homelab.internal (replicated)
Zone Transfer: From 10.147.17.5 (for shared zones)
```

**High Availability:**
- Clients configured with both DNS servers
- If primary fails, queries go to secondary
- Zone updates queue until primary returns

### 2. External-DNS (Kubernetes)

**Purpose**: Automatically create DNS records for Kubernetes services/ingresses

**Deployment**: 
- One instance per cluster (site-a, site-b)
- Each updates Technitium via API
- Uses annotations to control DNS records

**Configuration per Site:**

```yaml
# external-dns-site-a (in site A cluster)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: external-dns
  namespace: kube-system
spec:
  template:
    spec:
      containers:
      - name: external-dns
        image: registry.k8s.io/external-dns/external-dns:v0.14.0
        args:
        - --source=service
        - --source=ingress
        - --provider=webhook
        - --webhook-provider-url=http://technitium-webhook:8888
        - --domain-filter=pickers.hl
        - --txt-owner-id=primary
        - --policy=sync
        env:
        - name: TECHNITIUM_DNS_SERVER
          value: "http://10.147.17.5:5380"
        - name: TECHNITIUM_API_TOKEN
          valueFrom:
            secretKeyRef:
              name: technitium-token
              key: token
```

Secondary site uses same config but with:
- `--domain-filter=sheila.hl`
- `--txt-owner-id=secondary`
- Points to secondary DNS: `10.147.17.25:5380`

Shared services use:
- `--domain-filter=services.hl.internal`
- `--txt-owner-id=shared`
- Points to primary DNS: `10.147.17.5:5380`

### 3. Service Proxy (k3s Built-in Traefik)

**Purpose**: Provide memorable shortcuts without site/shared prefix

**Deployment**: k3s includes Traefik v2 by default
- Runs as DaemonSet on all nodes
- Configured via HelmChartConfig CRD
- Per-cluster deployment (not shared across sites)

**Web Dashboard**: Built-in read-only dashboard for monitoring routes and services
- Access: `http://traefik.pickers.hl/dashboard/` (Primary site)
- Access: `http://traefik.sheila.hl/dashboard/` (Secondary site)
- Features: Real-time topology, health checks, metrics
- Authentication: Basic auth (configured via Middleware CRD)

**k3s Traefik Benefits:**
- No separate installation required
- Integrated with k3s ServiceLB for LoadBalancer IPs
- Automatic certificate management support
- Lightweight and optimized for edge/HomeLab

**How it works:**
```
User requests: vault.homelab.internal
  ↓
DNS returns: 10.147.17.200 (proxy VIP)
  ↓
Proxy (Traefik) inspects hostname
  ↓
Routes to: vault.services.hl.internal (10.147.17.100)
```

**Traefik Configuration:**
```yaml
# Proxy routes
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: vault-shortcut
  namespace: shared-services
spec:
  entryPoints:
  - web
  - websecure
  routes:
  - match: Host(`vault.homelab.internal`)
    kind: Rule
    services:
    - name: vault
      namespace: shared-services
      port: 8200
---
# ArgoCD shortcut (intelligent routing)
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: argocd-shortcut
spec:
  entryPoints:
  - web
  - websecure
  routes:
  - match: Host(`argocd.homelab.internal`)
    kind: Rule
    services:
    # Weighted round-robin or active site preference
    - name: argocd-site-a
      namespace: argocd
      port: 80
      weight: 10
    - name: argocd-site-b
      namespace: argocd
      port: 80
      weight: 1
```

## Automatic Service Registration

### Kubernetes Service with DNS Annotation

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app
  namespace: default
  annotations:
    external-dns.alpha.kubernetes.io/hostname: "myapp.site-a.homelab.internal"
    external-dns.alpha.kubernetes.io/ttl: "300"
spec:
  type: LoadBalancer
  loadBalancerIP: 10.147.17.50  # ZeroTier IP
  ports:
  - port: 80
    targetPort: 8080
  selector:
    app: my-app
```

**What happens:**
1. External-DNS detects new service with annotation
2. Calls Technitium API: `POST /api/zones/records/add`
3. Creates A record: `myapp.site-a.homelab.internal` → `10.147.17.50`
4. Secondary DNS syncs record via zone transfer
5. Service immediately accessible via DNS

### Shared Service Example

```yaml
apiVersion: v1
kind: Service
metadata:
  name: vault
  namespace: shared-services
  annotations:
    external-dns.alpha.kubernetes.io/hostname: "vault.services.hl.internal"
spec:
  type: LoadBalancer
  loadBalancerIP: 10.147.17.100  # VIP managed by keepalived
  ports:
  - port: 8200
```

### Proxy Shortcut (Manual)

Add CNAME records in Technitium:
```
vault.homelab.internal      CNAME   vault.services.hl.internal
argocd.homelab.internal     CNAME   proxy.services.hl.internal
grafana.homelab.internal    CNAME   grafana.services.hl.internal
```

Or proxy handles routing without DNS change.

## Authentication and Security

### Built-in Authentication

Technitium DNS Server includes built-in authentication:
- **Admin account**: Username/password for web UI access
- **API tokens**: Bearer tokens for programmatic access
- **TSIG keys**: Secure zone transfers and dynamic updates

### Authentik SSO Integration (Recommended)

For centralized authentication across all HomeLab services, we add Authentik forward-auth protection to Technitium's web UI.

**Benefits:**
- Single sign-on across all services
- Google/Microsoft OAuth integration
- Multi-factor authentication support
- Centralized user management
- Audit logging of access

**Architecture:**
```
User → dns.homelab.internal
  ↓
Traefik IngressRoute
  ↓
Authentik Forward-Auth Middleware (checks session)
  ↓
Technitium Web UI (if authenticated)
```

**Deployment:**

The Authentik forward-auth configuration is deployed separately after both Authentik and Technitium are running:

```bash
# Deploy after Authentik and Technitium are both running
kubectl apply -f k8s-apps/dns/technitium-auth.yaml
```

This creates:
1. **Traefik Middleware** - Forward-auth to Authentik
2. **Protected IngressRoutes** - Web UI accessible only after SSO login
3. **Unprotected DNS service** - DNS queries (port 53) remain unauthenticated

**Configuration in Authentik:**

1. Create a new application in Authentik:
   - Name: Technitium DNS
   - Provider: Proxy Provider (Forward Auth)
   - External URL: `http://dns.homelab.internal` or `http://dns-primary.services.hl.internal`
   - Forward auth mode: Traefik

2. Assign users/groups who should have DNS admin access

3. The Traefik middleware will automatically redirect unauthenticated users to Authentik login

**Access Flow:**
1. Navigate to `http://dns.homelab.internal` or `http://dns-primary.services.hl.internal`
2. If not logged in, redirected to Authentik SSO login
3. Login with Google/Microsoft or Authentik credentials
4. Redirected back to Technitium web UI
5. Session persists across all protected services

**Security Notes:**
- DNS queries (port 53) remain unauthenticated (required for DNS to function)
- Web UI and API (port 5380) are protected by Authentik SSO
- API tokens still work for automation (external-dns, scripts)
- TSIG keys protect zone transfers between primary/secondary DNS

## Implementation Guide

### Phase 1: Deploy Technitium DNS Server

#### Option A: Docker Compose (Bootstrap Phase - Before k3s)

Use this during initial bootstrap when k3s doesn't exist yet.

```yaml
# boostrap/technitium/docker-compose.yml
version: '3.8'

services:
  technitium-primary:
    image: technitium/dns-server:latest
    container_name: technitium-primary
    hostname: dns-primary
    ports:
      - "5380:5380"     # Web UI
      - "53:53/udp"     # DNS
      - "53:53/tcp"     # DNS (TCP)
    environment:
      - DNS_SERVER_DOMAIN=dns-primary.homelab.internal
      - DNS_SERVER_ADMIN_PASSWORD=${TECHNITIUM_ADMIN_PASSWORD}
      - DNS_SERVER_PREFER_IPV6=false
    volumes:
      - ./config:/etc/dns
      - ./logs:/var/log/dns
    networks:
      zerotier:
        ipv4_address: 10.147.17.5
    restart: unless-stopped

networks:
  zerotier:
    external: true
    name: zerotier-bridge  # Bridge to ZeroTier interface
```

**Setup steps:**
```bash
# Generate admin password
export TECHNITIUM_ADMIN_PASSWORD=$(openssl rand -base64 32)
echo "TECHNITIUM_ADMIN_PASSWORD=${TECHNITIUM_ADMIN_PASSWORD}" > .env

# Start server
docker-compose up -d

# Access web UI
open http://10.147.17.5:5380
```

#### Option B: k3s Deployment (Production - After k3s Bootstrap)

Deploy Technitium as a k3s workload after clusters are running.

```yaml
# k8s-apps/dns/technitium-primary.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: technitium-primary
  namespace: dns-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: technitium-dns
      role: primary
  template:
    metadata:
      labels:
        app: technitium-dns
        role: primary
    spec:
      nodeSelector:
        site: site-a
      containers:
      - name: dns-server
        image: technitium/dns-server:latest
        ports:
        - containerPort: 5380
          name: web
        - containerPort: 53
          name: dns-udp
          protocol: UDP
        - containerPort: 53
          name: dns-tcp
          protocol: TCP
        env:
        - name: DNS_SERVER_ADMIN_PASSWORD
          valueFrom:
            secretKeyRef:
              name: technitium-secrets
              key: admin-password
        volumeMounts:
        - name: config
          mountPath: /etc/dns
        - name: logs
          mountPath: /var/log/dns
      volumes:
      - name: config
        persistentVolumeClaim:
          claimName: technitium-config
      - name: logs
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: technitium-primary
  namespace: dns-system
  annotations:
    external-dns.alpha.kubernetes.io/hostname: "dns-primary.services.hl.internal"
spec:
  type: LoadBalancer
  loadBalancerIP: 10.147.17.5
  ports:
  - name: web
    port: 5380
    targetPort: 5380
  - name: dns-udp
    port: 53
    protocol: UDP
    targetPort: 53
  - name: dns-tcp
    port: 53
    protocol: TCP
    targetPort: 53
  selector:
    app: technitium-dns
    role: primary
```

### Phase 2: Configure Primary Zone

**Via Web UI:**
1. Login to http://10.147.17.5:5380
2. Go to **Zones** → **Add Zone**
3. Configure:
   - Zone: `homelab.internal`
   - Type: Primary Zone
   - Enable DNSSEC: Optional (adds complexity)
4. Create subdomains:
   - `site-a.homelab.internal`
   - `site-b.homelab.internal`
   - `services.hl.internal`

**Via API:**
```bash
# Create primary zone
curl -X POST "http://10.147.17.5:5380/api/zones/create" \
  -H "Authorization: Bearer ${TECHNITIUM_API_TOKEN}" \
  -d "domain=homelab.internal&type=Primary"

# Create subdomain zones
for subdomain in site-a site-b shared; do
  curl -X POST "http://10.147.17.5:5380/api/zones/create" \
    -H "Authorization: Bearer ${TECHNITIUM_API_TOKEN}" \
    -d "domain=${subdomain}.homelab.internal&type=Primary"
done
```

### Phase 3: Deploy Secondary DNS (Site B)

```yaml
# k8s-apps/dns/technitium-secondary.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: technitium-secondary
  namespace: dns-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: technitium-dns
      role: secondary
  template:
    metadata:
      labels:
        app: technitium-dns
        role: secondary
    spec:
      nodeSelector:
        site: site-b
      containers:
      - name: dns-server
        image: technitium/dns-server:latest
        ports:
        - containerPort: 5380
        - containerPort: 53
          protocol: UDP
        - containerPort: 53
          protocol: TCP
        volumeMounts:
        - name: config
          mountPath: /etc/dns
---
apiVersion: v1
kind: Service
metadata:
  name: technitium-secondary
  namespace: dns-system
spec:
  type: LoadBalancer
  loadBalancerIP: 10.147.17.25
  ports:
  - name: web
    port: 5380
  - name: dns-udp
    port: 53
    protocol: UDP
  - name: dns-tcp
    port: 53
    protocol: TCP
  selector:
    app: technitium-dns
    role: secondary
```

**Configure zone transfer:**
1. Primary DNS → Settings → Zone Transfer
   - Add allowed IP: `10.147.17.25`
2. Secondary DNS → Zones → Add Zone
   - Type: Secondary Zone
   - Primary server: `10.147.17.5`
   - Zone: `homelab.internal`

### Phase 4: Deploy external-dns

```yaml
# k8s-apps/dns/external-dns-site-a.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: external-dns
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: external-dns
rules:
- apiGroups: [""]
  resources: ["services", "endpoints", "pods"]
  verbs: ["get", "watch", "list"]
- apiGroups: ["extensions", "networking.k8s.io"]
  resources: ["ingresses"]
  verbs: ["get", "watch", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: external-dns
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: external-dns
subjects:
- kind: ServiceAccount
  name: external-dns
  namespace: kube-system
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: external-dns
  namespace: kube-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: external-dns
  template:
    metadata:
      labels:
        app: external-dns
    spec:
      serviceAccountName: external-dns
      containers:
      - name: external-dns
        image: registry.k8s.io/external-dns/external-dns:v0.14.0
        args:
        - --source=service
        - --source=ingress
        - --provider=rfc2136
        - --rfc2136-host=10.147.17.5
        - --rfc2136-port=53
        - --rfc2136-zone=site-a.homelab.internal
        - --rfc2136-tsig-secret=${TECHNITIUM_TSIG_KEY}
        - --rfc2136-tsig-secret-alg=hmac-sha256
        - --rfc2136-tsig-keyname=externaldns-key
        - --txt-owner-id=site-a
        - --domain-filter=site-a.homelab.internal
        - --policy=sync
        env:
        - name: TECHNITIUM_TSIG_KEY
          valueFrom:
            secretKeyRef:
              name: external-dns-tsig
              key: tsig-secret
```

**Generate TSIG key for authentication:**
```bash
# Generate TSIG key
tsig-keygen -a hmac-sha256 externaldns-key

# Add to Technitium via Web UI:
# Settings → TSIG → Add Key
# Name: externaldns-key
# Algorithm: HMAC-SHA256
# Secret: <generated key>
```

### Phase 5: Configure k3s Built-in Traefik

k3s comes with Traefik pre-installed. We just need to configure it.

#### Step 1: Enable Traefik Dashboard

```yaml
# k8s-apps/traefik/config.yaml
# Apply this to configure k3s's built-in Traefik
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: traefik
  namespace: kube-system
spec:
  valuesContent: |-
    dashboard:
      enabled: true
    ports:
      traefik:
        expose: true
      web:
        redirectTo: websecure
      websecure:
        tls:
          enabled: true
    additionalArguments:
      - "--api.dashboard=true"
      - "--providers.kubernetescrd.allowCrossNamespace=true"
```

#### Step 2: Create Service Shortcuts (IngressRoutes)

```yaml
# k8s-apps/traefik/shortcuts.yaml
# Proxy shortcuts for memorable URLs
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: vault-shortcut
  namespace: shared-services
spec:
  entryPoints:
  - web
  - websecure
  routes:
  - match: Host(`vault.homelab.internal`)
    kind: Rule
    services:
    - name: vault
      port: 8200
---
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: argocd-shortcut
  namespace: shared-services
spec:
  entryPoints:
  - web
  - websecure
  routes:
  - match: Host(`argocd.homelab.internal`)
    kind: Rule
    services:
    # Weighted routing to prefer Site A
    - name: argocd-site-a
      namespace: argocd
      port: 80
      weight: 10
    - name: argocd-site-b
      namespace: argocd
      port: 80
      weight: 1
---
# Traefik Dashboard IngressRoute
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: traefik-dashboard
  namespace: kube-system
spec:
  entryPoints:
  - web
  routes:
  - match: Host(`traefik.site-a.homelab.internal`)
    kind: Rule
    services:
    - name: api@internal
      kind: TraefikService
    middlewares:
    - name: dashboard-auth
---
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: dashboard-auth
  namespace: kube-system
spec:
  basicAuth:
    secret: traefik-dashboard-auth
---
# Secret for basic auth (create this manually or via SOPS)
apiVersion: v1
kind: Secret
metadata:
  name: traefik-dashboard-auth
  namespace: kube-system
type: Opaque
data:
  # Generated with: htpasswd -nb admin password | base64
  users: YWRtaW46JGFwcjEkSC82dXNCSCRTRGxCeElsSDBpbkszVzB0Ni8udTEK
```

**Add wildcard DNS for shortcuts:**
```bash
# In Technitium, add A record
*.homelab.internal  →  10.147.17.200 (proxy VIP)
```

## Client Configuration

### k3s Nodes
```bash
# Update /etc/resolv.conf via cloud-init or Ansible
# This ensures k3s pods can resolve homelab.internal domains
nameserver 10.147.17.5    # Primary DNS
nameserver 10.147.17.25   # Secondary DNS
search homelab.internal

# k3s will also use these DNS servers for pod DNS resolution
# CoreDNS in k3s will forward homelab.internal queries to Technitium
```

### Workstation/Laptop
**Windows:**
```powershell
# Set DNS for ZeroTier adapter
$adapter = Get-NetAdapter | Where-Object {$_.InterfaceDescription -like "*ZeroTier*"}
Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses ("10.147.17.5","10.147.17.25")
```

**Linux/Mac:**
```bash
# Add to /etc/resolv.conf or NetworkManager
nameserver 10.147.17.5
nameserver 10.147.17.25
search homelab.internal
```

## Testing

### Test DNS Resolution
```bash
# Test site-specific service
dig argocd.site-a.homelab.internal @10.147.17.5

# Test shared service
dig vault.services.hl.internal @10.147.17.5

# Test shortcut
dig argocd.homelab.internal @10.147.17.5

# Test from any ZeroTier client
nslookup vault.homelab.internal
```

### Test Automatic Registration
```bash
# Deploy test service
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: test-app
  annotations:
    external-dns.alpha.kubernetes.io/hostname: "test.site-a.homelab.internal"
spec:
  type: LoadBalancer
  loadBalancerIP: 10.147.17.99
  ports:
  - port: 80
  selector:
    app: test
EOF

# Wait 60 seconds
sleep 60

# Check DNS
dig test.site-a.homelab.internal @10.147.17.5
# Should return: 10.147.17.99
```

### Test Failover
```bash
# Query both DNS servers
dig vault.services.hl.internal @10.147.17.5
dig vault.services.hl.internal @10.147.17.25

# Should return same result (zone replication working)

# Stop primary DNS
docker stop technitium-primary

# Queries should still work (secondary responds)
dig vault.services.hl.internal
```

## Maintenance

### Adding Manual DNS Records
**Via Web UI:** Zones → homelab.internal → Add Record

**Via API:**
```bash
curl -X POST "http://10.147.17.5:5380/api/zones/records/add" \
  -H "Authorization: Bearer ${TECHNITIUM_API_TOKEN}" \
  -d "domain=myservice.services.hl.internal" \
  -d "type=A" \
  -d "ipAddress=10.147.17.50" \
  -d "ttl=300"
```

### Monitoring DNS Health
```yaml
# Prometheus ServiceMonitor for Technitium
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: technitium-dns
spec:
  selector:
    matchLabels:
      app: technitium-dns
  endpoints:
  - port: web
    path: /api/stats/get
    interval: 30s
```

### Backup and Restore
```bash
# Backup (primary DNS)
docker exec technitium-primary tar czf /backup.tar.gz /etc/dns
docker cp technitium-primary:/backup.tar.gz ./dns-backup-$(date +%F).tar.gz

# Restore
docker cp ./dns-backup.tar.gz technitium-primary:/backup.tar.gz
docker exec technitium-primary tar xzf /backup.tar.gz -C /
docker restart technitium-primary
```

## Integration with Multi-Site Architecture

This DNS setup integrates with the multi-site architecture:

1. **Shared services** use `.services.hl.internal` with VIPs
2. **Site-specific services** use `.site-{a,b}.homelab.internal`
3. **Proxy shortcuts** provide memorable URLs
4. **Zone replication** ensures DNS survives site failure
5. **External-DNS** automatically registers k8s services

## Next Steps

1. Deploy Technitium DNS at Site A (Phase 1)
2. Configure primary zones (Phase 2)
3. Deploy external-dns in both clusters (Phase 4)
4. Test automatic service registration
5. Deploy secondary DNS at Site B (Phase 3)
6. Deploy service proxy (Phase 5)
7. Configure client DNS settings
8. Deploy Authentik SSO (see `docs/AUTHENTICATION.md`)
9. Apply Authentik forward-auth protection (`kubectl apply -f k8s-apps/dns/technitium-auth.yaml`)
10. Configure Technitium application in Authentik web UI

## References

- [Technitium DNS Server](https://technitium.com/dns/)
- [External-DNS Documentation](https://github.com/kubernetes-sigs/external-dns)
- [Traefik Documentation](https://doc.traefik.io/traefik/)
- [Authentik Documentation](https://goauthentik.io/docs/)
- [RFC 2136 (Dynamic DNS Updates)](https://datatracker.ietf.org/doc/html/rfc2136)
