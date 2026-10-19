-- KINFX v0.5 association phrases 聯想 (Windows-style).
--
-- After a single Chinese character is picked (digit / Enter), show follow-up
-- words keyed by that character: 我 → 同 講 望 … (suffix only; picking appends
-- to the already-committed character). Suffixes live in the native kinfx_assoc
-- table; Lua only encodes the character's code point to its lookup code
-- (hex 0-f → a-p) and drives the menu.
--
-- Key rules measured on the user's MS Quick:
--   Shift+digit picks (exclam at numbersign … = 1-9); a plain digit types the
--   digit and closes; Space pages and is swallowed; Esc / BackSpace / Enter /
--   Left Shift close without deleting; letters close and start a new code;
--   punctuation closes and types. No chaining after a pick.
--
-- Components:
--   assoc_keys       — processor (before selector): open on a one-char pick,
--                      then handle the association menu keys.
--   assoc_translator — yields the suffix candidates for tag kinfx_assoc.

local kAccepted = 1
local kNoop = 2

local rearming = false

local function config_bool(config, path, default)
  local v = config:get_bool(path)
  if v == nil then
    return default
  end
  return v
end

local function config_int(config, path, default)
  local v = config:get_int(path)
  if v == nil or v < 1 then
    return default
  end
  return v
end

local function new_memory(env, ns)
  local ok, mem = pcall(function()
    return Memory(env.engine, Schema(ns))
  end)
  if ok then
    return mem
  end
  return nil
end

local function has_exact(mem, code)
  if not mem then
    return false
  end
  local ok, hit = pcall(function()
    return mem:dict_lookup(code, false, 1)
  end)
  return ok and hit and true or false
end

-- hex 0-f -> a-p
local function encode_char(ch)
  local b1 = ch:byte(1)
  local cp
  if b1 < 0x80 then
    cp = b1
  elseif b1 < 0xE0 then
    cp = ((b1 - 0xC0) * 0x40) + (ch:byte(2) - 0x80)
  elseif b1 < 0xF0 then
    cp = ((b1 - 0xE0) * 0x1000) + ((ch:byte(2) - 0x80) * 0x40) + (ch:byte(3) - 0x80)
  else
    cp = ((b1 - 0xF0) * 0x40000) + ((ch:byte(2) - 0x80) * 0x1000)
      + ((ch:byte(3) - 0x80) * 0x40) + (ch:byte(4) - 0x80)
  end
  local hex = string.format("%x", cp)
  local out = {}
  for i = 1, #hex do
    out[#out + 1] = string.char(97 + tonumber(hex:sub(i, i), 16))
  end
  return table.concat(out)
end

local function utf8_count(s)
  local _, n = s:gsub("[^\128-\193]", "")
  return n
end

local function is_single_cjk(s)
  if not s or s == "" then
    return false
  end
  return utf8_count(s) == 1
end

local function page_size_of(env)
  local n = env.engine.schema.page_size
  if not n or n < 1 then
    return 9
  end
  return n
end

local function page_start_of(seg, ps)
  local idx = seg.selected_index or 0
  if idx < 0 then
    idx = 0
  end
  return idx - (idx % ps)
end

local function assoc_active(ctx)
  local comp = ctx.composition
  if not comp or comp:empty() then
    return false
  end
  local seg = comp:back()
  return seg and seg:has_tag("kinfx_assoc") or false
end

local function close_assoc(ctx)
  local comp = ctx.composition
  if comp and not comp:empty() then
    local seg = comp:back()
    if seg and seg:has_tag("kinfx_assoc") then
      comp:pop_back()
    end
  end
  ctx:set_property("kinfx_assoc_code", "")
end

local function open_assoc(env, ctx, ch)
  local code = encode_char(ch)
  if not has_exact(env.mem, code) then
    return false
  end
  local seg = Segment(0, 0)
  seg.tags = Set({ "kinfx_assoc", "placeholder" })
  local comp = ctx.composition
  rearming = true
  comp:push_back(seg)
  ctx:set_property("kinfx_assoc_code", code)
  -- Fire update_notifier to re-translate the placeholder. refresh_non_confirmed
  -- would CLEAR the composition (dropping the segment); setting caret_pos
  -- re-fires the update notifier without clearing.
  ctx.caret_pos = 0
  rearming = false
  return true
end

-- ---------------------------------------------------------------- translator

local function translator_init(env)
  env.mem = new_memory(env, "kinfx_assoc")
  env.max = config_int(env.engine.schema.config, "association/max", 36)
end

local function translator_func(input, seg, env)
  if not seg:has_tag("kinfx_assoc") then
    return
  end
  local ctx = env.engine.context
  local code = ctx:get_property("kinfx_assoc_code") or ""
  if code == "" or not env.mem then
    return
  end
  pcall(function()
    if env.mem:dict_lookup(code, false, env.max) then
      local n = 0
      for entry in env.mem:iter_dict() do
        yield(Candidate("phrase", seg.start, seg._end, entry.text, ""))
        n = n + 1
        if n >= env.max then
          break
        end
      end
    end
  end)
end

-- ---------------------------------------------------------------- processor

local SHIFT_DIGIT = {
  exclam = 1,
  at = 2,
  numbersign = 3,
  dollar = 4,
  percent = 5,
  asciicircum = 6,
  ampersand = 7,
  asterisk = 8,
  parenleft = 9,
}

local function processor_init(env)
  local config = env.engine.schema.config
  env.enable = config_bool(config, "association/enable", true)
  env.mem = new_memory(env, "kinfx_assoc")
  if not env.enable then
    return
  end
  -- Weasel clears the composition after a commit (the TSF composition ends),
  -- which drops the placeholder segment. Like librime-predict, put it back on
  -- every update while the association is armed (kinfx_assoc_code set) and
  -- nothing is being composed. Every closing path clears kinfx_assoc_code.
  env.update_conn = env.engine.context.update_notifier:connect(function(ctx)
    if rearming then
      return
    end
    local code = ctx:get_property("kinfx_assoc_code") or ""
    if code == "" or (ctx.input or "") ~= "" then
      return
    end
    local comp = ctx.composition
    if comp and not comp:empty() then
      return
    end
    rearming = true
    local seg = Segment(0, 0)
    seg.tags = Set({ "kinfx_assoc", "placeholder" })
    comp:push_back(seg)
    ctx.caret_pos = 0
    rearming = false
  end)
end

local function processor_fini(env)
  if env.update_conn then
    env.update_conn:disconnect()
  end
end

local function handle_pick(env, ctx, repr)
  local digit = repr:match("^([1-9])$") or repr:match("^KP_([1-9])$")
  local is_return = repr == "Return" or repr == "KP_Enter"
  if not digit and not is_return then
    return kNoop
  end
  if not ctx:has_menu() then
    return kNoop
  end
  -- Only a plain Windows pick (1-2 letter code) opens it, never a held
  -- phrase / English run (3+ letters).
  if #(ctx.input or "") > 2 then
    return kNoop
  end
  local seg = ctx.composition and ctx.composition:back() or nil
  if not seg then
    return kNoop
  end
  local ps = page_size_of(env)
  local start = page_start_of(seg, ps)
  local index = start
  if digit then
    index = start + tonumber(digit) - 1
  else
    index = seg.selected_index or start
    if index < start then
      index = start
    end
  end
  local cand = seg:get_candidate_at(index)
  if not cand or not cand.text or not is_single_cjk(cand.text) then
    return kNoop
  end
  seg.selected_index = index
  ctx:confirm_current_selection()
  open_assoc(env, ctx, cand.text)
  return kAccepted
end

local function handle_assoc(env, ctx, repr)
  local seg = ctx.composition:back()
  local ps = page_size_of(env)

  -- Shift+digit picks the suffix.
  -- Weasel may send the shifted keysym with or without the Shift modifier.
  local base = repr:match("^Shift%+(%a+)$") or repr
  local d = base and SHIFT_DIGIT[base] or nil
  if d then
    local start = page_start_of(seg, ps)
    local index = start + d - 1
    local cand = seg:get_candidate_at(index)
    if cand and cand.text then
      seg.selected_index = index
      ctx:confirm_current_selection()
    end
    close_assoc(ctx)
    return kAccepted
  end

  -- Plain digit (main row or keypad) types the digit and closes.
  local digit = repr:match("^([0-9])$") or repr:match("^KP_([0-9])$")
  if digit then
    close_assoc(ctx)
    env.engine:commit_text(digit)
    return kAccepted
  end

  -- Esc / BackSpace close without deleting. A Left Shift tap closes
  -- it too (english_mix, before ascii_composer); a Shift press alone must not,
  -- or Shift+digit could never pick.
  if repr == "Escape" or repr == "BackSpace" then
    close_assoc(ctx)
    return kAccepted
  end
  -- Enter closes and still reaches the app as a newline (kinfx-input real keys:
  -- vd1 Return iPhone must give two lines).
  if repr == "Return" or repr == "KP_Enter" then
    close_assoc(ctx)
    return kNoop
  end

  -- Letters close and start a new code.
  if repr:match("^[a-z]$") then
    close_assoc(ctx)
    return kNoop
  end

  -- Punctuation closes and types.
  if repr == "comma" or repr == "period" then
    close_assoc(ctx)
    return kNoop
  end

  -- Space is mapped to Page_Down by key_binder before this processor; swallow.
  if repr == "space" then
    return kAccepted
  end

  return kNoop
end

local function processor_func(key, env)
  if not env.enable then
    return kNoop
  end
  if key:release() or key:ctrl() or key:alt() or key:super() then
    return kNoop
  end
  local ctx = env.engine.context
  local repr = key:repr()
  local kc = key.keycode
  if kc == 0xffe1 or kc == 0xffe2 then
    return kNoop
  end
  if assoc_active(ctx) then
    return handle_assoc(env, ctx, repr)
  end
  if (ctx:get_property("kinfx_assoc_code") or "") ~= "" then
    ctx:set_property("kinfx_assoc_code", "") -- stale arm: never reopen later
  end
  return handle_pick(env, ctx, repr)
end

return {
  processor = { init = processor_init, func = processor_func, fini = processor_fini },
  translator = { init = translator_init, func = translator_func },
}
