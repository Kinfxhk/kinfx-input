#include <stdlib.h>
#include <string.h>
#include "rime_api.h"
#include "support.h"
int test_full_shape(uintptr_t session) {
  return rime_get_api()->get_option((RimeSessionId)session, "full_shape");
}
void test_set_full_shape(uintptr_t session, int value) {
  rime_get_api()->set_option((RimeSessionId)session, "full_shape", value);
}
char *test_raw_input(uintptr_t session) {
  const char *input = rime_get_api()->get_input((RimeSessionId)session);
  return strdup(input ? input : "");
}
