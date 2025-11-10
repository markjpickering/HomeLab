#!/bin/bash
set -e

echo '🚀 HomeLab Linux Bootstrap'
echo '==========================='
echo ''

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "⚠️  This script should be run as root or with sudo"
    echo "Re-running with sudo..."
    exec sudo bash "$0" "$@"
fi

# Detect Debian version
DEBIAN_VERSION=$(lsb_release -cs)
echo "Detected Debian version: $DEBIAN_VERSION"
echo ''

# Update package lists and upgrade system
echo '📦 Updating system packages...'
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq

# Install essential base packages
echo '📦 Installing essential packages...'
apt-get install -y -qq \
    git \
    curl \
    wget \
    unzip \
    sudo \
    gnupg \
    software-properties-common \
    ca-certificates \
    lsb-release \
    jq
echo '✅ Essential packages installed'
echo ''

# Install Terraform
echo '📦 Installing Terraform...'
if command -v terraform &> /dev/null; then
    echo "Terraform is already installed: $(terraform version -json | grep -o '"version":"[^"]*' | cut -d'"' -f4)"
else
    wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com ${DEBIAN_VERSION} main" | tee /etc/apt/sources.list.d/hashicorp.list
    apt-get update -qq
    apt-get install -y -qq terraform
    echo "✅ Terraform installed: $(terraform version -json | grep -o '"version":"[^"]*' | cut -d'"' -f4)"
fi
echo ''

# Install Ansible
echo '📦 Installing Ansible...'
if command -v ansible &> /dev/null; then
    echo "Ansible is already installed: $(ansible --version | head -n1)"
else
    apt-get install -y -qq ansible
    echo "✅ Ansible installed: $(ansible --version | head -n1)"
fi
echo ''

# Install age (encryption tool for SOPS)
echo '📦 Installing age...'
if command -v age &> /dev/null; then
    echo "age is already installed: $(age --version 2>&1 | head -n1)"
else
    apt-get install -y -qq age
    echo "✅ age installed: $(age --version 2>&1 | head -n1)"
fi
echo ''

# Install SOPS (secrets management)
echo '📦 Installing SOPS...'
if command -v sops &> /dev/null; then
    echo "SOPS is already installed: $(sops --version)"
else
    SOPS_VERSION="3.9.0"
    wget -q "https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops-v${SOPS_VERSION}.linux.amd64" -O /usr/local/bin/sops
    chmod +x /usr/local/bin/sops
    echo "✅ SOPS installed: $(sops --version)"
fi
echo ''

# Install Docker
echo '📦 Installing Docker...'
if command -v docker &> /dev/null; then
    echo "Docker is already installed: $(docker --version)"
else
    # Install Docker prerequisites
    apt-get install -y -qq apt-transport-https ca-certificates curl gnupg lsb-release
    
    # Add Docker GPG key
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    # Add Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian ${DEBIAN_VERSION} stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Start and enable Docker
    systemctl enable docker
    systemctl start docker
    
    echo "✅ Docker installed: $(docker --version)"
fi
echo ''

# Install docker-compose standalone (for compatibility)
echo '📦 Installing docker-compose...'
if command -v docker-compose &> /dev/null; then
    echo "docker-compose is already installed: $(docker-compose --version)"
else
    DOCKER_COMPOSE_VERSION="2.24.5"
    curl -SL "https://github.com/docker/compose/releases/download/v${DOCKER_COMPOSE_VERSION}/docker-compose-linux-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    echo "✅ docker-compose installed: $(docker-compose --version)"
fi
echo ''

# Install additional useful tools
echo '📦 Installing additional tools...'
apt-get install -y -qq \
    vim \
    htop \
    net-tools \
    iputils-ping \
    dnsutils \
    jq

echo ''
echo '✅ Linux bootstrap complete!'
echo ''
echo 'Installed tools:'
echo "  - Terraform: $(terraform version -json | grep -o '\"version\":\"[^\"]*' | cut -d'\"' -f4)"
echo "  - Ansible: $(ansible --version | head -n1 | awk '{print $2}')"
echo "  - Docker: $(docker --version | awk '{print $3}' | tr -d ',')"
echo "  - docker-compose: $(docker-compose --version | awk '{print $4}' | tr -d ',')"
echo "  - SOPS: $(sops --version)"
echo "  - age: $(age --version 2>&1 | head -n1)"
echo ''
echo 'Next steps:'
echo '  1. Navigate to the terraform directory:'
echo '     cd ~/homelab/k8s-infra/terraform'
echo '  2. Initialize Terraform:'
echo '     terraform init'
echo '  3. Create your infrastructure:'
echo '     terraform plan'
echo '     terraform apply'
