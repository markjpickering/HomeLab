# Infrastructure Operations Cheat Sheet

Quick reference for common infrastructure operations.

---

## 🔄 Update Infrastructure

### Update Terraform (add/change nodes)
```bash
cd ~/homelab/k8s-infra/terraform
terraform plan
terraform apply
```

### Update Ansible (reconfigure nodes)
```bash
cd ~/homelab/k8s-infra/ansible
ansible-playbook -i inventory/hosts.ini site.yml
```

### Update ztnet Controller
```bash
cd ~/homelab/boostrap/ztnet
docker-compose pull && docker-compose up -d
```

---

## 💥 Destroy Infrastructure

### Destroy Everything
```bash
cd ~/homelab/k8s-infra/terraform && terraform destroy
cd ~/homelab/boostrap/ztnet && docker-compose down -v
rm ~/homelab/.zerotier-network-id
```

### Destroy Only k8s Cluster
```bash
cd ~/homelab/k8s-infra/terraform
terraform destroy
```

### Destroy Single Node
```bash
cd ~/homelab/k8s-infra/terraform
terraform destroy -target=proxmox_virtual_environment_vm.k8s_workers[2]
```

---

## 💾 Backup

### Quick Backup (Essential Files)
```bash
tar czf homelab-backup-$(date +%Y%m%d).tar.gz \
  boostrap/ztnet/.env \
  .zerotier-network-id \
  k8s-infra/terraform/terraform.tfstate \
  k8s-infra/ansible/inventory/hosts.ini
```

### Backup ztnet Database
```bash
cd ~/homelab/boostrap/ztnet
docker-compose exec postgres pg_dump -U postgres ztnet > ztnet-backup-$(date +%Y%m%d).sql
```

---

## 📈 Scale Operations

### Add Worker Node
```bash
# 1. Edit k8s-nodes.tf (increase count)
vim ~/homelab/k8s-infra/terraform/k8s-nodes.tf

# 2. Apply
cd ~/homelab/k8s-infra/terraform && terraform apply

# 3. Authorize in ztnet UI

# 4. Add to inventory and configure
vim ~/homelab/k8s-infra/ansible/inventory/hosts.ini
cd ~/homelab/k8s-infra/ansible
ansible-playbook -i inventory/hosts.ini site.yml --limit <new-node>
```

### Remove Worker Node
```bash
# 1. Drain node
kubectl drain k8s-worker-3 --ignore-daemonsets --delete-emptydir-data

# 2. Delete from k8s
kubectl delete node k8s-worker-3

# 3. Remove from inventory
vim ~/homelab/k8s-infra/ansible/inventory/hosts.ini

# 4. Edit k8s-nodes.tf (decrease count)
vim ~/homelab/k8s-infra/terraform/k8s-nodes.tf

# 5. Apply
cd ~/homelab/k8s-infra/terraform && terraform apply
```

---

## 🔍 Check Status

### Terraform State
```bash
cd ~/homelab/k8s-infra/terraform
terraform show
terraform state list
```

### ztnet Status
```bash
cd ~/homelab/boostrap/ztnet
docker-compose ps
docker-compose logs --tail=50
```

### Node Connectivity
```bash
cd ~/homelab/k8s-infra/ansible
ansible -i inventory/hosts.ini all -m ping
```

### ZeroTier Status on All Nodes
```bash
cd ~/homelab/k8s-infra/ansible
ansible -i inventory/hosts.ini all -b -m shell -a "zerotier-cli status"
```

---

## 🛠️ Node Operations

### Rebuild Single Node
```bash
cd ~/homelab/k8s-infra/terraform
terraform destroy -target=proxmox_virtual_environment_vm.k8s_workers[1]
terraform apply -target=proxmox_virtual_environment_vm.k8s_workers[1]
# Then authorize in ztnet and run Ansible
```

### Update Single Node
```bash
cd ~/homelab/k8s-infra/ansible
ansible-playbook -i inventory/hosts.ini site.yml --limit k8s-worker-1
```

### SSH to Node via ZeroTier
```bash
# Get IP from inventory
ssh root@10.147.17.11
```

---

## 🚨 Emergency Operations

### Backup Before Destroying
```bash
# Quick backup
cd ~/homelab
tar czf emergency-backup-$(date +%Y%m%d-%H%M%S).tar.gz \
  boostrap/ztnet/.env \
  .zerotier-network-id \
  k8s-infra/terraform/ \
  k8s-infra/ansible/inventory/

# Database backup
cd boostrap/ztnet
docker-compose exec postgres pg_dump -U postgres ztnet > emergency-db-backup.sql
```

### Reset ztnet (Keep Nodes)
```bash
cd ~/homelab/boostrap/ztnet
docker-compose down -v
docker-compose up -d
# Recreate admin and network
```

### Force Node to Rejoin Network
```bash
# On the node
zerotier-cli leave <old-network-id>
zerotier-cli join <network-id>
```

---

## 📋 Common File Locations

```
~/homelab/
├── boostrap/ztnet/.env                    # ztnet secrets
├── .zerotier-network-id                   # ZeroTier network ID
├── k8s-infra/terraform/terraform.tfstate  # Infrastructure state
└── k8s-infra/ansible/inventory/hosts.ini  # Node inventory
```

---

## 🔗 See Full Documentation

- Complete operations guide: [`docs/OPERATIONS-GUIDE.md`](OPERATIONS-GUIDE.md)
- Bootstrap guide: [`docs/BOOTSTRAP-GUIDE.md`](BOOTSTRAP-GUIDE.md)
- Quick start: [`boostrap/QUICK-START.md`](../boostrap/QUICK-START.md)

---

**Pro Tip:** Always run `terraform plan` before `terraform apply` to preview changes!
