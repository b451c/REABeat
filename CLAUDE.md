# ReaBeat - Agent Harness

Neural beat detection and tempo mapping for REAPER. Free, open-source community tool.
Part of the reamix.me ecosystem (ReaBeat = free, reamix.me = commercial).

## Architecture

```
REAPER (Lua UI)  <--TCP:9877-->  Python Backend (auto-launched)
scripts/reaper/                   src/reabeat/
```

**Lua frontend** (6 files): UI, actions, socket, server launcher, theme.
**Python backend** (4 files): beat detector (beat-this only), TCP server, CLI, config.

## Key Files

| Purpose | File |
|---------|------|
| Entry point (UI) | `scripts/reaper/reabeat.lua` |
| UI drawing | `scripts/reaper/reabeat_ui.lua` |
| REAPER API actions | `scripts/reaper/reabeat_actions.lua` |
| Socket client | `scripts/reaper/reabeat_socket.lua` |
| Server launcher | `scripts/reaper/reabeat_server.lua` |
| Theme | `scripts/reaper/reabeat_theme.lua` |
| Beat detection | `src/reabeat/detector.py` |
| TCP server | `src/reabeat/server.py` |
| CLI | `src/reabeat/cli.py` |
| Config | `src/reabeat/config.py` |

## Three Action Modes

1. **Match Tempo** - adjust playrate to target BPM (pitch preserved, elastique), auto-align first downbeat to bar - DEFAULT
2. **Insert Tempo Map** - sync REAPER's grid to audio without modifying the item. Three sub-modes: Constant (single BPM), Variable - bars (per-downbeat), Variable - beats (per-beat). Includes octave correction and BPM filtering
3. **Insert Stretch Markers** - every beat or downbeats only, with stretch quality mode (Balanced/Transient/Tonal), optional "Quantize to grid" checkbox (snaps to REAPER's project grid via TimeMap2 per-bar)

## Key Technical Details

### beat-this Integration
- **Model**: CPJKU, ISMIR 2024 (state-of-the-art, best published F1 scores)
- **Frame rate**: 50fps (20ms temporal resolution)
- **Output**: beat positions + downbeat positions (two separate model heads)
- **Mode**: dbn=False (no Dynamic Bayesian Network — better F1 on varied music)
- **Downbeats**: we use beat-this neural downbeats directly (not naive every-4th-beat)

### Tempo Calculation
- **Phase-aware regression**: circular mean for optimal phase + linear regression on beat grid (based on CPJKU/beat_this#13)
- **Octave correction**: 78-185 BPM range (optimized for modern music: captures 140 BPM trap, filters 200+ artifacts)
- **Fallback**: filtered mean when regression fails (r² < 0.99)

### Stretch Marker Quantization
- **"Quantize to grid" snaps to REAPER's project grid** via TimeMap2 per-bar (no cumulative drift for constant tempo)
- **pos/srcpos separation**: pos = target position (where beat should PLAY), srcpos = source position (where audio IS). Enables correct behavior with D_PLAYRATE != 1.0
- **Smart threshold**: corrections limited to half a beat interval (prevents snapping to wrong grid beat)

### Downbeat Cleaning
- **After beat-this detection**: neural downbeats are cleaned — removes erroneous extras (<60% expected bar), fills gaps (>160% expected bar)
- **Reference**: uses detected BPM or median interval, whichever is more reliable
- **Improves**: tempo map accuracy, bar count, downbeat-only stretch markers

### Onset Refinement
- **After beat-this detection**: each beat position snapped to nearest audio transient via librosa onset detection
- **Precision**: ~0.05ms (sample-level) vs ~20ms (beat-this frame-level)
- **Window**: +/-30ms search around each beat-this position

### GPU Acceleration
- **Device priority**: CUDA > CPU (auto-detected at runtime)
- **Installer**: detects nvidia-smi, installs CUDA PyTorch from cu124 index (~2.5GB)
- **Skip if installed**: checks `torch.cuda.is_available()` before re-downloading

### Windows Server Launch
- **Uses wscript** to create a persistent hidden console (not start /B)
- **Why**: start /B shares parent's transient console; when os.execute() returns, console is destroyed, killing uv.exe before Python starts (CTRL_CLOSE_EVENT → forrtl error 200)

### Installer
- **No git required** - downloads ZIP archive when git is not available
- **ZIP update preserves .venv** - no 800MB re-download on update
- **Detects ZIP vs git installs** - checks for .git dir before attempting git pull
- **beat-this via archive URL** - no git needed for uv sync
- **CUDA auto-install** - detects NVIDIA GPU, installs CUDA PyTorch, skips if already present
- **Update = re-run installer** - same command for install and update

### Port Check
- **Uses LuaSocket with shared mavriq-lua-sockets paths** (same as reabeat_socket.lua)
- **No os.execute fallback** - avoids visible console windows on Windows
- **Why**: os.execute(netstat) in REAPER defer loop (~30ms) created multiplying console windows

### Editable BPM
- User can override detected tempo by clicking the BPM value
- `state.detected_tempo_original` stores detection result for "(was X)" display
- Only affects Match Tempo (rate calculation)
- Beat/downbeat positions are absolute seconds, NOT derived from tempo
- Covers Hipox's feature requests (filename analysis, pre-analysis input, multiple results) - simpler approach, works for all edge cases

### UI
- Version number displayed in header ("ReaBeat v1.3.1")
- Warning dialog when "Quantize to grid" is used with mismatched project tempo (>10% diff)

## Multi-Item Cache

Detection results cached per item GUID. Switching items preserves previous results.
Shows "(cached)" in status. Cache clears on script exit.

## Running

```bash
uv run python -m reabeat serve              # Start server
uv run python -m reabeat detect song.wav    # CLI detection
uv run python -m reabeat check              # Verify backend
uv run pytest tests/ -q                     # Run tests (36)
```

## Critical Rules

1. **Port 9877** (not 9876 - that's reamix.me/RemixTool)
2. **beat-this is the ONLY backend** - no silent fallbacks, clear errors instead
3. **All REAPER API actions wrapped in Undo blocks** - Ctrl+Z always works
4. **Warn before destructive actions** - dialog before overwriting markers
5. **Cross-platform** - OS detection in server launcher (macOS/Windows/Linux)
6. **Branding: "ReaBeat"** - follows REAPER convention (ReaPack, ReaImGui)
7. **No code from external scripts** - Hipox offered his quantize script, we built our own from REAPER API
8. **Never break tests** - 36 tests must pass before pushing
9. **Windows launch** - use wscript for hidden persistent console; never use start /B (transient console kills child processes)
10. **Beat positions are absolute seconds** - not derived from tempo. Changing tempo does NOT affect beat/downbeat/stretch marker positions

## GitHub

- **Repo**: https://github.com/b451c/ReaBeat
- **Current version**: v1.3.1
- **Forum thread**: https://forum.cockos.com/showthread.php?t=308240
- **Support**: Ko-fi, Buy Me a Coffee, PayPal (links in UI Support menu)
