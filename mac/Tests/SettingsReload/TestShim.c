#define kx_redeploy kxt_real_redeploy
#define kx_session kxt_real_session
#define kx_restore_idle_punct_tail kxt_real_restore
#include "../../Sources/Shim/kx_shim.c"
#undef kx_redeploy
#undef kx_session
#undef kx_restore_idle_punct_tail
static int fail_reload=0, fail_session=0, fail_restore=0;
int kx_redeploy(void){int ok=kxt_real_redeploy();return fail_reload?0:ok;}
uintptr_t kx_session(const char *schema){return fail_session?0:kxt_real_session(schema);}
int kx_restore_idle_punct_tail(uintptr_t s,int tail){return fail_restore?0:kxt_real_restore(s,tail);}
void qat_fail_reload(int f){fail_reload=f;}
void qat_fail_session(int f){fail_session=f;}
void qat_fail_restore(int f){fail_restore=f;}
void qat_option(uintptr_t s,const char*k,int v){api->set_option(s,k,v);}
int qat_get_option(uintptr_t s,const char*k){return api->get_option(s,k);}
void qat_destroy(uintptr_t s){api->destroy_session(s);}
void qat_property(uintptr_t s,const char*k,const char*v){api->set_property(s,k,v);}
int qat_deploy(const char *path){return api->deploy_schema(path);}
char *qat_schema(uintptr_t s){RIME_STRUCT(RimeStatus,status);if(!api->get_status(s,&status))return strdup("");char *out=strdup(status.schema_id?status.schema_id:"");api->free_status(&status);return out;}
static Bool (*real_select)(RimeSessionId,const char*);
static RimeSessionId (*real_create)(void);
static RimeSessionId last_created;
static int lie_select;
static Bool forced_select(RimeSessionId s,const char *schema){return lie_select==2;}
static char last_default_schema[128];
static RimeSessionId capture_create(void){last_created=real_create();RIME_STRUCT(RimeStatus,status);last_default_schema[0]=0;if(api->get_status(last_created,&status)){snprintf(last_default_schema,sizeof last_default_schema,"%s",status.schema_id?status.schema_id:"");api->free_status(&status);}return last_created;}
const char *qat_last_default_schema(void){return last_default_schema;}
// Real create_session defaults to the valid KINFX schema; force selection's
// return value only, so native get_status can reveal the wrong dictionary.
uintptr_t qat_bad_selection(int success){real_select=api->select_schema;real_create=api->create_session;lie_select=success?2:1;api->select_schema=forced_select;api->create_session=capture_create;uintptr_t s=kxt_real_session("qa_other_schema");api->select_schema=real_select;api->create_session=real_create;return s;}
int qat_last_created_alive(void){return api->find_session(last_created);}
