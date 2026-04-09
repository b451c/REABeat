# REABeat — Agent Harness

Neural beat detection and tempo mapping for REAPER. Open-source community tool.

## Architecture

```
REAPER (Lua UI)  <--TCP:9877-->  Python Backend (auto-launched)
scripts/reaper/                   src/reabeat/
```

**Lua frontend** (7 files): UI, actions (tempo map, stretch markers, match tempo), socket, server launcher, theme.
**Python backend** (4 files): beat detector (beat-this only), TCP server, CLI, config.

## Key Files

| Purpose | File |
|---------|------|
| Entry point (UI) | `scripts/reaper/reabeat.lua` |
| UI drawing | `scripts/reaper/reabeat_ui.lua` |
| REAPER API actions | `scripts/reaper/reabeat_actions.lua` |
| Beat detection | `src/reabeat/detector.py` |
| TCP server | `src/reabeat/server.py` |
| CLI | `src/reabeat/cli.py` |

## Three Action Modes

1. **Insert Tempo Map** — constant or variable per-bar BPM markers
2. **Insert Stretch Markers** — every beat or downbeats only
3. **Match Tempo** — adjust playrate to target BPM (pitch preserved, elastique)

## Running

```bash
uv run python -m reabeat serve              # Start server
uv run python -m reabeat detect song.wav    # CLI detection
uv run python -m reabeat check              # Verify backend
uv run pytest tests/ -q                     # Run tests (22)
```

## Critical Rules

1. Port 9877 (not 9876 — that's REAmix)
2. beat-this is the ONLY backend — no silent fallbacks
3. All REAPER API actions wrapped in Undo blocks
4. Backend auto-launches with 5-min idle timeout
5. Cross-platform: macOS, Windows, Linux (OS detection in server launcher)
6. All files lean — this is a focused tool, not a framework
