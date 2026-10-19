-- Windows Quick select UX on top of librime paging.
--
-- key_binder (schema) already maps, when a menu is showing:
--   space / Right → Page_Down,  Left → Page_Up
-- editor Return → confirm (focused candidate, not raw code).
-- This processor only adds what stock librime does not:
--   * Tab toggles a 4-column expand (active column stays page_size, keys 1–9)
--   * multi-page codes gain a wrap-around 「常用熱門」 page of exactly one page
--     … → last normal page → hot → page 1 → …
--     page 1 + Left → hot
-- Space with no menu is not touched, so mixed preedit 「好API」 still commits.
--
-- The filter does not reorder normal pages (dict order is the Windows top 9).
-- Favorites stay on the Left wrap page only.

local kAccepted = 1
local kNoop = 2

local VIEW_PROP = "kinfx_win_view"
local HOT_INPUT_PROP = "kinfx_hot_input"
local HOT_RETURN_PROP = "kinfx_hot_return"
local EXPAND_OPTION = "win_quick_expand"

local HIST_COMMENT = "♥常"
local FILL_COMMENT = "♥熱"

-- Shared by the processor and the filter (same Lua state).
local history = {}
local history_seq = 0
local history_loaded = false
local history_path = nil
local pending_code = ""
-- Texts the hot-page filter last showed. Select keys read this because the
-- select notifier no longer has the candidate, and table user dict is off.
local hot_slots = {}

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

local function page_size_of(env)
  local n = env.engine.schema.page_size
  if not n or n < 1 then
    return 9
  end
  return n
end

local function segment_of(ctx)
  local comp = ctx.composition
  if not comp or comp:empty() then
    return nil
  end
  return comp:back()
end

local function history_file()
  if history_path ~= nil then
    return history_path or nil
  end
  history_path = false
  if rime_api and rime_api.get_user_data_dir then
    local dir = rime_api.get_user_data_dir()
    if dir and dir ~= "" then
      history_path = dir .. "/kinfx_win_history.tsv"
    end
  end
  return history_path or nil
end

local function load_history()
  if history_loaded then
    return
  end
  history_loaded = true
  local path = history_file()
  if not path then
    return
  end
  local f = io.open(path, "r")
  if not f then
    return
  end
  for line in f:lines() do
    local code, text, n = line:match("^([^\t]+)\t([^\t]+)\t(%d+)$")
    if code and text then
      local bucket = history[code]
      if not bucket then
        bucket = {}
        history[code] = bucket
      end
      history_seq = history_seq + 1
      bucket[#bucket + 1] = {
        text = text,
        n = tonumber(n) or 1,
        seq = history_seq,
      }
    end
  end
  f:close()
end

local function save_history()
  local path = history_file()
  if not path then
    return
  end
  local f = io.open(path, "w")
  if not f then
    return
  end
  for code, bucket in pairs(history) do
    for _, item in ipairs(bucket) do
      f:write(code, "\t", item.text, "\t", tostring(item.n or 1), "\n")
    end
  end
  f:close()
end

local function sort_hist(bucket)
  table.sort(bucket, function(a, b)
    if a.n ~= b.n then
      return a.n > b.n
    end
    return a.seq > b.seq
  end)
end

local function note_history(code, text)
  if not code or code == "" or not text or text == "" then
    return
  end
  if code == text or code:find("%u") then
    return
  end
  if #text > 48 then
    return
  end
  load_history()
  local bucket = history[code]
  if not bucket then
    bucket = {}
    history[code] = bucket
  end
  history_seq = history_seq + 1
  local found = nil
  for _, item in ipairs(bucket) do
    if item.text == text then
      found = item
      break
    end
  end
  if found then
    found.n = (found.n or 0) + 1
    found.seq = history_seq
  else
    bucket[#bucket + 1] = { text = text, n = 1, seq = history_seq }
  end
  sort_hist(bucket)
  while #bucket > 9 do
    table.remove(bucket)
  end
  save_history()
end

local function sorted_history(code)
  load_history()
  local bucket = history[code]
  if not bucket then
    return {}
  end
  local copy = {}
  for i, item in ipairs(bucket) do
    copy[i] = item
  end
  sort_hist(copy)
  return copy
end

local function read_opts(env)
  local config = env.engine.schema.config
  env.hot_page = config_bool(config, "win_quick/hot_page", true)
  env.tab_expand = config_bool(config, "win_quick/tab_expand", true)
  env.space_pages = config_bool(config, "win_quick/space_pages", true)
  env.expand_columns = config_int(config, "win_quick/expand_columns", 4)
  if env.expand_columns > 8 then
    env.expand_columns = 8
  end
end

local function hot_active(ctx)
  if ctx:get_property(VIEW_PROP) ~= "hot" then
    return false
  end
  local want = ctx:get_property(HOT_INPUT_PROP) or ""
  local input = ctx.input or ""
  if want ~= input then
    ctx:set_property(VIEW_PROP, "")
    return false
  end
  return true
end

local function is_multi(seg, ps)
  return seg:get_candidate_at(ps) ~= nil
end

local function page_start_of(seg, ps)
  local idx = seg.selected_index or 0
  if idx < 0 then
    idx = 0
  end
  return idx - (idx % ps)
end

local function is_last_page(seg, ps)
  local start = page_start_of(seg, ps)
  return seg:get_candidate_at(start + ps) == nil
end

local function last_page_start(seg, ps)
  local i = 0
  local guard = 0
  while guard < 400 and seg:get_candidate_at(i + ps) do
    i = i + ps
    guard = guard + 1
  end
  return i
end

local function refresh_at(ctx, index)
  ctx:refresh_non_confirmed_composition()
  local seg = segment_of(ctx)
  if seg then
    seg.selected_index = index
    -- No prompt text: the prompt is drawn inside the inline preedit and
    -- some clients keep it with the text. The 9 slots carry ♥常／♥熱 instead.
  end
end

local function enter_hot_at(ctx, ps)
  local seg = segment_of(ctx)
  if not seg then
    return
  end
  local back = last_page_start(seg, ps)
  ctx:set_property(HOT_RETURN_PROP, tostring(back))
  ctx:set_property(HOT_INPUT_PROP, ctx.input or "")
  ctx:set_property(VIEW_PROP, "hot")
  seg.selected_index = 0
  refresh_at(ctx, 0)
end

local function leave_hot(ctx, index)
  ctx:set_property(VIEW_PROP, "")
  ctx:set_property(HOT_INPUT_PROP, "")
  refresh_at(ctx, index)
end

local function toggle_expand(ctx)
  local seg = segment_of(ctx)
  local idx = seg and (seg.selected_index or 0) or 0
  local on = not ctx:get_option(EXPAND_OPTION)
  ctx:set_option(EXPAND_OPTION, on)
  if seg then
    seg.selected_index = idx
  end
  refresh_at(ctx, idx)
end

local function move_expanded(ctx, ps, dir)
  local seg = segment_of(ctx)
  if not seg then
    return
  end
  local start = page_start_of(seg, ps)
  local dest = dir > 0 and (start + ps) or (start - ps)
  if dest < 0 then
    dest = 0
  end
  seg.selected_index = dest
  refresh_at(ctx, dest)
end

local function handle_page(env, ctx, dir)
  if not ctx:has_menu() then
    return kNoop
  end
  local input = ctx.input or ""
  if input ~= "" then
    pending_code = input
  end
  local ps = page_size_of(env)
  if hot_active(ctx) then
    if dir > 0 then
      leave_hot(ctx, 0)
    else
      local back = tonumber(ctx:get_property(HOT_RETURN_PROP)) or 0
      leave_hot(ctx, back)
    end
    return kAccepted
  end
  local seg = segment_of(ctx)
  if not seg then
    return kNoop
  end
  local multi = is_multi(seg, ps)
  local at_first = page_start_of(seg, ps) == 0
  local at_last = is_last_page(seg, ps)
  if env.hot_page and multi and dir > 0 and at_last then
    enter_hot_at(ctx, ps)
    return kAccepted
  end
  if env.hot_page and multi and dir < 0 and at_first then
    enter_hot_at(ctx, ps)
    return kAccepted
  end
  if not ctx:get_option(EXPAND_OPTION) then
    return kNoop
  end
  if (dir > 0 and at_last) or (dir < 0 and at_first) then
    return kAccepted
  end
  move_expanded(ctx, ps, dir)
  return kAccepted
end

-- Digit / Enter select runs after this processor. The select notifier does not
-- still hold the candidate, and table user dict is off so it cannot learn it.
-- Record the visible slot here. One lookup, and only when this key is 1–9 or Enter.
local function note_select_key(env, ctx, repr)
  local digit = repr:match("^([1-9])$") or repr:match("^KP_([1-9])$")
  local is_return = repr == "Return" or repr == "KP_Enter"
  if not digit and not is_return then
    return
  end
  if not ctx:has_menu() then
    return
  end
  local code = ctx.input or ""
  if code == "" then
    code = pending_code
  end
  if hot_active(ctx) then
    local n = nil
    if digit then
      n = tonumber(digit)
    elseif repr == "Return" or repr == "KP_Enter" then
      local seg = segment_of(ctx)
      local idx = seg and seg.selected_index or 0
      if idx < 0 then
        idx = 0
      end
      n = (idx % page_size_of(env)) + 1
    end
    local text = n and hot_slots[n] or nil
    if text then
      note_history(code, text)
    end
    return
  end
  local seg = segment_of(ctx)
  if not seg then
    return
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
  if cand and cand.text then
    note_history(code, cand.text)
  end
end

local function processor_init(env)
  read_opts(env)
  -- Tab expand belongs to one composition. When the input is gone (Esc,
  -- commit, Backspace to empty) switch it off, so the next code starts in the
  -- normal list. The option is not saved (not in switches), so this only
  -- resets the session flag.
  env.expand_conn = env.engine.context.update_notifier:connect(function(ctx)
    if (ctx.input or "") == "" and ctx:get_option(EXPAND_OPTION) then
      ctx:set_option(EXPAND_OPTION, false)
    end
  end)
end

local function processor_fini(env)
  if env.expand_conn then
    env.expand_conn:disconnect()
  end
end

-- Composition letters must not enter the history path. Ranking stays in the dict.
local SELECT_REPR = {
  ["1"] = true,
  ["2"] = true,
  ["3"] = true,
  ["4"] = true,
  ["5"] = true,
  ["6"] = true,
  ["7"] = true,
  ["8"] = true,
  ["9"] = true,
  KP_1 = true,
  KP_2 = true,
  KP_3 = true,
  KP_4 = true,
  KP_5 = true,
  KP_6 = true,
  KP_7 = true,
  KP_8 = true,
  KP_9 = true,
  Return = true,
  KP_Enter = true,
}

local NEXT_KEY = {
  Page_Down = true,
  Next = true,
}

local PREV_KEY = {
  Page_Up = true,
  Prior = true,
}

local function processor_func(key, env)
  if key:release() or key:alt() or key:ctrl() or key:super() then
    return kNoop
  end
  local ctx = env.engine.context
  local repr = key:repr()
  -- The association list (assoc.lua) owns its keys: no hot-page wrap, no
  -- history entry for a suffix under the previous code.
  local seg0 = segment_of(ctx)
  if seg0 and seg0:has_tag("kinfx_assoc") then
    return kNoop
  end
  if ctx.input and ctx.input ~= "" then
    pending_code = ctx.input
  end

  -- Flex: win_quick/space_pages: false restores space = confirm focused candidate.
  -- Default stays kNoop so key_binder can turn space into Page_Down.
  if repr == "space" and ctx:has_menu() and env.space_pages == false then
    note_select_key(env, ctx, "Return")
    ctx:confirm_current_selection()
    return kAccepted
  end

  if repr == "Tab" then
    if not env.tab_expand or not ctx:has_menu() then
      return kNoop
    end
    toggle_expand(ctx)
    return kAccepted
  end

  if NEXT_KEY[repr] then
    return handle_page(env, ctx, 1)
  end
  if PREV_KEY[repr] then
    return handle_page(env, ctx, -1)
  end
  if SELECT_REPR[repr] then
    note_select_key(env, ctx, repr)
  end
  return kNoop
end

local function collect(input, limit)
  local list = {}
  for cand in input:iter() do
    list[#list + 1] = cand
    if #list >= limit then
      break
    end
  end
  return list
end

local function find_cand(list, text)
  for _, cand in ipairs(list) do
    if cand.text == text then
      return cand
    end
  end
  return nil
end

local function user_dict_texts(env, code)
  local out = {}
  if not env.mem or not code or code == "" then
    return out
  end
  local ok, hit = pcall(function()
    return env.mem:user_lookup(code, false)
  end)
  if not ok or not hit then
    return out
  end
  local walked = pcall(function()
    for entry in env.mem:iter_user() do
      if entry and entry.text and entry.text ~= "" then
        out[#out + 1] = {
          text = entry.text,
          weight = entry.weight or 0,
          commit_count = entry.commit_count or 0,
        }
      end
    end
  end)
  if not walked then
    return {}
  end
  table.sort(out, function(a, b)
    if a.weight ~= b.weight then
      return a.weight > b.weight
    end
    return a.commit_count > b.commit_count
  end)
  return out
end

local function push_slot(slots, seen, ps, text, comment, orig)
  if not text or text == "" or seen[text] then
    return
  end
  if #slots >= ps then
    return
  end
  seen[text] = true
  slots[#slots + 1] = { text = text, comment = comment, orig = orig }
end

local function yield_hot(env, ctx, list)
  local ps = page_size_of(env)
  local code = ctx.input or ""
  local slots = {}
  local seen = {}
  for _, entry in ipairs(user_dict_texts(env, code)) do
    push_slot(slots, seen, ps, entry.text, HIST_COMMENT, find_cand(list, entry.text))
  end
  for _, entry in ipairs(sorted_history(code)) do
    push_slot(slots, seen, ps, entry.text, HIST_COMMENT, find_cand(list, entry.text))
  end
  for _, cand in ipairs(list) do
    if #slots >= ps then
      break
    end
    push_slot(slots, seen, ps, cand.text, FILL_COMMENT, cand)
  end
  local seg = segment_of(ctx)
  local start_i = seg and seg.start or 0
  local end_i = seg and seg._end or #code
  hot_slots = {}
  for _, slot in ipairs(slots) do
    hot_slots[#hot_slots + 1] = slot.text
    if slot.orig then
      yield(ShadowCandidate(slot.orig, "win_hot", slot.text, slot.comment))
    else
      yield(Candidate("phrase", start_i, end_i, slot.text, slot.comment))
    end
  end
end

local function grid_comment(buf, index0, ps, cols, active_page)
  local viewport = math.floor(active_page / cols) * cols
  local row = index0 % ps
  local parts = {}
  for col = 0, cols - 1 do
    local j = (viewport + col) * ps + row + 1
    local text = (buf[j] and buf[j].text and buf[j].text ~= "" and buf[j].text) or "·"
    if viewport + col == active_page then
      parts[#parts + 1] = "【" .. text .. "】"
    else
      parts[#parts + 1] = text
    end
  end
  return table.concat(parts, " ")
end

local function yield_expanded(env, ctx, input)
  local next_fn, state = input:iter()
  local buf = {}
  local function ensure(n)
    if n > 2000 then
      n = 2000
    end
    while #buf < n do
      local cand = next_fn(state)
      if not cand then
        return false
      end
      buf[#buf + 1] = cand
    end
    return true
  end
  local i = 0
  while true do
    i = i + 1
    if not ensure(i) then
      break
    end
    local cand = buf[i]
    local ps = page_size_of(env)
    local cols = env.expand_columns or 4
    local seg = segment_of(ctx)
    local sel = (seg and seg.selected_index) or 0
    local active_page = math.floor(sel / ps)
    local page = math.floor((i - 1) / ps)
    if page == active_page then
      local viewport = math.floor(active_page / cols) * cols
      local row = (i - 1) % ps
      local need = (viewport + cols - 1) * ps + row + 1
      ensure(need)
      local comment = grid_comment(buf, i - 1, ps, cols, active_page)
      yield(ShadowCandidate(cand, "win_grid", cand.text, comment))
    else
      yield(cand)
    end
  end
end

local function filter_init(env)
  read_opts(env)
  -- User dict is off (Windows order is fixed). Open Memory only if a custom
  -- patch turns it back on, so the default filter stays allocation-free.
  local cfg = env.engine.schema.config
  if cfg:get_bool("translator/enable_user_dict") then
    local ok, mem = pcall(function()
      return Memory(env.engine, env.engine.schema)
    end)
    if ok then
      env.mem = mem
    end
  end
end

local function filter_func(input, env)
  local ctx = env.engine.context
  if hot_active(ctx) then
    -- Only substitute when this code really has another page. A stale
    -- property must not hide a one-page menu or reshuffle page 1.
    local list = collect(input, 2000)
    local ps = page_size_of(env)
    if #list > ps then
      yield_hot(env, ctx, list)
      return
    end
    ctx:set_property(VIEW_PROP, "")
    for _, cand in ipairs(list) do
      yield(cand)
    end
    return
  end
  if env.tab_expand and ctx:get_option(EXPAND_OPTION) then
    yield_expanded(env, ctx, input)
    return
  end
  for cand in input:iter() do
    yield(cand)
  end
end

local M = {}
M.processor = { init = processor_init, func = processor_func, fini = processor_fini }
M.filter = { init = filter_init, func = filter_func }
return M
