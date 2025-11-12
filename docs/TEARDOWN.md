# Infrastructure Teardown Guide

This guide explains how to reverse the effects of the bootstrap script using the automated teardown script.

## Quick Start

### Interactive Mode (Recommended)
```bash
cd ~/homelab/boostrap/linux
bash teardown-infrastructure.sh
```
The script will prompt you for what to destroy.

### Complete Teardown (Everything)
```bash
bash teardown-infrastructure.sh --all --yes
```
**⚠️ WARNING**: This destroys all infrastructure without prompting!

## Usage Options

### Teardown Everything
```bash
bash teardown-infrastructure.sh -a
# or
bash teardown-infrastructure.sh --all
```

Destroys:
- All Kubernetes infrastructure (VMs)
- ZeroTier configuration on Proxmox hosts
- ztnet controller and database
- Saved network ID file

### Kubernetes Infrastructure Only
```bash
bash teardown-infrastructure.sh -k
# or
bash teardown-infrastructure.sh --k8s-only
```

Destroys only Terraform-managed VMs, keeps ztnet controller running.

### Proxmox ZeroTier Only
```bash
bash teardown-infrastructure.sh -p
# or
bash teardown-infrastructure.sh --proxmox-zt
```

Removes ZeroTier from Proxmox hosts (leaves the network).

### ztnet Controller Only
```bash
bash teardown-infrastructure.sh -z
# or
bash teardown-infrastructure.sh --ztnet-only
```

Stops and removes ztnet controller and database.

### Single Site Teardown
```bash
# Destroy primary site only
bash teardown-infrastructure.sh -k -s primary

# Destroy secondary site only
bash teardown-infrastructure.sh -k -s secondary
```

### Skip Confirmation Prompts
```bash
bash teardown-infrastructure.sh -a -y
# or
bash teardown-infrastructure.sh --all --yes
```

**⚠️ USE WITH CAUTION**: Destroys everything without asking for confirmation.

## Full Command Reference

```
Options:
  -a, --all                 Complete teardown (everything)
  -k, --k8s-only            Destroy only Kubernetes infrastructure
  -z, --ztnet-only          Remove only ztnet controller
  -p, --proxmox-zt          Remove ZeroTier from Proxmox hosts only
  -s, --site <site>         Teardown single site only (primary|secondary)
  -y, --yes                 Skip confirmation prompts
  -h, --help                Show help
```

## What Gets Destroyed vs. Preserved

### Destroyed by `-a/--all`:
- ✗ All Kubernetes VMs and containers
- ✗ ZeroTier configuration on Proxmox hosts
- ✗ ztnet controller and database
- ✗ Saved ZeroTier network ID (`.zerotier-network-id`)

### Always Preserved:
- ✓ Bootstrap host and installed tools
- ✓ Terraform state backups (`.tfstate.backup`)
- ✓ Configuration files (`config.sh`, `.env`)
- ✓ Source code repository
- ✓ Documentation

## Common Workflows

### Test and Rebuild
```bash
# Destroy and test bootstrap again
bash teardown-infrastructure.sh -a -y
bash bootstrap-infrastructure.sh

# Or just rebuild k8s cluster
bash teardown-infrastructure.sh -k -y
bash bootstrap-infrastructure.sh -p 5  # Phase 5: Provision infrastructure
```

### Move to Production
```bash
# Destroy dev environment
bash teardown-infrastructure.sh -a

# Update config.sh for production settings
vim ~/homelab/boostrap/config.sh

# Bootstrap production
bash bootstrap-infrastructure.sh
```

### Clean Up One Site
```bash
# Remove secondary site
bash teardown-infrastructure.sh -k -s secondary

# Later rebuild just secondary
bash bootstrap-infrastructure.sh -s secondary
```

## Safety Features

1. **Confirmation prompts**: By default, asks before destroying anything
2. **Single-site awareness**: Respects `-s/--site` flag
3. **Graceful degradation**: Continues if components already removed
4. **Clear warnings**: Shows what will be destroyed before proceeding

## Manual Teardown (Alternative)

If you prefer manual control or the script fails:

```bash
# 1. Destroy Kubernetes infrastructure
cd ~/homelab/k8s-infra/terraform
terraform destroy

# 2. Remove ZeroTier from Proxmox hosts
ssh root@<proxmox-ip>
zerotier-cli leave <network-id>

# 3. Stop and remove ztnet controller
cd ~/homelab/boostrap/ztnet
docker-compose down -v

# 4. Remove saved network ID
rm ~/homelab/.zerotier-network-id
```

See [OPERATIONS-GUIDE.md](OPERATIONS-GUIDE.md) for more details.

## Backup Before Teardown

Always backup critical data before destroying infrastructure:

```bash
# Quick backup
BACKUP_DIR="$HOME/homelab-backups/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

cp ~/homelab/boostrap/ztnet/.env "$BACKUP_DIR/"
cp ~/homelab/.zerotier-network-id "$BACKUP_DIR/"
cp ~/homelab/k8s-infra/terraform/terraform.tfstate "$BACKUP_DIR/"

# Backup ztnet database
cd ~/homelab/boostrap/ztnet
docker-compose exec -T postgres pg_dump -U postgres ztnet > "$BACKUP_DIR/ztnet-db.sql"
```

## Troubleshooting

### Script Can't Find Terraform
```bash
# Manually specify Terraform directory
export HOMELAB_TF_DIR="k8s-infra/terraform"
bash teardown-infrastructure.sh
```

### Proxmox Hosts Not Responding
```bash
# Skip Proxmox teardown, just destroy k8s and ztnet
bash teardown-infrastructure.sh -k -y
bash teardown-infrastructure.sh -z -y
```

### State Out of Sync
```bash
# Refresh Terraform state first
cd ~/homelab/k8s-infra/terraform
terraform refresh

# Then run teardown
bash teardown-infrastructure.sh -k
```

### Force Remove Everything
```bash
# Nuclear option - destroys without checking state
cd ~/homelab/k8s-infra/terraform
rm -rf .terraform terraform.tfstate*

cd ~/homelab/boostrap/ztnet
docker-compose down -v

rm ~/homelab/.zerotier-network-id
```

## See Also

- [BOOTSTRAP-USAGE.md](BOOTSTRAP-USAGE.md) - How to bootstrap infrastructure
- [OPERATIONS-GUIDE.md](OPERATIONS-GUIDE.md) - Day-to-day operations
- [ARCHITECTURE.md](ARCHITECTURE.md) - Overall system architecture
