terraform {
  required_version = ">= 1.0"
  
  required_providers {
    # Proxmox provider for homelab VMs/LXC
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.50"
    }
    
    # LXD provider for Debian VPS containers
    lxd = {
      source  = "terraform-lxd/lxd"
      version = "~> 2.0"
    }
    
    # SOPS provider for encrypted secrets
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.0"
    }
  }
}

# Load encrypted secrets
data "sops_file" "secrets" {
  source_file = "${path.module}/secrets.enc.yaml"
}

# Proxmox Provider Configuration
provider "proxmox" {
  endpoint = data.sops_file.secrets.data["proxmox.endpoint"]
  api_token = "${data.sops_file.secrets.data["proxmox.api_token_id"]}=${data.sops_file.secrets.data["proxmox.api_token_secret"]}"
  insecure = true  # For self-signed certs in homelab
  
  ssh {
    agent = true
  }
}

# LXD Provider Configuration (for Debian VPS)
provider "lxd" {
  # Configuration can be added here for remote LXD hosts
}

# Example: Access secrets in resources
# resource "proxmox_virtual_environment_vm" "example" {
#   name = "example-vm"
#   # ... other configuration
#   
#   # Access secrets like this:
#   # password = data.sops_file.secrets.data["some.nested.secret"]
# }

# Example: Create a compute node (abstracted)
# module "k8s_node" {
#   source = "./modules/compute"
#   
#   platform = var.platform  # "proxmox" or "debian-vps"
#   name     = "k8s-node-01"
#   cores    = 4
#   memory   = 8192
# }