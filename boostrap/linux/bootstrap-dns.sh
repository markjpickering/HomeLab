#!/usr/bin/env bash
#
# Bootstrap Technitium DNS Server
# This script deploys the DNS infrastructure for the HomeLab
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TECHNITIUM_DIR="${REPO_ROOT}/boostrap/technitium"

echo_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

echo_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    echo_info "Checking prerequisites..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        echo_error "Docker is not installed"
        exit 1
    fi
    
    # Check docker-compose
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        echo_error "docker-compose is not installed"
        exit 1
    fi
    
    echo_success "Prerequisites check passed"
}

# Generate secrets
generate_secrets() {
    echo_info "Generating secrets..."
    
    cd "${TECHNITIUM_DIR}"
    
    if [[ -f .env ]]; then
        echo_warn ".env file already exists, skipping generation"
        return
    fi
    
    # Generate admin password
    ADMIN_PASSWORD=$(openssl rand -base64 32)
    
    cat > .env << EOF
# Technitium DNS Server Configuration
# Generated on $(date)

TECHNITIUM_ADMIN_PASSWORD=${ADMIN_PASSWORD}
EOF
    
    chmod 600 .env
    
    echo_success "Secrets generated in ${TECHNITIUM_DIR}/.env"
    echo_warn "Admin password: ${ADMIN_PASSWORD}"
    echo_warn "Save this password securely!"
}

# Deploy Technitium DNS
deploy_technitium() {
    echo_info "Deploying Technitium DNS Server..."
    
    cd "${TECHNITIUM_DIR}"
    
    # Create directories
    mkdir -p config logs
    
    # Start containers
    if docker compose version &> /dev/null; then
        docker compose up -d
    else
        docker-compose up -d
    fi
    
    echo_success "Technitium DNS deployed"
}

# Wait for Technitium to be ready
wait_for_technitium() {
    echo_info "Waiting for Technitium DNS to be ready..."
    
    local max_attempts=30
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        if curl -sf http://localhost:5380 > /dev/null 2>&1; then
            echo_success "Technitium DNS is ready"
            return 0
        fi
        
        attempt=$((attempt + 1))
        echo_info "Attempt $attempt/$max_attempts: Waiting for Technitium..."
        sleep 5
    done
    
    echo_error "Technitium DNS did not become ready in time"
    return 1
}

# Configure DNS zones
configure_zones() {
    echo_info "Configuring DNS zones..."
    
    # Load admin password
    source "${TECHNITIUM_DIR}/.env"
    
    # Get API token (requires manual login first)
    echo ""
    echo_warn "Manual step required:"
    echo "1. Open http://localhost:5380 in your browser"
    echo "2. Login with username 'admin' and the password from .env"
    echo "3. Go to Settings → API Access"
    echo "4. Generate an API token"
    echo ""
    
    read -p "Press Enter once you have the API token..."
    read -p "Enter API token: " API_TOKEN
    
    if [[ -z "$API_TOKEN" ]]; then
        echo_warn "No API token provided, skipping zone configuration"
        return
    fi
    
    # Save API token
    echo "TECHNITIUM_API_TOKEN=${API_TOKEN}" >> "${TECHNITIUM_DIR}/.env"
    
    # Create zones
    echo_info "Creating DNS zones..."
    
    # Primary zone
    curl -s -X POST "http://localhost:5380/api/zones/create" \
        -H "Authorization: Bearer ${API_TOKEN}" \
        -d "domain=homelab.internal&type=Primary" > /dev/null
    
    # Subdomain zones
    for subdomain in site-a site-b shared; do
        curl -s -X POST "http://localhost:5380/api/zones/create" \
            -H "Authorization: Bearer ${API_TOKEN}" \
            -d "domain=${subdomain}.homelab.internal&type=Primary" > /dev/null
        echo_info "Created zone: ${subdomain}.homelab.internal"
    done
    
    echo_success "DNS zones configured"
}

# Show status
show_status() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo_success "Technitium DNS Setup Complete!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Web UI: http://localhost:5380"
    echo "Username: admin"
    echo "Password: (see ${TECHNITIUM_DIR}/.env)"
    echo ""
    echo "DNS Server: localhost:53"
    echo ""
    echo "Next steps:"
    echo "1. Access the web UI and complete initial setup"
    echo "2. Configure zone transfers for secondary DNS"
    echo "3. Deploy external-dns in Kubernetes clusters"
    echo "4. Update client DNS settings to use this server"
    echo ""
    echo "For more information, see docs/DNS-ARCHITECTURE.md"
    echo ""
}

# Main function
main() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Technitium DNS Bootstrap"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    check_prerequisites
    generate_secrets
    deploy_technitium
    wait_for_technitium
    
    # Optional zone configuration
    read -p "Do you want to configure DNS zones now? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        configure_zones
    else
        echo_info "Skipping zone configuration (can be done later via web UI)"
    fi
    
    show_status
}

# Run main
main "$@"
