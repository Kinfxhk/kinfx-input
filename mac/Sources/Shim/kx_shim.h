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
int kx_commit_composition(uintptr_t s);
char *kx_take_commit(uintptr_t s);  // caller frees
char *kx_context(uintptr_t s);      // caller frees
char *kx_property(uintptr_t s, const char *key);  // caller frees

#endif
