# GitHub Actions Setup Guide

Complete guide to enable GitHub Actions for automated HomeLab deployment.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Step 1: Configure Secrets](#step-1-configure-secrets)
- [Step 2: Update Configuration](#step-2-update-configuration)
- [Step 3: Set Up Self-Hosted Runners (Optional)](#step-3-set-up-self-hosted-runners-optional)
- [Step 4: Enable Workflows](#step-4-enable-workflows)
- [Step 5: Test Workflows](#step-5-test-workflows)
- [Troubleshooting](#troubleshooting)

---

## Overview

Your HomeLab has two GitHub Actions workflows:

1. **`bootstrap.yml`** - Automated infrastructure bootstrap
2. **`deploy.yml`** - Automated k8s application deployment

### Workflow Capabilities

**Bootstrap Workflow:**
- Runs on-demand via workflow_dispatch
- Deploys infrastructure to bootstrap host
- Supports phase selection (ztnet, network, terraform, k8s)
- Supports site selection (primary, secondary, or both)

**Deploy Workflow:**
- Runs on push to master (k8s-apps/** changes)
- Deploys to self-hosted runners on k8s nodes
- Supports manual target selection

---

## Prerequisites

Before enabling GitHub Actions, ensure you have:

- [ ] GitHub repository with workflows (already present)
- [ ] Bootstrap host accessible via SSH
- [ ] SSH key pair for authentication
- [ ] ZeroTier network ID
- [ ] Proxmox credentials (if using Proxmox)
- [ ] Age encryption key for SOPS
- [ ] All values from `boostrap/config.sh` finalized

---

## Step 1: Configure Secrets

GitHub Actions requires secrets for authentication and configuration. Add these in your repository.

### Navigate to Secrets

1. Go to your GitHub repository
2. Click **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**

### Required Secrets for Bootstrap Workflow

| Secret Name | Description | Example Value | Where to Find |
|-------------|-------------|---------------|---------------|
| `BOOTSTRAP_HOST` | IP/hostname of bootstrap host | `10.0.1.5` or `bootstrap.homelab.local` | Your bootstrap host IP |
| `BOOTSTRAP_USER` | SSH user for bootstrap host | `root` | User on bootstrap host |
| `BOOTSTRAP_SSH_KEY` | Private SSH key for authentication | `-----BEGIN OPENSSH PRIVATE KEY-----\n...` | Generate with `ssh-keygen` |
| `ZEROTIER_NETWORK_ID` | ZeroTier network ID | `a1b2c3d4e5f6g7h8` | Created during Phase 2 or from ztnet UI |

### Required Secrets for Deploy Workflow

Only needed if using self-hosted runners:

| Secret Name | Description | Example Value |
|-------------|-------------|---------------|
| `KUBECONFIG_PRIMARY` | kubeconfig for primary site | `apiVersion: v1\nkind: Config\n...` |
| `KUBECONFIG_SECONDARY` | kubeconfig for secondary site | `apiVersion: v1\nkind: Config\n...` |

### Optional Secrets (Recommended)

| Secret Name | Description | Example Value | Where to Find |
|-------------|-------------|---------------|---------------|
| `PROXMOX_PRIMARY_HOST` | Primary Proxmox host | `root@10.147.17.2` | From config.sh `HOMELAB_PROXMOX_PRIMARY_HOST` |
| `PROXMOX_SECONDARY_HOST` | Secondary Proxmox host | `root@10.147.17.3` | From config.sh `HOMELAB_PROXMOX_SECONDARY_HOST` |
| `PROXMOX_API_TOKEN` | Proxmox API token | `PVEAPIToken=user@pam!tokenid=xxx` | Proxmox web UI → API Tokens |
| `AGE_SECRET_KEY` | Age encryption key for SOPS | `AGE-SECRET-KEY-1...` | From `~/.age/key.txt` |
| `SLACK_WEBHOOK_URL` | Slack notifications (optional) | `https://hooks.slack.com/...` | Slack workspace settings |

### How to Generate SSH Key

```bash
# Generate SSH key pair
ssh-keygen -t ed25519 -C "github-actions" -f ~/.ssh/github_actions

# Copy public key to bootstrap host
ssh-copy-id -i ~/.ssh/github_actions.pub root@<bootstrap-host>

# Copy private key content for GitHub secret
cat ~/.ssh/github_actions
```

Copy the **entire private key output** (including `-----BEGIN` and `-----END` lines) as the `BOOTSTRAP_SSH_KEY` secret.

### How to Get ZeroTier Network ID

If you've already bootstrapped:
```bash
cat ~/homelab/.zerotier-network-id
```

Or from ztnet UI:
1. Access ztnet: http://localhost:3000
2. Go to Networks
3. Copy the 16-character network ID

### How to Get kubeconfig

```bash
# Primary site
ssh root@<primary-control-plane>
cat /etc/rancher/k3s/k3s.yaml
# Copy output

# Secondary site
ssh root@<secondary-control-plane>
cat /etc/rancher/k3s/k3s.yaml
# Copy output
```

**Important**: Update the `server:` field in kubeconfig to use ZeroTier IPs instead of localhost.

---

## Step 2: Update Configuration

### Update config.sh with Production Values

Edit `boostrap/config.sh` and ensure all values are set:

```bash
# Proxmox Configuration (from your infrastructure)
export HOMELAB_PROXMOX_PRIMARY_HOST="root@10.147.17.2"
export HOMELAB_PROXMOX_SECONDARY_HOST="root@10.147.17.3"
export HOMELAB_PROXMOX_PRIMARY_NODE="pve-primary"
export HOMELAB_PROXMOX_SECONDARY_NODE="pve-secondary"

# Site Configuration
export HOMELAB_PRIMARY_SITE_ID="pickers"
export HOMELAB_SECONDARY_SITE_ID="sheila"

# DNS Configuration
export HOMELAB_DNS_DOMAIN="hl"
export HOMELAB_PRIMARY_DNS_DOMAIN="pickers.hl"
export HOMELAB_SECONDARY_DNS_DOMAIN="sheila.hl"
export HOMELAB_SHARED_DNS_DOMAIN="services.hl"

# ZeroTier Configuration
export HOMELAB_ZEROTIER_NETWORK_NAME="HomeLabK8s"
export HOMELAB_ZEROTIER_SUBNET="10.147.17.0/24"

# Repository
export HOMELAB_REPO_URL="https://github.com/markjpickering/HomeLab"
```

### Update Terraform Secrets

Ensure `k8s-infra/terraform/secrets.enc.yaml` contains:

```yaml
proxmox_primary:
  endpoint: "https://proxmox-primary.your-domain:8006/api2/json"
  username: "root@pam"
  password: "your-password"
  
proxmox_secondary:
  endpoint: "https://proxmox-secondary.your-domain:8006/api2/json"
  username: "root@pam"
  password: "your-password"
```

Encrypt with SOPS:
```bash
cd k8s-infra/terraform
sops -e secrets.enc.yaml > secrets.enc.yaml.tmp && mv secrets.enc.yaml.tmp secrets.enc.yaml
```

### Commit Configuration Changes

```bash
git add boostrap/config.sh
git add k8s-infra/terraform/secrets.enc.yaml
git commit -m "Update configuration with production values"
git push origin master
```

---

## Step 3: Set Up Self-Hosted Runners (Optional)

Self-hosted runners allow deployment directly to your k8s clusters. This is optional for the deploy workflow.

### Primary Site Runner

SSH to primary control plane node:

```bash
ssh root@<primary-control-plane-ip>

# Create runner directory
mkdir -p ~/actions-runner && cd ~/actions-runner

# Download runner
curl -o actions-runner-linux-x64-2.311.0.tar.gz -L \
  https://github.com/actions/runner/releases/download/v2.311.0/actions-runner-linux-x64-2.311.0.tar.gz

# Extract
tar xzf ./actions-runner-linux-x64-2.311.0.tar.gz

# Configure runner
./config.sh --url https://github.com/markjpickering/HomeLab \
  --token <RUNNER_TOKEN> \
  --labels primary \
  --name primary-runner

# Install as service
sudo ./svc.sh install
sudo ./svc.sh start
```

### Secondary Site Runner

SSH to secondary control plane node and repeat the above with `--labels secondary` and `--name secondary-runner`.

### Get Runner Token

1. Go to GitHub repository
2. **Settings** → **Actions** → **Runners** → **New self-hosted runner**
3. Copy the token from the configuration command

---

## Step 4: Enable Workflows

### Verify Workflows Are Present

```bash
ls -la .github/workflows/
# Should show: bootstrap.yml, deploy.yml
```

### Enable Actions in Repository

1. Go to your GitHub repository
2. Click **Actions** tab
3. If prompted, click **I understand my workflows, go ahead and enable them**

### Review Workflow Permissions

1. **Settings** → **Actions** → **General**
2. Under "Workflow permissions":
   - Select **Read and write permissions**
   - Check **Allow GitHub Actions to create and approve pull requests**
3. Click **Save**

---

## Step 5: Test Workflows

### Test Bootstrap Workflow

1. Go to **Actions** tab
2. Select **Bootstrap HomeLab Infrastructure**
3. Click **Run workflow**
4. Select:
   - **Phase**: `2` (Deploy ztnet)
   - **Site**: `both`
5. Click **Run workflow**
6. Monitor execution

### Test Deploy Workflow

**Option 1: Push changes**
```bash
# Make a small change to k8s-apps
echo "# Test" >> k8s-apps/README.md
git add k8s-apps/README.md
git commit -m "Test deploy workflow"
git push origin master
```

**Option 2: Manual trigger**
1. Go to **Actions** tab
2. Select **Deploy to HomeLab Sites**
3. Click **Run workflow**
4. Select target: `both`, `primary`, or `secondary`
5. Click **Run workflow**

### Verify Success

Check the workflow run:
- ✅ Green checkmark = success
- ❌ Red X = failure
- 🟡 Yellow dot = in progress

Click on the run to see detailed logs.

---

## Troubleshooting

### SSH Authentication Failed

**Error**: `Permission denied (publickey)`

**Solution**:
1. Verify SSH key is added to bootstrap host:
   ```bash
   ssh -i ~/.ssh/github_actions root@<bootstrap-host>
   ```
2. Ensure private key in `BOOTSTRAP_SSH_KEY` secret matches public key on host
3. Check `~/.ssh/authorized_keys` on bootstrap host

### ZeroTier Network ID Not Found

**Error**: `Network ID not found`

**Solution**:
1. Verify network ID in GitHub secret: `ZEROTIER_NETWORK_ID`
2. Check ztnet UI for correct network ID
3. Ensure network was created during Phase 2

### Self-Hosted Runner Not Found

**Error**: `No runner matching the label 'primary'`

**Solution**:
1. Verify runner is online:
   - Go to **Settings** → **Actions** → **Runners**
   - Check runner status (should be "Idle" or "Active")
2. Restart runner service:
   ```bash
   sudo ~/actions-runner/svc.sh restart
   ```
3. Re-register runner if needed

### Workflow Permissions Error

**Error**: `Resource not accessible by integration`

**Solution**:
1. Go to **Settings** → **Actions** → **General**
2. Under "Workflow permissions", select **Read and write permissions**
3. Click **Save**

### Secrets Not Found

**Error**: `Secret not found: <SECRET_NAME>`

**Solution**:
1. Go to **Settings** → **Secrets and variables** → **Actions**
2. Verify secret name matches exactly (case-sensitive)
3. Re-add secret if needed

### Bootstrap Script Fails

**Error**: Script exits with error

**Solution**:
1. Check workflow logs for specific error
2. SSH to bootstrap host and run manually:
   ```bash
   cd ~/homelab
   bash boostrap/linux/bootstrap-infrastructure.sh -e -p 2
   ```
3. Fix configuration issues
4. Re-run workflow

---

## Next Steps

After successfully setting up GitHub Actions:

1. **Test full bootstrap**:
   ```
   Run workflow → Phase: 1 (all) → Site: both
   ```

2. **Set up notifications** (optional):
   - Add Slack webhook for deployment notifications
   - Configure email notifications in GitHub

3. **Create deployment branches** (optional):
   - `dev` branch for testing
   - `staging` branch for pre-production
   - `master` for production

4. **Add validation workflow** (optional):
   - Create `.github/workflows/validate.yml`
   - Run validation on pull requests

5. **Document runbook**:
   - Emergency rollback procedures
   - Common troubleshooting steps
   - On-call procedures

---

## Summary Checklist

- [ ] All secrets added to GitHub repository
- [ ] `config.sh` updated with production values
- [ ] Terraform secrets encrypted with SOPS
- [ ] SSH key configured for bootstrap host
- [ ] Self-hosted runners installed (if using deploy workflow)
- [ ] Workflows enabled in repository
- [ ] Test bootstrap workflow executed successfully
- [ ] Test deploy workflow executed successfully
- [ ] Monitoring/alerting configured (optional)

---

## See Also

- [BOOTSTRAP-USAGE.md](BOOTSTRAP-USAGE.md) - Bootstrap script usage
- [TEARDOWN.md](TEARDOWN.md) - Teardown procedures
- [OPERATIONS-GUIDE.md](OPERATIONS-GUIDE.md) - Day-to-day operations
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
