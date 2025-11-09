# Non-Interactive Bootstrap Guide

Guide for running HomeLab bootstrap in automated/non-interactive mode (CI/CD, scripts, etc.).

## Overview

All bootstrap scripts support non-interactive mode, allowing for:
- Automated deployments
- CI/CD pipelines
- Scripted provisioning
- Headless server setups

## Bootstrap Scripts

### `bootstrap-infrastructure.sh`

Complete infrastructure bootstrap with no user prompts.

**Usage:**
```bash
bash bootstrap-infrastructure.sh --yes [--phase <1-6>]
```

**Options:**
- `-y, --yes` - Non-interactive mode
- `-p, --phase <1-6>` - Run specific phase
- `-h, --help` - Show help

**Example - Complete Bootstrap:**
```bash
# Set required environment variables
export HOMELAB_ZEROTIER_NETWORK_ID="a1b2c3d4e5f6g7h8"

# Run all phases non-interactively
bash bootstrap-infrastructure.sh --yes
```

**Example - Specific Phase:**
```bash
# Run only Phase 3 (provision infrastructure)
bash bootstrap-infrastructure.sh --yes --phase 4
```

### `setup-sops.sh`

SOPS setup without prompts.

**Usage:**
```bash
bash setup-sops.sh --yes
```

**What it does:**
- Generates age key if missing
- Uses existing key if present
- Creates secrets file from example
- Does NOT open editor (manual edit required later)

**Example:**
```bash
bash boostrap/linux/setup-sops.sh --yes

# Edit secrets later
sops k8s-infra/terraform/secrets.enc.yaml
```

## Required Environment Variables

### Phase 2 - Create ZeroTier Network

**Required:**
```bash
export HOMELAB_ZEROTIER_NETWORK_ID="a1b2c3d4e5f6g7h8"
```

If not set, Phase 2 will fail in non-interactive mode.

**Optional:**
```bash
export HOMELAB_JOIN_BOOTSTRAP_HOST="true"  # Join bootstrap host to network
export HOMELAB_ZEROTIER_NETWORK_NAME="HomeLabK8s"
export HOMELAB_ZEROTIER_SUBNET="10.147.17.0/24"
```

## Complete Non-Interactive Example

### Prerequisites
1. Bootstrap host is already set up (Terraform, Ansible, Docker installed)
2. You have a ZeroTier network ID
3. SOPS secrets file is configured

### Script
```bash
#!/bin/bash
set -e

# Configuration
export HOMELAB_REPO_URL="https://github.com/myuser/HomeLab.git"
export HOMELAB_ZEROTIER_NETWORK_ID="a1b2c3d4e5f6g7h8"  # Get from ztnet
export HOMELAB_JOIN_BOOTSTRAP_HOST="false"  # Don't join bootstrap host

# Navigate to repository
cd ~/homelab

# Run complete bootstrap
bash boostrap/linux/bootstrap-infrastructure.sh --yes

echo "✅ Bootstrap complete!"
```

## Behavior in Non-Interactive Mode

### Phase 1 - Deploy ztnet Controller
- Starts containers
- Waits 10 seconds for initialization
- **Manual step required:** Create admin account at http://localhost:3000

### Phase 2 - Create ZeroTier Network
- Uses `HOMELAB_ZEROTIER_NETWORK_ID` environment variable
- **Fails if not set**
- Skips bootstrap host join unless `HOMELAB_JOIN_BOOTSTRAP_HOST=true`

### Phase 3 - Provision Infrastructure
- Auto-creates secrets file from example if missing
- **Does not open SOPS editor** (you must edit manually later)
- Runs `terraform apply -auto-approve`
- Waits 30 seconds for nodes to join ZeroTier
- **Manual step required:** Authorize nodes in ztnet web UI

### Phase 4 - Configure Kubernetes
- Assumes inventory is already populated
- Runs Ansible playbook without prompts

## Pre-Configuration for Full Automation

To run completely hands-off, pre-configure these:

### 1. ztnet Already Running
```bash
# Start ztnet beforehand
cd boostrap/ztnet
docker-compose up -d

# Create admin account via web UI
# Create network and note ID
```

### 2. SOPS Secrets Pre-Configured
```bash
# Set up SOPS
bash boostrap/linux/setup-sops.sh --yes

# Edit secrets with real values
sops k8s-infra/terraform/secrets.enc.yaml
```

### 3. Configuration File
Create `~/.homelab.conf`:
```bash
export HOMELAB_REPO_URL="https://github.com/myuser/HomeLab.git"
export HOMELAB_ZEROTIER_NETWORK_ID="a1b2c3d4e5f6g7h8"
export HOMELAB_K8S_WORKER_COUNT="5"
export HOMELAB_JOIN_BOOTSTRAP_HOST="false"
```

### 4. Then Run
```bash
# Phase 1 (if ztnet not running)
bash bootstrap-infrastructure.sh -y -p 2

# Phases 3+4 (provision and configure)
bash bootstrap-infrastructure.sh -y -p 6
```

## CI/CD Pipeline Example

### GitHub Actions
```yaml
name: Deploy HomeLab

on:
  workflow_dispatch:
    inputs:
      zerotier_network_id:
        description: 'ZeroTier Network ID'
        required: true

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Set up environment
        run: |
          # Install prerequisites
          bash boostrap/linux/bootstrap.sh
          
          # Configure SOPS
          echo "${{ secrets.AGE_PRIVATE_KEY }}" > ~/.config/sops/age/keys.txt
          
      - name: Run bootstrap
        env:
          HOMELAB_ZEROTIER_NETWORK_ID: ${{ github.event.inputs.zerotier_network_id }}
        run: |
          bash boostrap/linux/bootstrap-infrastructure.sh --yes --phase 4
```

### GitLab CI
```yaml
deploy:
  stage: deploy
  script:
    - export HOMELAB_ZEROTIER_NETWORK_ID="$ZEROTIER_NETWORK_ID"
    - bash boostrap/linux/bootstrap.sh
    - bash boostrap/linux/bootstrap-infrastructure.sh --yes --phase 6
  only:
    - main
```

## Handling Manual Steps Programmatically

### ztnet Network Creation (via API)

If ztnet exposes an API, you can create networks programmatically:

```bash
# Example (adjust based on ztnet API)
NETWORK_ID=$(curl -X POST http://localhost:3000/api/networks \
  -H "Authorization: Bearer $ZTNET_API_TOKEN" \
  -d '{"name": "HomeLabK8s"}' | jq -r '.id')

export HOMELAB_ZEROTIER_NETWORK_ID="$NETWORK_ID"
```

### Node Authorization (via API)

```bash
# List unauthorized nodes
curl http://localhost:3000/api/networks/$NETWORK_ID/members \
  -H "Authorization: Bearer $ZTNET_API_TOKEN" \
  | jq -r '.[] | select(.authorized == false) | .id'

# Authorize all nodes
for node_id in $(curl ...); do
  curl -X POST http://localhost:3000/api/networks/$NETWORK_ID/members/$node_id \
    -H "Authorization: Bearer $ZTNET_API_TOKEN" \
    -d '{"authorized": true}'
done
```

## Wait Times

Non-interactive mode uses these wait times:

| Phase | Wait Time | Purpose |
|-------|-----------|---------|
| Phase 1 | 10 seconds | ztnet initialization |
| Phase 3 | 30 seconds | Nodes to join ZeroTier |

**Adjust if needed:**
```bash
# In bootstrap-infrastructure.sh
# Change: sleep 10
# To: sleep 30
```

## Validation

### Before Running
```bash
# Check configuration
source boostrap/config.sh
show_config

# Verify network ID is set
echo $HOMELAB_ZEROTIER_NETWORK_ID

# Test SOPS
sops -d k8s-infra/terraform/secrets.enc.yaml | head -n 5
```

### After Running
```bash
# Check ztnet
docker-compose -f boostrap/ztnet/docker-compose.yml ps

# Check Terraform
cd k8s-infra/terraform && terraform show

# Check nodes
cd k8s-infra/ansible && ansible -i inventory/hosts.ini all -m ping
```

## Troubleshooting

### "Network ID cannot be empty"

**Solution:** Set environment variable:
```bash
export HOMELAB_ZEROTIER_NETWORK_ID="your-network-id"
```

### "Terraform requires secrets.enc.yaml"

**Solution:** Secrets file was created from example but not edited:
```bash
sops k8s-infra/terraform/secrets.enc.yaml
# Replace example values with real credentials
```

### "Terraform apply cancelled"

Non-interactive mode uses `terraform apply -auto-approve`. If this fails, check:
```bash
cd k8s-infra/terraform
terraform plan  # Check for errors
```

### Nodes Don't Appear in ztnet

30-second wait may not be enough. Manually:
```bash
# SSH to node
ssh root@<node-local-ip>

# Check ZeroTier
zerotier-cli status
zerotier-cli listnetworks
```

## Best Practices

1. **Test interactively first** - Run manually to understand the flow
2. **Pre-configure secrets** - Edit SOPS files before automation
3. **Use configuration file** - Set `~/.homelab.conf` for consistent settings
4. **Add extra wait times** - If automation is flaky, increase sleep durations
5. **Log everything** - Redirect output: `bash bootstrap.sh --yes 2>&1 | tee bootstrap.log`
6. **Idempotent** - Scripts can be re-run safely

## Example: Fully Automated Setup

```bash
#!/bin/bash
# fully-automated-bootstrap.sh
set -e

echo "🚀 Fully Automated HomeLab Bootstrap"

# 1. Prerequisites check
command -v docker || { echo "Docker required"; exit 1; }
command -v terraform || { echo "Terraform required"; exit 1; }
command -v ansible || { echo "Ansible required"; exit 1; }

# 2. Configuration
export HOMELAB_REPO_URL="https://github.com/myuser/HomeLab.git"
export HOMELAB_K8S_WORKER_COUNT="3"

# 3. Deploy ztnet (if not running)
if ! docker ps | grep -q ztnet; then
    cd boostrap/ztnet
    docker-compose up -d
    sleep 15
    echo "⚠️  Create admin account at http://localhost:3000"
    echo "⚠️  Then create a network and set HOMELAB_ZEROTIER_NETWORK_ID"
    exit 0
fi

# 4. Get network ID (from environment or file)
if [ -z "$HOMELAB_ZEROTIER_NETWORK_ID" ]; then
    if [ -f .zerotier-network-id ]; then
        export HOMELAB_ZEROTIER_NETWORK_ID=$(cat .zerotier-network-id)
    else
        echo "❌ HOMELAB_ZEROTIER_NETWORK_ID required"
        exit 1
    fi
fi

# 5. Set up SOPS (if not done)
if [ ! -f ~/.config/sops/age/keys.txt ]; then
    bash boostrap/linux/setup-sops.sh --yes
    echo "⚠️  Edit secrets: sops k8s-infra/terraform/secrets.enc.yaml"
    exit 0
fi

# 6. Run infrastructure bootstrap
echo "📦 Provisioning infrastructure..."
bash boostrap/linux/bootstrap-infrastructure.sh --yes --phase 6

echo "✅ Bootstrap complete!"
echo ""
echo "Next steps:"
echo "  1. Authorize nodes at http://localhost:3000"
echo "  2. Update ansible inventory with ZeroTier IPs"
echo "  3. Run: bash bootstrap-infrastructure.sh --yes --phase 5"
```

---

**Non-interactive mode is now fully supported across all bootstrap scripts!**
