// KINFX Input TSF text service (keyboard TIP, zh-TW). No Weasel / 小狼毫 involved.
#include <windows.h>
#include <msctf.h>
#include <olectl.h>
#include <functional>
#include <string>
#include <vector>
#include "chord.h"
#include "core.h"
#include "langbar.h"

HINSTANCE g_hinst;
static LONG g_refs = 0;

// {42EBBC99-2AAD-4AF6-A8D9-2552AD948ED3}
static const CLSID CLSID_KX = {0x42ebbc99, 0x2aad, 0x4af6, {0xa8, 0xd9, 0x25, 0x52, 0xad, 0x94, 0x8e, 0xd3}};
// {35BE04B0-E9E0-4E06-8438-10BFDCAE9E41}
static const GUID PROFILE_KX = {0x35be04b0, 0xe9e0, 0x4e06, {0x84, 0x38, 0x10, 0xbf, 0xdc, 0xae, 0x9e, 0x41}};
static const LANGID LANG_KX = MAKELANGID(LANG_CHINESE, SUBLANG_CHINESE_TRADITIONAL);  // 0x0404
static const wchar_t *NAME = L"KINFX Input";

// ---------- trace (KX_TRACE=1 or file "trace-on" in the user dir) ----------
static bool TraceOn() {
  static int on = -1;
  if (on < 0) on = GetFileAttributesW((kx::UserDir() + L"\\trace-on").c_str()) != INVALID_FILE_ATTRIBUTES;
  return on == 1;
}
static void Trace(const std::string &s) {
  if (!TraceOn()) return;
  // One handle kept open: re-opening per line fails whenever a scanner holds the file, and a
  // dropped line is worse than a leaked handle in a process that traces anyway.
  static HANDLE h = INVALID_HANDLE_VALUE;
  if (h == INVALID_HANDLE_VALUE)
    h = CreateFileW((kx::UserDir() + L"\\log\\kx-trace.log").c_str(), FILE_APPEND_DATA,
                    FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_ALWAYS, 0, nullptr);
  if (h == INVALID_HANDLE_VALUE) return;
  std::string line = s + "\r\n";
  DWORD n;
  WriteFile(h, line.data(), (DWORD)line.size(), &n, nullptr);
}

static std::string Hex(const std::string &s) {
  std::string o;
  char b[4];
  for (unsigned char c : s.substr(0, 24)) { snprintf(b, sizeof b, "%02x", c); o += b; }
  return o;
}

// ---------- key mapping: Windows virtual key -> Rime keysym + mask ----------
static const int kShift = 1, kLock = 2, kControl = 4, kAlt = 8, kRelease = 1 << 30;

static int Mask() {
  int m = 0;
  if (GetKeyState(VK_SHIFT) & 0x8000) m |= kShift;
  if (GetKeyState(VK_CAPITAL) & 1) m |= kLock;
  if (GetKeyState(VK_CONTROL) & 0x8000) m |= kControl;
  if (GetKeyState(VK_MENU) & 0x8000) m |= kAlt;
  return m;
}

// KINFX only sees these keys because core.cpp switches Windows' own bindings off (PreserveKey
// registers fine but OnPreservedKey is never dispatched, so there is nothing to claim).
static int ChordBit(WPARAM w) {
  switch (w) {
    case VK_SHIFT: case VK_LSHIFT: case VK_RSHIFT: return KxChord::kShift;
    case VK_CONTROL: case VK_LCONTROL: case VK_RCONTROL: return KxChord::kCtrl;
    case VK_MENU: case VK_LMENU: case VK_RMENU: return KxChord::kAlt;
  }
  return 0;  // Win and every other key cancel a chord
}

static int KeySym(WPARAM vk, LPARAM lp) {
  switch (vk) {
    case VK_RETURN: return 0xff0d;
    case VK_BACK: return 0xff08;
    case VK_ESCAPE: return 0xff1b;
    case VK_TAB: return 0xff09;
    case VK_SPACE: return 0x20;
    case VK_LEFT: return 0xff51;
    case VK_UP: return 0xff52;
    case VK_RIGHT: return 0xff53;
    case VK_DOWN: return 0xff54;
    case VK_PRIOR: return 0xff55;
    case VK_NEXT: return 0xff56;
    case VK_HOME: return 0xff50;
    case VK_END: return 0xff57;
    case VK_DELETE: return 0xffff;
    case VK_SHIFT: return ((lp >> 16) & 0xff) == 0x36 ? 0xffe2 : 0xffe1;
    case VK_LSHIFT: return 0xffe1;
    case VK_RSHIFT: return 0xffe2;
  }
  BYTE ks[256];
  if (!GetKeyboardState(ks)) return 0;
  ks[VK_CONTROL] = ks[VK_MENU] = 0;  // Rime wants the base character
  wchar_t buf[4];
  int n = ToUnicode((UINT)vk, (UINT)((lp >> 16) & 0xff), ks, buf, 4, 4 /* no dead-key state change */);
  if (n == 1 && buf[0] >= 0x20 && buf[0] < 0x7f) return buf[0];
  return 0;
}

// ---------- candidate window ----------
class CandWin {
 public:
  void Show(const std::vector<std::wstring> &items, POINT at, int lineAbove, bool vertical) {
    if (!hwnd_) Create();
    hintOn_ = false;  // a real candidate list takes the window back from the mode hint
    items_ = items;
    vertical_ = vertical;
    // The window lives in the host app's thread: GetDpiForWindow is 96 in DPI-unaware apps (Windows
    // stretches the window itself), the system DPI in system-aware ones, the monitor's in per-monitor ones.
    SetWindowPos(hwnd_, HWND_TOPMOST, at.x, at.y, 0, 0, SWP_NOSIZE | SWP_NOACTIVATE);
    int dpi = (int)GetDpiForWindow(hwnd_);
    if (dpi != dpi_ || !font_) {
      if (font_) DeleteObject(font_);
      dpi_ = dpi;
      font_ = CreateFontW(-S(kFontPx), 0, 0, 0, FW_NORMAL, 0, 0, 0, DEFAULT_CHARSET, 0, 0, CLEARTYPE_QUALITY, 0, L"Microsoft JhengHei UI");
    }
    HDC dc = GetDC(hwnd_);
    HGDIOBJ old = SelectObject(dc, font_);
    int w = 0, h = 0;
    for (auto &s : items_) {
      SIZE sz;
      GetTextExtentPoint32W(dc, s.c_str(), (int)s.size(), &sz);
      lineH_ = sz.cy + S(8);
      if (vertical_) { w = max(w, (int)sz.cx); h += lineH_; }
      else { w += sz.cx + S(20); h = lineH_; }
    }
    SelectObject(dc, old);
    ReleaseDC(hwnd_, dc);
    int ww = w + S(28), wh = h + S(12);
    MONITORINFO mi = {sizeof mi};
    if (GetMonitorInfoW(MonitorFromPoint(at, MONITOR_DEFAULTTONEAREST), &mi)) {
      RECT wa = mi.rcWork;
      if (at.y + wh > wa.bottom) at.y = max(wa.top, at.y - lineAbove - 4 - wh);  // no room below: above the text line
      if (at.x + ww > wa.right) at.x = max(wa.left, wa.right - ww);
      if (at.x < wa.left) at.x = wa.left;
    }
    SetWindowPos(hwnd_, HWND_TOPMOST, at.x, at.y, ww, wh, SWP_NOACTIVATE | SWP_SHOWWINDOW);
    InvalidateRect(hwnd_, nullptr, TRUE);
  }
  void Hide() { if (hwnd_ && !hintOn_) ShowWindow(hwnd_, SW_HIDE); }  // the hint owns the window for its 400 ms
  // Mode hint ("中"/"英"): the candidate window for 400 ms, so the switch is visible without
  // a second window class and without touching the keyboard. The modifier-up that follows the
  // switch runs Update() -> Hide(), so the window is held until the timer fires.
  void Hint(const std::wstring &s, POINT at) {
    Show({s}, at, 20, true);
    hintOn_ = true;
    if (hwnd_) SetTimer(hwnd_, 1, 400, nullptr);
  }
  void Destroy() { if (hwnd_) DestroyWindow(hwnd_); hwnd_ = nullptr; if (font_) DeleteObject(font_); font_ = nullptr; }

 private:
  void Create() {
    static bool reg = false;
    if (!reg) {
      WNDCLASSW wc = {};
      wc.lpfnWndProc = Proc;
      wc.hInstance = g_hinst;
      wc.lpszClassName = L"KINFXInputCand";
      wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
      RegisterClassW(&wc);
      reg = true;
    }
    hwnd_ = CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, L"KINFXInputCand", L"", WS_POPUP | WS_BORDER,
                            0, 0, 10, 10, nullptr, nullptr, g_hinst, nullptr);
    SetWindowLongPtrW(hwnd_, GWLP_USERDATA, (LONG_PTR)this);
  }
  static LRESULT CALLBACK Proc(HWND h, UINT m, WPARAM w, LPARAM l) {
    if (m == WM_MOUSEACTIVATE) return MA_NOACTIVATE;
    if (m == WM_TIMER) {
      auto *self = (CandWin *)GetWindowLongPtrW(h, GWLP_USERDATA);
      if (self) self->hintOn_ = false;
      KillTimer(h, w);
      ShowWindow(h, SW_HIDE);
      return 0;  // end of the mode hint's 400 ms
    }
    if (m == WM_PAINT) {
      auto *self = (CandWin *)GetWindowLongPtrW(h, GWLP_USERDATA);
      PAINTSTRUCT ps;
      HDC dc = BeginPaint(h, &ps);
      RECT rc;
      GetClientRect(h, &rc);
      HBRUSH bg = CreateSolidBrush(RGB(0x2b, 0x26, 0x24));
      FillRect(dc, &rc, bg);
      DeleteObject(bg);
      SetBkMode(dc, TRANSPARENT);
      SetTextColor(dc, RGB(0xee, 0xe6, 0xdc));
      HGDIOBJ old = SelectObject(dc, self->font_);
      int x = self->S(14), y = self->S(6);
      for (auto &s : self->items_) {
        TextOutW(dc, x, y, s.c_str(), (int)s.size());
        if (self->vertical_) y += self->lineH_;
        else { SIZE sz; GetTextExtentPoint32W(dc, s.c_str(), (int)s.size(), &sz); x += sz.cx + self->S(20); }
      }
      SelectObject(dc, old);
      EndPaint(h, &ps);
      return 0;
    }
    return DefWindowProcW(h, m, w, l);
  }
  HWND hwnd_ = nullptr;
  HFONT font_ = nullptr;
  std::vector<std::wstring> items_;
  bool vertical_ = true;
  bool hintOn_ = false;  // the window is showing 中/英 and must survive the next Hide()
  int lineH_ = 24;
  int dpi_ = 0;
  static const int kFontPx = 24;  // px at 96 DPI (0.1.3: a fixed 18 px, never DPI-scaled)
  int S(int px) const { return MulDiv(px, dpi_ ? dpi_ : 96, 96); }
};

// ---------- edit session helper ----------
class EditSession : public ITfEditSession {
 public:
  explicit EditSession(std::function<void(TfEditCookie)> f) : f_(std::move(f)) {}
  STDMETHODIMP QueryInterface(REFIID r, void **p) override {
    if (r == IID_IUnknown || r == IID_ITfEditSession) { *p = this; AddRef(); return S_OK; }
    *p = nullptr;
    return E_NOINTERFACE;
  }
  STDMETHODIMP_(ULONG) AddRef() override { return ++ref_; }
  STDMETHODIMP_(ULONG) Release() override { ULONG r = --ref_; if (!r) delete this; return r; }
  STDMETHODIMP DoEditSession(TfEditCookie ec) override { f_(ec); return S_OK; }

 private:
  std::function<void(TfEditCookie)> f_;
  ULONG ref_ = 1;
};

// ---------- the text service ----------
class Tip : public ITfTextInputProcessorEx, public ITfKeyEventSink, public ITfCompositionSink {
 public:
  Tip() { InterlockedIncrement(&g_refs); }
  ~Tip() { InterlockedDecrement(&g_refs); }

  STDMETHODIMP QueryInterface(REFIID r, void **p) override {
    if (r == IID_IUnknown || r == IID_ITfTextInputProcessor || r == IID_ITfTextInputProcessorEx) *p = (ITfTextInputProcessorEx *)this;
    else if (r == IID_ITfKeyEventSink) *p = (ITfKeyEventSink *)this;
    else if (r == IID_ITfCompositionSink) *p = (ITfCompositionSink *)this;
    else { *p = nullptr; return E_NOINTERFACE; }
    AddRef();
    return S_OK;
  }
  STDMETHODIMP_(ULONG) AddRef() override { return ++ref_; }
  STDMETHODIMP_(ULONG) Release() override { ULONG r = --ref_; if (!r) delete this; return r; }

  STDMETHODIMP Activate(ITfThreadMgr *tm, TfClientId id) override { return ActivateEx(tm, id, 0); }
  STDMETHODIMP ActivateEx(ITfThreadMgr *tm, TfClientId id, DWORD) override {
    tm_ = tm; tm_->AddRef();
    id_ = id;
    ITfKeystrokeMgr *km;
    if (SUCCEEDED(tm_->QueryInterface(IID_ITfKeystrokeMgr, (void **)&km))) {
      km->AdviseKeyEventSink(id_, (ITfKeyEventSink *)this, TRUE);
      km->Release();
    }
    bool ok = kx::Start();
    Trace(std::string("activate started=") + (ok ? "1" : "0"));
    // Language bar button (中/英). The manager advises its ITfLangBarItemSink during AddItem, so the
    // item must already be alive: Init() is called on our own reference.
    ITfLangBarItemMgr *lb = nullptr;
    HRESULT lbh = tm_->QueryInterface(IID_ITfLangBarItemMgr, (void **)&lb);
    Trace("lb mgr hr=" + std::to_string((long)lbh));
    if (SUCCEEDED(lbh)) {
      lb_ = new LangBar(CLSID_KX, [this] { return sess_ && kx::AsciiMode(sess_); },
                        [this] { ClickLangBar(); }, [](const std::string &s) { Trace(s); });
      if (FAILED(lb_->Init(lb))) { lb_->Release(); lb_ = nullptr; Trace("langbar add failed"); }
      lb->Release();
    }
    if (sess_) { lbAscii_ = !kx::AsciiMode(sess_); SyncMode(); }  // initial 中/英 for the system indicator
    return S_OK;
  }
  STDMETHODIMP Deactivate() override {
    Trace("deactivate");
    if (lb_) {
      ITfLangBarItemMgr *lb;
      if (tm_ && SUCCEEDED(tm_->QueryInterface(IID_ITfLangBarItemMgr, (void **)&lb))) {
        lb_->Uninit(lb);
        lb->Release();
      }
      lb_->Release();
      lb_ = nullptr;
    }
    ITfKeystrokeMgr *km;
    if (tm_ && SUCCEEDED(tm_->QueryInterface(IID_ITfKeystrokeMgr, (void **)&km))) {
      km->UnadviseKeyEventSink(id_);
      km->Release();
    }
    if (sess_) { kx_destroy(sess_); sess_ = 0; }
    cand_.Destroy();
    if (comp_) { comp_->Release(); comp_ = nullptr; }
    if (tm_) { tm_->Release(); tm_ = nullptr; }
    return S_OK;
  }

  // ITfKeyEventSink. Rime is stateful, so the key is processed once in OnTest* and the
  // result reused by the following On* call for the same key.
  STDMETHODIMP OnSetFocus(BOOL fg) override {
    if (fg) kx::ReloadIfChanged();
    else cand_.Hide();
    return S_OK;
  }
  STDMETHODIMP OnTestKeyDown(ITfContext *c, WPARAM w, LPARAM l, BOOL *eaten) override {
    *eaten = Process(w, l, false);
    Tail(c);
    // Paste: claim it here so OnKeyDown runs (sync edit session commits the held text), then OnKeyDown passes it to the app.
    if (paste_) *eaten = TRUE;
    return S_OK;
  }
  STDMETHODIMP OnTestKeyUp(ITfContext *c, WPARAM w, LPARAM l, BOOL *eaten) override {
    *eaten = Process(w, l, true);
    Tail(c);
    return S_OK;
  }
  STDMETHODIMP OnKeyDown(ITfContext *c, WPARAM w, LPARAM l, BOOL *eaten) override { *eaten = Handle(c, w, l, false); return S_OK; }
  STDMETHODIMP OnKeyUp(ITfContext *c, WPARAM w, LPARAM l, BOOL *eaten) override { *eaten = Handle(c, w, l, true); return S_OK; }
  // No preserved keys are claimed (see the note at ChordBit); the interface still needs this.
  STDMETHODIMP OnPreservedKey(ITfContext *, REFGUID, BOOL *eaten) override {
    *eaten = FALSE;
    return S_OK;
  }

  STDMETHODIMP OnCompositionTerminated(TfEditCookie ec, ITfComposition *) override {
    // The app ended the composition (click elsewhere): Rime commits what the user was typing
    // (F35 = blur key in english_mix.lua: an English run as letters, Sucheng as Return gives),
    // and that text replaces the preedit, so nothing typed disappears.
    std::wstring commit;
    if (sess_) {
      kx_key(sess_, 0xffe0, 0);
      char *raw = kx_take_commit(sess_);
      commit = raw ? kx::Wide(raw) : L"";
      free(raw);
      kx_clear(sess_);
    }
    if (comp_) {
      ITfRange *r;
      HRESULT g = comp_->GetRange(&r), h = E_FAIL;
      if (SUCCEEDED(g)) { h = r->SetText(ec, 0, commit.c_str(), (LONG)commit.size()); r->Release(); }
      Trace("blur commit [" + kx::Utf8(commit) + "] range=" + std::to_string(g) + " set=" + std::to_string(h));
      comp_->Release();
      comp_ = nullptr;
    }
    cand_.Hide();
    return S_OK;
  }

 private:
  bool Session() {
    if (!kx::Started()) return false;
    if (!sess_ || !kx_alive(sess_)) sess_ = kx_session("kinfx_quick");
    return sess_ != 0;
  }

  // A switch the sink ate in its own test path gets no OnKeyDown/OnKeyUp (TSF stops after the
  // eaten test), so the commit and the hint have to happen right there: an open preedit would
  // otherwise be cancelled by the app and the typed text lost.
  void Tail(ITfContext *c) {
    if (!switch_) return;
    switch_ = false;
    Update(c);
    if (hint_) { hint_ = false; ShowHint(); }
  }

  bool Process(WPARAM w, LPARAM l, bool up) {
    // The remembered result belongs to the On* call that follows its OnTest* — and an eaten switch
    // gets none (TSF stops after the test), so a pending Ctrl+Space must not answer the next one.
    if (pending_) {
      bool same = pendW_ == w && pendUp_ == up;
      pending_ = false;
      if (same) return pendEaten_;
    }
    int sym = KeySym(w, l), mask = Mask();
    bool modKey = sym >= 0xffe1 && sym <= 0xffe2;
    // Shortcuts with Ctrl/Alt go to the app; Shift taps reach Rime (english_mix).
    // Ctrl+V while a preedit shows goes to Rime first (0.1.2): held top-outs commit, letters drop, app pastes.
    // No preedit (e.g. association list after a pick) keeps the app paste, so Lua never shells out for the clipboard.
    bool paste = comp_ && (sym == 'v' || sym == 'V') && (mask & (kControl | kAlt)) == kControl;
    paste_ = paste && !up;
    // Bare Ctrl+Shift: the chord is complete on the last modifier release. Nothing synthetic is
    // sent: Rime's key_binder is fed Control+space directly.
    bool chord = chord_.Event(ChordBit(w), up);
    if (chord) Trace("chord toggles ascii");
    // Ctrl+Space is the Chinese/English switch: key_binder owns it, the shell only passes the key.
    bool toggle = sym == 0x20 && (mask & kControl) && !(mask & kAlt);
    bool eaten = false;
    if (chord || (toggle && !up)) {
      eaten = ToggleAscii();
      switch_ = true;  // committed and hinted in Tail: this key never reaches OnKeyDown
      pending_ = true; pendW_ = w; pendUp_ = up; pendEaten_ = eaten;
    } else if (sym && (paste || !(mask & (kControl | kAlt))) && Session() && (!up || modKey)) {
      int m = modKey ? mask & ~kShift : mask;  // Rime gets the Shift key itself, not Shift as a modifier
      eaten = kx_key(sess_, sym, m | (up ? kRelease : 0)) != 0;
      Trace("key sym=" + std::to_string(sym) + " m=" + std::to_string(m) + (up ? " up" : "") + " eaten=" + (eaten ? "1" : "0"));
      pending_ = true; pendW_ = w; pendUp_ = up; pendEaten_ = eaten;
    }
    return eaten;
  }

  // Rime owns ascii_mode. A live composition must be closed first: with one open,
  // ascii_composer keeps the key inline, so the first letters typed after the switch
  // were swallowed. Return commits the preedit (confirm; Space pages the Sucheng list),
  // Escape closes the association list a commit leaves open.
  bool ToggleAscii() {
    if (!Session()) return false;
    bool pre = comp_ != nullptr, list = cands_;
    if (pre) kx_key(sess_, 0xff0d, 0);
    if (pre || list) kx_key(sess_, 0xff1b, 0);
    bool eaten = kx_key(sess_, 0x20, kControl) != 0;
    hint_ = true;  // 中 / 英 for 400 ms: the user cannot see the mode anywhere else
    Trace(std::string("toggle ascii preedit=") + (pre ? "1" : "0") + " list=" + (list ? "1" : "0") + " eaten=" + (eaten ? "1" : "0"));
    return eaten;
  }

  // Language bar click: same switch as Ctrl+Space, plus the hint (there is no key to trigger it).
  void ClickLangBar() {
    if (!Session()) return;
    ToggleAscii();
    hint_ = false;
    ShowHint();
    SyncMode();
  }

  // 中/英 in the language bar follows ascii_mode whatever changed it (Ctrl+Space, Ctrl+Shift,
  // Shift+Space inside Rime, or a click on the button). Only a real change notifies the manager.
  void SyncMode() {
    if (!sess_) return;
    bool a = kx::AsciiMode(sess_);
    if (a == lbAscii_) return;
    lbAscii_ = a;
    SetConversion(a);
    if (lb_) lb_->Refresh();
    Trace(std::string("langbar ") + (a ? "en" : "zh"));
  }

  // The system's own indicator (tray box, and the 中/英 badge next to the caret) reads the
  // conversion-mode compartment; with it unset Windows keeps the profile icon (the K tile).
  void SetConversion(bool ascii) {
    if (!tm_) return;
    ITfCompartmentMgr *cm;
    ITfCompartment *c;
    if (FAILED(tm_->QueryInterface(IID_ITfCompartmentMgr, (void **)&cm))) return;
    if (SUCCEEDED(cm->GetCompartment(GUID_COMPARTMENT_KEYBOARD_INPUTMODE_CONVERSION, &c))) {
      VARIANT v;
      VariantInit(&v);
      if (SUCCEEDED(c->GetValue(&v))) {
        LONG f = v.vt == VT_I4 ? v.lVal : 0;
        VariantClear(&v);
        v.vt = VT_I4;
        v.lVal = ascii ? (f & ~TF_CONVERSIONMODE_NATIVE) : (f | TF_CONVERSIONMODE_NATIVE);
        Trace("conversion " + std::to_string((long)v.lVal) + " hr=" + std::to_string((long)c->SetValue(id_, &v)));
        VariantClear(&v);
      }
      c->Release();
    }
    cm->Release();
  }

  // Screen point under the caret, for when TSF gave no text extent.
  POINT CaretAt(int *lineH) {
    POINT at = {-1, -1};
    GetCaretPos(&at);
    HWND fw = GetFocus();
    if (fw) ClientToScreen(fw, &at);
    at.y += 24;
    *lineH = 24;
    return at;
  }

  void ShowHint() {
    std::wstring s = kx::AsciiMode(sess_) ? L"英" : L"中";
    int h = 0;
    POINT at = last_.x >= 0 ? last_ : CaretAt(&h);
    cand_.Hint(s, at);
    Trace("hint [" + kx::Utf8(s) + "]");
  }

  bool Handle(ITfContext *c, WPARAM w, LPARAM l, bool up) {
    bool eaten = Process(w, l, up);
    pending_ = false;
    // Update the document even for keys Rime let through: e.g. Return after a pick
    // closes the association list (Rime state changed) and must still reach the app.
    Update(c);
    if (hint_) { hint_ = false; ShowHint(); }
    if (paste_ && !up) {
      // TSF already ate this Ctrl+V (OnTestKeyDown); the held text is written, composition closed,
      // so a re-sent V reaches the app as a plain paste (paste_ needs comp_, now null).
      paste_ = false;
      INPUT in[4] = {};
      int n = 0;
      bool ctrl = (GetAsyncKeyState(VK_CONTROL) & 0x8000) != 0;  // async: a fast Ctrl release is already queued ahead of us
      if (!ctrl) { in[n].type = INPUT_KEYBOARD; in[n++].ki.wVk = VK_CONTROL; }
      in[n].type = INPUT_KEYBOARD; in[n++].ki.wVk = 'V';
      in[n].type = INPUT_KEYBOARD; in[n].ki.wVk = 'V'; in[n++].ki.dwFlags = KEYEVENTF_KEYUP;
      if (!ctrl) { in[n].type = INPUT_KEYBOARD; in[n].ki.wVk = VK_CONTROL; in[n++].ki.dwFlags = KEYEVENTF_KEYUP; }
      SendInput(n, in, sizeof(INPUT));
      return true;
    }
    return eaten;
  }

  void Update(ITfContext *c) {
    if (!sess_) return;
    SyncMode();
    char *raw = kx_take_commit(sess_);
    std::wstring commit = raw ? kx::Wide(raw) : L"";
    free(raw);
    raw = kx_context(sess_);
    std::string ctx = raw ? raw : "";
    free(raw);
    // fields joined by 0x1f: preedit, cursor, page_size, page_no, is_last, highlighted, candidates (text 0x1e comment)
    std::vector<std::string> f;
    size_t p = 0;
    for (size_t q; (q = ctx.find('\x1f', p)) != std::string::npos; p = q + 1) f.push_back(ctx.substr(p, q - p));
    f.push_back(ctx.substr(p));
    std::wstring pre = f.empty() ? L"" : kx::Wide(f[0]);
    std::vector<std::wstring> cands;
    for (size_t i = 6; i < f.size(); i++) {
      std::string t = f[i], cm;
      size_t s = t.find('\x1e');
      if (s != std::string::npos) { cm = t.substr(s + 1); t = t.substr(0, s); }
      cands.push_back(std::to_wstring((cands.size() + 1) % 10) + L". " + kx::Wide(t) + (cm.empty() ? L"" : L" " + kx::Wide(cm)));
    }
    if (!commit.empty()) Trace("commit [" + kx::Utf8(commit) + "]");
    if (!cands.empty()) Trace("view page=" + (f.size() > 2 ? f[2] : "") + " n=" + std::to_string(cands.size()) + " pre=[" + f[0] + "] raw=[" + Hex(f.size() > 6 ? f[6] : "") + "]");
    cands_ = !cands.empty();  // the association list a pick leaves open counts as candidates
    POINT at = {-1, -1};
    int lineH = 0;
    auto *es = new EditSession([&](TfEditCookie ec) { Write(ec, c, commit, pre, &at, &lineH); });
    HRESULT hr;
    c->RequestEditSession(id_, es, TF_ES_SYNC | TF_ES_READWRITE, &hr);
    es->Release();
    if (cands.empty()) { cand_.Hide(); return; }
    if (at.x < 0 && last_.x >= 0) { at = last_; lineH = lastH_; }  // TSF gave no extent: stay where the preedit was
    if (at.x < 0) at = CaretAt(&lineH);
    auto it = kx::Current().find("candidate_layout");
    cand_.Show(cands, at, lineH, it == kx::Current().end() || it->second != "horizontal");
  }

  // Commit text and/or preedit through one TSF composition.
  void Write(TfEditCookie ec, ITfContext *c, const std::wstring &commit, const std::wstring &pre, POINT *at, int *lineH) {
    if (!commit.empty()) {
      if (!comp_) Begin(ec, c);
      if (comp_) {
        ITfRange *r;
        if (SUCCEEDED(comp_->GetRange(&r))) {
          r->SetText(ec, 0, commit.c_str(), (LONG)commit.size());
          r->Collapse(ec, TF_ANCHOR_END);
          SetSel(ec, c, r);
          r->Release();
        }
        comp_->EndComposition(ec);
        comp_->Release();
        comp_ = nullptr;
      }
    }
    if (pre.empty()) {
      if (comp_) {
        ITfRange *r;
        if (SUCCEEDED(comp_->GetRange(&r))) { r->SetText(ec, 0, L"", 0); r->Release(); }
        comp_->EndComposition(ec);
        comp_->Release();
        comp_ = nullptr;
      }
      TF_SELECTION sel = {};
      ULONG n = 0;
      if (SUCCEEDED(c->GetSelection(ec, TF_DEFAULT_SELECTION, 1, &sel, &n)) && n == 1 && sel.range) {
        Below(ec, c, sel.range, at, lineH);
        sel.range->Release();
      }
      return;
    }
    if (!comp_) Begin(ec, c);
    if (!comp_) return;
    ITfRange *r;
    if (FAILED(comp_->GetRange(&r))) return;
    r->SetText(ec, 0, pre.c_str(), (LONG)pre.size());
    ITfRange *end;
    if (SUCCEEDED(r->Clone(&end))) { end->Collapse(ec, TF_ANCHOR_END); SetSel(ec, c, end); end->Release(); }
    Below(ec, c, r, at, lineH);
    r->Release();
  }

  // Screen point just below a text range, from the app's TSF view.
  void Below(TfEditCookie ec, ITfContext *c, ITfRange *r, POINT *at, int *lineH) {
    ITfContextView *v;
    if (FAILED(c->GetActiveView(&v))) return;
    RECT rc;
    BOOL clipped;
    if (SUCCEEDED(v->GetTextExt(ec, r, &rc, &clipped)) && (rc.left || rc.bottom)) {
      at->x = rc.left; at->y = rc.bottom + 2;
      *lineH = rc.bottom - rc.top;
      last_ = *at; lastH_ = *lineH;
    }
    v->Release();
  }

  void Begin(TfEditCookie ec, ITfContext *c) {
    ITfInsertAtSelection *ins;
    ITfContextComposition *cc;
    if (FAILED(c->QueryInterface(IID_ITfInsertAtSelection, (void **)&ins))) return;
    ITfRange *r = nullptr;
    if (SUCCEEDED(ins->InsertTextAtSelection(ec, TF_IAS_QUERYONLY, nullptr, 0, &r)) &&
        SUCCEEDED(c->QueryInterface(IID_ITfContextComposition, (void **)&cc))) {
      cc->StartComposition(ec, r, (ITfCompositionSink *)this, &comp_);
      cc->Release();
    }
    if (r) r->Release();
    ins->Release();
  }

  static void SetSel(TfEditCookie ec, ITfContext *c, ITfRange *r) {
    TF_SELECTION s = {};
    s.range = r;
    s.style.ase = TF_AE_NONE;
    s.style.fInterimChar = FALSE;
    c->SetSelection(ec, 1, &s);
  }

  ULONG ref_ = 1;
  ITfThreadMgr *tm_ = nullptr;
  TfClientId id_ = 0;
  uintptr_t sess_ = 0;
  ITfComposition *comp_ = nullptr;
  POINT last_ = {-1, -1};
  int lastH_ = 0;
  CandWin cand_;
  LangBar *lb_ = nullptr;
  bool lbAscii_ = false;  // mode the language bar is showing
  KxChord chord_;
  bool hint_ = false;  // a mode switch is waiting to be shown after the next Update
  bool switch_ = false;  // a mode switch happened in the test path: Tail() commits it
  bool pending_ = false, pendUp_ = false, pendEaten_ = false, paste_ = false;
  bool cands_ = false;  // candidates (incl. the association list) were showing on the last update
  WPARAM pendW_ = 0;
};

// ---------- COM plumbing ----------
class Factory : public IClassFactory {
 public:
  STDMETHODIMP QueryInterface(REFIID r, void **p) override {
    if (r == IID_IUnknown || r == IID_IClassFactory) { *p = this; return S_OK; }
    *p = nullptr;
    return E_NOINTERFACE;
  }
  STDMETHODIMP_(ULONG) AddRef() override { return 2; }
  STDMETHODIMP_(ULONG) Release() override { return 1; }
  STDMETHODIMP CreateInstance(IUnknown *outer, REFIID r, void **p) override {
    if (outer) return CLASS_E_NOAGGREGATION;
    Tip *t = new Tip();
    HRESULT hr = t->QueryInterface(r, p);
    t->Release();
    return hr;
  }
  STDMETHODIMP LockServer(BOOL lock) override { lock ? InterlockedIncrement(&g_refs) : InterlockedDecrement(&g_refs); return S_OK; }
};
static Factory g_factory;

BOOL WINAPI DllMain(HINSTANCE h, DWORD reason, LPVOID) {
  if (reason == DLL_PROCESS_ATTACH) { g_hinst = h; DisableThreadLibraryCalls(h); }
  return TRUE;
}

STDAPI DllGetClassObject(REFCLSID c, REFIID r, void **p) {
  if (c == CLSID_KX) return g_factory.QueryInterface(r, p);
  *p = nullptr;
  return CLASS_E_CLASSNOTAVAILABLE;
}

STDAPI DllCanUnloadNow() { return g_refs ? S_FALSE : S_OK; }

static std::wstring ClsidKey() {
  wchar_t g[64];
  StringFromGUID2(CLSID_KX, g, 64);
  return std::wstring(L"CLSID\\") + g;
}

STDAPI DllRegisterServer() {
  wchar_t path[MAX_PATH];
  GetModuleFileNameW(g_hinst, path, MAX_PATH);
  HKEY k;
  if (RegCreateKeyExW(HKEY_CLASSES_ROOT, (ClsidKey() + L"\\InprocServer32").c_str(), 0, nullptr, 0, KEY_WRITE, nullptr, &k, nullptr))
    return SELFREG_E_CLASS;
  RegSetValueExW(k, nullptr, 0, REG_SZ, (BYTE *)path, (DWORD)(wcslen(path) + 1) * 2);
  RegSetValueExW(k, L"ThreadingModel", 0, REG_SZ, (BYTE *)L"Apartment", 20);
  RegCloseKey(k);

  ITfInputProcessorProfileMgr *pm;
  if (FAILED(CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER, IID_ITfInputProcessorProfileMgr, (void **)&pm)))
    return E_FAIL;
  HRESULT hr = pm->RegisterProfile(CLSID_KX, LANG_KX, PROFILE_KX, NAME, (ULONG)wcslen(NAME), path, (ULONG)wcslen(path), 0, nullptr, 0, TRUE, 0);
  pm->Release();
  if (FAILED(hr)) return hr;

  ITfCategoryMgr *cm;
  if (FAILED(CoCreateInstance(CLSID_TF_CategoryMgr, nullptr, CLSCTX_INPROC_SERVER, IID_ITfCategoryMgr, (void **)&cm))) return E_FAIL;
  for (const GUID *cat : {&GUID_TFCAT_TIP_KEYBOARD, &GUID_TFCAT_TIPCAP_IMMERSIVESUPPORT, &GUID_TFCAT_TIPCAP_SYSTRAYSUPPORT,
                          &GUID_TFCAT_TIPCAP_SECUREMODE, &GUID_TFCAT_TIPCAP_COMLESS})
    cm->RegisterCategory(CLSID_KX, *cat, CLSID_KX);
  cm->Release();
  return S_OK;
}

STDAPI DllUnregisterServer() {
  kx::RestoreHotkeys();  // give Ctrl+Space / Ctrl+Shift / Alt+Shift back to Windows
  ITfInputProcessorProfileMgr *pm;
  if (SUCCEEDED(CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER, IID_ITfInputProcessorProfileMgr, (void **)&pm))) {
    pm->UnregisterProfile(CLSID_KX, LANG_KX, PROFILE_KX, 0);
    pm->Release();
  }
  ITfCategoryMgr *cm;
  if (SUCCEEDED(CoCreateInstance(CLSID_TF_CategoryMgr, nullptr, CLSCTX_INPROC_SERVER, IID_ITfCategoryMgr, (void **)&cm))) {
    for (const GUID *cat : {&GUID_TFCAT_TIP_KEYBOARD, &GUID_TFCAT_TIPCAP_IMMERSIVESUPPORT, &GUID_TFCAT_TIPCAP_SYSTRAYSUPPORT,
                            &GUID_TFCAT_TIPCAP_SECUREMODE, &GUID_TFCAT_TIPCAP_COMLESS})
      cm->UnregisterCategory(CLSID_KX, *cat, CLSID_KX);
    cm->Release();
  }
  RegDeleteTreeW(HKEY_CLASSES_ROOT, ClsidKey().c_str());
  return S_OK;
}
