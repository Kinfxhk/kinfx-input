// Language bar button (中 / 英). Without a TSF language bar item Windows draws its own default
// glyph for the text service (a single letter), so the mode was invisible outside the 400 ms hint.
// The icon is drawn with GDI at run time: no new asset, and it follows the system DPI.
#pragma once
#include <windows.h>
#include <msctf.h>
#include <ocidl.h>  // SysAllocString for the item's text
#include <functional>

// {7A5E1C64-3F2B-4E8D-9C11-6B0D2A8F4E73} — our language bar item's own id
static const GUID GUID_KX_MODEBTN = {0x7a5e1c64, 0x3f2b, 0x4e8d, {0x9c, 0x11, 0x6b, 0x0d, 0x2a, 0x8f, 0x4e, 0x73}};

class LangBar : public ITfLangBarItemButton, public ITfSource {
 public:
  // ascii: current mode. click: toggle the mode (the TIP does the Rime work and the hint).
  LangBar(REFCLSID service, std::function<bool()> ascii, std::function<void()> click,
          std::function<void(const std::string &)> log = [](const std::string &) {})
      : service_(service), ascii_(std::move(ascii)), click_(std::move(click)), log_(std::move(log)) {}
  ~LangBar() {
    if (sink_) sink_->Release();
    if (icon_) DestroyIcon(icon_);
  }

  HRESULT Init(ITfLangBarItemMgr *mgr) {
    HRESULT hr = mgr->AddItem(this);
    log_("lb add hr=" + std::to_string((long)hr));
    if (FAILED(hr)) return hr;
    added_ = true;
    Show(TRUE);
    return S_OK;
  }
  void Uninit(ITfLangBarItemMgr *mgr) {
    if (added_ && mgr) mgr->RemoveItem(this);
    added_ = false;
  }
  // The manager re-reads GetIcon / GetText after this. Called only when the mode actually changed.
  void Refresh() {
    if (sink_) sink_->OnUpdate(TF_LBI_ICON | TF_LBI_TEXT);
  }

  STDMETHODIMP QueryInterface(REFIID r, void **p) override {
    if (!p) return E_INVALIDARG;
    if (r == IID_IUnknown || r == IID_ITfLangBarItem || r == IID_ITfLangBarItemButton) *p = (ITfLangBarItemButton *)this;
    else if (r == IID_ITfSource) *p = (ITfSource *)this;
    else { *p = nullptr; return E_NOINTERFACE; }
    AddRef();
    return S_OK;
  }
  STDMETHODIMP_(ULONG) AddRef() override { return ++ref_; }
  STDMETHODIMP_(ULONG) Release() override { ULONG r = --ref_; if (!r) delete this; return r; }

  // ITfLangBarItem
  STDMETHODIMP GetInfo(TF_LANGBARITEMINFO *i) override {
    i->clsidService = service_;
    i->guidItem = GUID_KX_MODEBTN;
    i->dwStyle = TF_LBI_STYLE_BTN_BUTTON | TF_LBI_STYLE_SHOWNINTRAY;
    i->ulSort = 1;
    log_("lb getinfo");
    lstrcpynW(i->szDescription, L"KINFX Input", TF_LBI_DESC_MAXLEN);
    return S_OK;
  }
  STDMETHODIMP GetStatus(DWORD *s) override { *s = 0; return S_OK; }
  STDMETHODIMP Show(BOOL) override { return S_OK; }  // SHOWNINTRAY already shows it; nothing to hide
  STDMETHODIMP GetIcon(HICON *phIcon) override {
    bool a = ascii_();
    // GetDeviceCaps(LOGPIXELSX) reports 96 in a DPI-unaware host; the system DPI is what the shell
    // scales the tray with (150% VM -> 24 px).
    int dpi = (int)GetDpiForSystem();
    if (!dpi) dpi = 96;
    int px = MulDiv(16, dpi, 96);
    log_("lb icon " + std::to_string(px) + (a ? " en" : " zh"));
    if (!icon_ || a != iconAscii_ || px != iconPx_) {
      if (icon_) DestroyIcon(icon_);
      icon_ = Make(a ? L"英" : L"中", px);
      iconAscii_ = a;
      iconPx_ = px;
    }
    *phIcon = icon_;
    return icon_ ? S_OK : E_FAIL;
  }
  STDMETHODIMP GetTooltipString(BSTR *p) override {
    *p = SysAllocString(ascii_() ? L"KINFX Input：英（Ctrl+Space 切換）" : L"KINFX Input：中（Ctrl+Space 切換）");
    return *p ? S_OK : E_OUTOFMEMORY;
  }

  // ITfLangBarItemButton
  STDMETHODIMP OnClick(TfLBIClick, POINT, const RECT *) override {
    log_("lb click");
    click_();  // the TIP toggles Rime and calls Refresh through its own mode check
    return S_OK;
  }
  STDMETHODIMP InitMenu(ITfMenu *) override { return S_OK; }  // no menu: one mode button
  STDMETHODIMP OnMenuSelect(UINT) override { return S_OK; }
  STDMETHODIMP GetText(BSTR *p) override {
    log_("lb text");
    *p = SysAllocString(ascii_() ? L"英" : L"中");
    return *p ? S_OK : E_OUTOFMEMORY;
  }

  // ITfSource: the language bar manager advises its sink here, right after AddItem.
  STDMETHODIMP AdviseSink(REFIID r, IUnknown *p, DWORD *cookie) override {
    if (r != IID_ITfLangBarItemSink) return E_NOINTERFACE;
    if (sink_) return E_FAIL;  // one sink only (CONNECT_E_ADVISELIMIT's meaning; the code is not in every SDK)
    if (p->QueryInterface(IID_ITfLangBarItemSink, (void **)&sink_) != S_OK) { sink_ = nullptr; return E_NOINTERFACE; }
    log_("lb advised");
    *cookie = 1;
    return S_OK;
  }
  STDMETHODIMP UnadviseSink(DWORD) override {
    if (!sink_) return E_FAIL;
    sink_->Release();
    sink_ = nullptr;
    return S_OK;
  }

 private:
  // 16x16 (scaled by DPI) dark tile with a light 中/英, the same colours as the candidate window.
  static HICON Make(const wchar_t *s, int px) {
    HDC dc = CreateCompatibleDC(nullptr);
    BITMAPINFO bi = {};
    bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bi.bmiHeader.biWidth = px;
    bi.bmiHeader.biHeight = -px;  // top-down
    bi.bmiHeader.biPlanes = 1;
    bi.bmiHeader.biBitCount = 32;
    bi.bmiHeader.biCompression = BI_RGB;
    void *bits = nullptr;
    HBITMAP color = CreateDIBSection(dc, &bi, DIB_RGB_COLORS, &bits, nullptr, 0);
    if (!color) { DeleteDC(dc); return nullptr; }
    HGDIOBJ old = SelectObject(dc, color);
    RECT rc = {0, 0, px, px};
    HBRUSH bg = CreateSolidBrush(RGB(0x2b, 0x26, 0x24));
    FillRect(dc, &rc, bg);
    DeleteObject(bg);
    SetBkMode(dc, TRANSPARENT);
    SetTextColor(dc, RGB(0xee, 0xe6, 0xdc));
    HFONT f = CreateFontW(-MulDiv(px, 4, 5), 0, 0, 0, FW_BOLD, 0, 0, 0, DEFAULT_CHARSET, 0, 0, CLEARTYPE_QUALITY, 0,
                          L"Microsoft JhengHei UI");
    HGDIOBJ of = SelectObject(dc, f);
    SIZE sz = {};
    GetTextExtentPoint32W(dc, s, 1, &sz);
    TextOutW(dc, (px - sz.cx) / 2, (px - sz.cy) / 2, s, 1);
    SelectObject(dc, of);
    DeleteObject(f);
    for (int i = 0; i < px * px; i++) ((BYTE *)bits)[i * 4 + 3] = 255;  // GDI leaves alpha 0: icon would be invisible
    SelectObject(dc, old);
    DeleteDC(dc);
    HBITMAP mask = CreateBitmap(px, px, 1, 1, nullptr);  // all zero: opaque
    ICONINFO ii = {TRUE, 0, 0, mask, color};
    HICON ic = CreateIconIndirect(&ii);
    DeleteObject(color);
    DeleteObject(mask);
    return ic;
  }

  CLSID service_;
  std::function<bool()> ascii_;
  std::function<void()> click_;
  std::function<void(const std::string &)> log_;
  ITfLangBarItemSink *sink_ = nullptr;
  HICON icon_ = nullptr;
  bool iconAscii_ = false;
  int iconPx_ = 0;
  bool added_ = false;
  ULONG ref_ = 1;
};
