#include "display-caret.h"
#include <cassert>
int main(){
 assert(kx::DisplayCaretUtf16("abc","1")==1);
 assert(kx::DisplayCaretUtf16("\xe6\x98\xa8xe","3")==1);
 assert(kx::DisplayCaretUtf16("\xe6\x98\xa8xe","4")==2);
 assert(kx::DisplayCaretUtf16("\xf0\x9f\x98\x80x","4")==2);
 assert(kx::DisplayCaretUtf16("\xe6\x98\xa8xe","1")==3);
 assert(kx::DisplayCaretUtf16("abc","999999999999999999999")==3);
 assert(kx::DisplayCaretUtf16("abc","-1")==3);
 assert(kx::DisplayCaretUtf16("abc","")==3);
 assert(kx::DisplayCaretUtf16("abc","0")==0);
 return 0;
}
