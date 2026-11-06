-- KINFX v0.5 English: delayed top-out + Space + Left Shift tap.
--
-- Rule: Chinese typed the Windows way must come out exactly as v0.4.1.
-- How: while the letters typed since the run started are still a prefix of an
-- English word (native kinfx_en table, never a Lua heap table), this processor
-- runs the same v0.4.1 key rule (phrase_mix helpers + speller top-out) for each
-- letter, but every top-out it would commit goes into a pending buffer instead
-- of the app. ctx.input therefore stays exactly in the v0.4.1 state (same menu,
-- same phrase hold, same paging).
--   * Space on a space-safe English word (>= 3 letters, not in
--     kinfx_en_unsafe.txt, no Chinese phrase held) commits the word + " ".
--   * A symbol on such a word stays ASCII; dot waits for a domain suffix.
--   * Left Shift tap (english/commit_key) commits the raw letters.
--   * Any other key first commits the pending buffer and then runs untouched,
--     so the app ends up with the v0.4.1 text.
--   * A letter that ends the English prefix does the same.
-- A run starts on an empty composition or right after a Windows top-out
-- (vd + hello: 好 is committed as usual, then hello is tracked).
-- english/mode: shift (= v0.4.1) or off turns all of this off.

local pm = require("phrase_mix").helpers

local kRejected = 0 -- the app gets the key (librime ProcessResult)
local kAccepted = 1
local kNoop = 2

-- full_shape remains the user's Chinese punctuation preference. English
-- commits must bypass librime's *global* ASCII-to-fullwidth ShapeFormatter.
local function full_shape(env) return env.engine.context:get_option("full_shape") end
local function remember_tail(ctx, text)
  -- Punctuation/spacing alone keeps the last script (hello,?! / 好，。).
  local tail = text and text:match("([A-Za-z\128-\255])[^A-Za-z\128-\255]*$")
  if tail then
    ctx:set_property("kinfx_punct_tail", tail:match("%a") and "latin" or "other")
  end
  -- Digit-led alphanumeric run (60cm, 12v, 2x6): a commit ending in a digit
  -- marks the run so the next lowercase letter is a unit/word tail, not a
  -- Sucheng code. A following lowercase letter keeps the flag; any other
  -- commit (CJK, uppercase, symbol, space) clears it.
  if text and text:match("%d$") then
    ctx:set_property("kinfx_digit_tail", "1")
  elseif not (text and text:match("[a-z]$")) then
    ctx:set_property("kinfx_digit_tail", "")
  end
end

local function commit_text(env, text, ascii)
  local ctx = env.engine.context
  local wide = full_shape(env) and (ascii or (text and text:find("%a")))
  -- Internal formatter bypass is not a user navigation transaction (a native
  -- commit notifier can call this while its old association is still visible).
  local internal = env.width_internal
  env.width_internal = true
  local ok, err = pcall(function()
    if wide then ctx:set_option("full_shape", false) end
    env.engine:commit_text(text)
  end)
  local restored, restore_err = true, nil
  if wide then
    restored, restore_err = pcall(function() ctx:set_option("full_shape", true) end)
  end
  env.width_internal = internal
  if not ok then error(err) end
  if not restored then error(restore_err) end
  remember_tail(ctx, text)
end
local META_MASK = 0x10000000 -- kMetaMask (1 << 28)

local function config_int(config, path, default)
  local v = config:get_int(path)
  if v == nil then
    return default
  end
  return v
end

local function config_str(config, path, default)
  local v = config:get_string(path)
  if v == nil or v == "" then
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

-- Global, cross-context full_shape. librime's Shift+Space toggle is a per-
-- context option that resets to the schema default (half-width) on every new
-- context, so the width choice would be lost on a window/app switch. Persist
-- the user's last toggle in the user data dir and restore it when a context is
-- created, so full/half width survives owner changes until the next toggle.
local function full_shape_state_path()
  return user_file("kinfx_full_shape.state")
end

local function restore_full_shape(ctx)
  local path = full_shape_state_path()
  if not path then return end
  local fh = io.open(path, "r")
  if not fh then return end
  local v = fh:read("*l")
  fh:close()
  if v == "1" or v == "0" then
    ctx:set_option("full_shape", v == "1")
  end
end

local function persist_full_shape(on)
  local path = full_shape_state_path()
  if not path then return end
  local fh = io.open(path, "w")
  if fh then
    fh:write(on and "1" or "0")
    fh:close()
  end
end

-- About 350 short words; small enough for a Lua set.
local unsafe_cache = nil
local function load_unsafe()
  if unsafe_cache then
    return unsafe_cache
  end
  unsafe_cache = {}
  local path = user_file("kinfx_en_unsafe.txt")
  local fh = path and io.open(path, "r")
  if fh then
    for line in fh:lines() do
      local w = line:match("^([a-z]+)%s*$")
      if w then
        unsafe_cache[w] = true
      end
    end
    fh:close()
  end
  return unsafe_cache
end

-- Product / company names (kinfx_en_names.txt: "Display<TAB>code", a few
-- hundred lines). Most are missing from SCOWL, so their letters would top out
-- as Chinese. A small Lua set of names and their prefixes (a few thousand
-- short strings) is fine for the heap; the big English table stays native.
local names_cache, name_prefix_cache = nil, nil
local function load_names()
  if names_cache then
    return names_cache, name_prefix_cache
  end
  names_cache, name_prefix_cache = {}, {}
  local path = user_file("kinfx_en_names.txt")
  local fh = path and io.open(path, "r")
  if fh then
    for line in fh:lines() do
      line = line:gsub("\r$", "")
      if line ~= "" and line:sub(1, 1) ~= "#" then
        local text, code = line:match("^([^\t]+)\t([a-z][a-z0-9]*)%s*$")
        if not code then
          code = line:match("^([a-z][a-z0-9]*)%s*$")
          text = code
        end
        if code then
          names_cache[code] = text
          for i = 1, #code do
            name_prefix_cache[code:sub(1, i)] = true
          end
        end
      end
    end
    fh:close()
  end
  return names_cache, name_prefix_cache
end

-- Display text for an exact English code: the lowercase entry when the table
-- has one, else its first entry (gmail -> Gmail). Second value: whether a
-- lowercase entry exists (proper nouns such as Chen / Ohio have none).
local function word_text(mem, code)
  if not mem then
    return nil
  end
  local first, exact = nil, nil
  pcall(function()
    if mem:dict_lookup(code, false, 20) then
      for entry in mem:iter_dict() do
        first = first or entry.text
        if entry.text == code then
          exact = entry.text
          break
        end
      end
    end
  end)
  return exact or first, exact ~= nil
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

-- Run state, shared by the processor and the hint filter (one Lua state).
-- known: length of the longest prefix of raw that is a kinfx_en prefix.
-- raw longer than known = an unknown word held on (wondershare, kubernetes).
-- known_en: the same length counted on kinfx_en + kinfx_en_names.txt only
-- (v0.5.3). Every Space path uses known_en, so kinfx_names prefixes (gior of
-- Giordano) lengthen the hold but never let Space take a Chinese run (giorj).
local S = { raw = "", pending = "", tracking = false, guard = false, known = 0, known_en = 0 }

local function reset()
  S.raw, S.pending, S.tracking, S.known, S.known_en = "", "", false, 0, 0
end

-- v0.5.4 Left Shift rescue. When a run that started as an English / name
-- prefix (rescue_min letters) breaks, the normal v0.5.3 path below keeps
-- running unchanged, but whatever it commits is parked in R.defer instead of
-- reaching the app. R.raw collects every letter since the run started.
-- A Left Shift tap then types R.raw (zdrav) unless the normal path holds a
-- complete word (vd + of -> 好of). Any other key commits R.defer first, so
-- the app text equals v0.5.3 for every key sequence without that tap.
local R = { alive = false, raw = "", defer = "", cap = 0 }

-- One Lua VM serves multiple librime contexts. Processor, notifiers and hint
-- filter must all select the state belonging to this context, not the last key.
local states, next_state = {}, 0
local function activate(env)
  local id = env.engine.context:get_property("kinfx_english_state")
  local state = states[id]
  if state then S, R = state.run, state.rescue end
end

local function rescue_drop()
  R.alive, R.raw, R.defer, R.cap = false, "", "", 0
end

-- Older builds put the hint in seg.prompt; nothing to clear now.
local function clear_hint(_ctx)
end

local function flush(env)
  local text = S.pending
  local was = S.tracking
  reset()
  -- letters mode: the menu still carries the whole run as its preedit (aaka
  -- while the input is ka); rebuild it now that the run is gone
  if was and env.letters then
    local ctx = env.engine.context
    if ctx:is_composing() then
      S.guard = true
      pcall(function() ctx:refresh_non_confirmed_composition() end)
      S.guard = false
    end
  end
  if text == "" then
    return
  end
  if R.alive then
    R.defer = R.defer .. text
  else
    commit_text(env, text)
  end
end

-- End the rescue the v0.5.3 way: the parked commits reach the app now.
local function rescue_end(env)
  local text = R.defer
  rescue_drop()
  if text ~= "" then
    commit_text(env, text)
  end
end

local function set_input(ctx, text)
  S.guard = true
  ctx.input = text
  S.guard = false
end

-- The top-out candidate v0.4.1's speller would confirm for a full 2-letter code.
local function topout_text(ctx, input)
  if not ctx:has_menu() then
    return nil
  end
  local cand = ctx:get_selected_candidate()
  if not cand or cand.start ~= 0 or cand._end ~= #input then
    return nil
  end
  return cand.text
end

-- One letter through the v0.4.1 rule with its commit sent to S.pending.
-- Returns false when v0.4.1 would take a path this does not mirror; the caller
-- then flushes and lets the normal processors run.
local function v041_letter(env, ctx, ch)
  local input = ctx.input or ""
  if #input < 2 then
    set_input(ctx, input .. ch)
    return true
  end
  local extended = input .. ch
  if #input == 2 then
    if pm.may_capture(env, extended) then
      set_input(ctx, extended)
      return true
    end
    if not ctx:has_menu() then
      set_input(ctx, extended) -- speller pushes when nothing to top out
      return true
    end
    local text = topout_text(ctx, input)
    if not text then
      return false
    end
    S.pending = S.pending .. text
    set_input(ctx, ch)
    return true
  end
  if pm.may_capture(env, extended) or (#extended >= 5 and pm.continues(env, extended)) then
    set_input(ctx, extended)
    return true
  end
  -- split_commit: first candidate of every complete pair, the rest stays.
  local out = {}
  local i = 1
  while i + 1 <= #input do
    local text = pm.first_text(env.main, input:sub(i, i + 1))
    if not text then
      return false
    end
    out[#out + 1] = text
    i = i + 2
  end
  S.pending = S.pending .. table.concat(out)
  set_input(ctx, input:sub(i) .. ch)
  return true
end

-- A Chinese phrase is held (the menu leads with a Chinese phrase for 3+
-- letters). Chinese wins there: Space and punctuation behave like v0.4.1.
local function chinese_held(ctx)
  -- Only a phrase that spans the whole letter run counts. When top-outs are
  -- already pending (passion: 旨巨 + ion → 之隔…), the Chinese phrase covers the
  -- tail only and the run as a whole is the English word.
  if S.pending ~= "" then
    return false
  end
  local input = ctx.input or ""
  if #input < 3 or not ctx:has_menu() then
    return false
  end
  local cand = ctx:get_selected_candidate()
  return cand ~= nil and cand.text:find("[\128-\255]") ~= nil
end

local function space_allowed(env, raw)
  -- 2 letters only for a listed name (gg wp gl), and only on Space (callers check #raw)
  if (#raw < 3 and not (#raw == 2 and env.names[raw])) or env.space_mode == "off" then
    return false
  end
  if env.space_mode == "long" and #raw < 5 then
    return false
  end
  if env.space_mode == "safe" and env.unsafe[raw] then
    return false
  end
  return true
end

local function commit_word(env, ctx, text)
  reset()
  S.guard = true
  ctx:clear()
  S.guard = false
  -- 。 is only the held-dot sentinel here, never final English punctuation.
  if text then text = text:gsub("。", ".") end
  commit_text(env, text)
end

-- v0.5.10: "." / "-" after an English word waits for the next key. A letter
-- keeps the whole token Latin (llama.cpp, openai.com, bait-and-switch: the
-- recognizer's url pattern takes the letters); any other key first commits
-- what v0.5.9 committed at the "." / "-" (hello。 / tool-), so text is the same.
local function hold_latin(env, ctx, word, ch, fallback)
  local token = word .. ch -- word or name form (json- -> JSON-schema)
  reset()
  env.latin = fallback
  set_input(ctx, token)
  return kAccepted
end

-- Keys that close the association list and then type themselves. Shift+digit
-- symbols (exclam at numbersign ... parenleft) pick from the list instead, and
-- equal stays a page key.
local ASSOC_PUNCT = {
  period = true, comma = true, minus = true, semicolon = true, colon = true,
  question = true, slash = true, apostrophe = true, quotedbl = true,
  bracketleft = true, bracketright = true, braceleft = true, braceright = true,
  backslash = true, bar = true, grave = true, asciitilde = true,
  underscore = true, plus = true, less = true, greater = true,
  parenright = true,
}

-- English contraction stems: only these runs hold an apostrophe (don't it's we're).
local APOS_STEM = {}
for w in ("don can won isn aren wasn weren doesn didn hasn haven hadn couldn wouldn shouldn mustn needn it let that what there here who he she we you they"):gmatch("%a+") do
  APOS_STEM[w] = true
end

-- After word + ".", letters stay Latin only while they spell a domain / file suffix
-- (openai.com, llama.cpp, node.js); otherwise "." was a full stop (hello.vd1 -> hello。好).
-- shortcut: fixed suffix list, add entries when a real token misses.
local DOT_SUFFIX, DOT_FULL = {}, {}
for w in ("com net org io ai app dev co hk tw cn jp uk us me tv gg xyz info edu gov js ts py rb go rs md txt json yaml yml toml cpp hpp lua sh html css xml csv pdf png jpg jpeg gif svg mp3 mp4 mov zip dmg pkg exe dll deb apk"):gmatch("%a+") do
  DOT_FULL[w] = true
  for i = 1, #w do
    DOT_SUFFIX[w:sub(1, i)] = true
  end
end

local KEYCODE = { Shift_L = 0xffe1, Shift_R = 0xffe2, Caps_Lock = 0xffe5 }

-- Space may commit this word: a common (lowercase) word, or a listed extra
-- such as Gmail. Proper nouns only through Left Shift; they collide with
-- Chinese more and are rarely typed lowercase on purpose.
local function space_text(env, raw)
  local text, lower = word_text(env.en_mem, raw)
  -- An ordinary lowercase word stays lowercase (word, apple, edge); the
  -- names list only supplies the form for codes without one (openai -> OpenAI).
  if lower then
    return text
  end
  if env.names[raw] then
    return env.names[raw]
  end
  local name = word_text(env.names_mem, raw) -- kinfx_names (adsense -> AdSense)
  if name then
    return name
  end
  if text and env.hold_set[raw] then
    return text
  end
  return nil
end

-- Left Shift form: same rule (lowercase word first, then the names list).
local function shift_text(env, raw)
  local text, lower = word_text(env.en_mem, raw)
  if lower then
    return text
  end
  text = env.names[raw] or (word_text(env.names_mem, raw)) or raw
  -- The preview and actual Shift/blur commit must use the same case rule.
  -- A dictionary acronym is not permission to shout an unlisted typed run.
  if text ~= raw and text == raw:upper() and not env.names[raw] then
    return raw
  end
  return text
end

-- An unknown word (raw ran past every kinfx_en prefix): Space commits the raw
-- letters once the word is long enough that Chinese typing rarely ends there.
local unknown_len_ok
local function unknown_space_ok(env, ctx)
  return env.space_mode ~= "off" and #S.raw > S.known_en and env.unknown_space_min > 0
    and env.hold_min > 0 and S.known_en >= env.hold_min
    and #S.raw <= S.known_en + env.hold_extra
    and unknown_len_ok(env, #S.raw) and not chinese_held(ctx)
end

-- Unknown words after a 4-letter English start: lengths 5 and 7+ only.
-- Length 6 is three full Sucheng pairs, where Space pages the Chinese menu
-- (all such 6-letter runs together: 2.6 changes per 10,000 characters).
function unknown_len_ok(env, n)
  return n >= env.unknown_space_min and (n ~= 6 or env.unknown_space_min > 6)
end

-- What an end key (Space, comma, period, or any symbol in ASCII-punctuation
-- mode) commits for the current composition, before the key itself.
local function end_text(env, ctx)
  if S.tracking and S.raw ~= "" then
    -- Word / name form first (gmail -> Gmail); raw letters only after that.
    if space_allowed(env, S.raw) and #S.raw > 2 and not chinese_held(ctx) then
      local text = space_text(env, S.raw)
      if text then
        return text
      end
    end
    if unknown_space_ok(env, ctx) then
      return S.raw
    end
    return S.pending .. ctx:get_commit_text()
  end
  if ctx:is_composing() then
    return ctx:get_commit_text()
  end
  return ""
end

local function read_env(env)
  local config = env.engine.schema.config
  local on = pm.config_bool(config, "english/enable", true)
  env.smart = on and config_str(config, "english/mode", "smart") == "smart"
  env.space_mode = config_str(config, "english/space", "safe")
  -- association/space: type (Space closes the list and types a space, default)
  -- | page (Windows: Space pages the list and is swallowed).
  env.assoc_space = config_str(config, "association/space", "type")
  -- association/paren_pick: false (default) = Shift+9 after a pick types （ and
  -- closes the list (HKEPC: 遊戲越獄（ came out 越獄訟) | true = Shift+9 picks slot 9.
  env.paren_pick = pm.config_bool(config, "association/paren_pick", false)
  -- win_quick/period_pages: false (default) = "." with a menu commits the
  -- highlighted candidate, then the punctuator types 。 (vd. -> 好。, Windows Quick)
  -- | true = "." pages (Weasel's paging_with_comma_period binding).
  env.period_pages = pm.config_bool(config, "win_quick/period_pages", false)
  env.commit_key = config_str(config, "english/commit_key", "Shift_L")
  env.commit_code = KEYCODE[env.commit_key] or 0xffe1
  env.en_mem = pm.new_memory(env, "kinfx_en")
  -- v0.5.4: brand / website names (kinfx_names, ~5k, native table).
  env.names_mem = pm.new_memory(env, "kinfx_names")
  env.unsafe = load_unsafe()
  env.names, env.name_prefix = load_names()
  -- english/empty_shift: noop (default; a Left Shift tap with nothing typed
  -- does nothing) | ascii (librime inline_ascii: switch to English).
  env.empty_shift = config_str(config, "english/empty_shift", "noop")
  env.blur_short = config_str(config, "english/blur_short", "letters")
  -- english/hold_min: once an English prefix of this many letters breaks,
  -- keep holding up to hold_extra more letters as an unknown word (company /
  -- product names). 0 = off. Chinese output is still v0.4.1 for every key
  -- except Space / Left Shift on such a run.
  env.hold_min = config_int(config, "english/hold_min", 4)
  env.hold_extra = config_int(config, "english/hold_extra", 8)
  -- 7 (v0.5.2): at 5, giorj Space (去合 + j Space) typed giorj (article replay).
  env.unknown_space_min = config_int(config, "english/unknown_space_min", 7)
  -- english/rescue_min (v0.5.4): a run whose first rescue_min letters are an
  -- English / name prefix stays held for up to rescue_extra more letters even
  -- after it stops being one, so a Left Shift tap still types the letters
  -- (adsense, zdrav). Space, digits and every other key give the v0.4.1
  -- Chinese, so only the timing changes: the top-outs wait for that key.
  -- 0 = off (v0.5.3).
  env.rescue_min = config_int(config, "english/rescue_min", 2)
  env.rescue_extra = config_int(config, "english/rescue_extra", 8)
  -- english/clipboard: clear (default) = Ctrl+C / Ctrl+V / Ctrl+X close the
  -- composition (held top-outs are sent, letters dropped like Esc) and reach
  -- the app | keep = v0.5.2 (Ctrl+V paged the menu, Ctrl+C did nothing).
  env.clipboard = config_str(config, "english/clipboard", "clear")
  env.hyphen = config_str(config, "english/hyphen", "word")
  -- english/preedit: letters (default) = the preedit shows the typed letters
  -- (of, hello) | radicals = Sucheng radicals as before (人火).
  env.letters = config_str(config, "english/preedit", "letters") ~= "radicals"
  local _, hold = pm.load_capture()
  env.hold = hold
  env.hold_set = {}
  for _, w in ipairs(hold) do
    env.hold_set[w] = true
  end
end

-- Navigation belongs to the owning menu, not to the Shift+Space key path.
-- Engine::OnOptionUpdate refreshes every unconfirmed segment, including the
-- empty association placeholder. Bracket that synchronous refresh so native
-- punctuation still retranslates, then restore only the SAME candidate.
local function width_tags(seg)
  local tags = {}
  for tag, present in pairs(seg.tags) do
    -- Native navigation adds this transient tag; refresh intentionally drops
    -- it. It is not part of the segment's translation/source identity.
    if present and tag ~= "paging" then tags[#tags + 1] = tag end
  end
  table.sort(tags)
  return table.concat(tags, "\31")
end

local function width_candidate(cand)
  if not cand then return nil end
  local genuine = cand:get_genuine()
  return { text = cand.text, kind = cand.type, first = cand.start, last = cand._end,
    source = genuine.type, class = genuine:get_dynamic_type() }
end

local function width_equal(a, b)
  if not a or not b then return false end
  for key, value in pairs(a) do
    if value ~= b[key] then return false end
  end
  return true
end

local function width_owner(env, ctx)
  local comp = ctx.composition
  if not comp or comp:empty() then return nil end
  local segments = comp:toSegmentation():get_segments()
  local seg = segments[#segments]
  if not seg or not seg.menu then return nil end
  local prefix = {}
  for i, part in ipairs(segments) do
    prefix[#prefix + 1] = table.concat({part.start, part._end, width_tags(part)}, ":")
    if i < #segments then
      local cand = part:get_selected_candidate()
      prefix[#prefix + 1] = part.status .. ":" .. (cand and cand.text or "")
    end
  end
  return { session = env.state_id, state = ctx:get_property("kinfx_english_state"),
    schema = env.engine.schema.schema_id, input = ctx.input, caret = ctx.caret_pos,
    code = ctx:get_property("kinfx_assoc_code"), generation = env.width_generation,
    segments = table.concat(prefix, "\30") }, seg
end

local function width_init(env, ctx)
  env.width_generation = 0
  local function invalidate()
    env.width_generation = env.width_generation + 1
    env.width_saved = nil
  end
  env.width_commit_conn = ctx.commit_notifier:connect(invalidate, 0)
  env.width_select_conn = ctx.select_notifier:connect(invalidate, 0)
  env.width_property_conn = ctx.property_update_notifier:connect(function(_, name)
    if name == "kinfx_assoc_code" then invalidate() end
  end, 0)
  env.width_pre_conn = ctx.option_update_notifier:connect(function(c, name)
    if name ~= "full_shape" then return end
    env.width_saved = nil
    if env.width_restoring or env.width_internal then return end
    local ok, saved = pcall(function()
      local owner, seg = width_owner(env, c)
      if not owner then return nil end
      local index = seg.selected_index -- absolute index in THIS menu, not genuines
      local candidate = width_candidate(seg:get_candidate_at(index))
      if not candidate then return nil end
      return { owner = owner, index = index, candidate = candidate }
    end)
    if ok then env.width_saved = saved end
  end, 0) -- before the engine's ungrouped refresh slot
  env.width_post_conn = ctx.option_update_notifier:connect(function(c, name)
    if name ~= "full_shape" then return end
    local saved = env.width_saved
    env.width_saved = nil -- one shot, consumed even on mismatch/error/recursion
    if not saved or env.width_restoring or env.width_internal then return end
    env.width_restoring = true
    pcall(function()
      local owner, seg = width_owner(env, c)
      if not width_equal(saved.owner, owner) then return end
      -- Prepare the rebuilt lazy menu at the absolute index before comparing.
      local candidate = width_candidate(seg:get_candidate_at(saved.index))
      if not width_equal(saved.candidate, candidate) then return end
      c:highlight(saved.index) -- native update; no page-key replay or status lie
    end)
    env.width_restoring = false
  end)
end

local blur_text -- below blur()
local inline_plan, finish_plan -- below blur(); native raw ASCII ownership only
local publish_display -- below blur(); presentation only, never a commit plan

local function init(env)
  pm.init(env)
  read_env(env)
  env.shift_down = false
  next_state = next_state + 1
  env.state_id = tostring(next_state)
  states[env.state_id] = {
    run = { raw = "", pending = "", tracking = false, guard = false, known = 0, known_en = 0 },
    rescue = { alive = false, raw = "", defer = "", cap = 0 },
  }
  env.engine.context:set_property("kinfx_english_state", env.state_id)
  activate(env)
  reset()
  local ctx = env.engine.context
  ctx:set_property("kinfx_punct_tail", "")
  ctx:set_property("kinfx_digit_tail", "")
  width_init(env, ctx)
  -- Native CommitComposition bypasses processors. Consume only a proven raw
  -- inline snapshot before the engine's ungrouped formatter slot; after clear
  -- that slot reads empty text, so the immutable plan reaches the sink once.
  env.inline_commit_conn = ctx.commit_notifier:connect(function(c)
    activate(env)
    local plan = inline_plan(env, c)
    if plan then finish_plan(env, plan) end
  end, 0)
  -- Option refresh is synchronous. Preserve an idle app-tail only inside that
  -- transaction, not until the next key (an external clear must still clear it).
  env.tail_option_pre_conn = ctx.option_update_notifier:connect(function(c, name)
    -- Preserve only this exact native raw span when ascii_mode turns off;
    -- the engine synchronously retranslates it as Chinese afterwards. Any
    -- edit/clear invalidates this one-shot origin snapshot in update_notifier.
    if name == "ascii_mode" then
      local plan = inline_plan(env, c)
      env.inline_origin = plan and plan.input or nil
    end
    env.punct_mode_command = (name == "full_shape" or name == "ascii_mode")
      and not c:is_composing() and (c.input or "") == ""
  end, 0)
  env.tail_option_post_conn = ctx.option_update_notifier:connect(function()
    env.punct_mode_command = false
  end)
  -- Native commits (uppercase/URL/email, Chinese picks, mouse selection) do
  -- not call commit_word. Observe committed text, never just input codes.
  env.tail_commit_conn = ctx.commit_notifier:connect(function(c)
    activate(env)
    local text = c:get_commit_text()
    remember_tail(c, text)
    env.punct_committing = true
  end, 0)
  env.tail_update_conn = ctx.update_notifier:connect(function(c)
    activate(env)
    if (c.input or "") == "" then
      if not env.punct_committing and not S.guard and not env.punct_mode_command then
        c:set_property("kinfx_punct_tail", "")
        c:set_property("kinfx_digit_tail", "")
      end
      env.punct_committing = false
    end
  end)
  -- 0.1.4: kinfx_blur (what F35 would commit) is kept up to date for shells
  -- that hand it over before focus leaves (IBus). The update_notifier fires
  -- after the segmentors finalise the composition, so this sees both native
  -- Latin (uppercase/url/email) and the advanced S.raw of a smart run.
  env.blur_conn = env.engine.context.update_notifier:connect(function(c)
    activate(env)
    if env.inline_origin ~= c.input then env.inline_origin = nil end
    c:set_property("kinfx_blur", blur_text(env, c))
    publish_display(env, c)
  end)
  if not env.smart then
    return
  end
  -- A candidate picked with the mouse commits without a key event: send the
  -- pending top-outs first (grouped slots run before the engine's own).
  env.commit_conn = ctx.commit_notifier:connect(function(_)
    activate(env)
    if not S.guard and (S.pending ~= "" or R.defer ~= "") then
      local text = R.defer .. S.pending
      reset()
      rescue_drop()
      commit_text(env, text)
    end
  end, 0)
  -- Composition cleared from outside (focus change, schema switch): drop the run.
  env.update_conn = ctx.update_notifier:connect(function(c)
    activate(env)
    if not S.guard and (c.input or "") == "" then
      env.latin, env.latin_apos, env.dot = nil, false, nil
      reset()
      if R.alive then
        rescue_end(env)
      end
    end
  end)
end

local function fini(env)
  env.width_saved = nil
  for _, name in ipairs({"width_pre_conn", "width_post_conn", "width_commit_conn",
      "width_select_conn", "width_property_conn", "tail_option_pre_conn", "tail_option_post_conn",
      "inline_commit_conn"}) do
    if env[name] then env[name]:disconnect() end
  end
  states[env.state_id] = nil
  if env.tail_commit_conn then env.tail_commit_conn:disconnect() end
  if env.tail_update_conn then env.tail_update_conn:disconnect() end
  if env.blur_conn then
    env.blur_conn:disconnect()
  end
  if env.commit_conn then
    env.commit_conn:disconnect()
  end
  if env.update_conn then
    env.update_conn:disconnect()
  end
end

local function start_run(ctx, ch)
  S.tracking, S.raw, S.pending, S.known, S.known_en = true, ch, "", 1, 1
  set_input(ctx, ch)
end

-- May the run take letter ch? A kinfx_en prefix, or an unknown word that
-- started as a long enough English prefix (hold_min) and is still short.
local function en_prefix(env, raw)
  return pm.has_prefix(env.en_mem, raw) or env.name_prefix[raw]
end

local function is_prefix(env, raw)
  return en_prefix(env, raw) or pm.has_prefix(env.names_mem, raw)
end

local function can_extend(env, raw)
  if is_prefix(env, raw) then
    return true, true
  end
  if env.hold_min > 0 and S.known >= env.hold_min
     and #raw <= S.known + env.hold_extra then
    return true, false
  end
  return false, false
end

local function extend(env, ctx, ch)
  local raw = S.raw .. ch
  local ok, known = can_extend(env, raw)
  if not ok or not (ctx.input or ""):match("^[a-z]*$") then
    return false
  end
  S.raw = raw -- before set_input, so the hint filter sees it
  if known and S.known == #raw - 1 then
    S.known = #raw
  end
  if S.known_en == #raw - 1 and en_prefix(env, raw) then
    S.known_en = #raw
  end
  return v041_letter(env, ctx, ch)
end

-- Backspace inside a held run: drop the last letter and rebuild the run, so a
-- typo in an English word does not commit the held Chinese top-outs.
local function backspace(env, ctx)
  local raw = S.raw:sub(1, -2)
  reset()
  S.guard = true
  ctx:clear()
  S.guard = false
  if raw == "" then
    return
  end
  start_run(ctx, raw:sub(1, 1))
  for i = 2, #raw do
    if not extend(env, ctx, raw:sub(i, i)) then
      break
    end
  end
end

-- Typed after held letters, these start a URL: the letters stay as typed and
-- librime's recognizer (url pattern) takes the rest (https://x.com).
local URL_START = {
  ["http:"] = true, ["https:"] = true, ["ftp:"] = true, ["ftp."] = true,
  ["www."] = true, ["mailto:"] = true, ["file:"] = true,
}
local CLIP = { c = true, v = true, x = true }

local function is_symbol(kc)
  return kc >= 0x21 and kc <= 0x7e
    and not ((kc >= 0x30 and kc <= 0x39) or (kc >= 0x41 and kc <= 0x5a)
             or (kc >= 0x61 and kc <= 0x7a))
end

local function word_known(env, raw)
  return word_text(env.en_mem, raw) ~= nil or env.names[raw] ~= nil
    or word_text(env.names_mem, raw) ~= nil
end

local process -- the v0.5.3 key handler, below

-- Paste while composing: Ctrl+V, or Command+V on macOS (Super), or Meta+V
-- (some X clients). The user may have clicked elsewhere first, so nothing
-- composed or held is committed: it would land at the old caret. Drop it all
-- and return kRejected so the app pastes. kNoop let key_binder
-- (emacs_editing, when: composing) turn Control+v into Page_Down.
local function paste_key(env, key)
  local kc = key.keycode
  if env.clipboard == "keep" or key:release() or key:alt()
     or not (kc == 0x76 or kc == 0x56) then
    return false
  end
  if not (key:ctrl() or key:super() or math.floor(key.modifier / META_MASK) % 2 == 1) then
    return false
  end
  return env.engine.context:is_composing()
end

-- Clipboard text for a paste typed while the association list shows.
-- shortcut: one shell call per paste (Windows ~0.3 s for powershell); upgrade
-- to a native clipboard API if users find it slow.
local function read_clipboard()
  local cmd = "pbpaste 2>/dev/null || wl-paste -n 2>/dev/null || xclip -o -selection clipboard 2>/dev/null"
  if package.config:sub(1, 1) == "\\" then
    cmd = 'powershell -NoProfile -NonInteractive -Command "[Console]::OutputEncoding=[Text.Encoding]::UTF8;[Console]::Out.Write((Get-Clipboard -Raw))"'
  end
  local ok, text = pcall(function()
    local fh = io.popen(cmd, "r")
    if not fh then
      return nil
    end
    local t = fh:read("*a")
    fh:close()
    return t
  end)
  if ok and text and text ~= "" then
    return text
  end
  return nil
end

local function dispatch(key, env)
  local kc = key.keycode
  if paste_key(env, key) then
    local ctx = env.engine.context
    -- After a pick nothing is composed but the association list shows: paste
    -- here so the list survives (passing the key on closes it). Clipboard
    -- unreadable: fall through and hand the key to the app as before.
    if (ctx:get_property("kinfx_assoc_code") or "") ~= "" and (ctx.input or "") == "" then
      local text = read_clipboard()
      if text then
        commit_text(env, text)
        return kAccepted
      end
    end
    -- 0.1.2: paste mid-composition keeps the Windows model: the held top-outs
    -- reach the app (already committed in Windows), the letters drop, then the
    -- app pastes (kRejected). Same text as "Esc then paste".
    rescue_end(env)
    flush(env)
    S.guard = true
    env.engine.context:clear()
    S.guard = false
    return kRejected
  end
  if not R.alive then
    local r = process(key, env)
    -- the rescue started on this key; kNoop lets the speller commit next,
    -- so the parked text has to reach the app before it
    if R.alive and r ~= kAccepted then
      rescue_end(env)
    end
    return r
  end
  local repr = key:repr()
  local plain = not (key:ctrl() or key:alt() or key:super())
  if key:release() or kc == env.commit_code then
    -- A width-toggle modifier release is not a rescue terminator either.
    -- process clears/consumes the used Shift; retain the parked full run.
    if kc == env.commit_code and key:release() and env.shift_used then
      return process(key, env)
    end
    -- Left Shift tap: the rescue wins unless the normal path holds a word.
    if kc == env.commit_code and key:release() and env.shift_down and not env.shift_used
       and not (S.tracking and S.raw ~= "" and word_known(env, S.raw)) then
      env.shift_down, env.shift_used = false, false
      local text = R.raw
      rescue_drop()
      commit_word(env, env.engine.context, text)
      return kAccepted
    end
    if kc == env.commit_code and key:release() then
      local text = R.defer
      rescue_drop()
      if text ~= "" then
        commit_text(env, text)
      end
    end
    return process(key, env)
  end
  if plain and repr:match("^[a-z]$") then
    R.raw = R.raw .. repr
    local r = process(key, env)
    -- kNoop lets the speller commit after us: the parked text must go first.
    if r ~= kAccepted or #R.raw > R.cap then
      rescue_end(env)
    end
    return r
  end
  -- shortcut: Backspace ends the rescue like any other key (v0.5.3 text);
  -- replaying the run needs the speller's top-out, upgrade if users ask.
  -- A bare modifier press (Shift_R before Shift+;) keeps the rescue.
  if kc >= 0xffe1 and kc <= 0xffee and kc ~= 0xffe5 and kc ~= 0xffe6 then
    return process(key, env)
  end
  rescue_end(env)
  return process(key, env)
end

-- "." with a candidate menu: commit the highlighted candidate like a Windows
-- top-out; the punctuator then types 。 (key_binder's period -> Page_Down runs
-- later and finds no menu). Only after every other path returned kNoop, so
-- URLs (www.), English words (hello。) and ASCII punctuation keep their handling.
local function period_topout(env, key)
  if env.period_pages or key:release() or key.keycode ~= 0x2e
     or key:ctrl() or key:alt() or key:super() then
    return
  end
  local ctx = env.engine.context
  if ctx:get_option("ascii_mode") or not ctx:has_menu() or assoc_active(ctx) then
    return
  end
  local seg = ctx.composition:back()
  if seg and (seg:has_tag("url") or seg:has_tag("email") or seg:has_tag("uppercase")) then
    return
  end
  ctx:commit()
end

-- A Latin token built by hold_latin (llama.cpp, bait-and): url-tagged, but
-- not one of the URL starts (www. https: ...), which keep their own rules.
local function latin_token(ctx)
  local input = ctx.input or ""
  if not input:match("^[a-z][A-Za-z0-9]*[.-]") or input:match("^www%.") or input:match("^ftp[.:]")
     or input:match("^https?:") or input:match("^mailto:") or input:match("^file:") then
    return false
  end
  local seg = ctx.composition and not ctx.composition:empty() and ctx.composition:back()
  return seg and seg:has_tag("url")
end

-- 0.1.1: letters after word + "." (env.dot). A domain / file suffix keeps the token
-- Latin; anything else types "word。" and replays the letters the Windows way.
-- Runs first in func so , / ] after openai.co see the suffix decision.
local function dot_key(env, key)
  local d = env.dot
  if not d or key:release() then
    return nil
  end
  local kc = key.keycode
  if kc >= 0xffe1 and kc <= 0xffee then
    return nil -- a bare modifier (Shift before ?)
  end
  if key:repr() == "BackSpace" then
    if d.raw == "" then
      env.dot, env.latin = nil, d.fallback -- back to "word." waiting, the v0.5.10 path
    else
      d.tail, d.raw = d.tail:sub(1, -2), d.raw:sub(1, -2) -- a typo inside the suffix
    end
    return nil
  end
  local letter = not (key:ctrl() or key:alt() or key:super())
    and ((kc >= 0x61 and kc <= 0x7a) or (kc >= 0x41 and kc <= 0x5a))
  local tail = letter and (d.tail .. string.char(kc):lower()) or d.tail
  if letter and DOT_SUFFIX[tail] then
    d.tail, d.raw = tail, d.raw .. string.char(kc)
    return nil
  end
  env.dot = nil
  if not letter and DOT_FULL[tail] then
    return nil -- openai.com + Space / , / Enter: the url path commits it
  end
  local raw = letter and (d.raw .. string.char(kc)) or d.raw
  commit_word(env, env.engine.context, d.fallback)
  for i = 1, #raw do
    env.engine:process_key(KeyEvent(raw:sub(i, i)))
  end
  return letter and kAccepted or nil
end

-- 0.1.4: focus left the text (click elsewhere, window switch). The shell sends
-- F35 (no keyboard has it) and writes the commit before it ends the composition.
-- An English run gives what a Left Shift tap gives (hel -> hel), anything else
-- what Return gives (vd -> 好, ofc -> 人類, as Microsoft Quick commits on blur).
local BLUR = 0xffe0
local function blur_english(env, ctx)
  local input = ctx.input or ""
  -- 1–2 個字母嘅短碼：預設當英文留住（同 Shift+字母一致），可設 commit 回復 Windows 行為
  local short = env.blur_short ~= "commit" and #input <= 2 and input:match("^[a-z]+$") ~= nil
      and not chinese_held(ctx)
  return env.smart and (env.latin or env.dot or latin_token(ctx) or R.alive or short
    or (S.tracking and #S.raw >= 3 and not chinese_held(ctx)))
end

-- A pure snapshot is shared by the property and the terminal blur action.
-- Never dispatch synthetic keys here: Return can select only a prefix, and a
-- subsequent clear used to silently discard everything after the caret.
local function native_blur_text(ctx, input)
  local comp = ctx.composition
  local parts, pos = {}, 0
  if comp and not comp:empty() then
    local segments = comp:toSegmentation():get_segments()
    for _, seg in ipairs(segments) do
      local first, last = seg.start, seg._end
      local cand = seg:get_selected_candidate()
      if cand then first, last = cand.start, cand._end end
      -- Segment offsets index the raw UTF-8 input, never the rendered preedit.
      -- Refuse to consume corrupt ranges rather than calling a native substr
      -- getter with an invalid composition. Leave the input live on failure.
      if first < pos or last < first or last > #input then return nil end
      parts[#parts + 1] = input:sub(pos + 1, first)
      if not seg:has_tag("phony") then
        parts[#parts + 1] = cand and cand.text or input:sub(first + 1, last)
      end
      pos = last
    end
  end
  parts[#parts + 1] = input:sub(pos + 1)
  return table.concat(parts)
end

local function shape_blur_text(text, wide)
  if not wide then return text end
  -- Match librime ShapeFormatter (1.17): ASCII space and 0x21..0x7e only.
  return (text:gsub("[ -~]", function(ch)
    return utf8.char(ch == " " and 0x3000 or ch:byte() + 0xfee0)
  end))
end

inline_plan = function(env, ctx)
  local input = ctx.input or ""
  if input == "" or #input > 2048 or input:find("[^ -~]")
      or S.tracking or S.pending ~= "" or R.alive or R.defer ~= "" then return nil end
  local comp = ctx.composition
  if not comp or comp:empty() then return nil end
  local segments = comp:toSegmentation():get_segments()
  local pos, raw = 0, false
  local origin = env.inline_origin == input
  for _, seg in ipairs(segments) do
    -- Only native ascii_segmentor raw text, never a guessed Chinese code,
    -- selected prefix, recognizer token or an association placeholder.
    if seg.start ~= pos or seg._end < pos or seg._end > #input
        or seg.status == "kSelected" or seg.status == "kConfirmed" then return nil end
    if not origin and (seg:get_selected_candidate() or not seg:has_tag("raw")) then return nil end
    raw = raw or seg:has_tag("raw")
    pos = seg._end
  end
  -- Compose segments only through the native caret. In ascii_mode its raw
  -- segment owns the unchanged ASCII suffix too; never move the caret to End.
  if (not raw and not origin) or (pos ~= #input
      and not (ctx:get_option("ascii_mode") and pos == ctx.caret_pos)) then return nil end
  -- A raw native span proves ASCII origin; punctuation follows the last
  -- Latin letter within that span, not a document-tail observer. Digits and
  -- spaces retain both their native width and the preceding script context.
  local latin = false
  local text = input:gsub("[ -~]", function(ch)
    if ch:match("[A-Za-z]") then latin = true end
    local punct = ch:match("[^A-Za-z0-9 ]") ~= nil
    if not full_shape(env) or (latin and punct) then return ch end
    return utf8.char(ch == " " and 0x3000 or ch:byte() + 0xfee0)
  end)
  return { text = text, valid = true, input = input }
end

local function blur_plan(env, ctx)
  local inline = inline_plan(env, ctx)
  if inline then return inline end
  local input = ctx.input or ""
  if input == "" then return { text = "", valid = true } end
  local comp = ctx.composition
  local seg = comp and not comp:empty() and comp:back()
  -- Native recognizer tokens use the ASCII-preserving Return path too; they
  -- are not covered by latin_token(), which intentionally excludes URL starts.
  local native_latin = seg and (seg:has_tag("uppercase") or seg:has_tag("url")
    or seg:has_tag("email"))
  -- A highlighted candidate is still only a guess, but an explicitly selected
  -- prefix belongs to the user. Never replace it with the original short codes
  -- or a stale tracked English run when focus leaves. librime-lua exposes
  -- Segment.status as enum names, not the underlying C++ numeric values.
  local selected = false
  if comp and not comp:empty() then
    for _, part in ipairs(comp:toSegmentation():get_segments()) do
      if (part.status == "kSelected" or part.status == "kConfirmed")
          and part._end > part.start then
        selected = true
        break
      end
    end
  end
  local english = native_latin or (not selected and blur_english(env, ctx))
  local raw
  if not english then
    local native = native_blur_text(ctx, input)
    if not native then return { text = "", valid = false } end
    raw = R.defer .. S.pending .. native
  else
    local run = S.tracking and S.raw ~= ""
    if R.alive and not (run and word_known(env, S.raw)) then
      raw = R.raw
    elseif #input <= 2 and input:match("^[a-z]+$") and env.blur_short ~= "commit"
        and not (S.tracking and #S.raw > 2) then
      raw = R.defer .. input
    elseif env.latin then
      raw = input
    elseif run then
      raw = R.defer .. shift_text(env, S.raw)
    elseif input:match("^[a-z]+$") and not ctx:get_option("ascii_mode") then
      raw = R.defer .. input
    else
      local native = native_blur_text(ctx, input)
      if not native then return { text = "", valid = false } end
      raw = R.defer .. S.pending .. native
    end
    -- Held-dot sentinel has the same meaning as in commit_word.
    raw = raw:gsub("。", ".")
  end
  return { text = shape_blur_text(raw, full_shape(env) and not english), valid = true }
end

finish_plan = function(env, plan)
  local ctx = env.engine.context
  if not plan.valid then return kAccepted end -- do not clear unrepresented input
  env.shift_down, env.shift_used = false, false
  env.rshift_down, env.rshift_used, env.assoc_tap = false, false, false
  env.latin, env.latin_apos, env.dot = nil, false, nil
  reset()
  rescue_drop()
  ctx:set_property("kinfx_assoc_code", "")
  S.guard = true
  ctx:clear()
  S.guard = false
  -- The plan already includes width conversion. Bypass the formatter once,
  -- only after clear, so toggling the option cannot retranslate live input.
  if plan.text ~= "" then
    local wide = full_shape(env)
    if wide then ctx:set_option("full_shape", false) end
    env.engine:commit_text(plan.text)
    if wide then ctx:set_option("full_shape", true) end
  end
  ctx:set_property("kinfx_blur", "")
  ctx:set_property("kinfx_punct_tail", "")
  ctx:set_property("kinfx_digit_tail", "")
  return kAccepted
end

local function blur(env)
  -- Immutable value before clear or any option/update notifier runs.
  return finish_plan(env, blur_plan(env, env.engine.context))
end

function blur_text(env, ctx)
  return blur_plan(env, ctx).text
end

-- Pure, bounded presentation snapshot. The virtual held prefix is read-only:
-- only the native tail has editable raw offsets. A tail byte caret maps by
-- adding the displayed prefix length; no inverse mapping into parked text is
-- claimed. Navigation/backspace still run the existing processor (which ends
-- rescue); never move the native caret or manufacture keys to match the view.
local function display_plan(s)
  local invalid = { valid = false }
  if not s.smart or s.selected or s.native_latin or not s.input:match("^[a-z]+$")
      or #s.input > 2048 or s.caret < 0 or s.caret > #s.input then return invalid end
  local prefix, tail = s.defer .. s.pending, s.input
  if s.letters then
    local raw = s.rescue and not s.known and s.rescue_raw
      or (s.tracking and s.raw ~= "" and s.raw or nil)
    if raw then
      if raw:sub(-#s.input) ~= s.input then return invalid end
      prefix = (s.rescue and not s.known) and "" or s.defer
      tail = raw
    end
  end
  -- No ownership gap: ordinary native compositions remain untouched.
  if prefix == "" and tail == s.input then return invalid end
  local text, cursor
  if s.letters then
    text = prefix .. tail
    cursor = #text - #s.input + s.caret
  else
    if prefix == "" or s.native_cursor < 0 or s.native_cursor > #s.native_text then return invalid end
    text = prefix .. s.native_text
    cursor = #prefix + s.native_cursor
  end
  if #text > 2048 or text:find("[%z\1-\31\127]") or not utf8.len(text)
      or cursor < 0 or cursor > #text
      or (cursor < #text and text:byte(cursor + 1) >= 128
          and text:byte(cursor + 1) < 192) then return invalid end
  return { valid = true, text = text, cursor = cursor }
end

publish_display = function(env, ctx)
  local input = ctx.input or ""
  local selected, native_latin, ranges_valid = false, false, true
  local comp = ctx.composition
  if comp and not comp:empty() then
    for _, seg in ipairs(comp:toSegmentation():get_segments()) do
      selected = selected or seg.status == "kSelected" or seg.status == "kConfirmed"
      native_latin = native_latin or seg:has_tag("uppercase") or seg:has_tag("url") or seg:has_tag("email")
      local cand = seg:get_selected_candidate()
      if seg.start < 0 or seg._end < seg.start or seg._end > #input
          or (cand and (cand.start < 0 or cand._end < cand.start or cand._end > #input)) then
        ranges_valid = false
      end
    end
  end
  -- Avoid native preedit access for invalid ranges (the bridge's native API
  -- has its own validity limitations, outside this presentation contract).
  local eligible = ranges_valid and env.smart and not selected and not native_latin
    and input:match("^[a-z]+$") and #input <= 2048
  local native = eligible and (env.letters and { text = "", caret_pos = 0 }
    or ((R.defer .. S.pending) ~= "" and ctx:get_preedit())) or nil
  local plan = native and display_plan {
    smart = env.smart, letters = env.letters, input = input, caret = ctx.caret_pos,
    selected = selected, native_latin = native_latin,
    native_text = native.text, native_cursor = native.caret_pos,
    tracking = S.tracking, raw = S.raw, pending = S.pending,
    rescue = R.alive, rescue_raw = R.raw, defer = R.defer,
    known = S.tracking and S.raw ~= "" and word_known(env, S.raw),
  } or { valid = false }
  -- One atomic versioned record, capped before publication. The C bridge
  -- checks owner + exact native input/caret again, never kx_property's 4KB API.
  ctx:set_property("kinfx_display", plan.valid and table.concat({
    "1", env.state_id, input, tostring(ctx.caret_pos), tostring(plan.cursor), plan.text,
  }, "\n") or "")
end

local function func(key, env)
  -- Width is a mode command, not an English terminator. It must bypass dot,
  -- deferred punctuation and rescue dispatch too, before any of them commits.
  -- Mark the physical Shift as used so its later release is not a tap, and
  -- cancel the association tap without closing/rebuilding the candidate menu.
  if not key:release() and key.keycode == 0x20 and key:shift() then
    env.assoc_tap = false
    if env.shift_down then env.shift_used = true end
    if env.rshift_down then env.rshift_used = true end
    -- The key_binder toggles full_shape after this processor returns. Persist
    -- the resulting width so the next context restores it: otherwise the
    -- toggle would reset to the schema default on every window/app switch.
    persist_full_shape(not env.engine.context:get_option("full_shape"))
    return kNoop -- the original key_binder still owns full_shape
  end
  if key.keycode == BLUR and not key:release() then
    return blur(env)
  end
  local ctx = env.engine.context
  if not key:release() and key.keycode == 0xff0d
      and not (key:ctrl() or key:alt() or key:super()) then
    local plan = inline_plan(env, ctx)
    if plan then return finish_plan(env, plan) end
  end
  local r0 = dot_key(env, key)
  if r0 then
    return r0
  end
  local kc0 = key.keycode
  local ctx0 = env.engine.context
  local seg0 = ctx0.composition and not ctx0.composition:empty() and ctx0.composition:back()
  local native_latin = seg0 and (seg0:has_tag("uppercase") or seg0:has_tag("url") or seg0:has_tag("email"))
  -- These keys end native Latin just as they end a smart English word. Keep
  -- uppercase token continuations (-_+.'), and URL/email syntax, composing.
  -- Clear
  -- before bypassing ShapeFormatter: toggling its option on an active native
  -- composition would retranslate iPhone as Sucheng codes.
  if native_latin and not key:release() and not (key:ctrl() or key:alt() or key:super())
     and (kc0 == 0x2c or kc0 == 0x3b or kc0 == 0x29 or kc0 == 0x5d or kc0 == 0x7d
       or (is_symbol(kc0) and seg0:has_tag("uppercase")
           and not ("-_+.'"):find(string.char(kc0), 1, true))
       or kc0 == 0xff0d) then
    commit_word(env, ctx0, ctx0:get_commit_text() .. (kc0 < 0x80 and string.char(kc0) or ""))
    return kAccepted
  end
  if not env.latin and not key:release() and not (key:ctrl() or key:alt() or key:super())
     and (kc0 == 0x2c or kc0 == 0x2e or kc0 == 0x5d or kc0 == 0x7d) and latin_token(ctx0) then
    local input = ctx0.input
    if kc0 == 0x2e then
      -- llama.cpp. : another letter keeps the token going, anything else is 3002
      env.latin = input .. "。"
      set_input(ctx0, input .. ".")
      return kAccepted
    end
    commit_word(env, ctx0, input .. string.char(kc0))
    return kAccepted
  end
  local fallback = env.latin
  if fallback then
    local kc = key.keycode
    local ctx = env.engine.context
    if key:release() then
      -- Left Shift tap on llama. / bait-: type the letters as shown
      if kc == env.commit_code and env.shift_down and not env.shift_used then
        env.latin, env.shift_down = nil, false
        commit_word(env, ctx, ctx.input or "")
        return kAccepted
      end
    elseif not (key:ctrl() or key:alt() or key:super())
           and ((kc >= 0x61 and kc <= 0x7a) or (kc >= 0x41 and kc <= 0x5a)) then
      local apos = env.latin_apos
      env.latin, env.latin_apos = nil, false -- a letter: the token goes on as Latin
      if apos and not ("tsmdrlv"):find(string.char(kc):lower(), 1, true) then
        commit_word(env, ctx, fallback) -- not a contraction: the old text, then this letter
      elseif fallback:sub(-3) == "。" then
        env.dot = { fallback = fallback, tail = "", raw = "" }
        r0 = dot_key(env, key)
        if r0 then
          return r0
        end
      end
    elseif not (kc >= 0xffe1 and kc <= 0xffee and kc ~= 0xffe5 and kc ~= 0xffe6) then
      env.latin, env.latin_apos = nil, false -- not a modifier press: v0.5.9 text, then this key as usual
      commit_word(env, ctx, fallback)
    end
  end
  local r = dispatch(key, env)
  if r == kNoop then
    period_topout(env, key)
  end
  -- Run existing token/selection paths first: an English end key may just
  -- have committed, whereas a live two-code menu still belongs to Chinese.
  local ctx = env.engine.context
  if r == kNoop and not key:release() and not (key:ctrl() or key:alt() or key:super())
     and is_symbol(key.keycode) and not ctx:is_composing()
     and ctx:get_property("kinfx_punct_tail") == "latin" then
    commit_text(env, string.char(key.keycode), true)
    return kAccepted
  end
  -- Space is always half-width, independent of full_shape and the preceding
  -- script (idle, CJK, English, digits, or consecutive spaces): it bypasses the
  -- full-shape formatter, so even under full_shape a space stays U+0020.
  -- ascii_mode space is already half-width (Fix A owns the ASCII path), so
  -- leave its handled flag untouched. A composing Space is paging, not a
  -- literal space: key_binder converts it to Page_Down before this path, so
  -- the not ctx:is_composing() guard leaves candidate paging untouched.
  if r == kNoop and not key:release() and not (key:ctrl() or key:alt() or key:super())
     and key.keycode == 0x20 and not ctx:is_composing() and not ctx:get_option("ascii_mode") then
    commit_text(env, " ", true)
    return kAccepted
  end
  -- A leading slash starts an ASCII command (/init, /yolo): the command leader
  -- stays half-width under full_shape (the same ASCII-path contract as English
  -- after punctuation), and it sets the Latin tail so the command's trailing
  -- punctuation follows that context. A slash after CJK still follows
  -- full_shape (好/ -> 好／): tail == "other" there, so it falls through.
  if r == kNoop and not key:release() and not (key:ctrl() or key:alt() or key:super())
     and key.keycode == 0x2f and not ctx:is_composing()
     and ctx:get_property("kinfx_punct_tail") == "" then
    commit_text(env, "/", true)
    ctx:set_property("kinfx_punct_tail", "latin")
    return kAccepted
  end
  return r
end

function process(key, env)
  local ctx = env.engine.context
  local repr = key:repr()
  -- Compare keycodes, not repr: Weasel sends "Shift+Shift_L" for the press
  -- and "Shift+Release+Shift_L" for the release on a real keyboard.
  local kc = key.keycode


  -- Left Shift tap while the association list shows: close it (Windows) and
  -- swallow the tap so ascii_composer does not switch to English.
  if kc == 0xffe1 then
    if not key:release() then
      env.assoc_tap = true
    elseif env.assoc_tap and assoc_active(ctx) then
      env.assoc_tap = false
      -- this release never reaches the commit-key handler: end the Shift state here
      env.shift_down, env.shift_used = false, false
      close_assoc(ctx)
      return kAccepted
    end
  elseif not key:release() then
    env.assoc_tap = false
    -- Shift+; / Shift+- / Shift+6 …: releasing that Shift is not an English commit tap.
    if env.shift_down and kc ~= env.commit_code then
      env.shift_used = true
    end
    if kc == 0xffe2 and kc ~= env.commit_code then
      if not env.rshift_down then
        env.rshift_used = false
      end
      env.rshift_down = true
    elseif env.rshift_down then
      env.rshift_used = true
    end
  end
  -- Right Shift used as a modifier (Shift_R + ;): ascii_composer's Shift_R
  -- commit_text would fire on the release and commit the raw code (vd:).
  if kc == 0xffe2 and kc ~= env.commit_code and key:release() then
    local used = env.rshift_down and env.rshift_used
    env.rshift_down, env.rshift_used = false, false
    if used then
      return kAccepted
    end
  end

  if not key:release() then
    -- Ctrl+C / X while composing (Ctrl+V: paste_key above): the emacs bindings turned Ctrl+V into
    -- Page_Down and the app never saw the shortcut. Send the held top-outs
    -- (Windows had committed them), drop the letters, let the app copy/paste.
    if env.clipboard ~= "keep" and key:ctrl() and not key:alt() and not key:super()
       and CLIP[repr:match("^Control%+([a-z])$") or ""] and ctx:is_composing() then
      flush(env)
      S.guard = true
      ctx:clear()
      S.guard = false
      return kNoop
    end
    -- ASCII punctuation (Ctrl+.): every symbol commits itself as ASCII, after
    -- what an end key would commit for the composition (好; / const; / 我,).
    -- The punctuator only passes the key through in this mode, which some
    -- clients dropped; committing it here works the same everywhere.
    local cseg = ctx.composition and not ctx.composition:empty() and ctx.composition:back()
    local in_url = cseg and (cseg:has_tag("url") or cseg:has_tag("email") or cseg:has_tag("uppercase"))
    local url_start = S.tracking and kc < 0x80 and URL_START[S.raw .. string.char(kc)]

    -- Space on a URL / email: commit it plus a space, like an English word
    -- (www.x.com + Space typed www.x.com with no space).
    if repr == "space" and not S.tracking and env.smart and cseg
       and (cseg:has_tag("url") or cseg:has_tag("email")) then
      commit_word(env, ctx, (ctx.input or "") .. " ")
      return kAccepted
    end
    -- Space after a capitalised word or acronym (Sony, PS5, AI): commit what is
    -- shown plus the space, like a lowercase English word. librime committed
    -- the letters and dropped the Space, so "Sony PS5 " came out "SonyPS5".
    if repr == "space" and not S.tracking and env.smart and env.space_mode ~= "off"
       and cseg and cseg:has_tag("uppercase") then
      commit_word(env, ctx, ctx:get_commit_text() .. " ")
      return kAccepted
    end
    if ctx:get_option("ascii_punct") and not ctx:get_option("ascii_mode") and not in_url
       and not url_start
       and not (key:ctrl() or key:alt() or key:super()) and is_symbol(kc) then
      if assoc_active(ctx) then
        close_assoc(ctx)
      end
      local text = end_text(env, ctx)
      commit_word(env, ctx, text .. string.char(kc))
      return kAccepted
    end
  end

  -- Association list open (after a one-character pick). key_binder runs
  -- before assoc_keys and maps period to Page_Down whenever a menu shows, so a
  -- full stop typed after a Chinese pick was swallowed as paging. Close the
  -- list first; the key then reaches key_binder with no menu and types.
  if not key:release() and assoc_active(ctx) and
     not (key:ctrl() or key:alt() or key:super()) then
    -- Shift+9 sent as 9 / KP_9 with the Shift mask (direct process_key, some
    -- remote or on-screen keyboards): the punctuator would type 9, so commit （ here.
    local shift_nine = key:shift() and (kc == 0x39 or kc == 0xffb9)
    if ASSOC_PUNCT[repr] or (repr == "space" and env.assoc_space == "type")
       or ((kc == 0x28 or shift_nine) and not env.paren_pick) then
      close_assoc(ctx)
      if shift_nine and kc ~= 0x28 then
        env.engine:commit_text(full_shape(env) and "（" or "(")
        return kAccepted
      end
      return kNoop
    end
  end

  if not env.smart then
    return kNoop
  end

  -- Left Shift tap: press, then release with no other key in between.
  if kc == env.commit_code and not key:release() then
    -- an auto-repeat while Shift is held keeps the used flag (Bugbot)
    if not env.shift_down then
      env.shift_used = false
    end
    env.shift_down = true
    return kNoop
  end
  if kc == env.commit_code and key:release() then
    local used = env.shift_used -- set only by a key pressed while this Shift was down
    local tap = env.shift_down and not env.shift_used
    env.shift_down = false
    env.shift_used = false
    if used then
      -- this processor took the shifted key, so ascii_composer would read the
      -- release as a bare tap and switch to English: swallow it.
      return kAccepted
    end
    if tap and S.tracking and S.raw ~= "" then
      -- the raw letters (or a listed name: openai -> OpenAI) replace the held top-outs
      local text = shift_text(env, S.raw)
      commit_word(env, ctx, text)
      return kAccepted
    end
    local input = ctx.input or ""
    if tap and not ctx:get_option("ascii_mode") and input:match("^[a-z]+$") then
      commit_word(env, ctx, input) -- letters left after a Windows commit
      return kAccepted
    end
    -- Anything else being composed (uppercase / digits / a punctuation menu,
    -- e.g. 好API, or an inline-English run): commit what is shown and stay
    -- in Chinese. Letting ascii_composer run here turned the composition into
    -- an underlined inline-English run that only Enter or Esc could leave
    -- (Enter then committed the raw code, vdAPI instead of 好API).
    if tap and input ~= "" then
      local text = ctx:get_commit_text()
      flush(env)
      commit_word(env, ctx, text)
      if ctx:get_option("ascii_mode") then
        ctx:set_option("ascii_mode", false)
      end
      return kAccepted
    end
    -- Nothing typed: a stray tap must not switch to English (it looked like
    -- a stuck mode). english/empty_shift: ascii keeps the librime toggle.
    if tap and input == "" and env.empty_shift ~= "ascii"
       and not ctx:get_option("ascii_mode") then
      return kAccepted
    end
    return kNoop
  end
  if key:release() then
    return kNoop
  end
  if ctx:get_option("ascii_mode") then
    return kNoop
  end

  local plain = not (key:ctrl() or key:alt() or key:super())
  local input = ctx.input or ""

  -- A standalone digit stays half-width under full_shape: the global
  -- ShapeFormatter would otherwise turn 60cm into ６０cm. Only when nothing
  -- is composing — a digit inside a code, or an open association list, still
  -- selects a candidate and must reach the selector.
  if plain and not key:release() and repr:match("^[0-9]$") and input == ""
     and not S.tracking and not assoc_active(ctx) then
    commit_text(env, repr, true)
    return kAccepted
  end

  if plain and repr == "BackSpace" and S.tracking and S.raw ~= "" then
    backspace(env, ctx)
    return kAccepted
  end

  if plain and repr:match("^[a-z]$") then
    -- An externally cleared composition cannot keep a tracked English run.
    if S.tracking and input == "" then
      reset()
    end
    if S.tracking then
      local raw = S.raw .. repr
      if can_extend(env, raw) and input:match("^[a-z]*$") then
        if extend(env, ctx, repr) then
          return kAccepted
        end
        flush(env)
        return kNoop
      end
      -- The English prefix broke: send the held top-outs now (v0.4.1 had
      -- committed them already) and fall through, so this letter can still
      -- start a new English run at a code boundary.
      if env.rescue_min > 0 and not R.alive and S.known >= env.rescue_min then
        R.alive, R.raw, R.defer = true, raw, ""
        R.cap = S.known + env.rescue_extra
      end
      flush(env)
    end
    if input == "" then
      flush(env)
      if assoc_active(ctx) then
        close_assoc(ctx)
      end
      if ctx:get_property("kinfx_digit_tail") == "1" then
        -- A lowercase letter right after a digit is a unit/word tail (60cm,
        -- 12v, 2x6): output it literally, keep the digit-led flag alive, never
        -- start a Sucheng code run. Pure lowercase with no leading digit still
        -- types Sucheng (速成優先).
        commit_text(env, repr, true)
        return kAccepted
      end
      start_run(ctx, repr)
      return kAccepted
    end
    if not input:match("^[a-z]+$") then
      flush(env)
      -- A lowercase letter after a multi-letter ALL-CAPS abbreviation starts
      -- a new Sucheng code (MLG設計元素). Commit the abbreviation so the
      -- recognizer's `[A-Z][-_+.'0-9A-Za-z]*` pattern cannot swallow the code
      -- letters. Single-capital words (Edition, Docking) still keep their
      -- lowercase tail: one capital is ambiguous with a word.
      local cseg = ctx.composition and not ctx.composition:empty() and ctx.composition:back()
      if cseg and cseg:has_tag("uppercase") then
        local _, caps = input:gsub("[A-Z]", "")
        if caps >= 2 and not input:match("[a-z]") then
          commit_word(env, ctx, input)
        end
      end
      return kNoop
    end
    -- v0.4.1 step for this letter, commits held in S.pending.
    S.pending = ""
    if not v041_letter(env, ctx, repr) then
      flush(env)
      return kNoop
    end
    local rest = ctx.input or ""
    flush(env)
    if rest:match("^[a-z]+$") and is_prefix(env, rest) then
      -- Everything committed so far is final; the letters still composing
      -- start at a Windows code boundary, so track them as a possible word.
      S.tracking, S.raw, S.pending, S.known = true, rest, "", #rest
      S.known_en = en_prefix(env, rest) and #rest or 0
    end
    return kAccepted
  end

  if not S.tracking then
    return kNoop
  end
  -- A bare modifier press (Shift_R / Control / Alt before Shift+; …) is not an
  -- end key: keep the held run, or https + Shift_R + : committed 升花.
  -- Caps_Lock (0xffe5, schema action clear) still flushes (Bugbot).
  if kc >= 0xffe1 and kc <= 0xffee and kc ~= 0xffe5 and kc ~= 0xffe6 then
    return kNoop
  end
  clear_hint(ctx)
  if plain and (kc == 0x3a or kc == 0x2e) then
    local url = S.raw .. string.char(kc)
    if URL_START[url] then
      reset()
      set_input(ctx, url)
      return kAccepted
    end
  end
  -- A hyphen after a word that Space would commit as English joins words
  -- (tool-calling, e-mail): the word and an ASCII "-" go out, the next letters
  -- start a new run. Same safety rule as Space. english/hyphen: off = v0.5.2.
  if plain and kc == 0x2d and env.hyphen ~= "off" then
    local text = nil
    if space_allowed(env, S.raw) and #S.raw > 2 and not chinese_held(ctx) then
      text = space_text(env, S.raw)
    end
    if not text and unknown_space_ok(env, ctx) then
      text = S.raw
    end
    if text then
      return hold_latin(env, ctx, text, "-", text .. "-")
    end
  end
  -- 0.1.1: an apostrophe after a contraction stem waits for the next key (don't it's we're)
  if plain and kc == 0x27 and APOS_STEM[S.raw] and not chinese_held(ctx) then
    hold_latin(env, ctx, S.raw, "'", S.pending .. ctx:get_commit_text() .. "'")
    env.latin_apos = true
    return kAccepted
  end
  -- v0.5.9: ] / } (」 』) end a word like , and . ([1 nudification ]1 typed 乙寸灼曾芍乞); keycode
  -- so Shift+bracketright (Linux / macOS) and Weasel's braceright both match
  -- 0.1.1: Enter ? ! : ; ) too (hello Enter, /model Enter, thanks?); Enter commits with no newline, like Chinese
  -- Once this is an English word, every typed symbol is ASCII. Dot/hyphen/
  -- contraction continuation rules above still run first; Chinese menus still
  -- retain their number/Space/arrow/equal bindings.
  local endkey = plain and (repr == "space" or repr == "Return" or is_symbol(kc))
  if endkey and space_allowed(env, S.raw) and (#S.raw > 2 or repr == "space") and not chinese_held(ctx) then
    local text = space_text(env, S.raw)
    if text then
      if repr == "space" then
        commit_word(env, ctx, text .. " ")
        return kAccepted
      end
      if repr == "Return" then
        commit_word(env, ctx, text)
        return kAccepted
      end
      if kc == 0x2e then
        return hold_latin(env, ctx, S.raw, ".", text .. "。") -- openai.com, not OpenAI.com
      end
      commit_word(env, ctx, text .. string.char(kc))
      return kAccepted
    end
  end
  if endkey and unknown_space_ok(env, ctx) then
    if repr == "space" then
      commit_word(env, ctx, S.raw .. " ")
      return kAccepted
    end
    if repr == "Return" then
      commit_word(env, ctx, S.raw)
      return kAccepted
    end
    if kc == 0x2e then
      return hold_latin(env, ctx, S.raw, ".", S.raw .. "。")
    end
    commit_word(env, ctx, S.raw .. string.char(kc))
    return kAccepted
  end
  flush(env)
  return kNoop
end

-- Hint after the caret: pending top-outs, then ␣word (Space commits English)
-- or ⇧letters (Left Shift commits them).
local function filter_init(env)
  read_env(env)
end

local function filter_func(input, env)
  activate(env)
  -- The hint rides on the first candidate's comment, never on seg.prompt:
  -- a prompt is drawn inside the inline preedit, and clients that commit the
  -- preedit (Fcitx5 on focus change / IM switch) wrote it into the document.
  local hint = nil
  if env.smart and S.tracking and #S.raw >= 2 then
    local ctx = env.engine.context
    local mark = "⇧"
    if (space_allowed(env, S.raw) and not chinese_held(ctx)
        and space_text(env, S.raw)) or unknown_space_ok(env, ctx) then
      mark = "␣"
    end
    local held = R.defer .. S.pending
    local pre = held ~= "" and (held .. " ") or ""
    -- The preedit already shows the letters in letters mode; keep only the mark.
    hint = pre .. mark .. (env.letters and "" or S.raw)
  end
  -- Letters mode: every candidate's preedit is the letters it covers, and the
  -- whole held run while an English word is tracked (hello, not just o).
  local run, code = nil, nil
  if env.letters then
    code = env.engine.context.input or ""
    if env.smart and S.tracking and S.raw ~= "" then
      run = S.raw
    end
  end
  for cand in input:iter() do
    if code then
      local g = cand:get_genuine()
      g.preedit = run or code:sub(g.start + 1, g._end)
    end
    if hint then
      local c = cand.comment or ""
      yield(ShadowCandidate(cand, cand.type, cand.text, c ~= "" and (c .. " " .. hint) or hint))
      hint = nil
    else
      yield(cand)
    end
  end
end

return {
  processor = { init = init, fini = fini, func = function(key, env)
    activate(env)
    local ctx = env.engine.context
    -- A fresh context starts at the schema default (half-width). Restore the
    -- user's last full_shape toggle once, on the first key: init runs before
    -- librime applies the switch defaults, so a restore there is overwritten.
    if not env.full_shape_restored then
      env.full_shape_restored = true
      restore_full_shape(ctx)
    end
    -- Native ascii_composer rejects idle letters, but full_shape's postprocessor
    -- may still sink them (without commit_notifier). Observe only that literal
    -- route, never an association placeholder or uncommitted inline preedit.
    local kc = key.keycode
    local meta = math.floor(key.modifier / META_MASK) % 2 == 1
    local plain = not (key:ctrl() or key:alt() or key:super() or meta)
    local modifier = kc >= 0xffe1 and kc <= 0xffee and kc ~= 0xffe5 and kc ~= 0xffe6
    local mode_command = kc == 0x20 and not (key:alt() or key:super() or meta)
      and ((key:ctrl() and not key:shift()) or (key:shift() and not key:ctrl()))
    -- A bare Ctrl-down is not yet an edit. Classify its actual chord instead:
    -- Ctrl+Space/Shift+Space do not move the document caret; shortcuts do.
    if not key:release() and not mode_command
       and ((not modifier and not plain) or key:alt() or key:super()
         or kc == 0xff08 or kc == 0xffff or kc == 0xff1b
         or (kc >= 0xff50 and kc <= 0xff58)) then
      ctx:set_property("kinfx_punct_tail", "")
      ctx:set_property("kinfx_digit_tail", "")
    end
    if not key:release() and plain and ctx:get_option("ascii_mode")
       and not ctx:is_composing() and (ctx.input or "") == ""
       and ctx:get_property("kinfx_assoc_code") == ""
       and ((kc >= 0x41 and kc <= 0x5a) or (kc >= 0x61 and kc <= 0x7a)) then
      ctx:set_property("kinfx_punct_tail", "latin")
      -- ascii_mode letters are Western text and stay half-width even under
      -- full_shape (全角); ascii_composer would otherwise sink them fullwidth.
      local ch = string.char(kc)
      if key:shift() then ch = ch:upper() end
      commit_text(env, ch, true)
      return kAccepted
    end
    local r = func(key, env)
    ctx:set_property("kinfx_blur", blur_text(env, ctx))
    publish_display(env, ctx)
    return r
  end },
  filter = { init = filter_init, func = filter_func },
}
