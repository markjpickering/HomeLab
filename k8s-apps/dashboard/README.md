# Heimdall Dashboard

Heimdall provides a beautiful, organized landing page for all your HomeLab services. It's your homepage for accessing everything in your infrastructure.

## Features

- **Visual service menu** - Click-able tiles with icons for each service
- **Auto-organized** - Services grouped by site (primary/secondary/shared)
- **Easy management** - Add/edit/remove services via web UI
- **Responsive** - Works on desktop, tablet, and mobile
- **Customizable** - Backgrounds, colors, layouts all configurable
- **Search** - Quick search to find services
- **Enhanced items** - Show stats from services (optional)

## Access URLs

The dashboard is accessible from multiple URLs:

- `http://home.hl` - Main shortcut
- `http://dashboard.services.hl` - Shared access
- `http://dashboard.pickers.hl` - Primary site
- `http://dashboard.sheila.hl` - Secondary site
- `http://hl` - Ultra-short access

## Deployment

### Deploy to Kubernetes

```bash
# Deploy Heimdall dashboard
kubectl apply -f k8s-apps/dashboard/heimdall.yaml

# Check deployment status
kubectl get pods -n dashboard

# Check service IP
kubectl get svc -n dashboard
```

### Verify DNS Registration

```bash
# Check DNS records (after external-dns processes them)
dig home.hl @10.147.17.5
dig dashboard.services.hl @10.147.17.5
```

## Initial Setup

### First Access

1. Navigate to `http://home.hl` in your browser
2. Heimdall will show the initial setup wizard
3. Set your preferred theme (dark/light)
4. The pre-configured services will be loaded automatically

### Adding Services

**Via Web UI:**
1. Click the settings icon (top-right)
2. Click "Add Application"
3. Fill in:
   - **Title**: Service name (e.g., "ArgoCD")
   - **URL**: Service URL (e.g., `http://argocd.pickers.hl`)
   - **Description**: Brief description
   - **Color**: Hex color for the tile
4. Optional: Add icon (Heimdall has built-in icons for many apps)
5. Click "Save"

**Automatic with Enhanced Apps:**
Heimdall can pull stats from many popular applications automatically:
- Click "Settings" → "Enhanced Apps"
- Select your app type (e.g., "Grafana")
- Enter API details
- Tile will show live stats!

## Pre-Configured Services

The deployment includes these services organized by category:

### Pickering's Home (Primary Site)
- ArgoCD - GitOps deployment
- Grafana - Metrics & monitoring
- Traefik - Ingress controller dashboard

### Sheila's Home (Secondary Site)
- ArgoCD - GitOps deployment
- Grafana - Metrics & monitoring
- Traefik - Ingress controller dashboard

### Shared Services
- Vault - Secrets management
- Harbor Registry - Container registry
- MinIO - Object storage
- Authentik - Identity provider & SSO
- Technitium DNS - DNS management
- ZTnet - ZeroTier controller

### Infrastructure
- Proxmox - Hypervisor management

## Customization

### Backgrounds

**Set custom background:**
1. Settings → Appearance
2. Upload image or provide URL
3. Choose background style (cover, contain, etc.)

**Recommended backgrounds:**
- Solid dark color: `#1a1a1a`
- Gradient: Use CSS gradients
- Image: 1920x1080 or higher resolution

### Themes

**Built-in themes:**
- Dark (default)
- Light
- Custom (define your own colors)

**To change theme:**
Settings → Theme → Select theme

### Organization

**Create sections:**
1. Services are auto-organized by the JSON config
2. Drag and drop to reorder
3. Create new sections via "Add item" → "Add tag"

**Tips:**
- Group by site (primary/secondary/shared)
- Group by function (monitoring/storage/security)
- Use colors to distinguish categories

## Enhanced Applications

Heimdall supports "enhanced" tiles that show live stats:

**Supported apps with enhancements:**
- **Sonarr/Radarr** - Show upcoming downloads
- **Plex** - Show currently playing
- **Proxmox** - Show VM status and resource usage
- **PiHole** - Show blocked queries
- **And many more...**

**To enable:**
1. Add application normally
2. Settings → Select app type from dropdown
3. Enter API URL and credentials
4. Save - tile will update with live data

## Backup & Restore

### Manual Backup

Heimdall stores configuration in the PVC. To backup:

```bash
# Backup entire config directory
kubectl exec -n dashboard deployment/heimdall -- tar czf /tmp/heimdall-backup.tar.gz /config

kubectl cp dashboard/heimdall-<pod-id>:/tmp/heimdall-backup.tar.gz ./heimdall-backup.tar.gz
```

### Restore

```bash
# Copy backup to pod
kubectl cp ./heimdall-backup.tar.gz dashboard/heimdall-<pod-id>:/tmp/

# Extract
kubectl exec -n dashboard deployment/heimdall -- tar xzf /tmp/heimdall-backup.tar.gz -C /
```

### GitOps Backup

Configuration is also stored in SQLite database at `/config/app.sqlite`. Consider:
- Regular backups via Velero
- Export config and commit to Git
- Use config management for reproducibility

## Troubleshooting

### Dashboard not accessible

```bash
# Check pod status
kubectl get pods -n dashboard

# Check logs
kubectl logs -n dashboard deployment/heimdall

# Check service
kubectl get svc -n dashboard
```

### Services not loading

1. **Check DNS**: Ensure service URLs resolve
   ```bash
   dig argocd.pickers.hl @10.147.17.5
   ```

2. **Check network**: Ensure pod can reach services
   ```bash
   kubectl exec -n dashboard deployment/heimdall -- curl http://argocd.pickers.hl
   ```

3. **Check URL format**: URLs should be complete (include `http://` or `https://`)

### Enhanced apps not working

1. **Check API access**: Ensure API endpoint is reachable
2. **Verify credentials**: Double-check API keys/tokens
3. **Check app type**: Select correct app type from dropdown
4. **Review logs**: Look for API errors in Heimdall logs

### Slow to load

1. **Check resources**: Ensure pod has sufficient memory/CPU
2. **Optimize icons**: Use smaller icon images
3. **Disable enhancements**: Turn off enhanced apps temporarily
4. **Check network**: Verify fast network path to services

## Security

### Authentication

**Option 1: Authentik SSO (Recommended)**

Protect Heimdall with Authentik forward-auth:

```yaml
# Add to heimdall.yaml
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: heimdall-auth
  namespace: dashboard
spec:
  forwardAuth:
    address: http://authentik.auth.svc.cluster.local/outpost.goauthentik.io/auth/traefik
    trustForwardHeader: true

# Update IngressRoutes to use middleware
spec:
  routes:
    - match: Host(`home.hl`)
      middlewares:
        - name: heimdall-auth
      services:
        - name: heimdall
```

**Option 2: Network-level**

- Keep dashboard on internal network only
- Access via ZeroTier VPN
- No public exposure

**Option 3: Heimdall built-in auth**

Heimdall has basic authentication:
- Settings → Security
- Enable authentication
- Create users

## Best Practices

1. **Keep it simple** - Don't overload with too many services
2. **Use categories** - Organize by site or function
3. **Add descriptions** - Help identify what each service does
4. **Use icons** - Visual identification is faster
5. **Test links** - Verify all URLs work before deploying
6. **Regular updates** - Add new services as you deploy them
7. **Backup config** - Backup SQLite database regularly

## Advanced: Custom CSS

Add custom styling via Settings → Appearance → Custom CSS:

```css
/* Example: Larger tiles */
.item {
  height: 180px !important;
}

/* Example: Custom font */
body {
  font-family: 'Roboto', sans-serif;
}

/* Example: Animate tiles on hover */
.item:hover {
  transform: scale(1.05);
  transition: transform 0.2s;
}
```

## Integration with Other Tools

### Bookmarks

Set as browser homepage:
1. Browser settings → Homepage
2. Set to `http://home.hl`

### Mobile

Add to home screen:
1. Open `http://home.hl` in mobile browser
2. Browser menu → "Add to Home Screen"
3. Icon appears on home screen

### Voice Assistants

Use with Home Assistant:
- Create webhook to open specific services
- "Hey Google, open Grafana"

## Updates

```bash
# Update Heimdall image
kubectl set image deployment/heimdall heimdall=linuxserver/heimdall:latest -n dashboard

# Or edit deployment
kubectl edit deployment heimdall -n dashboard

# Restart to pick up changes
kubectl rollout restart deployment/heimdall -n dashboard
```

## Alternatives

If Heimdall doesn't meet your needs, consider:

- **Homer** - Static config, faster, more technical
- **Organizr** - More features, heavier
- **Dashy** - Modern, highly customizable
- **Flame** - Minimalist design
- **Homepage** - Widget-focused

## Resources

- [Heimdall GitHub](https://github.com/linuxserver/Heimdall)
- [Heimdall Documentation](https://heimdall.site)
- [LinuxServer.io Docs](https://docs.linuxserver.io/images/docker-heimdall)

## Example: Adding a New Service

When you deploy a new service to your HomeLab:

1. **Via Heimdall UI:**
   - Click settings icon
   - "Add Application"
   - Title: "Prometheus"
   - URL: `http://prometheus.services.hl`
   - Description: "Metrics Collection"
   - Color: `#e6522c` (Prometheus orange)
   - Icon: Search for "prometheus" in icon picker
   - Save

2. **Automatic via external-dns:**
   - Service is automatically registered in DNS
   - Heimdall link works immediately
   - No DNS configuration needed

3. **Enhanced app (if supported):**
   - Settings → Select "Prometheus" type
   - Enter API URL
   - Tile shows live metric count
