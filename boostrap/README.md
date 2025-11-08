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

## After Bootstrap

Once bootstrap is complete:

```bash
# Access your infrastructure code
cd ~/homelab/k8s-infra/terraform

# Initialize Terraform
terraform init

# Plan your infrastructure
terraform plan

# Apply your infrastructure
terraform apply
```

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
