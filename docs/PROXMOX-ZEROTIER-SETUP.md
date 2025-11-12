# Proxmox ZeroTier Setup Guide

## Overview

This guide walks through installing and configuring ZeroTier on both Proxmox hosts to enable them to communicate over your HomeLab ZeroTier network.

## Prerequisites

- Both Proxmox hosts accessible via SSH
- ZeroTier network created (via bootstrap or ztnet UI)
- Network ID from ztnet controller
- Root access to both Proxmox hosts

## Quick Setup

### Option 1: Automated Script (Recommended)

```bash
# On each Proxmox host (run as root):

# Download script
wget https://raw.githubusercontent.com/YOUR_USERNAME/HomeLab/master/scripts/setup-proxmox-zerotier.sh

# Make executable
chmod +x setup-proxmox-zerotier.sh

# Run script
./setup-proxmox-zerotier.sh
```

The script will:
1. Install ZeroTier if not present
2. Join your HomeLab network
3. Display node address for authorization
4. Test connectivity
5. Save configuration

### Option 2: Manual Setup

If you prefer manual setup or need to troubleshoot:

## Manual Installation Steps

### Step 1: Install ZeroTier on Primary Proxmox Host

SSH into your primary Proxmox host:

```bash
ssh root@<primary-proxmox-ip>
```

Install ZeroTier:

```bash
curl -s https://install.zerotier.com | bash
```

Verify installation:

```bash
zerotier-cli --version
systemctl status zerotier-one
```

### Step 2: Join HomeLab Network (Primary Host)

Get your network ID from ztnet UI (`http://localhost:3000` or wherever ztnet is running).

Join the network:

```bash
# Replace with your actual network ID
NETWORK_ID="your-network-id-here"
zerotier-cli join $NETWORK_ID
```

Get node address:

```bash
zerotier-cli info
# Output: 200 info <node-address> <version> ONLINE
```

Note the `<node-address>` - you'll need this for authorization.

### Step 3: Authorize Primary Host

In the ztnet web UI:
1. Navigate to Networks → Your HomeLab Network → Members
2. Find the node with the address from Step 2
3. Check the "Authorized" checkbox
4. Optionally set a description: `proxmox-primary`

### Step 4: Verify Primary Host Connection

Check network status:

```bash
zerotier-cli listnetworks
```

You should see your network with status `OK` and an assigned IP (10.147.17.x).

Test connectivity:

```bash
# Ping the ZeroTier controller
ping 10.147.17.1

# Check assigned IP
ip addr show | grep 10.147.17
```

### Step 5: Repeat for Secondary Proxmox Host

SSH into secondary host:

```bash
ssh root@<secondary-proxmox-ip>
```

Repeat Steps 1-4, but:
- In Step 3, use description `proxmox-secondary`

## Verification

### Check Both Hosts are Connected

On each Proxmox host:

```bash
# Show ZeroTier status
zerotier-cli listnetworks

# Show assigned IP
zerotier-cli listnetworks | grep 10.147.17
```

### Test Inter-Host Communication

From primary host, ping secondary:

```bash
# Get secondary IP from ztnet UI or zerotier-cli listnetworks
ping 10.147.17.xx  # Replace with actual secondary IP
```

From secondary host, ping primary:

```bash
# Get primary IP from ztnet UI or zerotier-cli listnetworks
ping 10.147.17.xx  # Replace with actual primary IP
```

### Test k3s Cluster Connectivity

Once k3s is deployed on the hosts, verify:

```bash
# From primary host, ping k3s nodes
ping 10.147.17.10  # k3s server node
ping 10.147.17.11  # k3s agent node
```

## Expected IP Assignments

Based on your configuration:

**Proxmox Hosts:**
- Primary Proxmox: Any IP in 10.147.17.0/24 (not reserved)
- Secondary Proxmox: Any IP in 10.147.17.0/24 (not reserved)

**Reserved IPs:**
- 10.147.17.1 - ZeroTier controller
- 10.147.17.5 - Primary DNS
- 10.147.17.10-19 - Primary site k3s nodes
- 10.147.17.20-29 - Secondary site k3s nodes
- 10.147.17.25 - Secondary DNS
- 10.147.17.100-109 - Shared service VIPs
- 10.147.17.200 - Dashboard/Proxy VIP

## Troubleshooting

### ZeroTier Service Not Running

```bash
# Check status
systemctl status zerotier-one

# Start service
systemctl start zerotier-one

# Enable on boot
systemctl enable zerotier-one
```

### Node Not Showing in ztnet

- Verify ZeroTier service is running: `systemctl status zerotier-one`
- Check node is online: `zerotier-cli info`
- Verify network join: `zerotier-cli listnetworks`
- Check ztnet controller is accessible: `curl http://10.147.17.1:9993/status`

### No IP Assigned

Common causes:
1. **Node not authorized** - Check ztnet UI, authorize the node
2. **IP pool exhausted** - Expand IP pool in ztnet network settings
3. **Network not configured** - Verify network has IP assignment enabled

Check network configuration:

```bash
zerotier-cli listnetworks
# Should show "OK" status and assigned IP
```

If status is "REQUESTING_CONFIGURATION":
- Node needs authorization in ztnet UI
- Wait 30 seconds after authorizing

### Cannot Reach Other Hosts

1. **Verify both hosts authorized:**
   ```bash
   # On ztnet UI, both nodes should show "Authorized: ✓"
   ```

2. **Check IPs assigned:**
   ```bash
   zerotier-cli listnetworks | grep "10.147.17"
   ```

3. **Test ZeroTier network:**
   ```bash
   # From primary, test secondary IP
   ping -c 4 <secondary-zt-ip>
   ```

4. **Check firewall rules:**
   ```bash
   # Proxmox uses iptables, verify ZeroTier traffic allowed
   iptables -L -n | grep 10.147.17
   ```

### Firewall Issues

If ping fails but ZeroTier shows connected:

```bash
# Allow ZeroTier subnet through firewall
iptables -I INPUT -s 10.147.17.0/24 -j ACCEPT
iptables -I OUTPUT -d 10.147.17.0/24 -j ACCEPT

# Make persistent (Proxmox)
apt-get install iptables-persistent
netfilter-persistent save
```

## Configuration Files

### ZeroTier Configuration

```bash
# ZeroTier identity files
/var/lib/zerotier-one/identity.public
/var/lib/zerotier-one/identity.secret

# Network membership
/var/lib/zerotier-one/networks.d/<network-id>.conf

# Local configuration
/var/lib/zerotier-one/local.conf
```

### HomeLab Configuration

After running setup script:

```bash
# Configuration saved to:
/root/zerotier-homelab.conf

# View configuration
cat /root/zerotier-homelab.conf
```

## Maintenance

### View Network Status

```bash
# List all networks
zerotier-cli listnetworks

# Show detailed info
zerotier-cli info

# List network peers
zerotier-cli listpeers
```

### Leave Network

```bash
zerotier-cli leave <network-id>
```

### Rejoin Network

```bash
zerotier-cli join <network-id>
```

### Update ZeroTier

```bash
# Download and run installer again
curl -s https://install.zerotier.com | bash

# Or use package manager (Debian/Ubuntu)
apt-get update
apt-get upgrade zerotier-one
```

## Security Considerations

1. **Node Authorization** - Always manually authorize nodes in ztnet UI
2. **Access Control** - Use ZeroTier flow rules to restrict traffic if needed
3. **Firewall** - Keep host firewall enabled, allow only necessary ports
4. **Identity Files** - Protect `/var/lib/zerotier-one/identity.*` files

## Integration with HomeLab Bootstrap

The bootstrap process expects Proxmox hosts to be on the ZeroTier network because:

1. **k3s Node Provisioning** - Terraform creates VMs with ZeroTier IPs
2. **Ansible Configuration** - Ansible connects to nodes via ZeroTier
3. **Service Communication** - All services communicate over ZeroTier

**Important:** Complete this Proxmox ZeroTier setup **before** running the HomeLab bootstrap.

## Next Steps

After both Proxmox hosts are on ZeroTier:

1. ✅ Verify both hosts can ping each other
2. ✅ Verify both hosts can reach ZeroTier controller
3. ✅ Note the ZeroTier IPs for documentation
4. ➡️ Proceed with HomeLab bootstrap
5. ➡️ Deploy k3s clusters via Terraform
6. ➡️ Configure k3s via Ansible

## Quick Reference Commands

```bash
# Status check
zerotier-cli info
zerotier-cli listnetworks
systemctl status zerotier-one

# Network operations
zerotier-cli join <network-id>
zerotier-cli leave <network-id>

# Connectivity tests
ping 10.147.17.1          # Controller
ping <other-proxmox-zt-ip> # Other host

# IP information
ip addr show | grep 10.147.17
zerotier-cli listnetworks | grep 10.147.17

# Service control
systemctl start zerotier-one
systemctl stop zerotier-one
systemctl restart zerotier-one
systemctl enable zerotier-one
```

## Support

If issues persist:
1. Check ZeroTier logs: `journalctl -u zerotier-one -f`
2. Verify network configuration in ztnet UI
3. Review ZeroTier documentation: https://docs.zerotier.com
4. Check HomeLab repository issues
