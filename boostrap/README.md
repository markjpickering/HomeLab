# HomeLab Bootstrap

This directory contains bootstrap scripts to set up your HomeLab infrastructure on different platforms.

## Quick Start

### Windows → WSL (Debian)

From Windows PowerShell (as Administrator):

```powershell
cd C:\Users\markj\source\repos\HomeLab\boostrap\windows
.\bootstrap-wsl-debian.ps1
```

This will:
1. Create a minimal Debian WSL instance
2. Clone the HomeLab repository
3. Install all required software (Terraform, Ansible, etc.)

### Direct Linux (Debian VPS, Proxmox LXC, etc.)

From a fresh Debian/Ubuntu system:

```bash
curl -fsSL https://raw.githubusercontent.com/markjpickering/HomeLab/main/boostrap/linux/bootstrap-standalone.sh | bash
```

Or with a custom repository URL:

```bash
curl -fsSL https://raw.githubusercontent.com/markjpickering/HomeLab/main/boostrap/linux/bootstrap-standalone.sh | bash -s -- https://github.com/markjpickering/HomeLab.git
```

This works on:
- Fresh Debian/Ubuntu VPS
- Proxmox LXC containers
- Any Debian-based system

## Bootstrap Scripts

### Windows Scripts

- **`windows/bootstrap-wsl-debian.ps1`**: Creates WSL Debian instance and bootstraps it
- **`windows/install-unix-env.ps1`**: Installs Unix tools on Windows (Git Bash, WSL, Chocolatey)

### Linux Scripts

- **`linux/bootstrap-standalone.sh`**: Self-contained bootstrap that can be curled (installs git, clones repo, runs full bootstrap)
- **`linux/bootstrap.sh`**: Full bootstrap script that installs all software (Terraform, Ansible, etc.)

## What Gets Installed

The Linux bootstrap installs:

- **Essential tools**: git, curl, wget, unzip, sudo, gnupg, etc.
- **Terraform**: Latest version from HashiCorp's official repository
- **Ansible**: Latest version from Debian repositories
- **Additional tools**: vim, htop, net-tools, jq, etc.

## Architecture

```
Windows PC
    └── WSL (Debian) ───┐
                        ├──> Linux Bootstrap Scripts ──> Full Environment
Debian VPS ────────────┤
Proxmox LXC ───────────┘
```

## Customization

Before running, update these values:

1. **GitHub Repository URL**: 
   - In `windows/bootstrap-wsl-debian.ps1` (line 36)
   - In `linux/bootstrap-standalone.sh` (line 20)

2. **Install Directory**: Default is `/root/homelab` (can be changed in scripts)

## Infrastructure Bootstrap

After the bootstrap host is ready, run the complete infrastructure bootstrap:

```bash
cd ~/homelab/boostrap/linux
bash bootstrap-infrastructure.sh
```

This will guide you through:
1. Deploying ztnet controller (self-hosted ZeroTier)
2. Creating your ZeroTier network
3. Provisioning k8s nodes with Terraform
4. Configuring Kubernetes with Ansible

**See the complete guide:** [`docs/BOOTSTRAP-GUIDE.md`](../docs/BOOTSTRAP-GUIDE.md)

## Manual Infrastructure Setup (Alternative)

If you prefer to run steps manually:

```bash
# 1. Deploy ztnet controller
cd ~/homelab/boostrap/ztnet
cp .env.example .env
# Edit .env with your secrets
docker-compose up -d

# 2. Access http://localhost:3000 and create network

# 3. Provision infrastructure
cd ~/homelab/k8s-infra/terraform
export TF_VAR_zerotier_network_id="your-network-id"
terraform init
terraform plan
terraform apply

# 4. Configure Kubernetes
cd ~/homelab/k8s-infra/ansible
# Edit inventory/hosts.ini with ZeroTier IPs
ansible-playbook -i inventory/hosts.ini site.yml
```

## Documentation

### Quick References
- **[QUICK-START.md](QUICK-START.md)** - One-page quick reference for bootstrap process
- **[docs/OPERATIONS-CHEATSHEET.md](../docs/OPERATIONS-CHEATSHEET.md)** - Command cheat sheet for operations

### Complete Guides
- **[docs/BOOTSTRAP-GUIDE.md](../docs/BOOTSTRAP-GUIDE.md)** - Complete 4-phase bootstrap walkthrough
- **[docs/OPERATIONS-GUIDE.md](../docs/OPERATIONS-GUIDE.md)** - Update, destroy, and manage infrastructure
- **[docs/SOPS-SETUP.md](../docs/SOPS-SETUP.md)** - Secrets management setup

### Implementation Details
- **[docs/IMPLEMENTATION-SUMMARY.md](../docs/IMPLEMENTATION-SUMMARY.md)** - Technical implementation overview

## Troubleshooting

### Windows: WSL not installed
If you get a WSL error, restart your computer after the first run.

### Linux: Permission denied
Run the bootstrap script with sudo or as root:
```bash
curl -fsSL URL | sudo bash
```

### Git not found
The standalone bootstrap installs git automatically, but if you're running `bootstrap.sh` directly, install git first:
```bash
apt-get update && apt-get install -y git
```
