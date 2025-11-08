#!/bin/bash
# HomeLab Standalone Bootstrap
# Can be run via: curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/HomeLab/main/boostrap/linux/bootstrap-standalone.sh | bash
# Or with custom repo: curl -fsSL URL | bash -s -- https://github.com/YOUR_USERNAME/HomeLab.git

set -e

echo '🚀 HomeLab Standalone Bootstrap'
echo '================================'
echo ''

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "⚠️  This script requires root privileges"
    echo "Re-running with sudo..."
    exec sudo bash "$0" "$@"
fi

# Configuration
GITHUB_REPO="${1:-https://github.com/YOUR_USERNAME/HomeLab.git}"  # Update with your repo
INSTALL_DIR="/root/homelab"
BOOTSTRAP_SCRIPT="$INSTALL_DIR/boostrap/linux/bootstrap.sh"

echo "Repository: $GITHUB_REPO"
echo "Install directory: $INSTALL_DIR"
echo ''

# Step 1: Install minimal dependencies (only git and curl)
echo '📦 Installing minimal dependencies (git, curl)...'
export DEBIAN_FRONTEND=noninteractive

# Detect package manager
if command -v apt-get &> /dev/null; then
    apt-get update -qq
    apt-get install -y -qq git curl
elif command -v yum &> /dev/null; then
    yum install -y git curl
elif command -v apk &> /dev/null; then
    apk add --no-cache git curl
else
    echo "❌ Unsupported package manager. This script supports apt, yum, or apk."
    exit 1
fi

echo '✅ Git and curl installed'
echo ''

# Step 2: Clone or update repository
echo '📦 Cloning/updating HomeLab repository...'
if [ -d "$INSTALL_DIR" ]; then
    echo "Directory $INSTALL_DIR already exists. Updating..."
    cd "$INSTALL_DIR"
    git pull
else
    echo "Cloning repository..."
    git clone "$GITHUB_REPO" "$INSTALL_DIR"
fi

echo '✅ Repository ready'
echo ''

# Step 3: Execute full bootstrap script
echo '📦 Executing full bootstrap script...'
if [ -f "$BOOTSTRAP_SCRIPT" ]; then
    chmod +x "$BOOTSTRAP_SCRIPT"
    bash "$BOOTSTRAP_SCRIPT"
else
    echo "❌ Bootstrap script not found at $BOOTSTRAP_SCRIPT"
    echo "Please ensure your repository contains boostrap/linux/bootstrap.sh"
    exit 1
fi

echo ''
echo '🎉 Standalone bootstrap complete!'
echo ''
echo 'Your HomeLab environment is ready at:'
echo "  $INSTALL_DIR"
