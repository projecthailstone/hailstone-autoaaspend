local plan = require('lib.plan')
local settings = require('lib.settings')

-- An ability as hailstone.alt_abilities gives it.
local function A(t)
  return {
    id = t.id or (t.group * 10), group = t.group, name = t.name, tab = t.tab or 1, category = t.category or "",
    rank = t.rank or 0, max_rank = t.max or 3, cost = t.maxed and 0 or (t.cost or 1), level = t.level or 1,
    maxed = t.maxed or false, can_train = t.can_train ~= false and not t.maxed, activated = false,
    prereqs = t.prereqs or {},
  }
end

local function queue(...)
  local S = settings.defaults()
  for _, n in ipairs({ ... }) do
    if type(n) == "table" then settings.add(S, n[1], n[2], n[3]) else settings.add(S, n) end
  end
  return S
end

case("plan: the first entry that can be bought, skipping the rest", function()
  local list = {
    A { group = 1, name = "Expensive", cost = 9, can_train = false },
    A { group = 2, name = "Cheap", cost = 2 },
    A { group = 3, name = "Other", cost = 1 },
  }
  local S = queue("Expensive", "Cheap", "Other")
  local p = plan.pick(list, S, 5, 60)
  eq(p.ability.name, "Cheap")
  eq(p.why, "list")
  -- wait: nothing until the top one can be bought
  S.order = "wait"
  local none, why = plan.pick(list, S, 5, 60)
  eq(none, nil)
  check(why:find("Waiting for Expensive", 1, true) ~= nil, why)
  check(why:find("4 more pt", 1, true) ~= nil, why)
end)

case("plan: reserve, caps, maxed and switched-off entries", function()
  local list = {
    A { group = 1, name = "Maxed", maxed = true, rank = 3 },
    A { group = 2, name = "Capped", rank = 2, cost = 1 },
    A { group = 3, name = "Off", cost = 1 },
    A { group = 4, name = "Last", cost = 4 },
  }
  local S = queue("Maxed", { "Capped", 2, 2 }, "Off", "Last")
  S.list[3].on = false
  eq(plan.pick(list, S, 4, 60).ability.name, "Last")
  S.reserve = 1
  local none, why = plan.pick(list, S, 4, 60)
  eq(none, nil, "4 points less 1 in reserve cannot pay 4")
  eq(why, "Nothing to buy now")
  local st = plan.statuses(list, S, 4, 60)
  eq(st[1].state, "maxed")
  eq(st[2].state, "capped")
  eq(st[3].state, "off")
  eq(st[4].state, "points")
  eq(st[4].text, "1 more pt")
  -- the game's check is what decides: a rank it will not train is not bought even with the points
  list[4].can_train = false
  S.reserve = 0
  eq(plan.status(plan.index(list), S.list[4], 10, 60).state, "blocked")
end)

case("plan: an entry's missing prerequisite is bought first, when allowed", function()
  local list = {
    A { group = 1, name = "Big", cost = 3, can_train = false, prereqs = { { group = 2, rank = 2, met = false } } },
    A { group = 2, name = "Base", rank = 1, cost = 2 },
  }
  local S = queue("Big")
  local p = plan.pick(list, S, 5, 60)
  eq(p.ability.name, "Base")
  eq(p.why, "prereq")
  eq(p.for_name, "Big")
  eq(plan.statuses(list, S, 5, 60)[1].text, "Needs Base 2")
  S.prereqs = false
  eq(plan.pick(list, S, 5, 60), nil)
  -- a prerequisite's own prerequisite
  S.prereqs = true
  list[2].can_train = false
  list[2].prereqs = { { group = 3, rank = 1, met = false } }
  list[3] = A { group = 3, name = "Root", cost = 1 }
  eq(plan.pick(list, S, 5, 60).ability.name, "Root")
end)

case("plan: level and missing abilities", function()
  local list = { A { group = 1, name = "High", level = 70, can_train = false } }
  local S = queue("High", "Gone")
  local st = plan.statuses(list, S, 10, 60)
  eq(st[1].state, "level")
  eq(st[1].text, "Level 70")
  eq(st[2].state, "missing")
  -- an entry found by group after a rename on the server
  S = queue({ "Old Name", 1 })
  eq(plan.statuses(list, S, 10, 60)[1].state, "level")
end)

case("plan: fill buys the cheapest on the chosen tabs, never past a queued entry", function()
  local list = {
    A { group = 1, name = "Gen 3", tab = 1, cost = 3 },
    A { group = 2, name = "Gen 1", tab = 1, cost = 1 },
    A { group = 3, name = "Class 1", tab = 3, cost = 1 },
    A { group = 4, name = "Queued", tab = 1, cost = 1, rank = 2 },
  }
  local S = queue({ "Queued", 4, 2 }) -- capped at rank 2
  local none, why = plan.pick(list, S, 10, 60)
  eq(none, nil)
  eq(why, "Nothing to buy now")
  S.fill.on = true
  eq(plan.pick(list, S, 10, 60).ability.name, "Gen 1")
  eq(plan.pick(list, S, 10, 60).why, "fill")
  S.fill.tabs.general = false
  S.fill.tabs.class = true
  eq(plan.pick(list, S, 10, 60).ability.name, "Class 1")
  S.fill.tabs.general = true
  S.fill.max_cost = 2
  list[2].can_train = false
  list[3].can_train = false
  eq(plan.pick(list, S, 10, 60), nil, "only Gen 3 is left, and it costs more than 2")
end)

case("plan: skip leaves out an ability the server did not answer for", function()
  local list = { A { group = 1, name = "A", cost = 1 }, A { group = 2, name = "B", cost = 1 } }
  local S = queue("A", "B")
  eq(plan.pick(list, S, 5, 60, { [1] = true }).ability.name, "B")
end)

case("plan: what it says with nothing to do", function()
  local _, why = plan.pick({}, settings.defaults(), 5, 60)
  check(why:find("Nothing queued", 1, true) ~= nil, why)
  local S = queue("A")
  _, why = plan.pick({ A { group = 1, name = "A", cost = 3, can_train = false } }, S, 0, 60)
  eq(why, "No points to spend")
  S.reserve = 5
  _, why = plan.pick({ A { group = 1, name = "A", cost = 3, can_train = false } }, S, 4, 60)
  eq(why, "Keeping 5 points in reserve")
end)
