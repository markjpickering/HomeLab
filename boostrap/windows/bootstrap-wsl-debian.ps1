# HomeLab Bootstrap - Create Debian WSL and Setup Terraform
# This script:
# 1. Creates a minimal Debian WSL instance
# 2. Clones the HomeLab repository from GitHub
# 3. Executes the Terraform bootstrap script

# Elevate to Administrator if needed
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$AlreadyElevated = $env:SCRIPT_ELEVATED -eq "1"

if (-not $IsAdmin -and -not $AlreadyElevated) {
    Write-Host "🔐 Relaunching with Administrator privileges..." -ForegroundColor Yellow
    $scriptPath = $PSCommandPath
    $currentExe = (Get-Process -Id $PID).Path
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $currentExe
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"`$env:SCRIPT_ELEVATED='1'; & '$scriptPath'`""
    $psi.Verb = "runas"
    $psi.UseShellExecute = $true
    try {
        $process = [System.Diagnostics.Process]::Start($psi)
        if ($null -eq $process) {
            Write-Host "❌ Elevation was cancelled or failed. Please run this script as Administrator." -ForegroundColor Red
            exit 1
        }
        Write-Host "✅ Elevated process started. This window will now close." -ForegroundColor Green
        exit 0
    } catch {
        Write-Host "❌ Elevation failed: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

# Configuration
$WSL_DISTRO_NAME = "HomeLab-Debian"
$INSTALL_DIR = "/root/homelab"

# Get repository URL from environment or prompt user
$GITHUB_REPO = $env:HOMELAB_REPO_URL
if (-not $GITHUB_REPO) {
    Write-Host "`n📋 Repository Configuration" -ForegroundColor Cyan
    Write-Host "================================" -ForegroundColor Cyan
    Write-Host "Please enter your HomeLab repository URL" -ForegroundColor Yellow
    Write-Host "Example: https://github.com/username/HomeLab.git" -ForegroundColor DarkGray
    Write-Host ""
    
    # Try to detect from current directory if we're in a git repo
    try {
        $gitRemote = git remote get-url origin 2>$null
        if ($gitRemote) {
            Write-Host "Detected repository: $gitRemote" -ForegroundColor Green
            $useDetected = Read-Host "Use this repository? (Y/n)"
            if ($useDetected -eq "" -or $useDetected -eq "Y" -or $useDetected -eq "y") {
                $GITHUB_REPO = $gitRemote
            }
        }
    } catch {
        # Not in a git repository, that's fine
    }
    
    # If still not set, prompt
    if (-not $GITHUB_REPO) {
        $GITHUB_REPO = Read-Host "Repository URL"
        if (-not $GITHUB_REPO) {
            Write-Host "❌ No repository URL provided. Cannot continue." -ForegroundColor Red
            Write-Host ""
            Write-Host "You can also set the environment variable:" -ForegroundColor Yellow
            Write-Host "  `$env:HOMELAB_REPO_URL = 'https://github.com/username/HomeLab.git'" -ForegroundColor White
            Write-Host "  .\bootstrap-wsl-debian.ps1" -ForegroundColor White
            exit 1
        }
    }
    
    Write-Host "✅ Using repository: $GITHUB_REPO" -ForegroundColor Green
    Write-Host ""
}

# Helper function for steps
function Step {
    param (
        [string]$Message,
        [scriptblock]$Action
    )
    Write-Host "`n➡️  $Message" -ForegroundColor Cyan
    $ErrorActionPreference = 'Stop'
    try {
        & $Action
        Write-Host "✅ Completed: $Message" -ForegroundColor Green
    } catch {
        Write-Host "❌ Failed: $Message" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor DarkRed
        exit 1
    }
}

# Step 1: Check WSL is installed
Step "Checking WSL installation" {
    $wslVersion = wsl --version 2>$null
    if (-not $wslVersion) {
        Write-Host "Installing WSL..." -ForegroundColor Yellow
        wsl --install --no-distribution
        Write-Host "⚠️  WSL installed. Please restart your computer and run this script again." -ForegroundColor Yellow
        exit 0
    }
}

# Step 2: Check if distro already exists
Step "Checking for existing $WSL_DISTRO_NAME distribution" {
    $existingDistros = wsl -l -q
    if ($existingDistros -match $WSL_DISTRO_NAME) {
        Write-Host "⚠️  $WSL_DISTRO_NAME already exists." -ForegroundColor Yellow
        $response = Read-Host "Do you want to unregister and recreate it? (yes/no)"
        if ($response -eq "yes") {
            wsl --unregister $WSL_DISTRO_NAME
            Write-Host "Unregistered $WSL_DISTRO_NAME"
        } else {
            Write-Host "Using existing $WSL_DISTRO_NAME distribution"
            $script:useExisting = $true
        }
    }
}

# Step 3: Install Debian WSL
if (-not $script:useExisting) {
    Step "Installing minimal Debian WSL distribution" {
        wsl --install -d Debian
        Write-Host "Waiting for Debian setup to complete..."
        Start-Sleep -Seconds 5
        
        # Rename to our custom name if needed
        $distros = wsl -l -q
        if ($distros -notmatch $WSL_DISTRO_NAME -and $distros -match "Debian") {
            # Export and reimport with custom name
            $tempPath = "$env:TEMP\debian-wsl.tar"
            wsl --export Debian $tempPath
            wsl --unregister Debian
            wsl --import $WSL_DISTRO_NAME "$env:LOCALAPPDATA\WSL\$WSL_DISTRO_NAME" $tempPath
            Remove-Item $tempPath
        }
    }
}

# Step 4: Install only git (minimal requirement to clone repo)
Step "Installing git (required to clone repository)" {
    wsl -d $WSL_DISTRO_NAME -- bash -c @"
export DEBIAN_FRONTEND=noninteractive
if ! command -v git &> /dev/null; then
    apt-get update -qq
    apt-get install -y -qq git
fi
"@
}

# Step 5: Clone HomeLab repository
Step "Cloning HomeLab repository from GitHub" {
    wsl -d $WSL_DISTRO_NAME -- bash -c @"
if [ -d '$INSTALL_DIR' ]; then
    echo 'Directory $INSTALL_DIR already exists. Updating...'
    cd '$INSTALL_DIR'
    git pull
else
    echo 'Cloning repository...'
    git clone '$GITHUB_REPO' '$INSTALL_DIR'
fi
"@
}

# Step 6: Execute Linux bootstrap script
Step "Executing Linux bootstrap script" {
    # Check if bootstrap script exists
    $bootstrapScriptPath = "$INSTALL_DIR/boostrap/linux/bootstrap.sh"
    
    $scriptExists = wsl -d $WSL_DISTRO_NAME -- bash -c "test -f '$bootstrapScriptPath' && echo 'exists' || echo 'missing'"
    
    if ($scriptExists -match "missing") {
        Write-Host "⚠️  Bootstrap script not found at $bootstrapScriptPath" -ForegroundColor Yellow
        Write-Host "Creating a default bootstrap script..." -ForegroundColor Yellow
        
        wsl -d $WSL_DISTRO_NAME -- bash -c @"
mkdir -p '$INSTALL_DIR/boostrap/linux'
cat > '$bootstrapScriptPath' << 'EOFSCRIPT'
#!/bin/bash
set -e

echo '🚀 HomeLab Linux Bootstrap'
echo '==========================='

# Install Terraform
echo 'Installing Terraform...'
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo 'deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com \$(lsb_release -cs) main' | tee /etc/apt/sources.list.d/hashicorp.list
apt-get update -qq
apt-get install -y -qq terraform

# Install Ansible
echo 'Installing Ansible...'
apt-get install -y -qq ansible

echo '✅ Linux bootstrap complete!'
echo ''
echo 'Terraform and Ansible are now installed.'
echo 'Next: Run terraform commands in: $INSTALL_DIR/k8s-infra/terraform'
EOFSCRIPT

chmod +x '$bootstrapScriptPath'
"@
    }
    
    # Execute the bootstrap script
    wsl -d $WSL_DISTRO_NAME -- bash -c "cd '$INSTALL_DIR' && bash '$bootstrapScriptPath'"
}

# Final message
Write-Host "`n🎉 Bootstrap Complete!" -ForegroundColor Green
Write-Host "================================" -ForegroundColor Green
Write-Host "WSL Distribution: $WSL_DISTRO_NAME" -ForegroundColor Cyan
Write-Host "HomeLab Location: $INSTALL_DIR" -ForegroundColor Cyan
Write-Host ""
Write-Host "To access your WSL instance:" -ForegroundColor Yellow
Write-Host "  wsl -d $WSL_DISTRO_NAME" -ForegroundColor White
Write-Host ""
Write-Host "To access HomeLab directory:" -ForegroundColor Yellow
Write-Host "  wsl -d $WSL_DISTRO_NAME -- bash -c 'cd $INSTALL_DIR && bash'" -ForegroundColor White
