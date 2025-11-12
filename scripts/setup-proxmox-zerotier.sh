#!/bin/bash
# Setup ZeroTier on Proxmox Hosts
# Run this script on each Proxmox host to install ZeroTier and join the HomeLab network

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
ZEROTIER_NETWORK_ID="${ZEROTIER_NETWORK_ID:-}"
SITE_NAME="${SITE_NAME:-}"

# Helper functions
log_info() {
    echo -e "${CYAN}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    log_error "Please run as root (use sudo)"
fi

# Display banner
echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Proxmox ZeroTier Setup Script        ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""

# Get site name if not provided
if [ -z "$SITE_NAME" ]; then
    log_info "Which site is this Proxmox host?"
    echo "  1) Primary Site (Pickering's Home)"
    echo "  2) Secondary Site (Sheila's Home)"
    read -p "Enter choice [1-2]: " SITE_CHOICE
    
    case $SITE_CHOICE in
        1)
            SITE_NAME="primary"
            SITE_FULL_NAME="Pickering's Home"
            ;;
        2)
            SITE_NAME="secondary"
            SITE_FULL_NAME="Sheila's Home"
            ;;
        *)
            log_error "Invalid choice"
            ;;
    esac
    
    log_info "Site: $SITE_FULL_NAME ($SITE_NAME)"
fi

# Get ZeroTier network ID if not provided
if [ -z "$ZEROTIER_NETWORK_ID" ]; then
    log_info "Enter your ZeroTier network ID:"
    log_warning "Find this in the ztnet UI at http://localhost:3000"
    read -p "Network ID: " ZEROTIER_NETWORK_ID
    
    if [ -z "$ZEROTIER_NETWORK_ID" ]; then
        log_error "Network ID is required"
    fi
fi

echo ""
log_info "Configuration:"
echo "  Site: $SITE_NAME"
echo "  Network ID: $ZEROTIER_NETWORK_ID"
echo ""

# Check if ZeroTier is already installed
if command -v zerotier-cli &> /dev/null; then
    log_info "ZeroTier is already installed"
    ZEROTIER_VERSION=$(zerotier-cli --version 2>&1 || echo "unknown")
    log_info "Version: $ZEROTIER_VERSION"
else
    log_info "Installing ZeroTier..."
    
    # Install ZeroTier
    curl -s https://install.zerotier.com | bash
    
    if [ $? -eq 0 ]; then
        log_success "ZeroTier installed successfully"
    else
        log_error "Failed to install ZeroTier"
    fi
    
    # Wait for service to start
    sleep 2
fi

# Check ZeroTier service status
log_info "Checking ZeroTier service..."
if systemctl is-active --quiet zerotier-one; then
    log_success "ZeroTier service is running"
else
    log_warning "ZeroTier service not running, attempting to start..."
    systemctl start zerotier-one
    systemctl enable zerotier-one
    sleep 2
    
    if systemctl is-active --quiet zerotier-one; then
        log_success "ZeroTier service started"
    else
        log_error "Failed to start ZeroTier service"
    fi
fi

# Get ZeroTier node address
NODE_ADDRESS=$(zerotier-cli info | awk '{print $3}')
log_info "ZeroTier Node Address: $NODE_ADDRESS"

# Check if already joined to network
CURRENT_NETWORKS=$(zerotier-cli listnetworks | tail -n +2 | awk '{print $3}')

if echo "$CURRENT_NETWORKS" | grep -q "$ZEROTIER_NETWORK_ID"; then
    log_success "Already joined to network $ZEROTIER_NETWORK_ID"
else
    log_info "Joining network $ZEROTIER_NETWORK_ID..."
    zerotier-cli join "$ZEROTIER_NETWORK_ID"
    
    if [ $? -eq 0 ]; then
        log_success "Joined network successfully"
    else
        log_error "Failed to join network"
    fi
    
    # Wait for network to be configured
    sleep 3
fi

# Display network status
log_info "Network Status:"
zerotier-cli listnetworks

# Get assigned IP if available
ZT_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)10\.147\.17\.\d+' | head -1)

if [ -n "$ZT_IP" ]; then
    log_success "ZeroTier IP assigned: $ZT_IP"
else
    log_warning "No IP assigned yet - node may need authorization"
    log_warning "Authorize this node in ztnet UI:"
    log_warning "  1. Open http://localhost:3000 (or ztnet controller)"
    log_warning "  2. Go to Networks → Members"
    log_warning "  3. Find node: $NODE_ADDRESS"
    log_warning "  4. Check 'Authorized'"
fi

# Set hostname description
HOSTNAME=$(hostname)
log_info "Setting node description to: proxmox-$SITE_NAME ($HOSTNAME)"

# Note: Node description must be set via API or UI, zerotier-cli doesn't support it
log_warning "Set node description in ztnet UI:"
log_warning "  Node: $NODE_ADDRESS"
log_warning "  Description: proxmox-$SITE_NAME ($HOSTNAME)"

# Test connectivity
log_info "Testing ZeroTier connectivity..."

# Try to ping controller (typically .1)
if ping -c 2 -W 2 10.147.17.1 &> /dev/null; then
    log_success "Can reach ZeroTier network (controller at 10.147.17.1)"
else
    log_warning "Cannot reach controller - network may still be initializing"
fi

# Display final status
echo ""
log_info "╔════════════════════════════════════════╗"
log_info "║  Setup Complete                        ║"
log_info "╚════════════════════════════════════════╝"
echo ""
echo "Summary:"
echo "  Site: $SITE_NAME"
echo "  Node Address: $NODE_ADDRESS"
echo "  Network ID: $ZEROTIER_NETWORK_ID"
echo "  ZeroTier IP: ${ZT_IP:-Pending authorization}"
echo ""
echo "Next steps:"
echo "  1. Authorize node in ztnet UI if not already authorized"
echo "  2. Verify IP assignment: zerotier-cli listnetworks"
echo "  3. Test connectivity: ping 10.147.17.1"
echo "  4. Repeat this script on the other Proxmox host"
echo ""

# Save configuration
cat > /root/zerotier-homelab.conf << EOF
# HomeLab ZeroTier Configuration
# Generated: $(date)
SITE_NAME="$SITE_NAME"
ZEROTIER_NETWORK_ID="$ZEROTIER_NETWORK_ID"
NODE_ADDRESS="$NODE_ADDRESS"
ZEROTIER_IP="$ZT_IP"
EOF

log_success "Configuration saved to /root/zerotier-homelab.conf"
