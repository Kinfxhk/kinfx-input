// Windows self-test: same checks as mac/linux (vd1 -> 好, Return passes, page 5/9 via KxDeploy).
// Runs from the build folder next to rime.dll and data\.
#include <cstdio>
#include <fstream>
#include <string>
#include "core.h"

HINSTANCE g_hinst;
extern "C" int __stdcall KxDeploy();
static int fails = 0;

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
  for (auto [code, want] : {std::pair<const char *, const char *>{"vdhel", "\xe5\xa5\xbd\xe5\x8f\x8d"}, {"vd", ""}}) {
    s = kx_session("kinfx_quick");
    std::string out;
    for (const char *k = code; *k; k++) { kx_key(s, *k, 0); out += Take(s); }
    int eaten = kx_key(s, 'v', 4);  // Ctrl+V
    out += Take(s);
    Check(std::string(code) + " Ctrl+V commits held, app pastes", out + "/" + std::to_string(eaten), std::string(want) + "/0");
    kx_destroy(s);
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
  printf(fails ? "%d FAIL\n" : "ALL PASS\n", fails);
  return fails ? 1 : 0;
}
