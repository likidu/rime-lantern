-- rime-lantern: English gloss next to every Chinese candidate.
-- https://github.com/likidu/rime-lantern  (MIT)
--
-- Usage in a schema (or its *.custom.yaml):
--   engine/filters/+: [ lua_filter@*lantern ]
--   switches/+: [ { name: english_gloss, states: [ 译关, 译开 ] } ]
--   lantern:
--     data: lantern/cedict-en.tsv   # relative to the Rime user or shared dir
--     senses: 1                     # how many senses to show
--     max_chars: 24                 # truncate the gloss (in characters)
--     separator: " · "              # between an existing comment and the gloss
--     option: english_gloss         # the switch that turns the gloss on
--
-- Written for Lua 5.4; also runs on 5.3 and on LuaJIT (no utf8 library).

local M = {}

M.DEFAULTS = {
  data = "lantern/cedict-en.tsv",
  senses = 1,
  max_chars = 24,
  separator = " · ",
  option = "english_gloss",
  ellipsis = "…",
}

-- The gloss table is loaded once per process, on first use, and shared by
-- every session. Keys are simplified and traditional forms; values are the
-- raw gloss string ("sense1; sense2; sense3").
M.table = nil
M.rows = 0

local has_utf8 = type(utf8) == "table" and utf8.codes ~= nil

---------------------------------------------------------------------------
-- Pure helpers (exposed with a leading underscore for tests)
---------------------------------------------------------------------------

local function cjk_codepoint(cp)
  return (cp >= 0x4E00 and cp <= 0x9FFF)      -- CJK Unified Ideographs
      or (cp >= 0x3400 and cp <= 0x4DBF)      -- Extension A
      or (cp >= 0xF900 and cp <= 0xFAFF)      -- Compatibility Ideographs
      or (cp >= 0x20000 and cp <= 0x2FA1F)    -- Extensions B..F, Supplement
end

-- True when every character of text is a CJK ideograph.
function M._is_cjk(text)
  if text == nil or text == "" then return false end
  if has_utf8 then
    local ok, result = pcall(function()
      for _, cp in utf8.codes(text) do
        if not cjk_codepoint(cp) then return false end
      end
      return true
    end)
    if ok then return result end
    return false -- invalid UTF-8
  end
  -- No utf8 library (LuaJIT): accept only 3-byte sequences in the E3..E9
  -- lead-byte range (U+3000..U+9FFF) and 4-byte sequences F0 A0..AF
  -- (U+20000..U+2FFFF, the CJK extensions); this excludes emoji (F0 9F).
  local n3 = select(2, text:gsub("[\xE3-\xE9][\x80-\xBF][\x80-\xBF]", ""))
  local n4 = select(2, text:gsub("\xF0[\xA0-\xAF][\x80-\xBF][\x80-\xBF]", ""))
  return n3 * 3 + n4 * 4 == #text
end

-- Character length and prefix without relying on the utf8 library.
local function char_len(s)
  if has_utf8 then
    local n = utf8.len(s)
    if n then return n end
  end
  local _, count = s:gsub("[^\x80-\xBF]", "")
  return count
end

local function char_prefix(s, n)
  if has_utf8 then
    local ok, offset = pcall(utf8.offset, s, n + 1)
    if ok and offset then return s:sub(1, offset - 1) end
  end
  local i, count = 1, 0
  while i <= #s do
    if count == n then return s:sub(1, i - 1) end
    local c = s:byte(i)
    local width = c < 0x80 and 1 or c < 0xE0 and 2 or c < 0xF0 and 3 or 4
    i = i + width
    count = count + 1
  end
  return s
end

-- Parse one TSV row: "simp\ttrad\tgloss". Comments and blanks give nil.
function M._parse_line(line)
  if line == nil or line == "" or line:sub(1, 1) == "#" then return nil end
  local simp, trad, gloss = line:match("^([^\t]+)\t([^\t]+)\t([^\t\r]*)")
  if simp == nil or gloss == "" then return nil end
  return simp, trad, gloss
end

-- Pick the first `senses` senses and truncate to `max_chars` characters.
function M._shape(gloss, senses, max_chars, ellipsis)
  senses = (senses and senses >= 1) and senses or 1
  ellipsis = ellipsis or M.DEFAULTS.ellipsis
  local parts = {}
  for part in (gloss .. "; "):gmatch("(.-); ") do
    parts[#parts + 1] = part
    if #parts >= senses then break end
  end
  local text = table.concat(parts, "; ")
  if max_chars and max_chars > 0 and char_len(text) > max_chars then
    local keep = max_chars - char_len(ellipsis)
    local full = text
    text = char_prefix(full, keep)
    -- If the cut lands inside a word, back off to the previous word boundary,
    -- unless that would drop more than half the room.
    local next_char = char_prefix(full, keep + 1):sub(#text + 1)
    if next_char ~= "" and not next_char:match("^[%s%p]") then
      local at_word = text:match("^(.*)%s%S*$")
      if at_word and char_len(at_word) >= keep / 2 then text = at_word end
    end
    text = text:gsub("[%s;,]+$", "") .. ellipsis
  end
  return text
end

-- Append the gloss to an existing comment (e.g. a correction hint).
function M._append(existing, gloss, separator)
  if existing == nil or existing == "" then return gloss end
  return existing .. (separator or M.DEFAULTS.separator) .. gloss
end

-- Load a TSV file into a lookup table. Returns table, row count.
function M._load(path)
  local t, rows = {}, 0
  local f = io.open(path, "r")
  if not f then return nil, 0 end
  for line in f:lines() do
    local simp, trad, gloss = M._parse_line(line)
    if simp then
      t[simp] = gloss
      if trad ~= simp and t[trad] == nil then t[trad] = gloss end
      rows = rows + 1
    end
  end
  f:close()
  return t, rows
end

---------------------------------------------------------------------------
-- Rime glue
---------------------------------------------------------------------------

local function file_exists(path)
  local f = io.open(path, "r")
  if f then f:close() return true end
  return false
end

-- Resolve a data path: absolute as-is, else user dir first, then shared dir.
local function find_data(rel)
  if rel:sub(1, 1) == "/" or rel:match("^%a:[/\\]") then
    return file_exists(rel) and rel or nil
  end
  local dirs = {}
  if rime_api then
    if rime_api.get_user_data_dir then dirs[#dirs + 1] = rime_api.get_user_data_dir() end
    if rime_api.get_shared_data_dir then dirs[#dirs + 1] = rime_api.get_shared_data_dir() end
  end
  for _, dir in ipairs(dirs) do
    local path = dir .. "/" .. rel
    if file_exists(path) then return path end
  end
  return nil
end

local function read_options(config, ns)
  local o = {}
  for k, v in pairs(M.DEFAULTS) do o[k] = v end
  if config == nil then return o end
  local s = config:get_string(ns .. "/data");      if s and s ~= "" then o.data = s end
  s = config:get_string(ns .. "/separator");       if s and s ~= "" then o.separator = s end
  s = config:get_string(ns .. "/option");          if s and s ~= "" then o.option = s end
  s = config:get_string(ns .. "/ellipsis");        if s and s ~= "" then o.ellipsis = s end
  local n = config:get_int(ns .. "/senses");       if n and n >= 1 then o.senses = n end
  n = config:get_int(ns .. "/max_chars");          if n and n >= 0 then o.max_chars = n end
  return o
end

local function ensure_loaded(env)
  if M.table then return true end
  local path = env.lantern.path
  if not path then
    if log then log.error("lantern: data file not found: " .. env.lantern.data) end
    M.table = {}
    return false
  end
  local t0 = os.clock()
  local t, rows = M._load(path)
  M.table, M.rows = t or {}, rows
  if log then
    log.info(string.format("lantern: loaded %d rows from %s in %.0f ms",
      rows, path, (os.clock() - t0) * 1000))
  end
  return t ~= nil
end

function M.init(env)
  local ns = (env.name_space or "lantern"):gsub("^%*", "")
  local config = env.engine and env.engine.schema and env.engine.schema.config
  env.lantern = read_options(config, ns)
  env.lantern.path = find_data(env.lantern.data)
end

function M.func(input, env)
  local opts = env.lantern
  local ctx = env.engine.context
  if not ctx:get_option(opts.option) then
    for cand in input:iter() do yield(cand) end
    return
  end
  ensure_loaded(env)
  local t = M.table
  for cand in input:iter() do
    local text = cand.text
    if M._is_cjk(text) then
      local gloss = t[text]
      if gloss then
        local shaped = M._shape(gloss, opts.senses, opts.max_chars, opts.ellipsis)
        cand.comment = M._append(cand.comment, shaped, opts.separator)
      end
    end
    yield(cand)
  end
end

function M.fini(env) end

return M
