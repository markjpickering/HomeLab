# Bootstrap Script Usage Guide

## Overview

The `bootstrap-infrastructure.sh` script automates the deployment of your HomeLab infrastructure across one or both sites. **By default, the script runs in non-interactive mode** with comprehensive pre-flight validation.

## Quick Start

```bash
# Validate configuration first (recommended)
./boostrap/linux/bootstrap-infrastructure.sh --validate-only

# Preview what would be done (dry-run)
./boostrap/linux/bootstrap-infrastructure.sh --dry-run

# Bootstrap both sites (non-interactive)
./boostrap/linux/bootstrap-infrastructure.sh

# Bootstrap only primary site
./boostrap/linux/bootstrap-infrastructure.sh --site primary

# Bootstrap only secondary site  
./boostrap/linux/bootstrap-infrastructure.sh --site secondary

# Interactive mode (prompts for confirmations)
./boostrap/linux/bootstrap-infrastructure.sh --interactive
```

## Command-Line Options

### Non-Interactive Mode (Default)

```bash
./boostrap/linux/bootstrap-infrastructure.sh [options]
```

**Options:**

- `-i, --interactive` - Enable interactive mode (prompts for confirmations)
- `-s, --site <site>` - Bootstrap single site only (`primary` or `secondary`)
- `-p, --phase <1-6>` - Run specific phase (see Phases section)
- `-v, --validate-only` - Validate configuration and exit without running bootstrap
- `-n, --dry-run` - Show what would be done without executing (preview mode)
- `-h, --help` - Show help message

### Examples

```bash
# Validate configuration before running
./boostrap/linux/bootstrap-infrastructure.sh -v

# Preview what would be done (dry-run)
./boostrap/linux/bootstrap-infrastructure.sh -n

# Preview single site bootstrap
./boostrap/linux/bootstrap-infrastructure.sh -n --site primary

# Bootstrap primary site only
./boostrap/linux/bootstrap-infrastructure.sh --site primary

# Run only phase 3 (Terraform provisioning) interactively
./boostrap/linux/bootstrap-infrastructure.sh -i -p 4

# Bootstrap both sites with interactive confirmations
./boostrap/linux/bootstrap-infrastructure.sh -i
```

## Pre-Flight Validation

The script automatically performs comprehensive pre-flight validation checks before running any bootstrap operations:

### Validation Checks (8 stages):

1. **Configuration Variables** - Validates required environment variables (HOMELAB_REPO_URL, DNS_DOMAIN, site IDs, etc.)
2. **Required Tools** - Checks for docker, docker-compose, terraform, ansible, jq, sops, age, curl, ssh
3. **Site Configuration** - Validates single-site parameter if specified
4. **Directory Structure** - Verifies existence of ztnet, terraform, and ansible directories
5. **Docker Service** - Ensures Docker daemon is running and accessible
6. **IP Address Configuration** - Checks for duplicate IPs and validates subnet membership
7. **SOPS/Age Setup** - Validates age key and .sops.yaml configuration
8. **Terraform Secrets** - Verifies encrypted secrets file exists and is properly encrypted

### Validation Output

The script will display:
- ⚠️ **Warnings** - Non-critical issues that may cause problems
- ❌ **Errors** - Critical issues that must be fixed before proceeding

If any errors are found, the script will exit with an error message. Fix the issues and run again.

### Validate-Only Mode

```bash
./boostrap/linux/bootstrap-infrastructure.sh --validate-only
```

This runs all validation checks and displays the results without executing any bootstrap operations. Useful for:
- Initial setup verification
- Pre-deployment checks
- CI/CD pipeline validation

## Bootstrap Phases

The bootstrap process consists of 4 phases:

### Phase 1: Deploy ztnet Controller
- Deploys ZeroTier network controller using Docker Compose
- Generates secrets for ztnet
- Starts controller service
- Waits for controller to become ready

**In non-interactive mode:**
- Automatically generates secrets
- Waits 10 seconds for initial setup
- Displays URL for manual admin account creation

### Phase 2: Create ZeroTier Network
- Creates ZeroTier overlay network via controller API
- Configures IP pool and routing
- Optionally joins bootstrap host to network
- Saves network ID for later use

**In non-interactive mode:**
- Automatically creates network
- Uses `HOMELAB_JOIN_BOOTSTRAP_HOST` config value (default: `n`)
- Auto-authorizes members if `HOMELAB_ZT_AUTO_AUTHORIZE=y`

### Phase 3: Provision Infrastructure (Terraform)
- Validates SOPS and age configuration
- Checks for encrypted secrets file
- Initializes Terraform
- Plans infrastructure changes
- Applies Terraform configuration

**In non-interactive mode:**
- Automatically applies terraform plan with `-auto-approve`
- Creates secrets file from example if missing

**Single-site mode:**
- Exports `TF_VAR_single_site=primary` or `TF_VAR_single_site=secondary`
- Your Terraform configuration must support this variable

### Phase 4: Configure Kubernetes (Ansible)
- Generates Ansible inventory from ZeroTier network
- Runs Ansible playbook to configure k3s
- Installs and configures k3s on all nodes

**Single-site mode:**
- Ansible inventory should filter nodes based on site labels

## Single-Site Mode

Bootstrap only one site instead of both. Useful for:
- Initial testing with one site
- Phased rollout (primary first, then secondary)
- Site-specific maintenance or rebuilds

### Configuration

**Via command-line:**
```bash
./boostrap/linux/bootstrap-infrastructure.sh --site primary
```

**Via environment variable:**
```bash
export HOMELAB_BOOTSTRAP_SITE="primary"
./boostrap/linux/bootstrap-infrastructure.sh
```

**Via config.sh:**
```bash
# In boostrap/config.sh
export HOMELAB_BOOTSTRAP_SITE="primary"
```

### Single-Site Behavior

When single-site mode is enabled:
1. Validation confirms site parameter is valid (`primary` or `secondary`)
2. Terraform receives `TF_VAR_single_site` environment variable
3. Only nodes for the specified site are provisioned
4. Ansible configures only the specified site's nodes

**Note:** Your Terraform configuration must support the `single_site` variable to filter resources appropriately.

## Interactive vs Non-Interactive Mode

### Non-Interactive Mode (Default)

**Behavior:**
- No prompts for user input
- Automatically proceeds with default/configured values
- Creates secrets from examples if missing
- Auto-approves Terraform plans
- Suitable for automation, CI/CD, and scripted deployments

**Configuration:**
Uses values from:
- `boostrap/config.sh`
- Environment variables
- User config file (`~/.homelab.conf` if exists)

### Interactive Mode

**Behavior:**
- Prompts for confirmations before critical operations
- Asks to review Terraform plans before applying
- Prompts for secrets file creation
- Asks before joining bootstrap host to ZeroTier network
- Asks before transferring controller to remote host

**Enable with:**
```bash
./boostrap/linux/bootstrap-infrastructure.sh --interactive
```

## Configuration Files

### Primary Configuration

**File:** `boostrap/config.sh`

Contains all configurable parameters:
- Site definitions (names, IDs, locations)
- Network configuration (ZeroTier, DNS)
- IP address assignments
- k3s settings
- Tool paths

### User Overrides

**File:** `~/.homelab.conf` (optional)

Create this file to override default config.sh values:

```bash
# ~/.homelab.conf
export HOMELAB_PRIMARY_SITE_NAME="My Primary Lab"
export HOMELAB_K3S_VERSION="v1.29.0+k3s1"
export HOMELAB_ZT_AUTO_AUTHORIZE="n"
```

### Terraform Secrets

**File:** `k8s-infra/terraform/secrets.enc.yaml`

Encrypted with SOPS/age. Contains sensitive values like:
- Proxmox API credentials
- SSH keys
- Service passwords

**Create from example:**
```bash
cp k8s-infra/terraform/secrets.enc.yaml.example k8s-infra/terraform/secrets.enc.yaml
sops k8s-infra/terraform/secrets.enc.yaml
```

## Phase Selection

Run specific phases using the `-p` or `--phase` option:

```bash
# Phase options:
# 1 = Complete bootstrap (all phases)
# 2 = Phase 1 only (Deploy ztnet)
# 3 = Phase 2 only (Create ZeroTier network)
# 4 = Phase 3 only (Provision infrastructure with Terraform)
# 5 = Phase 4 only (Configure Kubernetes with Ansible)
# 6 = Phases 3+4 (Provision & Configure)

# Example: Run only Terraform provisioning
./boostrap/linux/bootstrap-infrastructure.sh -p 4

# Example: Run only Ansible configuration
./boostrap/linux/bootstrap-infrastructure.sh -p 5

# Example: Re-run provisioning and configuration
./boostrap/linux/bootstrap-infrastructure.sh -p 6
```

**Use cases:**
- **Phase 2-3 only:** Already have ztnet running, need to create network and provision nodes
- **Phase 4 only:** Nodes are provisioned, need to configure k3s
- **Phase 6:** Infrastructure exists, need to re-provision and reconfigure

## Troubleshooting

### Validation Errors

**Error: "HOMELAB_REPO_URL not configured"**
```bash
# Edit boostrap/config.sh
export HOMELAB_REPO_URL="https://github.com/YOUR_USERNAME/HomeLab.git"
```

**Error: "Missing required tools: terraform"**
```bash
# Install missing tools (Ubuntu/Debian)
sudo apt-get install terraform

# Or use asdf/tfenv for version management
```

**Error: "Docker daemon not running"**
```bash
sudo systemctl start docker
sudo usermod -aG docker $USER
# Log out and back in
```

**Error: "Duplicate IP addresses detected"**
```bash
# Check config.sh for duplicate IPs in these variables:
# HOMELAB_PRIMARY_SERVER_IP, HOMELAB_AGENT*_IP, etc.
```

**Error: "Terraform secrets file not encrypted"**
```bash
# Re-encrypt the secrets file
sops -e k8s-infra/terraform/secrets.enc.yaml > temp.yaml
mv temp.yaml k8s-infra/terraform/secrets.enc.yaml
```

### Runtime Issues

**ztnet controller not accessible**
```bash
# Check Docker containers
docker ps | grep ztnet

# View logs
cd boostrap/ztnet
docker-compose logs -f
```

**Terraform apply fails**
```bash
# Check terraform logs
cd k8s-infra/terraform
terraform plan  # Review for errors

# Validate secrets can be decrypted
sops -d secrets.enc.yaml
```

**Ansible playbook fails**
```bash
# Check inventory was generated
cat k8s-infra/ansible/inventory/hosts.ini

# Test connectivity
ansible -i k8s-infra/ansible/inventory/hosts.ini all -m ping

# Run with verbose output
cd k8s-infra/ansible
ansible-playbook -i inventory/hosts.ini site.yml -vvv
```

## Best Practices

### Initial Setup

1. **Validate first:**
   ```bash
   ./boostrap/linux/bootstrap-infrastructure.sh --validate-only
   ```

2. **Test with single site:**
   ```bash
   ./boostrap/linux/bootstrap-infrastructure.sh --site primary -i
   ```

3. **Review Terraform plan in interactive mode before committing to full deployment**

4. **Once confident, run full deployment:**
   ```bash
   ./boostrap/linux/bootstrap-infrastructure.sh
   ```

### CI/CD Integration

```yaml
# GitHub Actions example
- name: Validate HomeLab Configuration
  run: |
    ./boostrap/linux/bootstrap-infrastructure.sh --validate-only

- name: Bootstrap Primary Site
  run: |
    ./boostrap/linux/bootstrap-infrastructure.sh --site primary
  env:
    HOMELAB_ZT_AUTO_AUTHORIZE: "y"
```

### Re-running Bootstrap

**Idempotency:**
- Phases are mostly idempotent
- Re-running won't break existing infrastructure
- Terraform will show no changes if infrastructure matches desired state

**Selective re-runs:**
```bash
# Re-provision nodes only
./boostrap/linux/bootstrap-infrastructure.sh -p 4

# Re-configure k3s only
./boostrap/linux/bootstrap-infrastructure.sh -p 5
```

## Environment Variables Reference

Key environment variables that affect bootstrap behavior:

```bash
# Site selection
HOMELAB_BOOTSTRAP_SITE="primary"  # or "secondary" or "" for both

# ZeroTier behavior
HOMELAB_JOIN_BOOTSTRAP_HOST="n"  # Join bootstrap host to network?
HOMELAB_ZT_AUTO_AUTHORIZE="y"    # Auto-authorize members?

# Directory locations
HOMELAB_TF_DIR="k8s-infra/terraform"
HOMELAB_ANSIBLE_DIR="k8s-infra/ansible"

# Secrets
HOMELAB_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
HOMELAB_TF_SECRETS_FILE="secrets.enc.yaml"
```

See `boostrap/config.sh` for complete list.

## Next Steps After Bootstrap

1. **Verify ztnet controller:**
   ```bash
   open http://localhost:3000
   # Create admin account if not done
   ```

2. **Check k3s nodes:**
   ```bash
   export KUBECONFIG=~/.kube/config
   kubectl get nodes
   ```

3. **Deploy core services:**
   ```bash
   kubectl apply -f k8s-apps/dns/
   kubectl apply -f k8s-apps/auth/
   ```

4. **Configure DNS:**
   ```bash
   ./boostrap/linux/bootstrap-dns.sh
   ```

See main documentation for complete post-bootstrap setup.
