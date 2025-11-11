# Authentication with Authentik

This document describes the Authentik identity provider setup for centralized authentication across your HomeLab.

## Overview

**Authentik provides:**
- Single Sign-On (SSO) for all services
- OAuth2/OIDC for modern apps
- LDAP server for legacy apps (Proxmox, Linux)
- Integration with Google and Microsoft login
- Self-service user portal
- Multi-factor authentication (MFA)

## When to Deploy

**Authentik is deployed AFTER bootstrap is complete:**

```
Bootstrap Process:
1. ✅ Phase 1: Deploy ztnet
2. ✅ Phase 2: Create ZeroTier network
3. ✅ Phase 3: Provision infrastructure (Proxmox uses root)
4. ✅ Phase 4: Configure k3s
5. ⭐ Phase 5: Deploy Authentik (this step)
6. Phase 6: Configure services to use Authentik
```

**Why after bootstrap?**
- Bootstrap requires Proxmox root access (chicken/egg problem)
- Authentik needs k3s cluster to be running
- Services can be added to Authentik incrementally

## Deployment

### Step 1: Generate Secrets

```bash
# Generate secrets for Authentik
export AUTHENTIK_SECRET_KEY=$(openssl rand -base64 32)
export POSTGRES_PASSWORD=$(openssl rand -base64 32)

# Store securely (use SOPS or Vault later)
echo "AUTHENTIK_SECRET_KEY: $AUTHENTIK_SECRET_KEY"
echo "POSTGRES_PASSWORD: $POSTGRES_PASSWORD"
```

### Step 2: Update Manifest Secrets

Edit `k8s-apps/auth/authentik.yaml`:

```yaml
stringData:
  secret-key: "YOUR_GENERATED_SECRET_KEY"
  postgres-password: "YOUR_GENERATED_POSTGRES_PASSWORD"
```

### Step 3: Deploy Authentik

```bash
# Deploy to k3s cluster
kubectl apply -f k8s-apps/auth/authentik.yaml

# Wait for pods to be ready
kubectl wait --for=condition=ready pod \
  -l app=authentik-server -n auth --timeout=300s

# Check status
kubectl get pods -n auth
```

### Step 4: Access Web UI

```bash
# Access Authentik
http://auth.homelab.internal
# or
http://10.147.17.110
```

**Initial Setup:**
1. Create admin account (akadmin)
2. Set strong password
3. Configure email (optional)

## Integration Guides

### 1. Proxmox Integration (LDAP)

**Why:** Proxmox needs LDAP or AD for centralized authentication

#### Configure Authentik LDAP Outpost

In Authentik UI:

1. **Create LDAP Provider:**
   - Go to: Applications → Providers → Create
   - Type: LDAP Provider
   - Name: `Proxmox LDAP`
   - Base DN: `dc=ldap,dc=goauthentik,dc=io`
   - Search Group: (select admin group)

2. **Create Application:**
   - Go to: Applications → Applications → Create
   - Name: `Proxmox`
   - Slug: `proxmox`
   - Provider: Select "Proxmox LDAP"

3. **Create Outpost:**
   - Go to: Applications → Outposts → Create
   - Name: `LDAP Outpost`
   - Type: LDAP
   - Applications: Select "Proxmox"

4. **Get Bind Credentials:**
   - Go to: Applications → Providers → Proxmox LDAP
   - Note the Bind DN: `cn=ldapservice,dc=ldap,dc=goauthentik,dc=io`
   - Generate service account password

#### Configure Proxmox

In Proxmox UI:

1. **Add LDAP Realm:**
   ```
   Datacenter → Permissions → Realms → Add → LDAP Server
   
   Realm: authentik
   Server: ldap.shared.homelab.internal (or 10.147.17.111)
   Port: 389
   Base DN: dc=ldap,dc=goauthentik,dc=io
   User Attribute: cn
   Bind DN: cn=ldapservice,dc=ldap,dc=goauthentik,dc=io
   Bind Password: (from Authentik)
   
   ✅ Default
   ✅ Secure (if using LDAPS on port 636)
   ```

2. **Test Connection:**
   - Click "Test"
   - Should show "Connection OK"

3. **Create User in Authentik:**
   - Authentik UI → Directory → Users → Create
   - Username: `john`
   - Name: `John Doe`
   - Email: `john@example.com`
   - Password: (set or send email invite)
   - Groups: Add to admin group for Proxmox admin access

4. **Login to Proxmox:**
   - Username: `john@authentik`
   - Password: (user's Authentik password)

#### Proxmox Permissions

Grant permissions in Proxmox:

```bash
# Via Proxmox UI
Datacenter → Permissions → Add → User Permission

Path: /
User: john@authentik
Role: Administrator (or custom role)
```

Or via CLI:
```bash
pveum acl modify / --users john@authentik --roles Administrator
```

### 2. Google OAuth Integration

**Setup Google OAuth:**

1. **Google Cloud Console:**
   - Go to: https://console.cloud.google.com/
   - Create project: "HomeLab Auth"
   - APIs & Services → OAuth consent screen
   - User Type: External
   - Add authorized domains: `homelab.internal`

2. **Create OAuth Credentials:**
   - APIs & Services → Credentials → Create → OAuth 2.0 Client
   - Application type: Web application
   - Name: Authentik
   - Authorized redirect URIs:
     ```
     https://auth.homelab.internal/source/oauth/callback/google/
     http://auth.homelab.internal/source/oauth/callback/google/
     ```
   - Save Client ID and Client Secret

3. **Configure in Authentik:**
   - Directory → Federation & Social login → Create
   - Type: Google OAuth
   - Name: Google
   - Consumer Key: (Client ID)
   - Consumer Secret: (Client Secret)
   - ✅ Enabled

4. **Test:**
   - Logout of Authentik
   - Should see "Login with Google" button
   - Click and authenticate with Google account

### 3. Microsoft OAuth Integration

**Setup Microsoft OAuth:**

1. **Azure Portal:**
   - Go to: https://portal.azure.com/
   - Azure Active Directory → App registrations → New registration
   - Name: Authentik HomeLab
   - Supported account types: Personal Microsoft accounts
   - Redirect URI:
     ```
     https://auth.homelab.internal/source/oauth/callback/microsoft/
     ```

2. **Configure Application:**
   - Copy Application (client) ID
   - Certificates & secrets → New client secret
   - Copy client secret value

3. **Configure in Authentik:**
   - Directory → Federation & Social login → Create
   - Type: Microsoft OAuth
   - Name: Microsoft
   - Client ID: (from Azure)
   - Client Secret: (from Azure)
   - ✅ Enabled

4. **Test:**
   - Should see "Login with Microsoft" button
   - Authenticate with Microsoft account

### 4. Grafana Integration (OAuth2/OIDC)

**In Authentik:**

1. **Create OAuth Provider:**
   - Applications → Providers → Create
   - Type: OAuth2/OpenID Provider
   - Name: Grafana
   - Client ID: grafana
   - Client Secret: (generate and save)
   - Redirect URIs: `https://grafana.homelab.internal/login/generic_oauth`

2. **Create Application:**
   - Applications → Applications → Create
   - Name: Grafana
   - Slug: grafana
   - Provider: Select "Grafana"

**In Grafana config:**

```ini
[auth.generic_oauth]
enabled = true
name = Authentik
client_id = grafana
client_secret = YOUR_CLIENT_SECRET
scopes = openid profile email
auth_url = https://auth.homelab.internal/application/o/authorize/
token_url = https://auth.homelab.internal/application/o/token/
api_url = https://auth.homelab.internal/application/o/userinfo/
role_attribute_path = contains(groups[*], 'Grafana Admins') && 'Admin' || 'Viewer'
```

### 5. ArgoCD Integration

**In Authentik:**

1. **Create OAuth Provider:**
   - Type: OAuth2/OpenID Provider
   - Name: ArgoCD
   - Client ID: argocd
   - Redirect URIs: `https://argocd.homelab.internal/auth/callback`

**In ArgoCD:**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  url: https://argocd.homelab.internal
  oidc.config: |
    name: Authentik
    issuer: https://auth.homelab.internal/application/o/argocd/
    clientID: argocd
    clientSecret: YOUR_CLIENT_SECRET
    requestedScopes:
      - openid
      - profile
      - email
```

### 6. Linux SSH/PAM Integration

**For centralized Linux user authentication:**

1. **Install LDAP client on Linux servers:**
   ```bash
   apt-get install libnss-ldap libpam-ldap ldap-utils
   ```

2. **Configure LDAP:**
   ```bash
   # /etc/ldap/ldap.conf
   BASE dc=ldap,dc=goauthentik,dc=io
   URI ldap://ldap.shared.homelab.internal
   ```

3. **Configure NSS:**
   ```bash
   # /etc/nsswitch.conf
   passwd: files ldap
   group: files ldap
   shadow: files ldap
   ```

4. **Configure PAM:**
   ```bash
   # /etc/pam.d/common-auth
   auth sufficient pam_ldap.so
   ```

5. **Test:**
   ```bash
   # Should show LDAP users
   getent passwd
   
   # SSH with LDAP user
   ssh john@server
   ```

## User Management

### Create Users

**Via Authentik UI:**
1. Directory → Users → Create
2. Fill in username, email, name
3. Set password or send invitation
4. Add to groups (for permissions)

**Via API:**
```bash
curl -X POST https://auth.homelab.internal/api/v3/core/users/ \
  -H "Authorization: Bearer YOUR_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "jane",
    "name": "Jane Doe",
    "email": "jane@example.com",
    "is_active": true
  }'
```

### Groups and Permissions

**Create Groups:**
1. Directory → Groups → Create
2. Name: `Proxmox Admins`
3. Add users to group

**Map to Proxmox:**
- Users in `Proxmox Admins` group get admin access
- Configure in Proxmox permissions

### Enable MFA

**For users:**
1. User portal → Settings → MFA Devices
2. Add device:
   - TOTP (Google Authenticator, Authy)
   - WebAuthn (YubiKey, FaceID)
   - Duo (requires Duo account)

**Enforce MFA:**
1. Flows & Stages → Stages → Create
2. Type: Authenticator Validation Stage
3. Add to authentication flow

## Backup and Recovery

### Backup Authentik Data

**Database backup (automatic via Velero):**
```bash
# Velero backs up PostgreSQL PVC automatically
velero backup create authentik-backup --include-namespaces auth
```

**Manual backup:**
```bash
# Dump PostgreSQL
kubectl exec -n auth authentik-postgresql-0 -- \
  pg_dump -U authentik authentik > authentik-backup.sql

# Upload to MinIO
mc cp authentik-backup.sql minio/backups/authentik/
```

### Restore

```bash
# Restore from Velero
velero restore create --from-backup authentik-backup

# Or manual restore
kubectl exec -i -n auth authentik-postgresql-0 -- \
  psql -U authentik authentik < authentik-backup.sql
```

## Monitoring

### Check Health

```bash
# Check pods
kubectl get pods -n auth

# Check logs
kubectl logs -n auth -l app=authentik-server --tail=50

# Check LDAP
ldapsearch -x -H ldap://ldap.shared.homelab.internal \
  -b "dc=ldap,dc=goauthentik,dc=io"
```

### Prometheus Metrics

Authentik exposes metrics at:
```
http://authentik.auth.svc.cluster.local:9000/metrics
```

Add ServiceMonitor:
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: authentik
  namespace: auth
spec:
  selector:
    matchLabels:
      app: authentik-server
  endpoints:
    - port: http
      path: /metrics
```

## Troubleshooting

### Proxmox Can't Connect to LDAP

**Check LDAP service:**
```bash
kubectl get svc -n auth authentik-ldap
kubectl logs -n auth -l app=authentik-ldap
```

**Test LDAP manually:**
```bash
ldapsearch -x -H ldap://10.147.17.111 \
  -D "cn=ldapservice,dc=ldap,dc=goauthentik,dc=io" \
  -w "PASSWORD" \
  -b "dc=ldap,dc=goauthentik,dc=io"
```

### OAuth Not Working

**Check redirect URIs match exactly:**
- Trailing slashes matter
- HTTP vs HTTPS matters
- Port numbers matter

**Check logs:**
```bash
kubectl logs -n auth -l app=authentik-server | grep oauth
```

### Users Can't Login

**Check user status:**
- Is user active?
- Is user in correct group?
- Password correct?

**Check authentication flow:**
- Authentik UI → Events → Logs
- Filter by username

## Security Best Practices

1. **Enable MFA for admin accounts**
2. **Use strong passwords** (enforce policy)
3. **Regular backups** (automated with Velero)
4. **Monitor login events** (Authentik audit log)
5. **Use HTTPS** (configure TLS certificates)
6. **Rotate secrets** periodically
7. **Review user permissions** quarterly

## Next Steps

After deploying Authentik:

1. ✅ Configure Proxmox LDAP integration
2. ✅ Setup Google/Microsoft OAuth
3. ✅ Migrate services to use Authentik OAuth
4. ✅ Enable MFA for all users
5. ✅ Setup automated backups
6. ✅ Configure monitoring alerts

## See Also

- [Authentik Documentation](https://goauthentik.io/docs/)
- [Proxmox User Management](https://pve.proxmox.com/wiki/User_Management)
- [MULTI-SITE-ARCHITECTURE.md](MULTI-SITE-ARCHITECTURE.md) - Overall architecture
- [STORAGE-ARCHITECTURE.md](STORAGE-ARCHITECTURE.md) - Backup strategy
