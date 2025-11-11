#!/bin/bash
#
# Setup GitHub Actions Self-Hosted Runners for k3s clusters
# This script deploys runners to both primary and secondary sites
#

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/boostrap/config.sh"

echo "Setting up GitHub Actions runners for HomeLab"
echo "=============================================="
echo ""

# Check required environment variables
if [ -z "$GITHUB_REPO" ]; then
    echo "Error: GITHUB_REPO environment variable not set"
    echo "Example: export GITHUB_REPO=username/HomeLab"
    exit 1
fi

if [ -z "$GITHUB_TOKEN" ]; then
    echo "Error: GITHUB_TOKEN environment variable not set"
    echo "Generate a token at: https://github.com/settings/tokens"
    echo "Required scopes: repo, workflow, admin:org"
    exit 1
fi

# Install actions-runner-controller using Helm
echo "Installing actions-runner-controller..."
echo ""

# Add Helm repo
helm repo add actions-runner-controller https://actions-runner-controller.github.io/actions-runner-controller
helm repo update

# Create namespace
kubectl create namespace actions-runner-system --dry-run=client -o yaml | kubectl apply -f -

# Install controller
helm upgrade --install actions-runner-controller \
    actions-runner-controller/actions-runner-controller \
    --namespace actions-runner-system \
    --set=authSecret.create=true \
    --set=authSecret.github_token="$GITHUB_TOKEN" \
    --wait

echo "✅ Actions-runner-controller installed"
echo ""

# Deploy runner for primary site
echo "Deploying runner for primary site..."
cat <<EOF | kubectl apply -f -
apiVersion: actions.summerwind.dev/v1alpha1
kind: RunnerDeployment
metadata:
  name: github-runner-primary
  namespace: actions-runner-system
spec:
  replicas: 1
  template:
    spec:
      repository: $GITHUB_REPO
      labels:
        - self-hosted
        - primary
        - k3s
      nodeSelector:
        site: ${HOMELAB_PRIMARY_SITE_ID}
      env:
        - name: KUBECONFIG
          value: /root/.kube/config
      volumeMounts:
        - name: kubeconfig
          mountPath: /root/.kube
          readOnly: true
      volumes:
        - name: kubeconfig
          secret:
            secretName: runner-kubeconfig
EOF

echo "✅ Primary site runner deployed"
echo ""

# Deploy runner for secondary site
echo "Deploying runner for secondary site..."
cat <<EOF | kubectl apply -f -
apiVersion: actions.summerwind.dev/v1alpha1
kind: RunnerDeployment
metadata:
  name: github-runner-secondary
  namespace: actions-runner-system
spec:
  replicas: 1
  template:
    spec:
      repository: $GITHUB_REPO
      labels:
        - self-hosted
        - secondary
        - k3s
      nodeSelector:
        site: ${HOMELAB_SECONDARY_SITE_ID}
      env:
        - name: KUBECONFIG
          value: /root/.kube/config
      volumeMounts:
        - name: kubeconfig
          mountPath: /root/.kube
          readOnly: true
      volumes:
        - name: kubeconfig
          secret:
            secretName: runner-kubeconfig
EOF

echo "✅ Secondary site runner deployed"
echo ""

# Create kubeconfig secret (using in-cluster config)
echo "Creating kubeconfig secret..."
kubectl create secret generic runner-kubeconfig \
    --from-file=config=/etc/rancher/k3s/k3s.yaml \
    --namespace=actions-runner-system \
    --dry-run=client -o yaml | kubectl apply -f -

echo "✅ Kubeconfig secret created"
echo ""

# Wait for runners to be ready
echo "Waiting for runners to be ready..."
kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=github-runner-primary \
    -n actions-runner-system \
    --timeout=300s

kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=github-runner-secondary \
    -n actions-runner-system \
    --timeout=300s

echo ""
echo "✅ GitHub Actions runners are ready!"
echo ""
echo "Runners should now appear in:"
echo "https://github.com/$GITHUB_REPO/settings/actions/runners"
echo ""
echo "Labels:"
echo "  Primary site: [self-hosted, primary, k3s]"
echo "  Secondary site: [self-hosted, secondary, k3s]"
