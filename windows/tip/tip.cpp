// KINFX Input TSF text service (keyboard TIP, zh-TW). No Weasel / 小狼毫 involved.
#include <windows.h>
#include <msctf.h>
#include <olectl.h>
#include <functional>
#include <memory>
#include <string>
#include <vector>
#include "chord.h"
#include "core.h"
#include "display-caret.h"
#include "cand-place.h"
#include "caret-origin.h"
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
  void Show(const std::vector<std::wstring> &items, POINT at, int lineAbove, bool vertical,
            std::function<void(int)> pick = {}) {
    pick_ = std::move(pick); pressed_ = -1;
    if (!hwnd_) Create();
    hintOn_ = false;  // a real candidate list takes the window back from the mode hint
    KillTimer(hwnd_, 1);  // ... and the hint's 400 ms timer must not hide the list later
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
    int ww = 0, wh = 0;
    std::vector<int> widths;
    {
      HDC dc = GetDC(hwnd_);
      HGDIOBJ old = SelectObject(dc, font_);
      for (auto &s : items_) {
        SIZE sz;
        GetTextExtentPoint32W(dc, s.c_str(), (int)s.size(), &sz);
        lineH_ = sz.cy + S(8);
        widths.push_back((int)sz.cx);
      }
      SelectObject(dc, old);
      ReleaseDC(hwnd_, dc);
    }
    // Paint and hit-test share one cell layout (kx::FitCandidates), so a panel short of room
    // re-flows its candidates into that room instead of clipping them (Mac review 2026-11-06 P2).
    RECT wr0, cr0;
    GetWindowRect(hwnd_, &wr0); GetClientRect(hwnd_, &cr0);
    const int inset = max(0, (int)((wr0.right - wr0.left) - cr0.right) / 2);  // WS_BORDER per side
    const kx::CandGeom geom{lineH_, S(14), S(6), S(20), 2, inset};
    cells_ = kx::LayoutCells(widths, lineH_, vertical_, 1 << 30, 1 << 30, geom.padX, geom.padY, geom.gapX, &ww, &wh);
    ww += 2 * inset; wh += 2 * inset;
    MONITORINFO mi = {sizeof mi};
    if (GetMonitorInfoW(MonitorFromPoint(at, MONITOR_DEFAULTTONEAREST), &mi)) {
      RECT wa = mi.rcWork;
      // A tall vertical list below the caret reaches the next input of Qt/Electron forms, whose
      // fields are not separate windows: a click meant for that field picks a candidate instead
      // (x46: "vd" + click lower field -> upper field "妹好", lower field never focused). Tall
      // lists go above the text line when they fit; short ones stay below. A list that fits
      // neither way becomes one row, and it never covers the line being typed.
      const kx::Rect area{wa.left, wa.top, wa.right, wa.bottom};
      const kx::Rect caretLine{at.x, at.y - 2 - lineAbove, at.x + 8, at.y - 2};
      // A list that fits neither above nor below is re-flowed (one row first, then wrapped rows or
      // columns) inside the real room on one side of the caret; see kx::FitCandidates.
      POINT at2 = at;
      int how = -1, shown = 0;
      bool vert = vertical_;
      const int natW = ww, natH = wh;
      kx::Rect placed = kx::FitCandidates(widths, vertical_, caretLine, area, geom, &cells_, &shown, &how, &vert);
      vertical_ = vert;
      if (placed.Width() != natW || placed.Height() != natH || shown != (int)items_.size())
        Trace("cand relayout " + std::to_string(natW) + "x" + std::to_string(natH) + " -> " +
              std::to_string(placed.Width()) + "x" + std::to_string(placed.Height()) + " shown=" +
              std::to_string(shown) + "/" + std::to_string(items_.size()));
      at2.x = placed.left;
      at2.y = placed.top;
      at = at2;
      // PlaceCandidate may shrink the panel to the room it has: the window must use that size,
      // or it still spills past the work area (Mac review 2026-11-06).
      ww = placed.Width();
      wh = placed.Height();
      Trace("cand place=" + std::to_string(how) + " at=" + std::to_string(at.x) + "," + std::to_string(at.y) +
            " wh=" + std::to_string(ww) + "x" + std::to_string(wh));
    }
    SetWindowPos(hwnd_, HWND_TOPMOST, at.x, at.y, ww, wh, SWP_NOACTIVATE | SWP_SHOWWINDOW);
    // Some hosts (WebView2 panels such as Raycast's search, browser popups) hide their window
    // without a TSF focus change, so OnSetFocus(FALSE) never arrives and this topmost list stays
    // on screen over other apps (reported 2026-10-27). While the list is visible, watch the
    // host's foreground root and hide when it is no longer ours.
    HWND fg = GetForegroundWindow();
    fgRoot_ = fg ? GetAncestor(fg, GA_ROOT) : nullptr;
    if (fgRoot_) SetTimer(hwnd_, 2, 250, nullptr);
    InvalidateRect(hwnd_, nullptr, TRUE);
  }
  void Hide(bool force = false) {
    if (!hwnd_ || (hintOn_ && !force)) return;  // focus loss also cancels a mode hint
    pick_ = {}; pressed_ = -1;
    if (force) { hintOn_ = false; KillTimer(hwnd_, 1); items_.clear(); }
    KillTimer(hwnd_, 2);
    ShowWindow(hwnd_, SW_HIDE);
  }
  // Mode hint ("中"/"英"): the candidate window for 400 ms, so the switch is visible without
  // a second window class and without touching the keyboard. The modifier-up that follows the
  // switch runs Update() -> Hide(), so the window is held until the timer fires.
  void Hint(const std::wstring &s, POINT at) {
    Show({s}, at, 20, true);
    hintOn_ = true;
    if (hwnd_) SetTimer(hwnd_, 1, 400, nullptr);
  }
  void Destroy() {
    pick_ = {}; pressed_ = -1;
    if (hwnd_) { KillTimer(hwnd_, 1); KillTimer(hwnd_, 2); DestroyWindow(hwnd_); }
    hwnd_ = nullptr;
    if (font_) DeleteObject(font_); font_ = nullptr;
  }

 private:
  int HitItem(POINT pt) {
    if (hintOn_ || !pick_ || !IsWindowVisible(hwnd_) || !ScreenToClient(hwnd_, &pt)) return -1;
    RECT rc; GetClientRect(hwnd_, &rc);
    for (size_t i = 0; i < cells_.size() && i < items_.size(); ++i) {
      const kx::Rect &c = cells_[i];
      // Hidden cells are empty; a cell cut by the window edge only counts where it is visible.
      if (!kx::IsEmpty(c) && pt.x >= c.left && pt.x < c.right && pt.x < rc.right && pt.y >= c.top && pt.y < c.bottom && pt.y < rc.bottom)
        return (int)i;
    }
    return -1;
  }
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
    auto *self = (CandWin *)GetWindowLongPtrW(h, GWLP_USERDATA);
    if (m == WM_NCHITTEST) {
      POINT pt = {(short)LOWORD(l), (short)HIWORD(l)};
      return self && self->HitItem(pt) >= 0 ? HTCLIENT : HTTRANSPARENT;
    }
    if (m == WM_MOUSEACTIVATE) return MA_NOACTIVATE;
    if (m == WM_LBUTTONDOWN) {
      POINT pt; GetCursorPos(&pt); if (self) self->pressed_ = self->HitItem(pt); return 0;
    }
    if (m == WM_LBUTTONUP) {
      POINT pt; GetCursorPos(&pt);
      if (self) {
        int item = self->HitItem(pt), pressed = self->pressed_; self->pressed_ = -1;
        auto pick = self->pick_;  // callback may replace/destroy the window; no self access afterwards
        if (item >= 0 && item == pressed && pick) pick(item);
      }
      return 0;
    }
    if (m == WM_TIMER) {
      auto *self = (CandWin *)GetWindowLongPtrW(h, GWLP_USERDATA);
      if (w == 1) {
        if (self) self->hintOn_ = false;
        KillTimer(h, 1);
        KillTimer(h, 2);
        ShowWindow(h, SW_HIDE);
        return 0;  // end of the mode hint's 400 ms
      }
      if (w == 2 && self) {
        HWND fg = GetForegroundWindow();
        // A hidden host can still be the foreground window (Windows only moves it when another
        // window activates), so the window's own visibility counts as lost focus too.
        bool lost = !fg || GetAncestor(fg, GA_ROOT) != self->fgRoot_ || !IsWindowVisible(self->fgRoot_) || IsIconic(self->fgRoot_);
        if (lost) {
          KillTimer(h, 2);
          self->hintOn_ = false;
          ShowWindow(h, SW_HIDE);
          Trace("cand hidden: app lost foreground");
        }
        return 0;  // foreground watchdog
      }
      return 0;
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
      for (size_t i = 0; i < self->items_.size() && i < self->cells_.size(); ++i)
        if (!kx::IsEmpty(self->cells_[i]))  // hidden: does not fit even after re-flow
          TextOutW(dc, self->cells_[i].left, self->cells_[i].top, self->items_[i].c_str(), (int)self->items_[i].size());
      SelectObject(dc, old);
      EndPaint(h, &ps);
      return 0;
    }
    return DefWindowProcW(h, m, w, l);
  }
  HWND hwnd_ = nullptr;
  HFONT font_ = nullptr;
  std::vector<std::wstring> items_;
  std::vector<kx::Rect> cells_;  // client-space cell per item: the one layout paint and hit-test share
  std::function<void(int)> pick_;
  int pressed_ = -1;
  bool vertical_ = true;
  bool hintOn_ = false;  // the window is showing 中/英 and must survive the next Hide()
  HWND fgRoot_ = nullptr;  // foreground root the list was shown for (timer 2 hides when it changes)
  int lineH_ = 24;
  int dpi_ = 0;
  static const int kFontPx = 24;  // px at 96 DPI (0.1.3: a fixed 18 px, never DPI-scaled)
  int S(int px) const { return MulDiv(px, dpi_ ? dpi_ : 96, 96); }
};

// ---------- edit session helper ----------
class EditSession : public ITfEditSession {
 public:
  explicit EditSession(std::function<void(TfEditCookie)> f) : f_(std::move(f)) { InterlockedIncrement(&g_refs); }
  ~EditSession() { InterlockedDecrement(&g_refs); }
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
class Tip : public ITfTextInputProcessorEx, public ITfKeyEventSink, public ITfCompositionSink,
            public ITfThreadMgrEventSink, public ITfTextEditSink {
 public:
  Tip() { InterlockedIncrement(&g_refs); }
  ~Tip() { InterlockedDecrement(&g_refs); }

  STDMETHODIMP QueryInterface(REFIID r, void **p) override {
    if (r == IID_IUnknown || r == IID_ITfTextInputProcessor || r == IID_ITfTextInputProcessorEx) *p = (ITfTextInputProcessorEx *)this;
    else if (r == IID_ITfKeyEventSink) *p = (ITfKeyEventSink *)this;
    else if (r == IID_ITfCompositionSink) *p = (ITfCompositionSink *)this;
    else if (r == IID_ITfThreadMgrEventSink) *p = (ITfThreadMgrEventSink *)this;
    else if (r == IID_ITfTextEditSink) *p = (ITfTextEditSink *)this;
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
    ITfSource *source = nullptr;
    if (SUCCEEDED(tm_->QueryInterface(IID_ITfSource, (void **)&source))) {
      source->AdviseSink(IID_ITfThreadMgrEventSink, (ITfThreadMgrEventSink *)this, &threadCookie_);
      source->Release();
    }
    RefreshFocus();
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
    Blur();
    TrackContext(nullptr);
    ITfSource *source = nullptr;
    if (tm_ && threadCookie_ != TF_INVALID_COOKIE &&
        SUCCEEDED(tm_->QueryInterface(IID_ITfSource, (void **)&source))) {
      source->UnadviseSink(threadCookie_);
      source->Release();
    }
    threadCookie_ = TF_INVALID_COOKIE;
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

    if (tm_) { tm_->Release(); tm_ = nullptr; }
    return S_OK;
  }

  // ITfKeyEventSink. Rime is stateful, so the key is processed once in OnTest* and the
  // result reused by the following On* call for the same key.
  STDMETHODIMP OnSetFocus(BOOL fg) override {
    if (fg) { kx::ReloadIfChanged(); RefreshFocus(); }
    else { Blur(); TrackContext(nullptr); }
    return S_OK;
  }
  STDMETHODIMP OnTestKeyDown(ITfContext *c, WPARAM w, LPARAM l, BOOL *eaten) override {
    EnsureContext(c);
    *eaten = Process(w, l, false);
    Tail(c);
    // Paste: claim it here so OnKeyDown runs (sync edit session commits the held text), then OnKeyDown passes it to the app.
    if (paste_) *eaten = TRUE;
    return S_OK;
  }
  STDMETHODIMP OnTestKeyUp(ITfContext *c, WPARAM w, LPARAM l, BOOL *eaten) override {
    EnsureContext(c);
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

  STDMETHODIMP OnCompositionTerminated(TfEditCookie ec, ITfComposition *composition) override {
    // Late notifications for a detached/ended composition must not clear the new field's Rime state.
    if (comp_ && Same(composition, comp_)) Blur(true, ec);
    return S_OK;
  }

  // ITfThreadMgrEventSink: document changes alone are insufficient (WinForms can reuse a context).
  STDMETHODIMP OnInitDocumentMgr(ITfDocumentMgr *) override { return S_OK; }
  STDMETHODIMP OnUninitDocumentMgr(ITfDocumentMgr *doc) override {
    ITfDocumentMgr *owner = nullptr;
    if (focus_ && SUCCEEDED(focus_->GetDocumentMgr(&owner)) && owner) {
      if (Same(doc, owner)) { Blur(); TrackContext(nullptr); }
      owner->Release();
    }
    return S_OK;
  }
  STDMETHODIMP OnSetFocus(ITfDocumentMgr *doc, ITfDocumentMgr *) override {
    ITfContext *c = nullptr;
    if (doc && FAILED(doc->GetTop(&c))) c = nullptr;
    EnsureContext(c);
    if (c) c->Release();
    return S_OK;
  }
  STDMETHODIMP OnPushContext(ITfContext *) override { RefreshFocus(); return S_OK; }
  STDMETHODIMP OnPopContext(ITfContext *c) override {
    if (Same(c, focus_)) { Blur(); TrackContext(nullptr); }
    RefreshFocus();
    return S_OK;
  }

  STDMETHODIMP OnEndEdit(ITfContext *c, TfEditCookie ec, ITfEditRecord *record) override {
    if (writing_ || !Same(c, focus_)) return S_OK;
    const auto generation = generation_;
    // Every edit OnEndEdit triggers must be async (the app still holds the lock; MS docs for
    // ITfTextEditSink::OnEndEdit). That includes the blur a view/HWND change makes EnsureContext do.
    EnsureContext(c, true);
    if (generation != generation_ || !Same(c, focus_)) return S_OK;
    BOOL changed = FALSE;
    if (!comp_ || !Same(c, owner_)) return S_OK;
    comp_->AddRef();
    auto composition = Adopt(comp_);
    if (FAILED(record->GetSelectionStatus(&changed)) || !changed || generation != generation_) return S_OK;
    TF_SELECTION sel = {};
    ULONG count = 0;
    ITfRange *range = nullptr;
    if (SUCCEEDED(c->GetSelection(ec, TF_DEFAULT_SELECTION, 1, &sel, &count)) && count == 1 && sel.range) {
      LONG start = 0, end = 0;
      if (generation == generation_ && Same(composition.get(), comp_) &&
          SUCCEEDED(composition->GetRange(&range)) && range) {
        bool outside = FAILED(range->CompareStart(ec, sel.range, TF_ANCHOR_START, &start)) ||
                       FAILED(range->CompareEnd(ec, sel.range, TF_ANCHOR_END, &end)) || start > 0 || end < 0;
        range->Release();
        // OnEndEdit runs while the app still holds the document lock: a TF_ES_SYNC request is
        // refused here (TF_E_LOCKED/TF_E_SYNCHRONOUS) and the preedit would stay behind.
        if (outside && generation == generation_ && Same(composition.get(), comp_)) Blur(false, 0, true);
      }
      sel.range->Release();
    }
    return S_OK;
  }

 private:
  // Compare canonical COM identities, not interface addresses.
  static bool Same(IUnknown *a, IUnknown *b) {
    if (!a || !b) return a == b;
    IUnknown *x = nullptr, *y = nullptr;
    a->QueryInterface(IID_IUnknown, (void **)&x);
    b->QueryInterface(IID_IUnknown, (void **)&y);
    bool same = x && x == y;
    if (x) x->Release();
    if (y) y->Release();
    return same;
  }
  template<class T> static std::shared_ptr<T> Adopt(T *p) {
    return std::shared_ptr<T>(p, [](T *v) { if (v) v->Release(); });
  }

  void ResetInput() {
    ++generation_;
    pending_ = pendUp_ = pendEaten_ = paste_ = switch_ = hint_ = cands_ = newline_ = newlineExt_ = endFailed_ = commitWritten_ = commitFailed_ = false;
    pendW_ = 0;
    chord_ = KxChord();
    last_ = POINT{-1, -1}; lastH_ = 0;
    cand_.Hide(true);
  }

  void Blur(bool terminated = false, TfEditCookie ec = 0, bool deferred = false) {
    // Detach BEFORE requesting a lock/ending a composition: TSF can reenter any sink here.
    auto composition = Adopt(comp_);
    auto context = Adopt(owner_);
    comp_ = nullptr; owner_ = nullptr;
    const std::wstring shown = shownPre_;
    shownPre_.clear();
    std::wstring commit;
    if (sess_) {
      kx_key(sess_, 0xffe0, 0);  // existing F35 blur policy, not a new candidate/space policy
      char *raw = kx_take_commit(sess_);
      commit = raw ? kx::Wide(raw) : L"";
      free(raw);
      kx_clear(sess_);
    }
    const auto generation = generation_ + 1;
    ResetInput();
    if (generation != generation_ || !composition || !context) return;
    // Synchronous by default: a delayed range can follow a reused context into another field.
    // Only the in-field caret move (OnEndEdit, lock still held) defers; that write is bound to
    // this blur's generation and its own composition object, so any later focus/context change
    // (EnsureContext -> Blur -> ResetInput) cancels it instead of writing into the wrong field.
    // If the write lock fails, leave the existing document preedit untouched. The host owns
    // its eventual termination; the F35 conversion is not guaranteed in that case.
    AddRef(); auto lifetime = Adopt(static_cast<ITfTextInputProcessorEx *>(this));
    auto finish = [this, lifetime, composition, context, commit, terminated, generation, deferred](TfEditCookie cookie) {
      if (generation != generation_) return;
      if (deferred && (comp_ && Same(composition.get(), comp_))) return;  // re-adopted: not ours to end
      ITfRange *range = nullptr;
      if (!commit.empty() && SUCCEEDED(composition->GetRange(&range)) && range) {
        if (generation == generation_)
          range->SetText(cookie, 0, commit.c_str(), (LONG)commit.size());
        range->Release();
      }
      if (!terminated && generation == generation_) composition->EndComposition(cookie);
    };
    // The app ended the composition itself (Chromium/Electron finalizes the preedit on blur and
    // keeps it). When the blur result is exactly that preedit, the document already holds it:
    // writing it again from the termination callback lands in the newly focused field because
    // Chromium uses one text store per window.
    if (terminated && commit == shown) { Trace("blur terminated: app kept preedit, no write"); return; }
    if (terminated) { Trace("blur terminated: write commit"); finish(ec); return; }
    auto *edit = new EditSession(finish);
    HRESULT result = E_FAIL;
    HRESULT request = context->RequestEditSession(id_, edit, (deferred ? TF_ES_ASYNC : TF_ES_SYNC) | TF_ES_READWRITE, &result);
    Trace("blur owner request=" + std::to_string((long)request) + " result=" + std::to_string((long)result));
    edit->Release();
  }

  void TrackContext(ITfContext *c) {
    if (Same(c, focus_)) return;
    // Detach the members before UnadviseSink: TSF may reenter a sink there, and a nested
    // TrackContext must not see (and release) the context this call is about to drop.
    ITfContext *old = focus_;
    const DWORD oldCookie = editCookie_;
    focus_ = nullptr; editCookie_ = TF_INVALID_COOKIE;
    if (old) {
      ITfSource *source = nullptr;
      if (oldCookie != TF_INVALID_COOKIE && SUCCEEDED(old->QueryInterface(IID_ITfSource, (void **)&source))) {
        source->UnadviseSink(oldCookie);
        source->Release();
      }
      old->Release();
    }
    if (focus_) return;  // a reentrant transition already installed the newer context
    focus_ = c;
    if (view_) { view_->Release(); view_ = nullptr; }
    focusHwnd_ = nullptr; viewHwnd_ = nullptr;
    if (focus_) {
      focus_->AddRef();
      ITfSource *source = nullptr;
      if (SUCCEEDED(focus_->QueryInterface(IID_ITfSource, (void **)&source))) {
        source->AdviseSink(IID_ITfTextEditSink, (ITfTextEditSink *)this, &editCookie_);
        source->Release();
      }
    }
  }

  void EnsureContext(ITfContext *c, bool fromEndEdit = false) {
    const auto generation = generation_;
    ITfContextView *view = nullptr;
    HWND hwnd = GetFocus(), viewHwnd = nullptr;
    if (c && SUCCEEDED(c->GetActiveView(&view)) && view) view->GetWnd(&viewHwnd);
    if (generation_ != generation) { if (view) view->Release(); return; }
    bool changed = !Same(c, focus_) || (focusHwnd_ && hwnd && focusHwnd_ != hwnd) ||
                   (viewHwnd_ && viewHwnd && viewHwnd_ != viewHwnd) ||
                   (view_ && view && !Same(view_, view));
    Trace("ensure ctx=" + std::to_string((uintptr_t)c) + " focus=" + std::to_string((uintptr_t)focus_) + " hwnd=" + std::to_string((uintptr_t)hwnd) + " prev=" + std::to_string((uintptr_t)focusHwnd_) + " changed=" + std::to_string(changed));
    if (changed) Blur(false, 0, fromEndEdit);
    // Blur resets once; any further reset means a nested focus transition won.
    const auto expected = generation + (changed ? 1 : 0);
    if (generation_ != expected) { if (view) view->Release(); return; }
    TrackContext(c);
    if (generation_ != expected) { if (view) view->Release(); return; }
    if (view_) view_->Release();
    view_ = view;
    focusHwnd_ = hwnd; viewHwnd_ = viewHwnd;
  }

  void RefreshFocus() {
    ITfDocumentMgr *doc = nullptr;
    ITfContext *c = nullptr;
    if (tm_ && SUCCEEDED(tm_->GetFocus(&doc)) && doc) {
      if (FAILED(doc->GetTop(&c))) c = nullptr;
      doc->Release();
    }
    EnsureContext(c);
    if (c) c->Release();
  }
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
    newline_ = false;  // only the key that set it (test + real call of one Return) may use it
    int sym = KeySym(w, l), mask = Mask();
    // Tab is the shared "expand" key (Linux/macOS behave the same): with an open composition it
    // goes to Rime, where win_quick toggles the multi-column list and the text stays in preedit
    // in the same field. With nothing composing Rime does not eat it, so the host still gets its
    // own Tab/Shift+Tab focus navigation. Focus leaving the field commits through Blur as usual.
    if (sym == 0xff09 && !comp_ && !(mask & (kControl | kAlt))) return false;
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
      // 全形/半形 is held user-wide: another app's Shift+Space, or this app's new session (the
      // schema resets full_shape), must not flip it back. Apply before the key, publish after.
      if (kx::ApplyShape(sess_)) Trace("shape applied");
      eaten = kx_key(sess_, sym, m | (up ? kRelease : 0)) != 0;
      // A Return Rime lets through while a preedit is open (deferred "hello." / "hello-") is a
      // genuine newline (shared hello-dot-return): Rime committed the held text. Passed on with
      // our composition still open, the app spends it ending the composition (no CR LF). Letting
      // it through after a sync commit is not enough either: IMM32/CUAS hosts (WinForms) apply
      // the result after the key, so the newline lands before the text (VM fd02caa). Claim it;
      // FinishNewline re-sends one tagged Return once the commit is really in the document.
      newline_ = sym == 0xff0d && !up && !eaten && comp_ != nullptr && GetMessageExtraInfo() != kNewlineTag;
      if (newline_) { eaten = true; endFailed_ = commitWritten_ = commitFailed_ = false; }
      newlineExt_ = newline_ && ((l >> 24) & 1);
      // key_bindings: Shift+space toggles full_shape (the Ctrl chords never reach Rime here).
      if (kx::NoteShape(sess_, sym == 0x20 && (m & kShift) && !up)) Trace("shape held");
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
    // Preserve shared association/inline state: a synthetic Escape disables v8 held ASCII.
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
    ITfCompartmentMgr *cm = nullptr;
    ITfCompartment *c = nullptr;
    if (FAILED(tm_->QueryInterface(IID_ITfCompartmentMgr, (void **)&cm)) || !cm) return;
    if (SUCCEEDED(cm->GetCompartment(GUID_COMPARTMENT_KEYBOARD_INPUTMODE_CONVERSION, &c)) && c) {
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

  // The claimed Return (see Process), after Handle's Update. Only a commit that is really in the
  // document (sync lock granted, the commit's SetText accepted, EndComposition succeeded, our
  // composition closed) gets the newline:
  // one Return is re-sent, tagged so it can never be claimed again, queued behind the app's own
  // handling of the commit. Otherwise (lock refused -> commit only queued async, or the end was
  // refused) the Return stays swallowed: text kept, that newline lost, never newline-before-text.
  // A failed SendInput is traced; the newline is then lost too (the text is not).
  bool FinishNewline() {
    if (!newline_) return false;
    newline_ = false;
    if (comp_ || endFailed_ || commitFailed_ || !commitWritten_) {
      Trace("newline: commit not confirmed, Return swallowed");
      return true;
    }
    // The user's Return is normally still down here. A re-sent key-down on a held key carries the
    // previous-state bit (lParam bit 30), and Chromium/Electron drop such a '\r' until the field has
    // seen a fresh Return (crbug.com/319100: accept_carriage_return_), so the first newline in every
    // field was lost (E40 host f19f39f). Release it first so the re-sent Return is a fresh press.
    INPUT in[3] = {};
    const DWORD ext = newlineExt_ ? KEYEVENTF_EXTENDEDKEY : 0;  // keypad Enter stays keypad Enter
    for (int i = 0; i < 3; i++) {
      in[i].type = INPUT_KEYBOARD; in[i].ki.wVk = VK_RETURN;
      in[i].ki.dwFlags = ext | (i != 1 ? KEYEVENTF_KEYUP : 0); in[i].ki.dwExtraInfo = (ULONG_PTR)kNewlineTag;
    }
    const UINT lead = (GetAsyncKeyState(VK_RETURN) & 0x8000) ? 1 : 0;  // release only a held Return
    const UINT want = 2 + lead;  // [up] down up
    const UINT sent = SendInput(want, &in[1 - lead], sizeof(INPUT));
    if (sent == want) Trace(lead ? "newline: committed, held Return released, re-sent" : "newline: committed, Return re-sent");
    else if (sent == want - 1) {
      // Only the key-down went in (the newline is delivered); never leave Return logically held.
      const UINT up = SendInput(1, &in[2], sizeof(INPUT));
      Trace(up == 1 ? "newline: re-sent, key-up retried" : "newline: re-sent, key-up lost");
    } else Trace("newline: SendInput failed, newline lost");
    return true;
  }

  bool Handle(ITfContext *c, WPARAM w, LPARAM l, bool up) {
    EnsureContext(c);
    bool eaten = Process(w, l, up);
    pending_ = false;
    // Update the document even for keys Rime let through: e.g. Return after a pick
    // closes the association list (Rime state changed) and must still reach the app.
    Update(c);
    if (hint_) { hint_ = false; ShowHint(); }
    if (!up && FinishNewline()) return true;
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
    if (!sess_ || !c || !Same(c, focus_)) return;
    const auto generation = generation_;
    SyncMode();
    if (generation != generation_) return;
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
    const LONG preCaret = f.size() > 1 ? kx::DisplayCaretUtf16(f[0], f[1]) : (LONG)pre.size();
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
    auto *es = new EditSession([&](TfEditCookie ec) {
      if (generation != generation_ || !Same(c, focus_)) return;
      ++writing_;
      Write(ec, c, commit, pre, preCaret, &at, &lineH, generation);
      --writing_;
    });
    HRESULT hr = E_FAIL;
    HRESULT request = c->RequestEditSession(id_, es, TF_ES_SYNC | TF_ES_READWRITE, &hr);
    es->Release();
    if (generation != generation_) return;
    if (FAILED(request) || FAILED(hr)) {
      // The engine already gave up this commit (kx_take_commit). A refused sync lock — reachable from
      // a mouse pick, which is not a keystroke — must not drop it: queue the same write async, bound
      // to this generation and context so a later focus change cancels it instead of misplacing it.
      if (!commit.empty()) {
        AddRef(); auto lifetime = Adopt(static_cast<ITfTextInputProcessorEx *>(this));
        c->AddRef(); auto ctxRef = Adopt(c);
        auto *later = new EditSession([this, lifetime, ctxRef, commit, pre, preCaret, generation](TfEditCookie ec) {
          if (generation != generation_ || !Same(ctxRef.get(), focus_)) return;
          POINT p = {-1, -1}; int lh = 0;
          ++writing_;
          Write(ec, ctxRef.get(), commit, pre, preCaret, &p, &lh, generation);
          --writing_;
        });
        HRESULT hr2 = E_FAIL;
        HRESULT r2 = c->RequestEditSession(id_, later, TF_ES_ASYNC | TF_ES_READWRITE, &hr2);
        later->Release();
        Trace("update sync refused request=" + std::to_string((long)request) + " hr=" + std::to_string((long)hr) +
              " async=" + std::to_string((long)r2));
      }
      cand_.Hide(true);
      return;
    }
    if (cands.empty()) { cand_.Hide(); return; }
    if (at.x < 0 && last_.x >= 0) { at = last_; lineH = lastH_; }  // TSF gave no extent: stay where the preedit was
    if (at.x < 0) at = CaretAt(&lineH);
    auto it = kx::Current().find("candidate_layout");
    c->AddRef(); auto context = Adopt(c);
    HWND hwnd = GetFocus();
    cand_.Show(cands, at, lineH, it == kx::Current().end() || it->second != "horizontal",
               [this, context, generation, hwnd, ctx](int item) { PickCandidate(context.get(), generation, hwnd, ctx, item); });
  }

  void PickCandidate(ITfContext *c, unsigned long long generation, HWND hwnd, const std::string &menu, int item) {
    AddRef(); auto lifetime = Adopt(this);
    if (!sess_ || item < 0 || item >= 9 || generation != generation_ || GetFocus() != hwnd || !Same(c, focus_)) return;
    EnsureContext(c);
    if (generation != generation_ || GetFocus() != hwnd || !Same(c, focus_)) return;
    char *raw = kx_context(sess_); std::string current = raw ? raw : ""; free(raw);
    if (menu != current) return;  // page, highlight and preedit must still be the displayed snapshot
    pending_ = false; chord_ = KxChord();
    kx_select_candidate_on_current_page(sess_, item);  // explicit mouse selection, not Shift+9 punctuation policy
    Update(c);
  }

  // Commit text and/or preedit through one TSF composition.
  void Write(TfEditCookie ec, ITfContext *c, const std::wstring &commit, const std::wstring &pre, LONG preCaret, POINT *at, int *lineH,
             unsigned long long generation) {
    if (generation != generation_ || !Same(c, focus_) || (comp_ && !Same(c, owner_))) return;
    if (!commit.empty()) {
      if (!comp_) Begin(ec, c);
      if (generation != generation_ || !Same(c, owner_)) return;
      if (!comp_) commitFailed_ = true;
      if (comp_) {
        comp_->AddRef();
        auto composition = Adopt(comp_);
        ITfRange *r = nullptr;
        if (SUCCEEDED(composition->GetRange(&r)) && r) {
          // Only a commit the document really accepted may release a claimed Return (FinishNewline).
          if (SUCCEEDED(r->SetText(ec, 0, commit.c_str(), (LONG)commit.size()))) commitWritten_ = true;
          else commitFailed_ = true;
          if (generation != generation_ || !Same(composition.get(), comp_)) { r->Release(); return; }
          r->Collapse(ec, TF_ANCHOR_END);
          SetSel(ec, c, r);
          r->Release();
        } else {
          commitFailed_ = true;
        }
        if (generation != generation_ || !Same(composition.get(), comp_)) return;
        End(ec);
      }
    }
    if (generation != generation_ || !Same(c, focus_)) return;
    if (pre.empty()) {
      if (comp_) {
        comp_->AddRef();
        auto composition = Adopt(comp_);
        ITfRange *r = nullptr;
        if (SUCCEEDED(composition->GetRange(&r)) && r) { r->SetText(ec, 0, L"", 0); r->Release(); }
        if (generation != generation_ || !Same(composition.get(), comp_)) return;
        End(ec);
      }
      TF_SELECTION sel = {};
      ULONG n = 0;
      if (SUCCEEDED(c->GetSelection(ec, TF_DEFAULT_SELECTION, 1, &sel, &n)) && n == 1 && sel.range) {
        Below(ec, c, sel.range, at, lineH);
        sel.range->Release();
      }
      return;
    }
    if (generation != generation_ || !Same(c, focus_)) return;
    if (!comp_) Begin(ec, c);
    if (!comp_ || generation != generation_ || !Same(c, owner_)) return;
    comp_->AddRef();
    auto composition = Adopt(comp_);
    ITfRange *r = nullptr;
    if (FAILED(composition->GetRange(&r)) || !r) return;
    const HRESULT set = r->SetText(ec, 0, pre.c_str(), (LONG)pre.size());
    if (generation != generation_ || !Same(composition.get(), comp_)) { r->Release(); return; }
    // Only a preedit the document really holds, for the composition still ours, may suppress a blur write.
    if (SUCCEEDED(set)) shownPre_ = pre;
    ITfRange *caret = nullptr;
    if (SUCCEEDED(r->Clone(&caret)) && caret) {
      LONG shifted = 0;
      if (SUCCEEDED(caret->Collapse(ec, TF_ANCHOR_START)) &&
          SUCCEEDED(caret->ShiftEnd(ec, preCaret, &shifted, nullptr)) && shifted == preCaret &&
          generation == generation_ && Same(c, owner_)) {
        caret->Collapse(ec, TF_ANCHOR_END); SetSel(ec, c, caret);
        if (generation == generation_ && Same(c, focus_)) Below(ec, c, caret, at, lineH);
      }
      caret->Release();
    }
    r->Release();
  }

  // Screen point just below a text range, from the app's TSF view.
  void Below(TfEditCookie ec, ITfContext *c, ITfRange *r, POINT *at, int *lineH) {
    const auto generation = generation_;
    ITfContextView *v = nullptr;
    if (FAILED(c->GetActiveView(&v)) || !v) return;
    // Full preedit bounds can start far left of the caret in a scrolled input.
    // Query a collapsed clone, leaving the live composition range unchanged.
    ITfRange *caret = nullptr;
    if (generation == generation_ && Same(c, focus_) && SUCCEEDED(r->Clone(&caret)) && caret) {
      RECT rc;
      BOOL clipped;
      if (SUCCEEDED(caret->Collapse(ec, TF_ANCHOR_END)) && generation == generation_ &&
          Same(c, focus_) && SUCCEEDED(v->GetTextExt(ec, caret, &rc, &clipped)) &&
          (rc.left || rc.bottom) && generation == generation_ && Same(c, focus_)) {
        at->x = rc.left; at->y = rc.bottom + 2;
        *lineH = rc.bottom - rc.top;
        // Native EDIT can return a successful but left-wrapped TSF extent after horizontal scroll.
        // Never substitute a browser/system caret or a caret belonging to another context/view.
        HWND fw = GetFocus(), viewWindow = nullptr;
        GUITHREADINFO gi = {sizeof gi};
        wchar_t cls[128] = {};
        if (fw && SUCCEEDED(v->GetWnd(&viewWindow)) &&
            GetGUIThreadInfo(GetCurrentThreadId(), &gi) && GetClassNameW(fw, cls, 128)) {
          RECT client = {};
          POINT cp = {gi.rcCaret.left, gi.rcCaret.bottom};
          const bool editHost = _wcsicmp(cls, L"Edit") == 0 || wcsncmp(cls, L"WindowsForms10.EDIT.", 20) == 0;
          const bool valid = GetClientRect(fw, &client) && gi.rcCaret.bottom > gi.rcCaret.top &&
              gi.rcCaret.left >= client.left && gi.rcCaret.right <= client.right &&
              gi.rcCaret.top >= client.top && gi.rcCaret.bottom <= client.bottom && ClientToScreen(fw, &cp);
          if (kx::PreferEditCaret(editHost, gi.hwndFocus == fw, gi.hwndCaret == fw, viewWindow == fw,
                                  valid, rc.left, cp.x, 48) && generation == generation_ && Same(c, focus_)) {
            at->x = cp.x; at->y = cp.y + 2;
            *lineH = gi.rcCaret.bottom - gi.rcCaret.top;
          }
        }
        if (generation != generation_ || !Same(c, focus_)) { caret->Release(); v->Release(); return; }
        last_ = *at; lastH_ = *lineH;
      }
      caret->Release();
    }
    v->Release();
  }

  void Begin(TfEditCookie ec, ITfContext *c) {
    const auto generation = generation_;
    ITfInsertAtSelection *ins = nullptr;
    ITfContextComposition *cc = nullptr;
    if (FAILED(c->QueryInterface(IID_ITfInsertAtSelection, (void **)&ins))) return;
    ITfRange *r = nullptr;
    if (SUCCEEDED(ins->InsertTextAtSelection(ec, TF_IAS_QUERYONLY, nullptr, 0, &r)) && r &&
        SUCCEEDED(c->QueryInterface(IID_ITfContextComposition, (void **)&cc))) {
      ITfComposition *composition = nullptr;
      cc->StartComposition(ec, r, (ITfCompositionSink *)this, &composition);
      if (composition) {
        if (generation == generation_ && Same(c, focus_) && !comp_) {
          comp_ = composition;
          owner_ = c; owner_->AddRef();
        } else {
          // A focus callback reentered StartComposition. Never publish that stale range.
          composition->EndComposition(ec);
          composition->Release();
        }
      }
      cc->Release();
    }
    if (r) r->Release();
    ins->Release();
  }

  void End(TfEditCookie ec) {
    auto composition = Adopt(comp_);
    auto context = Adopt(owner_);
    comp_ = nullptr; owner_ = nullptr;
    shownPre_.clear();
    if (composition && FAILED(composition->EndComposition(ec))) endFailed_ = true;
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
  ITfContext *owner_ = nullptr;  // the ONLY context whose edit cookie can touch comp_'s range
  std::wstring shownPre_;  // preedit last written into comp_'s range
  ITfContext *focus_ = nullptr;
  ITfContextView *view_ = nullptr;
  HWND focusHwnd_ = nullptr, viewHwnd_ = nullptr;
  DWORD threadCookie_ = TF_INVALID_COOKIE, editCookie_ = TF_INVALID_COOKIE;
  unsigned long long generation_ = 0;
  unsigned writing_ = 0;
  POINT last_ = {-1, -1};
  int lastH_ = 0;
  CandWin cand_;
  LangBar *lb_ = nullptr;
  bool lbAscii_ = false;  // mode the language bar is showing
  KxChord chord_;
  bool hint_ = false;  // a mode switch is waiting to be shown after the next Update
  bool switch_ = false;  // a mode switch happened in the test path: Tail() commits it
  bool pending_ = false, pendUp_ = false, pendEaten_ = false, paste_ = false;
  bool newline_ = false, newlineExt_ = false;  // claimed Return: FinishNewline re-sends it after the commit
  bool endFailed_ = false;  // the host refused EndComposition since the claim
  bool commitWritten_ = false, commitFailed_ = false;  // commit SetText accepted / refused since the claim
  static constexpr LPARAM kNewlineTag = 0x4B584E4C;  // 'KXNL' in dwExtraInfo: our own re-sent Return
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
