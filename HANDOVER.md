# Handover Report - 2026-04-13

## Session Summary
**Focus**: Built native C++ REAPER extension (Phase 1-5 of 6), fixed installers
**Branch**: main (Lua/Python), native/ has its own git repo
**Version**: v1.3.1 (Lua/Python), v2.0.0-dev (native)
**Tests**: 36 passing (Lua/Python), native needs testing with real model
**Repo**: https://github.com/b451c/ReaBeat
**Forum**: https://forum.cockos.com/showthread.php?t=308240

## What Was Done This Session

### Native C++ Extension (native/ directory - separate git repo)

Built a native REAPER extension from scratch. 26 source files, 2,946 lines C++.
Uses JUCE for UI, ONNX Runtime for inference, PocketFFT for spectrograms.
Architecture: ReaJoice pattern (timer-based JUCE message pump in REAPER extension).

**Phase 1: Skeleton** - CMake + JUCE + REAPER entry point
- ReaperPluginEntry, REAPERAPI_LoadAPI, timer pump, command registration
- PluginWindow (DocumentWindow toggle), MainComponent placeholder
- Builds and loads in REAPER (confirmed working with screenshot)

**Phase 2: Inference Core** - beat_this_cpp ported with critical fixes
- MelSpectrogram: PocketFFT, Slaney mel scale, cached filterbank
- InferenceProcessor: ONNX Runtime chunked inference, fixed split_piece
- Postprocessor: FIXED separate max_pool for beat/downbeat (original had cross-boundary bug)
- TempoEstimator: phase-aware BPM (circular mean + linear regression + octave correction)
- DownbeatCleaner: remove extras (<0.6x), fill gaps (>1.6x)
- TimeSigDetector: count beats between downbeats
- BeatInterpolator: NEW - fill missing beats in quiet sections (squibs' 0.51x fix)

**Phase 3: REAPER Actions** - direct port from Lua
- insertStretchMarkers: pos/srcpos separation, TimeMap2 quantization
- insertTempoMap: constant/variable-bars/variable-beats
- matchTempo: playrate + pitch preserve + auto-align to bar

**Phase 4: Full UI + Pipeline** - end-to-end
- BeatDetector: high-level API, JUCE audio loading/resampling, background thread
- MainComponent: complete UI with all controls, 3 action modes, detection cache
- Dark theme with gold accent matching Lua version

**Phase 5: Accuracy Improvements + Fixes**
- OnsetRefinement: C++ spectral flux onset detection (replaces librosa)
- FilenameParser: regex BPM/meter extraction from filenames (Hipox's request)
- FIXED MelSpectrogram normalization (was incorrect vs PyTorch training pipeline)
- FIXED thread safety (SafePointer in detection thread)
- FIXED dangling pointer validation (ValidatePtr2 on cached items)

### Installer Fix (main repo)
- Both install.sh and install.ps1 now prompt for REAPER path when not found
- Addresses reaperfreaker's Linux custom path issue (forum post #35)

### Forum
- New post #35 from reaperfreaker: macOS Mojave (PyTorch limit) + Linux custom path (fixed)
- squibs posted positive feedback on v1.3.1 (close to perfect, some edge cases)
- Need to reply to reaperfreaker (saved in memory)

## What's Not Done (Phase 6)

- ModelManager: download ONNX model on first use (~79MB)
- GitHub Actions CI: macOS + Windows + Linux builds
- ReaPack index.xml packaging
- ort-builder minimal static ONNX Runtime build for release
- CoreML EP on Apple Silicon (optional acceleration)
- Persistent cache via SetProjExtState/GetProjExtState
- End-to-end testing with real ONNX model on real audio

## Files (native/)

| File | Purpose |
|------|---------|
| CMakeLists.txt | Build system (C++20, JUCE, WDL, ONNX RT) |
| src/main.cpp | REAPER extension entry point |
| src/PluginWindow.h | JUCE DocumentWindow |
| src/MainComponent.h/cpp | Full UI (3 action modes, detection, cache) |
| src/BeatDetector.h/cpp | High-level detection API |
| src/MelSpectrogram.h/cpp | Mel spectrogram (PocketFFT) |
| src/InferenceProcessor.h/cpp | ONNX chunked inference |
| src/Postprocessor.h/cpp | Peak detection + dedup |
| src/TempoEstimator.h/cpp | Phase-aware BPM |
| src/DownbeatCleaner.h/cpp | Clean neural downbeats |
| src/TimeSigDetector.h/cpp | Time sig from downbeats |
| src/BeatInterpolator.h/cpp | Fill missing beats (NEW) |
| src/OnsetRefinement.h/cpp | Spectral flux onset detection |
| src/FilenameParser.h/cpp | BPM/meter from filename |
| src/ReaperActions.h/cpp | REAPER API actions |
| RESEARCH.md | Deep research document |

## What Next Agent Should Do

### Priority 1: Test with real model
- Download beat_this_final0.onnx to ~/.reabeat/models/
- Convert from PyTorch checkpoint or find pre-converted ONNX
- Test detection on real audio in REAPER
- Compare results vs Python version (BPM within 0.5, beats within 2)
- Test squibs' track (Joe Jackson) - verify no 0.51x ratios

### Priority 2: ModelManager (Phase 6)
- Implement auto-download on first use
- Host model on GitHub Releases
- SHA-256 verification
- Progress bar during download

### Priority 3: Cross-platform build + distribution
- GitHub Actions CI (macOS universal, Windows x64, Linux x64)
- ReaPack index.xml
- ort-builder minimal static build for release

### Priority 4: Forum reply to reaperfreaker
- Mojave: PyTorch platform limit, suggest upgrade
- Linux path: fixed in installer, re-run to get prompt
- See memory file project_forum_reply_pending.md

### Keep maintained
- Lua/Python v1.3.1 stays as-is (not affected by native work)
- 36 Python tests must still pass
- native/ is a separate git repo, doesn't affect main
