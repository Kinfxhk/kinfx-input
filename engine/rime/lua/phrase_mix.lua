-- KINFX phrase / English mix on top of Windows-style Sucheng.
--
-- Lookups go to librime's compiled tables (kinfx_quick_phrase, kinfx_en) through
-- Memory:dict_lookup. Nothing large lives in the Lua heap, so a keystroke costs
-- a few milliseconds instead of a garbage-collector sweep over 240k rows.
--
-- Key rule (Windows first):
--   * Two letters, then a third: Windows tops out (頂字) and starts a new code.
--     KINFX holds keys 3 and 4 only while the input is in the gate list
--     (kinfx_capture.txt: prefixes of common phrases, plus full 4-letter
--     phrases such as ofch 無錫). So ofc shows 人類 / 無錯, ofca = 無錯.
--   * From key 5, any word in the compiled phrase table keeps it held. When
--     nothing continues, Windows takes over: the first candidate of each full
--     pair is committed and the rest becomes the new code, so ofcx → 伙 + cx
--     and vd o f 3 still gives 好係.
--   * English hold words ("+gmail" lines in kinfx_capture.txt: Gmail,
--     scriptwriting, voiceover ...) keep every letter while the input is still
--     a prefix of such a word. Other English goes through Shift or uppercase.
-- Segmentor: tags the held abc segment kinfx_phrase / kinfx_en (len ≥ 3) so the
-- native phrase / English translators never touch two-letter page 1.

local kAccepted = 1
local kNoop = 2

local function config_bool(config, path, default)
  local v = config:get_bool(path)
  if v == nil then
    return default
  end
  return v
end

local function user_file(name)
  if not rime_api or not rime_api.get_user_data_dir then
    return nil
  end
  local dir = rime_api.get_user_data_dir()
  if not dir or dir == "" then
    return nil
  end
  return dir .. "/" .. name
end

-- Small set: one 3-letter prefix per line (about a thousand lines).
local capture_cache = nil
local hold_words = nil
local function load_capture()
  if capture_cache then
    return capture_cache, hold_words
  end
  capture_cache = {}
  hold_words = {}
  local path = user_file("kinfx_capture.txt")
  local fh = path and io.open(path, "r")
  if fh then
    for line in fh:lines() do
      local w = line:match("^%+([a-z]+)")
      if w then
        -- English hold words live in their own list; they never enter the
        -- Chinese gate set, so gm+a still tops out when English is off.
        hold_words[#hold_words + 1] = w
      else
        local p = line:match("^([a-z][a-z][a-z]+)%s*$")
        if p then
          capture_cache[p] = true
        end
      end
    end
    fh:close()
  end
  return capture_cache, hold_words
end

local function is_hold_prefix(words, code)
  for _, w in ipairs(words) do
    if #w >= #code and w:sub(1, #code) == code then
      return true
    end
  end
  return false
end

local function new_memory(env, ns)
  local ok, mem = pcall(function()
    if ns then
      return Memory(env.engine, Schema(ns))
    end
    return Memory(env.engine, env.engine.schema)
  end)
  if ok then
    return mem
  end
  return nil
end

local function has_prefix(mem, code)
  if not mem then
    return false
  end
  local ok, hit = pcall(function()
    return mem:dict_lookup(code, true, 1)
  end)
  return ok and hit and true or false
end

local function first_text(mem, code)
  if not mem then
    return nil
  end
  local found = nil
  pcall(function()
    if mem:dict_lookup(code, false, 1) then
      for entry in mem:iter_dict() do
        found = entry.text
        break
      end
    end
  end)
  return found
end

-- english/mode: smart (v0.5) | shift (v0.4.1) | off (no English at all).
local function english_on(config)
  if not config_bool(config, "english/enable", true) then
    return false
  end
  return (config:get_string("english/mode") or "smart") ~= "off"
end

local function processor_init(env)
  local config = env.engine.schema.config
  env.enable = config_bool(config, "phrase_mix/enable", true)
  env.eng_enable = english_on(config)
  env.capture = config:get_string("phrase_mix/capture") or "hot"
  env.main = new_memory(env, nil)
  env.phrase = new_memory(env, "kinfx_phrase")
  env.hot, env.hold = load_capture()
end

local function may_capture(env, code)
  -- English hold words follow english/enable only; capture: none is the
  -- Chinese switch (pure Windows top-out), so gmai → Gmail still works.
  if env.eng_enable and is_hold_prefix(env.hold, code) then
    return true
  end
  if env.capture == "none" or not env.enable then
    return false
  end
  if env.hot[code] then
    return true
  end
  if env.capture == "all" and has_prefix(env.phrase, code) then
    return true
  end
  return false
end

-- After the gate: any phrase or English hold word that continues the input.
local function continues(env, code)
  if env.enable and env.capture ~= "none" and has_prefix(env.phrase, code) then
    return true
  end
  if env.eng_enable and is_hold_prefix(env.hold, code) then
    return true
  end
  return false
end

-- Windows fallback: commit the top candidate of each complete pair.
local function split_commit(env, ctx, input, ch)
  local out = {}
  local i = 1
  while i + 1 <= #input do
    local text = first_text(env.main, input:sub(i, i + 1))
    if not text then
      return false
    end
    out[#out + 1] = text
    i = i + 2
  end
  local rest = input:sub(i) .. ch
  ctx:clear()
  env.engine:commit_text(table.concat(out))
  ctx:push_input(rest)
  return true
end

local function processor_func(key, env)
  if not env.enable and not env.eng_enable then
    return kNoop
  end
  if key:release() or key:ctrl() or key:alt() or key:super() then
    return kNoop
  end
  local ch = key:repr()
  if not ch or not ch:match("^[a-z]$") then
    return kNoop
  end
  local ctx = env.engine.context
  local input = ctx.input or ""
  if #input < 2 or not input:match("^[a-z]+$") then
    return kNoop
  end
  local extended = input .. ch
  if #input == 2 then
    if may_capture(env, extended) and ctx:push_input(ch) then
      return kAccepted
    end
    return kNoop -- speller tops out, exactly like Windows
  end
  -- Held composition (length ≥ 3). Key 4 must pass the gate list too
  -- (ofca 無錯, ofch 無錫); a full-table key 4 would turn 好同 into 好貼.
  -- From key 5 on, any phrase in the compiled table keeps it held.
  local gated = may_capture(env, extended)
  if gated or (#extended >= 5 and continues(env, extended)) then
    ctx:push_input(ch)
    return kAccepted
  end
  if split_commit(env, ctx, input, ch) then
    return kAccepted
  end
  return kNoop
end

-- Tag long abc segments so the native phrase / English translators run there
-- only, and only when their switch is on. English starts at 4 letters.
local function segmentor_init(env)
  local config = env.engine.schema.config
  env.enable = config_bool(config, "phrase_mix/enable", true)
  env.eng_enable = english_on(config)
end

local function segmentor_func(segmentation, env)
  if segmentation:empty() then
    return true
  end
  local seg = segmentation:back()
  if not seg or not seg:has_tag("abc") then
    return true
  end
  local n = seg._end - seg.start
  local tags = {}
  if env.enable and n >= 3 then
    tags[#tags + 1] = "kinfx_phrase"
  end
  if env.eng_enable and n >= 4 then
    tags[#tags + 1] = "kinfx_en"
  end
  if #tags > 0 then
    seg.tags = seg.tags + Set(tags)
  end
  return true
end

-- Shared with english_mix.lua: it replays this exact key rule to know what
-- Windows / v0.4.1 would have committed while it delays the top-out.
local helpers = {
  config_bool = config_bool,
  new_memory = new_memory,
  has_prefix = has_prefix,
  first_text = first_text,
  load_capture = load_capture,
  is_hold_prefix = is_hold_prefix,
  init = processor_init,
  may_capture = may_capture,
  continues = continues,
}

return {
  processor = { init = processor_init, func = processor_func },
  segmentor = { init = segmentor_init, func = segmentor_func },
  helpers = helpers,
}
