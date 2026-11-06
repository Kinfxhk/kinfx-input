#!/usr/bin/env python3
"""Exact production pure display_plan via the shipped librime Lua 5.4 runtime.
Supplementary unit/boundary proof, NOT native/UI acceptance.
"""
import argparse
import ctypes as C
import json
from pathlib import Path
import resource

p=argparse.ArgumentParser()
p.add_argument('--source',type=Path,required=True)
p.add_argument('--lua-lib',type=Path,required=True)
p.add_argument('--shim-lib',type=Path,required=True)
p.add_argument('--output',type=Path,required=True)
a=p.parse_args()
resource.setrlimit(resource.RLIMIT_CORE,(0,0))
C.CDLL(str(a.shim_lib),mode=C.RTLD_GLOBAL)
l=C.CDLL(str(a.lua_lib))
l.luaL_newstate.restype=C.c_void_p
l.luaL_openlibs.argtypes=[C.c_void_p]
l.luaL_loadstring.argtypes=[C.c_void_p,C.c_char_p]
l.lua_pcallk.argtypes=[C.c_void_p,C.c_int,C.c_int,C.c_int,C.c_longlong,C.c_void_p]
l.lua_tolstring.argtypes=[C.c_void_p,C.c_int,C.c_void_p];l.lua_tolstring.restype=C.c_char_p
l.lua_close.argtypes=[C.c_void_p]
source=a.source.read_text()
start=source.index('local function display_plan(s)\n')
end=source.index('\npublish_display =',start)
exact=source[start:end]
script=exact+r'''
local count = 0
local function check(ok, name)
  count = count + 1
  assert(ok, name)
end
local function state(extra)
  local s = { smart=true, letters=true, selected=false, native_latin=false,
    input='xe', caret=2, defer='昨', pending='', tracking=true, raw='xe',
    rescue=true, rescue_raw='asxe', known=true, native_text='難水', native_cursor=6 }
  for k,v in pairs(extra or {}) do s[k]=v end
  return s
end
local function invalid(extra,name)
  check(not display_plan(state(extra)).valid,name)
end
local p=display_plan(state())
check(p.valid and p.text=='昨xe' and p.cursor==5,'known-tail prefix')
p=display_plan(state{known=false,rescue_raw='asxz',input='xz'})
check(p.valid and p.text=='asxz' and p.cursor==4,'rescue entire raw')
p=display_plan(state{letters=false})
check(p.valid and p.text=='昨難水' and p.cursor==9,'radicals keep native')
for _,caret in ipairs{0,1,2} do
  p=display_plan(state{caret=caret})
  check(p.valid and p.cursor==3+caret,'tail caret mapping')
end
for _,c in ipairs{0,3,6} do
  p=display_plan(state{letters=false,native_cursor=c})
  check(p.valid and p.cursor==3+c,'radical native caret mapping')
end
invalid({smart=false},'off')
invalid({selected=true},'explicit selected prefix')
invalid({native_latin=true},'native token')
invalid({input='x@e'},'syntax')
invalid({caret=-1},'negative caret')
invalid({caret=3},'caret out of raw bounds')
invalid({raw='zz'},'mismatching raw suffix')
invalid({letters=false,native_cursor=-3},'negative native caret')
invalid({letters=false,native_cursor=9},'native caret past native text')
invalid({letters=false,native_cursor=1},'split native utf8')
invalid({letters=false,native_text=string.char(255)},'malformed native utf8')
invalid({defer=string.char(31)},'wire separator')
invalid({input=string.rep('a',2049)},'oversized native source')
invalid({raw=string.rep('a',2049)..'xe'},'oversized displayed raw')
invalid({defer=string.rep('昨',683)},'oversized displayed prefix')
invalid({defer='',pending=''},'ordinary native tail not owned')
for n=1,2046 do
  local raw=string.rep('a',n)..'xe'
  local s=state{raw=raw,defer=''}
  local before=s.raw..s.input..s.defer..s.pending
  local p=display_plan(s)
  check(p.valid and p.text==raw and p.cursor==#raw,'bounded ascii source property')
  check(before==s.raw..s.input..s.defer..s.pending,'pure snapshot does not mutate')
end
for n=1,681 do
  local prefix=string.rep('昨',n)
  for caret=0,2 do
    local p=display_plan(state{defer=prefix,caret=caret})
    check(p.valid and p.text==prefix..'xe' and p.cursor==#prefix+caret,
          'bounded UTF8 prefix property')
    check(utf8.len(p.text:sub(1,p.cursor))~=nil,'utf8 byte cursor prefix boundary')
    check(utf8.len(p.text:sub(p.cursor+1))~=nil,'utf8 byte cursor suffix boundary')
  end
end
return tostring(count)
'''
s=l.luaL_newstate();l.luaL_openlibs(s)
err=l.luaL_loadstring(s,script.encode())
if not err:err=l.lua_pcallk(s,0,1,0,0,None)
result=l.lua_tolstring(s,-1,None).decode()
l.lua_close(s)
output=dict(scope='exact production pure function unit/property tests; NOT native/UI',
            passed=err==0,assertions=int(result) if not err else None,error=result if err else '')
a.output.write_text(json.dumps(output,ensure_ascii=False,indent=2));print(json.dumps(output))
raise SystemExit(int(err!=0))
