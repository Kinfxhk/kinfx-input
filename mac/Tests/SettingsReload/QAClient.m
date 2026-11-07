#import "QAClient.h"
#include "rime_api.h"
@implementation QAClient
- (BOOL)becomeFirstResponder {return [super becomeFirstResponder];}
- (BOOL)resignFirstResponder {if(self.qaController)[self.qaController deactivateServer:self];return [super resignFirstResponder];}
- (void)keyDown:(NSEvent*)e {if(self.qaController){BOOL h=[self.qaController inputText:e.characters key:e.keyCode modifiers:e.modifierFlags client:self];if(!self.actualEventLog)self.actualEventLog=[NSMutableArray new];[self.actualEventLog addObject:@{@"type":@(e.type),@"key":@(e.keyCode),@"flags":@(e.modifierFlags),@"characters":e.characters?:@"",@"handled":@(h)}];if(!h){if(e.keyCode==36)[self insertNewline:self];else if(e.characters.length)[self insertText:e.characters replacementRange:NSMakeRange(NSNotFound,0)];}return;}[super keyDown:e];}
- (void)flagsChanged:(NSEvent*)e {if(self.qaController){[self.qaController handleEvent:e client:self];return;}[super flagsChanged:e];}
- (instancetype)initWithFrame:(NSRect)r { self=[super initWithFrame:r]; if(self){_insertionLog=[NSMutableArray new];_geometryLog=[NSMutableArray new];}return self;}
- (void)insertText:(id)s replacementRange:(NSRange)r { NSString *t=[s isKindOfClass:[NSAttributedString class]]?[s string]:s; self.insertCalls++;if([t length]==0)self.emptyInsertCalls++;[self.insertionLog addObject:@{@"text":t?:@"",@"replacement":@[@(r.location),@(r.length)]}];[super insertText:s replacementRange:r];}
- (void)setMarkedText:(id)s selectionRange:(NSRange)a replacementRange:(NSRange)b {self.markedCalls++;[super setMarkedText:s selectedRange:a replacementRange:b];}
- (NSDictionary*)attributesForCharacterIndex:(NSUInteger)i lineHeightRectangle:(NSRect*)r {NSRange m=[self markedRange];NSUInteger n=(m.location==NSNotFound?[self selectedRange].location:m.location)+i;NSRange actual;NSRect q=self.useSuppliedCaret?self.suppliedCaret:[self firstRectForCharacterRange:NSMakeRange(n,0) actualRange:&actual];if(r)*r=q;[self.geometryLog addObject:@{@"inlineIndex":@(i),@"documentIndex":@(n),@"rect":@[@(q.origin.x),@(q.origin.y),@(q.size.width),@(q.size.height)]}];return @{};}
- (NSAttributedString*)attributedSubstringFromRange:(NSRange)r {if(NSMaxRange(r)>self.string.length)return nil;return [self.textStorage attributedSubstringFromRange:r];}
- (NSInteger)length {return self.string.length;}
- (NSInteger)characterIndexForPoint:(NSPoint)p tracking:(IMKLocationToOffsetMappingMode)m inMarkedRange:(BOOL*)b {if(b)*b=NO;return [self characterIndexForPoint:p];}
- (NSArray*)validAttributesForMarkedText {return @[];}
- (void)overrideKeyboardWithKeyboardNamed:(NSString*)s {}
- (void)selectInputMode:(NSString*)s {}
- (BOOL)supportsUnicode {return YES;}
- (NSString*)bundleIdentifier {return @"hk.kinfx.qa.frozen.v8";}
- (CGWindowLevel)windowLevel {return self.window.level;}
- (BOOL)supportsProperty:(TSMDocumentPropertyTag)p {return NO;}
- (NSString*)uniqueClientIdentifierString {return [NSString stringWithFormat:@"qa-%p",self];}
- (NSString*)stringFromRange:(NSRange)r actualRange:(NSRangePointer)a {if(NSMaxRange(r)>self.string.length)return nil;if(a)*a=r;return [self.string substringWithRange:r];}
@end
int qa_full_shape(uintptr_t s){return rime_get_api()->get_option(s,"full_shape");}
void qa_set_full_shape(uintptr_t s,int v){rime_get_api()->set_option(s,"full_shape",v);}
char *qa_raw(uintptr_t s){const char *p=rime_get_api()->get_input(s);return strdup(p?p:"");}
void qa_set_ascii(uintptr_t s,int v){rime_get_api()->set_option(s,"ascii_mode",v);}
int qa_ascii(uintptr_t s){return rime_get_api()->get_option(s,"ascii_mode");}
void qa_set_caret(uintptr_t s,int pos){rime_get_api()->set_caret_pos(s,pos);}
char *qa_property(uintptr_t s,const char *name){char b[1024]={0};rime_get_api()->get_property(s,name,b,sizeof(b));return strdup(b);}
const char *qa_version(void){return rime_get_api()->get_version();}
