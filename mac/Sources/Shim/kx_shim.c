// Thin C layer over librime's RimeApi so the Swift side never touches RIME_STRUCT
// or C struct layouts. Shared by the input method and the command-line self-test.
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <limits.h>
#include "rime_api.h"
#include "kx_shim.h"

static RimeApi *api = NULL;
static char *schema_source = NULL;

int kx_start(const char *shared_dir, const char *user_dir, const char *log_dir, int full_check) {
  if (api) return 1;  // setup() may run only once per process (glog)
  size_t n = strlen(shared_dir) + 32;
  schema_source = malloc(n);
  snprintf(schema_source, n, "%s/kinfx_quick.schema.yaml", shared_dir);
  api = rime_get_api();
  if (!api) return 0;
  RIME_STRUCT(RimeTraits, t);
  t.shared_data_dir = shared_dir;
  t.user_data_dir = user_dir;
  t.distribution_name = "KINFX Input";
  t.distribution_code_name = "kinfx-input";
  t.distribution_version = "0.1.5";
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
  // start_maintenance reports scheduling, not schema deployment success.
  return ok && schema_source && api->deploy_schema(schema_source);
}

uintptr_t kx_session(const char *schema) {
  if (!api) return 0;
  RimeSessionId s = api->create_session();
  if (!s) return 0;
  // create_session may select a different default (or no schema). Never expose
  // that alive fallback as the requested dictionary after a failed selection.
  if (schema) {
    int selected = api->select_schema(s, schema);
    RIME_STRUCT(RimeStatus, status);
    int got_status = api->get_status(s, &status);
    int matches = got_status && status.schema_id && !strcmp(status.schema_id, schema);
    if (got_status) api->free_status(&status);
    // librime can create an empty named schema even when selection and status
    // both report success; require the loaded configuration's declared identity.
    RimeConfig config = {0};
    int opened = api->schema_open(schema, &config);
    const char *configured = opened ? api->config_get_cstring(&config, "schema/schema_id") : NULL;
    int valid = configured && !strcmp(configured, schema);
    if (opened) api->config_close(&config);
    if (!selected || !matches || !valid) { api->destroy_session(s); return 0; }
  }
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

int kx_select_candidate_on_current_page(uintptr_t s, int index) {
  if (!kx_alive(s) || index < 0 ||
      !RIME_API_AVAILABLE(api, select_candidate_on_current_page)) return 0;
  RIME_STRUCT(RimeContext, ctx);
  if (!api->get_context((RimeSessionId)s, &ctx)) return 0;
  int valid = index < ctx.menu.num_candidates;
  api->free_context(&ctx);
  if (!valid) return 0;
  // assoc.lua observes this transaction in commit/update notifiers. Native
  // selection bypasses processors, so keyboard Shift+9 keeps its literal meaning.
  api->set_property((RimeSessionId)s, "kinfx_candidate_click", "1");
  int ok = api->select_candidate_on_current_page((RimeSessionId)s, (size_t)index);
  api->set_property((RimeSessionId)s, "kinfx_candidate_click", "");
  return ok;
}

char *kx_take_commit(uintptr_t s) {
  if (!api) return NULL;
  RIME_STRUCT(RimeCommit, c);
  if (!api->get_commit((RimeSessionId)s, &c)) return NULL;
  char *out = c.text ? strdup(c.text) : NULL;
  api->free_commit(&c);
  return out;
}

// Queue consumption is tracked by Engine: this guard inspects only native input
// and Lua's complete pending plan, never GetCommitText (which consumes the queue).
int kx_has_pending(uintptr_t s) {
  if (!kx_alive(s) || !RIME_API_AVAILABLE(api, get_input)) return -1;
  const char *input = api->get_input((RimeSessionId)s);
  if (!input) return -1;
  if (*input) return 1;
  char plan[4096];
  memset(plan, 0xff, sizeof plan);
  // librime 1.17 returns false for an EMPTY property as well as a missing one.
  // Require the production Lua initializer marker before accepting that empty
  // plan; a full/truncated nonempty plan remains unknown, never idle.
  int present = api->get_property((RimeSessionId)s, "kinfx_blur", plan, sizeof plan);
  if (present) {
    if (!memchr(plan, 0, sizeof plan - 1)) return -1;
    return *plan ? 1 : 0;
  }
  char owner[64];
  memset(owner, 0xff, sizeof owner);
  if (!api->get_property((RimeSessionId)s, "kinfx_english_state", owner, sizeof owner) ||
      !memchr(owner, 0, sizeof owner - 1) || !*owner) return -1;
  return 0;
}
// This context belongs to an idle controller, not a document or recovery plan.
// Reject unknown/truncated values instead of restoring arbitrary Lua state.
int kx_idle_punct_tail(uintptr_t s) {
  if (kx_has_pending(s) != 0) return -1;
  char tail[16];
  memset(tail, 0xff, sizeof tail);
  if (!api->get_property((RimeSessionId)s, "kinfx_punct_tail", tail, sizeof tail)) return 0;
  if (!memchr(tail, 0, sizeof tail - 1)) return -1;
  if (!*tail) return 0;
  if (!strcmp(tail, "latin")) return 1;
  if (!strcmp(tail, "other")) return 2;
  return -1;
}
int kx_restore_idle_punct_tail(uintptr_t s, int tail) {
  if (tail < 0 || tail > 2 || kx_has_pending(s) != 0) return 0;
  const char *value = tail == 1 ? "latin" : tail == 2 ? "other" : "";
  api->set_property((RimeSessionId)s, "kinfx_punct_tail", value);
  return kx_idle_punct_tail(s) == tail;
}
// Digit-led alphanumeric tail (60cm, 12v, 2x6), same idle/validated shape as the
// script tail: a single bounded boolean property, never composition text.
int kx_idle_digit_tail(uintptr_t s) {
  if (kx_has_pending(s) != 0) return -1;
  char tail[16];
  memset(tail, 0xff, sizeof tail);
  if (!api->get_property((RimeSessionId)s, "kinfx_digit_tail", tail, sizeof tail)) return 0;
  if (!memchr(tail, 0, sizeof tail - 1)) return -1;
  if (!*tail) return 0;
  if (!strcmp(tail, "1")) return 1;
  return -1;
}
int kx_restore_idle_digit_tail(uintptr_t s, int tail) {
  if (tail < 0 || tail > 1 || kx_has_pending(s) != 0) return 0;
  const char *value = tail == 1 ? "1" : "";
  api->set_property((RimeSessionId)s, "kinfx_digit_tail", value);
  return kx_idle_digit_tail(s) == tail;
}

int kx_option(uintptr_t s, const char *key) { return kx_alive(s) && api->get_option(s, key); }
void kx_set_option(uintptr_t s, const char *key, int value) {
  if (kx_alive(s)) api->set_option(s, key, value);
}

char *kx_property(uintptr_t s, const char *key) {
  char buf[4096];
  if (!api || !api->get_property((RimeSessionId)s, key, buf, sizeof buf)) return NULL;
  return strdup(buf);
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

// Display v1 is optional and bounded, not blur/commit text. RimeGetProperty
// uses strncpy without a length query or a guaranteed terminator. Reject a
// full buffer, including a provider truncating with a final NUL: never strdup
// a potentially truncated value or use kx_property's legacy 4KB path here.
static int bounded_property(uintptr_t s, const char *key, char *buf, size_t cap) {
  memset(buf, 0xff, cap);
  return api->get_property((RimeSessionId)s, key, buf, cap) &&
         memchr(buf, 0, cap - 1) != NULL;
}

static int decimal(const char *text, size_t *out) {
  size_t n = 0;
  if (!*text) return 0;
  for (; *text; ++text) {
    if (*text < '0' || *text > '9' || n > (INT_MAX - (*text - '0')) / 10U) return 0;
    n = n * 10 + (unsigned)(*text - '0');
  }
  *out = n;
  return 1;
}

static int utf8_cursor(const char *text, size_t cursor) {
  const unsigned char *p = (const unsigned char *)text;
  size_t i = 0;
  int boundary = cursor == 0;
  while (p[i]) {
    unsigned c = p[i++], n = 0, cp = c;
    if (c < 32 || c == 127) return 0;
    if (c >= 0xc2 && c <= 0xdf) { n = 1; cp = c & 31; }
    else if (c >= 0xe0 && c <= 0xef) { n = 2; cp = c & 15; }
    else if (c >= 0xf0 && c <= 0xf4) { n = 3; cp = c & 7; }
    else if (c >= 128) return 0;
    for (unsigned j = 0; j < n; ++j) {
      unsigned next = p[i];
      if (next < 128 || next >= 192) return 0;
      cp = (cp << 6) | (next & 63); ++i;
    }
    if ((n == 1 && cp < 128) || (n == 2 && cp < 2048) ||
        (n == 3 && cp < 65536) || cp > 0x10ffff || (cp >= 0xd800 && cp <= 0xdfff)) return 0;
    if (i == cursor) boundary = 1;
  }
  return boundary;
}

static const char *display_snapshot(uintptr_t s, char *buf, size_t cap, int *cursor) {
  if (!RIME_API_AVAILABLE(api, get_input) || !RIME_API_AVAILABLE(api, get_caret_pos) ||
      !bounded_property(s, "kinfx_display", buf, cap)) return NULL;
  char *fields[6] = {buf};
  for (int i = 1; i < 6; ++i) {
    char *end = strchr(fields[i - 1], '\n');
    if (!end) return NULL;
    *end = 0; fields[i] = end + 1;
  }
  char owner[64];
  size_t raw_cursor, display_cursor, id;
  const char *input = api->get_input((RimeSessionId)s);
  if (strcmp(fields[0], "1") || !decimal(fields[1], &id) || !id ||
      !bounded_property(s, "kinfx_english_state", owner, sizeof owner) || strcmp(fields[1], owner) ||
      !input || !*input || strcmp(fields[2], input) || strlen(input) > 2048 ||
      !decimal(fields[3], &raw_cursor) || raw_cursor != api->get_caret_pos((RimeSessionId)s) ||
      !decimal(fields[4], &display_cursor) || strlen(fields[5]) > 2048 ||
      !utf8_cursor(fields[5], display_cursor)) return NULL;
  *cursor = (int)display_cursor;
  return fields[5];
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
  char display[8192];
  int cursor = ctx.composition.cursor_pos;
  const char *preedit = display_snapshot(s, display, sizeof display, &cursor);
  append(&buf, &len, &cap, preedit ? preedit : ctx.composition.preedit);
  snprintf(num, sizeof num, "\x1f%d\x1f%d\x1f%d\x1f%d\x1f%d", cursor,
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
