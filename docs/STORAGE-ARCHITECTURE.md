# Storage Architecture - Persistent Data Strategy

This document describes how to ensure non-volatile data survives cluster changes, node failures, and complete rebuilds.

## Overview

**Problem**: k3s clusters are ephemeral. If you destroy and recreate nodes, all data is lost.

**Solution**: Multi-layered storage strategy:
1. **External persistent storage** (MinIO distributed across sites)
2. **Backup automation** (Velero with MinIO backend)
3. **GitOps for configuration** (Everything in Git)
4. **Secrets management** (External Secrets Operator + Vault)

## Storage Layers

### Layer 1: Local Ephemeral Storage

**Purpose**: Temporary data that can be lost

**k3s Default**: `local-path` provisioner (hostPath)
- Fast, local to node
- **Lost when node is destroyed**

**Use cases:**
- Cache directories
- Temporary files
- Logs (before shipping to Loki)
- Non-critical application state

### Layer 2: Distributed Persistent Storage (MinIO)

**Purpose**: Persistent data that survives cluster changes

**Architecture**: MinIO in distributed mode across both sites
- 4 nodes (2 per site)
- Erasure coding EC:2 (survives 1 site failure)
- S3-compatible API
- **Data persists even if entire cluster is destroyed**

**Use cases:**
- Database backups
- Application data
- Docker registry blobs
- Prometheus long-term storage (via Thanos)
- Loki log archives
- Velero backups

### Layer 3: External Backups

**Purpose**: Disaster recovery

**Tools**: Velero (k8s backup) + restic (file-level backups)
- Backs up to MinIO
- Can restore entire cluster from backup
- Scheduled automatic backups

**Use cases:**
- Complete cluster state snapshots
- Point-in-time recovery
- Migration to new infrastructure

### Layer 4: Git (GitOps)

**Purpose**: Configuration as code

**What's in Git:**
- All k8s manifests
- Helm charts
- Terraform configs
- Ansible playbooks

**Not in Git:**
- Secrets (use SOPS encryption)
- Binary data
- Databases

## MinIO Distributed Storage Setup

### Architecture

```
MinIO Distributed Cluster (4 nodes)

Site Primary:                    Site Secondary:
┌─────────────────┐             ┌─────────────────┐
│ minio-primary-1 │             │ minio-sec-1     │
│ /data (100GB)   │◄───────────►│ /data (100GB)   │
└─────────────────┘             └─────────────────┘
         │                               │
         │        Erasure Coding         │
         │        EC:2 (2+2 parity)      │
         │                               │
┌─────────────────┐             ┌─────────────────┐
│ minio-primary-2 │             │ minio-sec-2     │
│ /data (100GB)   │◄───────────►│ /data (100GB)   │
└─────────────────┘             └─────────────────┘

Total Capacity: 200GB usable (400GB raw)
Survives: 2 node failures (or 1 site failure)
```

### Deployment

```yaml
# k8s-apps/storage/minio-distributed.yaml
apiVersion: v1
kind: Service
metadata:
  name: minio
  namespace: storage
spec:
  type: LoadBalancer
  loadBalancerIP: 10.147.17.102  # Shared VIP
  ports:
    - name: api
      port: 9000
      targetPort: 9000
    - name: console
      port: 9001
      targetPort: 9001
  selector:
    app: minio
---
apiVersion: v1
kind: Service
metadata:
  name: minio-primary-1
  namespace: storage
spec:
  clusterIP: None  # Headless
  ports:
    - port: 9000
  selector:
    app: minio
    site: primary
    instance: "1"
---
apiVersion: v1
kind: Service
metadata:
  name: minio-primary-2
  namespace: storage
spec:
  clusterIP: None
  ports:
    - port: 9000
  selector:
    app: minio
    site: primary
    instance: "2"
---
apiVersion: v1
kind: Service
metadata:
  name: minio-sec-1
  namespace: storage
spec:
  clusterIP: None
  ports:
    - port: 9000
  selector:
    app: minio
    site: secondary
    instance: "1"
---
apiVersion: v1
kind: Service
metadata:
  name: minio-sec-2
  namespace: storage
spec:
  clusterIP: None
  ports:
    - port: 9000
  selector:
    app: minio
    site: secondary
    instance: "2"
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: minio-primary
  namespace: storage
spec:
  serviceName: minio
  replicas: 2
  selector:
    matchLabels:
      app: minio
      site: primary
  template:
    metadata:
      labels:
        app: minio
        site: primary
    spec:
      nodeSelector:
        site: primary
      containers:
        - name: minio
          image: quay.io/minio/minio:latest
          command:
            - /bin/sh
            - -c
          args:
            - minio server
              http://minio-primary-{0...1}.storage.svc.cluster.local/data
              http://minio-sec-{0...1}.storage.svc.cluster.local/data
              --console-address ":9001"
          env:
            - name: MINIO_ROOT_USER
              valueFrom:
                secretKeyRef:
                  name: minio-credentials
                  key: root-user
            - name: MINIO_ROOT_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: minio-credentials
                  key: root-password
          ports:
            - containerPort: 9000
              name: api
            - containerPort: 9001
              name: console
          volumeMounts:
            - name: data
              mountPath: /data
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: local-path
        resources:
          requests:
            storage: 100Gi
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: minio-secondary
  namespace: storage
spec:
  serviceName: minio
  replicas: 2
  selector:
    matchLabels:
      app: minio
      site: secondary
  template:
    metadata:
      labels:
        app: minio
        site: secondary
    spec:
      nodeSelector:
        site: secondary
      containers:
        - name: minio
          image: quay.io/minio/minio:latest
          command:
            - /bin/sh
            - -c
          args:
            - minio server
              http://minio-primary-{0...1}.storage.svc.cluster.local/data
              http://minio-sec-{0...1}.storage.svc.cluster.local/data
              --console-address ":9001"
          env:
            - name: MINIO_ROOT_USER
              valueFrom:
                secretKeyRef:
                  name: minio-credentials
                  key: root-user
            - name: MINIO_ROOT_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: minio-credentials
                  key: root-password
          ports:
            - containerPort: 9000
            - containerPort: 9001
          volumeMounts:
            - name: data
              mountPath: /data
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: local-path
        resources:
          requests:
            storage: 100Gi
```

**Key Points:**
- StatefulSets ensure stable pod identities
- VolumeClaimTemplates create persistent volumes
- Even if cluster is destroyed, volumes can be reattached
- Data is distributed across 4 nodes with erasure coding

## Velero Backup System

### Install Velero

```bash
# Install Velero CLI
wget https://github.com/vmware-tanzu/velero/releases/download/v1.12.0/velero-v1.12.0-linux-amd64.tar.gz
tar -xvf velero-v1.12.0-linux-amd64.tar.gz
sudo mv velero-v1.12.0-linux-amd64/velero /usr/local/bin/

# Install Velero in k3s with MinIO backend
velero install \
    --provider aws \
    --plugins velero/velero-plugin-for-aws:v1.8.0 \
    --bucket velero-backups \
    --secret-file ./minio-credentials \
    --use-volume-snapshots=false \
    --backup-location-config \
        region=minio,s3ForcePathStyle="true",s3Url=http://minio.storage.svc.cluster.local:9000
```

### Velero Configuration

```yaml
# k8s-apps/backup/velero-schedule.yaml
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: daily-backup
  namespace: velero
spec:
  schedule: "0 2 * * *"  # 2 AM daily
  template:
    includedNamespaces:
      - "*"
    excludedNamespaces:
      - velero
      - kube-system
    snapshotVolumes: true
    ttl: 720h  # 30 days retention
---
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: hourly-backup-critical
  namespace: velero
spec:
  schedule: "0 * * * *"  # Every hour
  template:
    includedNamespaces:
      - storage
      - vault
      - shared-services
    snapshotVolumes: true
    ttl: 168h  # 7 days retention
```

## Stateful Application Examples

### PostgreSQL with Persistent Storage

```yaml
# k8s-apps/databases/postgres.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-data
  namespace: databases
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 20Gi
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: databases
spec:
  serviceName: postgres
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: postgres:15-alpine
          env:
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: postgres-credentials
                  key: password
            - name: PGDATA
              value: /var/lib/postgresql/data/pgdata
          ports:
            - containerPort: 5432
          volumeMounts:
            - name: data
              mountPath: /var/lib/postgresql/data
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: postgres-data
---
# Backup job to MinIO
apiVersion: batch/v1
kind: CronJob
metadata:
  name: postgres-backup
  namespace: databases
spec:
  schedule: "0 3 * * *"  # 3 AM daily
  jobTemplate:
    spec:
      template:
        spec:
          containers:
            - name: backup
              image: postgres:15-alpine
              command:
                - /bin/sh
                - -c
              args:
                - |
                  pg_dump -h postgres -U postgres -Fc > /tmp/backup.dump
                  mc alias set minio http://minio.storage.svc.cluster.local:9000 $MINIO_USER $MINIO_PASSWORD
                  mc cp /tmp/backup.dump minio/postgres-backups/backup-$(date +%Y%m%d-%H%M%S).dump
              env:
                - name: PGPASSWORD
                  valueFrom:
                    secretKeyRef:
                      name: postgres-credentials
                      key: password
                - name: MINIO_USER
                  valueFrom:
                    secretKeyRef:
                      name: minio-credentials
                      key: root-user
                - name: MINIO_PASSWORD
                  valueFrom:
                    secretKeyRef:
                      name: minio-credentials
                      key: root-password
          restartPolicy: OnFailure
```

## Disaster Recovery Procedures

### Scenario 1: Single Node Failure

**Impact**: Minimal (data still available on other nodes)

**Recovery**:
```bash
# Replace node, join cluster
# MinIO automatically heals
mc admin heal minio-cluster --recursive
```

### Scenario 2: Complete Cluster Rebuild

**Impact**: All k8s state lost, but data survives in MinIO volumes

**Recovery**:
```bash
# 1. Bootstrap new k3s clusters
bash boostrap/linux/bootstrap-infrastructure.sh -y

# 2. Redeploy MinIO (reuses existing volumes)
kubectl apply -f k8s-apps/storage/minio-distributed.yaml

# 3. Restore from Velero backup
velero restore create --from-backup daily-backup-20250111

# 4. Verify data
kubectl get pods -A
```

### Scenario 3: Complete Site Loss

**Impact**: Primary or secondary site completely destroyed

**Recovery**:
```bash
# Data still available on remaining site (EC:2 redundancy)

# 1. Continue operating on surviving site
# 2. Rebuild lost site when possible
# 3. Redeploy MinIO nodes
# 4. MinIO heals automatically
mc admin heal minio-cluster --recursive
```

### Scenario 4: Both Sites Down (Worst Case)

**Impact**: Everything offline, but data survives if volumes intact

**Recovery**:
```bash
# If MinIO volumes intact:
# 1. Rebuild both clusters
# 2. Redeploy MinIO with same volume mounts
# 3. Data automatically available

# If volumes lost:
# 1. Rebuild clusters
# 2. Restore from Velero backup (stored in MinIO)
# 3. If MinIO lost, restore from external backup
```

## Data Protection Best Practices

### 1. Volume Lifecycle Management

```yaml
# Always use PersistentVolumeClaims, never hostPath directly
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-app-data
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 10Gi
```

### 2. Backup Verification

```bash
# Weekly backup verification
velero backup describe daily-backup-20250111
velero backup logs daily-backup-20250111

# Test restore in separate namespace
velero restore create test-restore \
  --from-backup daily-backup-20250111 \
  --namespace-mappings default:test-restore
```

### 3. External Backup Strategy

**Sync MinIO to external storage** (S3, Backblaze B2, etc.):

```bash
# mc mirror for continuous sync
mc mirror --watch minio/velero-backups s3/homelab-backups-external
```

### 4. Database-Specific Backups

```yaml
# Application-aware backups in addition to Velero
apiVersion: batch/v1
kind: CronJob
metadata:
  name: db-backup-to-minio
spec:
  schedule: "0 */6 * * *"  # Every 6 hours
  jobTemplate:
    spec:
      template:
        spec:
          containers:
            - name: backup
              image: appropriate/db-image
              command: ["/backup-script.sh"]
```

## Storage Classes

### k3s Default: local-path

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-path
provisioner: rancher.io/local-path
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete  # Change to Retain for safety
```

**Change to Retain** to prevent data loss:

```bash
kubectl patch storageclass local-path \
  -p '{"reclaimPolicy":"Retain"}'
```

### Custom: MinIO-backed (via CSI)

For true cluster-independent storage, consider:
- Longhorn (distributed block storage)
- Rook-Ceph (if you have more resources)

## Monitoring Storage Health

### MinIO Health

```bash
# Check cluster status
mc admin info minio-cluster

# Check healing status
mc admin heal minio-cluster --recursive --dry-run

# Check usage
mc du minio-cluster
```

### Velero Health

```bash
# Check backup status
velero backup get
velero schedule get

# Check for failures
velero backup describe --details
```

### Prometheus Metrics

```yaml
# Monitor PVC usage
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: storage-alerts
spec:
  groups:
    - name: storage
      rules:
        - alert: PVCAlmostFull
          expr: kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes > 0.85
          annotations:
            summary: "PVC {{ $labels.persistentvolumeclaim }} is {{ $value | humanizePercentage }} full"
        
        - alert: MinIONodeDown
          expr: up{job="minio"} == 0
          for: 5m
          annotations:
            summary: "MinIO node {{ $labels.instance }} is down"
```

## Migration Checklist

Before destroying/rebuilding cluster:

- [ ] Run full Velero backup
- [ ] Verify backup completed successfully
- [ ] Export important secrets (vault, minio credentials)
- [ ] Document custom configurations not in Git
- [ ] Sync MinIO to external location (optional)
- [ ] Note all LoadBalancer IPs and DNS entries
- [ ] Save kubeconfig files
- [ ] Test restore in separate namespace

After rebuilding:

- [ ] Verify MinIO volumes reattached correctly
- [ ] Restore from Velero backup
- [ ] Verify all pods running
- [ ] Check application data integrity
- [ ] Update DNS if IPs changed
- [ ] Run application-specific health checks

## Summary

**Data Survival Strategy:**

1. **Critical persistent data** → MinIO distributed storage (survives cluster rebuild)
2. **Cluster state** → Velero backups to MinIO (restore entire cluster)
3. **Configuration** → Git (recreate from code)
4. **Secrets** → Vault (external to cluster) or SOPS (encrypted in Git)
5. **Catastrophic loss** → External backup of MinIO to S3/B2

**Result**: You can completely destroy both clusters and rebuild from scratch with zero data loss.

## See Also

- [MULTI-SITE-ARCHITECTURE.md](MULTI-SITE-ARCHITECTURE.md) - Overall architecture
- [GITHUB-ACTIONS.md](GITHUB-ACTIONS.md) - CI/CD automation
- [MinIO Documentation](https://min.io/docs/minio/linux/index.html)
- [Velero Documentation](https://velero.io/docs/)
