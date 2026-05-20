# ReaBeat Roadmap

Tracking deferred fixes and feature requests by user/source. Anything actionable lives here so it doesn't fall out of memory between sessions.

Updated: 2026-05-20

---

## v2.0.3 candidates - UX polish (forum feedback)

### Daodan #4 - Middle-mouse pan + working scrollbar
**Source:** Daodan post #2 (forum t=308368)
**Effort:** ~2h
**Risk:** LOW
**Status:** Deferred from v2.0.2

Pan via middle-mouse drag (standard DAW behaviour) and make the existing scroll thumb at the bottom of the waveform clickable/draggable.

- `WaveformView.cpp` - add `mouseDown` / `mouseDrag` handling for `e.mods.isMiddleButtonDown()`
- Detect click on scrollbar Y region (bottom 4-6 px), allow drag to scrub view position
- Watch for trackpad emulation differences between macOS and Windows

### Daodan #5 - Item persistence after deselect
**Source:** Daodan post #2
**Effort:** ~30 min + careful pointer-safety testing
**Risk:** MEDIUM (cached MediaItem* can be deleted by user)
**Status:** Deferred from v2.0.2

Keep the last selected item visible in `updateSelectedItem` when count drops to 0, so users don't lose their detection state by clicking empty timeline.

- `MainComponent.cpp:869-882` - on count<=0, set sourceLabel to "<name> (deselected)" instead of full reset
- Before any Apply path, call `ValidatePtr2(nullptr, currentItem_.item, "MediaItem*")` and bail out if invalid
- Mark detected_ as "stale" (different colour) when deselected, refresh on next select

### Daodan #9 + notabot - Manual time signature dropdown
**Source:** Daodan post #2, notabot post #43 (6/8 misdetected as 4/4)
**Effort:** ~2-3h
**Risk:** MEDIUM (algorithm-touching)
**Status:** Deferred from v2.0.2

Dropdown "Time signature: Auto / 2/4 / 3/4 / 4/4 / 6/8 / 9/8 / 12/8" that overrides `detection_.timeSigNum` and `timeSigDenom`. When user changes it after detection, recompute downbeats from the new meter.

- `MainComponent` - add `juce::ComboBox timeSigCombo`
- On change: re-run `DownbeatCleaner::clean` with new num, repaint waveform
- For compound meters (6/8, 9/8, 12/8) treat each "main" beat as group of 3 eighth notes
- Persist user override per-item alongside cache

---

## v2.0.3 - Detection robustness

### Sliding-window BPM for variable-tempo material
**Source:** Alex (90-min symphony)
**Effort:** Large (1-2 days)
**Risk:** HIGH

Current `TempoEstimator` returns a single BPM for the whole detection. For Beethoven-length classical or any score with tempo changes this is meaningless. Compute BPM in sliding windows (e.g. 30 s) and let the user pick "constant" vs "variable" output.

- New `TempoEstimator::computeVariable(beats, windowSec)` returning `vector<{time, bpm}>`
- "Insert Tempo Map" - Variable mode already exists per-beat; add windowed mid-grain mode
- UI: small line plot under BPM label showing tempo curve

### OnsetRefinement memory fix instead of skip
**Source:** Alex
**Effort:** Medium
**Risk:** MEDIUM

Currently we skip refinement past 10 minutes (saves the 3.8 GB magnitudes matrix). Better: stream the spectral flux frame-by-frame so only the running window is in RAM.

- `OnsetRefinement.cpp` - rewrite `detectOnsets` to keep only `kAdaptiveWindow` (7) frames + previous magnitudes for diff
- Removes the matrix allocation entirely
- Should restore sample-level precision on long files

---

## Open user issues (no fix yet)

### reaperfreaker - Debian Trixie not loading
**Source:** Forum post #6
**Status:** Awaiting diagnostics

Need from user:
- `ldd ~/.config/REAPER/UserPlugins/reaper_reabeat-x86_64.so`
- `REAPER --loglevel=verbose 2>&1 | grep -i reabeat` (if REAPER supports a verbose flag)
- `dmesg | tail -20` after attempting to load

Candidate causes:
- glibc/libstdc++ ABI: we build on Ubuntu 22.04 (glibc 2.35) - Debian Trixie has 2.41, should be forward-compatible
- Wayland-only session: REAPER under native Wayland can't open X11 socket, our XBridge fails
- Missing system libs: `libfreetype6`, `libcurl4`, `mesa-utils`

Mitigations to consider:
- Build on Ubuntu 20.04 instead of 22.04 (older glibc baseline)
- `-static-libstdc++ -static-libgcc` link flags

---

## Long-term ideas

- C++ unit tests (none exist today)
- Cancel button during detection (reuse "Detect Beats" as "Cancel" while detecting)
- Free `mono` buffer after resample (release ~900 MB on long files)
- Compound meter heuristic in `TimeSigDetector` (BPM > 130 && bar=2 → 6/8 hint)
- Forum: post v2.0.2 announcement, reply per user thread
