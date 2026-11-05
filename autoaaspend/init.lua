-- Auto AA for Hailstone: spends your alternate advancement points for you, on the abilities you choose, in your
-- order.
--
-- The queue: tick abilities in the AA window (each row gets a toggle while this runs) or add them in the Auto AA
-- window. The first entry that can be bought is bought, one rank at a time, through the game's own check
-- (hailstone.train_aa: what /alternateadv buy does), until it is maxed or at the entry's highest rank. Options:
-- wait for the top entry instead of skipping past it, keep points in reserve, buy missing prerequisites first, buy
-- during fights, and fill with the cheapest abilities on chosen tabs when the queue has nothing to buy.
--
-- It buys one rank, then waits for the server to say so (the points or the rank change) before the next; a purchase
-- the server does not answer within a few seconds is left alone for a minute.
--
-- /autoaaspend [show | on | off | toggle | now | add <name> | remove <name> | status]
-- Settings are kept per server and character in scripts/config/autoaaspend/. A server may turn it off in its
-- hailstone.cfg: [autoaaspend] enabled = off.
local mq = require('mq')
local hs = require('hailstone')
local settings_mod = require('lib.settings')
local plan = require('lib.plan')

local TICK_MS = 250
local REFRESH_MS = 3000   -- the ability list is read again at least this often (and when the points change)
local GAP_MS = 900        -- between two purchases
local ANSWER_MS = 6000    -- a purchase the server has not answered by then is given up
local BACKOFF_MS = 60000  -- and that ability is left alone this long
local LOG_MAX = 60

local S = settings_mod.defaults()
local rev = 1
local dirty_at = nil
local loaded_for = nil
local open = true
local running = false
local once = false          -- "Spend now": buy what can be bought, then stop
local abilities, ix = {}, plan.index({})
local abilities_rev = 0
local read_at, read_points, read_spent = -1e9, -1, -1
local pending = nil         -- { group, name, rank, points, at }
local last_buy = -1e9
local backoff = {}          -- [group] = until (ms)
local log = {}              -- { text, at (os.time) }
local status = "Paused"
local next_pick = nil       -- { name, cost, why, for_name }
local bought_session = 0

local function say(text) hs.chat('[Auto AA] ' .. text, 15) end

local function note(text)
  log[#log + 1] = { text = text, at = os.time() }
  while #log > LOG_MAX do table.remove(log, 1) end
end

-- ---------------------------------------------------------------- settings

local function clean(s) return (tostring(s or ""):gsub("[^%w_%-]", "_")) end

local function settings_path()
  local server = mq.TLO.EverQuest.Server() or ""
  local char = mq.TLO.Me.Name() or ""
  if server == "" or char == "" then return nil end
  return "autoaaspend/" .. clean(server) .. "_" .. clean(char) .. ".lua"
end

local function allowed()
  local v = hs.server_rule("autoaaspend", "enabled")
  return not (v and (v:lower() == "off" or v:lower() == "no" or v == "0"))
end

local function changed()
  rev = rev + 1
  dirty_at = mq.gettime()
end

local function load_settings()
  local path = settings_path()
  if not path or path == loaded_for then return end
  if loaded_for and dirty_at then mq.pickle(loaded_for, S) end -- (the last character's, before switching)
  loaded_for = path
  local chunk = loadfile(path)
  local ok, t = false, nil
  if chunk then ok, t = pcall(chunk) end
  S = settings_mod.repair(ok and t or nil)
  rev = rev + 1
  dirty_at = nil
  pending, backoff, once = nil, {}, false
  read_at = -1e9
  running = S.resume and S.running and allowed()
  if running then note("Resumed after login.") end
end

local function save_if_due()
  if dirty_at and loaded_for and mq.gettime() - dirty_at > 1500 then
    mq.pickle(loaded_for, S)
    dirty_at = nil
  end
end

-- ---------------------------------------------------------------- running

local function set_running(on, quiet)
  if on and not allowed() then
    say("this server does not allow Auto AA.")
    return
  end
  running = on
  once = false
  if S.running ~= on then
    S.running = on
    changed()
  end
  if not quiet then say(on and "on." or "paused.") end
  note(on and "Started." or "Paused.")
  read_at = -1e9
end

local function in_combat()
  if mq.TLO.Me.Combat() then return true end
  local n = tonumber(hs.player() and hs.player().xtarget_slots) or 0
  for i = 1, n do
    local x = hs.xtarget(i)
    if x and x.type == 1 and (x.spawn_id or 0) ~= 0 then return true end
  end
  return false
end

local function read_abilities(now, p)
  if now - read_at < REFRESH_MS and p.aa_points == read_points and p.aa_spent == read_spent then return end
  abilities = hs.alt_abilities() or {}
  ix = plan.index(abilities)
  read_at, read_points, read_spent = now, p.aa_points, p.aa_spent
  abilities_rev = abilities_rev + 1
end

-- The purchase in flight has been answered (the rank or the points changed), or has waited too long.
local function settle(now, p)
  if not pending then return end
  local a = ix.by_group[pending.group]
  local rank = a and a.rank or pending.rank
  if rank > pending.rank or p.aa_points < pending.points then
    bought_session = bought_session + 1
    local text = string.format("Bought %s rank %d (%d pt), %d left.", pending.name, rank, pending.points - p.aa_points,
      p.aa_points)
    note(text)
    pending = nil
  elseif now - pending.at > ANSWER_MS then
    note("No answer for " .. pending.name .. "; leaving it for a minute.")
    backoff[pending.group] = now + BACKOFF_MS
    pending = nil
  end
end

local function skips(now)
  local out = {}
  for g, t in pairs(backoff) do
    if now < t then out[g] = true else backoff[g] = nil end
  end
  return out
end

local function tick()
  load_settings()
  local now = mq.gettime()
  local p = hs.player()
  if not p or not p.in_zone or not loaded_for then
    status = "Waiting for the game"
    return
  end
  read_abilities(now, p)
  settle(now, p)
  local pick, why = plan.pick(ix, S, p.aa_points, p.level, skips(now))
  next_pick = pick and { name = pick.ability.name, cost = pick.ability.cost, why = pick.why, for_name = pick.for_name,
    rank = pick.ability.rank + 1, max = pick.ability.max_rank } or nil
  if not running then
    status = allowed() and "Paused" or "Off on this server"
    return
  end
  if pending then
    status = "Buying " .. pending.name .. "..."
    return
  end
  if not pick then
    status = why or "Nothing to buy now"
    if once then
      once = false
      running = S.running
      note(bought_session > 0 and "Spend now: done." or "Spend now: nothing to buy.")
    end
    return
  end
  if not S.combat and in_combat() then
    status = "Waiting for the fight to end"
    return
  end
  if now - last_buy < GAP_MS then return end
  local a = pick.ability
  if hs.train_aa(a.group) then
    pending = { group = a.group, name = a.name, rank = a.rank, points = p.aa_points, at = now }
    last_buy = now
    status = "Buying " .. a.name .. "..."
  else
    backoff[a.group] = now + BACKOFF_MS / 2
    note("The game would not buy " .. a.name .. " now.")
    read_at = -1e9
  end
end

local function spend_now()
  if not allowed() then return say("this server does not allow Auto AA.") end
  bought_session = 0
  if running then return end
  running, once = true, true
  note("Spend now.")
end

-- ---------------------------------------------------------------- the windows' functions

local function add(name, group, cap)
  if settings_mod.add(S, name, group, cap) then changed() return true end
  return false
end

hs.ui_function("state", function()
  local p = hs.player()
  return {
    open = open,
    running = running,
    once = once,
    allowed = allowed(),
    character = loaded_for ~= nil,
    points = p and p.aa_points or 0,
    spent = p and p.aa_spent or 0,
    level = p and p.level or 0,
    status = status,
    next = next_pick,
    entries = plan.statuses(ix, S, p and p.aa_points or 0, p and p.level or 0),
    pending = pending and pending.name or nil,
    log = log,
    rev = rev,
    abilities_rev = abilities_rev,
  }
end)
hs.ui_function("settings", function() load_settings() return S end)
-- The abilities as hailstone.alt_abilities gives them, for the window's search (its own copy is read again only when
-- abilities_rev changes).
hs.ui_function("abilities", function() return abilities end)
hs.ui_function("set", function(path, value)
  local ok
  S, ok = settings_mod.set(S, path, value)
  if ok then changed() end
  return ok
end)
hs.ui_function("command", function(what, a, b, c)
  if what == "start" then set_running(true, true)
  elseif what == "pause" then set_running(false, true)
  elseif what == "toggle" then set_running(not running, true)
  elseif what == "now" then spend_now()
  elseif what == "close" then open = false
  elseif what == "show" then open = true
  elseif what == "add" then return add(a, b, c)
  elseif what == "remove" then
    if settings_mod.remove(S, a, b) then changed() end
  elseif what == "flip" then -- in the queue, or out of it (the AA window's toggle)
    if settings_mod.find(S, a, b) then settings_mod.remove(S, a, b) else settings_mod.add(S, a, b) end
    changed()
  elseif what == "move" then
    if settings_mod.move(S, a, b, c) then changed() end
  elseif what == "cap" then
    local e = settings_mod.find(S, a, b)
    if e then
      e.cap = math.max(0, math.floor(tonumber(c) or 0))
      changed()
    end
  elseif what == "enable" then
    local e = settings_mod.find(S, a, b)
    if e then
      e.on = c ~= false
      changed()
    end
  elseif what == "clear" then
    S.list = {}
    changed()
  end
  return true
end)
hs.menu("Auto AA", "/autoaaspend show")

-- ---------------------------------------------------------------- the command

mq.bind('/autoaaspend', function(a, ...)
  a = (a or ""):lower()
  local rest = table.concat({ ... }, " ")
  if a == "" or a == "show" then open = not open
  elseif a == "on" or a == "start" then set_running(true)
  elseif a == "off" or a == "pause" or a == "stop" then set_running(false)
  elseif a == "toggle" then set_running(not running)
  elseif a == "now" or a == "spend" then spend_now()
  elseif a == "add" or a == "remove" then
    load_settings()
    local found = ix.by_name[rest:lower()]
    if a == "add" then
      if not found then return say("no ability called '" .. rest .. "' for you.") end
      add(found.name, found.group)
      say("queued " .. found.name .. ".")
    else
      if settings_mod.remove(S, found and found.name or rest, found and found.group) then
        changed()
        say("removed " .. (found and found.name or rest) .. ".")
      else
        say("'" .. rest .. "' is not queued.")
      end
    end
  elseif a == "status" then
    say((running and status or "paused") .. (next_pick and (" (next: " .. next_pick.name .. ", " .. next_pick.cost .. " pt)") or ""))
  else
    say("/autoaaspend [show | on | off | toggle | now | add <name> | remove <name> | status]")
  end
end)

-- ---------------------------------------------------------------- the loop

while true do
  local ok, err = pcall(tick)
  if not ok then
    running, once = false, false
    status = "Stopped by an error"
    note("Stopped by an error: " .. tostring(err))
    say("stopped by an error: " .. tostring(err))
  end
  save_if_due()
  mq.delay(TICK_MS)
end
