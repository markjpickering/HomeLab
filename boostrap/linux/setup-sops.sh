#!/bin/bash
# SOPS Setup Helper Script
# Generates age key and updates .sops.yaml configuration
#
# Usage:
#   setup-sops.sh [-y|--yes]
#
# Options:
#   -y, --yes    Non-interactive mode

set -e

# Parse arguments
NON_INTERACTIVE=false
if [ "$1" = "-y" ] || [ "$1" = "--yes" ]; then
    NON_INTERACTIVE=true
fi

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

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

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load configuration
CONFIG_FILE="$REPO_ROOT/boostrap/config.sh"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

AGE_KEY_FILE="${HOMELAB_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
SOPS_CONFIG="$REPO_ROOT/.sops.yaml"

echo ""
log_info "╔════════════════════════════════════════╗"
log_info "║     SOPS + age Setup Helper            ║"
log_info "╚════════════════════════════════════════╝"
echo ""

# Step 1: Check if tools are installed
log_info "Checking required tools..."
if ! command -v age-keygen &> /dev/null; then
    log_error "age is not installed. Run bootstrap.sh first."
fi

if ! command -v sops &> /dev/null; then
    log_error "sops is not installed. Run bootstrap.sh first."
fi

log_success "Required tools installed"
echo ""

# Step 2: Generate or check age key
log_info "Checking for age key..."
if [ -f "$AGE_KEY_FILE" ]; then
    log_success "Age key already exists at $AGE_KEY_FILE"
    
    # Extract public key
    PUBLIC_KEY=$(grep "public key:" "$AGE_KEY_FILE" | cut -d: -f2 | tr -d ' ')
    log_info "Current public key: $PUBLIC_KEY"
    
    if [ "$NON_INTERACTIVE" = false ]; then
        read -p "Generate a new key? [y/N]: " -n 1 -r
        echo
        GEN_NEW_KEY=$REPLY
    else
        GEN_NEW_KEY="n"
    fi
    
    if [[ ! $GEN_NEW_KEY =~ ^[Yy]$ ]]; then
        log_info "Using existing key"
    else
        log_warning "Backing up existing key..."
        cp "$AGE_KEY_FILE" "$AGE_KEY_FILE.backup.$(date +%s)"
        log_info "Generating new age key..."
        age-keygen -o "$AGE_KEY_FILE"
        PUBLIC_KEY=$(grep "public key:" "$AGE_KEY_FILE" | cut -d: -f2 | tr -d ' ')
        log_success "New key generated"
    fi
else
    log_info "Generating new age key..."
    mkdir -p "$(dirname "$AGE_KEY_FILE")"
    age-keygen -o "$AGE_KEY_FILE"
    PUBLIC_KEY=$(grep "public key:" "$AGE_KEY_FILE" | cut -d: -f2 | tr -d ' ')
    log_success "Age key generated at $AGE_KEY_FILE"
fi

echo ""
log_info "════════════════════════════════════════"
log_success "Your age public key:"
echo -e "${GREEN}$PUBLIC_KEY${NC}"
log_info "════════════════════════════════════════"
echo ""

# Step 3: Update .sops.yaml
log_info "Updating .sops.yaml with your public key..."
if [ ! -f "$SOPS_CONFIG" ]; then
    log_error ".sops.yaml not found at $SOPS_CONFIG"
fi

# Update all occurrences of age public keys in .sops.yaml
if grep -q "YOUR_AGE_PUBLIC_KEY_HERE" "$SOPS_CONFIG"; then
    log_info "Replacing placeholder keys..."
    sed -i.backup "s/YOUR_AGE_PUBLIC_KEY_HERE/$PUBLIC_KEY/g" "$SOPS_CONFIG"
    log_success "Updated .sops.yaml (backup created)"
elif grep -q "$PUBLIC_KEY" "$SOPS_CONFIG"; then
    log_success ".sops.yaml already has your public key"
else
    log_warning ".sops.yaml doesn't have placeholder or your key"
    log_info "You may need to manually update .sops.yaml"
fi

echo ""

# Step 4: Test SOPS
log_info "Testing SOPS encryption..."
TEST_FILE="/tmp/sops-test-$$.yaml"
cat > "$TEST_FILE" << 'EOF'
test:
  secret: this-is-a-test-secret
  password: test-password-123
EOF

log_info "Encrypting test file..."
if sops -e "$TEST_FILE" > "$TEST_FILE.enc"; then
    log_success "Encryption successful"
    
    log_info "Decrypting test file..."
    if sops -d "$TEST_FILE.enc" > /dev/null 2>&1; then
        log_success "Decryption successful"
        log_success "SOPS is working correctly!"
    else
        log_error "Decryption failed"
    fi
    
    rm -f "$TEST_FILE" "$TEST_FILE.enc"
else
    log_error "Encryption failed"
fi

echo ""

# Step 5: Create Terraform secrets if needed
TERRAFORM_SECRETS="$REPO_ROOT/k8s-infra/terraform/secrets.enc.yaml"
TERRAFORM_EXAMPLE="$REPO_ROOT/k8s-infra/terraform/secrets.enc.yaml.example"

if [ ! -f "$TERRAFORM_SECRETS" ]; then
    log_warning "Terraform secrets file not found"
    
    if [ -f "$TERRAFORM_EXAMPLE" ]; then
        if [ "$NON_INTERACTIVE" = false ]; then
            read -p "Create encrypted secrets file from example? [y/N]: " -n 1 -r
            echo
            CREATE_SECRETS=$REPLY
        else
            # In non-interactive mode, create from example but don't open editor
            CREATE_SECRETS="y"
        fi
        
        if [[ $CREATE_SECRETS =~ ^[Yy]$ ]]; then
            cp "$TERRAFORM_EXAMPLE" "$TERRAFORM_SECRETS"
            
            if [ "$NON_INTERACTIVE" = false ]; then
                log_info "Opening secrets file in SOPS editor..."
                log_info "Replace example values with your actual secrets"
                echo ""
                read -p "Press Enter to open SOPS editor..."
                sops "$TERRAFORM_SECRETS"
                log_success "Secrets file created and encrypted"
            else
                log_success "Secrets file created from example"
                log_warning "Remember to edit with: sops $TERRAFORM_SECRETS"
            fi
        fi
    fi
else
    log_success "Terraform secrets file already exists"
    
    if [ "$NON_INTERACTIVE" = false ]; then
        read -p "Edit secrets file? [y/N]: " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sops "$TERRAFORM_SECRETS"
        fi
    fi
fi

echo ""
log_success "╔════════════════════════════════════════╗"
log_success "║     SOPS Setup Complete! 🎉            ║"
log_success "╚════════════════════════════════════════╝"
echo ""

log_info "Next steps:"
echo "  1. Your age key is stored at: $AGE_KEY_FILE"
echo "  2. ⚠️  BACKUP THIS KEY SECURELY - You cannot decrypt without it!"
echo "  3. Your public key is in: $SOPS_CONFIG"
echo "  4. Create/edit secrets: sops $TERRAFORM_SECRETS"
echo ""

log_info "Usage examples:"
echo "  # Edit encrypted file"
echo "  sops $TERRAFORM_SECRETS"
echo ""
echo "  # Encrypt a new file"
echo "  sops -e myfile.yaml > myfile.enc.yaml"
echo ""
echo "  # Decrypt a file"
echo "  sops -d myfile.enc.yaml"
echo ""

log_warning "IMPORTANT: Backup your age key!"
echo "  cp $AGE_KEY_FILE ~/age-key-backup-$(date +%Y%m%d).txt"
echo ""
