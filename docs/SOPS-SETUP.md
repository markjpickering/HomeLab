# SOPS Setup Guide

This guide explains how to set up and use SOPS (Secrets OPerationS) for managing encrypted secrets in your HomeLab infrastructure.

## What is SOPS?

SOPS encrypts values in YAML/JSON files while keeping the structure readable. This allows you to:
- Commit encrypted secrets to git safely
- Version control your secrets
- Share encrypted secrets with your team
- Decrypt automatically when running Terraform

## Initial Setup

### 1. Generate Age Key Pair (One-time)

After running the bootstrap script, generate your encryption key:

```bash
# Generate key pair
age-keygen -o ~/.config/sops/age/keys.txt

# Output will show:
# Public key: age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
# (keep your public key, you'll need it in step 2)
```

**IMPORTANT:** 
- The private key in `~/.config/sops/age/keys.txt` must be kept **secret** and **backed up**
- Without this key, you cannot decrypt your secrets!
- Store a backup in a password manager or encrypted USB drive

### 2. Update .sops.yaml

Edit `.sops.yaml` in the repo root and replace `YOUR_AGE_PUBLIC_KEY_HERE` with your public key from step 1:

```yaml
creation_rules:
  - path_regex: \.enc\.(yaml|yml|json|env)$
    age: >-
      age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx  # Your public key here
```

### 3. Commit the Updated Configuration

```bash
git add .sops.yaml
git commit -m "Configure SOPS with age public key"
git push
```

## Creating Encrypted Secrets

### Method 1: Create from Template

```bash
# Copy the template
cd ~/homelab/k8s-infra/terraform
cp secrets.yaml secrets.enc.yaml

# Edit and encrypt (SOPS will encrypt on save)
sops secrets.enc.yaml

# Add your real secrets, save and exit
# File is now encrypted!

# Commit the encrypted file
git add secrets.enc.yaml
git commit -m "Add encrypted secrets"
git push
```

### Method 2: Encrypt Existing File

```bash
# Encrypt an existing file
sops -e secrets.yaml > secrets.enc.yaml

# Or encrypt in-place
sops -e -i secrets.yaml
```

## Using Encrypted Secrets

### In Terraform

Terraform automatically decrypts via the SOPS provider:

```hcl
# Load secrets
data "sops_file" "secrets" {
  source_file = "${path.module}/secrets.enc.yaml"
}

# Use secrets
resource "proxmox_vm" "example" {
  # Access nested values with dot notation
  api_token = data.sops_file.secrets.data["proxmox.api_token_secret"]
}
```

### Manual Decryption

```bash
# View decrypted content
sops -d secrets.enc.yaml

# Decrypt to file
sops -d secrets.enc.yaml > secrets-decrypted.yaml

# Decrypt specific value
sops -d --extract '["proxmox"]["api_token_secret"]' secrets.enc.yaml
```

## Editing Encrypted Secrets

```bash
# SOPS will decrypt, open editor, then re-encrypt on save
sops secrets.enc.yaml
```

## Setting Up on New Machine

When bootstrapping a new machine or WSL instance:

### Option 1: Copy Existing Key (Recommended)

```bash
# Create directory
mkdir -p ~/.config/sops/age

# Copy your backed-up private key
nano ~/.config/sops/age/keys.txt
# Paste your private key (starts with AGE-SECRET-KEY-1...)

# Set permissions
chmod 600 ~/.config/sops/age/keys.txt
```

### Option 2: Generate New Key (For additional machines)

```bash
# Generate new key
age-keygen -o ~/.config/sops/age/keys.txt

# Add the new public key to .sops.yaml:
creation_rules:
  - path_regex: \.enc\.(yaml|yml|json|env)$
    age: >-
      age1old_key_here,
      age1new_key_here  # Multiple keys can decrypt

# Re-encrypt all files with both keys
find . -name "*.enc.yaml" -exec sops updatekeys {} \;
```

## Common Tasks

### Rotate Keys

```bash
# Generate new key
age-keygen -o ~/.config/sops/age/keys-new.txt

# Update .sops.yaml with new public key
# Re-encrypt all secrets
find . -name "*.enc.yaml" -exec sops updatekeys -y {} \;
```

### Check Encryption Status

```bash
# Verify file is encrypted
sops -d secrets.enc.yaml > /dev/null && echo "Can decrypt" || echo "Cannot decrypt"
```

### Backup Private Key

```bash
# Display private key (back up securely!)
cat ~/.config/sops/age/keys.txt

# Copy to password manager or encrypted storage
```

## Security Best Practices

1. **Never commit** unencrypted secrets files
2. **Always backup** your age private key securely
3. **Use different keys** for different environments (dev/prod)
4. **Rotate keys** periodically
5. **Audit access** - track who has the private key
6. **Test decryption** after encrypting to verify it works

## File Naming Convention

- `secrets.yaml` - Template (never contains real secrets)
- `secrets.enc.yaml` - Encrypted secrets (safe to commit)
- `*.enc.yaml` - Any encrypted file (auto-detected by SOPS)

## Troubleshooting

### "no age identity found"

Your private key is missing or not in the right location:
```bash
ls -la ~/.config/sops/age/keys.txt
```

### "failed to decrypt"

You don't have the correct private key for this encrypted file. Contact someone who has access to share the key with you.

### "MAC mismatch"

File may be corrupted. Restore from git or backup.

## Integration with CI/CD

For automated pipelines, store the age private key as a secret environment variable:

```bash
export SOPS_AGE_KEY="AGE-SECRET-KEY-1xxxx..."
sops -d secrets.enc.yaml
```

## Additional Resources

- [SOPS Documentation](https://github.com/getsops/sops)
- [age Specification](https://age-encryption.org/)
- [Terraform SOPS Provider](https://registry.terraform.io/providers/carlpett/sops/latest/docs)
