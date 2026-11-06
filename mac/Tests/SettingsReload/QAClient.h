#import <Cocoa/Cocoa.h>
#import <InputMethodKit/InputMethodKit.h>
#include "kx_shim.h"
@interface QAClient : NSTextView <IMKTextInput>
@property NSInteger insertCalls;
@property NSInteger emptyInsertCalls;
@property NSInteger markedCalls;
@property NSRect suppliedCaret;
@property BOOL useSuppliedCaret;
@property NSMutableArray *insertionLog;
@property NSMutableArray *geometryLog;
@property id qaController;
@property NSMutableArray *actualEventLog;
@end
int qa_full_shape(uintptr_t s);
void qa_set_full_shape(uintptr_t s,int v);
char *qa_raw(uintptr_t s);
void qa_set_ascii(uintptr_t s,int v);
int qa_ascii(uintptr_t s);
void qa_set_caret(uintptr_t s,int pos);
char *qa_property(uintptr_t s,const char *name);
const char *qa_version(void);
