-- What Auto AA buys next. Pure: it reads the abilities as hailstone.alt_abilities() gives them, the settings
-- (lib/settings.lua) and the player's points and level, and never calls the game.
--
-- An ability (hailstone.alt_abilities): id, group, name, tab (1..4), category, rank (owned), max_rank, cost (the next
-- rank's; 0 at the maximum), level (the next rank's), maxed, can_train (the game's own check: points, level, class,
-- expansion, prerequisites), activated, prereqs = { { group, rank, met } }.
--
-- The game's check decides; what this adds is what to try first. The words for why an entry waits (level, points,
-- a prerequisite) are worked out from the same fields for the window only: when the game says no for a reason this
-- cannot see (an expansion, a server rule), the entry says "Can't be bought yet".
local M = {}

M.TAB_KEYS = { "general", "archetype", "class", "special" }

-- The abilities by group and by lower-case name.
function M.index(abilities)
  local by_group, by_name = {}, {}
  for _, a in ipairs(abilities or {}) do
    by_group[a.group] = a
    if a.name and a.name ~= "" then by_name[a.name:lower()] = a end
  end
  return { by_group = by_group, by_name = by_name, list = abilities or {} }
end

function M.lookup(ix, entry)
  if not entry then return nil end
  return (entry.group and entry.group ~= 0 and ix.by_group[entry.group]) or ix.by_name[(entry.name or ""):lower()]
end

-- An entry's state now: { state, text, ability, need (points short), prereq (the missing ability's name) }.
--   off      switched off             missing  not offered to this character (class, server)
--   maxed    every rank owned         capped   at the entry's highest rank
--   ready    can be bought now        points   short of points (reserve counted)
--   level    below the next rank's level
--   prereq   needs another ability    blocked  the game will not train it, for a reason not seen here
function M.status(ix, entry, points, level, reserve)
  local a = M.lookup(ix, entry)
  if entry.on == false then return { state = "off", text = "Off", ability = a } end
  if not a then return { state = "missing", text = "Not offered to you" } end
  if a.maxed then return { state = "maxed", text = "Maxed", ability = a } end
  if (entry.cap or 0) > 0 and a.rank >= entry.cap then
    return { state = "capped", text = "Done at rank " .. entry.cap, ability = a }
  end
  local avail = (points or 0) - (reserve or 0)
  if a.can_train and a.cost <= avail then return { state = "ready", text = "Ready", ability = a } end
  for _, q in ipairs(a.prereqs or {}) do
    if not q.met then
      local other = ix.by_group[q.group]
      local nm = other and other.name or ("ability " .. q.group)
      return { state = "prereq", text = "Needs " .. nm .. " " .. q.rank, ability = a, prereq = other, prereq_rank = q.rank }
    end
  end
  if (a.level or 0) > (level or 0) then
    return { state = "level", text = "Level " .. a.level, ability = a }
  end
  if a.cost > avail then
    local need = a.cost - avail
    return { state = "points", text = need .. " more pt", ability = a, need = need }
  end
  return { state = "blocked", text = "Can't be bought yet", ability = a }
end

local function buyable(a, avail)
  return a and not a.maxed and a.can_train and a.cost <= avail
end

-- The missing prerequisite that can be bought now for `a`, following prerequisites of prerequisites (3 deep).
local function prereq_pick(ix, a, avail, depth)
  if depth > 3 or not a then return nil end
  for _, q in ipairs(a.prereqs or {}) do
    if not q.met then
      local other = ix.by_group[q.group]
      if buyable(other, avail) then return other end
      local deeper = prereq_pick(ix, other, avail, depth + 1)
      if deeper then return deeper end
    end
  end
  return nil
end

-- The next purchase: { ability, why ("list" | "prereq" | "fill"), for_name (a prerequisite's entry) }, or nil and
-- why nothing is bought (a short sentence for the window).
-- skip: { [group] = true } abilities to leave out this time (one the server did not answer for).
function M.pick(abilities, S, points, level, skip)
  local ix = abilities.by_group and abilities or M.index(abilities)
  skip = skip or {}
  local avail = (points or 0) - (S.reserve or 0)
  local waiting = nil
  for _, e in ipairs(S.list) do
    local st = M.status(ix, e, points, level, S.reserve)
    local a = st.ability
    if st.state == "ready" and not skip[a.group] then
      return { ability = a, why = "list" }
    end
    if st.state == "prereq" and S.prereqs then
      local p = prereq_pick(ix, a, avail, 1)
      if p and not skip[p.group] then return { ability = p, why = "prereq", for_name = a.name } end
    end
    if S.order == "wait" and (st.state == "ready" or st.state == "points" or st.state == "level"
        or st.state == "prereq" or st.state == "blocked") then
      waiting = "Waiting for " .. (a and a.name or e.name) .. ": " .. st.text:lower()
      return nil, waiting
    end
  end
  if S.fill and S.fill.on then
    local best = nil
    for _, a in ipairs(ix.list) do
      local key = M.TAB_KEYS[a.tab]
      local entry = nil
      for _, e in ipairs(S.list) do
        if e.group == a.group or e.name:lower() == (a.name or ""):lower() then entry = e end
      end
      local allowed = key and S.fill.tabs[key]
      if entry then allowed = false end -- a listed ability keeps to its own entry (its cap, or off)
      if allowed and buyable(a, avail) and not skip[a.group]
          and (S.fill.max_cost == 0 or a.cost <= S.fill.max_cost) then
        if not best or a.cost < best.cost or (a.cost == best.cost and (a.tab < best.tab
            or (a.tab == best.tab and (a.name or "") < (best.name or "")))) then
          best = a
        end
      end
    end
    if best then return { ability = best, why = "fill" } end
  end
  if #S.list == 0 and not (S.fill and S.fill.on) then
    return nil, "Nothing queued: tick abilities in the AA window"
  end
  if avail <= 0 and (points or 0) > 0 then return nil, "Keeping " .. (S.reserve or 0) .. " points in reserve" end
  if (points or 0) <= 0 then return nil, "No points to spend" end
  return nil, "Nothing to buy now"
end

-- Every entry's state, in list order, for the window.
function M.statuses(abilities, S, points, level)
  local ix = abilities.by_group and abilities or M.index(abilities)
  local out = {}
  for i, e in ipairs(S.list) do
    local st = M.status(ix, e, points, level, S.reserve)
    local a = st.ability
    out[i] = {
      name = e.name, group = a and a.group or e.group, state = st.state, text = st.text,
      rank = a and a.rank or 0, max = a and a.max_rank or 0, cost = a and a.cost or 0, cap = e.cap or 0,
      on = e.on ~= false, tab = a and a.tab or 0, category = a and a.category or "",
    }
  end
  return out
end

return M
