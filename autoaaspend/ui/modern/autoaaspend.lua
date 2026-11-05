-- Auto AA's windows for the Modern pack. The script (../../init.lua) keeps the queue and buys; these show its state and
-- change the queue through its functions (eq.Plugin("autoaaspend"): state, settings, abilities, set, command).
--   The Auto AA window (opens with the script; /autoaaspend, or the EQ menu's Plugins > Auto AA): the points, Start /
--           Pause and Spend now, what it buys next, and three pages: Queue (the abilities in order: drag to reorder,
--           a highest rank, a switch, a right-click menu; a search to add more), Settings and Log.
--   The AA window (the pack's lib/aa.lua, covered by a window of the same name): a toggle on each row puts the
--           ability in the queue or takes it out (a queued row has a gold outline and its place; the next purchase
--           pulses and says NEXT), the selected ability's panel gets Auto Buy (on, up to a rank, its place), and a
--           strip under the header shows whether Auto AA runs and what it buys next. An older client without
--           lib/aa.lua keeps its own AA window; the Auto AA window still works.
local hud = dofile("lib/hud.lua")
local T = hud.T
local C = T.color

local NAME = "autoaaspend"
local P                         -- the script's functions (nil while it is not running)
local st = {}                   -- its state, read each frame
local S = nil                   -- its settings, read again when they change (rev)
local rev = -1
local abilities, abilitiesRev = {}, -1
local page = "queue"
local search = ""
local drag = nil                -- { from = i, y = the press's y } while a queue row is dragged

local GOLD = C.aa or C.gold
local DOT = "  \xC2\xB7  "

-- ---------------------------------------------------------------- helpers

local function mix(a, b, t) return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t } end

local function cmd(...) if P then return P.command(...) end end
local function set(path, value) if P then P.set(path, value) end end

local STATE_COLOR = {
  ready = C.good, points = C.gold, level = C.hpLow or C.gold, prereq = C.accent, maxed = GOLD, capped = GOLD,
  missing = C.danger, blocked = C.danger, off = C.faint,
}
local STATE_TIP = {
  ready = "It buys this next time it can",
  points = "Waiting for more AA points",
  level = "The next rank needs a higher level",
  prereq = "Needs another ability first (Settings: buy prerequisites first)",
  maxed = "Every rank is owned",
  capped = "At the highest rank you set: raise it to buy more",
  missing = "The server offers this ability to none of your classes, or not at all",
  blocked = "The game will not train it now (an expansion, or a server rule)",
  off = "Switched off: kept in the queue, skipped",
}

-- A small rounded label; returns its width.
local function chip(x, y, s, text, color, solid)
  local tw, th = T.TextSize(text, T.font.tiny)
  local w = tw + 10 * s
  ui.DrawRectFilled(x, y, x + w, y + th + 4 * s, color[1], color[2], color[3], solid and 0.9 or 0.16, 4 * s)
  T.Text(x + 5 * s, y + 2 * s, text, solid and { 0.08, 0.08, 0.1, 1 } or color, T.font.tiny)
  return w
end

-- Rank pips (up to 10; more as a bar), centred on y; returns the width.
local function pips(x, y, s, cur, max, w)
  if max <= 0 then return 0 end
  if max > 10 then
    ui.DrawRectFilled(x, y - 2 * s, x + w, y + 2 * s, C.ink[1], C.ink[2], C.ink[3], 0.12, 2 * s)
    ui.DrawRectFilled(x, y - 2 * s, x + w * math.min(1, cur / max), y + 2 * s, GOLD[1], GOLD[2], GOLD[3], 1, 2 * s)
    return w
  end
  local gap = 3 * s
  local pw = math.min(9 * s, (w - gap * (max - 1)) / max)
  for i = 1, max do
    local px = x + (i - 1) * (pw + gap)
    local a = i <= cur and 1 or 0.12
    local c = i <= cur and GOLD or C.ink
    ui.DrawRectFilled(px, y - 2 * s, px + pw, y + 2 * s, c[1], c[2], c[3], a, 2 * s)
  end
  return max * (pw + gap) - gap
end

-- An on / off switch; returns clicked.
local function switch(id, x, y, s, on, tipText)
  local w, h = 30 * s, 16 * s
  local hit = T.Hit(id, x, y, x + w, y + h)
  local hovered = ui.IsItemHovered()
  local c = on and C.good or C.ink
  ui.DrawRectFilled(x, y, x + w, y + h, c[1], c[2], c[3], on and 0.75 or (hovered and 0.24 or 0.16), h / 2)
  local kx = on and (x + w - h / 2) or (x + h / 2)
  ui.DrawCircleFilled(kx, y + h / 2, h / 2 - 2.5 * s, 1, 1, 1, on and 1 or 0.7)
  if hovered and tipText then ui.SetTooltip(tipText) end
  return hit
end

-- A small round icon button (a minus, a plus or a cross); returns clicked.
local function iconButton(id, x, y, size, s, kind, tipText, enabled)
  local hit = T.Hit(id, x, y, x + size, y + size)
  local hovered, active = ui.IsItemHovered(), ui.IsItemActive()
  enabled = enabled ~= false
  local cx, cy, r = x + size / 2, y + size / 2, size / 2
  local base = kind == "x" and C.danger or C.ink
  ui.DrawCircleFilled(cx, cy, r, base[1], base[2], base[3], not enabled and 0.03
    or (active and 0.30 or (hovered and 0.20 or 0.08)))
  local ic = not enabled and C.faint or (hovered and (kind == "x" and C.danger or C.text) or C.muted)
  local a = r * 0.45
  if kind == "x" then
    ui.DrawLine(cx - a, cy - a, cx + a, cy + a, ic[1], ic[2], ic[3], 1, 1.4 * s)
    ui.DrawLine(cx - a, cy + a, cx + a, cy - a, ic[1], ic[2], ic[3], 1, 1.4 * s)
  else
    ui.DrawLine(cx - a, cy, cx + a, cy, ic[1], ic[2], ic[3], 1, 1.4 * s)
    if kind == "+" then ui.DrawLine(cx, cy - a, cx, cy + a, ic[1], ic[2], ic[3], 1, 1.4 * s) end
  end
  if hovered and tipText then ui.SetTooltip(tipText) end
  return hit and enabled
end

-- "Up to: All [-][+]": the highest rank an entry buys (0 every rank). Returns the new cap, or nil.
local function capStepper(id, x, y, s, cap, max)
  local size = 16 * s
  local label = cap == 0 and "All" or tostring(cap)
  local lw = 26 * s
  local out = nil
  if iconButton(id .. "-", x, y, size, s, "-", "Buy fewer ranks", cap ~= 1) then
    out = cap == 0 and math.max(1, max - 1) or math.max(1, cap - 1)
  end
  T.Text(x + size + lw / 2, y + 1 * s, label, cap == 0 and C.muted or GOLD, T.font.tiny, "center")
  if iconButton(id .. "+", x + size + lw, y, size, s, "+", "Buy more ranks", cap ~= 0) then
    out = (max > 0 and cap + 1 >= max) and 0 or cap + 1
  end
  return out, 2 * size + lw
end

-- The big Start / Pause button; returns clicked.
local function goButton(id, x0, y0, x1, y1, s, running)
  local hit = T.Hit(id, x0, y0, x1, y1)
  local hovered, active = ui.IsItemHovered(), ui.IsItemActive()
  local base = running and C.danger or GOLD
  local f = active and 0.62 or (hovered and 0.88 or 0.74)
  local top, bottom = mix(base, { 1, 1, 1 }, 0.12), mix(base, { 0, 0, 0 }, 0.28)
  local rad = 8 * s
  local bh = y1 - y0
  ui.DrawRectFilled(x0, y0 + 2 * s, x1, y1 + 2 * s, 0, 0, 0, 0.30, rad)
  ui.DrawRectFilled(x0, y0, x1, y1, bottom[1], bottom[2], bottom[3], f, rad)
  ui.DrawRectFilled(x0, y0, x1, y0 + bh * 0.55, top[1], top[2], top[3], f, rad)
  ui.DrawRect(x0, y0, x1, y1, base[1], base[2], base[3], 1, rad, 1.2 * s)
  local word = running and "Pause" or "Start"
  local tw, th = T.TextSize(word, T.font.normal)
  local iw = 10 * s
  local gx = x0 + (x1 - x0 - tw - iw - 6 * s) / 2
  local cy = y0 + bh / 2
  local ic = C.barText or { 1, 1, 1, 1 }
  if running then
    ui.DrawRectFilled(gx, cy - 6 * s, gx + 3.5 * s, cy + 6 * s, ic[1], ic[2], ic[3], 1, 1 * s)
    ui.DrawRectFilled(gx + 6.5 * s, cy - 6 * s, gx + 10 * s, cy + 6 * s, ic[1], ic[2], ic[3], 1, 1 * s)
  else
    ui.DrawTriangleFilled(gx, cy - 6.5 * s, gx, cy + 6.5 * s, gx + iw, cy, ic[1], ic[2], ic[3], 1)
  end
  T.Text(gx + iw + 6 * s, cy - th / 2, word, ic, T.font.normal, nil, 1, C.barShadow)
  if hovered then
    ui.SetTooltip(running and "Pause: stop buying (/autoaaspend off)"
      or "Start: buy the queue as points come in (/autoaaspend on)")
  end
  return hit
end

-- A row of pills, one chosen: list = { {id, label}, ... }. Returns the id clicked, if any.
local function segmented(id, x0, y0, x1, y1, s, list, current)
  local n = #list
  local gap = 4 * s
  local w = (x1 - x0 - gap * (n - 1)) / n
  ui.DrawRectFilled(x0 - 3 * s, y0 - 3 * s, x1 + 3 * s, y1 + 3 * s, C.inset[1], C.inset[2], C.inset[3],
    C.inset[4] or 1, 8 * s)
  local chosen = nil
  for i, e in ipairs(list) do
    local bx = x0 + (i - 1) * (w + gap)
    local hit = T.Hit(id .. e[1], bx, y0, bx + w, y1)
    local hovered = ui.IsItemHovered()
    local on = e[1] == current
    if on then
      ui.DrawRectFilled(bx, y0, bx + w, y1, GOLD[1], GOLD[2], GOLD[3], 0.22, 6 * s)
      ui.DrawRect(bx, y0, bx + w, y1, GOLD[1], GOLD[2], GOLD[3], 0.6, 6 * s, 1)
    elseif hovered then
      ui.DrawRectFilled(bx, y0, bx + w, y1, C.ink[1], C.ink[2], C.ink[3], 0.06, 6 * s)
    end
    local _, th = T.TextSize("Ag", T.font.small)
    T.Text(bx + w / 2, (y0 + y1 - th) / 2, e[2], on and C.text or C.muted, T.font.small, "center")
    if hit then chosen = e[1] end
  end
  return chosen
end

local function section(text, s, first)
  if not first then ui.Dummy(0, 8 * s) end
  local hc = C.heading or GOLD
  ui.TextColored(hc[1], hc[2], hc[3], 1, text)
  local x, y = ui.GetCursorScreenPos()
  local w = ui.GetContentRegionAvail()
  ui.DrawLine(x, y, x + w, y, C.ink[1], C.ink[2], C.ink[3], 0.10, 1)
  ui.Dummy(0, 4 * s)
end

local function note(text)
  ui.PushTextWrapPos(0)
  ui.TextColored(C.faint[1], C.faint[2], C.faint[3], 1, text)
  ui.PopTextWrapPos()
end

local function tip(text) if ui.IsItemHovered() then ui.SetTooltip(text) end end

local function check(text, value)
  local v, changed = ui.Checkbox(text, value)
  return changed and v or nil
end

local function number(id, value, width, lo, hi)
  ui.SetNextItemWidth(width)
  local text, changed = ui.InputText(id, tostring(value), 8, ui.InputTextFlags.CharsDecimal)
  if not changed then return nil end
  local v = tonumber(text)
  if not v then return nil end
  v = math.floor(v)
  if lo and v < lo then v = lo end
  if hi and v > hi then v = hi end
  return v
end

-- The queue's entry for an ability (by group, else name), and its place.
local function queued(name, group)
  if not S then return nil end
  local lname = (name or ""):lower()
  for i, e in ipairs(S.list) do
    if (group and group ~= 0 and e.group == group) or e.name:lower() == lname then return e, i end
  end
  return nil
end

local function entryState(i) return (st.entries or {})[i] end

local function refreshAbilities()
  if P and st.abilities_rev ~= abilitiesRev then
    abilities = P.abilities() or {}
    abilitiesRev = st.abilities_rev
  end
end

local function abilityNamed(name)
  local lname = (name or ""):lower()
  for _, a in ipairs(abilities) do
    if (a.name or ""):lower() == lname then return a end
  end
  return nil
end

-- ---------------------------------------------------------------- the Auto AA window

local function header(x, y, w, s)
  local pad = 12 * s
  local h = 84 * s
  ui.DrawRectFilled(x, y, x + w, y + h, C.inset[1], C.inset[2], C.inset[3], C.inset[4] or 1, 10 * s)
  -- a thin gold line along the top while it runs
  if st.running then
    local a = 0.55 + 0.35 * math.sin(ui.GetTime() * 3)
    ui.DrawRectFilled(x + 10 * s, y, x + w - 10 * s, y + 2 * s, GOLD[1], GOLD[2], GOLD[3], a, 1 * s)
  end
  -- the points
  T.Text(x + pad, y + 10 * s, "UNSPENT", C.muted, T.font.tiny)
  local pts = tostring(st.points or 0)
  local _, ph = T.TextSize(pts, T.font.large)
  T.Text(x + pad, y + 22 * s, pts, GOLD, T.font.large)
  local sub = (st.spent or 0) .. " spent"
  if S and S.reserve > 0 then sub = sub .. DOT .. "keeping " .. S.reserve end
  T.Text(x + pad, y + 26 * s + ph, sub, C.faint, T.font.tiny)
  -- Start / Pause, Spend now
  local bw, bh = 104 * s, 40 * s
  local bx = x + w - pad - bw
  local by = y + 12 * s
  if goButton("##aasgo", bx, by, bx + bw, by + bh, s, st.running and not st.once) then
    cmd(st.running and "pause" or "start")
  end
  local nowLabel = st.once and "Spending..." or "Spend now"
  if T.Button("##aasnow", bx, by + bh + 6 * s, bx + bw, by + bh + 24 * s, s, nowLabel,
      { enabled = not st.running and st.allowed ~= false,
        tooltip = "Buy what can be bought now, then stop (/autoaaspend now)" }) then
    cmd("now")
  end
  -- what it does now, and the next purchase
  local mx = x + pad + 96 * s
  local mw = bx - 12 * s - mx
  local running = st.running
  local light = st.allowed == false and C.danger or (running and C.good or C.faint)
  local ly = y + 16 * s
  if running then
    ui.DrawCircleFilled(mx + 4 * s, ly + 6 * s, 7 * s, light[1], light[2], light[3], 0.25 + 0.2 * math.sin(ui.GetTime() * 4))
  end
  ui.DrawCircleFilled(mx + 4 * s, ly + 6 * s, 4 * s, light[1], light[2], light[3], 1)
  T.Text(mx + 14 * s, ly, T.Fit(st.status or "", mw - 14 * s, T.font.small), running and C.text or C.muted, T.font.small)
  local n = st.next
  if n then
    local ny = ly + 26 * s
    local cw = chip(mx, ny, s, "NEXT", GOLD, true)
    local why = n.why == "prereq" and ("for " .. (n.for_name or "")) or (n.why == "fill" and "filling" or nil)
    local line = n.name
    T.Text(mx + cw + 6 * s, ny - 1 * s, T.Fit(line, mw - cw - 6 * s, T.font.small), C.text, T.font.small)
    local detail = string.format("rank %d of %d%s%d pt", n.rank or 0, n.max or 0, DOT, n.cost or 0)
    if why then detail = detail .. DOT .. why end
    T.Text(mx, ny + 18 * s, T.Fit(detail, mw, T.font.tiny), C.faint, T.font.tiny)
  end
  return h
end

local function queuePage(x, y, w, h, s)
  local list = S.list
  local footH = 34 * s
  local listH = h - footH - 6 * s
  ui.SetCursorScreenPos(x, y)
  ui.BeginChild("##aasqueue", w, listH, false)
  local cw = ui.GetContentRegionAvail()
  local ox, oy = ui.GetCursorScreenPos()
  if #list == 0 then
    local _, th = T.TextSize("Ag", T.font.normal)
    local cy = oy + listH * 0.30
    T.Text(ox + cw / 2, cy, "Your queue is empty", C.muted, T.font.normal, "center")
    T.Text(ox + cw / 2, cy + th + 6 * s, "Tick abilities in the AA window, or search below.", C.faint, T.font.small,
      "center")
    local bw = 150 * s
    if T.Button("##aasopenaa", ox + (cw - bw) / 2, cy + th + 30 * s, ox + (cw + bw) / 2, cy + th + 54 * s, s,
        "Open the AA window", { primary = true }) then
      eq.ShowWindow("AAWindow", true)
    end
    ui.EndChild()
  else
    local rowH = 50 * s
    local gap = 4 * s
    local mx, my = ui.GetMousePos()
    local dropAt = nil
    if drag then
      dropAt = math.max(1, math.min(#list, math.floor((my - oy) / (rowH + gap)) + 1))
    end
    for i, e in ipairs(list) do
      local es = entryState(i) or {}
      local y0 = oy + (i - 1) * (rowH + gap)
      local x0, x1, y1 = ox, ox + cw, y0 + rowH
      local on = e.on ~= false
      local sc = STATE_COLOR[es.state] or C.muted
      local isNext = st.next and st.next.name == e.name
      -- the card
      local lifted = drag and drag.from == i
      ui.DrawRectFilled(x0, y0, x1, y1, C.ink[1], C.ink[2], C.ink[3], lifted and 0.10 or 0.04, 8 * s)
      if isNext then
        local a = 0.45 + 0.35 * math.sin(ui.GetTime() * 4)
        ui.DrawRect(x0, y0, x1, y1, GOLD[1], GOLD[2], GOLD[3], a, 8 * s, 1.5 * s)
      end
      -- the press area for dragging and the menu (the controls on the right take their own clicks)
      local ctrlW = 150 * s
      T.Hit("##aasrow" .. i, x0, y0, x1 - ctrlW, y1)
      local hovered = ui.IsItemHovered()
      if ui.IsItemActive() and not drag and ui.IsMouseDragging(ui.Mouse.Left) then drag = { from = i } end
      if hovered and not drag then
        ui.DrawRectFilled(x0, y0, x1, y1, C.ink[1], C.ink[2], C.ink[3], 0.04, 8 * s)
        ui.SetTooltip((STATE_TIP[es.state] or "") .. "\nDrag to change the order; right-click for more")
      end
      if ui.BeginPopupContextItem("##aasmenu" .. i) then
        if ui.MenuItem("Move to the top", false, i > 1) then cmd("move", e.name, e.group, 1) end
        if ui.MenuItem("Move to the bottom", false, i < #list) then cmd("move", e.name, e.group, #list) end
        if ui.MenuItem(on and "Switch off" or "Switch on") then cmd("enable", e.name, e.group, not on) end
        ui.Separator()
        if ui.MenuItem("Remove from the queue") then cmd("remove", e.name, e.group) end
        ui.EndPopup()
      end
      -- the place: a numbered badge (grip dots beside it)
      local bx, by = x0 + 20 * s, y0 + rowH / 2
      local bc = on and (es.state == "ready" and C.good or GOLD) or C.faint
      ui.DrawCircleFilled(bx, by, 11 * s, bc[1], bc[2], bc[3], on and 0.20 or 0.08)
      ui.DrawCircle(bx, by, 11 * s, bc[1], bc[2], bc[3], on and 0.8 or 0.3, 1.2 * s)
      local _, nh = T.TextSize("0", T.font.small)
      T.Text(bx, by - nh / 2, tostring(i), on and C.text or C.faint, T.font.small, "center")
      -- the name, then its state and category
      local tx = x0 + 40 * s
      local tw = x1 - ctrlW - tx - 6 * s
      T.Text(tx, y0 + 8 * s, T.Fit(e.name, tw, T.font.small), on and C.text or C.faint, T.font.small)
      local sw = chip(tx, y0 + 28 * s, s, es.text or "", sc)
      if (es.category or "") ~= "" then
        T.Text(tx + sw + 6 * s, y0 + 29 * s, T.Fit(es.category, tw - sw - 6 * s, T.font.tiny), C.faint, T.font.tiny)
      end
      -- the controls: ranks, up to, switch, remove
      local rx = x1 - ctrlW
      T.Text(rx, y0 + 8 * s, string.format("%d / %d", es.rank or 0, es.max or 0),
        (es.state == "maxed" or es.state == "capped") and GOLD or C.muted, T.font.tiny)
      pips(rx, y0 + 26 * s, s, es.rank or 0, es.max or 0, 56 * s)
      T.Text(rx, y0 + 33 * s, "up to", C.faint, T.font.tiny)
      local capNew = capStepper("##aascap" .. i, rx + 28 * s, y0 + 31 * s, s, e.cap or 0, es.max or 0)
      if capNew then cmd("cap", e.name, e.group, capNew) end
      if switch("##aason" .. i, x1 - 56 * s, y0 + 9 * s, s, on, on and "On: bought when it can be" or "Off: skipped") then
        cmd("enable", e.name, e.group, not on)
      end
      if iconButton("##aasrm" .. i, x1 - 22 * s, y0 + 9 * s, 16 * s, s, "x", "Remove from the queue") then
        cmd("remove", e.name, e.group)
      end
    end
    -- the drop line while dragging
    if drag then
      local to = dropAt
      local ly = oy + (to - 1) * (rowH + gap) + (to > drag.from and (rowH + gap / 2) or (-gap / 2))
      ui.DrawRectFilled(ox, ly - 1.5 * s, ox + cw, ly + 1.5 * s, GOLD[1], GOLD[2], GOLD[3], 0.9, 1.5 * s)
      local e = list[drag.from]
      T.Text(mx + 12 * s, my - 8 * s, e and e.name or "", GOLD, T.font.small, nil, 0.9, C.barShadow)
      if not ui.IsMouseDown(ui.Mouse.Left) then
        if e and to ~= drag.from then cmd("move", e.name, e.group, to) end
        drag = nil
      end
    end
    ui.SetCursorScreenPos(ox, oy)
    ui.Dummy(cw, #list * (rowH + gap))
    ui.EndChild()
  end
  -- the foot: a search to add abilities, and the AA window
  local fy = y + h - footH
  ui.SetCursorScreenPos(x, fy + 4 * s)
  local bw = 96 * s
  ui.SetNextItemWidth(w - bw - 8 * s)
  search = ui.InputTextWithHint("##aassearch", "Add an ability...", search, 64)
  local sx, sy = x, fy + 4 * s
  local sw = w - bw - 8 * s
  if T.Button("##aasaa", x + w - bw, fy + 4 * s, x + w, fy + 28 * s, s, "AA window",
      { tooltip = "Open the AA window: each row has a toggle to queue it" }) then
    eq.ShowWindow("AAWindow", true)
  end
  local needle = search:lower()
  if #needle >= 2 then
    refreshAbilities()
    local hits = {}
    for _, a in ipairs(abilities) do
      if (a.name or ""):lower():find(needle, 1, true) and not queued(a.name, a.group) then
        hits[#hits + 1] = a
        if #hits >= 8 then break end
      end
    end
    if #hits > 0 then
      local rh = 24 * s
      local ph = #hits * rh + 8 * s
      local py = sy - ph - 4 * s
      ui.DrawRectFilled(sx, py, sx + sw, sy - 4 * s, C.popup and C.popup[1] or 0.1, C.popup and C.popup[2] or 0.1,
        C.popup and C.popup[3] or 0.12, 0.98, 8 * s)
      ui.DrawRect(sx, py, sx + sw, sy - 4 * s, GOLD[1], GOLD[2], GOLD[3], 0.35, 8 * s, 1)
      for k, a in ipairs(hits) do
        local ry = py + 4 * s + (k - 1) * rh
        local hit = T.Hit("##aashit" .. k, sx + 4 * s, ry, sx + sw - 4 * s, ry + rh)
        if ui.IsItemHovered() then
          ui.DrawRectFilled(sx + 4 * s, ry, sx + sw - 4 * s, ry + rh, GOLD[1], GOLD[2], GOLD[3], 0.16, 5 * s)
        end
        T.Text(sx + 12 * s, ry + 4 * s, T.Fit(a.name, sw - 110 * s, T.font.small), C.text, T.font.small)
        local info = a.maxed and "maxed" or string.format("%d/%d%s%d pt", a.rank, a.max_rank, DOT, a.cost)
        T.Text(sx + sw - 12 * s, ry + 5 * s, info, C.faint, T.font.tiny, "right")
        if hit then
          cmd("add", a.name, a.group)
          search = ""
        end
      end
    end
  end
end

local ORDERS = { { "skip", "Skip ahead" }, { "wait", "Wait for the top" } }
local TABS = { { "general", "General" }, { "archetype", "Archetype" }, { "class", "Class" }, { "special", "Special" } }

local function settingsPage(x, y, w, h, s)
  ui.SetCursorScreenPos(x, y)
  ui.BeginChild("##aassettings", w, h, false)
  section("Order", s, true)
  local cx, cy = ui.GetCursorScreenPos()
  local cw = ui.GetContentRegionAvail()
  local o = segmented("##aasorder", cx + 2 * s, cy + 2 * s, cx + cw - 2 * s, cy + 26 * s, s, ORDERS, S.order)
  if o then set("order", o) end
  ui.SetCursorScreenPos(cx, cy + 34 * s)
  note(S.order == "wait"
    and "Saves points for the first ability not done yet, and buys nothing else until it is bought."
    or "Buys the first ability in the queue that can be bought now, skipping those that must wait.")
  section("Points", s)
  -- (label, then the field on the same line)
  ui.Text("Keep in reserve")
  ui.SameLine(170 * s)
  local r = number("##aasreserve", S.reserve, 70 * s, 0, 100000)
  if r then set("reserve", r) end
  tip("Points Auto AA never spends, for a purchase of your own")
  section("When", s)
  local v = check("Buy missing prerequisites first##aaspre", S.prereqs)
  if v ~= nil then set("prereqs", v) end
  tip("An ability that needs another one first buys that one, when it can be bought")
  v = check("Buy during fights too##aascombat", S.combat)
  if v ~= nil then set("combat", v) end
  tip("Off: only while auto attack is off and nothing is on your extended target list")
  v = check("Start again after logging in, if it was running##aasresume", S.resume)
  if v ~= nil then set("resume", v) end
  section("When the queue has nothing to buy", s)
  v = check("Buy the cheapest abilities on these tabs##aasfill", S.fill.on)
  if v ~= nil then set("fill.on", v) end
  if S.fill.on then
    for i, t in ipairs(TABS) do
      if i > 1 then ui.SameLine() end
      local tv = check(t[2] .. "##aastab" .. t[1], S.fill.tabs[t[1]])
      if tv ~= nil then set("fill.tabs." .. t[1], tv) end
    end
    -- (label, then the field on the same line)
    ui.Text("Only ranks costing at most")
    ui.SameLine(190 * s)
    local m = number("##aasmaxcost", S.fill.max_cost, 60 * s, 0, 1000)
    if m then set("fill.max_cost", m) end
    ui.SameLine()
    ui.TextColored(C.faint[1], C.faint[2], C.faint[3], 1, "points (0: any)")
    note("Abilities in the queue keep to their own entry (its highest rank, or off).")
  end
  section("Queue", s)
  local qx, qy = ui.GetCursorScreenPos()
  if T.Button("##aasclear", qx, qy, qx + 130 * s, qy + 24 * s, s, "Clear the queue", { enabled = #S.list > 0 }) then
    ui.OpenPopup("##aasclearask")
  end
  ui.Dummy(0, 28 * s)
  if ui.BeginPopup("##aasclearask") then
    ui.Text("Remove every ability from the queue?")
    if ui.Button("Clear") then cmd("clear") ui.CloseCurrentPopup() end
    ui.SameLine()
    if ui.Button("Keep") then ui.CloseCurrentPopup() end
    ui.EndPopup()
  end
  ui.EndChild()
end

local function logPage(x, y, w, h, s)
  ui.SetCursorScreenPos(x, y)
  ui.BeginChild("##aaslog", w, h, false)
  local log = st.log or {}
  if #log == 0 then
    note("Nothing yet. Purchases and pauses show here, newest first.")
  else
    for i = #log, 1, -1 do
      local e = log[i]
      local c = i == #log and C.text or C.muted
      ui.TextColored(C.faint[1], C.faint[2], C.faint[3], 1, os.date("%H:%M", e.at or 0))
      ui.SameLine()
      ui.PushTextWrapPos(0)
      ui.TextColored(c[1], c[2], c[3], 1, e.text or "")
      ui.PopTextWrapPos()
    end
  end
  ui.EndChild()
end

local function body(x, y, w, h, s)
  local hh = header(x, y, w, s)
  local ty = y + hh + 10 * s
  local count = #S.list
  local PAGES = { { "queue", count > 0 and ("Queue  " .. count) or "Queue" }, { "settings", "Settings" },
    { "log", "Log" } }
  local p = segmented("##aaspage", x + 3 * s, ty, x + w - 3 * s, ty + 24 * s, s, PAGES, page)
  if p then page = p end
  local cy = ty + 34 * s
  local ch = y + h - cy
  if page == "queue" then queuePage(x, cy, w, ch, s)
  elseif page == "settings" then settingsPage(x, cy, w, ch, s)
  else logPage(x, cy, w, ch, s) end
  ui.SetCursorScreenPos(x, y)
  ui.Dummy(w, h)
end

local function readState()
  P = eq.Plugin(NAME)
  if not P or not eq.InGame() then return false end
  st = P.state() or {}
  if st.rev ~= rev or not S then
    S = P.settings()
    rev = st.rev
  end
  return S ~= nil
end

ui.window("Auto AA", function()
  if not readState() or not st.open then return end
  hud.Window(nil, "Auto AA", {
    shown = function() return st.open end,
    size = function() return 440, 560 end,
    resizable = { 380, 420 },
    place = function(W, H, w, h) return W - w - 40, H * 0.22 end,
    onClose = function() cmd("close") end,
  }, body)
end)

-- ---------------------------------------------------------------- the AA window
-- The pack's AA window (lib/aa.lua) with Auto AA's parts. An older client without lib/aa.lua keeps its own window.
local aaOk, aa = pcall(dofile, "lib/aa.lua")
if not aaOk or type(aa) ~= "table" or not aa.window then aa = nil end

local TOGGLE_W = 40

-- The round toggle on a row: empty ring (a plus while hovered) when not queued, a gold disc with the place when it is.
local function rowToggle(id, cx, cy, r, s, place, maxed)
  local hit = T.Hit(id, cx - r, cy - r, cx + r, cy + r)
  local hovered, active = ui.IsItemHovered(), ui.IsItemActive()
  if place then
    ui.DrawCircleFilled(cx, cy, r, GOLD[1], GOLD[2], GOLD[3], active and 0.7 or (hovered and 1 or 0.88))
    local _, th = T.TextSize("0", T.font.tiny)
    T.Text(cx, cy - th / 2, tostring(place), { 0.08, 0.08, 0.1, 1 }, T.font.tiny, "center")
    if hovered then ui.SetTooltip("Queued: number " .. place .. " in Auto AA's order. Click to take it out.") end
  else
    local c = hovered and GOLD or C.ink
    ui.DrawCircleFilled(cx, cy, r, c[1], c[2], c[3], active and 0.25 or (hovered and 0.16 or 0.05))
    ui.DrawCircle(cx, cy, r - 0.5 * s, c[1], c[2], c[3], hovered and 0.9 or 0.25, 1.3 * s)
    if hovered then
      local a = r * 0.45
      ui.DrawLine(cx - a, cy, cx + a, cy, GOLD[1], GOLD[2], GOLD[3], 1, 1.5 * s)
      ui.DrawLine(cx, cy - a, cx, cy + a, GOLD[1], GOLD[2], GOLD[3], 1, 1.5 * s)
      ui.SetTooltip(maxed and "Maxed: nothing left to buy" or "Queue it: Auto AA buys its ranks for you")
    end
  end
  return hit
end

local AA_ROW = {
  width = TOGGLE_W,
  style = function(r)
    local e, i = queued(r.name)
    if not e then return nil end
    if st.next and st.next.name == e.name then
      local a = 0.5 + 0.4 * math.sin(ui.GetTime() * 4)
      return { ring = { GOLD[1], GOLD[2], GOLD[3], a }, tag = { "NEXT", GOLD } }
    end
    local es = entryState(i)
    if e.on == false then return { ring = { C.faint[1], C.faint[2], C.faint[3], 0.4 }, tag = { "OFF", C.faint } } end
    return { ring = { GOLD[1], GOLD[2], GOLD[3], 0.35 }, tag = es and es.state == "capped" and { "DONE", GOLD } or nil }
  end,
  draw = function(r, x0, y0, x1, y1, s)
    local e, i = queued(r.name)
    local size = math.min(20 * s, y1 - y0 - 10 * s)
    if rowToggle("##aastg" .. r.page .. r.name, (x0 + x1) / 2, (y0 + y1) / 2, size / 2, s, e and i or nil, r.maxed) then
      local a = abilityNamed(r.name)
      cmd("flip", r.name, a and a.group or 0)
    end
  end,
}

-- In the selected ability's panel: Auto Buy, on and up to a rank, and its place.
local function aaDetails(sel, x, y, w, s)
  if not sel or (sel.name or "") == "" then return 0 end
  refreshAbilities()
  local e, i = queued(sel.name)
  local h = e and 66 * s or 44 * s
  local yy = y + 4 * s
  ui.DrawRectFilled(x, yy, x + w, yy + h - 8 * s, GOLD[1], GOLD[2], GOLD[3], e and 0.08 or 0.035, 8 * s)
  if e then ui.DrawRect(x, yy, x + w, yy + h - 8 * s, GOLD[1], GOLD[2], GOLD[3], 0.35, 8 * s, 1) end
  local pad = 10 * s
  T.Text(x + pad, yy + 8 * s, "AUTO BUY", e and GOLD or C.muted, T.font.tiny)
  local sub = e and ("number " .. i .. " of " .. #S.list .. " in the queue") or "not queued"
  T.Text(x + pad, yy + 20 * s, sub, C.faint, T.font.tiny)
  if switch("##aasdon", x + w - pad - 30 * s, yy + 10 * s, s, e ~= nil,
      e and "Take it out of Auto AA's queue" or "Put it in Auto AA's queue") then
    local a = abilityNamed(sel.name)
    cmd("flip", sel.name, a and a.group or 0)
  end
  if e then
    local ry = yy + 38 * s
    T.Text(x + pad, ry + 1 * s, "Up to rank", C.muted, T.font.tiny)
    local capNew, cw = capStepper("##aasdcap", x + pad + 60 * s, ry, s, e.cap or 0, sel.max or 0)
    if capNew then cmd("cap", e.name, e.group, capNew) end
    local bx = x + pad + 60 * s + cw + 10 * s
    if i > 1 and T.Button("##aasdtop", bx, ry - 2 * s, math.min(x + w - pad, bx + 80 * s), ry + 16 * s, s,
        "Move to top", { tooltip = "Buy this before the rest of the queue" }) then
      cmd("move", e.name, e.group, 1)
    end
  end
  return h
end

-- The strip under the header: whether Auto AA runs and what it buys next; Start / Pause and the queue.
local function aaBanner(x, y, w, s)
  local h = 30 * s
  ui.DrawRectFilled(x, y, x + w, y + h, GOLD[1], GOLD[2], GOLD[3], 0.07, 7 * s)
  local running = st.running
  local light = st.allowed == false and C.danger or (running and C.good or C.faint)
  local cy = y + h / 2
  if running then
    ui.DrawCircleFilled(x + 14 * s, cy, 7 * s, light[1], light[2], light[3], 0.25 + 0.2 * math.sin(ui.GetTime() * 4))
  end
  ui.DrawCircleFilled(x + 14 * s, cy, 4 * s, light[1], light[2], light[3], 1)
  local _, th = T.TextSize("Ag", T.font.small)
  T.Text(x + 26 * s, cy - th / 2, "Auto AA", GOLD, T.font.small)
  local lw = T.TextSize("Auto AA", T.font.small)
  local text = st.next and running and ("next: " .. st.next.name .. " (" .. st.next.cost .. " pt)") or (st.status or "")
  local bw = 64 * s
  local room = w - (26 * s + lw + 10 * s) - 2 * bw - 22 * s
  T.Text(x + 26 * s + lw + 10 * s, cy - th / 2, T.Fit(text, room, T.font.small), C.muted, T.font.small)
  local bx = x + w - 2 * bw - 14 * s
  if T.Button("##aasbgo", bx, y + 5 * s, bx + bw, y + h - 5 * s, s, running and "Pause" or "Start",
      { primary = not running, enabled = st.allowed ~= false }) then
    cmd(running and "pause" or "start")
  end
  if T.Button("##aasbq", bx + bw + 6 * s, y + 5 * s, bx + 2 * bw + 6 * s, y + h - 5 * s, s,
      "Queue  " .. #S.list, { tooltip = "Open the Auto AA window" }) then
    cmd("show")
  end
  return h
end

local AA_OPTS = { row = AA_ROW, details = aaDetails, banner = aaBanner }

ui.window("Alternate Advancement", function()
  if not aa or not readState() then return ui.base_window() end
  refreshAbilities()
  aa.window(AA_OPTS)
end)
