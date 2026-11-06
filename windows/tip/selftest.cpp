// Windows self-test: same checks as mac/linux (vd1 -> 好, Return passes, page 5/9 via KxDeploy).
// Runs from the build folder next to rime.dll and data\.
#include <cstdio>
#include <cstring>
#include <fstream>
#include <regex>
#include <string>
#include <vector>
#include "chord.h"
#include "core.h"
#include "langbar.h"
#include "rime_api.h"

HINSTANCE g_hinst;
extern "C" int __stdcall KxDeploy();
static int fails = 0, gaps = 0;

// A contract vector the shared engine does not meet yet (Hermes owns the fix). It is not a PASS and
// not hidden as INFO: it prints GAP, counts in the summary, and turns into PASS by itself once the
// shared fix lands. It does not fail the Windows gate, because Windows must not change shared Lua.
static void Gap(const std::string &name, const std::string &got, const std::string &want) {
  bool ok = got == want;
  gaps += !ok;
  printf("%s %s: got [%s] want [%s]\n", ok ? "PASS" : "GAP(shared, open)", name.c_str(), got.c_str(), want.c_str());
}

static void Check(const std::string &name, const std::string &got, const std::string &want) {
  bool ok = got == want;
  fails += !ok;
  printf("%s %s: got [%s] want [%s]\n", ok ? "PASS" : "FAIL", name.c_str(), got.c_str(), want.c_str());
}

// Live Windows input hotkeys (00000010 window switch, 00000070 CHT toggle, the Toggle pair) plus
// the CHT binding from ImmGetHotKey. The run must end with exactly what it started with.
static std::string LiveHotkeys() {
  auto reg = [](const wchar_t *sub, const wchar_t *n) {
    HKEY k;
    wchar_t buf[16] = {};
    DWORD type = 0, sz = sizeof buf;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, sub, 0, KEY_QUERY_VALUE, &k)) return -1L;
    long r = -1L;
    if (RegQueryValueExW(k, n, nullptr, &type, (BYTE *)buf, &sz) == ERROR_SUCCESS) {
      if (type == REG_SZ) r = wcstol(buf, nullptr, 10);
      else if (sz >= 4) { DWORD d = 0; memcpy(&d, buf, 4); r = (long)d; }
    }
    RegCloseKey(k);
    return r;
  };
  std::string out;
  for (auto sub : {L"Control Panel\\Input Method\\Hot Keys\\00000010", L"Control Panel\\Input Method\\Hot Keys\\00000070"})
    out += std::to_string(reg(sub, L"Key Modifiers")) + "/" + std::to_string(reg(sub, L"Virtual Key")) + "/";
  out += std::to_string(reg(L"Keyboard Layout\\Toggle", L"Language Hotkey")) + "/" +
         std::to_string(reg(L"Keyboard Layout\\Toggle", L"Layout Hotkey"));
  typedef BOOL(WINAPI * GetFn)(DWORD, UINT *, UINT *, HKL *);
  HMODULE imm = LoadLibraryW(L"imm32.dll");
  auto get = imm ? (GetFn)GetProcAddress(imm, "ImmGetHotKey") : nullptr;
  UINT m = 0, v = 0; HKL h = nullptr;
  out += get && get(0x70, &m, &v, &h) ? " imm70=" + std::to_string(m) + "/" + std::to_string(v) : " imm70=none";
  return out;
}

static std::string Take(uintptr_t s) {
  char *p = kx_take_commit(s);
  std::string r = p ? p : "";
  free(p);
  return r;
}

static int Cands(uintptr_t s) {
  char *p = kx_context(s);
  std::string c = p ? p : "";
  free(p);
  int n = 0;
  for (char ch : c) n += ch == '\x1f';
  return n >= 5 ? n - 5 : 0;
}

static std::string Type(const char *keys, int *cands = nullptr) {
  uintptr_t s = kx_session("kinfx_quick");
  std::string out;
  for (const char *k = keys; *k; k++) { kx_key(s, *k, 0); out += Take(s); }
  if (cands) *cands = Cands(s);
  kx_destroy(s);
  return out;
}

// Count light pixels in an icon: proves the GDI-drawn 中/英 really landed on the bitmap (a blank
// icon would look like a missing language bar button, which was the 0.1.6 symptom).
static int LightPixels(HICON ic) {
  ICONINFO ii;
  if (!ic || !GetIconInfo(ic, &ii)) return -1;
  BITMAP bm = {};
  GetObject(ii.hbmColor, sizeof bm, &bm);
  BITMAPINFO bi = {};
  bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bi.bmiHeader.biWidth = bm.bmWidth;
  bi.bmiHeader.biHeight = -bm.bmHeight;
  bi.bmiHeader.biPlanes = 1;
  bi.bmiHeader.biBitCount = 32;
  bi.bmiHeader.biCompression = BI_RGB;
  std::vector<BYTE> px((size_t)bm.bmWidth * bm.bmHeight * 4);
  HDC dc = GetDC(nullptr);
  int n = GetDIBits(dc, ii.hbmColor, 0, bm.bmHeight, px.data(), &bi, DIB_RGB_COLORS);
  ReleaseDC(nullptr, dc);
  DeleteObject(ii.hbmColor);
  DeleteObject(ii.hbmMask);
  if (!n) return -1;
  int c = 0;
  for (size_t i = 0; i + 3 < px.size(); i += 4)
    if (px[i] > 0x80 && px[i + 1] > 0x80 && px[i + 2] > 0x80) c++;
  return c;
}

int main() {
  SetConsoleOutputCP(CP_UTF8);
  g_hinst = GetModuleHandleW(nullptr);
  const std::string hotkeysAtStart = LiveHotkeys();
  Check("start", kx::Start() ? "1" : "0", "1");
  Check("KX_USER start leaves hotkeys alone", LiveHotkeys(), hotkeysAtStart);
  Check("vd1", Type("vd1"), "\xe5\xa5\xbd");
  int n = 0;
  Type("vd", &n);
  Check("vd shows 9", std::to_string(n), "9");
  uintptr_t s = kx_session("kinfx_quick");
  for (char k : std::string("vd1")) kx_key(s, k, 0);
  Take(s);
  Check("Return after pick passes to app", std::to_string(kx_key(s, 0xff0d, 0)), "0");
  kx_destroy(s);
  Check("iPhone Space", Type("iPhone "), "iPhone ");
  // Width contract (canonical shared 3cf6a6b supersedes the 0.1.8 reset:1 rows, Mac review P1):
  // full_shape reset:0 (default 半形) governs punctuation only; emitted Space is U+0020 in BOTH
  // modes; composing Space still pages. Each mode is set explicitly per session (SetShape), so
  // neither the schema default nor kinfx_full_shape.state from an earlier run decides a row.
  {
    DeleteFileW((kx::UserDir() + L"\\kinfx_full_shape.state").c_str());
    RimeApi *api = rime_get_api();
    auto open = [&](int full) {
      uintptr_t g = kx_session("kinfx_quick");
      kx_key(g, 0xff1b, 0);  // idle Escape: the first key runs the Lua state restore, nothing else
                             // (a Shift tap would be the 中/英 chord)
      Take(g);
      if (full >= 0) api->set_option((RimeSessionId)g, "full_shape", full == 1);
      return g;
    };
    auto typeIn = [&](int full, std::initializer_list<const char *> keys, int *cands = nullptr) {
      uintptr_t g = open(full);
      std::string out;
      for (const char *k : keys) {
        std::string ks = k;
        if (ks == "ESC") kx_key(g, 0xff1b, 0);
        else if (ks == "RET") kx_key(g, 0xff0d, 0);
        else for (char ch : ks) kx_key(g, (unsigned char)ch, 0);
        out += Take(g);
      }
      if (cands) *cands = Cands(g);
      kx_destroy(g);
      return out;
    };
    {
      uintptr_t g = open(-1);
      Check("width default is half (reset:0)", std::to_string(api->get_option((RimeSessionId)g, "full_shape")), "0");
      kx_destroy(g);
    }
    struct P { const char *keys; const wchar_t *want; };
    static const P full[] = {
        {",", L"，"}, {".", L"。"}, {"?", L"？"}, {"!", L"！"}, {";", L"；"}, {":", L"："},
        {"(", L"（"}, {")", L"）"}, {"[", L"「"}, {"]", L"」"}, {"{", L"『"}, {"}", L"』"},
        {"<", L"《"}, {">", L"》"}, {"\\", L"、"}, {"''", L"‘’"}, {"\"\"", L"“”"},
        // Leading slash in a fresh context is a command leader (/init): half-width by contract.
        {"/", L"/"}, {"-", L"－"}, {"_", L"＿"}, {"+", L"＋"}, {"=", L"＝"}, {"~", L"～"},
        {"$", L"＄"}, {"%", L"％"}, {"@", L"＠"}, {"#", L"＃"}, {"^", L"＾"}, {"&", L"＆"},
        {"*", L"＊"}, {"|", L"｜"}, {"`", L"｀"},
    };
    std::string bad;
    for (const P &p : full) {
      int c = 0;
      std::string out = typeIn(1, {p.keys}, &c);
      if (out != kx::Utf8(p.want) || c) bad += std::string(p.keys) + "=" + out + "/" + std::to_string(c) + " ";
    }
    Check("punct full mode: one glyph, no menu", bad.empty() ? "ok" : bad, "ok");
    bad.clear();
    for (const char *k : {",", ".", "?", "!", ";", ":", "(", ")", "[", "]", "-", "*", "/"}) {
      int c = 0;
      std::string out = typeIn(0, {k}, &c);
      if (out != k || c) bad += std::string(k) + "=" + out + "/" + std::to_string(c) + " ";
    }
    Check("punct half mode: plain ASCII, no menu", bad.empty() ? "ok" : bad, "ok");
    // Space: U+0020 in both modes, after CJK, digits and Latin alike.
    for (int m : {0, 1}) {
      std::string tag = m ? "full" : "half";
      Check("space " + tag + ": idle", typeIn(m, {" "}), " ");
      Check("space " + tag + ": after 好", typeIn(m, {"vd1", "ESC", " "}), "\xe5\xa5\xbd ");
      Check("space " + tag + ": hello.", typeIn(m, {"hello.", " "}), "hello. ");
      Check("space " + tag + ": 60cm", typeIn(m, {"60cm", " "}), "60cm ");
      Check("space " + tag + ": 60 then two", typeIn(m, {"60", " ", " "}), "60  ");
    }
    {
      int c = 0;
      typeIn(1, {"vd", " "}, &c);  // composing Space still pages, it does not commit a space
      Check("space while composing pages (full)", std::to_string(c > 0), "1");
    }
    Check("comma after 好 full", typeIn(1, {"vd1", ","}), "\xe5\xa5\xbd\xef\xbc\x8c");
    Check("comma after 好 half", typeIn(0, {"vd1", ","}), "\xe5\xa5\xbd,");
    // Shift+Space toggles 半形 -> 全形 -> 半形 from the explicit half start.
    {
      uintptr_t g = open(0);
      std::string shape;
      Check("Shift+Space eaten", std::to_string(kx_key(g, 0x20, 1)), "1");  // half -> full
      for (const char *k : {"v", "d", "1", ","}) { kx_key(g, *k, 0); shape += Take(g); }
      kx_key(g, 0x20, 1);  // full -> half
      for (const char *k : {"v", "d", "1", ","}) { kx_key(g, *k, 0); shape += Take(g); }
      Check("Shift+Space: full then half", shape, "\xe5\xa5\xbd\xef\xbc\x8c\xe5\xa5\xbd,");
      kx_destroy(g);
    }
    DeleteFileW((kx::UserDir() + L"\\kinfx_full_shape.state").c_str());
    // 全形/半形 held user-wide (the TSF key path runs ApplyShape before and NoteShape after each
    // key; only Shift+Space publishes). App A picks full; app B and A after switching back keep it.
    {
      Check("shape: nothing chosen yet", std::to_string(kx::ShapeWanted()), "-1");
      uintptr_t a = open(-1);
      kx::ApplyShape(a);
      kx_key(a, 0x20, 1);  // Shift+Space: half -> full
      kx::NoteShape(a, true);
      Check("shape: Shift+Space held as full", std::to_string(kx::ShapeWanted()), "1");
      uintptr_t b = open(-1);  // new app: schema default is half
      kx::ApplyShape(b);
      std::string got;
      for (const char *k : {"v", "d", "1", ","}) { kx_key(b, *k, 0); got += Take(b); kx::NoteShape(b, false); }
      Check("shape: other app keeps full", got, "\xe5\xa5\xbd\xef\xbc\x8c");
      // A drift that is not the toggle key (e.g. a stale Lua state restore) is undone, not published.
      api->set_option((RimeSessionId)b, "full_shape", false);
      kx::NoteShape(b, false);
      Check("shape: non-toggle drift not published", std::to_string(kx::ShapeWanted()) + "/" +
            std::to_string(api->get_option((RimeSessionId)b, "full_shape")), "1/1");
      kx_key(b, 0x20, 1);  // Shift+Space in B: full -> half
      kx::NoteShape(b, true);
      kx::ApplyShape(a);  // back to app A
      got.clear();
      for (const char *k : {"v", "d", "1", ","}) { kx_key(a, *k, 0); got += Take(a); }
      Check("shape: half chosen in B reaches A", got, "\xe5\xa5\xbd,");
      kx_destroy(a);
      kx_destroy(b);
    }
    DeleteFileW((kx::UserDir() + L"\\kinfx_full_shape.state").c_str());
    // Handoff vector the shared engine owns, judged with an explicit mode (not the default).
    Gap("shared: full mode vd1 then '/' after CJK", typeIn(1, {"vd1", "/", "RET"}), "\xe5\xa5\xbd\xef\xbc\x8f");
    Check("half mode vd1 then '/'", typeIn(0, {"vd1", "/", "RET"}), "\xe5\xa5\xbd/");
  }
  for (auto cw : {std::pair<const char *, const char *>{"vdhel", "\xe5\xa5\xbd\xe5\x8f\x8d"}, {"vd", ""}}) {
    const char *code = cw.first, *want = cw.second;
    s = kx_session("kinfx_quick");
    std::string out;
    for (const char *k = code; *k; k++) { kx_key(s, *k, 0); out += Take(s); }
    int eaten = kx_key(s, 'v', 4);  // Ctrl+V
    out += Take(s);
    Check(std::string(code) + " Ctrl+V commits held, app pastes", out + "/" + std::to_string(eaten), std::string(want) + "/0");
    kx_destroy(s);
  }
  // 0.1.4 blur (F35 from OnCompositionTerminated): what was typed stays. Shared default
  // english/blur_short=letters keeps a 1-2 letter run as letters (same rows as mac/linux selftest).
  for (auto cw : {std::pair<const char *, const char *>{"hel", "hel"}, {"vdhel", "vdhel"}, {"vd", "vd"},
                  {"vd1hel", "\xe5\xa5\xbdhel"}, {"ofca", "ofca"}, {"he", "he"}}) {
    s = kx_session("kinfx_quick");
    std::string out;
    for (const char *k = cw.first; *k; k++) { kx_key(s, *k, 0); out += Take(s); }
    kx_key(s, 0xffe0, 0);
    out += Take(s);
    for (char k : std::string("vd1")) { kx_key(s, k, 0); out += Take(s); }
    Check(std::string(cw.first) + " blur keeps text", out, std::string(cw.second) + "\xe5\xa5\xbd");
    kx_destroy(s);
  }
  // 0.1.6 Chinese/English switch: Control+space toggles ascii_mode (key_binder).
  // Fix A (locked): in ascii mode english_mix eats a letter and commits it half-width (v, never
  // ｖ even under full_shape), so the shell inserts it; back in Chinese they compose.
  {
    uintptr_t t = kx_session("kinfx_quick");
    int on = kx_key(t, 0x20, 4);
    int pass = kx_key(t, 'v', 0);
    int off = kx_key(t, 0x20, 4);
    std::string out;
    for (char k : std::string("vd1")) { kx_key(t, k, 0); out += Take(t); }
    Check("Control+space toggles ascii_mode", std::to_string(on) + "/" + std::to_string(pass) + "/" +
                                                 std::to_string(off) + "/" + out, "1/1/1/v\xe5\xa5\xbd");
    kx_destroy(t);
  }
  // A live composition is closed before the toggle (the shell's sequence): Return commits the
  // preedit, Escape closes the association list the pick leaves open. With one open,
  // ascii_composer keeps the key inline and the first letters typed are swallowed.
  {
    uintptr_t t = kx_session("kinfx_quick");
    for (char k : std::string("vd")) kx_key(t, k, 0);
    kx_key(t, 0xff0d, 0);
    std::string out = Take(t);
    kx_key(t, 0xff1b, 0);
    kx_key(t, 0x20, 4);
    int v = kx_key(t, 'v', 0), d = kx_key(t, 'd', 0);
    std::string typed = Take(t);
    // No letter swallowed: both are committed as half-width ASCII (Fix A).
    Check("preedit commit then toggle", out + "/" + std::to_string(v) + std::to_string(d) + "/" + typed,
          "\xe5\xa5\xbd/11/vd");
    kx_destroy(t);
  }
  // The mode hint reads ascii_mode back to know 中 vs 英: a wrong read would mislabel the switch.
  {
    uintptr_t t = kx_session("kinfx_quick");
    kx_key(t, 0x20, 4);
    bool on = kx::AsciiMode(t);
    kx_key(t, 0x20, 4);
    bool off = kx::AsciiMode(t);
    Check("ascii_mode readable (hint)", std::string(on ? "1" : "0") + "/" + (off ? "1" : "0"), "1/0");
    kx_destroy(t);
  }
  // A modifier plus a real key must not toggle: the app owns Ctrl+Shift+P.
  {
    uintptr_t t = kx_session("kinfx_quick");
    int ctrl_p = kx_key(t, 'p', 5);  // Control+Shift+p
    std::string out;
    for (char k : std::string("vd1")) { kx_key(t, k, 0); out += Take(t); }
    Check("Control+Shift+P keeps Chinese", std::to_string(ctrl_p) + "/" + out, "0/\xe5\xa5\xbd");
    kx_destroy(t);
  }
  // Bare-modifier chords: the state machine (chord.h) that turns a Ctrl+Shift tap into the mode
  // switch. No UI, no hook: pure key order. Alt+Shift is Windows' language switch, not a chord.
  {
    auto hit = [](std::initializer_list<std::pair<int, bool>> ev) {
      KxChord c;
      bool h = false;
      for (auto &e : ev) if (c.Event(e.first, e.second)) h = true;
      return h ? "1" : "0";
    };
    const int C = KxChord::kCtrl, S = KxChord::kShift, A = KxChord::kAlt;
    auto N = [](int k) { return std::pair<int, bool>{k, false}; };
    auto U = [](int k) { return std::pair<int, bool>{k, true}; };
    Check("chord Ctrl+Shift, shift up first", hit({N(C), N(S), U(S), U(C)}), "1");
    Check("chord Ctrl+Shift, ctrl up first", hit({N(C), N(S), U(C), U(S)}), "1");
    Check("chord Ctrl+Shift+P is a shortcut", hit({N(C), N(S), N('p'), U('p'), U(S), U(C)}), "0");
    Check("chord lone Ctrl", hit({N(C), U(C)}), "0");
    Check("chord lone Shift", hit({N(S), U(S)}), "0");
    Check("chord Ctrl+Space is no chord", hit({N(C), N(0x20), U(0x20), U(C)}), "0");
    Check("chord Alt+Tab is no chord", hit({N(A), N(0x09), U(0x09), U(A)}), "0");
    Check("chord Ctrl+Shift+Alt is no chord", hit({N(C), N(S), N(A), U(A), U(S), U(C)}), "0");
    Check("chord works again after a shortcut", hit({N(C), N('p'), U('p'), U(C), N(C), N(S), U(S), U(C)}), "1");
  }
  // Hotkey takeover: Windows handles Ctrl+Space / Ctrl+Shift before TSF, so those OS bindings are
  // switched off and the originals kept in the backup. Alt+Shift goes the other way: Language Hotkey
  // "1" = Left Alt+Shift hands it back to Windows, Layout Hotkey "3" = None keeps Ctrl+Shift for the
  // chord (both are REG_SZ; measured values). Under KX_USER Start() leaves them alone, so the test
  // records the live values, watches the takeover switch them off, then checks the restore
  // (the uninstall path) returns exactly the live baseline, and leaves no backup behind.
  {
    const wchar_t *HK = L"Control Panel\\Input Method\\Hot Keys\\00000010", *TOG = L"Keyboard Layout\\Toggle";
    auto reg = [](const wchar_t *sub, const wchar_t *n) {
      HKEY k;
      wchar_t buf[16] = {};
      DWORD type = 0, sz = sizeof buf;
      if (RegOpenKeyExW(HKEY_CURRENT_USER, sub, 0, KEY_QUERY_VALUE, &k)) return -1L;
      long r = -1L;
      if (RegQueryValueExW(k, n, nullptr, &type, (BYTE *)buf, &sz) == ERROR_SUCCESS) {
        if (type == REG_SZ) r = wcstol(buf, nullptr, 10);  // the Toggle pair is REG_SZ
        else if (sz >= 4) { DWORD d = 0; memcpy(&d, buf, 4); r = (long)d; }
      }
      RegCloseKey(k);
      return r;
    };
    auto state = [&] {
      return std::to_string(reg(HK, L"Key Modifiers")) + "/" + std::to_string(reg(HK, L"Virtual Key")) + "/" +
             std::to_string(reg(TOG, L"Language Hotkey")) + "/" + std::to_string(reg(TOG, L"Layout Hotkey"));
    };
    // KX_USER: Start() no longer takes the hotkeys over, so the test owns the whole cycle. A backup
    // left by an interrupted earlier run is put back first, then the live values are the baseline.
    std::wstring bp = kx::UserDir() + L"\\hotkeys-backup.json", cbp = kx::UserDir() + L"\\hotkeys-backup-cht.json";
    if (GetFileAttributesW(bp.c_str()) != INVALID_FILE_ATTRIBUTES ||
        GetFileAttributesW(cbp.c_str()) != INVALID_FILE_ATTRIBUTES)
      kx::RestoreHotkeys();
    const wchar_t *HK70 = L"Control Panel\\Input Method\\Hot Keys\\00000070";
    const std::string before = state();
    const long chtVk = reg(HK70, L"Virtual Key"), chtMod = reg(HK70, L"Key Modifiers");
    kx::TakeOverHotkeys();
    std::string taken = state();                    // sequenced: an argument order would let state()
    long taken70 = reg(HK70, L"Virtual Key");
    bool back = kx::RestoreHotkeys();               // and the restore swap places
    std::string restored = state();
    Check("CHT Ctrl+Space hotkey off", std::to_string(chtVk <= 0 ? 0 : taken70 <= 0 ? 0 : taken70), "0");
    Check("CHT Ctrl+Space hotkey restored (live)",
          std::to_string(reg(HK70, L"Key Modifiers")) + "/" + std::to_string(reg(HK70, L"Virtual Key")),
          std::to_string(chtMod) + "/" + std::to_string(chtVk));
    Check("hotkeys taken over", taken, "0/0/1/3");
    Check("hotkeys restored to the live baseline", std::to_string(back ? 1 : 0) + "/" + restored, "1/" + before);
    Check("hotkey backups removed",
          std::to_string(GetFileAttributesW(bp.c_str()) != INVALID_FILE_ATTRIBUTES ? 1 : 0) + "/" +
              std::to_string(GetFileAttributesW(cbp.c_str()) != INVALID_FILE_ATTRIBUTES ? 1 : 0),
          "0/0");
    // Backup must be proven before a binding is cleared: with the backup path blocked (a directory
    // of the same name, so the write fails), takeover leaves Windows' own bindings untouched.
    CreateDirectoryW(bp.c_str(), nullptr);
    CreateDirectoryW(cbp.c_str(), nullptr);
    kx::TakeOverHotkeys();
    std::string blocked = state();
    long blocked70 = reg(HK70, L"Virtual Key");
    RemoveDirectoryW(bp.c_str());
    RemoveDirectoryW(cbp.c_str());
    Check("backup write fails: bindings untouched", blocked + "/" + std::to_string(blocked70),
          before + "/" + std::to_string(chtVk));
    if (blocked != before) kx::RestoreHotkeys();
    // Mac re-review P2: a malformed backup must fail closed: restore reports false, writes nothing
    // from it and keeps the file (the user's original may still be recoverable by hand).
    auto put = [](const std::wstring &p, const char *s) {
      FILE *f = _wfopen(p.c_str(), L"wb");
      if (f) { fputs(s, f); fclose(f); }
    };
    auto exists = [](const std::wstring &p) { return GetFileAttributesW(p.c_str()) != INVALID_FILE_ATTRIBUTES; };
    char valid[200];
    snprintf(valid, sizeof valid,
             "{\n \"modifiers\": %ld,\n \"virtual_key\": %ld,\n \"language_hotkey\": %ld,\n \"layout_hotkey\": %ld\n}\n",
             reg(HK, L"Key Modifiers"), reg(HK, L"Virtual Key"), reg(TOG, L"Language Hotkey"), reg(TOG, L"Layout Hotkey"));
    put(cbp, "{\n \"cht_modifiers\": 99999999999,\n \"cht_virtual_key\": 32\n}\n");
    put(bp, valid);
    bool r1 = kx::RestoreHotkeys();
    Check("malformed CHT backup: restore false, file kept, 0x70 untouched",
          std::to_string(r1) + "/" + std::to_string(exists(cbp)) + "/" + std::to_string(reg(HK70, L"Virtual Key")),
          "0/1/" + std::to_string(chtVk));
    DeleteFileW(cbp.c_str());
    DeleteFileW(bp.c_str());
    put(bp, "{\n \"modifiers\": 0,\n \"virtual_key\": 0,\n \"language_hotkey\": 1\n}\n");  // field missing
    bool r2 = kx::RestoreHotkeys();
    Check("malformed main backup: restore false, file kept, bindings untouched",
          std::to_string(r2) + "/" + std::to_string(exists(bp)) + "/" + state(), "0/1/" + before);
    DeleteFileW(bp.c_str());
    put(bp, "{\n \"modifiers\": 0,\n \"virtual_key\": 0,\n \"language_hotkey\": 1\n}\n");
    kx::TakeOverHotkeys();  // an invalid existing backup is rewritten from live values, never trusted
    Check("takeover rewrites a malformed backup", std::to_string(kx::RestoreHotkeys()) + "/" + state(), "1/" + before);
    DeleteFileW(bp.c_str());
    DeleteFileW(cbp.c_str());
  }
  // 0.1.7 language bar button: text and GDI icon follow ascii_mode, and the button is a tray item.
  {
    bool ascii = false;
    LangBar lb(GUID{}, [&] { return ascii; }, [] {});
    TF_LANGBARITEMINFO info = {};
    lb.GetInfo(&info);
    BSTR zh = nullptr;
    lb.GetText(&zh);
    HICON iz = nullptr;
    lb.GetIcon(&iz);
    int lz = LightPixels(iz);
    ascii = true;
    BSTR en = nullptr;
    lb.GetText(&en);
    HICON ie = nullptr;
    lb.GetIcon(&ie);
    int le = LightPixels(ie);
    Check("langbar text zh/en", kx::Utf8(zh) + "/" + kx::Utf8(en), "\xe4\xb8\xad/\xe8\x8b\xb1");
    Check("langbar icon drawn", std::to_string(iz != nullptr) + "/" + std::to_string(ie != nullptr) + "/" +
                                   std::to_string(lz > 10) + "/" + std::to_string(le > 10),
          "1/1/1/1");
    Check("langbar style", std::to_string((info.dwStyle & TF_LBI_STYLE_SHOWNINTRAY) != 0) + "/" +
                               std::to_string((info.dwStyle & TF_LBI_STYLE_BTN_BUTTON) != 0),
          "1/1");
    SysFreeString(zh);
    SysFreeString(en);
  }
  for (const char *size : {"5", "9"}) {
    Sleep(1100);
    std::ofstream(kx::UserDir() + L"\\settings.json") << "{\"page_size\": " << size << "}";
    Check("KxDeploy", std::to_string(KxDeploy()), "1");
    Type("vd", &n);
    Check(std::string("vd shows ") + size, std::to_string(n), size);
  }
  Check("bad settings fall back", kx::Load(L"Z:\\nope.json")["page_size"], "9");
  Check("unknown value dropped", [] {
    std::ofstream(kx::UserDir() + L"\\bad.json") << "{\"page_size\": 7, \"english_space\": \"long\"}";
    auto v = kx::Load(kx::UserDir() + L"\\bad.json");
    return v["page_size"] + "/" + v["english_space"];
  }(), "9/long");
  Check("hotkeys at exit equal start (incl. ImmGetHotKey 0x70)", LiveHotkeys(), hotkeysAtStart);
  if (gaps) printf("%d SHARED GAP (open, owned by the shared engine; not a pass)\n", gaps);
  printf(fails ? "%d FAIL\n" : "ALL PASS (Windows)\n", fails);
  return fails ? 1 : 0;
}
