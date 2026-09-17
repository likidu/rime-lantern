package.path = "./lua/?.lua;" .. package.path
local M = require("lantern")

local FIXTURE = "tests/lua/fixtures/gloss.tsv"

local function fake_cand(text, comment)
  return { text = text, comment = comment or "" }
end

local function fake_input(cands)
  return { iter = function()
    local i = 0
    return function() i = i + 1; return cands[i] end
  end }
end

local function fake_ctx(option_on)
  local ctx = {
    connected = {},
    get_option = function(_, name) return name == "english_gloss" and option_on end,
  }
  ctx.update_notifier = { connect = function(_, fn)
    ctx.connected[#ctx.connected + 1] = fn
    return { disconnect = function() ctx.disconnected = true end }
  end }
  return ctx
end

-- extra: config overrides; defaults to mode "all" so v1 specs stay meaningful
local function fake_env(option_on, path, extra)
  extra = extra or {}
  if extra["lantern/mode"] == nil then extra["lantern/mode"] = "all" end
  local env = {
    name_space = "*lantern",
    engine = {
      context = fake_ctx(option_on),
      schema = { config = {
        get_string = function(_, key) return extra[key] end,
        get_int = function(_, key) return extra[key] end,
      } },
    },
  }
  M.init(env)
  env.lantern.path = path
  return env
end

-- A fake composition with one segment and a lazily "prepared" menu.
local function fake_menu(ctx, cands, selected)
  local prepared = 0
  local seg = { selected_index = selected or 0 }
  seg.menu = {
    prepare = function(_, n) if n > prepared then prepared = math.min(n, #cands) end end,
    candidate_count = function() return prepared end,
    get_candidate_at = function(_, i) return cands[i + 1] end,
  }
  ctx.composition = { empty = function() return false end, back = function() return seg end }
  return seg
end

local function run(env, cands)
  local out = {}
  _G.yield = function(c) out[#out + 1] = c end
  M.func(fake_input(cands), env)
  return out
end

describe("_is_cjk", function()
  it("accepts pure CJK", function()
    assert.is_true(M._is_cjk("银行"))
    assert.is_true(M._is_cjk("龘"))
  end)
  it("rejects ASCII, digits, emoji, mixed and empty", function()
    assert.is_false(M._is_cjk("hello"))
    assert.is_false(M._is_cjk("110"))
    assert.is_false(M._is_cjk("🏦"))
    assert.is_false(M._is_cjk("X光"))
    assert.is_false(M._is_cjk(""))
    assert.is_false(M._is_cjk("，"))
  end)
end)

describe("_parse_line", function()
  it("parses rows and skips comments", function()
    local s, t, g = M._parse_line("开发\t開發\tto exploit; to develop")
    assert.same({ "开发", "開發", "to exploit; to develop" }, { s, t, g })
    assert.is_nil(M._parse_line("# comment"))
    assert.is_nil(M._parse_line(""))
    assert.is_nil(M._parse_line("x\ty\t"))
  end)
end)

describe("_shape", function()
  it("picks the first N senses", function()
    assert.equal("to exploit", M._shape("to exploit; to open up; to develop", 1, 24))
    assert.equal("to exploit; to open up", M._shape("to exploit; to open up; to develop", 2, 40))
    assert.equal("bank", M._shape("bank", 3, 24))
  end)
  it("truncates by characters with an ellipsis, trimming trailing separators", function()
    local long = "Beijing municipality, capital of the People's Republic of China"
    local s = M._shape(long, 1, 24)
    assert.equal("Beijing municipality…", s)
    assert.equal("to exploit; to open up…", M._shape("to exploit; to open up; to develop", 3, 24))
    assert.equal("to exploit; to…", M._shape("to exploit; to open up; to develop", 3, 16))
  end)
  it("cuts mid-word when a word boundary would drop more than half", function()
    assert.equal("supercalifragilis…", M._shape("supercalifragilisticexpialidocious yes", 1, 18))
    assert.equal("a supercalifr…", M._shape("a supercalifragilistic", 1, 14))
  end)
  it("does not truncate when max_chars is 0", function()
    local long = "Beijing municipality, capital of the People's Republic of China"
    assert.equal(long, M._shape(long, 1, 0))
  end)
  it("counts multibyte characters, not bytes", function()
    assert.equal("ééééé", M._shape("ééééé", 1, 5))
    assert.equal("éééé…", M._shape("éééééé", 1, 5))
  end)
end)

describe("_append", function()
  it("returns the gloss alone when there is no comment", function()
    assert.equal("bank", M._append("", "bank", " · "))
    assert.equal("bank", M._append(nil, "bank", " · "))
  end)
  it("keeps an existing comment in front", function()
    assert.equal("jǐ yǔ · to give", M._append("jǐ yǔ", "to give", " · "))
  end)
end)

describe("_strip", function()
  it("removes a gloss we appended and nothing else", function()
    assert.equal("", M._strip("bank", "bank", " · "))
    assert.equal("jǐ yǔ", M._strip("jǐ yǔ · to give", "to give", " · "))
    assert.equal("jǐ yǔ", M._strip("jǐ yǔ", "to give", " · "))
    assert.equal("", M._strip("", "bank", " · "))
    assert.equal("", M._strip(nil, "bank", " · "))
    assert.equal("banker", M._strip("banker", "bank", " · "))
  end)
end)

describe("highlighted mode", function()
  before_each(function() M.table = nil end)

  it("connects the update notifier only in highlighted mode", function()
    local env = fake_env(true, FIXTURE, { ["lantern/mode"] = "highlighted" })
    assert.equal(1, #env.engine.context.connected)
    assert.is_not_nil(env.lantern.connection)
    local env_all = fake_env(true, FIXTURE)
    assert.equal(0, #env_all.engine.context.connected)
    M.fini(env)
    assert.is_true(env.engine.context.disconnected)
  end)

  it("func passes everything through untouched", function()
    local env = fake_env(true, FIXTURE, { ["lantern/mode"] = "highlighted" })
    local out = run(env, { fake_cand("银行") })
    assert.equal("", out[1].comment)
  end)

  it("glosses the initially highlighted candidate after preparing the menu", function()
    local env = fake_env(true, FIXTURE, { ["lantern/mode"] = "highlighted" })
    local ctx = env.engine.context
    local cands = { fake_cand("银行"), fake_cand("🏦"), fake_cand("引航") }
    fake_menu(ctx, cands, 0)
    M._on_update(ctx, env)
    assert.equal("bank", cands[1].comment)
    assert.equal("", cands[2].comment)
    assert.equal("", cands[3].comment)
  end)

  it("moves the gloss with the highlight and keeps other comments", function()
    local env = fake_env(true, FIXTURE, { ["lantern/mode"] = "highlighted" })
    local ctx = env.engine.context
    local cands = { fake_cand("给予", "jǐ yǔ"), fake_cand("给"), fake_cand("开发") }
    local seg = fake_menu(ctx, cands, 0)
    M._on_update(ctx, env)
    assert.equal("jǐ yǔ · to give", cands[1].comment)
    seg.selected_index = 2
    M._on_update(ctx, env)
    assert.equal("jǐ yǔ", cands[1].comment)
    assert.equal("", cands[2].comment)
    assert.equal("to exploit", cands[3].comment)
    seg.selected_index = 0
    M._on_update(ctx, env)
    assert.equal("jǐ yǔ · to give", cands[1].comment)
    assert.equal("", cands[3].comment)
  end)

  it("does nothing when the option is off or the composition is empty", function()
    local env = fake_env(false, FIXTURE, { ["lantern/mode"] = "highlighted" })
    local ctx = env.engine.context
    local cands = { fake_cand("银行") }
    fake_menu(ctx, cands, 0)
    M._on_update(ctx, env)
    assert.equal("", cands[1].comment)
    assert.is_nil(M.table)
    local env2 = fake_env(true, FIXTURE, { ["lantern/mode"] = "highlighted" })
    env2.engine.context.composition = { empty = function() return true end }
    M._on_update(env2.engine.context, env2)
    assert.is_nil(M.table)
  end)
end)

describe("_load", function()
  it("indexes simplified and traditional forms", function()
    local t, rows = M._load(FIXTURE)
    assert.equal(6, rows)
    assert.equal("bank", t["银行"])
    assert.equal("bank", t["銀行"])
    assert.equal("time", t["時間"])
  end)
  it("returns nil for a missing file", function()
    local t, rows = M._load("/nonexistent/x.tsv")
    assert.is_nil(t)
    assert.equal(0, rows)
  end)
end)

describe("func", function()
  before_each(function() M.table = nil end)

  it("passes candidates through untouched when the option is off", function()
    local env = fake_env(false, FIXTURE)
    local out = run(env, { fake_cand("银行"), fake_cand("hello") })
    assert.equal(2, #out)
    assert.equal("", out[1].comment)
    assert.is_nil(M.table)
  end)

  it("glosses CJK candidates and leaves others alone when on", function()
    local env = fake_env(true, FIXTURE)
    local out = run(env, { fake_cand("银行"), fake_cand("🏦"), fake_cand("hello"), fake_cand("引航") })
    assert.equal("bank", out[1].comment)
    assert.equal("", out[2].comment)
    assert.equal("", out[3].comment)
    assert.equal("", out[4].comment)
  end)

  it("appends to an existing comment", function()
    local env = fake_env(true, FIXTURE)
    local out = run(env, { fake_cand("给予", "jǐ yǔ") })
    assert.equal("jǐ yǔ · to give", out[1].comment)
  end)

  it("honours senses, max_chars and separator from config", function()
    local env = fake_env(true, FIXTURE, {
      ["lantern/senses"] = 2, ["lantern/max_chars"] = 12, ["lantern/separator"] = " | ",
    })
    local out = run(env, { fake_cand("开发", "x") })
    assert.equal("x | to exploit…", out[1].comment)
    -- "to exploit; to open up" (22 chars) does not fit in 12: cut after "to exploit;"
  end)

  it("loads lazily once and reuses the table", function()
    local env = fake_env(true, FIXTURE)
    run(env, { fake_cand("银行") })
    assert.equal(6, M.rows)
    local t = M.table
    run(env, { fake_cand("银行") })
    assert.equal(t, M.table)
  end)

  it("degrades to passthrough when the data file is missing", function()
    local env = fake_env(true, nil)
    local out = run(env, { fake_cand("银行") })
    assert.equal("", out[1].comment)
  end)
end)
