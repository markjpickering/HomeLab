# Infrastructure Operations Guide

Guide for updating configuration, destroying environments, and managing your HomeLab infrastructure.

## Table of Contents

- [Updating Infrastructure](#updating-infrastructure)
- [Destroying Infrastructure](#destroying-infrastructure)
- [Backup and Restore](#backup-and-restore)
- [Common Operations](#common-operations)
- [Controller Migration](#controller-migration)

---

## Updating Infrastructure

### Updating Terraform Configuration

When you change Terraform files (`.tf`):

```bash
cd ~/homelab/k8s-infra/terraform

# Preview changes
terraform plan

# Apply changes
terraform apply

# Or use the bootstrap script (Phase 3 only)
cd ~/homelab/boostrap/linux
bash bootstrap-infrastructure.sh
# Select option 4: Phase 3 only
```

**Common updates:**
- Adding/removing nodes
- Changing node resources (CPU, memory, disk)
- Updating cloud-init configuration
- Modifying network settings

**Example - Add a worker node:**

1. Edit `k8s-infra/terraform/k8s-nodes.tf`:
   ```hcl
   resource "proxmox_virtual_environment_vm" "k8s_workers" {
     count = 4  # Changed from 3 to 4
     # ... rest of config
   }
   ```

2. Apply changes:
   ```bash
   cd ~/homelab/k8s-infra/terraform
   terraform plan  # Review the plan
   terraform apply
   ```

3. Authorize new node in ztnet UI

4. Update Ansible inventory and run playbook:
   ```bash
   # Edit inventory/hosts.ini to add new worker
   cd ~/homelab/k8s-infra/ansible
   ansible-playbook -i inventory/hosts.ini site.yml
   ```

### Updating Ansible Configuration

When you change Ansible playbooks or variables:

```bash
cd ~/homelab/k8s-infra/ansible

# Test connectivity first
ansible -i inventory/hosts.ini all -m ping

# Run playbook with check mode (dry-run)
ansible-playbook -i inventory/hosts.ini site.yml --check

# Apply changes
ansible-playbook -i inventory/hosts.ini site.yml

# Or use the bootstrap script (Phase 4 only)
cd ~/homelab/boostrap/linux
bash bootstrap-infrastructure.sh
# Select option 5: Phase 4 only
```

**Common updates:**
- Kubernetes version upgrades
- Configuration changes
- Installing additional tools/packages
- Security updates

**Target specific hosts:**
```bash
# Only control plane nodes
ansible-playbook -i inventory/hosts.ini site.yml --limit k8s_control_plane

# Only worker nodes
ansible-playbook -i inventory/hosts.ini site.yml --limit k8s_workers

# Single node
ansible-playbook -i inventory/hosts.ini site.yml --limit k8s-worker-1
```

### Updating ztnet Controller

Update to the latest ztnet version:

```bash
cd ~/homelab/boostrap/ztnet

# Pull latest image
docker-compose pull

# Restart with new version
docker-compose up -d

# Check logs
docker-compose logs -f ztnet
```

**Database migrations happen automatically.**

### Updating Bootstrap Scripts

When you update bootstrap scripts, just run them again:

```bash
cd ~/homelab/boostrap/linux

# Re-run to install/update tools
sudo bash bootstrap.sh

# Tools already installed will be skipped
# New tools or updates will be applied
```

---

## Destroying Infrastructure

### Complete Teardown (Everything)

Destroy all infrastructure and reset to clean state:

```bash
# 1. Destroy all Terraform-managed infrastructure
cd ~/homelab/k8s-infra/terraform
terraform destroy
# Type 'yes' to confirm

# 2. Stop and remove ztnet controller
cd ~/homelab/boostrap/ztnet
docker-compose down -v
# -v flag removes volumes (database will be deleted!)

# 3. Remove saved network ID
rm ~/homelab/.zerotier-network-id

# 4. (Optional) Remove ZeroTier client from bootstrap host
sudo apt remove zerotier-one
# Or: curl -s 'https://install.zerotier.com/uninstall.sh' | sudo bash
```

**⚠️ WARNING:** This destroys:
- All VMs/containers
- ztnet controller and database
- ZeroTier network configuration
- Saved network ID

**Not destroyed:**
- Bootstrap host and tools
- Terraform state backups
- Your configuration files

### Destroy Only k8s Cluster

Keep ztnet controller but remove all k8s nodes:

```bash
cd ~/homelab/k8s-infra/terraform

# Preview what will be destroyed
terraform plan -destroy

# Destroy only k8s nodes
terraform destroy

# Nodes will be removed from ZeroTier automatically
```

**To rebuild cluster:**
```bash
terraform apply
# Then authorize nodes in ztnet
# Then run Ansible
```

---

## Controller Migration

You can move the ztnet controller to a permanent host after bootstrap without breaking existing networks by preserving the controller identity.

### Migrate with Bootstrap Hook

Set these variables before running the bootstrap script (or export them and re-run the final step):

```bash
export HOMELAB_ZTNET_REMOTE_HOST="root@10.0.0.5"   # Destination host
export HOMELAB_ZTNET_REMOTE_DIR="/opt/ztnet"       # Destination directory (optional)
```

At the end of the bootstrap, the script will:
- Copy `boostrap/ztnet/docker-compose.yml` and `.env` to the remote host
- Copy `boostrap/ztnet/zerotier-one/` (controller identity) to the remote host
- Ensure Docker is installed on the remote
- Start the ztnet stack remotely and stop the local stack

This preserves the controller identity so all networks and members continue to function. The ztnet UI database is not migrated by default; if you need UI data continuity, back up/restore the Postgres volume.

### Manual Migration Outline

1. Stop local controller: `cd boostrap/ztnet && docker-compose down`
2. Copy `zerotier-one/` directory to the new host
3. Copy `docker-compose.yml` and `.env` to the new host
4. Start the stack on the new host: `docker compose up -d`
5. Verify network/controller functionality

### Destroy Specific Nodes

Remove individual nodes:

```bash
cd ~/homelab/k8s-infra/terraform

# Target specific resource
terraform destroy -target=proxmox_virtual_environment_vm.k8s_workers[2]

# This will destroy k8s-worker-3 (0-indexed)
```

**Don't forget to:**
1. Remove from ztnet (optional - node will just show offline)
2. Remove from Ansible inventory

### Remove ztnet Controller Only

Keep infrastructure but remove controller:

```bash
cd ~/homelab/boostrap/ztnet

# Stop and remove containers + volumes
docker-compose down -v
```

**⚠️ WARNING:** If you remove the controller:
- Nodes will continue working on existing network
- You can't authorize new nodes
- You can't manage network settings
- Backup the database first if you want to restore later!

### Backup Database Before Destroying

```bash
# Backup ztnet database
cd ~/homelab/boostrap/ztnet
docker-compose exec postgres pg_dump -U postgres ztnet > ztnet-backup-$(date +%Y%m%d).sql

# Stop controller (keeps database)
docker-compose down

# Or backup the entire volume
docker run --rm -v ztnet_postgres-data:/data -v $(pwd):/backup ubuntu tar czf /backup/postgres-data-backup.tar.gz /data
```

---

## Backup and Restore

### What to Backup

**Critical files:**
```bash
boostrap/ztnet/.env                    # ztnet secrets
.zerotier-network-id                   # Network ID
k8s-infra/terraform/terraform.tfstate  # Infrastructure state
k8s-infra/ansible/inventory/hosts.ini  # Node inventory
```

**Optional but recommended:**
```bash
# ztnet database
docker-compose exec postgres pg_dump -U postgres ztnet > ztnet-backup.sql

# All ztnet data including ZeroTier controller state
docker run --rm -v ztnet_ztnet-data:/data -v $(pwd):/backup ubuntu tar czf /backup/ztnet-data.tar.gz /data
```

### Backup Script

Create `backup-infrastructure.sh`:

```bash
#!/bin/bash
BACKUP_DIR="$HOME/homelab-backups/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Backup configuration files
cp ~/homelab/boostrap/ztnet/.env "$BACKUP_DIR/"
cp ~/homelab/.zerotier-network-id "$BACKUP_DIR/" 2>/dev/null
cp ~/homelab/k8s-infra/terraform/terraform.tfstate "$BACKUP_DIR/"
cp ~/homelab/k8s-infra/ansible/inventory/hosts.ini "$BACKUP_DIR/"

# Backup ztnet database
cd ~/homelab/boostrap/ztnet
docker-compose exec -T postgres pg_dump -U postgres ztnet > "$BACKUP_DIR/ztnet-db.sql"

echo "✅ Backup completed: $BACKUP_DIR"
ls -lh "$BACKUP_DIR"
```

### Restore from Backup

```bash
# 1. Restore configuration files
cp backup/.env ~/homelab/boostrap/ztnet/
cp backup/.zerotier-network-id ~/homelab/

# 2. Deploy ztnet controller
cd ~/homelab/boostrap/ztnet
docker-compose up -d

# 3. Wait for PostgreSQL to be ready
sleep 10

# 4. Restore database
docker-compose exec -T postgres psql -U postgres -d ztnet < backup/ztnet-db.sql

# 5. Restore infrastructure
cd ~/homelab/k8s-infra/terraform
cp backup/terraform.tfstate .
terraform plan  # Verify state matches reality
```

---

## Common Operations

### Scale Up (Add Nodes)

```bash
# 1. Edit Terraform config
vim ~/homelab/k8s-infra/terraform/k8s-nodes.tf
# Increase count for workers

# 2. Apply changes
cd ~/homelab/k8s-infra/terraform
terraform apply

# 3. Authorize new nodes in ztnet UI

# 4. Add to Ansible inventory
vim ~/homelab/k8s-infra/ansible/inventory/hosts.ini

# 5. Configure new nodes
cd ~/homelab/k8s-infra/ansible
ansible-playbook -i inventory/hosts.ini site.yml --limit <new-node-name>
```

### Scale Down (Remove Nodes)

```bash
# 1. Drain node first (if running k8s)
kubectl drain k8s-worker-3 --ignore-daemonsets --delete-emptydir-data

# 2. Remove from k8s cluster
kubectl delete node k8s-worker-3

# 3. Remove from Ansible inventory
vim ~/homelab/k8s-infra/ansible/inventory/hosts.ini

# 4. Edit Terraform config
vim ~/homelab/k8s-infra/terraform/k8s-nodes.tf
# Decrease count

# 5. Apply changes
cd ~/homelab/k8s-infra/terraform
terraform apply
```

### Rebuild Single Node

```bash
# 1. Destroy the node
cd ~/homelab/k8s-infra/terraform
terraform destroy -target=proxmox_virtual_environment_vm.k8s_workers[1]

# 2. Recreate it
terraform apply -target=proxmox_virtual_environment_vm.k8s_workers[1]

# 3. Authorize in ztnet UI

# 4. Reconfigure with Ansible
cd ~/homelab/k8s-infra/ansible
ansible-playbook -i inventory/hosts.ini site.yml --limit k8s-worker-2
```

### Update Single Node Configuration

```bash
# Run Ansible on specific node
cd ~/homelab/k8s-infra/ansible
ansible-playbook -i inventory/hosts.ini site.yml --limit k8s-worker-1

# Or run specific tasks with tags (if defined in playbook)
ansible-playbook -i inventory/hosts.ini site.yml --tags "docker,kubernetes"
```

### Recreate Network (Preserve Infrastructure)

```bash
# 1. Note your current Network ID
cat ~/homelab/.zerotier-network-id

# 2. Create new network in ztnet UI
# 3. Save new Network ID
echo "new-network-id-here" > ~/homelab/.zerotier-network-id

# 4. Update all nodes
export NEW_NETWORK_ID="new-network-id-here"
cd ~/homelab/k8s-infra/ansible

# Run command on all nodes to join new network
ansible -i inventory/hosts.ini all -b -m shell -a "zerotier-cli leave old-network-id && zerotier-cli join $NEW_NETWORK_ID"

# 5. Authorize all nodes in ztnet UI
# 6. Update IPs in inventory if they changed
```

### Check Infrastructure State

```bash
# Terraform state
cd ~/homelab/k8s-infra/terraform
terraform show
terraform state list

# ztnet status
cd ~/homelab/boostrap/ztnet
docker-compose ps
docker-compose logs --tail=50

# Node connectivity
cd ~/homelab/k8s-infra/ansible
ansible -i inventory/hosts.ini all -m ping

# ZeroTier status on nodes
ansible -i inventory/hosts.ini all -b -m shell -a "zerotier-cli status"
```

---

## Troubleshooting

### Terraform State Issues

**State out of sync:**
```bash
# Refresh state from actual infrastructure
terraform refresh

# Or import missing resources
terraform import proxmox_virtual_environment_vm.k8s_workers[0] <vm-id>
```

**Corrupt state:**
```bash
# Restore from backup
cp terraform.tfstate.backup terraform.tfstate

# Or if using remote state
terraform state pull > terraform.tfstate
```

### ztnet Database Issues

**Reset database:**
```bash
cd ~/homelab/boostrap/ztnet
docker-compose down -v  # Destroys database!
docker-compose up -d
# Create new admin account and network
```

**Restore from backup:**
```bash
docker-compose exec -T postgres psql -U postgres -d ztnet < backup.sql
```

### Node Won't Join Network

```bash
# SSH to the node
ssh root@<local-ip>

# Check ZeroTier status
zerotier-cli status
zerotier-cli listnetworks

# Rejoin network
zerotier-cli leave <old-network-id>
zerotier-cli join <network-id>

# Check logs
journalctl -u zerotier-one -f
```

---

## Summary of Commands

### Update Infrastructure
```bash
# Terraform changes
cd ~/homelab/k8s-infra/terraform && terraform apply

# Ansible changes
cd ~/homelab/k8s-infra/ansible && ansible-playbook -i inventory/hosts.ini site.yml

# ztnet update
cd ~/homelab/boostrap/ztnet && docker-compose pull && docker-compose up -d
```

### Destroy Infrastructure
```bash
# Everything
terraform destroy
docker-compose down -v
rm .zerotier-network-id

# k8s only
cd ~/homelab/k8s-infra/terraform && terraform destroy

# Single node
terraform destroy -target=<resource>
```

### Backup
```bash
# Quick backup
tar czf homelab-backup-$(date +%Y%m%d).tar.gz \
  boostrap/ztnet/.env \
  .zerotier-network-id \
  k8s-infra/terraform/terraform.tfstate \
  k8s-infra/ansible/inventory/hosts.ini
```

---

**Remember:** Always backup before destroying infrastructure!
