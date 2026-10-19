// KINFX Input for Windows: core shared by the TSF text service (KINFXInput.dll),
// the self-test and the settings app (through the KxDeploy export).
// Mirrors mac/Sources/Engine: settings.json -> Rime patch -> librime through kx_shim.
#pragma once
#include <windows.h>
#include <string>
#include <map>

namespace kx {

using Settings = std::map<std::string, std::string>;

std::wstring InstallDir();          // folder of KINFXInput.dll
std::wstring UserDir();             // %APPDATA%\KINFX Input
std::string Utf8(const std::wstring &w);
std::wstring Wide(const std::string &s);

Settings Defaults();
Settings Load(const std::wstring &path);  // trust boundary: unknown keys dropped, bad values -> default
std::string RimeCustom(const Settings &s);

// Loads rime.dll from InstallDir, prepares the user dir, starts Rime once per process.
bool Start();
bool Started();
// Re-read settings.json if its mtime changed; rewrite the patch and redeploy.
bool ReloadIfChanged();
const Settings &Current();

}  // namespace kx

extern "C" {
#include "kx_shim.h"
}
