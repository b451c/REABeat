# REABeat — Installation Guide

## Quick Install

### macOS / Linux
Open Terminal, paste, press Enter:
```bash
curl -sSL https://raw.githubusercontent.com/b451c/REABeat/main/install.sh | bash
```

### Windows
Open PowerShell, paste, press Enter:
```powershell
irm https://raw.githubusercontent.com/b451c/REABeat/main/install.ps1 | iex
```

Both scripts will: install uv (if needed) → download REABeat → install Python dependencies → copy scripts to REAPER.

---

## Manual Install (all platforms)

### Step 1: Install uv (Python package manager)

**macOS / Linux:**
```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

**Windows (PowerShell):**
```powershell
irm https://astral.sh/uv/install.ps1 | iex
```

### Step 2: Download REABeat

**macOS / Linux:**
```bash
cd ~/Documents
git clone https://github.com/b451c/REABeat.git
cd REABeat
```

**Windows:**
```powershell
cd $env:USERPROFILE\Documents
git clone https://github.com/b451c/REABeat.git
cd REABeat
```

No git? Download ZIP: https://github.com/b451c/REABeat/archive/refs/heads/main.zip

### Step 3: Install Python dependencies

```bash
uv sync
```
Downloads Python, PyTorch, beat-this (~800MB, one-time).

Verify:
```bash
uv run python -m reabeat check
```
Expected: `OK: beat-this ready`

### Step 4: Install REAPER dependencies

Open REAPER:
1. **Extensions > ReaPack > Import repositories**
2. Paste URL, click OK:
   ```
   https://github.com/mavriq-dev/public-reascripts/raw/master/index.xml
   ```
3. **Extensions > ReaPack > Browse packages**
4. Install these two:
   - **ReaImGui** (required)
   - **mavriq-lua-sockets** (required)
5. Restart REAPER

Recommended: install [SWS Extension](https://www.sws-extension.org/) (enables Support menu links).

### Step 5: Add script to REAPER

1. **Actions > Show action list**
2. **New action... > Load ReaScript...**
3. Select `reabeat.lua`:
   - **Auto-installer path:**
     - macOS: `~/Library/Application Support/REAPER/Scripts/REABeat/reabeat.lua`
     - Windows: `%APPDATA%\REAPER\Scripts\REABeat\reabeat.lua`
     - Linux: `~/.config/REAPER/Scripts/REABeat/reabeat.lua`
   - **Manual install path:**
     - macOS/Linux: `~/Documents/REABeat/scripts/reaper/reabeat.lua`
     - Windows: `Documents\REABeat\scripts\reaper\reabeat.lua`
4. (Optional) Assign a keyboard shortcut

### Step 6: Use

1. Select an audio item on your timeline
2. Run REABeat from Actions menu
3. Click **Detect Beats** (~2-3 seconds)
4. Choose action:
   - **Insert Tempo Map** — align REAPER grid to audio
   - **Insert Stretch Markers** — for timing quantization
   - **Match Tempo** — adjust item to project BPM or custom target
5. Click **Apply** (Ctrl+Z to undo)

Backend launches automatically. Shuts down after 5 min idle.

---

## Troubleshooting

### "Starting..." hangs (backend won't start)
```bash
cd ~/Documents/REABeat   # or wherever you installed
uv run python -m reabeat check
```
- `OK: beat-this ready` → backend works, issue is REAPER connection. Try: close REABeat, restart REAPER.
- Error message → follow instructions in the error.

### "beat-this not installed"
```bash
cd ~/Documents/REABeat
uv sync
```

### Port 9877 already in use
**macOS / Linux:**
```bash
kill $(lsof -ti:9877)
```
**Windows:**
```powershell
netstat -ano | findstr :9877
taskkill /PID <PID_NUMBER> /F
```

### ReaImGui missing
Extensions > ReaPack > Browse packages > search "ReaImGui" > Install > Restart REAPER

### mavriq-lua-sockets missing
Extensions > ReaPack > Import repositories > paste URL above > Browse > search "mavriq-lua-sockets" > Install

### Wrong BPM detected
beat-this works best with clear rhythmic content. Ambient, classical, or heavily rubato recordings may produce less accurate results.

### Server log (for bug reports)
- **macOS / Linux:** `/tmp/reabeat_server.log`
- **Windows:** `%TEMP%\reabeat_server.log`
