# Changelog

## v1.2.0 (2026-04-09)

Precision and quality update based on deep analysis of beat-this internals and community feedback (dukati, Bassman002, JetRed).

### Precision Improvements
- **Improved tempo accuracy** — hybrid span/mean calculation instead of median. Eliminates systematic error from beat-this 20ms frame quantization (e.g. 100 BPM → 101.8 BPM for a true 102 BPM track)
- **Neural downbeats** — uses beat-this's dedicated downbeat detection head instead of naive every-4th-beat. Correctly identifies bar boundaries even when audio doesn't start on beat 1
- **Fixed stretch marker quantization** — uses TimeMap2 instead of BR_GetClosestGridDivision. Markers now snap to nearest beat regardless of REAPER grid setting (was causing 0.52x stretch ratios)

### New Features
- **Editable BPM** — click detected tempo to override manually. Shows "(was X)" when edited. Useful when detection is close but not exact
- **Auto-align to bar** — Match Tempo automatically shifts item so first downbeat lands on nearest bar line. No more manual alignment (on by default)
- **Stretch quality mode** — choose Balanced, Transient, or Tonal algorithm for stretch markers via dropdown. Transient best for drums, Tonal for vocals/melodic

### Fixes
- **Windows server launch** — fixed nested cmd quotes that prevented server startup when scripts installed via installer (reported by Bassman002)
- **Tooltip** — corrected "madmom > librosa fallback" to accurately reflect beat-this as sole backend

### Tests
- 22 → 26 tests (quantized tempo, neural downbeats 4/4/3/4/empty)

## v1.1.0 (2026-04-09)

Feature update based on community feedback (Hipox).

### New Features
- **Match & Quantize mode** - new combo action: inserts variable tempo map first (aligns grid to audio), then inserts stretch markers quantized to that grid. Result: minimal stretching (0.99x-1.01x) instead of drastic corrections.
- **Snap first beat to bar** - tempo map automatically aligns first detected beat to nearest REAPER grid division (uses BR_GetClosestGridDivision with SnapToGrid fallback). No more floating tempo maps at random positions.
- **Multi-item detection cache** - switching between items preserves detection results. Come back to a previously analyzed item and beats/tempo/downbeats are instantly restored (shows "cached" in status). Cache clears on script exit.

### UI Improvements
- **Reordered actions** from simplest to most advanced: Match Tempo > Insert Tempo Map > Insert Stretch Markers > Match & Quantize
- **Match Tempo is now the default** action (most common use case)
- Each mode has clear tooltips explaining what it does and when to use it

## v1.0.1 (2026-04-09)

Hotfix for Windows.

### Fixes
- **SCRIPT_DIR detection** - pattern now matches Windows backslashes (reported by Hipox)
- **Project root discovery** - searches `~/ReaBeat/` and `~/Documents/ReaBeat/` when scripts are installed separately from repo
- **Branding** - unified naming to ReaBeat everywhere (ReaPack convention)

## v1.0.0 (2026-04-09)

Initial release.

### Features
- Beat detection using **beat-this** (CPJKU, ISMIR 2024) — state-of-the-art neural model, ~2-3s per song
- **Insert Tempo Map** — constant BPM or variable per-bar tempo markers
- **Insert Stretch Markers** — at every beat or downbeats only
- **Match Tempo** — adjust item playrate to project BPM or custom target, pitch preserved (elastique)
- Time signature estimation (4/4, 3/4)
- Confidence score based on tempo consistency
- Warns before overwriting existing tempo markers or stretch markers
- Full undo support (Ctrl+Z) for all actions

### UI
- REAPER-native dark theme with warm gold accent
- Three action modes: Tempo Map, Stretch Markers, Match Tempo
- "Match to project" one-click button reads current session BPM
- Custom BPM input field with live preview (shows rate change)
- Support menu with Ko-fi, Buy Me a Coffee, PayPal links
- Connection status with elapsed time counter during startup
- Clear error messages: missing deps, silent audio, MIDI items, file not found
- Compact, focused interface — no unnecessary controls

### Architecture
- Python backend with auto-launch and 5-minute idle timeout
- TCP localhost:9877, line-delimited JSON protocol
- Cross-platform: macOS, Windows, Linux
- 22 automated tests

### Backend
- beat-this as sole detection engine — no silent fallbacks to lower quality
- GPU auto-detection with automatic CPU fallback on CUDA failure
- Silent audio detection (RMS < 0.001 → clear error)
- MIDI item rejection with helpful message
- Audio too short (<2s) detection with clear error
