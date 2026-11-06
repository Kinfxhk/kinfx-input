#include "../../Sources/Shim/kx_shim.h"
// Read-only diagnostics plus per-test-session width setup; not production API.
int test_full_shape(uintptr_t session);
void test_set_full_shape(uintptr_t session, int value);
char *test_raw_input(uintptr_t session); // caller frees
