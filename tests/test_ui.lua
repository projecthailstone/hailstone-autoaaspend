-- The windows (autoaaspend/ui/modern/autoaaspend.lua) drawn over stand-ins for the client's ui, eq, the Modern
-- pack's theme (lib/hud.lua) and its AA window library (lib/aa.lua): every page draws without an error, and the
-- buttons that matter send the script the right command. What it looks like is not checked here.

local function stubs(opts)
  opts = opts or {}
  local env = { calls = {}, windows = {}, aaCalls = 0, shown = {} }
  local hits = opts.hits or {}
  local zero = function() return 0, 0 end
  local ui = {
    Mouse = { Left = 0, Right = 1 },
    InputTextFlags = { CharsDecimal = 8 },
    GetCursorScreenPos = zero, GetCursorPos = zero, GetMousePos = zero,
    GetContentRegionAvail = function() return 400, 300 end,
    CalcTextSize = function(t) return #(t or "") * 6, 12 end,
    GetTime = function() return 1.5 end,
    GetIO = function() return { uiScale = 1 } end,
    InputTextWithHint = function(_, _, text) return opts.search or text end,
    InputText = function(_, text) return text, false end,
    Checkbox = function(_, v) return v, false end,
    BeginChild = function() return true end,
    BeginPopupContextItem = function() return false end,
    BeginPopup = function() return false end,
    MenuItem = function() return false end,
    IsItemHovered = function() return opts.hover == true end,
    IsItemActive = function() return false end,
    IsMouseDown = function() return false end,
    IsMouseDragging = function() return false end,
    window = function(name, fn) env.windows[name] = fn end,
    base_window = function() env.base = (env.base or 0) + 1 return true end,
  }
  setmetatable(ui, { __index = function(_, k)
    if type(k) == "string" and k:match("^[A-Z]") then return function() end end
    return nil
  end })
  local color = setmetatable({}, { __index = function() return { 0.5, 0.5, 0.5, 1 } end })
  local T = {
    color = color,
    font = { tiny = 1, small = 2, normal = 3, large = 4 },
    Hit = function(id) return hits[id] == true end,
    Text = function() return 0, 0 end,
    TextSize = function(t) return #(t or "") * 6, 12 end,
    Fit = function(t) return t end,
    Button = function(id) return hits[id] == true end,
  }
  local hud = {
    T = T,
    Window = function(_, title, o, body)
      env.shown[title] = true
      if o.shown and not o.shown() then return end
      local w, h = o.size(1)
      body(0, 0, w, h, 1)
    end,
  }
  local aa = {
    window = function(o)
      env.aaCalls = env.aaCalls + 1
      o.banner(0, 0, 600, 1)
      for _, r in ipairs(opts.rows or {}) do
        o.row.style(r)
        o.row.draw(r, 560, 0, 600, 38, 1)
      end
      o.details(opts.sel, 0, 0, 280, 1)
    end,
  }
  local P = {
    state = function() return opts.state end,
    settings = function() return opts.settings end,
    abilities = function() return opts.abilities or {} end,
    set = function(path, value) env.calls[#env.calls + 1] = { "set", path, value } return true end,
    command = function(...) env.calls[#env.calls + 1] = { ... } return true end,
  }
  local eqapi = {
    Plugin = function(name)
      if opts.noPlugin or name ~= "autoaaspend" then return nil end
      return P
    end,
    InGame = function() return true end,
    ShowWindow = function(name, on) env.showWindow = { name, on } end,
  }
  local g = setmetatable({
    ui = ui, eq = eqapi,
    dofile = function(path)
      if path == "lib/hud.lua" then return hud end
      if path == "lib/aa.lua" then
        if opts.noAALib then error("cannot open lib/aa.lua") end
        return aa
      end
      error("unexpected dofile " .. tostring(path))
    end,
  }, { __index = _G })
  local chunk = assert(loadfile(ROOT .. "/autoaaspend/ui/modern/autoaaspend.lua", "t", g))
  chunk()
  return env
end

local settings = require('lib.settings')

local function sampleSettings()
  local S = settings.defaults()
  settings.add(S, "Innate Strength", 10)
  settings.add(S, "Mystical Shielding", 20, 2)
  S.list[2].on = false
  S.reserve = 5
  return S
end

local function sampleState(over)
  local st = {
    open = true, running = true, once = false, allowed = true, character = true, points = 12, spent = 30, level = 60,
    status = "Buying Innate Strength...", rev = 3, abilities_rev = 1,
    next = { name = "Innate Strength", cost = 3, why = "list", rank = 2, max = 5 },
    entries = {
      { name = "Innate Strength", group = 10, state = "ready", text = "Ready", rank = 1, max = 5, cost = 3, cap = 0,
        on = true, tab = 1, category = "Stats" },
      { name = "Mystical Shielding", group = 20, state = "off", text = "Off", rank = 0, max = 12, cost = 2, cap = 2,
        on = false, tab = 1, category = "" },
    },
    log = { { text = "Started.", at = 0 }, { text = "Bought Innate Strength rank 1 (3 pt), 12 left.", at = 60 } },
  }
  for k, v in pairs(over or {}) do st[k] = v end
  return st
end

local ROWS = {
  { name = "Innate Strength", rank = 1, max = 5, cost = "3", category = "Stats", trainable = true, maxed = false, page = 0 },
  { name = "Mystical Shielding", rank = 0, max = 12, cost = "2", category = "", trainable = true, maxed = false, page = 0 },
  { name = "Not Queued", rank = 3, max = 3, cost = "", category = "", trainable = false, maxed = true, page = 0 },
}

local function draw(env, name)
  local ok, err = pcall(env.windows[name])
  check(ok, name .. ": " .. tostring(err))
end

case("ui: the Auto AA window's pages and the AA window draw", function()
  for _, pageHit in ipairs({ "none", "##aaspagesettings", "##aaspagelog" }) do
    local env = stubs({ state = sampleState(), settings = sampleSettings(), rows = ROWS,
      sel = { id = 100, name = "Innate Strength", rank = 1, max = 5, cost = "3" }, hits = { [pageHit] = true } })
    check(env.windows["Auto AA"] ~= nil, "the Auto AA window")
    check(env.windows["Alternate Advancement"] ~= nil, "the AA window's cover")
    draw(env, "Auto AA")
    draw(env, "Auto AA") -- (the page chosen on the first frame)
    draw(env, "Alternate Advancement")
    eq(env.aaCalls, 1)
  end
end)

case("ui: hovered, empty, paused and with a search", function()
  local S = settings.defaults()
  local env = stubs({ state = sampleState({ running = false, next = nil, entries = {}, log = {} }), settings = S,
    hover = true, search = "inn", abilities = { { name = "Innate Strength", group = 10, rank = 0, max_rank = 5, cost = 1 } },
    rows = ROWS, sel = { name = "" } })
  draw(env, "Auto AA")
  draw(env, "Alternate Advancement")
end)

case("ui: Start, the row toggle, Auto Buy's switch and the search send the script's commands", function()
  local env = stubs({ state = sampleState({ running = false }), settings = sampleSettings(), rows = ROWS,
    sel = { id = 300, name = "Not Queued", rank = 3, max = 3, cost = "" },
    abilities = { { name = "Not Queued", group = 30, rank = 3, max_rank = 3, cost = 0, maxed = true },
      { name = "Innate Strength", group = 10, rank = 1, max_rank = 5, cost = 3 } },
    hits = { ["##aasgo"] = true, ["##aastg0Not Queued"] = true, ["##aasdon"] = true, ["##aasrm1"] = true } })
  draw(env, "Auto AA")
  draw(env, "Alternate Advancement")
  local seen = {}
  for _, c in ipairs(env.calls) do seen[#seen + 1] = table.concat({ tostring(c[1]), tostring(c[2]), tostring(c[3]) }, " ") end
  local all = table.concat(seen, "; ")
  check(all:find("start", 1, true) ~= nil, all)
  check(all:find("remove Innate Strength 10", 1, true) ~= nil, all)
  check(all:find("flip Not Queued 30", 1, true) ~= nil, "the AA row's toggle, with the ability's group: " .. all)
end)

case("ui: without the script, or on an older client, the AA window is the pack's own", function()
  local env = stubs({ noPlugin = true, state = sampleState(), settings = sampleSettings() })
  draw(env, "Auto AA")
  draw(env, "Alternate Advancement")
  eq(env.base, 1)
  env = stubs({ noAALib = true, state = sampleState(), settings = sampleSettings() })
  draw(env, "Alternate Advancement")
  eq(env.base, 1)
  check(env.windows["Auto AA"] ~= nil, "the Auto AA window still loads")
end)
