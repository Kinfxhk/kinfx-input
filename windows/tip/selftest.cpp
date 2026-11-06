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
  Check("start", kx::Start() ? "1" : "0", "1");
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
  // 0.1.8 punctuation: one key = one glyph and no candidate menu, so nothing ever asks the user to
  // pick 全形/半形. The shipped default is full shape (schema `full_shape reset: 1`), so the ASCII
  // keys must produce the 全形 table from engine/prelude/punctuation.yaml; Shift+Space switches to
  // 半形 and the same keys must give plain ASCII again (code and URLs must not break).
  {
    struct P { const char *keys; const wchar_t *want; };
    static const P full[] = {
        {" ", L"　"},
        {",", L"，"},
        {".", L"。"},
        {"?", L"？"},
        {"!", L"！"},
        {";", L"；"},
        {":", L"："},
        {"(", L"（"},
        {")", L"）"},
        {"[", L"「"},
        {"]", L"」"},
        {"{", L"『"},
        {"}", L"』"},
        {"<", L"《"},
        {">", L"》"},
        {"\\", L"、"},
        {"''", L"‘’"},
        {"\"\"", L"“”"},
        // Leading slash in a fresh ASCII context is a command leader (/init): half-width
        // (shared contract, english_mix.lua); after CJK it follows full_shape.
        {"/", L"/"},
        {"-", L"－"},
        {"_", L"＿"},
        {"+", L"＋"},
        {"=", L"＝"},
        {"~", L"～"},
        {"$", L"＄"},
        {"%", L"％"},
        {"@", L"＠"},
        {"#", L"＃"},
        {"^", L"＾"},
        {"&", L"＆"},
        {"*", L"＊"},
        {"|", L"｜"},
        {"`", L"｀"},
    };
    std::string bad;
    for (const P &p : full) {
      int c = 0;
      std::string out = Type(p.keys, &c);
      if (out != kx::Utf8(p.want) || c) bad += std::string(p.keys) + "=" + out + "/" + std::to_string(c) + " ";
    }
    Check("punct full (default): one glyph, no menu", bad.empty() ? "ok" : bad, "ok");
    s = kx_session("kinfx_quick");
    std::string shape;
    Check("Shift+Space eaten", std::to_string(kx_key(s, 0x20, 1)), "1");  // full -> half
    for (const char *k : {",", "/", "-", "*"}) { kx_key(s, *k, 0); shape += Take(s); }
    kx_key(s, 0x20, 1);  // half -> full
    // A slash is not used here: a leading slash stays half-width by contract (/init), and the
    // half row leaves a Latin punctuation tail that is the shared owner's to define.
    // Punctuation straight after half punctuation keeps that Latin tail (shared english_mix), so
    // the full row is proved after Chinese, the same vector as tools/test-contextual-punctuation.py.
    for (const char *k : {"v", "d", "1", ","}) { kx_key(s, *k, 0); shape += Take(s); }
    Check("half shape, then full again", shape, ",/-*\xe5\xa5\xbd\xef\xbc\x8c");
    kx_destroy(s);
    // 全形/半形 held user-wide (the TSF key path runs ApplyShape before and NoteShape after each
    // key): Shift+Space in app A, then a fresh session (app B, or A after switching back) stays half.
    {
      Check("shape: nothing chosen yet", std::to_string(kx::ShapeWanted()), "-1");
      uintptr_t a = kx_session("kinfx_quick");
      kx::ApplyShape(a);
      kx_key(a, 0x20, 1);  // Shift+Space: full -> half
      kx::NoteShape(a);
      Check("shape: Shift+Space held as half", std::to_string(kx::ShapeWanted()), "0");
      uintptr_t b = kx_session("kinfx_quick");  // new app: schema resets to full
      kx::ApplyShape(b);
      std::string got;
      for (const char *k : {"v", "d", "1", " ", ","}) { kx_key(b, *k == ' ' ? 0x20 : *k, 0); got += Take(b); kx::NoteShape(b); }
      Check("shape: other app keeps half (space U+0020)", got, "\xe5\xa5\xbd ,");
      kx::ApplyShape(a);  // back to app A
      got.clear();
      for (const char *k : {"v", "d", "1", " "}) { kx_key(a, *k == ' ' ? 0x20 : *k, 0); got += Take(a); }
      Check("shape: switching back keeps half", got, "\xe5\xa5\xbd ");
      kx_key(b, 0x20, 1);  // Shift+Space in B: half -> full
      kx::NoteShape(b);
      kx::ApplyShape(a);
      got.clear();
      for (const char *k : {"v", "d", "1", " "}) { kx_key(a, *k == ' ' ? 0x20 : *k, 0); got += Take(a); }
      Check("shape: full chosen in B reaches A (U+3000)", got, "\xe5\xa5\xbd\xe3\x80\x80");
      kx_destroy(a);
      kx_destroy(b);
    }
    // Handoff contract vectors the shared engine owns. Reported as GAP until the shared fix lands.
    auto run = [&](std::initializer_list<const char *> keys) {
      uintptr_t g = kx_session("kinfx_quick");
      std::string out;
      for (const char *k : keys) { kx_key(g, *k == ' ' ? 0x20 : *k, 0); out += Take(g); }
      kx_key(g, 0xff0d, 0);  // Return flushes a held tail
      out += Take(g);
      kx_destroy(g);
      return out;
    };
    Gap("shared: vd1 then '/' after CJK", run({"v", "d", "1", "/"}), "\xe5\xa5\xbd\xef\xbc\x8f");
    Gap("shared: 'hello. ' keeps ASCII space", run({"h", "e", "l", "l", "o", ".", " "}), "hello. ");
    Gap("shared: '60cm ' keeps ASCII space", run({"6", "0", "c", "m", " "}), "60cm ");
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
  // chord (both are REG_SZ; measured values). Start() already took them over, so the test puts the
  // recorded originals back and watches the takeover switch them off again, then checks the restore
  // (the uninstall path) returns the backup's values.
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
    auto set = [](const wchar_t *sub, const wchar_t *n, long v, bool str) {
      HKEY k;
      if (RegCreateKeyExW(HKEY_CURRENT_USER, sub, 0, nullptr, 0, KEY_SET_VALUE, nullptr, &k, nullptr)) return;
      if (v < 0) RegDeleteValueW(k, n);
      else if (str) { wchar_t s[8]; swprintf(s, 8, L"%ld", v); RegSetValueExW(k, n, 0, REG_SZ, (BYTE *)s, (DWORD)((wcslen(s) + 1) * 2)); }
      else RegSetValueExW(k, n, 0, REG_DWORD, (BYTE *)&v, 4);
      RegCloseKey(k);
    };
    auto state = [&] {
      return std::to_string(reg(HK, L"Key Modifiers")) + "/" + std::to_string(reg(HK, L"Virtual Key")) + "/" +
             std::to_string(reg(TOG, L"Language Hotkey")) + "/" + std::to_string(reg(TOG, L"Layout Hotkey"));
    };
    std::wstring bp = kx::UserDir() + L"\\hotkeys-backup.json";
    std::ifstream f(bp);
    std::string json((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
    f.close();  // an open handle blocks the restore's DeleteFile
    std::map<std::string, long> orig;
    std::string want;
    std::regex re("\"(modifiers|virtual_key|language_hotkey|layout_hotkey)\"\\s*:\\s*(-?[0-9]+)");
    for (std::sregex_iterator it(json.begin(), json.end(), re), end; it != end; ++it) orig[(*it)[1]] = std::stol((*it)[2]);
    if (json.empty()) want = "no backup";
    else {
      set(HK, L"Key Modifiers", orig["modifiers"], false);
      set(HK, L"Virtual Key", orig["virtual_key"], false);
      set(TOG, L"Language Hotkey", orig["language_hotkey"], true);
      set(TOG, L"Layout Hotkey", orig["layout_hotkey"], true);
      want = std::to_string(orig["modifiers"]) + "/" + std::to_string(orig["virtual_key"]) + "/" +
             std::to_string(orig["language_hotkey"]) + "/" + std::to_string(orig["layout_hotkey"]);
    }
    // CHT Ctrl+Space (IME hotkey 0x70) is cleared too; its original sits in hotkeys-backup-cht.json.
    const wchar_t *HK70 = L"Control Panel\\Input Method\\Hot Keys\\00000070";
    std::ifstream cf(kx::UserDir() + L"\\hotkeys-backup-cht.json");
    std::string cjson((std::istreambuf_iterator<char>(cf)), std::istreambuf_iterator<char>());
    cf.close();
    std::smatch cm;
    long chtVk = std::regex_search(cjson, cm, std::regex("\"cht_virtual_key\"\\s*:\\s*([0-9]+)")) ? std::stol(cm[1]) : reg(HK70, L"Virtual Key");
    kx::TakeOverHotkeys();
    std::string taken = state();                    // sequenced: an argument order would let state()
    long taken70 = reg(HK70, L"Virtual Key");
    bool back = kx::RestoreHotkeys();               // and the restore swap places
    std::string restored = state();
    Check("CHT Ctrl+Space hotkey off", std::to_string(taken70 <= 0 ? 0 : taken70), "0");
    Check("CHT Ctrl+Space hotkey restored", std::to_string(reg(HK70, L"Virtual Key")), std::to_string(chtVk));
    Check("hotkeys taken over", taken, "0/0/1/3");
    Check("hotkeys restored", std::to_string(back ? 1 : 0) + "/" + restored, "1/" + want);
    Check("hotkey backup removed", std::to_string(GetFileAttributesW(bp.c_str()) != INVALID_FILE_ATTRIBUTES ? 1 : 0), "0");
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
  if (gaps) printf("%d SHARED GAP (open, owned by the shared engine; not a pass)\n", gaps);
  printf(fails ? "%d FAIL\n" : "ALL PASS (Windows)\n", fails);
  return fails ? 1 : 0;
}
