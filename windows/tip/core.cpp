#include "core.h"
#include <shlobj.h>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <regex>
#include <sstream>
#include <vector>
#include "rime_api.h"
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

// Windows' own input hotkeys: Ctrl+Space (switch IME) and Ctrl+Shift (switch layout) are handled
// before TSF sees the key, and switching deactivates the text service. KINFX owns the chords in its
// key sink, so those OS bindings go off here and the original values are backed up for uninstall.
// Alt+Shift (Language Hotkey) is deliberately left on: TSF never sees VK_MENU, so that pair has to
// stay Windows' own input-language switch.
static const wchar_t *kHotKeys = L"Control Panel\\Input Method\\Hot Keys\\00000010";
static const wchar_t *kToggle = L"Keyboard Layout\\Toggle";

std::wstring HotkeyBackup() { return UserDir() + L"\\hotkeys-backup.json"; }

// -1 when the value is absent (restore then removes it again). The window hotkey is REG_BINARY (a
// 4-byte DWORD); the Keyboard Layout\Toggle pair is REG_SZ — Windows ignores a DWORD written there,
// measured on Win11: "1" = Left Alt+Shift, "2" = Ctrl+Shift, "3" = None, "4" = grave.
static long RegGet(const wchar_t *sub, const wchar_t *name, bool *isStr = nullptr) {
  if (isStr) *isStr = false;
  HKEY k;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, sub, 0, KEY_QUERY_VALUE, &k)) return -1;
  wchar_t buf[16] = {};
  DWORD type = 0, n = sizeof buf;
  long r = -1;
  if (RegQueryValueExW(k, name, nullptr, &type, (BYTE *)buf, &n) == ERROR_SUCCESS) {
    if (type == REG_SZ) {
      r = wcstol(buf, nullptr, 10);
      if (isStr) *isStr = true;
    } else if (n >= 4) {
      DWORD d = 0;
      memcpy(&d, buf, 4);
      r = (long)d;
    }
  }
  RegCloseKey(k);
  return r;
}

// Writes only when the value differs: the WM_SETTINGCHANGE below walks every top-level window and
// blocks on a hung one, so it must not run on every text service activation. v < 0 removes the value.
// str picks REG_SZ (the Toggle pair) over REG_DWORD (the IME hotkey).
static bool RegSet(const wchar_t *sub, const wchar_t *name, long v, bool str = false) {
  bool isStr = false;
  if (RegGet(sub, name, &isStr) == v && isStr == (str && v >= 0)) return false;
  HKEY k;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, sub, 0, nullptr, 0, KEY_SET_VALUE, nullptr, &k, nullptr)) return false;
  bool ok;
  if (v < 0) ok = RegDeleteValueW(k, name) == ERROR_SUCCESS;
  else if (str) {
    wchar_t s[8];
    swprintf(s, 8, L"%ld", v);
    ok = RegSetValueExW(k, name, 0, REG_SZ, (BYTE *)s, (DWORD)((wcslen(s) + 1) * sizeof(wchar_t))) == ERROR_SUCCESS;
  } else ok = RegSetValueExW(k, name, 0, REG_DWORD, (BYTE *)&v, 4) == ERROR_SUCCESS;
  RegCloseKey(k);
  return ok;
}

static void NotifyInputChanged() {
  SendMessageTimeoutW(HWND_BROADCAST, WM_SETTINGCHANGE, 0, (LPARAM)L"Keyboard Layout", SMTO_ABORTIFHUNG, 1000, nullptr);
}

void TakeOverHotkeys() {
  std::wstring b = HotkeyBackup();
  if (GetFileAttributesW(b.c_str()) == INVALID_FILE_ATTRIBUTES) {  // an existing backup is the user's original
    SYSTEMTIME t;
    GetLocalTime(&t);
    char json[256];
    snprintf(json, sizeof json,
             "{\n \"time\": \"%04d-%02d-%02dT%02d:%02d:%02d\",\n \"modifiers\": %ld,\n \"virtual_key\": %ld,\n"
             " \"language_hotkey\": %ld,\n \"layout_hotkey\": %ld\n}\n",
             t.wYear, t.wMonth, t.wDay, t.wHour, t.wMinute, t.wSecond, RegGet(kHotKeys, L"Key Modifiers"),
             RegGet(kHotKeys, L"Virtual Key"), RegGet(kToggle, L"Language Hotkey"), RegGet(kToggle, L"Layout Hotkey"));
    WriteIfChanged(b, json);
  }
  // 0 modifiers + 0 virtual key = the IME hotkey is unassigned. Language Hotkey 1 = Left Alt+Shift,
  // handed back to Windows (measured: 2 would be Ctrl+Shift, 3 None); Layout Hotkey 3 = None, so
  // Windows never claims the Ctrl+Shift that KINFX uses as its chord.
  bool changed = RegSet(kHotKeys, L"Key Modifiers", 0);
  changed |= RegSet(kHotKeys, L"Virtual Key", 0);
  changed |= RegSet(kToggle, L"Language Hotkey", 1, true);
  changed |= RegSet(kToggle, L"Layout Hotkey", 3, true);
  if (changed) NotifyInputChanged();
}

bool RestoreHotkeys() {
  std::string text = ReadAll(HotkeyBackup());
  if (text.empty()) return false;
  static const std::regex num("\"([a-z_]+)\"\\s*:\\s*(-?[0-9]+)");
  std::map<std::string, long> v;
  for (std::sregex_iterator it(text.begin(), text.end(), num), end; it != end; ++it) v[(*it)[1]] = std::stol((*it)[2]);
  RegSet(kHotKeys, L"Key Modifiers", v.count("modifiers") ? v["modifiers"] : -1);
  RegSet(kHotKeys, L"Virtual Key", v.count("virtual_key") ? v["virtual_key"] : -1);
  RegSet(kToggle, L"Language Hotkey", v.count("language_hotkey") ? v["language_hotkey"] : -1, true);
  RegSet(kToggle, L"Layout Hotkey", v.count("layout_hotkey") ? v["layout_hotkey"] : -1, true);
  DeleteFileW(HotkeyBackup().c_str());
  NotifyInputChanged();
  return true;
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
  TakeOverHotkeys();
  std::string shared = Utf8(InstallDir() + L"\\data"), user = Utf8(UserDir()), log = user + "\\log";
  g_started = kx_start(shared.c_str(), user.c_str(), log.c_str(), 0) != 0;
  return g_started;
}

bool Started() { return g_started; }
const Settings &Current() { return g_cur; }

// Rime owns ascii_mode; get_property does not report it, so ask the option API directly. The
// 中/英 hint needs the real state, not a flag the shell flips.
bool AsciiMode(uintptr_t sess) {
  static RimeApi *api = nullptr;
  if (!api) api = rime_get_api();
  return api && api->get_option && api->get_option((RimeSessionId)sess, "ascii_mode") != 0;
}

bool ReloadIfChanged() {
  if (!g_started) return false;
  TakeOverHotkeys();  // idempotent; also repairs a binding something put back
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
