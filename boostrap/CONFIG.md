# Bootstrap Configuration Guide

The HomeLab bootstrap scripts use a centralized configuration system to avoid hardcoded values and make customization easy.

## Configuration Files

### `boostrap/config.sh`
Default configuration with sensible defaults. **Safe to commit to git.**

### `~/.homelab.conf` (Optional)
User-specific overrides. **Not tracked in git.** Create this file to override defaults without modifying the repository.

### `boostrap/config.local.sh` (Optional)
Repository-specific overrides. **Not tracked in git.** Use for project-specific settings.

## Configuration Variables

### Repository Settings

```bash
# Your HomeLab repository URL
export HOMELAB_REPO_URL="https://github.com/YOUR_USERNAME/HomeLab.git"
```

**Note:** The bootstrap scripts will auto-detect this from `git remote` if you're running from within the cloned repository.

### Installation Paths

```bash
# Where to install HomeLab on the bootstrap host
export HOMELAB_INSTALL_DIR="/root/homelab"

# WSL distribution name (Windows only)
export HOMELAB_WSL_DISTRO_NAME="HomeLab-Debian"
```

### ZeroTier Configuration

```bash
# Network name (for display purposes)
export HOMELAB_ZEROTIER_NETWORK_NAME="HomeLabK8s"

# Default subnet for ZeroTier network
export HOMELAB_ZEROTIER_SUBNET="10.147.17.0/24"
```

### ztnet Controller

```bash
# Port for ztnet web UI
export HOMELAB_ZTNET_PORT="3000"
```

### SOPS/Age Configuration

```bash
# Location of age private key
export HOMELAB_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
```

### Terraform/Ansible Paths

```bash
# Terraform directory (relative to repository root)
export HOMELAB_TF_DIR="k8s-infra/terraform"

# Terraform secrets file name
export HOMELAB_TF_SECRETS_FILE="secrets.enc.yaml"

# Ansible directory (relative to repository root)
export HOMELAB_ANSIBLE_DIR="k8s-infra/ansible"

# Ansible inventory file (relative to ansible directory)
export HOMELAB_ANSIBLE_INVENTORY="inventory/hosts.ini"
```

### Kubernetes Cluster Configuration

```bash
# Number of control plane nodes
export HOMELAB_K8S_CONTROL_PLANE_COUNT="1"

# Number of worker nodes
export HOMELAB_K8S_WORKER_COUNT="3"
```

### Node Resources (for Terraform)

```bash
# Control plane node specs
export HOMELAB_CONTROL_PLANE_CORES="2"
export HOMELAB_CONTROL_PLANE_MEMORY="4096"  # MB
export HOMELAB_CONTROL_PLANE_DISK="32"      # GB

# Worker node specs
export HOMELAB_WORKER_CORES="4"
export HOMELAB_WORKER_MEMORY="8192"  # MB
export HOMELAB_WORKER_DISK="64"      # GB
```

### Proxmox Settings (if using Proxmox)

```bash
# Proxmox node name
export HOMELAB_PROXMOX_NODE="pve"

# Storage pool
export HOMELAB_PROXMOX_STORAGE="local-lvm"

# Network bridge
export HOMELAB_PROXMOX_BRIDGE="vmbr0"
```

### SSH/Ansible Settings

```bash
# Default SSH user for nodes
export HOMELAB_SSH_USER="root"

# Python interpreter path
export HOMELAB_PYTHON_INTERPRETER="/usr/bin/python3"
```

## Usage Examples

### 1. Create Personal Config Override

Create `~/.homelab.conf`:

```bash
# My personal HomeLab configuration
export HOMELAB_REPO_URL="https://github.com/myusername/HomeLab.git"
export HOMELAB_K8S_WORKER_COUNT="5"  # I want 5 workers
export HOMELAB_WORKER_MEMORY="16384"  # My workers have more RAM
```

This file is loaded automatically by all bootstrap scripts.

### 2. Set Environment Variables

For one-time overrides:

```bash
# Override repository URL
export HOMELAB_REPO_URL="https://github.com/myuser/HomeLab.git"

# Run bootstrap
cd boostrap/windows
./bootstrap-wsl-debian.ps1
```

### 3. Check Current Configuration

```bash
cd ~/homelab/boostrap/linux
source ../config.sh
show_config
```

Output:
```
HomeLab Bootstrap Configuration:
  Repository: https://github.com/myuser/HomeLab.git
  Install Dir: /root/homelab
  WSL Distro: HomeLab-Debian
  ZeroTier Network: HomeLabK8s
  ZeroTier Subnet: 10.147.17.0/24
  K8s Control Plane: 1 nodes
  K8s Workers: 3 nodes
```

## Auto-Detection

The configuration system auto-detects values when possible:

1. **Repository URL**: Detected from `git remote get-url origin` if running from cloned repo
2. **Existing values**: Environment variables take precedence over config file
3. **Sensible defaults**: If nothing is specified, reasonable defaults are used

## Priority Order (Highest to Lowest)

1. Environment variables (e.g., `export HOMELAB_REPO_URL=...`)
2. `~/.homelab.conf` (user-specific overrides)
3. `boostrap/config.local.sh` (repository-specific, not tracked)
4. `boostrap/config.sh` (default configuration)
5. Hardcoded fallbacks in scripts

## Windows Bootstrap Behavior

The PowerShell script `bootstrap-wsl-debian.ps1`:

1. Checks for `$env:HOMELAB_REPO_URL`
2. If not set, tries to detect from `git remote`
3. If not detected, prompts user to enter repository URL
4. Prevents proceeding without a valid repository URL

**No hardcoded repository URLs in the script!**

## Secrets vs Configuration

**Configuration** (in `config.sh`):
- Non-sensitive settings
- Repository URLs, paths, resource counts
- Safe to commit to git

**Secrets** (in SOPS-encrypted files):
- API tokens, passwords, SSH keys
- Stored in `secrets.enc.yaml` (encrypted)
- Never in plain text in configuration files

## Validating Configuration

Before running bootstrap:

```bash
# Check if repo URL is set
echo $HOMELAB_REPO_URL

# View all configuration
cd boostrap/linux
source ../config.sh
show_config

# Test by running with dry-run (if available)
bash bootstrap-infrastructure.sh  # Will prompt/validate during phases
```

## Troubleshooting

### "Repository URL not set"

Create `~/.homelab.conf`:
```bash
export HOMELAB_REPO_URL="https://github.com/youruser/HomeLab.git"
```

Or set environment variable before running:
```bash
export HOMELAB_REPO_URL="https://github.com/youruser/HomeLab.git"
./bootstrap-wsl-debian.ps1
```

### "Cannot find config.sh"

The scripts look for `config.sh` in `boostrap/` directory. Make sure you're running from the correct location or the repository is properly cloned.

### "Using wrong repository"

Check priority order. Your environment variable or `~/.homelab.conf` might be overriding the default.

```bash
unset HOMELAB_REPO_URL  # Clear environment variable
rm ~/.homelab.conf       # Remove user config
# Edit boostrap/config.sh instead
```

## Best Practices

1. **Fork the repository** and update `HOMELAB_REPO_URL` in `boostrap/config.sh` to your fork
2. **Use `~/.homelab.conf`** for machine-specific settings (different laptop, server, etc.)
3. **Never commit secrets** - Use SOPS for sensitive data
4. **Document custom settings** - Comment your overrides in `~/.homelab.conf`
5. **Test after changes** - Run `show_config` to verify settings before bootstrap

## Example: Complete Setup

```bash
# 1. Fork the repository on GitHub
# 2. Clone your fork
git clone https://github.com/YOURUSER/HomeLab.git ~/HomeLab
cd ~/HomeLab

# 3. Update default config (optional - can use ~/.homelab.conf instead)
vim boostrap/config.sh
# Change: export HOMELAB_REPO_URL="https://github.com/YOURUSER/HomeLab.git"

# 4. Create personal overrides
cat > ~/.homelab.conf << 'EOF'
export HOMELAB_K8S_WORKER_COUNT="5"
export HOMELAB_ZEROTIER_SUBNET="10.200.100.0/24"
EOF

# 5. Run bootstrap
cd boostrap/linux
bash bootstrap-infrastructure.sh
```

---

**Configuration is now centralized and no placeholders remain in scripts!**
