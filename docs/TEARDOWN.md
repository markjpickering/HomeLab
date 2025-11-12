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
bash teardown-infrastructure.sh --all
```
**Note**: By default, persistent data (volumes, databases) is preserved.

```bash
bash teardown-infrastructure.sh --all --delete-data --yes
```
**⚠️ WARNING**: This destroys all infrastructure AND data without prompting!

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
- ztnet controller (stopped)

Preserves by default:
- ztnet volumes and database
- Network ID file
- Terraform state backups

Add `-d/--delete-data` to also delete persistent data.

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

Stops ztnet controller (preserves database by default).

To also delete the database:
```bash
bash teardown-infrastructure.sh -z -d
```

### Single Site Teardown
```bash
# Destroy primary site only
bash teardown-infrastructure.sh -k -s primary

# Destroy secondary site only
bash teardown-infrastructure.sh -k -s secondary
```

### Dry Run (Preview Changes)
```bash
# See what would be destroyed without making changes
bash teardown-infrastructure.sh -a -n
# or
bash teardown-infrastructure.sh --all --dry-run
```

Shows execution plan without making any changes. Safe to run anytime.

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
  -z, --ztnet-only          Stop ztnet controller (preserves data by default)
  -p, --proxmox-zt          Remove ZeroTier from Proxmox hosts only
  -s, --site <site>         Teardown single site only (primary|secondary)
  -d, --delete-data         Delete persistent data (volumes, databases, network ID)
  -n, --dry-run             Show what would be done without executing
  -y, --yes                 Skip confirmation prompts
  -h, --help                Show help
```

## What Gets Destroyed vs. Preserved

### Destroyed by `-a/--all` (without `-d`):
- ✗ All Kubernetes VMs and containers
- ✗ ZeroTier configuration on Proxmox hosts
- ✗ ztnet controller (stopped)

### Preserved by default (without `-d`):
- ✓ ztnet volumes and database
- ✓ Saved ZeroTier network ID (`.zerotier-network-id`)
- ✓ Bootstrap host and installed tools
- ✓ Terraform state backups (`.tfstate.backup`)
- ✓ Configuration files (`config.sh`, `.env`)
- ✓ Source code repository
- ✓ Documentation

### Additionally destroyed with `-d/--delete-data`:
- ✗ ztnet database and volumes
- ✗ Saved ZeroTier network ID

## Common Workflows

### Preview Before Teardown
```bash
# Always preview first with dry-run
bash teardown-infrastructure.sh -a -n

# Review output, then execute if satisfied
bash teardown-infrastructure.sh -a
```

### Test and Rebuild
```bash
# Preview first
bash teardown-infrastructure.sh -a -n

# Destroy and test bootstrap again (preserves ztnet data)
bash teardown-infrastructure.sh -a -y
bash bootstrap-infrastructure.sh

# Complete clean rebuild (delete everything including data)
bash teardown-infrastructure.sh -a -d -y
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

# 3. Stop ztnet controller (preserves data)
cd ~/homelab/boostrap/ztnet
docker-compose down

# 3a. Or stop and delete data
docker-compose down -v
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
