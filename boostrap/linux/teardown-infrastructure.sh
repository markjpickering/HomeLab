#!/bin/bash
# HomeLab Infrastructure Teardown Script
# Reverses the effects of bootstrap-infrastructure.sh
#
# Usage:
#   teardown-infrastructure.sh [options]
#
# Options:
#   -a, --all                 Complete teardown (everything)
#   -k, --k8s-only            Destroy only Kubernetes infrastructure
#   -z, --ztnet-only          Remove only ztnet controller
#   -p, --proxmox-zt          Remove ZeroTier from Proxmox hosts only
#   -s, --site <site>         Teardown single site only (primary|secondary)
#   -d, --delete-data         Delete persistent data (volumes, databases, network ID)
#   -n, --dry-run             Dry run mode (show what would be done without executing)
#   -y, --yes                 Skip confirmation prompts
#   -h, --help                Show this help
#
# Default: Interactive mode (prompts for what to destroy)

set -e

# Parse arguments
TEARDOWN_MODE=""
SINGLE_SITE=""
SKIP_CONFIRMATION=false
DELETE_DATA=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -a|--all)
            TEARDOWN_MODE="all"
            shift
            ;;
        -k|--k8s-only)
            TEARDOWN_MODE="k8s"
            shift
            ;;
        -z|--ztnet-only)
            TEARDOWN_MODE="ztnet"
            shift
            ;;
        -p|--proxmox-zt)
            TEARDOWN_MODE="proxmox-zt"
            shift
            ;;
        -s|--site)
            SINGLE_SITE="$2"
            shift 2
            ;;
        -d|--delete-data)
            DELETE_DATA=true
            shift
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -y|--yes)
            SKIP_CONFIRMATION=true
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

ZTNET_DIR="$REPO_ROOT/boostrap/ztnet"
TERRAFORM_DIR="$REPO_ROOT/${HOMELAB_TF_DIR:-k8s-infra/terraform}"
NETWORK_ID_FILE="$REPO_ROOT/.zerotier-network-id"

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

log_dryrun() {
    echo -e "${YELLOW}[DRY RUN]${NC} $1"
}

run_command() {
    local description="$1"
    shift
    
    if [ "$DRY_RUN" = true ]; then
        log_dryrun "$description"
        log_dryrun "  Command: $*"
        return 0
    else
        "$@"
    fi
}

confirm() {
    if [ "$SKIP_CONFIRMATION" = true ]; then
        return 0
    fi
    
    local message="$1"
    local default="${2:-n}"
    
    if [ "$default" = "y" ]; then
        prompt="[Y/n]"
    else
        prompt="[y/N]"
    fi
    
    read -p "$message $prompt " response
    response=${response:-$default}
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

# Teardown functions
teardown_k8s() {
    log_info "Destroying Kubernetes infrastructure..."
    
    if [ ! -d "$TERRAFORM_DIR" ]; then
        log_warning "Terraform directory not found: $TERRAFORM_DIR"
        return
    fi
    
    cd "$TERRAFORM_DIR"
    
    if [ ! -f "terraform.tfstate" ]; then
        log_warning "No Terraform state found - nothing to destroy"
        return
    fi
    
    # Check if destroying single site
    if [ -n "$SINGLE_SITE" ]; then
        log_info "Destroying $SINGLE_SITE site only..."
        export TF_VAR_single_site="$SINGLE_SITE"
    fi
    
    if [ "$DRY_RUN" = true ]; then
        log_dryrun "Would destroy Terraform-managed infrastructure"
        run_command "Run terraform destroy" terraform destroy -auto-approve
        return
    fi
    
    if confirm "This will destroy all Terraform-managed infrastructure. Continue?" "n"; then
        terraform destroy -auto-approve
        log_success "Kubernetes infrastructure destroyed"
    else
        log_info "Skipping Kubernetes destruction"
    fi
}

teardown_proxmox_zerotier() {
    log_info "Removing ZeroTier from Proxmox hosts..."
    
    local network_id
    if [ -f "$NETWORK_ID_FILE" ]; then
        network_id=$(cat "$NETWORK_ID_FILE")
    else
        log_warning "Network ID file not found"
        network_id="${HOMELAB_ZEROTIER_NETWORK_ID:-}"
    fi
    
    if [ -z "$network_id" ]; then
        log_warning "Cannot determine ZeroTier network ID - skipping Proxmox cleanup"
        return
    fi
    
    local hosts=()
    
    if [ -z "$SINGLE_SITE" ] || [ "$SINGLE_SITE" = "primary" ]; then
        if [ -n "$HOMELAB_PROXMOX_PRIMARY_HOST" ]; then
            hosts+=("$HOMELAB_PROXMOX_PRIMARY_HOST")
        fi
    fi
    
    if [ -z "$SINGLE_SITE" ] || [ "$SINGLE_SITE" = "secondary" ]; then
        if [ -n "$HOMELAB_PROXMOX_SECONDARY_HOST" ]; then
            hosts+=("$HOMELAB_PROXMOX_SECONDARY_HOST")
        fi
    fi
    
    if [ ${#hosts[@]} -eq 0 ]; then
        log_warning "No Proxmox hosts configured - skipping"
        return
    fi
    
    for host in "${hosts[@]}"; do
        log_info "Removing ZeroTier from $host..."
        
        if [ "$DRY_RUN" = true ]; then
            log_dryrun "Would remove ZeroTier from $host"
            run_command "SSH to $host and leave network" ssh "$host" "zerotier-cli leave $network_id"
        else
            if ssh "$host" "zerotier-cli leave $network_id" 2>/dev/null; then
                log_success "ZeroTier removed from $host"
            else
                log_warning "Failed to remove ZeroTier from $host (may not be installed)"
            fi
        fi
    done
}

teardown_ztnet() {
    log_info "Stopping ztnet controller..."
    
    if [ ! -d "$ZTNET_DIR" ]; then
        log_warning "ztnet directory not found: $ZTNET_DIR"
        return
    fi
    
    cd "$ZTNET_DIR"
    
    if ! docker-compose ps 2>/dev/null | grep -q "Up"; then
        log_warning "ztnet controller not running"
        return
    fi
    
    if [ "$DRY_RUN" = true ]; then
        if [ "$DELETE_DATA" = true ]; then
            log_dryrun "Would destroy ztnet controller AND database"
            run_command "Stop and remove ztnet with volumes" docker-compose down -v
            if [ -f "$NETWORK_ID_FILE" ]; then
                log_dryrun "Would remove network ID file: $NETWORK_ID_FILE"
            fi
        else
            log_dryrun "Would stop ztnet controller (data preserved)"
            run_command "Stop ztnet controller" docker-compose down
            log_info "Volumes would be preserved: ztnet_postgres-data, ztnet_ztnet-data"
        fi
        return
    fi
    
    if [ "$DELETE_DATA" = true ]; then
        if confirm "This will destroy the ztnet controller AND database. Continue?" "n"; then
            docker-compose down -v
            log_success "ztnet controller and data removed"
            
            if [ -f "$NETWORK_ID_FILE" ]; then
                rm "$NETWORK_ID_FILE"
                log_success "Network ID file removed"
            fi
        else
            log_info "Skipping ztnet removal"
        fi
    else
        if confirm "This will stop the ztnet controller (data will be preserved). Continue?" "y"; then
            docker-compose down
            log_success "ztnet controller stopped (data preserved)"
            log_info "Volumes preserved: ztnet_postgres-data, ztnet_ztnet-data"
            log_info "To delete data later, run with -d/--delete-data flag"
        else
            log_info "Skipping ztnet removal"
        fi
    fi
}

teardown_all() {
    log_warning "=== COMPLETE TEARDOWN ==="
    log_warning "This will destroy:"
    log_warning "  - All Kubernetes infrastructure"
    log_warning "  - ZeroTier configuration on Proxmox hosts"
    log_warning "  - ztnet controller (stopped)"
    
    if [ "$DELETE_DATA" = true ]; then
        log_warning "  - ztnet database and volumes (--delete-data specified)"
        log_warning "  - Saved network ID"
    else
        log_info "Persistent data will be preserved (use -d to delete)"
    fi
    echo ""
    
    if ! confirm "Are you absolutely sure you want to proceed?" "n"; then
        log_info "Teardown cancelled"
        exit 0
    fi
    
    teardown_k8s
    teardown_proxmox_zerotier
    teardown_ztnet
    
    log_success "Complete teardown finished"
}

show_interactive_menu() {
    echo ""
    log_info "What do you want to tear down?"
    echo "  1) Complete teardown (everything)"
    echo "  2) Kubernetes infrastructure only"
    echo "  3) Proxmox ZeroTier configuration only"
    echo "  4) ztnet controller only"
    echo "  5) Cancel"
    read -p "Enter choice [1-5]: " choice
    
    case $choice in
        1)
            TEARDOWN_MODE="all"
            ;;
        2)
            TEARDOWN_MODE="k8s"
            ;;
        3)
            TEARDOWN_MODE="proxmox-zt"
            ;;
        4)
            TEARDOWN_MODE="ztnet"
            ;;
        5)
            log_info "Teardown cancelled"
            exit 0
            ;;
        *)
            log_error "Invalid choice"
            ;;
    esac
}

# Main execution
log_info "HomeLab Infrastructure Teardown"
log_info "================================"
echo ""

# Show dry-run banner if enabled
if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}╔════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║       DRY RUN MODE - NO CHANGES       ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════╝${NC}"
    echo ""
fi

# If no mode specified, show interactive menu
if [ -z "$TEARDOWN_MODE" ]; then
    show_interactive_menu
fi

# Execute teardown based on mode
case $TEARDOWN_MODE in
    all)
        teardown_all
        ;;
    k8s)
        teardown_k8s
        ;;
    proxmox-zt)
        teardown_proxmox_zerotier
        ;;
    ztnet)
        teardown_ztnet
        ;;
    *)
        log_error "Invalid teardown mode: $TEARDOWN_MODE"
        ;;
esac

echo ""
if [ "$DRY_RUN" = true ]; then
    log_info "Dry run complete! No changes were made."
    log_info "Run without -n/--dry-run to execute the teardown."
else
    log_info "Teardown complete!"
fi
log_info ""
log_info "What was preserved:"
log_info "  - Bootstrap host and tools"
log_info "  - Terraform state backups"
log_info "  - Configuration files (config.sh, .env)"
log_info "  - Source code repository"

if [ "$DELETE_DATA" != true ]; then
    log_info "  - ztnet volumes and database (use -d to delete)"
    log_info "  - Network ID file"
fi
