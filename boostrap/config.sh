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

# Site Definitions
export HOMELAB_PRIMARY_SITE_ID="${HOMELAB_PRIMARY_SITE_ID:-primary}"
export HOMELAB_PRIMARY_SITE_NAME="${HOMELAB_PRIMARY_SITE_NAME:-Pickerings Home}"  # Human-readable name
export HOMELAB_PRIMARY_SITE_LOCATION="${HOMELAB_PRIMARY_SITE_LOCATION:-Pickering Family Home Lab}"  # Full description

export HOMELAB_SECONDARY_SITE_ID="${HOMELAB_SECONDARY_SITE_ID:-secondary}"
export HOMELAB_SECONDARY_SITE_NAME="${HOMELAB_SECONDARY_SITE_NAME:-Sheilas Home}"  # Human-readable name
export HOMELAB_SECONDARY_SITE_LOCATION="${HOMELAB_SECONDARY_SITE_LOCATION:-Sheila's Home Lab}"  # Full description

# Bootstrap Mode
# Set to 'primary' or 'secondary' to bootstrap only one site, or leave empty for both sites
# Can also be overridden with: --site primary or --site secondary
export HOMELAB_BOOTSTRAP_SITE="${HOMELAB_BOOTSTRAP_SITE:-}"

# DNS Configuration
# Base domain (used for shared services and as fallback)
export HOMELAB_DNS_DOMAIN="${HOMELAB_DNS_DOMAIN:-hl.internal}"

# Site-specific domains (consistent .hl.internal pattern)
# Each site gets a subdomain of the base hl.internal domain
export HOMELAB_PRIMARY_DNS_DOMAIN="${HOMELAB_PRIMARY_DNS_DOMAIN:-pickers.hl.internal}"
export HOMELAB_SECONDARY_DNS_DOMAIN="${HOMELAB_SECONDARY_DNS_DOMAIN:-sheila.hl.internal}"

# Shared services domain
export HOMELAB_SHARED_DNS_DOMAIN="${HOMELAB_SHARED_DNS_DOMAIN:-services.hl.internal}"

# Legacy subdomain format (for backward compatibility)
# These are computed from site IDs + base domain
export HOMELAB_PRIMARY_DNS_SUBDOMAIN="${HOMELAB_PRIMARY_SITE_ID}.${HOMELAB_DNS_DOMAIN}"
export HOMELAB_SECONDARY_DNS_SUBDOMAIN="${HOMELAB_SECONDARY_SITE_ID}.${HOMELAB_DNS_DOMAIN}"
export HOMELAB_SHARED_DNS_SUBDOMAIN="shared.${HOMELAB_DNS_DOMAIN}"

# ZeroTier Configuration
export HOMELAB_ZEROTIER_NETWORK_NAME="${HOMELAB_ZEROTIER_NETWORK_NAME:-HomeLabK8s}"
export HOMELAB_ZEROTIER_NETWORK_DESCRIPTION="${HOMELAB_ZEROTIER_NETWORK_DESCRIPTION:-HomeLab Kubernetes overlay network}"
export HOMELAB_ZEROTIER_SUBNET="${HOMELAB_ZEROTIER_SUBNET:-10.147.17.0/24}"
# Optional: pre-provide an existing network ID to skip creation
export HOMELAB_ZEROTIER_NETWORK_ID="${HOMELAB_ZEROTIER_NETWORK_ID:-}"
# Whether to join the bootstrap host to the ZT network (y/n)
export HOMELAB_JOIN_BOOTSTRAP_HOST="${HOMELAB_JOIN_BOOTSTRAP_HOST:-n}"
# Auto-authorize all members that appear on the network (y/n)
export HOMELAB_ZT_AUTO_AUTHORIZE="${HOMELAB_ZT_AUTO_AUTHORIZE:-y}"
# Optional: host to re-home the controller to after provisioning (e.g. root@10.147.17.10)
export HOMELAB_ZTNET_REMOTE_HOST="${HOMELAB_ZTNET_REMOTE_HOST:-}"
export HOMELAB_ZTNET_REMOTE_DIR="${HOMELAB_ZTNET_REMOTE_DIR:-/opt/ztnet}"

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

# IP Ranges (ZeroTier network)
export HOMELAB_PRIMARY_IP_RANGE="10.147.17.10-19"
export HOMELAB_SECONDARY_IP_RANGE="10.147.17.20-29"
export HOMELAB_SHARED_IP_RANGE="10.147.17.100-109"

# Primary Site Node IPs
export HOMELAB_PRIMARY_SERVER_IP="${HOMELAB_PRIMARY_SERVER_IP:-10.147.17.10}"
export HOMELAB_PRIMARY_AGENT1_IP="${HOMELAB_PRIMARY_AGENT1_IP:-10.147.17.11}"
export HOMELAB_PRIMARY_AGENT2_IP="${HOMELAB_PRIMARY_AGENT2_IP:-10.147.17.12}"

# Secondary Site Node IPs
export HOMELAB_SECONDARY_SERVER_IP="${HOMELAB_SECONDARY_SERVER_IP:-10.147.17.20}"
export HOMELAB_SECONDARY_AGENT1_IP="${HOMELAB_SECONDARY_AGENT1_IP:-10.147.17.21}"
export HOMELAB_SECONDARY_AGENT2_IP="${HOMELAB_SECONDARY_AGENT2_IP:-10.147.17.22}"

# Shared Service VIPs
export HOMELAB_VAULT_VIP="${HOMELAB_VAULT_VIP:-10.147.17.100}"
export HOMELAB_REGISTRY_VIP="${HOMELAB_REGISTRY_VIP:-10.147.17.101}"
export HOMELAB_MINIO_VIP="${HOMELAB_MINIO_VIP:-10.147.17.102}"
export HOMELAB_PROXY_VIP="${HOMELAB_PROXY_VIP:-10.147.17.200}"

# DNS Server IPs
export HOMELAB_PRIMARY_DNS_IP="${HOMELAB_PRIMARY_DNS_IP:-10.147.17.5}"
export HOMELAB_SECONDARY_DNS_IP="${HOMELAB_SECONDARY_DNS_IP:-10.147.17.25}"

# k3s Configuration
export HOMELAB_K3S_VERSION="${HOMELAB_K3S_VERSION:-v1.28.4+k3s2}"
export HOMELAB_K3S_CLUSTER_CIDR="${HOMELAB_K3S_CLUSTER_CIDR:-10.42.0.0/16}"
export HOMELAB_K3S_SERVICE_CIDR="${HOMELAB_K3S_SERVICE_CIDR:-10.43.0.0/16}"
export HOMELAB_K8S_CONTROL_PLANE_COUNT="${HOMELAB_K8S_CONTROL_PLANE_COUNT:-1}"
export HOMELAB_K8S_WORKER_COUNT="${HOMELAB_K8S_WORKER_COUNT:-2}"

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

# Helper Functions

# Generate node name based on site, role, and number
# Usage: generate_node_name primary server 1
generate_node_name() {
    local site_id=$1
    local role=$2  # server or agent
    local number=$3
    echo "k3s-${site_id}-${role}-${number}"
}

# Get DNS name for a service
# Usage: get_service_dns vault shared
get_service_dns() {
    local service=$1
    local scope=$2  # primary, secondary, shared, or empty for shortcut
    
    case $scope in
        primary)
            echo "${service}.${HOMELAB_PRIMARY_DNS_DOMAIN}"
            ;;
        secondary)
            echo "${service}.${HOMELAB_SECONDARY_DNS_DOMAIN}"
            ;;
        shared)
            echo "${service}.${HOMELAB_SHARED_DNS_DOMAIN}"
            ;;
        *)
            # Shortcut (uses base domain)
            echo "${service}.${HOMELAB_DNS_DOMAIN}"
            ;;
    esac
}

# Export helper functions
export -f generate_node_name 2>/dev/null || true
export -f get_service_dns 2>/dev/null || true

# Function to display configuration
show_config() {
    echo "HomeLab Bootstrap Configuration:"
    echo "================================"
    echo ""
    echo "Sites:"
    echo "  Primary:   ${HOMELAB_PRIMARY_SITE_NAME} (${HOMELAB_PRIMARY_SITE_ID})"
    echo "  Secondary: ${HOMELAB_SECONDARY_SITE_NAME} (${HOMELAB_SECONDARY_SITE_ID})"
    echo ""
    echo "DNS Domains:"
    echo "  Base:      ${HOMELAB_DNS_DOMAIN}"
    echo "  Primary:   ${HOMELAB_PRIMARY_DNS_DOMAIN}"
    echo "  Secondary: ${HOMELAB_SECONDARY_DNS_DOMAIN}"
    echo "  Shared:    ${HOMELAB_SHARED_DNS_DOMAIN}"
    echo ""
    echo "Repository: ${HOMELAB_REPO_URL}"
    echo "Install Dir: ${HOMELAB_INSTALL_DIR}"
    echo "ZeroTier Network: ${HOMELAB_ZEROTIER_NETWORK_NAME}"
    echo "ZeroTier Subnet: ${HOMELAB_ZEROTIER_SUBNET}"
    echo "k3s Version: ${HOMELAB_K3S_VERSION}"
    echo "Control Plane: ${HOMELAB_K8S_CONTROL_PLANE_COUNT} node(s) per site"
    echo "Workers: ${HOMELAB_K8S_WORKER_COUNT} node(s) per site"
    echo ""
}

# Load user overrides if they exist
USER_CONFIG_FILE="${HOMELAB_USER_CONFIG:-$HOME/.homelab.conf}"
if [ -f "$USER_CONFIG_FILE" ]; then
    source "$USER_CONFIG_FILE"
fi
