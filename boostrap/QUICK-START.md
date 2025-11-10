# HomeLab Bootstrap - Quick Start

One-page reference for bootstrapping your entire HomeLab infrastructure from scratch.

## 🚀 Complete Bootstrap (All Phases)

### Step 1: Prepare Bootstrap Host

**Windows:**
```powershell
cd C:\Users\<you>\source\repos\HomeLab\boostrap\windows
.\bootstrap-wsl-debian.ps1
wsl -d HomeLab-Debian
```

**Linux (VPS/Direct):**
```bash
git clone https://github.com/YOUR_USERNAME/HomeLab.git ~/homelab
cd ~/homelab/boostrap/linux
sudo bash bootstrap.sh
```

### Step 2: Run Complete Infrastructure Bootstrap

```bash
cd ~/homelab/boostrap/linux
bash bootstrap-infrastructure.sh
# Select option 1: Complete bootstrap
```

### Step 3: Follow Interactive Prompts

**Phase 1 - Deploy ztnet:**
- Wait for containers to start
- Optional: Access http://localhost:3000 to create a UI admin (not required for automation)

**Phase 2 - Create Network (automated):**
- The script creates the ZeroTier network via the controller API
- Name, description, and subnet are read from config (see below)
- Network ID is saved to `.zerotier-network-id`

**Phase 3 - Provision Nodes:**
- (First time) Create encrypted secrets file if prompted
- Review Terraform plan
- Type `y` to apply
- If auto-authorization is enabled, nodes are authorized automatically; otherwise authorize in ztnet UI
- Note their ZeroTier IPs if assigning statics

**Phase 4 - Configure k8s:**
- Edit `k8s-infra/ansible/inventory/hosts.ini`
- Add nodes with ZeroTier IPs
- Save and press Enter

Done! Your cluster is ready.

## 📋 Individual Phases

Run only specific phases:

```bash
cd ~/homelab/boostrap/linux
bash bootstrap-infrastructure.sh

# Choose:
# 2 = Phase 1 only (Deploy ztnet)
# 3 = Phase 2 only (Create network)
# 4 = Phase 3 only (Provision infrastructure)
# 5 = Phase 4 only (Configure k8s)
# 6 = Phases 3+4 (Provision + Configure)
```

## 🔧 Manual Commands

### Setup SOPS (Secrets Management)

```bash
cd ~/homelab/boostrap/linux
bash setup-sops.sh

# Or manually:
age-keygen -o ~/.config/sops/age/keys.txt
# Update .sops.yaml with your public key
sops k8s-infra/terraform/secrets.enc.yaml
```

### Deploy ztnet Controller

```bash
cd ~/homelab/boostrap/ztnet
echo "NEXTAUTH_SECRET=$(openssl rand -base64 32)" > .env
echo "POSTGRES_PASSWORD=$(openssl rand -base64 24)" >> .env
docker-compose up -d
```

### Provision Infrastructure

```bash
cd ~/homelab/k8s-infra/terraform
export TF_VAR_zerotier_network_id="$(cat ~/.*/homelab/.zerotier-network-id 2>/dev/null || echo your-network-id)"
terraform init
terraform apply
```

### Configure Kubernetes

```bash
cd ~/homelab/k8s-infra/ansible
# Edit inventory/hosts.ini first!
ansible-playbook -i inventory/hosts.ini site.yml
```

## 📝 Inventory Template

Edit `k8s-infra/ansible/inventory/hosts.ini`:

```ini
[k8s_control_plane]
k8s-master-1 ansible_host=10.147.17.10 ansible_user=root

[k8s_workers]
k8s-worker-1 ansible_host=10.147.17.11 ansible_user=root
k8s-worker-2 ansible_host=10.147.17.12 ansible_user=root

[k8s_cluster:children]
k8s_control_plane
k8s_workers
```

## 🔍 Verify Cluster

```bash
# Check nodes
kubectl get nodes

# Check all pods
kubectl get pods -A

# Check services
kubectl get svc -A
```

## 🆘 Troubleshooting

**ztnet won't start:**
```bash
cd ~/homelab/boostrap/ztnet
docker-compose logs -f
```

**Nodes don't appear:**
```bash
# SSH to node and check
cloud-init status
zerotier-cli status
```

**Ansible can't connect:**
```bash
ansible -i k8s-infra/ansible/inventory/hosts.ini all -m ping -vvv
```

**Start over:**
```bash
cd ~/homelab/boostrap/ztnet && docker-compose down -v
cd ~/homelab/k8s-infra/terraform && terraform destroy
rm ~/homelab/.zerotier-network-id
cd ~/homelab/boostrap/linux && bash bootstrap-infrastructure.sh
```

## 📚 Full Documentation

- [`docs/BOOTSTRAP-GUIDE.md`](../docs/BOOTSTRAP-GUIDE.md) - Complete bootstrap guide
- [`docs/OPERATIONS-GUIDE.md`](../docs/OPERATIONS-GUIDE.md) - Update & destroy infrastructure

## 🎯 Key Files

```
boostrap/
├── ztnet/
│   ├── docker-compose.yml        # ztnet controller
│   └── .env                       # Generated secrets
│   └── zerotier-one/              # Controller identity (authtoken.secret etc.)
├── linux/
│   ├── bootstrap.sh               # Install tools
│   └── bootstrap-infrastructure.sh # Main orchestration
k8s-infra/
├── terraform/
│   ├── main.tf                    # Providers
│   └── k8s-nodes.tf.example       # Node template
└── ansible/
    └── inventory/hosts.ini        # Node inventory
```

## ✅ What Gets Installed

**Bootstrap Host:**
- Terraform, Ansible, Docker, docker-compose
- SOPS, age (for secrets)
- jq, curl, git

**Infrastructure:**
- ztnet controller (self-hosted ZeroTier)
- PostgreSQL (for ztnet)
- k8s control plane + worker nodes
- ZeroTier on all nodes

---

**Remember:** Bootstrap host is temporary - all infrastructure runs independently!
