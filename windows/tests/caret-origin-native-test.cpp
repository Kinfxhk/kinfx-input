#include "caret-origin.h"
#include <cstdio>
int main(){
 int n=0;
#define CHECK(x) do{++n;if(!(x)){std::printf("FAIL check %d: %s\n",n,#x);return 1;}}while(0)
 CHECK(kx::PreferEditCaret(true,true,true,true,true,435,992,48));
 CHECK(!kx::PreferEditCaret(false,true,true,true,true,435,992,48));
 CHECK(!kx::PreferEditCaret(true,false,true,true,true,435,992,48));
 CHECK(!kx::PreferEditCaret(true,true,false,true,true,435,992,48));
 CHECK(!kx::PreferEditCaret(true,true,true,false,true,435,992,48));
 CHECK(!kx::PreferEditCaret(true,true,true,true,false,435,992,48));
 CHECK(!kx::PreferEditCaret(true,true,true,true,true,656,650,48));
 CHECK(!kx::PreferEditCaret(true,true,true,true,true,698,650,48));
 CHECK(kx::PreferEditCaret(true,true,true,true,true,699,650,48));
 std::printf("PASS %d origin-policy checks\n",n);return 0;
}
