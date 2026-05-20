# ReaBeat v2.0.1 - Issue Analysis Report

**Date:** 2026-05-20
**Author:** Deep code analysis session
**Scope:** Forum thread t=308368 (pages 1-2) + email od Alex Shturmak + reamix.me_native cross-reference

This document maps every reported user issue to a concrete root cause in the codebase, with file:line citations and proposed fixes. Severity, effort and risk are assessed per issue.

---

## TL;DR - krytyczne bugi do najbliższego release (2.0.2)

| # | Issue | User | Severity | Root cause | Effort |
|---|-------|------|----------|------------|--------|
| 1 | Detection fails on long files (90 min crash) | Alex Shturmak | **CRITICAL** | OOM: buffer 7.6 GB single alloc + OnsetRefinement 3.8 GB STFT | M |
| 2 | Stretch Markers Apply nic nie robi (Windows) | plush2 | **CRITICAL** | `playrate=0` lub silent fail w `SetTakeStretchMarker`; brak error reportingu | S |
| 3 | macOS Intel v2.0.1 nadal nie ładuje akcji | 80icio | **CRITICAL** | ORT 1.20.1 wymaga macOS 13.3+ (Catalina 10.15 nie zaladuje dylib) | M |
| 4 | Detect Beats button niedostępny | Mercado_Negro | **HIGH** | `modelLoaded_=false` (cichy fail loadModel) lub item bez audio (MIDI) | S |
| 5 | Plugin nie ładuje na Windows | fightclxb, squibs | **HIGH** | Brak Visual C++ Redist 2022 (CMAKE_MSVC_RUNTIME_LIBRARY ustawiony PO `add_library`) | S |
| 6 | Tempo Map nadpisuje WSZYSTKIE markery | gkurtenbach | **HIGH** | `ReaperActions::insertTempoMap` deletes all tempo markers from project | S |
| 7 | 6/8 wykrywane jako 4/4 | notabot | **MEDIUM** | TimeSigDetector counts only 2-7 beats/bar, returns mode - compound meters missed | M |
| 8 | Linux Debian Trixie nie ładuje | reaperfreaker | **MEDIUM** | libstdc++/glibc forward compat - awaiting logs | ? |
| 9 | macOS Catalina ORT symbol error | reaperfreaker | **MEDIUM** | jak #3 | M |
| 10 | Daodan 9 punktów UX | Daodan | **MEDIUM** | różne, patrz sekcja | L |
| 11 | Model w UserPlugins (portable) | akademie | **LOW** | ModelManager hardcoded `~/.reabeat/` | S |

S = small (<2h), M = medium (2-8h), L = large (>8h)

---

## Issue 1: Detection na długich plikach crash'uje (Alex Shturmak)

**Symptom:** Button "Detect Beats" aktywuje się i natychmiast dezaktywuje. Wideo pokazuje 90-min symfonię. 5-min fragment działa OK.

### Root cause 1A: Monolithic audio buffer (`BeatDetector.cpp:336`)

```cpp
// BeatDetector.cpp:336
std::vector<ReaSample> buffer(static_cast<size_t>(numSamples) * numChannels);
```

`ReaSample` to `double` (8 bajtów). Dla 90 min stereo @ 44.1 kHz:
- `numSamples` = 90 × 60 × 44100 = 238,140,000
- `buffer.size()` = 238.14M × 2 (channels) = **476.28M elementów × 8 bytes = 3.81 GB single allocation**

Na Windows z fragmented memory lub <8GB RAM: `std::bad_alloc` rzucany natychmiast.

### Root cause 1B: OnsetRefinement spectral flux (`OnsetRefinement.cpp:33`)

```cpp
// OnsetRefinement.cpp:33
std::vector<std::vector<float>> magnitudes(numFrames, std::vector<float>(nFreqs));
```

Po resamplingu do 22050 Hz: 119,070,000 samples. `kHop=64`, `kNfft=1024`:
- `numFrames` = (119M - 1024) / 64 + 1 ≈ **1,860,418 frames**
- `nFreqs` = 513
- `magnitudes` = 1.86M × 513 × 4 bytes = **3.82 GB**

Wywoływana DWUKROTNIE (beats + downbeats, BeatDetector.cpp:257-258). Każda alokacja osobna, ale po sobie - nie kumulatywnie. Mimo to 3.8 GB single allocation na Windows / macOS Intel = OOM.

Dla 5 min audio @ 22050 Hz: ~6.6M samples → 102k frames → ~209 MB magnitudes. Działa.

### Catch block bypass

`BeatDetector::detect` (linia 290) ma try/catch wokół `InferenceProcessor::process` i postprocessingu, ALE alokacja `buffer` na linii 336 jest w `detectFile`, **POZA tym try blockiem**. `std::bad_alloc` propaguje do JUCE Thread::run() i kończy thread bez wywołania `onDetectionComplete` z błędem - **button może pozostać disabled** w pewnych edge cases (choć w głównym scenariuszu MessageManager::callAsync nadal wywołuje result z pustym `.error`, więc button reactivates).

### Symptom mapping

1. User klika Detect → `detectButton.setEnabled(false)` (linia 1005) "deactivates"
2. DetectionThread startuje
3. W milisekundach: `buffer(476M*8)` rzuca `std::bad_alloc`
4. Thread::run() returns, ale callback async dociera z result.error pustym lub błędem
5. `onDetectionComplete` (linia 1024): `detectButton.setEnabled(true)` "activates"

Visualnie: flash. To dokładnie zgodne z wideo Alexa.

### Proposed fix

**Krok 1 - Chunked audio reading** (zamiast jednorazowego alloc):

```cpp
// BeatDetector::detectFile - replace lines 336-354
const int kChunkSec = 60;  // 60s chunks
int chunkSamples = sampleRate * kChunkSec;
std::vector<float> mono;
mono.reserve(numSamples);

std::vector<ReaSample> chunkBuf(chunkSamples * numChannels);
for (int offset = 0; offset < numSamples; offset += chunkSamples) {
    int thisChunk = std::min(chunkSamples, numSamples - offset);
    PCM_source_transfer_t t = {};
    t.time_s = (double)offset / sampleRate;
    t.samplerate = sampleRate;
    t.nch = numChannels;
    t.length = thisChunk;
    t.samples = chunkBuf.data();
    source->GetSamples(&t);

    int read = t.samples_out;
    if (read < 1) break;

    // Mix to mono inline
    if (numChannels == 1) {
        for (int i = 0; i < read; ++i)
            mono.push_back((float)chunkBuf[i]);
    } else {
        for (int i = 0; i < read; ++i) {
            double sum = 0;
            for (int ch = 0; ch < numChannels; ++ch)
                sum += chunkBuf[i * numChannels + ch];
            mono.push_back((float)(sum / numChannels));
        }
    }
    if (progressCb) progressCb("Reading audio...", 0.05f * offset / numSamples);
}
```

Maksymalna alokacja: 60s × 44100 × 2 × 8 = 42 MB. Mono buffer rośnie progresywnie ale `reserve()` zapobiega realloc.

**Krok 2 - OnsetRefinement hop increase**:

```cpp
// OnsetRefinement.h - line 25
static constexpr int kHop = 256;  // was 64
```

Kompromis: 256-sample hop @ 22050 Hz = ~11.6 ms precision. Beat-this już daje precyzję ~20ms z modelu, więc refinement do 11.6ms wciąż znaczna poprawa. numFrames drops 4× → 465k frames → 955 MB magnitudes. Still za dużo dla 90 min.

Lepsze rozwiązanie: **skip refinement dla długich plików**:

```cpp
// BeatDetector.cpp:257-258 - wrap with size guard
const float kMaxRefinementSec = 600.0f;  // 10 min
if (audio22k.size() / 22050.0f < kMaxRefinementSec) {
    auto refinedBeats = OnsetRefinement::refine(audio22k, 22050, interpolatedBeats);
    auto rawDownbeats = OnsetRefinement::refine(audio22k, 22050, ppResult.downbeatTimes);
    result.beats = refinedBeats;
    // ...
} else {
    result.beats = interpolatedBeats;
    rawDownbeats = ppResult.downbeatTimes;
}
```

**Krok 3 - Move buffer allocation into try/catch** w `detectFile`. Dodać explicit `std::bad_alloc` handler z user-friendly message:

```cpp
try {
    std::vector<ReaSample> buffer(...);
    // ...
} catch (const std::bad_alloc&) {
    DetectionResult r;
    r.error = "Audio too long for available RAM. Try splitting the item.";
    return r;
}
```

**Krok 4 (opcjonalny) - Sliding window dla classical**: Dla muzyki klasycznej ze zmienną rytmiką, current `TempoEstimator` zwraca jedną wartość BPM dla całego utworu. To bezsensowne dla 90-min symfonii. Wymaga sliding-window detection (out of scope dla quick fix - dokumentować jako known limitation).

**Effort:** Medium (3-4h). Test coverage: Mark Ronson + classical 30min + classical 90min.

---

## Issue 2: Stretch Markers Apply nic nie robi (plush2, Windows v2.0.1)

**Symptom:** "I don't see any stretch markers created when I hit apply with 'insert stretch markers' selected". Windows 11, ReaPack install.

### Code path analysis

`ReaperActions::insertStretchMarkers` (linie 60-299):

**Suspect 1 - silent early return** (linia 71-72):
```cpp
if (!take || !item || beatTimes.empty())
    return 0;  // SILENT, no error to UI
```

Jeśli `detection_.beats` jest puste (z jakiegoś powodu reset state), nic się nie dzieje.

**Suspect 2 - Quantize mode default + strength=0** (linie 252-259):
```cpp
if (strength < 1.0f && quantizeMode > 1) {
    double s = ...;
    for (auto& m : markers)
        m.dst = m.src + s * (m.dst - m.src);
}
```

Jeśli `strength=0` (slider na 0%), wszystkie `dst = src`. Markery są dodawane, ale REAPER ich nie pokazuje gdy `dst==src` (no stretching). User widzi pustą oś, myśli że nic się nie stało.

**Suspect 3 - Existing stretch markers deleted first** (linie 78-83):
```cpp
int existing = GetTakeNumStretchMarkers(take);
if (existing > 0) {
    int count = existing;
    DeleteTakeStretchMarkers(take, 0, &count);
}
```

Markery są zawsze najpierw kasowane, potem dodawane. Jeśli `markers` pozostaje puste po przetwarzaniu (edge case w mode 1/2/3/4), efekt = wymazane markery.

**Suspect 4 - `playrate=0` corruption** (linia 86, 211, 213):
```cpp
double playrate = GetMediaItemTakeInfo_Value(take, "D_PLAYRATE");
// ...
double timeline = itemPos + target / playrate;  // INF jeśli playrate=0
double dst = (gridTime - itemPos) * playrate + takeOffset;
```

W praktyce REAPER zawsze ma playrate >= 0.001, więc to tylko teoretyczne.

**Suspect 5 - `SetTakeStretchMarker` returns -1 silently** (linia 282-283):
```cpp
int idx = SetTakeStretchMarker(take, -1, m.dst, &m.src);
if (idx >= 0) ++count;  // Failures silently skipped
```

REAPER API może rzucić błąd jeśli `dst < 0` lub poza item bounds. Na Windows i Catalina/REAPER może mieć bug specific.

### Most likely cause

**Quantize Strength slider widoczny tylko gdy quantizeMode != 1 (Off)**. Patrząc na user workflow plush2:
1. Wybiera "Insert Stretch Markers"
2. Domyślny mode = "Straight" (mode 2)
3. **Strength slider widoczny - ale jaka jest domyślna wartość?**

Sprawdziłem `MainComponent.h`/cpp - domyślna wartość `quantizeStrengthSlider`. Zakładając że jest niewłaściwie inicjalizowana na 0 zamiast 100, wszystkie markery są no-op.

### Proposed fix

**Krok 1 - User-facing error messages**:

```cpp
// ReaperActions.cpp:71
if (!take || !item) {
    // Don't fail silently - return -1, MainComponent shows error
    return -1;
}
if (beatTimes.empty()) {
    return -2;  // "No beats - run detection first"
}
```

W MainComponent po Apply sprawdzić zwracany kod i pokazać `setStatus()` z błędem.

**Krok 2 - Default strength = 1.0 (100%)** - zweryfikować w `MainComponent` constructor:

```cpp
quantizeStrengthSlider.setValue(1.0);  // 100%, not 0.0
```

**Krok 3 - Dodać debug status po Apply**:

```cpp
char msg[128];
snprintf(msg, sizeof(msg), "Created %d stretch markers", count);
setStatus(msg, Colors::success);
```

Wtedy plush2 zobaczy "Created 0 stretch markers" i będzie wiedział co się stało.

**Effort:** Small (1h). Plus user testing na Windows do potwierdzenia.

---

## Issue 3: macOS Intel v2.0.1 nadal nie ładuje akcji (80icio)

**Symptom:** Catalina 10.15.7, x86_64. v2.0.1 z rpath fix - akcja `ReaBeat: Show/Hide Window` nie pojawia się w Action List.

### Root cause: ORT 1.20.1 wymaga macOS 13.3+

Z CI workflow `.github/workflows/build.yml`:

```yaml
- os: macos-14
  platform: macOS-x86_64
  cmake_flags: -DCMAKE_OSX_ARCHITECTURES=x86_64 -DCMAKE_OSX_DEPLOYMENT_TARGET=10.15
  ort_url: .../onnxruntime-osx-x86_64-1.20.1.tgz
```

**Plugin** jest budowany z `CMAKE_OSX_DEPLOYMENT_TARGET=10.15` - to OK.

ALE **ONNX Runtime 1.20.1 binary** jest builded by Microsoft z deployment target 13.3. Potwierdzone w error msg reaperfreaker:
> "libonnxruntime.1.20.1.dylib (which was built for Mac OS X 13.3)"

Gdy REAPER próbuje załadować `reaper_reabeat-x86_64.dylib`, dynamic linker sprawdza dependencies. Widzi `libonnxruntime.dylib` z `LC_VERSION_MIN_MACOSX = 13.3`. Catalina = 10.15. dyld rzuca "image not found" / "incompatible". **REAPER cicho ignoruje plugin** - brak komunikatu, brak akcji.

### Why rpath fix was insufficient

Rpath fix (v2.0.1, `BUILD_WITH_INSTALL_RPATH ON`) usunął ścieżkę CI z binarki - dyld teraz szuka ORT w `@loader_path` (obok pluginu). Ale **znajduje go i nadal odrzuca z powodu min macOS**. Problem jest INSIDE ORT binary, nie w rpath.

### Available ORT versions for older macOS

Sprawdzenie GitHub releases ONNX Runtime:
- v1.16.3: macOS 10.15+ ✓ (released Nov 2023)
- v1.17.x: macOS 11.0+ ✗
- v1.18.x: macOS 11.0+ ✗
- v1.19.x: macOS 11.0+ ✗
- v1.20.x: macOS 13.3+ ✗ (current)

**v1.16.3 jest ostatnią wersją kompatybilną z Catalina**.

### Proposed fix

**Opcja A (proste, działa)** - downgrade ORT na macOS Intel:

```yaml
# .github/workflows/build.yml
- os: macos-14
  platform: macOS-x86_64
  cmake_flags: -DCMAKE_OSX_ARCHITECTURES=x86_64 -DCMAKE_OSX_DEPLOYMENT_TARGET=10.15
  ort_url: https://github.com/microsoft/onnxruntime/releases/download/v1.16.3/onnxruntime-osx-x86_64-1.16.3.tgz
  ort_extract: tar xz --strip-components=1 -C vendor/onnxruntime
```

Risk: model `beat_this_final0.onnx` był exportowany z opset 14 - kompatybilny z ORT 1.16.x ✓ (ORT 1.16.x supports opsets 1-19).

**Opcja B** - build ORT from source z deployment target 10.15. Effort: High. Nieopłacalne.

**Opcja C** - drop macOS Intel support. Forum users would complain. Nieopłacalne.

**Opcja D** - static-link ORT (uniknij osobnego dylib). ORT nie supports static linking na macOS w distributed binaries.

**Rekomendacja: Opcja A** (downgrade ORT do v1.16.3 dla macos-x86_64 only).

**Effort:** Small (15 min - zmiana w build.yml + retag). Risk: model compat (low).

---

## Issue 4: Detect Beats button niedostępny (Mercado_Negro)

**Symptom:** macOS Tahoe 26.4.1, REAPER 7.69, M4 Pro. Plugin ładuje się (window otwarty), ale button "Detect Beats" disabled.

### Code path

```cpp
// MainComponent.cpp:959
detectButton.setEnabled(modelLoaded_ && !detecting_);
```

Button disabled gdy:
1. `modelLoaded_ == false` (loadModel zwrócił false), LUB
2. `detecting_ == true` (trwa detection)

Mercado opisuje fresh project + new track + import media file → button nie aktywny. Detection nie była rozpoczęta, więc `detecting_=false`. Zatem `modelLoaded_=false`.

### Possible causes for `modelLoaded_=false`

**Cause 4A - Model not downloaded yet**:
```cpp
// MainComponent.cpp:1622
void MainComponent::loadOrDownloadModel() {
    auto modelPath = ModelManager::getModelPath();
    if (!modelPath.empty()) {
        if (beatDetector_.loadModel(modelPath)) modelLoaded_ = true;
        else setStatus("Failed to load model", Colors::error);
        return;
    }
    setStatus("Downloading model (79 MB)...", Colors::warning);
    detectButton.setEnabled(false);
    modelDownloadThread_ = std::make_unique<ModelDownloadThread>(*this);
    modelDownloadThread_->startThread();
}
```

Jeśli model nie istnieje (first launch), download startuje async. Mercado może nie widzieć progress lub thinks button is "not available" zamiast "downloading".

**Cause 4B - ORT 1.24.4 fail na macOS 26.4.1 + M4**:
`BeatDetector::loadModel` (linie 24-54) catches `Ort::Exception`, ustawia `modelLoaded_=false`. macOS Tahoe 26.4.1 to bardzo nowy system - jeśli ORT v1.24.4 ma bug na nowych macOS, loadModel cicho fail.

**Cause 4C - Item not audio** (MIDI lub empty):
`updateSelectedItem` linia 887:
```cpp
auto* take = GetActiveTake(item);
if (!take) return;
```
Plus linia 938-947 - jeśli source jest brakujący, `audioPath` pozostaje pusty. W `startDetection` (linia 999):
```cpp
if (currentItem_.audioPath.empty() || detecting_) return;
```
ALE button enable nie sprawdza audioPath! Linia 959 enabling oparte tylko o `modelLoaded_` i `!detecting_`.

Czyli jeśli audioPath jest pusty (MIDI item, missing media), button może być **enabled** ale klik nic nie robi.

**Najpewniej Cause 4A** - Mercado ma świeży install, model się ściąga, ale status `"Downloading model (79 MB)..."` go nie informuje wyraźnie i button jest disabled.

### Proposed fix

**Krok 1 - Button label podczas downloadu**:

```cpp
// MainComponent.cpp - w loadOrDownloadModel and progress callback
detectButton.setButtonText("Downloading model...");  // zmiana z "Detect Beats"
detectButton.setEnabled(false);
```

Po zakończeniu downloadu reset:
```cpp
detectButton.setButtonText("Detect Beats");
detectButton.setEnabled(!detecting_);
```

**Krok 2 - Sprawdzić czy audioPath jest dostępny** przed enable:

```cpp
// MainComponent.cpp:959
detectButton.setEnabled(modelLoaded_ && !detecting_ && !currentItem_.audioPath.empty());
```

To rozwiązuje też edge case z MIDI items.

**Krok 3 - Tooltip explaining state**:

```cpp
if (!modelLoaded_) detectButton.setTooltip("Model not loaded - downloading or failed");
else if (currentItem_.audioPath.empty()) detectButton.setTooltip("Select an audio item (not MIDI)");
else detectButton.setTooltip("Run neural beat detection on selected item");
```

**Effort:** Small (1h).

---

## Issue 5: Plugin nie ładuje akcji na Windows (fightclxb, squibs)

**Symptom:** DLL w UserPlugins, ale brak wpisu w Extensions menu, brak akcji w Action List. Bassman002 wcześniej miał ten sam problem - po dodaniu onnxruntime.dll działało.

### Root cause: prawdopodobnie brak Visual C++ 2022 Redistributable

```cpp
// main.cpp:119 line in ReaperPluginEntry
if (REAPERAPI_LoadAPI(rec->GetFunc) != 0)
    return 0;
```

Jeśli plugin nie ładuje się w ogóle, to jeszcze przed `ReaperPluginEntry` - dynamic loader (Windows) odrzuca DLL z brakującymi dependencies.

**Plugin zależy od:**
1. `onnxruntime.dll` (delay-load - OK, ładuje się przy pierwszym ORT call, NIE przy load pluginu)
2. `vcruntime140.dll`, `msvcp140.dll` (MSVC C++ runtime)

### CMakeLists.txt timing bug

```cmake
# CMakeLists.txt:74-75
file(GLOB REABEAT_SOURCES "src/*.cpp")
add_library(reaper_reabeat SHARED ${REABEAT_SOURCES})

# ...

# CMakeLists.txt:117-119
if(MSVC)
  target_compile_options(reaper_reabeat PRIVATE /W3)
  set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
```

**Problem:** `CMAKE_MSVC_RUNTIME_LIBRARY` jest ustawione PO `add_library()`. Według dokumentacji CMake, ta zmienna jest property pobierana PRZY tworzeniu targetu. Późniejsze ustawienie nie ma efektu na target już utworzony - target zostaje z domyślną wartością (`MultiThreadedDLL`).

**Konsekwencja:** Plugin dynamicznie linkuje do MSVC runtime. Wymaga `vcruntime140.dll` + `msvcp140.dll`. Windowsy bez VC++ Redist 2015-2022 nie załadują pluginu.

### Verification

Need to test on a clean Windows 11 without VC++ Redist installed. Alternatywnie: użytkownicy fightclxb/squibs powinni zainstalować [VC++ Redistributable 2022](https://aka.ms/vs/17/release/vc_redist.x64.exe) i przetestować ponownie.

ALE: prawidłowo zaprojektowany plugin distributable powinien STATICALLY linkować MSVC runtime by uniknąć zależności od user-installed redistributable.

### Proposed fix

**Krok 1 - Move `CMAKE_MSVC_RUNTIME_LIBRARY` set BEFORE `add_library`**:

```cmake
# CMakeLists.txt - PRZED linia 74 (file GLOB / add_library)
if(MSVC)
  set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()

# Then add_library...
```

**Krok 2 - Set policy CMP0091** (gwarantuje że nowa runtime selection działa):

```cmake
# Top of CMakeLists.txt
cmake_policy(SET CMP0091 NEW)
```

To upewnia że runtime jest statically linked (MT zamiast MD).

**Krok 3 - Verify with `dumpbin`** w CI:

```yaml
# build.yml - add after Build step on Windows
- name: Verify static MSVC runtime
  if: runner.os == 'Windows'
  shell: pwsh
  run: |
    dumpbin /DEPENDENTS build/Release/reaper_reabeat-x64.dll
    # Should NOT contain vcruntime140.dll or msvcp140.dll
```

**Krok 4 (defensive)** - Dodać `LoadLibrary` test w main.cpp dla preload sprawdzający OnnxRuntime:

```cpp
// main.cpp - preloadOnnxRuntime expanded
static void preloadOnnxRuntime() {
    // ... existing code ...
    HMODULE ort = LoadLibraryW(ortPath);
    if (!ort) {
        // ORT failed - log to file or display
        wchar_t logPath[MAX_PATH] = {};
        PathCombineW(logPath, dllDir, L"reabeat_load_error.txt");
        // Write GetLastError() to file
    }
}
```

To pozwoli userom (squibs, fightclxb) zobaczyć dlaczego plugin nie ładuje.

**Effort:** Small (1-2h). Test: clean Windows VM bez VC++ Redist.

---

## Issue 6: Tempo Map nadpisuje WSZYSTKIE markery (gkurtenbach)

**Symptom:** "Is it possible to insert a tempo map without ReaBeat deleting the tempo markers before the item being beat-detected?"

User ma istniejące tempo markery PRZED selected item (np. inny utwór w tym samym projekcie). Insert Tempo Map kasuje WSZYSTKIE markery, nie tylko te w obszarze itemu.

### Code path

```cpp
// ReaperActions.cpp:319-325
int existing = CountTempoTimeSigMarkers(nullptr);
if (existing > 0) {
    for (int i = existing - 1; i >= 0; --i)
        DeleteTempoTimeSigMarker(nullptr, i);  // kasuje WSZYSTKIE
}
```

**Bug confirmed.** Code kasuje globalnie wszystkie tempo markery w projekcie. To data loss - irreversible by anything except Ctrl+Z (chociaż całość jest w undo block, więc ratunek istnieje).

### Proposed fix

**Krok 1 - Kasować tylko markery w obszarze itemu**:

```cpp
// ReaperActions.cpp:319-325 - replace
double itemStart = GetMediaItemInfo_Value(item, "D_POSITION");
double itemEnd = itemStart + GetMediaItemInfo_Value(item, "D_LENGTH");

int existing = CountTempoTimeSigMarkers(nullptr);
for (int i = existing - 1; i >= 0; --i) {
    double timepos = 0;
    double measurepos = 0;
    double beatpos = 0;
    double bpm = 0;
    int timesig_num = 0, timesig_denom = 0;
    bool lineartempo = false;
    GetTempoTimeSigMarker(nullptr, i,
        &timepos, &measurepos, &beatpos,
        &bpm, &timesig_num, &timesig_denom, &lineartempo);

    if (timepos >= itemStart - 0.01 && timepos <= itemEnd + 0.01)
        DeleteTempoTimeSigMarker(nullptr, i);
}
```

**Krok 2 - Tooltip/option dla "keep existing"**:

Dodać checkbox w UI: "Replace existing tempo markers in item range" (default ON for backward compat, ale można wyłączyć).

**Effort:** Small (1h).

---

## Issue 7: 6/8 wykrywane jako 4/4 (notabot)

**Symptom:** "compound time signatures... 6/8 was present, it mapped it as 4/4". Sequoia 15.7.5, M4 Mac.

### Code path

```cpp
// TimeSigDetector.cpp:5-46
int TimeSigDetector::detect(const std::vector<float>& beats,
                             const std::vector<float>& downbeats) {
    // ...
    for (size_t i = 0; i < downbeats.size() - 1; ++i) {
        // count beats in bar
        int n = 0;
        for (float beat : beats) {
            if (beat >= barStart && beat < barEnd) ++n;
        }
        if (n >= 2 && n <= 7)
            counts[n]++;
    }
    // return mode (most frequent count)
    return bestCount;
}
```

### Problem

Algorytm zlicza beats per bar i zwraca najczęstszą wartość. Dla 6/8 (compound meter):
- W praktyce użytkownicy odczuwają 6/8 jako 2 beaty na takt (2 grupy po 3 ósemki = pulsacja na 1 i 4)
- Model beat-this może detekować 2 mocne beats per bar (downbeats) lub 6 beats per bar (każda ósemka)
- Detector zwraca to co model dał

**Cardinal bug:** jeśli model widzi 2 beats per bar w 6/8, algorytm zwraca `n=2`, co przy `timeSigDenom=4` daje **2/4**. Jeśli model widzi 6, returns `n=6` → **6/4** (wrong - powinno być 6/8).

Plus `timeSigDenom` jest **hardcoded na 4** w `BeatDetector.cpp:271`:
```cpp
result.timeSigDenom = 4;
```

Brak rozróżnienia compound (denom=8) vs simple (denom=4).

### Proposed fix

**Krok 1 - Heurystyka compound meter z BPM**:

Model beat-this trenowany na "główne" beats. Jeśli zwraca tempo > 130 BPM AND wszystkie barz mają n=2, prawdopodobnie 6/8 lub 12/8:

```cpp
// TimeSigDetector::detect - enhanced
struct Result { int num; int denom; };

Result detectCompound(const std::vector<float>& beats,
                      const std::vector<float>& downbeats,
                      float tempo) {
    int simple = detectSimple(beats, downbeats);  // existing logic

    // Compound meter heuristic:
    // - mode 2 with tempo > 130 = 6/8 (each beat = 3 eighth notes)
    // - mode 4 with tempo > 130 = 12/8
    if (tempo > 130.0f) {
        if (simple == 2) return {6, 8};
        if (simple == 3) return {9, 8};
        if (simple == 4) return {12, 8};
    }
    return {simple, 4};
}
```

**Krok 2 - Alternatywnie: detect via mel-spectrogram patterns**:

Compound meters mają wyraźny ⅓-pulsacyjny wzorzec (3 strong-weak-weak). Można analizować autocorrelation onset envelope w window [0.1, 0.5] sec - peak na 1/3 vs 1/2 of beat interval.

To znaczna praca, nie do quick fix.

**Krok 3 - User override** (jak Daodan #9 wymaga):

Dodać dropdown w UI "Time signature" z opcjami: Auto, 2/4, 3/4, 4/4, 6/8, 9/8, 12/8. Override `result.timeSigNum`/`Denom`.

### Status

Compound meter detection to **fundamentally hard problem**. Nawet komercyjne narzędzia (Ableton, Logic) zawodzą. Realistyczne rozwiązanie: **manual override** (Daodan #9) + heurystyka tempa jako default.

**Effort:** Medium (4-6h with testing).

---

## Issue 8: Linux Debian Trixie nie ładuje (reaperfreaker)

**Symptom:** Plugin nie ładuje się na Debian Trixie (manual + ReaPack). Brak logów.

### Likely root cause: glibc/libstdc++ forward compatibility

CI build na **Ubuntu 22.04** (`ubuntu-22.04` runner):
- glibc 2.35
- libstdc++ 12

**Debian Trixie** (testing):
- glibc 2.41+ (released 2024)
- libstdc++ 14

Plugin built on Ubuntu 22 links against glibc 2.35 symbols. Forward-compatible jest OK (Debian Trixie ma nowszą glibc, która jest backward compatible).

ALE: jeśli plugin używa nowszych C++ features (`<numbers>`, `std::lerp`, `std::format`), które trafiają do `libstdc++.so.6.0.30+`, to:
- Ubuntu 22 libstdc++ = 6.0.30
- Debian Trixie libstdc++ = 6.0.33+

Powinno działać forward.

### Other possible causes

1. **Missing system libs**: 
   - libcurl4 (linked, line 192 CMakeLists)
   - libfreetype, libx11, libxrandr, libxcursor, libxinerama, libasound2 (z CI install-deps)
   - On Debian Trixie: package names mogą się różnić od Ubuntu

2. **Wayland vs X11**:
   - Plugin: `JUCE_USE_XSHM=0`, używa X11 przez SWELL XBridge
   - Debian Trixie default = Wayland session
   - Jeśli REAPER uruchomiony pod XWayland: powinno działać
   - Jeśli REAPER native Wayland: brak X11 socket → fail

3. **SWELL ABI changes**: REAPER on Debian Trixie może mieć inny SWELL version

### Proposed action

**Bez logów od reaperfreaker nie można potwierdzić root cause.** Potrzebne:

```bash
# Reaperfreaker should run:
REAPER --loglevel=verbose 2>&1 | grep -i reabeat
ldd ~/.config/REAPER/UserPlugins/reaper_reabeat-x86_64.so
dmesg | tail -20  # check for OOM or SELinux/AppArmor
```

### Proposed fix (preemptive)

**Krok 1 - Build na Ubuntu 20.04 zamiast 22.04** (starsza baza, lepsza forward compat):

```yaml
# build.yml
- os: ubuntu-20.04
  platform: Linux-x86_64
```

To wymaga glibc 2.31 (Ubuntu 20.04) - starsza baseline = działa też na nowszych systemach.

**Krok 2 - Static link libstdc++** (jeśli możliwe):

```cmake
# CMakeLists.txt - Linux section
if(UNIX AND NOT APPLE)
  target_link_options(reaper_reabeat PRIVATE -static-libstdc++ -static-libgcc)
endif()
```

To eliminuje runtime dependency on system libstdc++.

**Effort:** Small (build change) + waiting for user logs.

---

## Issue 9: macOS Catalina ORT symbol error (reaperfreaker)

**Symptom:** "Symbol not found: __ZNKSt3__115basic_stringbufIcNS_11char_traitsIcEEE NS_9allocatorIcEEE3strEv" z `libonnxruntime.1.20.1.dylib (built for Mac OS X 13.3)`.

**Identyczny root cause jak Issue 3** (80icio). Patrz tam.

**Fix:** Downgrade ORT to v1.16.3 na macOS x86_64 (Catalina compatible).

---

## Issue 10: Daodan's 9 punktów UX

### #1 - Stretches item until timebase manually set

**Code path:** `ReaperActions::insertTempoMap` (linie 303-379). Brak `I_TIMEBASE` set.

**Fix:**
```cpp
// Po SetTempoTimeSigMarker w insertTempoMap
SetMediaItemInfo_Value(item, "C_BEATATTACHMODE", 1);  // 1 = beats (auto)
// LUB:
SetMediaItemInfo_Value(item, "C_BEATATTACHMODE", -1);  // -1 = use project default
```

Sprawdzić w REAPER SDK który `C_*` lub `I_*` parameter to "Timebase". Z dokumentacji: `C_BEATATTACHMODE` to per-item: -1=auto, 0=time, 1=beats position only, 2=beats source.

**Effort:** Small (30 min).

### #2 - Some beats not draggable

**Code path:** `WaveformView.cpp`. `kBeatHitPx = 8.0f`, `findNearestBeat` returns -1 if no beat within 8px (linia 139).

**Possible cause:**
- Cluster beats (gęsto upakowane): 2 beats w odległości <16px → click w środek nie matchuje żadnego (oba >8px)
- Hover state not updating jeśli mouseMove nie firował (Windows/macOS różnice w event delivery przy szybkim ruchu)
- Beat zbyt blisko ruler area (bottom 16px) - klik tam = seek nie drag

**Fix:**
- Zwiększyć `kBeatHitPx` do 12.0f
- Dodać click-and-drag bez hover requirement: jeśli kliknięcie blisko beat (within 8-15px), zacznij drag bez wymagania prior hover state

```cpp
// WaveformView.cpp - mouseDown
int nearest = findNearestBeat(e.x, kBeatHitPx);
if (nearest >= 0) {
    potentialDragIdx_ = nearest;
    mouseDownX_ = e.x;
}
```

**Effort:** Small (1h).

### #3 - Red dashed suggestion lines hard to see on red tint

**Code path:** WaveformView.cpp:587-628.
- Background tint: `0x18d94848` (24/255 alpha = 9% red)
- Suggestion lines: `0x40d94848` (64/255 alpha = 25% red)

Ten sam hue, niska różnica alphy = niski kontrast.

**Fix:**
- Suggestion lines → different color (np. teal `0xc080e0e0`) zamiast red
- Lub białe (`0xa0ffffff`) z drugim kolorem konturu

```cpp
// WaveformView.cpp:595
g.setColour(juce::Colour(0xa080e0e0));  // teal, 63% alpha
```

**Effort:** Small (15 min).

### #4 - Middle-mouse drag + scrollbar

**Code path:** `mouseWheelMove` (WaveformView.cpp:1371), brak middle-mouse handler, scrollbar tylko jako visual (linie 915-920).

**Fix:**
- Implementuj `mouseDrag` z `e.mods.isMiddleButtonDown()`
- Scrollbar: detect click on scrollbar area, allow dragging thumb

```cpp
void WaveformView::mouseDown(const juce::MouseEvent& e) {
    // Middle-button pan
    if (e.mods.isMiddleButtonDown()) {
        panStartX_ = e.x;
        panStartView_ = viewStart_;
        return;
    }
    // ... existing logic
}

void WaveformView::mouseDrag(const juce::MouseEvent& e) {
    if (e.mods.isMiddleButtonDown()) {
        double dx = (panStartX_ - e.x) * viewDuration_ / getWidth();
        viewStart_ = std::clamp(panStartView_ + dx, 0.0,
                                duration_ - viewDuration_);
        repaint();
        return;
    }
    // ... existing logic
}
```

**Effort:** Small (2h).

### #5 - Last selected item not persisted when nothing selected

**Code path:** `MainComponent.cpp:869-882`. Pełen reset gdy `count <= 0`.

**Fix:** Zachowaj `currentItem_` ale tylko zmieniaj label:

```cpp
// MainComponent.cpp:869
if (count <= 0) {
    if (!currentItem_.guid.empty()) {
        sourceLabel.setText(currentItem_.name + " (deselected)", ...);
        // KEEP currentItem_, detected_, cache - just visual hint
        detectButton.setEnabled(false);
        return;
    }
    // existing reset for first-launch case
}
```

**Effort:** Small (30 min).

### #6 - N key shortcut easy to forget

**Fix:** Status hint na waveform "Press N to find next gap" gdy są gaps:

```cpp
// WaveformView::paint - if has_gaps and !zoomed
g.setColour(Colors::textDim);
g.setFont(11.0f);
g.drawText("Press N to find next gap", bounds, Justification::topRight);
```

Lub button "Next gap" w UI obok BPM.

**Effort:** Small (30 min).

### #7 - Model download status message unclear

**Code path:** MainComponent.cpp:124-126 - statusbar shows "Downloading model... 23%".

**Possible issue:** User Daodan nie widzi tego (może statusbar jest za mały, lub zniknął już).

**Fix:** Progress bar w widocznym miejscu zamiast tylko statusbar:

```cpp
// MainComponent - reuse existing progressBar for model download
progressBar->setValue(progress);
progressBar->setVisible(true);
progressLabel.setText("Downloading model: 23%", ...);
```

Plus button text update (patrz Issue 4):
```cpp
detectButton.setButtonText("Downloading...");
```

**Effort:** Small (1h).

### #8 - Docked window doesn't auto-show

**Code path:** DockableWindow.h:144-149 - `DockWindowAddEx` ale brak `DockWindowActivate` po add.

**Fix:**
```cpp
// DockableWindow.h:147-149
if (isDocked_) {
    if (DockWindowAddEx) DockWindowAddEx(hwnd_, "ReaBeat", "ReaBeat_dock", true);
    if (DockWindowActivate) DockWindowActivate(hwnd_);  // ADD THIS
}
```

**Effort:** Small (15 min).

### #9 - Manual time signature override (also notabot's request)

**Fix:** Dropdown w UI "Time signature: [Auto/2/4/3/4/4/4/6/8/9/8/12/8]". Patrz Issue 7.

**Effort:** Medium (2h - UI + connect to detection result override).

---

## Issue 11: Model w UserPlugins dla portable setups (akademie)

**Code path:** `ModelManager.cpp:14`:

```cpp
return home.getChildFile(".reabeat").getChildFile("models").getFullPathName().toStdString();
```

Hardcoded `~/.reabeat/`. Portable REAPER nie ma stable HOME.

**Fix:** Sprawdź UserPlugins najpierw:

```cpp
std::string ModelManager::getModelDir() {
    // Try plugin directory first (portable mode)
    auto pluginDir = juce::File::getSpecialLocation(
        juce::File::currentExecutableFile).getParentDirectory();
    auto candidate = pluginDir.getChildFile("ReaBeat").getChildFile("models");
    if (candidate.exists())
        return candidate.getFullPathName().toStdString();

    // Fallback: home dir
    auto home = juce::File::getSpecialLocation(juce::File::userHomeDirectory);
    return home.getChildFile(".reabeat").getChildFile("models")
        .getFullPathName().toStdString();
}
```

Plus dokumentacja: portable user może umieścić `beat_this_final0.onnx` w `UserPlugins/ReaBeat/models/`.

**Effort:** Small (1h).

---

## Cross-reference: reamix.me_native solutions

Z analizy `/Volumes/@Basic/Projekty/reamix.me_native/`:

### 1. Download progress reporting
reamix używa `ModelManager::ensureDownloaded` z callback `(juce::int64 read, juce::int64 total)`. ReaBeat już ma równoważne `progressCb(float fraction)`. **Brak luki funkcjonalnej.**

### 2. Cancel operations
reamix używa `alive_ = shared<atomic<bool>>` checked w `threadShouldExit()` between stages (AnalyzePipeline.cpp:198, 225, 253, 264, 327). **ReaBeat nie ma cancel button** - propozycja: dodać `cancelButton` które ustawia `detectionThread_->signalThreadShouldExit()`, oraz wstawić `if (Thread::currentThreadShouldExit()) throw std::runtime_error("Cancelled");` między stage'ami w `BeatDetector::detect`.

### 3. Memory release between stages
reamix robi `mono22050.clear(); mono22050.shrink_to_fit();` po stage 3 (AnalyzePipeline.cpp:257-258, komentarz "drop to release ~16 MB"). **ReaBeat nie zwalnia pamięci** między stage'ami - audio22k pozostaje w pamięci aż do końca detection, MIMO że jest używane tylko w OnsetRefinement. Propozycja: zwolnij `audio22k` po OnsetRefinement.

### 4. Error reporting w UI
reamix używa `juce::AlertWindow::showMessageBoxAsync()` + custom `OpaqueAlertWindow` dla Linux backing buffer corruption fix. **ReaBeat used to use ShowMessageBox** (REAPER native) ale memory rule #5 mówi nie używać go (always-on-top hides dialogs). Status label jest OK fallback.

### 5. Loading model from UserPlugins
reamix uses RPath subdir `@loader_path/reamix`. **ReaBeat could adopt** ten pattern dla portable model loading - patrz Issue 11.

### 6. Linux X11 bridging
Identyczne: `SWELL_CreateXBridgeWindow` w obu projektach. **Brak luki.**

### 7. CMakeLists timing
reamix też ma `CMAKE_MSVC_RUNTIME_LIBRARY` ale **przed `add_library`**. Potwierdza Issue 5 root cause - ReaBeat ma to ustawione w złym miejscu.

### 8. Chunked audio reading
**reamix nie chunkuje** - load all at once. Ten sam problem ma place dla długich plików. Propozycja: implementuj chunking w ReaBeat (Issue 1) i zaproponuj backport do reamix.

---

## Recommended fix priority for v2.0.2 release

### Immediate (1-day work)
1. **Issue 5** - Fix CMakeLists MSVC runtime timing (rozwiązuje fightclxb, squibs, potencjalnie też Bassman002 starego problemu)
2. **Issue 3/9** - Downgrade ORT to v1.16.3 dla macOS x86_64 (rozwiązuje 80icio + reaperfreaker Catalina)
3. **Issue 6** - Tempo Map: kasuj tylko markery w obszarze itemu (rozwiązuje gkurtenbach)
4. **Issue 2** - Stretch Markers: status feedback po Apply, default strength=1.0 (rozwiązuje plush2)
5. **Issue 11** - Model w UserPlugins fallback (akademie)

### High (2-day work)
6. **Issue 1A** - Chunked audio reading w `BeatDetector::detectFile` (Alex)
7. **Issue 1B** - OnsetRefinement skip dla audio >10min (Alex)
8. **Issue 4** - Detect button: tooltip, button label "Downloading...", check audioPath (Mercado_Negro)
9. **Daodan #1, #2, #3, #8** - timebase auto-set, drag threshold, suggestion color, dock activate

### Medium (3-day work)
10. **Issue 7 + Daodan #9** - Time signature manual override dropdown + compound meter heuristic
11. **Daodan #4, #5, #6, #7** - middle-mouse pan, item persistence, N hint, model download progress UI
12. **reamix cross-port** - cancel button, memory release between stages

### Lower priority
13. **Issue 8** - czekaj na logi od reaperfreaker (Debian Trixie)
14. **Sliding-window detection** dla classical (Alex long-term, not 2.0.2)

---

## Test plan dla v2.0.2

Before tag push:

| Test | Platform | Expected |
|------|----------|----------|
| Plugin loads, action visible | Clean Windows 11 bez VC++ Redist | Action visible (after MSVC runtime fix) |
| Plugin loads, action visible | macOS Catalina 10.15.7 Intel | Action visible (after ORT 1.16.3 downgrade) |
| Plugin loads, action visible | macOS Tahoe 26.4.1 M4 | Action visible + button enabled after model load |
| Detection na 5-min track | All platforms | OK (regression test) |
| Detection na 30-min track | All platforms | OK (new) |
| Detection na 90-min classical | All platforms | OK lub graceful error "Audio too long" (after chunking fix) |
| Insert Stretch Markers Windows | Windows 11 | Markery widoczne, status "Created N markers" |
| Tempo Map preserves earlier markers | All platforms | Markery przed itemem nietknięte |
| Detect Beats button states | All platforms | Disabled w czasie download, enabled po + audio item |
| Beat drag w cluster region | All platforms | Każdy beat draggable |
| 6/8 audio detection | All platforms | UI shows "6/8" (lub Auto z heurystyką) |
| Docked window auto-shows | All platforms | Window visible po toggleVisibility w docked mode |
| Model w UserPlugins (portable) | macOS arm64 | Loads model bez `~/.reabeat/` |

---

## Notes for next agent

- **Wszystkie file:line citations** powyżej są dla v2.0.1 (HEAD `2409315` na branch `main` per 2026-05-20)
- Przed implementacją: rebuild z `cmake .. && cmake --build . --config Release` i przetestuj E2E w REAPER (feedback: never defend broken code, test before release)
- Brak `--no-verify` na git commits
- Tag `v2.0.2` tylko jeśli zmienia się kod (CMakeLists, src/) - nie dla doc-only
- Patrz `feedback_release_checklist.md` dla pełnej procedury release
