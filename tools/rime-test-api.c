/* Test-only access to librime context operations not exposed by kx_shim. */
#include <rime_api.h>
void kxt_set_property(RimeSessionId s, const char *key, const char *value) {
  rime_get_api()->set_property(s, key, value);
}
int kxt_option(RimeSessionId s, const char *key) {
  return rime_get_api()->get_option(s, key);
}
const char *kxt_version(void) { return rime_get_api()->get_version(); }
