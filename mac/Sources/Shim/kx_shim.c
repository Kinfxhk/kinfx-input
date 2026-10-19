// Thin C layer over librime's RimeApi so the Swift side never touches RIME_STRUCT
// or C struct layouts. Shared by the input method and the command-line self-test.
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include "rime_api.h"
#include "kx_shim.h"

static RimeApi *api = NULL;

int kx_start(const char *shared_dir, const char *user_dir, const char *log_dir, int full_check) {
  if (api) return 1;  // setup() may run only once per process (glog)
  api = rime_get_api();
  if (!api) return 0;
  RIME_STRUCT(RimeTraits, t);
  t.shared_data_dir = shared_dir;
  t.user_data_dir = user_dir;
  t.distribution_name = "KINFX Input";
  t.distribution_code_name = "kinfx-input";
  t.distribution_version = "0.1.0";
  t.app_name = "rime.kinfx-input";
  t.min_log_level = 1;
  t.log_dir = log_dir;
  api->setup(&t);
  api->initialize(NULL);
  if (api->start_maintenance(full_check)) api->join_maintenance_thread();
  return 1;
}

int kx_redeploy(void) {
  if (!api) return 0;
  // Same as Squirrel's deploy: restart the engine so cached schema configs are
  // dropped, then a full check rebuilds from the new .custom.yaml.
  api->cleanup_all_sessions();
  api->finalize();
  api->initialize(NULL);
  int ok = api->start_maintenance(1);
  if (ok) api->join_maintenance_thread();
  return ok;
}

uintptr_t kx_session(const char *schema) {
  if (!api) return 0;
  RimeSessionId s = api->create_session();
  if (s && schema) api->select_schema(s, schema);
  return (uintptr_t)s;
}

int kx_alive(uintptr_t s) { return api && s && api->find_session((RimeSessionId)s); }
void kx_destroy(uintptr_t s) { if (api && s) api->destroy_session((RimeSessionId)s); }
void kx_clear(uintptr_t s) { if (api && s) api->clear_composition((RimeSessionId)s); }
int kx_key(uintptr_t s, int keycode, int mask) {
  return api ? api->process_key((RimeSessionId)s, keycode, mask) : 0;
}
int kx_commit_composition(uintptr_t s) {
  return api ? api->commit_composition((RimeSessionId)s) : 0;
}

char *kx_take_commit(uintptr_t s) {
  if (!api) return NULL;
  RIME_STRUCT(RimeCommit, c);
  if (!api->get_commit((RimeSessionId)s, &c)) return NULL;
  char *out = c.text ? strdup(c.text) : NULL;
  api->free_commit(&c);
  return out;
}

static void append(char **buf, size_t *len, size_t *cap, const char *s) {
  size_t n = s ? strlen(s) : 0;
  if (*len + n + 1 > *cap) {
    while (*len + n + 1 > *cap) *cap *= 2;
    *buf = realloc(*buf, *cap);
  }
  if (n) memcpy(*buf + *len, s, n);
  *len += n;
  (*buf)[*len] = 0;
}

// Fields joined by 0x1f: preedit, cursor (bytes), page_size, page_no, is_last,
// highlighted, then one field per candidate as text 0x1e comment.
char *kx_context(uintptr_t s) {
  if (!api) return NULL;
  RIME_STRUCT(RimeContext, ctx);
  if (!api->get_context((RimeSessionId)s, &ctx)) return NULL;
  size_t len = 0, cap = 256;
  char *buf = malloc(cap);
  buf[0] = 0;
  char num[64];
  append(&buf, &len, &cap, ctx.composition.preedit);
  snprintf(num, sizeof num, "\x1f%d\x1f%d\x1f%d\x1f%d\x1f%d", ctx.composition.cursor_pos,
           ctx.menu.page_size, ctx.menu.page_no, ctx.menu.is_last_page,
           ctx.menu.highlighted_candidate_index);
  append(&buf, &len, &cap, num);
  for (int i = 0; i < ctx.menu.num_candidates; i++) {
    append(&buf, &len, &cap, "\x1f");
    append(&buf, &len, &cap, ctx.menu.candidates[i].text);
    append(&buf, &len, &cap, "\x1e");
    append(&buf, &len, &cap, ctx.menu.candidates[i].comment);
  }
  api->free_context(&ctx);
  return buf;
}
