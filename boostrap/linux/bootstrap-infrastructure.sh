#!/bin/bash
# HomeLab Infrastructure Bootstrap - Complete Automation
# This script orchestrates the complete 4-phase bootstrap process:
# Phase 1: Deploy ztnet controller
# Phase 2: Create ZeroTier network
# Phase 3: Provision k8s nodes with Terraform
# Phase 4: Configure k8s with Ansible
#
# Usage:
#   bootstrap-infrastructure.sh [options]
#
# Options:
#   -i, --interactive       Interactive mode (prompt for confirmations)
#   -s, --site <site>       Bootstrap single site only (primary|secondary)
#   -p, --phase <1-6>       Run specific phase (1=all, 2=ztnet, 3=network, 4=provision, 5=k8s, 6=provision+k8s)
#   -v, --validate-only     Validate configuration and exit
#   -h, --help              Show this help
#
# Default behavior: Non-interactive, both sites

set -e

# Parse arguments
INTERACTIVE_MODE=false
SINGLE_SITE=""
PHASE_CHOICE=""
VALIDATE_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--interactive)
            INTERACTIVE_MODE=true
            shift
            ;;
        -s|--site)
            SINGLE_SITE="$2"
            shift 2
            ;;
        -p|--phase)
            PHASE_CHOICE="$2"
            shift 2
            ;;
        -v|--validate-only)
            VALIDATE_ONLY=true
            shift
            ;;
        -h|--help)
            head -n 20 "$0" | grep "#" | sed 's/^# //g'
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load configuration
CONFIG_FILE="$REPO_ROOT/boostrap/config.sh"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# Set directory variables (with fallbacks)
ZTNET_DIR="$REPO_ROOT/boostrap/ztnet"
TERRAFORM_DIR="$REPO_ROOT/${HOMELAB_TF_DIR:-k8s-infra/terraform}"
ANSIBLE_DIR="$REPO_ROOT/${HOMELAB_ANSIBLE_DIR:-k8s-infra/ansible}"

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

wait_for_service() {
    local url=$1
    local max_attempts=30
    local attempt=1
    
    log_info "Waiting for service at $url..."
    while [ $attempt -le $max_attempts ]; do
        if curl -sf "$url" > /dev/null 2>&1; then
            log_success "Service is ready!"
            return 0
        fi
        echo -n "."
        sleep 2
        attempt=$((attempt + 1))
    done
    log_error "Service did not become ready in time"
}

# ZeroTier controller API helpers (via localhost:9993 exposed in compose)
zt_read_token() {
    local token_file="$ZTNET_DIR/zerotier-one/authtoken.secret"
    if [ ! -f "$token_file" ]; then
        log_error "ZeroTier controller token not found at $token_file. Is ztnet running?"
    fi
    cat "$token_file"
}

zt_api() {
    local method="$1"; shift
    local path="$1"; shift
    local data="${1:-}"
    local token
    token=$(zt_read_token)
    if [ -n "$data" ]; then
        curl -sS -X "$method" -H "X-ZT1-Auth: $token" -H "Content-Type: application/json" --data "$data" "http://127.0.0.1:9993$path"
    else
        curl -sS -X "$method" -H "X-ZT1-Auth: $token" "http://127.0.0.1:9993$path"
    fi
}

create_zerotier_network() {
    local name="${HOMELAB_ZEROTIER_NETWORK_NAME:-HomeLabK8s}"
    local desc="${HOMELAB_ZEROTIER_NETWORK_DESCRIPTION:-HomeLab Kubernetes overlay network}"
    local subnet="${HOMELAB_ZEROTIER_SUBNET:-10.147.17.0/24}"

    log_info "Creating ZeroTier network automatically (name: $name, subnet: $subnet)"

    # Ensure controller API is up
    local status
    status=$(zt_api GET "/status" || true)
    if [ -z "$status" ]; then
        log_error "Controller API not responding on 127.0.0.1:9993"
    fi
    local address
    address=$(echo "$status" | jq -r '.address')
    if [ -z "$address" ] || [ "$address" = "null" ]; then
        log_error "Unable to read controller address from /status"
    fi

    # Derive a network ID: controller address (10 hex) + 6 random hex chars
    local tail
    tail=$(head -c 3 /dev/urandom | hexdump -v -e '/1 "%02x"')
    local net_id="${address}${tail}"

    # Derive IP pool start/end from subnet (basic /24 handling)
    local base
    base=$(echo "$subnet" | cut -d'/' -f1)
    local pool_start pool_end route
    if echo "$base" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' && echo "$subnet" | grep -q '/24'; then
        pool_start="$(echo "$base" | awk -F. '{printf "%d.%d.%d.10", $1,$2,$3}')"
        pool_end="$(echo "$base" | awk -F. '{printf "%d.%d.%d.250", $1,$2,$3}')"
        route="$(echo "$base" | awk -F. '{printf "%d.%d.%d.0/24", $1,$2,$3}')"
    else
        # Fallback defaults
        pool_start="10.147.17.10"
        pool_end="10.147.17.250"
        route="10.147.17.0/24"
    fi

    # Compose config
    local cfg
    cfg=$(jq -nc \
        --arg name "$name" \
        --arg desc "$desc" \
        --arg start "$pool_start" \
        --arg end "$pool_end" \
        --arg route "$route" \
        '{
            name: $name,
            description: $desc,
            v4AssignMode: { zt: true },
            routes: [{ target: $route }],
            ipAssignmentPools: [{ ipRangeStart: $start, ipRangeEnd: $end }]
        }')

    # Try create (POST), fall back to PUT
    local resp
    resp=$(zt_api POST "/controller/network/$net_id" "$cfg" || true)
    if [ -z "$resp" ] || echo "$resp" | jq -e '.id? // empty' >/dev/null 2>&1; then
        : # likely created
    else
        resp=$(zt_api PUT "/controller/network/$net_id" "$cfg" || true)
    fi

    # Read back to confirm
    local verify
    verify=$(zt_api GET "/controller/network/$net_id" || true)
    if [ -z "$verify" ] || ! echo "$verify" | jq -e '.id? // empty' >/dev/null 2>&1; then
        log_error "Failed to create or read network $net_id via controller API"
    fi

    echo "$net_id"
}

authorize_all_members() {
    local net_id="$1"
    log_info "Authorizing all members on network $net_id"
    local members
    members=$(zt_api GET "/controller/network/$net_id/member" || true)
    if [ -z "$members" ]; then
        log_warning "No members returned yet; skipping authorization"
        return 0
    fi
    echo "$members" | jq -r 'keys[]' | while read -r mid; do
        zt_api POST "/controller/network/$net_id/member/$mid" '{"authorized":true}' >/dev/null 2>&1 || true
    done
    log_success "Members authorized (where present)"
}

# Optional: Transfer controller hosting to a remote host
transfer_controller() {
    local remote_host="${HOMELAB_ZTNET_REMOTE_HOST:-}"
    local remote_dir="${HOMELAB_ZTNET_REMOTE_DIR:-/opt/ztnet}"
    if [ -z "$remote_host" ]; then
        return 0
    fi

    log_info "Preparing to transfer controller to $remote_host ($remote_dir)"

    if [ "$INTERACTIVE_MODE" = true ]; then
        read -p "Proceed with controller transfer now? [y/N]: " -n 1 -r; echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_warning "Controller transfer skipped by user"
            return 0
        fi
    fi

    # Ensure ssh/scp present
    if ! command -v ssh >/dev/null 2>&1 || ! command -v scp >/dev/null 2>&1; then
        log_error "ssh/scp not available on bootstrap host. Install openssh-client."
    fi

    # Create remote dir and copy compose + env + controller identity
    log_info "Copying ztnet stack to remote host..."
    ssh -o StrictHostKeyChecking=no "$remote_host" "sudo mkdir -p '$remote_dir' && sudo chown \$(id -u):\$(id -g) '$remote_dir'"
    scp "$ZTNET_DIR/docker-compose.yml" "$ZTNET_DIR/.env" "$remote_host":"$remote_dir/" >/dev/null
    ssh "$remote_host" "mkdir -p '$remote_dir/zerotier-one'"
    scp -r "$ZTNET_DIR/zerotier-one/"* "$remote_host":"$remote_dir/zerotier-one/" >/dev/null

    # Install Docker on remote if missing, then start stack
    log_info "Ensuring Docker on remote host..."
    ssh "$remote_host" 'bash -s' << 'EOSSH'
set -e
if ! command -v docker >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq
    apt-get install -y -qq apt-transport-https ca-certificates curl gnupg lsb-release
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable docker || true
    systemctl start docker || true
  else
    echo "Docker is required on remote host" >&2
    exit 1
  fi
fi
EOSSH

    log_info "Starting ztnet on remote host..."
    ssh "$remote_host" "cd '$remote_dir' && docker compose up -d"

    # Stop local controller
    log_info "Stopping local ztnet stack..."
    (cd "$ZTNET_DIR" && docker-compose down -v) || true
    log_success "Controller transferred to $remote_host"
}

# Comprehensive pre-flight validation
validate_configuration() {
    log_info "========================================"
    log_info "Pre-Flight Configuration Validation"
    log_info "========================================"
    echo ""
    
    local errors=()
    local warnings=()
    
    # 1. Check required environment variables
    log_info "[1/8] Checking required configuration variables..."
    
    if [ -z "${HOMELAB_REPO_URL}" ] || [ "${HOMELAB_REPO_URL}" = "https://github.com/YOUR_USERNAME/HomeLab.git" ]; then
        errors+=("HOMELAB_REPO_URL not configured in boostrap/config.sh")
    fi
    
    if [ -z "${HOMELAB_DNS_DOMAIN}" ]; then
        errors+=("HOMELAB_DNS_DOMAIN not set")
    fi
    
    if [ -z "${HOMELAB_PRIMARY_SITE_ID}" ] || [ -z "${HOMELAB_SECONDARY_SITE_ID}" ]; then
        errors+=("Site IDs not configured")
    fi
    
    if [ -z "${HOMELAB_ZEROTIER_SUBNET}" ]; then
        errors+=("HOMELAB_ZEROTIER_SUBNET not set")
    fi
    
    # 2. Check tool prerequisites
    log_info "[2/8] Checking required tools..."
    
    local missing_tools=()
    command -v docker &> /dev/null || missing_tools+=("docker")
    command -v docker-compose &> /dev/null || missing_tools+=("docker-compose")
    command -v terraform &> /dev/null || missing_tools+=("terraform")
    command -v ansible &> /dev/null || missing_tools+=("ansible")
    command -v jq &> /dev/null || missing_tools+=("jq")
    command -v sops &> /dev/null || missing_tools+=("sops")
    command -v age &> /dev/null || missing_tools+=("age")
    command -v curl &> /dev/null || missing_tools+=("curl")
    command -v ssh &> /dev/null || missing_tools+=("ssh")
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        errors+=("Missing required tools: ${missing_tools[*]}")
    fi
    
    # 3. Validate single-site parameter
    log_info "[3/8] Validating site configuration..."
    
    if [ -n "$SINGLE_SITE" ]; then
        if [ "$SINGLE_SITE" != "primary" ] && [ "$SINGLE_SITE" != "secondary" ]; then
            errors+=("Invalid --site value: '$SINGLE_SITE' (must be 'primary' or 'secondary')")
        else
            log_info "Single-site mode: $SINGLE_SITE"
        fi
    else
        log_info "Multi-site mode: both sites will be configured"
    fi
    
    # 4. Check directory structure
    log_info "[4/8] Checking directory structure..."
    
    if [ ! -d "$ZTNET_DIR" ]; then
        errors+=("ztnet directory not found: $ZTNET_DIR")
    fi
    
    if [ ! -d "$TERRAFORM_DIR" ]; then
        errors+=("Terraform directory not found: $TERRAFORM_DIR")
    fi
    
    if [ ! -d "$ANSIBLE_DIR" ]; then
        errors+=("Ansible directory not found: $ANSIBLE_DIR")
    fi
    
    if [ ! -f "$CONFIG_FILE" ]; then
        warnings+=("Configuration file not found: $CONFIG_FILE")
    fi
    
    # 5. Check Docker service
    log_info "[5/8] Checking Docker service..."
    
    if ! docker ps &> /dev/null; then
        errors+=("Docker daemon not running or insufficient permissions")
    fi
    
    # 6. Validate IP ranges
    log_info "[6/8] Validating IP address configuration..."
    
    # Check for IP conflicts
    local ips=(
        "$HOMELAB_PRIMARY_SERVER_IP"
        "$HOMELAB_PRIMARY_AGENT1_IP"
        "$HOMELAB_PRIMARY_AGENT2_IP"
        "$HOMELAB_SECONDARY_SERVER_IP"
        "$HOMELAB_SECONDARY_AGENT1_IP"
        "$HOMELAB_SECONDARY_AGENT2_IP"
        "$HOMELAB_PRIMARY_DNS_IP"
        "$HOMELAB_SECONDARY_DNS_IP"
        "$HOMELAB_VAULT_VIP"
        "$HOMELAB_REGISTRY_VIP"
        "$HOMELAB_MINIO_VIP"
        "$HOMELAB_PROXY_VIP"
    )
    
    local unique_ips=$(printf '%s\n' "${ips[@]}" | sort -u | wc -l)
    if [ ${#ips[@]} -ne $unique_ips ]; then
        errors+=("Duplicate IP addresses detected in configuration")
    fi
    
    # Validate IPs are in subnet
    local subnet_base=$(echo "$HOMELAB_ZEROTIER_SUBNET" | cut -d'/' -f1 | cut -d'.' -f1-3)
    for ip in "${ips[@]}"; do
        if [ -n "$ip" ]; then
            local ip_base=$(echo "$ip" | cut -d'.' -f1-3)
            if [ "$ip_base" != "$subnet_base" ]; then
                warnings+=("IP $ip may be outside configured subnet $HOMELAB_ZEROTIER_SUBNET")
            fi
        fi
    done
    
    # 7. Check SOPS/Age setup
    log_info "[7/8] Checking SOPS/Age configuration..."
    
    local age_key_file="${HOMELAB_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
    if [ ! -f "$age_key_file" ]; then
        warnings+=("Age key not found at $age_key_file (will be generated if needed)")
    fi
    
    if [ ! -f "$REPO_ROOT/.sops.yaml" ]; then
        warnings+=(".sops.yaml not found in repository root")
    fi
    
    # 8. Check Terraform secrets
    log_info "[8/8] Checking Terraform secrets..."
    
    local secrets_file="$TERRAFORM_DIR/${HOMELAB_TF_SECRETS_FILE:-secrets.enc.yaml}"
    if [ ! -f "$secrets_file" ]; then
        warnings+=("Terraform secrets file not found: $secrets_file")
    elif ! grep -q "sops:" "$secrets_file" || ! grep -q "age:" "$secrets_file"; then
        errors+=("Terraform secrets file exists but is not encrypted with SOPS")
    fi
    
    # Report results
    echo ""
    log_info "========================================"
    log_info "Validation Results"
    log_info "========================================"
    echo ""
    
    if [ ${#warnings[@]} -gt 0 ]; then
        log_warning "Found ${#warnings[@]} warning(s):"
        for warning in "${warnings[@]}"; do
            echo -e "  ${YELLOW}⚠️  $warning${NC}"
        done
        echo ""
    fi
    
    if [ ${#errors[@]} -gt 0 ]; then
        log_error "Found ${#errors[@]} error(s):"
        for error in "${errors[@]}"; do
            echo -e "  ${RED}❌ $error${NC}"
        done
        echo ""
        log_error "Please fix the above errors before proceeding."
    fi
    
    log_success "✅ Configuration validation passed!"
    echo ""
    
    # Display summary
    if [ -n "$SINGLE_SITE" ]; then
        log_info "Bootstrap mode: Single site ($SINGLE_SITE)"
    else
        log_info "Bootstrap mode: Multi-site (primary + secondary)"
    fi
    
    if [ "$INTERACTIVE_MODE" = true ]; then
        log_info "Interaction mode: Interactive (prompts enabled)"
    else
        log_info "Interaction mode: Non-interactive (automated)"
    fi
    
    echo ""
}

# Check prerequisites (legacy, kept for backward compatibility)
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing=()
    command -v docker &> /dev/null || missing+=("docker")
    command -v docker-compose &> /dev/null || missing+=("docker-compose")
    command -v terraform &> /dev/null || missing+=("terraform")
    command -v ansible &> /dev/null || missing+=("ansible")
    command -v jq &> /dev/null || missing+=("jq")
    command -v sops &> /dev/null || missing+=("sops")
    command -v age &> /dev/null || missing+=("age")
    
    if [ ${#missing[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing[*]}"
    fi
    
    log_success "All prerequisites installed"
}

# Check SOPS setup
check_sops_setup() {
    log_info "Checking SOPS configuration..."
    
    # Check if age key exists
    local age_key_file="${HOMELAB_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
    if [ ! -f "$age_key_file" ]; then
        log_warning "Age key not found at $age_key_file"
        log_info "Generating age key..."
        mkdir -p "$(dirname "$age_key_file")"
        age-keygen -o "$age_key_file"
        log_success "Age key generated"
        
        # Display public key
        local public_key=$(grep "public key:" "$age_key_file" | cut -d: -f2 | tr -d ' ')
        log_info "Your age public key: $public_key"
        log_warning "Make sure this key is in .sops.yaml"
    fi
    
    # Check if .sops.yaml exists
    if [ ! -f "$REPO_ROOT/.sops.yaml" ]; then
        log_error ".sops.yaml not found in repository root"
    fi
    
    log_success "SOPS configuration OK"
}

# Check Terraform secrets
check_terraform_secrets() {
    log_info "Checking Terraform secrets..."
    
    local secrets_file="$TERRAFORM_DIR/${HOMELAB_TF_SECRETS_FILE:-secrets.enc.yaml}"
    local example_file="$TERRAFORM_DIR/${HOMELAB_TF_SECRETS_FILE:-secrets.enc.yaml}.example"
    
    if [ ! -f "$secrets_file" ]; then
        log_warning "Encrypted secrets file not found: $secrets_file"
        
        if [ -f "$example_file" ]; then
            if [ "$INTERACTIVE_MODE" = true ]; then
                log_info "Example file exists. You need to:"
                echo "  1. Copy the example: cp $example_file $secrets_file"
                echo "  2. Edit with your values: sops $secrets_file"
                echo "  3. SOPS will encrypt it automatically"
                echo ""
                read -p "Create secrets file now? [y/N]: " -n 1 -r
                echo
                CREATE_NOW=$REPLY
            else
                # In non-interactive mode, create from example
                CREATE_NOW="y"
            fi
            
            if [[ $CREATE_NOW =~ ^[Yy]$ ]]; then
                cp "$example_file" "$secrets_file"
                
                if [ "$INTERACTIVE_MODE" = true ]; then
                    log_info "Opening secrets file in SOPS editor..."
                    sops "$secrets_file"
                    log_success "Secrets file created and encrypted"
                else
                    log_success "Secrets file created from example"
                    log_warning "Edit later with: sops $secrets_file"
                fi
            else
                log_error "Terraform requires secrets.enc.yaml to proceed"
            fi
        else
            log_error "No secrets file or example found. Create one manually."
        fi
    else
        # Verify file is encrypted
        if grep -q "sops:" "$secrets_file" && grep -q "age:" "$secrets_file"; then
            log_success "Encrypted secrets file exists"
        else
            log_error "secrets.enc.yaml exists but doesn't appear to be encrypted"
        fi
    fi
}

# Phase 1: Deploy ztnet Controller
phase1_deploy_ztnet() {
    echo ""
    log_info "========================================"
    log_info "PHASE 1: Deploy ztnet Controller"
    log_info "========================================"
    
    cd "$ZTNET_DIR"
    
    # Generate secrets if .env doesn't exist
    if [ ! -f .env ]; then
        log_info "Generating secrets..."
        cat > .env << EOF
NEXTAUTH_SECRET=$(openssl rand -base64 32)
POSTGRES_PASSWORD=$(openssl rand -base64 24)
EOF
        log_success "Secrets generated in $ZTNET_DIR/.env"
    else
        log_warning ".env already exists, using existing configuration"
    fi
    
    # Deploy ztnet
    log_info "Starting ztnet controller..."
    docker-compose up -d
    
    # Wait for ztnet to be ready
    wait_for_service "http://localhost:3000"
    
    log_success "ztnet controller is running at http://localhost:3000"
    
    if [ "$INTERACTIVE_MODE" = true ]; then
        log_warning "IMPORTANT: Access http://localhost:3000 and create your admin account NOW"
        echo ""
        read -p "Press Enter after you've created your admin account..."
    else
        log_info "Running in non-interactive mode"
        log_warning "Make sure to create admin account at http://localhost:3000"
        log_info "Waiting 10 seconds for initial setup..."
        sleep 10
    fi
}

# Phase 2: Create ZeroTier Network
phase2_create_network() {
    echo ""
    log_info "========================================"
    log_info "PHASE 2: Create ZeroTier Network"
    log_info "========================================"
    
    # Check if network ID already provided
    ZEROTIER_NETWORK_ID="${HOMELAB_ZEROTIER_NETWORK_ID:-}"

    if [ -z "$ZEROTIER_NETWORK_ID" ]; then
        # Create network automatically via controller API
        ZEROTIER_NETWORK_ID=$(create_zerotier_network)
        log_success "ZeroTier network created: $ZEROTIER_NETWORK_ID"
    else
        log_info "Using provided Network ID: $ZEROTIER_NETWORK_ID"
    fi
    
    # Save network ID for later use
    echo "$ZEROTIER_NETWORK_ID" > "$REPO_ROOT/.zerotier-network-id"
    
    # Export for Terraform
    export TF_VAR_zerotier_network_id="$ZEROTIER_NETWORK_ID"
    
    log_success "Network ID saved: $ZEROTIER_NETWORK_ID"
    
    # Join bootstrap host to network based on preference
    if [ "$INTERACTIVE_MODE" = true ]; then
        log_info "Join this bootstrap host to the ZeroTier network?"
        read -p "[y/N]: " -n 1 -r; echo
        JOIN_NETWORK=$REPLY
    else
        JOIN_NETWORK="$HOMELAB_JOIN_BOOTSTRAP_HOST"
    fi
    if [[ "$JOIN_NETWORK" =~ ^[Yy]$ ]]; then
        if ! command -v zerotier-cli &> /dev/null; then
            log_info "Installing ZeroTier client..."
            curl -s https://install.zerotier.com | sudo bash
        fi
        sudo zerotier-cli join "$ZEROTIER_NETWORK_ID"
        log_success "Bootstrap host joined network"
    fi
}

# Phase 2.5: Setup ZeroTier on Proxmox Hosts
phase25_setup_proxmox_zerotier() {
    echo ""
    log_info "========================================"
    log_info "PHASE 2.5: Setup Proxmox ZeroTier"
    log_info "========================================"
    
    # Check if Proxmox hosts are configured
    if [ -z "${HOMELAB_PROXMOX_PRIMARY_HOST:-}" ] && [ -z "${HOMELAB_PROXMOX_SECONDARY_HOST:-}" ]; then
        log_warning "No Proxmox hosts configured, skipping ZeroTier setup"
        log_warning "Set HOMELAB_PROXMOX_PRIMARY_HOST and HOMELAB_PROXMOX_SECONDARY_HOST to enable"
        return 0
    fi
    
    # Load network ID
    if [ ! -f "$REPO_ROOT/.zerotier-network-id" ]; then
        log_error "Network ID not found. Run phase 2 first."
    fi
    
    ZEROTIER_NETWORK_ID=$(cat "$REPO_ROOT/.zerotier-network-id")
    log_info "Network ID: $ZEROTIER_NETWORK_ID"
    
    # Setup script path
    local setup_script="$REPO_ROOT/scripts/setup-proxmox-zerotier.sh"
    
    if [ ! -f "$setup_script" ]; then
        log_error "Setup script not found: $setup_script"
    fi
    
    # Setup primary Proxmox host
    if [ -n "${HOMELAB_PROXMOX_PRIMARY_HOST:-}" ]; then
        log_info "Setting up ZeroTier on primary Proxmox host: $HOMELAB_PROXMOX_PRIMARY_HOST"
        
        # Copy script to Proxmox host
        scp -o StrictHostKeyChecking=no "$setup_script" "${HOMELAB_PROXMOX_PRIMARY_HOST}:/tmp/setup-zerotier.sh"
        
        # Run script on Proxmox host
        ssh -o StrictHostKeyChecking=no "${HOMELAB_PROXMOX_PRIMARY_HOST}" \
            "ZEROTIER_NETWORK_ID=$ZEROTIER_NETWORK_ID SITE_NAME=primary bash /tmp/setup-zerotier.sh"
        
        if [ $? -eq 0 ]; then
            log_success "Primary Proxmox host configured"
        else
            log_warning "Primary Proxmox setup had issues, check logs"
        fi
    fi
    
    # Setup secondary Proxmox host
    if [ -n "${HOMELAB_PROXMOX_SECONDARY_HOST:-}" ] && [ "$SINGLE_SITE" != "primary" ]; then
        log_info "Setting up ZeroTier on secondary Proxmox host: $HOMELAB_PROXMOX_SECONDARY_HOST"
        
        # Copy script to Proxmox host
        scp -o StrictHostKeyChecking=no "$setup_script" "${HOMELAB_PROXMOX_SECONDARY_HOST}:/tmp/setup-zerotier.sh"
        
        # Run script on Proxmox host
        ssh -o StrictHostKeyChecking=no "${HOMELAB_PROXMOX_SECONDARY_HOST}" \
            "ZEROTIER_NETWORK_ID=$ZEROTIER_NETWORK_ID SITE_NAME=secondary bash /tmp/setup-zerotier.sh"
        
        if [ $? -eq 0 ]; then
            log_success "Secondary Proxmox host configured"
        else
            log_warning "Secondary Proxmox setup had issues, check logs"
        fi
    fi
    
    # Wait for nodes to be authorized
    log_info "Waiting for Proxmox hosts to join network..."
    sleep 5
    
    # Auto-authorize if enabled
    if [ "${HOMELAB_ZT_AUTO_AUTHORIZE:-y}" = "y" ]; then
        log_info "Auto-authorizing new members..."
        authorize_all_members "$ZEROTIER_NETWORK_ID"
    else
        log_warning "Auto-authorization disabled"
        log_warning "Manually authorize Proxmox hosts in ztnet UI"
    fi
    
    log_success "Proxmox ZeroTier setup complete!"
}

# Phase 3: Provision Infrastructure with Terraform
phase3_provision_infrastructure() {
    echo ""
    log_info "========================================"
    log_info "PHASE 3: Provision Infrastructure"
    log_info "========================================"
    
    # Check SOPS setup
    check_sops_setup
    check_terraform_secrets
    
    cd "$TERRAFORM_DIR"
    
    # Load network ID
    if [ ! -f "$REPO_ROOT/.zerotier-network-id" ]; then
        log_error "Network ID not found. Run phase 2 first."
    fi
    
    ZEROTIER_NETWORK_ID=$(cat "$REPO_ROOT/.zerotier-network-id")
    export TF_VAR_zerotier_network_id="$ZEROTIER_NETWORK_ID"
    
    log_info "Initializing Terraform..."
    terraform init
    
    log_info "Planning infrastructure..."
    terraform plan -out=tfplan
    
    if [ "$INTERACTIVE_MODE" = true ]; then
        log_warning "Review the plan above. Ready to apply?"
        read -p "Continue? [y/N]: " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_error "Terraform apply cancelled by user"
        fi
        log_info "Applying Terraform configuration..."
        terraform apply tfplan
    else
        log_info "Applying Terraform configuration (non-interactive mode)..."
        terraform apply -auto-approve tfplan
    fi
    
    log_success "Infrastructure provisioned!"
    
    # Wait for nodes to join ZeroTier
    log_info "Waiting for nodes to join ZeroTier network..."
    # Basic wait loop for members to appear, then optionally auto-authorize
    sleep 10
    if [ "${HOMELAB_ZT_AUTO_AUTHORIZE:-y}" = "y" ]; then
        authorize_all_members "$ZEROTIER_NETWORK_ID"
    else
        log_warning "Auto-authorization disabled. Authorize nodes in the ztnet UI."
    fi
}

# Phase 4: Configure Kubernetes with Ansible
phase4_configure_kubernetes() {
    echo ""
    log_info "========================================"
    log_info "PHASE 4: Configure Kubernetes"
    log_info "========================================"
    
    cd "$ANSIBLE_DIR"
    
    # Generate inventory from ZeroTier network
    log_info "Generating Ansible inventory from ZeroTier network..."
    bash "$SCRIPT_DIR/generate-inventory.sh"
    
    log_info "Running Ansible playbook..."
    ansible-playbook -i inventory/hosts.ini site.yml
    
    log_success "Kubernetes cluster configured!"
}

# Main execution
main() {
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  HomeLab Infrastructure Bootstrap     ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo ""
    
    # Run validation
    validate_configuration
    
    # If validate-only flag is set, exit here
    if [ "$VALIDATE_ONLY" = true ]; then
        log_success "Validation complete. Exiting (--validate-only flag set)."
        exit 0
    fi
    
    # Set Terraform variables for single-site mode if applicable
    if [ -n "$SINGLE_SITE" ]; then
        export TF_VAR_single_site="$SINGLE_SITE"
        log_info "Single-site deployment: Only $SINGLE_SITE will be configured"
    fi
    
    # Ask which phases to run (if not provided as argument)
    if [ -z "$PHASE_CHOICE" ]; then
        if [ "$INTERACTIVE_MODE" = false ]; then
            log_info "Non-interactive mode: Running complete bootstrap (all phases)"
            PHASE_CHOICE="1"
        else
            echo ""
            log_info "Select which phases to run:"
            echo "  1) Complete bootstrap (all phases)"
            echo "  2) Phase 1 only (Deploy ztnet)"
            echo "  3) Phase 2 only (Create network)"
            echo "  4) Phase 2.5 only (Setup Proxmox ZeroTier)"
            echo "  5) Phase 3 only (Provision infrastructure)"
            echo "  6) Phase 4 only (Configure Kubernetes)"
            echo "  7) Phases 3+4 (Provision & Configure)"
            read -p "Enter choice [1-7]: " PHASE_CHOICE
        fi
    fi
    
    case $PHASE_CHOICE in
        1)
            phase1_deploy_ztnet
            phase2_create_network
            phase25_setup_proxmox_zerotier
            phase3_provision_infrastructure
            phase4_configure_kubernetes
            ;;
        2)
            phase1_deploy_ztnet
            ;;
        3)
            phase2_create_network
            ;;
        4)
            phase25_setup_proxmox_zerotier
            ;;
        5)
            phase3_provision_infrastructure
            ;;
        6)
            phase4_configure_kubernetes
            ;;
        7)
            phase3_provision_infrastructure
            phase4_configure_kubernetes
            ;;
        *)
            log_error "Invalid choice"
            ;;
    esac
    
    echo ""
    log_success "╔════════════════════════════════════════╗"
    log_success "║     Bootstrap Complete! 🎉             ║"
    log_success "╚════════════════════════════════════════╝"
    echo ""
    log_info "Next steps:"
    echo "  - Access ztnet: http://localhost:3000"
    echo "  - Check cluster: kubectl get nodes"
    echo "  - View services: kubectl get svc -A"

    # Optional controller transfer
    transfer_controller
}

# Run main function
main "$@"
