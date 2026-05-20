#include "ModelManager.h"
#include <juce_core/juce_core.h>

#ifdef _WIN32
  #include <windows.h>
#else
  #include <dlfcn.h>
#endif

// Resolve the directory containing this plugin binary. Used to look for
// a portable model file next to the plugin (UserPlugins / portable REAPER).
static juce::File getPluginDirectory()
{
#ifdef _WIN32
    HMODULE hSelf = nullptr;
    GetModuleHandleExW(
        GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
        GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
        (LPCWSTR)&getPluginDirectory, &hSelf);
    if (!hSelf) return {};
    wchar_t buf[MAX_PATH] = {};
    if (GetModuleFileNameW(hSelf, buf, MAX_PATH) == 0) return {};
    return juce::File(juce::String(buf)).getParentDirectory();
#else
    Dl_info info{};
    if (dladdr((void*)&getPluginDirectory, &info) && info.dli_fname)
        return juce::File(juce::String::fromUTF8(info.dli_fname)).getParentDirectory();
    return {};
#endif
}

std::string ModelManager::getModelDir()
{
    auto home = juce::File::getSpecialLocation(juce::File::userHomeDirectory);
    return home.getChildFile(".reabeat").getChildFile("models").getFullPathName().toStdString();
}

std::string ModelManager::getModelPath()
{
    // Search order:
    //   1. Plugin directory (portable: UserPlugins/beat_this_final0.onnx)
    //   2. Plugin directory / "ReaBeat" / "models" subfolder (organized portable)
    //   3. ~/.reabeat/models/ (auto-download default)
    auto pluginDir = getPluginDirectory();
    if (pluginDir != juce::File())
    {
        auto flat = pluginDir.getChildFile(kModelFilename);
        if (flat.existsAsFile())
            return flat.getFullPathName().toStdString();

        auto sub = pluginDir.getChildFile("ReaBeat").getChildFile("models").getChildFile(kModelFilename);
        if (sub.existsAsFile())
            return sub.getFullPathName().toStdString();
    }

    auto home = juce::File(getModelDir()).getChildFile(kModelFilename);
    if (home.existsAsFile())
        return home.getFullPathName().toStdString();

    return {};
}

bool ModelManager::isModelCached()
{
    auto path = getModelPath();
    if (path.empty()) return false;

    // Basic size validation
    auto size = juce::File(path).getSize();
    return size >= kExpectedSizeMin && size <= kExpectedSizeMax;
}

bool ModelManager::downloadModel(std::function<void(float)> progressCb)
{
    // Create directory
    auto dir = juce::File(getModelDir());
    if (!dir.exists())
        dir.createDirectory();

    auto destFile = dir.getChildFile(kModelFilename);

    // Download URL - hosted on GitHub Releases
    juce::URL url("https://github.com/b451c/ReaBeat/releases/download/v2.0.0-model/beat_this_final0.onnx");

    // Use JUCE URL download with progress
    auto inputStream = url.createInputStream(
        juce::URL::InputStreamOptions(juce::URL::ParameterHandling::inAddress)
            .withConnectionTimeoutMs(30000)
            .withStatusCode(nullptr));

    if (!inputStream)
        return false;

    // Get content length for progress
    auto contentLength = inputStream->getTotalLength();

    auto outputStream = destFile.createOutputStream();
    if (!outputStream)
        return false;

    // Download in chunks
    constexpr int kBufferSize = 65536;
    juce::HeapBlock<char> buffer(kBufferSize);
    juce::int64 totalRead = 0;

    while (!inputStream->isExhausted())
    {
        auto bytesRead = inputStream->read(buffer.getData(), kBufferSize);
        if (bytesRead <= 0)
            break;

        outputStream->write(buffer.getData(), static_cast<size_t>(bytesRead));
        totalRead += bytesRead;

        if (progressCb && contentLength > 0)
            progressCb(static_cast<float>(totalRead) / static_cast<float>(contentLength));
    }

    outputStream->flush();
    outputStream.reset();

    // Validate downloaded file size
    auto size = destFile.getSize();
    if (size < kExpectedSizeMin || size > kExpectedSizeMax)
    {
        destFile.deleteFile();
        return false;
    }

    return true;
}
