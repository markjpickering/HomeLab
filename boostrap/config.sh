#!/bin/bash
# HomeLab Bootstrap Configuration
# This file contains user-customizable settings for bootstrap scripts
# Copy this file and modify values as needed

# Repository Configuration
# Update with your actual GitHub repository URL
export HOMELAB_REPO_URL="${HOMELAB_REPO_URL:-https://github.com/YOUR_USERNAME/HomeLab.git}"

# Installation Directories
export HOMELAB_INSTALL_DIR="${HOMELAB_INSTALL_DIR:-/root/homelab}"
export HOMELAB_WSL_DISTRO_NAME="${HOMELAB_WSL_DISTRO_NAME:-HomeLab-Debian}"

# ZeroTier Configuration
export HOMELAB_ZEROTIER_NETWORK_NAME="${HOMELAB_ZEROTIER_NETWORK_NAME:-HomeLabK8s}"
export HOMELAB_ZEROTIER_SUBNET="${HOMELAB_ZEROTIER_SUBNET:-10.147.17.0/24}"

# ztnet Configuration
export HOMELAB_ZTNET_PORT="${HOMELAB_ZTNET_PORT:-3000}"

# Age/SOPS Configuration
export HOMELAB_AGE_KEY_FILE="${HOMELAB_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"

# Terraform Configuration
export HOMELAB_TF_DIR="${HOMELAB_TF_DIR:-k8s-infra/terraform}"
export HOMELAB_TF_SECRETS_FILE="${HOMELAB_TF_SECRETS_FILE:-secrets.enc.yaml}"

# Ansible Configuration
export HOMELAB_ANSIBLE_DIR="${HOMELAB_ANSIBLE_DIR:-k8s-infra/ansible}"
export HOMELAB_ANSIBLE_INVENTORY="${HOMELAB_ANSIBLE_INVENTORY:-inventory/hosts.ini}"

# Kubernetes Configuration
export HOMELAB_K8S_CONTROL_PLANE_COUNT="${HOMELAB_K8S_CONTROL_PLANE_COUNT:-1}"
export HOMELAB_K8S_WORKER_COUNT="${HOMELAB_K8S_WORKER_COUNT:-3}"

# Node Resource Defaults (for Terraform)
export HOMELAB_CONTROL_PLANE_CORES="${HOMELAB_CONTROL_PLANE_CORES:-2}"
export HOMELAB_CONTROL_PLANE_MEMORY="${HOMELAB_CONTROL_PLANE_MEMORY:-4096}"
export HOMELAB_CONTROL_PLANE_DISK="${HOMELAB_CONTROL_PLANE_DISK:-32}"

export HOMELAB_WORKER_CORES="${HOMELAB_WORKER_CORES:-4}"
export HOMELAB_WORKER_MEMORY="${HOMELAB_WORKER_MEMORY:-8192}"
export HOMELAB_WORKER_DISK="${HOMELAB_WORKER_DISK:-64}"

# Proxmox Configuration (if using Proxmox)
export HOMELAB_PROXMOX_NODE="${HOMELAB_PROXMOX_NODE:-pve}"
export HOMELAB_PROXMOX_STORAGE="${HOMELAB_PROXMOX_STORAGE:-local-lvm}"
export HOMELAB_PROXMOX_BRIDGE="${HOMELAB_PROXMOX_BRIDGE:-vmbr0}"

# User Preferences
export HOMELAB_SSH_USER="${HOMELAB_SSH_USER:-root}"
export HOMELAB_PYTHON_INTERPRETER="${HOMELAB_PYTHON_INTERPRETER:-/usr/bin/python3}"

# Auto-detect repository URL from git remote if in repository
if [ -d ".git" ]; then
    GIT_REMOTE=$(git remote get-url origin 2>/dev/null || echo "")
    if [ -n "$GIT_REMOTE" ]; then
        export HOMELAB_REPO_URL="$GIT_REMOTE"
    fi
fi

# Function to display configuration
show_config() {
    echo "HomeLab Bootstrap Configuration:"
    echo "  Repository: $HOMELAB_REPO_URL"
    echo "  Install Dir: $HOMELAB_INSTALL_DIR"
    echo "  WSL Distro: $HOMELAB_WSL_DISTRO_NAME"
    echo "  ZeroTier Network: $HOMELAB_ZEROTIER_NETWORK_NAME"
    echo "  ZeroTier Subnet: $HOMELAB_ZEROTIER_SUBNET"
    echo "  K8s Control Plane: $HOMELAB_K8S_CONTROL_PLANE_COUNT nodes"
    echo "  K8s Workers: $HOMELAB_K8S_WORKER_COUNT nodes"
}

# Load user overrides if they exist
USER_CONFIG_FILE="${HOMELAB_USER_CONFIG:-$HOME/.homelab.conf}"
if [ -f "$USER_CONFIG_FILE" ]; then
    source "$USER_CONFIG_FILE"
fi
