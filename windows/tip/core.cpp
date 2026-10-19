#include "core.h"
#include <shlobj.h>
#include <fstream>
#include <regex>
#include <sstream>
#include <vector>
#include "spec.h"

extern HINSTANCE g_hinst;

namespace kx {

static Settings g_cur;
static bool g_started = false;
static FILETIME g_stamp = {};

std::string Utf8(const std::wstring &w) {
  if (w.empty()) return {};
  int n = WideCharToMultiByte(CP_UTF8, 0, w.c_str(), (int)w.size(), nullptr, 0, nullptr, nullptr);
  std::string s(n, 0);
  WideCharToMultiByte(CP_UTF8, 0, w.c_str(), (int)w.size(), &s[0], n, nullptr, nullptr);
  return s;
}

std::wstring Wide(const std::string &s) {
  if (s.empty()) return {};
  int n = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.size(), nullptr, 0);
  std::wstring w(n, 0);
  MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.size(), &w[0], n);
  return w;
}

std::wstring InstallDir() {
  wchar_t p[MAX_PATH];
  GetModuleFileNameW(g_hinst, p, MAX_PATH);
  std::wstring s(p);
  return s.substr(0, s.find_last_of(L'\\'));
}

std::wstring UserDir() {
  wchar_t env[MAX_PATH];
  if (GetEnvironmentVariableW(L"KX_USER", env, MAX_PATH)) return env;  // self-test only
  PWSTR p = nullptr;
  std::wstring out;
  if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_RoamingAppData, 0, nullptr, &p))) out = std::wstring(p) + L"\\KINFX Input";
  CoTaskMemFree(p);
  return out;
}

static std::string ReadAll(const std::wstring &path) {
  std::ifstream f(path, std::ios::binary);
  std::stringstream ss;
  ss << f.rdbuf();
  return ss.str();
}

static bool WriteIfChanged(const std::wstring &path, const std::string &text) {
  if (ReadAll(path) == text) return true;
  std::wstring tmp = path + L".tmp";
  { std::ofstream f(tmp, std::ios::binary | std::ios::trunc); f << text; if (!f) return false; }
  return MoveFileExW(tmp.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING) != 0;
}

Settings Defaults() {
  Settings s;
  for (auto &e : kSpec) s[e.key] = e.opts[0].v;
  return s;
}

Settings Load(const std::wstring &path) {
  Settings s = Defaults();
  std::string text = ReadAll(path);
  // shortcut: flat-object regex, not a JSON parser; settings.json is always flat (our writers).
  static const std::regex re("\"([a-z_]+)\"\\s*:\\s*(\"([^\"]*)\"|true|false|-?[0-9]+)");
  for (std::sregex_iterator it(text.begin(), text.end(), re), end; it != end; ++it) {
    std::string k = (*it)[1], v = (*it)[3].matched ? (*it)[3].str() : (*it)[2].str();
    for (auto &e : kSpec)
      if (k == e.key)
        for (int i = 0; i < e.n; i++)
          if (v == e.opts[i].v) s[k] = v;
  }
  return s;
}

std::string RimeCustom(const Settings &s) {
  std::string out = "# \xe7\x94\xb1 KINFX Input \xe8\xa8\xad\xe5\xae\x9a\xe8\xa6\x96\xe7\xaa\x97\xe7\x94\xa2\xe7\x94\x9f\xef\xbc\x8c\xe8\xab\x8b\xe5\x8b\xbf\xe6\x89\x8b\xe5\x8b\x95\xe4\xbf\xae\xe6\x94\xb9\xe3\x80\x82\npatch:\n";
  for (auto &e : kSpec) {
    if (!e.rime_key) continue;
    auto it = s.find(e.key);
    std::string v = it == s.end() ? e.opts[0].v : it->second, rv = v;
    for (int i = 0; i < e.n; i++)
      if (v == e.opts[i].v) rv = e.opts[i].rime;
    out += std::string("  \"") + e.rime_key + "\": " + rv + "\n";
  }
  return out;
}

static FILETIME Stamp(const std::wstring &path) {
  WIN32_FILE_ATTRIBUTE_DATA a = {};
  GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &a);
  return a.ftLastWriteTime;
}

static void PrepareUserDir() {
  std::wstring u = UserDir(), shared = InstallDir() + L"\\data";
  CreateDirectoryW(u.c_str(), nullptr);
  CreateDirectoryW((u + L"\\log").c_str(), nullptr);
  // The Lua scripts read their word lists from the user dir; keep it equal to the install.
  for (auto n : {L"kinfx_capture.txt", L"kinfx_en_unsafe.txt", L"kinfx_en_names.txt"})
    WriteIfChanged(u + L"\\" + n, ReadAll(shared + L"\\" + n));
  g_cur = Load(u + L"\\settings.json");
  g_stamp = Stamp(u + L"\\settings.json");
  WriteIfChanged(u + L"\\kinfx_quick.custom.yaml", RimeCustom(g_cur));
}

bool Start() {
  if (g_started) return true;
  // The host app's DLL search path does not include our folder.
  if (!LoadLibraryExW((InstallDir() + L"\\rime.dll").c_str(), nullptr, LOAD_WITH_ALTERED_SEARCH_PATH)) return false;
  PrepareUserDir();
  std::string shared = Utf8(InstallDir() + L"\\data"), user = Utf8(UserDir()), log = user + "\\log";
  g_started = kx_start(shared.c_str(), user.c_str(), log.c_str(), 0) != 0;
  return g_started;
}

bool Started() { return g_started; }
const Settings &Current() { return g_cur; }

bool ReloadIfChanged() {
  if (!g_started) return false;
  std::wstring p = UserDir() + L"\\settings.json";
  FILETIME now = Stamp(p);
  if (CompareFileTime(&now, &g_stamp) == 0) return false;
  // Normally the settings app already rebuilt (KxDeploy), so this only finds the build up
  // to date. Packaged apps (e.g. Notepad) virtualise AppData writes, so avoid building here.
  PrepareUserDir();
  kx_redeploy();
  return true;
}

}  // namespace kx

// Settings app and installer: apply settings.json and rebuild in this (normal) process,
// so the text service in each app only finds an up-to-date build.
extern "C" __declspec(dllexport) int __stdcall KxDeploy() {
  if (!kx::Start()) return 0;
  kx::ReloadIfChanged();
  // Rime compares mtimes in whole seconds; drop the built schema so it is rebuilt.
  DeleteFileW((kx::UserDir() + L"\\build\\kinfx_quick.schema.yaml").c_str());
  return kx_redeploy();
}
