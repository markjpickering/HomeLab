# GitHub Actions CI/CD for HomeLab

This document describes the GitHub Actions setup for automated deployment to both HomeLab sites.

## Overview

The HomeLab uses **GitOps** with GitHub Actions to automatically deploy changes to both primary and secondary sites when you push to the `master` branch.

**Architecture:**
- Self-hosted runners run on each k3s cluster
- Runners are labeled by site (`primary`, `secondary`)
- Workflows deploy to both sites in parallel
- Changes to `k8s-apps/` trigger automatic deployments

## Workflows

### 1. Bootstrap Workflow (`bootstrap.yml`)

**Purpose**: Initial infrastructure setup

**Trigger**: Manual (workflow_dispatch)

**What it does:**
- Runs on GitHub-hosted runner
- SSHs to bootstrap host
- Executes `bootstrap-infrastructure.sh` in non-interactive mode
- Supports all 6 phases

**Usage:**
```
GitHub → Actions → Bootstrap HomeLab Infrastructure → Run workflow
  - Phase: 1 (Complete bootstrap)
  - Site: both
```

### 2. Deploy Workflow (`deploy.yml`)

**Purpose**: Automatic deployment on code changes

**Trigger**: 
- Push to `master` branch (paths: `k8s-apps/**`, `k8s-infra/**`)
- Manual trigger with site selection

**What it does:**
- Runs on self-hosted runners (one at each site)
- Pulls latest code
- Applies k3s manifests with `kubectl apply`
- Verifies deployment
- Reports status

**Automatic on push:**
```bash
git add k8s-apps/my-app/deployment.yaml
git commit -m "Update my-app"
git push origin master
# Both sites update automatically!
```

**Manual trigger:**
```
GitHub → Actions → Deploy to HomeLab Sites → Run workflow
  - Target: both (or primary/secondary)
```

## Setup Instructions

### Step 1: Configure GitHub Repository Secrets

Go to: `https://github.com/YOUR_USERNAME/HomeLab/settings/secrets/actions`

Add these secrets:

```
# For bootstrap workflow (optional - only if using bootstrap workflow)
BOOTSTRAP_SSH_KEY        # Private SSH key to access bootstrap host
BOOTSTRAP_HOST           # IP or hostname of bootstrap host
BOOTSTRAP_USER           # SSH username (usually 'root')

# ZeroTier network ID (for automated bootstrap)
ZEROTIER_NETWORK_ID      # From .zerotier-network-id file

# GitHub token for self-hosted runners
GITHUB_TOKEN             # Personal Access Token with repo, workflow scopes
```

### Step 2: Setup Self-Hosted Runners

After k3s clusters are deployed, install runners on **each site**:

```bash
# SSH to primary site k3s server
ssh root@10.147.17.10

# Set environment variables
export GITHUB_REPO="YOUR_USERNAME/HomeLab"
export GITHUB_TOKEN="ghp_yourpersonalaccesstoken"

# Run setup script
cd /root/homelab
bash k8s-apps/github-runner/setup-runners.sh
```

This installs [actions-runner-controller](https://github.com/actions/actions-runner-controller) which manages ephemeral runners on your k3s clusters.

### Step 3: Verify Runners

Check that runners appear in GitHub:
```
https://github.com/YOUR_USERNAME/HomeLab/settings/actions/runners
```

You should see:
- ✅ `github-runner-primary-xxxxx` (self-hosted, primary, k3s)
- ✅ `github-runner-secondary-xxxxx` (self-hosted, secondary, k3s)

### Step 4: Test Deployment

Make a test change:

```bash
# Create a test manifest
cat > k8s-apps/test/nginx.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-test
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx-test
  template:
    metadata:
      labels:
        app: nginx-test
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
EOF

# Commit and push
git add k8s-apps/test/
git commit -m "Test automated deployment"
git push origin master

# Watch the workflow run
# GitHub → Actions → Deploy to HomeLab Sites (should start automatically)
```

## Workflow Files

### Bootstrap Workflow

Location: `.github/workflows/bootstrap.yml`

**Inputs:**
- `phase`: Which bootstrap phase to run (1-6)
- `site`: Which site to bootstrap (primary, secondary, both)

**Jobs:**
- `bootstrap`: Runs on GitHub-hosted runner, SSHs to bootstrap host

### Deploy Workflow

Location: `.github/workflows/deploy.yml`

**Triggers:**
- Push to `master` with changes in `k8s-apps/` or `k8s-infra/`
- Manual dispatch with target selection

**Jobs:**
- `deploy-primary`: Runs on `[self-hosted, primary]` runner
- `deploy-secondary`: Runs on `[self-hosted, secondary]` runner
- `notify`: Aggregates and reports results

## How It Works

### Automatic Deployment Flow

```
1. Developer pushes to master
   └─> GitHub detects changes in k8s-apps/

2. Workflow starts
   ├─> deploy-primary job (runs on primary site)
   │   ├─> Checkout code
   │   ├─> Apply manifests with kubectl
   │   └─> Verify deployment
   │
   └─> deploy-secondary job (runs on secondary site)
       ├─> Checkout code
       ├─> Apply manifests with kubectl
       └─> Verify deployment

3. Summary notification
   └─> Both sites updated ✅
```

### Self-Hosted Runner Architecture

```
GitHub
  │
  ├─> Workflow triggers
  │
  ├─────────────────────────────────────┐
  │                                     │
  ▼                                     ▼
┌────────────────┐             ┌────────────────┐
│  Primary Site  │             │ Secondary Site │
│                │             │                │
│  k3s cluster   │             │  k3s cluster   │
│  ┌──────────┐  │             │  ┌──────────┐  │
│  │ Runner   │  │             │  │ Runner   │  │
│  │ Pod      │  │             │  │ Pod      │  │
│  │          │  │             │  │          │  │
│  │ kubectl  │  │             │  │ kubectl  │  │
│  └──────────┘  │             │  └──────────┘  │
└────────────────┘             └────────────────┘
```

## Runner Management

### Scale Runners

Increase replicas for faster deployments:

```bash
kubectl patch runnerdeployment github-runner-primary \
  -n actions-runner-system \
  --type=merge \
  -p '{"spec":{"replicas":2}}'
```

### View Runner Logs

```bash
# Primary site runner logs
kubectl logs -n actions-runner-system \
  -l app.kubernetes.io/name=github-runner-primary \
  -f

# Secondary site runner logs
kubectl logs -n actions-runner-system \
  -l app.kubernetes.io/name=github-runner-secondary \
  -f
```

### Restart Runners

```bash
# Delete runner pods (they'll be recreated)
kubectl delete pod -n actions-runner-system \
  -l app.kubernetes.io/name=github-runner-primary

kubectl delete pod -n actions-runner-system \
  -l app.kubernetes.io/name=github-runner-secondary
```

### Remove Runners

```bash
helm uninstall actions-runner-controller -n actions-runner-system
kubectl delete namespace actions-runner-system
```

## Security Considerations

### Runner Isolation

- Runners run in dedicated namespace (`actions-runner-system`)
- Each runner has kubectl access to its cluster only
- Runners use ephemeral pods (destroyed after each job)
- Secrets managed via k3s secrets

### GitHub Token Permissions

Required scopes for `GITHUB_TOKEN`:
- `repo` - Access repository
- `workflow` - Trigger workflows
- `admin:org` - Register runners (if using organization repo)

**Never commit tokens to Git!** Always use GitHub Secrets.

### Network Security

- Runners communicate with GitHub over HTTPS
- All inter-site traffic over ZeroTier (encrypted)
- No external exposure required (runners initiate connection)

## Troubleshooting

### Workflow not triggering

Check trigger paths:
```yaml
paths:
  - 'k8s-apps/**'     # Only triggers on changes here
  - 'k8s-infra/**'
```

If you change docs, workflows won't trigger (by design).

### Runner offline

Check runner pod status:
```bash
kubectl get pods -n actions-runner-system
```

View runner logs:
```bash
kubectl logs -n actions-runner-system \
  -l app.kubernetes.io/component=runner
```

Common issues:
- GitHub token expired (update secret)
- Network connectivity (check ZeroTier)
- Resource constraints (increase pod resources)

### Deployment failed

Check kubectl access:
```bash
# From runner pod
kubectl get nodes
kubectl get pods -A
```

Check manifest syntax:
```bash
kubectl apply --dry-run=client -f k8s-apps/my-app/
```

View workflow logs in GitHub Actions UI.

## GitOps Best Practices

### 1. Never Deploy Manually

Always use Git as source of truth:
```bash
# ❌ Bad
kubectl apply -f deployment.yaml

# ✅ Good
git add deployment.yaml
git commit -m "Update deployment"
git push
```

### 2. Use Kustomize or Helm

Organize manifests:
```
k8s-apps/
├── base/              # Base configs
│   └── deployment.yaml
├── overlays/
│   ├── primary/       # Primary site customizations
│   └── secondary/     # Secondary site customizations
```

### 3. Test in Feature Branches

```bash
# Create feature branch
git checkout -b feature/new-app

# Make changes
vim k8s-apps/new-app/deployment.yaml

# Test locally (optional)
kubectl apply --dry-run=client -f k8s-apps/new-app/

# Push to feature branch (won't auto-deploy)
git push origin feature/new-app

# Create PR, review, then merge to master (auto-deploys)
```

### 4. Use Semantic Commit Messages

```
feat: Add new service to k8s-apps
fix: Correct replica count for nginx
chore: Update GitHub Actions workflow
docs: Update deployment guide
```

## Advanced: Multi-Environment Workflows

For dev/staging/production:

```yaml
on:
  push:
    branches:
      - master        # Production
      - staging       # Staging
      - develop       # Development
```

Deploy to different namespaces per environment.

## See Also

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [actions-runner-controller](https://github.com/actions/actions-runner-controller)
- [MULTI-SITE-ARCHITECTURE.md](MULTI-SITE-ARCHITECTURE.md) - Overall architecture
- [CONFIGURATION.md](CONFIGURATION.md) - Configuration reference
