#include "QAClient.h"
void qat_fail_reload(int f);
void qat_option(uintptr_t s,const char*k,int v);
int qat_get_option(uintptr_t s,const char*k);
void qat_destroy(uintptr_t s);
void qat_property(uintptr_t s,const char*k,const char*v);
void qat_fail_session(int f);
void qat_fail_restore(int f);
char *qat_schema(uintptr_t s);
int qat_deploy(const char *path);
uintptr_t qat_bad_selection(int success);
int qat_last_created_alive(void);
const char *qat_last_default_schema(void);
