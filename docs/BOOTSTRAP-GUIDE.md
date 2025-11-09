# HomeLab Infrastructure Bootstrap Guide

This guide walks you through the complete process of bootstrapping your HomeLab infrastructure from scratch, including the ztnet controller and Kubernetes cluster.

## Overview

The bootstrap process consists of 4 phases:

1. **Phase 1**: Deploy ztnet Controller (self-hosted ZeroTier network controller)
2. **Phase 2**: Create ZeroTier Network (overlay network for all infrastructure)
3. **Phase 3**: Provision Infrastructure (k8s nodes using Terraform)
4. **Phase 4**: Configure Kubernetes (using Ansible)

## Prerequisites

- **Bootstrap Host**: One machine to run the automation from:
  - Windows PC with WSL2 (Debian)
  - Debian/Ubuntu VPS
  - Proxmox LXC container
  - Any Linux machine with root access

- **Infrastructure Platform**: At least one of:
  - Proxmox VE (for local VMs/LXC)
  - Debian VPS with LXD (for remote containers)

## Quick Start

### 1. Prepare Bootstrap Host

#### Option A: Windows → WSL2

```powershell
cd C:\Users\<your-username>\source\repos\HomeLab\boostrap\windows
.\bootstrap-wsl-debian.ps1
```

This creates a Debian WSL2 instance with all required tools installed.

#### Option B: Direct Linux

```bash
# Clone the repository
git clone https://github.com/YOUR_USERNAME/HomeLab.git ~/homelab
cd ~/homelab/boostrap/linux

# Run bootstrap script
sudo bash bootstrap.sh
```

### 2. Run Infrastructure Bootstrap

After your bootstrap host is ready:

```bash
cd ~/homelab/boostrap/linux
bash bootstrap-infrastructure.sh
```

This interactive script will guide you through all 4 phases.

## Detailed Phase Breakdown

### Phase 1: Deploy ztnet Controller

The ztnet controller is deployed using Docker Compose and provides:
- Self-hosted ZeroTier network controller
- Web UI for network management
- PostgreSQL database for persistence

**What happens:**
1. Generates random secrets for NextAuth and PostgreSQL
2. Starts ztnet and postgres containers
3. Waits for the web UI to be accessible
4. Prompts you to create an admin account

**Manual step required:**
- Access http://localhost:3000 (or your host IP:3000)
- Create your admin account
- Log in to the dashboard

**Files created:**
- `boostrap/ztnet/.env` - Contains generated secrets
- Docker volumes for persistent data

### Phase 2: Create ZeroTier Network

Creates the overlay network that all k8s nodes will join.

**What happens:**
1. Prompts you to create a network in the ztnet web UI
2. Saves the Network ID to `.zerotier-network-id` file
3. Optionally joins the bootstrap host to the network

**Manual steps required:**
1. Go to http://localhost:3000
2. Click "Create Network" or navigate to Networks → Add
3. Configure network settings:
   - **Name**: HomeLabK8s (or your choice)
   - **IPv4 Auto-Assign**: Enable
   - **IPv4 Range**: e.g., `10.147.17.0/24`
4. Copy the 16-character Network ID (e.g., `a1b2c3d4e5f6g7h8`)
5. Paste it when prompted by the script

**Network ID storage:**
The Network ID is saved to `.zerotier-network-id` in your repo root and used by Terraform in Phase 3.

### Phase 3: Provision Infrastructure

Uses Terraform to create VMs/containers that auto-join your ZeroTier network.

**What happens:**
1. **Checks SOPS setup** - Verifies age key exists and secrets are encrypted
2. Loads the Network ID from Phase 2
3. Sets `TF_VAR_zerotier_network_id` environment variable
4. Runs `terraform init`
5. Creates execution plan with `terraform plan`
6. Applies configuration to create nodes
7. Nodes boot and automatically:
   - Install ZeroTier client
   - Join your network
   - Appear in ztnet web UI

**Manual steps required:**

**If SOPS secrets not configured:**
- Script will prompt you to create `secrets.enc.yaml`
- Opens SOPS editor to enter your Proxmox/VPS credentials
- SOPS automatically encrypts the file
- Or run manually: `bash boostrap/linux/setup-sops.sh`

**Terraform provisioning:**
1. Review Terraform plan when shown
2. Type `y` to confirm infrastructure creation
3. After nodes are created, go to ztnet web UI
4. Navigate to your network → Members
5. **Authorize each new node** that appears
6. Optionally assign static IPs (e.g., 10.147.17.10, .11, .12, etc.)

**Important notes:**
- Nodes must be authorized before they can communicate
- ZeroTier IPs will be used by Ansible in Phase 4
- Make note of which node has which IP

### Phase 4: Configure Kubernetes

Uses Ansible to install and configure Kubernetes on your nodes.

**What happens:**
1. Generates inventory template at `k8s-infra/ansible/inventory/hosts.ini`
2. Waits for you to fill in ZeroTier IPs
3. Runs Ansible playbook to configure k8s cluster

**Manual steps required:**
1. Edit `k8s-infra/ansible/inventory/hosts.ini`
2. Add your nodes with their ZeroTier IPs:

```ini
[k8s_control_plane]
k8s-master-1 ansible_host=10.147.17.10 ansible_user=root

[k8s_workers]
k8s-worker-1 ansible_host=10.147.17.11 ansible_user=root
k8s-worker-2 ansible_host=10.147.17.12 ansible_user=root
k8s-worker-3 ansible_host=10.147.17.13 ansible_user=root

[k8s_cluster:children]
k8s_control_plane
k8s_workers
```

3. Save the file
4. Press Enter to continue the script

**What gets installed:**
- Container runtime (containerd)
- Kubernetes control plane (on master nodes)
- Kubernetes worker components (on worker nodes)
- CNI networking plugin (e.g., Calico, Flannel)

## Running Individual Phases

You can run specific phases instead of the complete bootstrap:

```bash
bash bootstrap-infrastructure.sh
# Select from menu:
#   1) Complete bootstrap (all phases)
#   2) Phase 1 only (Deploy ztnet)
#   3) Phase 2 only (Create network)
#   4) Phase 3 only (Provision infrastructure)
#   5) Phase 4 only (Configure Kubernetes)
#   6) Phases 3+4 (Provision & Configure)
```

This is useful for:
- **Rerunning failed phases** without starting over
- **Updating infrastructure** (run Phase 3 again)
- **Reconfiguring k8s** (run Phase 4 again)

## Directory Structure

```
HomeLab/
├── boostrap/
│   ├── windows/
│   │   └── bootstrap-wsl-debian.ps1      # Windows → WSL bootstrap
│   ├── linux/
│   │   ├── bootstrap.sh                   # Install software on Linux
│   │   ├── bootstrap-infrastructure.sh    # Main 4-phase orchestration
│   │   └── generate-inventory.sh          # Ansible inventory helper
│   └── ztnet/
│       ├── docker-compose.yml             # ztnet controller definition
│       └── .env.example                   # Environment template
├── k8s-infra/
│   ├── terraform/
│   │   ├── main.tf                        # Provider configuration
│   │   ├── k8s-nodes.tf.example           # Example node provisioning
│   │   └── variables.tf                   # Terraform variables
│   └── ansible/
│       ├── inventory/
│       │   └── hosts.ini                  # Generated inventory file
│       └── site.yml                       # Main Ansible playbook
└── docs/
    ├── BOOTSTRAP-GUIDE.md                 # This file
    └── SOPS-SETUP.md                      # Secrets management guide
```

## Bootstrap Host Role

**Important:** The bootstrap host is only used to *run* the automation. Once complete:

✅ **Infrastructure runs independently:**
- ztnet controller (on VPS/Proxmox)
- k8s nodes (managed by Terraform)
- All services

❌ **Bootstrap host is NOT required after setup:**
- Can be turned off
- Can be destroyed
- Only needed for future infrastructure changes

To make changes later:
- Power on bootstrap host (or any machine with Terraform/Ansible)
- Run `terraform apply` or `ansible-playbook`
- Shut down again

## Troubleshooting

### ztnet won't start

```bash
cd ~/homelab/boostrap/ztnet
docker-compose logs -f
```

Common issues:
- Port 3000 already in use
- Docker not running: `sudo systemctl start docker`
- Missing .env file: `cp .env.example .env` and edit

### Nodes don't appear in ztnet

Check cloud-init on the node:
```bash
# SSH to the node (using local IP)
ssh root@<local-ip>

# Check cloud-init status
cloud-init status

# Check ZeroTier status
zerotier-cli status
zerotier-cli listnetworks
```

Common issues:
- Cloud-init still running (wait a few minutes)
- ZeroTier failed to install (check `/var/log/cloud-init-output.log`)
- Network ID incorrect (check `.zerotier-network-id` file)

### Ansible can't connect to nodes

```bash
# Test connectivity
ansible -i k8s-infra/ansible/inventory/hosts.ini all -m ping

# Test with verbose output
ansible -i k8s-infra/ansible/inventory/hosts.ini all -m ping -vvv
```

Common issues:
- ZeroTier IPs incorrect in inventory
- Nodes not authorized in ztnet (check web UI)
- SSH keys not set up (add your key to cloud-init)
- Bootstrap host not joined to ZeroTier network

### Starting over

To completely reset and start from scratch:

```bash
# Stop and remove ztnet
cd ~/homelab/boostrap/ztnet
docker-compose down -v

# Destroy Terraform infrastructure
cd ~/homelab/k8s-infra/terraform
terraform destroy

# Remove saved network ID
rm ~/homelab/.zerotier-network-id

# Re-run bootstrap
cd ~/homelab/boostrap/linux
bash bootstrap-infrastructure.sh
```

## Security Considerations

### Secrets

- **ztnet credentials**: Stored in `boostrap/ztnet/.env` (git-ignored)
- **ZeroTier Network ID**: Stored in `.zerotier-network-id` (git-ignored)
- **Terraform secrets**: Use SOPS encryption (see `docs/SOPS-SETUP.md`)
- **SSH keys**: Never commit private keys to git

### Network Security

- ZeroTier provides encrypted overlay network
- All k8s traffic flows over ZeroTier (encrypted)
- ztnet web UI should use HTTPS in production
- Consider restricting ztnet UI to VPN/ZeroTier only

### Access Control

- Manually authorize all nodes in ztnet
- Review network members regularly
- Revoke access for decommissioned nodes
- Use SSH key authentication (disable password auth)

## Next Steps

After bootstrap is complete:

1. **Access your cluster:**
   ```bash
   kubectl get nodes
   kubectl get pods -A
   ```

2. **Deploy applications:**
   - Use kubectl to deploy workloads
   - Set up Helm for package management
   - Configure ingress controller

3. **Set up monitoring:**
   - Prometheus + Grafana
   - Log aggregation (ELK, Loki)
   - Alerts and notifications

4. **Backup your infrastructure:**
   - Export ztnet configuration
   - Backup Terraform state
   - Document node configurations

## Additional Resources

- [ZeroTier Documentation](https://docs.zerotier.com/)
- [ztnet GitHub](https://github.com/sinamics/ztnet)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Terraform Proxmox Provider](https://registry.terraform.io/providers/bpg/proxmox/latest/docs)
- [Ansible Documentation](https://docs.ansible.com/)

## Getting Help

If you encounter issues:

1. Check the troubleshooting section above
2. Review logs:
   - Docker: `docker-compose logs`
   - Cloud-init: `/var/log/cloud-init-output.log`
   - Terraform: `terraform show`
   - Ansible: Run with `-vvv` flag

3. Verify prerequisites are met
4. Try running individual phases to isolate the problem

---

**Remember:** The bootstrap host is disposable. The actual infrastructure (ztnet + k8s) runs independently!
