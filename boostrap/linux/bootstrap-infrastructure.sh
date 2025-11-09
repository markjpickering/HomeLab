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
#   -y, --yes              Non-interactive mode (use defaults/skip prompts)
#   -p, --phase <1-6>      Run specific phase (1=all, 2=ztnet, 3=network, 4=provision, 5=k8s, 6=provision+k8s)
#   -h, --help             Show this help

set -e

# Parse arguments
NON_INTERACTIVE=false
PHASE_CHOICE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -y|--yes)
            NON_INTERACTIVE=true
            shift
            ;;
        -p|--phase)
            PHASE_CHOICE="$2"
            shift 2
            ;;
        -h|--help)
            head -n 15 "$0" | grep "#" | sed 's/^# //g'
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

# Check prerequisites
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
            if [ "$NON_INTERACTIVE" = false ]; then
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
                
                if [ "$NON_INTERACTIVE" = false ]; then
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
    
    if [ "$NON_INTERACTIVE" = false ]; then
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
        if [ "$NON_INTERACTIVE" = true ]; then
            log_error "Non-interactive mode requires HOMELAB_ZEROTIER_NETWORK_ID environment variable"
        fi
        
        log_warning "Manual step required:"
        echo "  1. Go to http://localhost:3000"
        echo "  2. Create a new ZeroTier network"
        echo "  3. Configure the network settings:"
        echo "     - Name: ${HOMELAB_ZEROTIER_NETWORK_NAME:-HomeLabK8s}"
        echo "     - IPv4 Auto-Assign: Enable (e.g., ${HOMELAB_ZEROTIER_SUBNET:-10.147.17.0/24})"
        echo "  4. Copy the Network ID (16-character hex)"
        echo ""
        
        read -p "Enter your ZeroTier Network ID: " ZEROTIER_NETWORK_ID
        
        if [ -z "$ZEROTIER_NETWORK_ID" ]; then
            log_error "Network ID cannot be empty"
        fi
    else
        log_info "Using provided Network ID: $ZEROTIER_NETWORK_ID"
    fi
    
    # Save network ID for later use
    echo "$ZEROTIER_NETWORK_ID" > "$REPO_ROOT/.zerotier-network-id"
    
    # Export for Terraform
    export TF_VAR_zerotier_network_id="$ZEROTIER_NETWORK_ID"
    
    log_success "Network ID saved: $ZEROTIER_NETWORK_ID"
    
    # Join bootstrap host to network (optional but recommended)
    if [ "${HOMELAB_JOIN_BOOTSTRAP_HOST:-false}" = "true" ] || [ "$NON_INTERACTIVE" = false ]; then
        if [ "$NON_INTERACTIVE" = false ]; then
            log_info "Do you want to join this bootstrap host to the ZeroTier network?"
            read -p "(recommended for accessing k8s cluster later) [y/N]: " -n 1 -r
            echo
            JOIN_NETWORK=$REPLY
        else
            JOIN_NETWORK="${HOMELAB_JOIN_BOOTSTRAP_HOST:-n}"
        fi
        
        if [[ $JOIN_NETWORK =~ ^[Yy]$ ]]; then
            if ! command -v zerotier-cli &> /dev/null; then
                log_info "Installing ZeroTier client..."
                curl -s https://install.zerotier.com | sudo bash
            fi
            sudo zerotier-cli join "$ZEROTIER_NETWORK_ID"
            log_success "Bootstrap host joined network"
            log_warning "Remember to authorize this node in the ztnet web UI"
        fi
    fi
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
    if [ "$NON_INTERACTIVE" = true ]; then
        terraform plan -out=tfplan
        log_info "Applying Terraform configuration (non-interactive mode)..."
        terraform apply -auto-approve tfplan
    else
        terraform plan -out=tfplan
        
        log_warning "Review the plan above. Ready to apply?"
        read -p "Continue? [y/N]: " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_error "Terraform apply cancelled by user"
        fi
        
        log_info "Applying Terraform configuration..."
        terraform apply tfplan
    fi
    
    log_success "Infrastructure provisioned!"
    
    # Wait for nodes to join ZeroTier
    log_info "Waiting for nodes to join ZeroTier network..."
    
    if [ "$NON_INTERACTIVE" = false ]; then
        log_warning "Go to http://localhost:3000 and authorize all new nodes"
        read -p "Press Enter after authorizing all nodes..."
    else
        log_warning "Make sure to authorize nodes at http://localhost:3000"
        log_info "Waiting 30 seconds for nodes to join and be authorized..."
        sleep 30
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
    
    check_prerequisites
    
    # Ask which phases to run (if not provided as argument)
    if [ -z "$PHASE_CHOICE" ]; then
        if [ "$NON_INTERACTIVE" = true ]; then
            log_info "Non-interactive mode: Running complete bootstrap (all phases)"
            PHASE_CHOICE="1"
        else
            echo ""
            log_info "Select which phases to run:"
            echo "  1) Complete bootstrap (all phases)"
            echo "  2) Phase 1 only (Deploy ztnet)"
            echo "  3) Phase 2 only (Create network)"
            echo "  4) Phase 3 only (Provision infrastructure)"
            echo "  5) Phase 4 only (Configure Kubernetes)"
            echo "  6) Phases 3+4 (Provision & Configure)"
            read -p "Enter choice [1-6]: " PHASE_CHOICE
        fi
    fi
    
    case $PHASE_CHOICE in
        1)
            phase1_deploy_ztnet
            phase2_create_network
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
            phase3_provision_infrastructure
            ;;
        5)
            phase4_configure_kubernetes
            ;;
        6)
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
}

# Run main function
main "$@"
