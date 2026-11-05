-- Auto AA's settings: their defaults, and repair() to make any loaded table (an older file, a hand edit) safe to use.
--   list     the abilities to buy, in priority order: { name, group, cap (the highest rank to buy; 0 every rank),
--            on (false: kept, but skipped) }. An entry is found by its group, else by its name.
--   order    "skip": buy the first entry that can be bought now; "wait": buy only the first entry not done yet,
--            and wait for it (saving points for it)
--   reserve  points never spent
--   prereqs  buy an entry's missing prerequisites first, when they can be bought
--   combat   buy during a fight too (off: only with auto attack off and nothing on the extended target list)
--   resume   start again by itself after a login, if it was running when the character left
--   running  whether it was running (for resume)
--   fill     { on, tabs = { general, archetype, class, special }, max_cost (0 any) }: when the list has nothing to
--            buy, the cheapest abilities on those tabs
local M = {}

M.ORDERS = { "skip", "wait" }
M.TABS = { "general", "archetype", "class", "special" }
M.VERSION = 1

function M.defaults()
  return {
    version = M.VERSION,
    list = {},
    order = "skip",
    reserve = 0,
    prereqs = true,
    combat = false,
    resume = false,
    running = false,
    fill = { on = false, tabs = { general = true, archetype = false, class = false, special = false }, max_cost = 0 },
  }
end

local function int(v, lo, hi, def)
  v = tonumber(v)
  if not v or v ~= v then return def end
  v = math.floor(v)
  if lo and v < lo then v = lo end
  if hi and v > hi then v = hi end
  return v
end

local function bool(v, def)
  if v == nil then return def end
  return v == true
end

function M.entry(name, group, cap)
  return { name = tostring(name or ""), group = int(group, 0, nil, 0), cap = int(cap, 0, 999, 0), on = true }
end

function M.repair(t)
  local d = M.defaults()
  if type(t) ~= "table" then return d end
  local out = d
  out.order = (t.order == "wait") and "wait" or "skip"
  out.reserve = int(t.reserve, 0, 100000, 0)
  out.prereqs = bool(t.prereqs, true)
  out.combat = bool(t.combat, false)
  out.resume = bool(t.resume, false)
  out.running = bool(t.running, false)
  local seen = {}
  if type(t.list) == "table" then
    for _, e in ipairs(t.list) do
      if type(e) == "table" and type(e.name) == "string" and e.name ~= "" and not seen[e.name:lower()] then
        seen[e.name:lower()] = true
        local r = M.entry(e.name, e.group, e.cap)
        r.on = e.on ~= false
        out.list[#out.list + 1] = r
      end
    end
  end
  local f = type(t.fill) == "table" and t.fill or {}
  out.fill.on = bool(f.on, false)
  out.fill.max_cost = int(f.max_cost, 0, 1000, 0)
  if type(f.tabs) == "table" then
    for _, k in ipairs(M.TABS) do out.fill.tabs[k] = bool(f.tabs[k], d.fill.tabs[k]) end
  end
  return out
end

-- The entry for an ability (by group, else by name, ignoring case), and its place; nil when it is not listed.
function M.find(S, name, group)
  group = tonumber(group) or 0
  local lname = type(name) == "string" and name:lower() or nil
  for i, e in ipairs(S.list) do
    if (group ~= 0 and e.group == group) or (lname and e.name:lower() == lname) then return e, i end
  end
  return nil
end

-- Adds an ability at the end (or does nothing if it is listed); returns its entry.
function M.add(S, name, group, cap)
  local e = M.find(S, name, group)
  if e then
    if (tonumber(group) or 0) ~= 0 then e.group = math.floor(tonumber(group)) end
    return e
  end
  if type(name) ~= "string" or name == "" then return nil end
  e = M.entry(name, group, cap)
  S.list[#S.list + 1] = e
  return e
end

function M.remove(S, name, group)
  local _, i = M.find(S, name, group)
  if i then table.remove(S.list, i) end
  return i ~= nil
end

-- Moves an entry to place `to` (1-based, clamped).
function M.move(S, name, group, to)
  local e, i = M.find(S, name, group)
  if not e then return false end
  to = int(to, 1, #S.list, i)
  table.remove(S.list, i)
  table.insert(S.list, to, e)
  return true
end

-- Sets a value by a dotted path ("reserve", "fill.max_cost", "fill.tabs.class"), repaired; returns ok.
local PATHS = {
  order = true, reserve = true, prereqs = true, combat = true, resume = true,
  ["fill.on"] = true, ["fill.max_cost"] = true,
  ["fill.tabs.general"] = true, ["fill.tabs.archetype"] = true, ["fill.tabs.class"] = true, ["fill.tabs.special"] = true,
}
function M.set(S, path, value)
  if not PATHS[path] then return S, false end
  local t = S
  local keys = {}
  for k in path:gmatch("[^%.]+") do keys[#keys + 1] = k end
  for i = 1, #keys - 1 do t = t[keys[i]] end
  t[keys[#keys]] = value
  return M.repair(S), true
end

return M
