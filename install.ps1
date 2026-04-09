# ReaBeat Installer for Windows
# Run: powershell -ExecutionPolicy Bypass -File install.ps1
# Or:  irm https://raw.githubusercontent.com/b451c/ReaBeat/main/install.ps1 | iex

$REPO_URL = "https://github.com/b451c/ReaBeat.git"
$INSTALL_DIR = "$env:USERPROFILE\ReaBeat"
$REAPER_SCRIPTS = "$env:APPDATA\REAPER\Scripts"

function Abort($msg) {
    Write-Host ""
    Write-Host "  ERROR: $msg" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Press any key to exit..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

Write-Host ""
Write-Host "  +======================================+" -ForegroundColor Cyan
Write-Host "  |     ReaBeat Installer                |" -ForegroundColor Cyan
Write-Host "  |     Neural beat detection for REAPER |" -ForegroundColor Cyan
Write-Host "  +======================================+" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Platform: Windows"

# Step 1: Install uv if needed
Write-Host ""
Write-Host "  [1/4] Checking uv..." -ForegroundColor Yellow
$uvPath = Get-Command uv -ErrorAction SilentlyContinue
if ($uvPath) {
    Write-Host "         uv found: $($uvPath.Source)"
} else {
    Write-Host "         Installing uv (Python package manager)..."
    try {
        $uvInstaller = Join-Path $env:TEMP "uv_install.ps1"
        Invoke-WebRequest -Uri "https://astral.sh/uv/install.ps1" -OutFile $uvInstaller -UseBasicParsing
        & powershell -ExecutionPolicy Bypass -File $uvInstaller
        Remove-Item $uvInstaller -ErrorAction SilentlyContinue
    } catch {
        Abort "Failed to download/run uv installer: $_`n         Install manually: https://docs.astral.sh/uv/"
    }
    # Refresh PATH (uv installs to ~/.local/bin or ~/.cargo/bin)
    $env:PATH = "$env:USERPROFILE\.local\bin;$env:USERPROFILE\.cargo\bin;$env:PATH"
    $uvPath = Get-Command uv -ErrorAction SilentlyContinue
    if (-not $uvPath) {
        Abort "uv installed but not found in PATH.`n         Close this window, open a new PowerShell, and run the installer again."
    }
    Write-Host "         uv installed: $($uvPath.Source)"
}

# Step 2: Clone or update repo
Write-Host ""
Write-Host "  [2/4] Getting ReaBeat..." -ForegroundColor Yellow
$gitPath = Get-Command git -ErrorAction SilentlyContinue
if (-not $gitPath) {
    Abort "git is not installed.`n         Install from: https://git-scm.com/download/win`n         Or download ZIP: https://github.com/b451c/ReaBeat/archive/refs/heads/main.zip"
}
if (Test-Path $INSTALL_DIR) {
    Write-Host "         Updating existing installation..."
    Push-Location $INSTALL_DIR
    git pull --ff-only
    if ($LASTEXITCODE -ne 0) {
        Pop-Location
        Abort "git pull failed. Try deleting $INSTALL_DIR and running installer again."
    }
    Pop-Location
} else {
    Write-Host "         Downloading to $INSTALL_DIR..."
    git clone $REPO_URL $INSTALL_DIR
    if ($LASTEXITCODE -ne 0) {
        Abort "git clone failed. Check your internet connection."
    }
}
Push-Location $INSTALL_DIR

# Step 3: Install Python dependencies
Write-Host ""
Write-Host "  [3/4] Installing Python dependencies (torch + beat-this)..." -ForegroundColor Yellow
Write-Host "         This may take a few minutes on first install (~800MB)."
Write-Host ""
uv sync
if ($LASTEXITCODE -ne 0) {
    Pop-Location
    Abort "uv sync failed. Check the output above for details."
}

Write-Host ""
Write-Host "         Verifying backend..."
uv run python -m reabeat check
if ($LASTEXITCODE -ne 0) {
    Pop-Location
    Abort "Backend verification failed. Check the output above for details."
}
Write-Host ""

# Step 4: Copy Lua scripts to REAPER
Write-Host ""
Write-Host "  [4/4] Installing REAPER scripts..." -ForegroundColor Yellow
$reaperDir = "$REAPER_SCRIPTS\ReaBeat"
if (-not (Test-Path $reaperDir)) {
    New-Item -ItemType Directory -Path $reaperDir -Force | Out-Null
}
Copy-Item "$INSTALL_DIR\scripts\reaper\*.lua" -Destination $reaperDir -Force
Write-Host "         Copied to: $reaperDir"

Pop-Location

Write-Host ""
Write-Host "  +======================================================+" -ForegroundColor Green
Write-Host "  |  Installation complete!                                |" -ForegroundColor Green
Write-Host "  |                                                        |" -ForegroundColor Green
Write-Host "  |  Next steps in REAPER:                                 |" -ForegroundColor Green
Write-Host "  |  1. Install ReaImGui & mavriq-lua-sockets via ReaPack  |" -ForegroundColor Green
Write-Host "  |  2. Actions > New action > Load ReaScript              |" -ForegroundColor Green
Write-Host "  |     Select: $reaperDir\reabeat.lua" -ForegroundColor Green
Write-Host "  |  3. Select an audio item and run ReaBeat               |" -ForegroundColor Green
Write-Host "  |                                                        |" -ForegroundColor Green
Write-Host "  |  ReaPack repo for sockets:                             |" -ForegroundColor Green
Write-Host "  |  https://github.com/mavriq-dev/public-reascripts/      |" -ForegroundColor Green
Write-Host "  |         raw/master/index.xml                           |" -ForegroundColor Green
Write-Host "  +======================================================+" -ForegroundColor Green
Write-Host ""
Write-Host "  Press any key to exit..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
