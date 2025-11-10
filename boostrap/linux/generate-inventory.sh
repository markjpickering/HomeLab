#!/bin/bash
# Generate Ansible inventory from ZeroTier network members
# This script queries the local ZeroTier node to get network members

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INVENTORY_FILE="$REPO_ROOT/k8s-infra/ansible/inventory/hosts.ini"

# Load network ID
if [ ! -f "$REPO_ROOT/.zerotier-network-id" ]; then
    echo "❌ Network ID not found. Run bootstrap-infrastructure.sh first."
    exit 1
fi

NETWORK_ID=$(cat "$REPO_ROOT/.zerotier-network-id")

echo "🔍 Discovering ZeroTier network members..."
echo "Network ID: $NETWORK_ID"
echo ""

# Check if zerotier-cli is available
if ! command -v zerotier-cli &> /dev/null; then
    echo "❌ zerotier-cli not found. This script must run on a machine joined to the network."
    exit 1
fi

# Get network members from local zerotier info
# Note: This is a simplified version. For production, you'd query the ztnet API
echo "⚠️  Manual inventory generation"
echo ""
echo "This is a template generator. You'll need to:"
echo "  1. Check ztnet web UI for authorized nodes and their ZeroTier IPs"
echo "  2. Update the inventory file manually or use the template below"
echo ""

# Create backup of existing inventory
if [ -f "$INVENTORY_FILE" ]; then
    cp "$INVENTORY_FILE" "$INVENTORY_FILE.backup.$(date +%s)"
    echo "📋 Backed up existing inventory"
fi

# Create directory if it doesn't exist
mkdir -p "$(dirname "$INVENTORY_FILE")"

# Generate template inventory
cat > "$INVENTORY_FILE" << 'EOF'
# Kubernetes Cluster Inventory
# Update the ansible_host values with the ZeroTier IPs from your ztnet controller
# Format: <node-name> ansible_host=<zerotier-ip> ansible_user=<ssh-user>

[k8s_control_plane]
# Control plane nodes (masters)
# Example: k8s-master-1 ansible_host=10.147.17.10 ansible_user=root

[k8s_workers]
# Worker nodes
# Example: k8s-worker-1 ansible_host=10.147.17.11 ansible_user=root
# Example: k8s-worker-2 ansible_host=10.147.17.12 ansible_user=root

[k8s_cluster:children]
k8s_control_plane
k8s_workers

[k8s_cluster:vars]
# Common variables for all nodes
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_common_args='-o StrictHostKeyChecking=no'

# Optional: Uncomment and set if using SSH keys
# ansible_ssh_private_key_file=~/.ssh/id_rsa
EOF

echo "✅ Generated inventory template at: $INVENTORY_FILE"
echo ""
echo "📝 Next steps:"
echo "  1. Go to http://localhost:3000"
echo "  2. Find your network and view the member list"
echo "  3. Copy the ZeroTier IPs for each node"
echo "  4. Edit $INVENTORY_FILE"
echo "  5. Replace the example entries with your actual nodes"
echo ""
echo "Example:"
echo "  [k8s_control_plane]"
echo "  k8s-master-1 ansible_host=10.147.17.10 ansible_user=root"
echo ""
echo "  [k8s_workers]"
echo "  k8s-worker-1 ansible_host=10.147.17.11 ansible_user=root"
echo "  k8s-worker-2 ansible_host=10.147.17.12 ansible_user=root"
