#ifndef KX_SHIM_H
#define KX_SHIM_H
#include <stdint.h>

int kx_start(const char *shared_dir, const char *user_dir, const char *log_dir, int full_check);
int kx_redeploy(void);
uintptr_t kx_session(const char *schema);
int kx_alive(uintptr_t s);
void kx_destroy(uintptr_t s);
void kx_clear(uintptr_t s);
int kx_key(uintptr_t s, int keycode, int mask);
int kx_select_candidate_on_current_page(uintptr_t s, int index);
int kx_commit_composition(uintptr_t s);
int kx_has_pending(uintptr_t s);  // 0 idle, 1 pending, -1 unknown
int kx_option(uintptr_t s, const char *key);
void kx_set_option(uintptr_t s, const char *key, int value);
// Validated same-controller idle script context only; never composition text.
int kx_idle_punct_tail(uintptr_t s);  // -1 unknown/pending, 0 empty, 1 Latin, 2 other
int kx_restore_idle_punct_tail(uintptr_t s, int tail);
int kx_idle_digit_tail(uintptr_t s);  // -1 unknown/pending, 0 empty, 1 digit-led run
int kx_restore_idle_digit_tail(uintptr_t s, int tail);
char *kx_take_commit(uintptr_t s);  // caller frees
char *kx_context(uintptr_t s);      // caller frees
char *kx_property(uintptr_t s, const char *key);  // caller frees

#endif
