-- Linux-style mouse clipboard for macOS, and Hyprland-style window resize.
--   1. Select text with the mouse  -> it is copied.
--   2. Right-click inside the text field you are typing in -> paste.
--      Hold Option while right-clicking to get the normal menu.
-- Ghostty does both natively (see ~/.config/ghostty/config), so it is skipped here.

hs.autoLaunch(true)
require("hs.ipc") -- lets the `hs` command line tool talk to Hammerspoon

local skip = { ["com.mitchellh.ghostty"] = true, ["com.apple.finder"] = true }
local textRoles = { AXTextField = true, AXTextArea = true, AXComboBox = true, AXSearchField = true }

local function frontSkipped()
  local app = hs.application.frontmostApplication()
  return app and skip[app:bundleID()]
end

local function focusedElement()
  return hs.axuielement.systemWideElement():attributeValue("AXFocusedUIElement")
end

-- 1. Copy on select -----------------------------------------------------------
local downAt, copyTimer -- keep the timer referenced, or Lua may garbage-collect it before it fires
copyOnSelect = hs.eventtap.new({ hs.eventtap.event.types.leftMouseDown, hs.eventtap.event.types.leftMouseUp }, function(e)
  local t = e:getType()
  if t == hs.eventtap.event.types.leftMouseDown then downAt = e:location(); return false end

  -- Only plain drags or double/triple clicks; any modifier (e.g. yabai's ctrl-drag) is ignored.
  local mods = e:getFlags()
  if mods.cmd or mods.ctrl or mods.alt or mods.shift or frontSkipped() or not downAt then return false end
  local up = e:location()
  local dragged = math.abs(up.x - downAt.x) + math.abs(up.y - downAt.y) > 6
  local multi = e:getProperty(hs.eventtap.event.properties.mouseEventClickState) >= 2
  if not (dragged or multi) then return false end

  -- Wait for the app to finish updating its selection, then read it.
  copyTimer = hs.timer.doAfter(0.08, function()
    local el = focusedElement()
    local text = el and el:attributeValue("AXSelectedText")
    if text and text ~= "" then
      hs.pasteboard.setContents(text)
    elseif dragged and text == nil then
      -- App doesn't expose its selection to macOS: fall back to a real ⌘C.
      hs.eventtap.keyStroke({ "cmd" }, "c", 0)
    end
  end)
  return false
end):start()

-- 2. Right-click paste ----------------------------------------------------------
rightClickPaste = hs.eventtap.new({ hs.eventtap.event.types.rightMouseDown }, function(e)
  if e:getFlags().alt or frontSkipped() then return false end
  local el = focusedElement()
  if not el or not textRoles[el:attributeValue("AXRole")] then return false end
  -- Paste only if the click lands on the focused field itself.
  local f, p = el:attributeValue("AXFrame"), e:location()
  if not f or p.x < f.x or p.x > f.x + f.w or p.y < f.y or p.y > f.y + f.h then return false end
  hs.eventtap.keyStroke({ "cmd" }, "v", 0)
  return true -- swallow the click so no context menu opens
end):start()

-- 3. Window resize: hold ⌘⌃ + arrow ---------------------------------------------
-- skhd can't see a key release, so it could only jump 60 px per press. Here a held key runs
-- back-to-back 20 px yabai steps until release (a tap still gives 60 px). Each step starts when
-- the last one ends, so speed is set by how fast the apps redraw. The arrow moves the window's
-- inner border in its direction (Hyprland dwindle); bsp re-tiles the neighbours.
local yabai = "/opt/homebrew/bin/yabai"
local gridState = os.getenv("HOME") .. "/.local/state/aeris/grid-spaces"
-- 20 px: Safari ignores a top-edge shrink under ~20 px (it moves but keeps its height).
local STEP, TAP_STEPS = 20, 3
local hold = nil -- the active resize, or nil

local function query(what) return hs.json.decode(hs.execute(yabai .. " -m query " .. what) or "null") end

-- Run yabai commands one after another, off the main thread; cb(ok) when done or on failure.
local function yabaiSeq(cmds, cb, i)
  i = i or 1
  if i > #cmds then return cb(true) end
  hs.task.new(yabai, function(code)
    if code ~= 0 then return cb(false) end
    yabaiSeq(cmds, cb, i + 1)
  end, cmds[i]):start()
end

-- Apps have a minimum size yabai ignores, so a tiled neighbour can refuse to shrink and spill
-- over another window or off the work area. Score it (overlap + off-screen area); up to 2 px
-- of overlap is rounding.
local function spill(wins, s)
  local function span(a0, a1, b0, b1) return math.max(math.min(a1, b1) - math.max(a0, b0), 0) end
  local f, total = {}, 0
  for _, w in ipairs(wins or {}) do
    if w["is-visible"] and not w["is-floating"] then f[#f + 1] = w.frame end
  end
  for i, a in ipairs(f) do
    total = total + a.w * a.h - span(a.x, a.x + a.w, s.x, s.x + s.w) * span(a.y, a.y + a.h, s.y, s.y + s.h)
    for j = i + 1, #f do
      local b = f[j]
      total = total + math.max(span(a.x, a.x + a.w, b.x, b.x + b.w) - 2, 0)
                    * math.max(span(a.y, a.y + a.h, b.y, b.y + b.h) - 2, 0)
    end
  end
  return math.floor(total)
end

local function gridded(index)
  local f = io.open(gridState)
  if not f then return false end
  for line in f:lines() do if tonumber(line) == index then f:close() return true end end
  f:close()
  return false
end

local function startResize(dir)
  local space, win = query("--spaces --space"), query("--windows --window")
  if not (space and win) then return end
  local id = tostring(win.id)
  -- The grid owns window sizes: shake the window as a "no".
  if gridded(space.index) and not win["is-floating"] then
    for _, dx in ipairs({ 10, -20, 20, -20, 10 }) do
      hs.execute(yabai .. " -m window " .. id .. " --move rel:" .. dx .. ":0")
      hs.timer.usleep(30000)
    end
    return
  end
  -- Work area = display minus yabai padding (8) and the bar (26), plus 2 px slack.
  local d = query("--displays --window").frame
  local s = { x = d.x + 6, y = d.y + 32, w = d.w - 12, h = d.h - 38 }
  local f = win.frame
  -- Right/bottom edge, unless it sits on the screen edge: then left/top.
  local edge
  if dir == "left" or dir == "right" then
    edge = ((s.x + s.w) - (f.x + f.w) < 40 and f.x - s.x >= 40) and "left" or "right"
  else
    edge = ((s.y + s.h) - (f.y + f.h) < 40 and f.y - s.y >= 40) and "top" or "bottom"
  end
  local dx, dy = table.unpack(({ left = { -STEP, 0 }, right = { STEP, 0 }, up = { 0, -STEP }, down = { 0, STEP } })[dir])
  local function resize(x, y) return { "-m", "window", id, "--resize", string.format("%s:%d:%d", edge, x, y) } end
  local step = { resize(dx, dy) }
  -- Unmanaged windows: yabai shrinks a top/left edge by moving first, and macOS then drops the
  -- size change on a window hanging past the screen. Shrink the far edge, then move.
  local loose = space.type == "float" or win["is-floating"]
  if loose and edge == "top" and dir == "down" then
    step = { { "-m", "window", id, "--resize", "bottom:0:" .. -STEP }, { "-m", "window", id, "--move", "rel:0:" .. STEP } }
  elseif loose and edge == "left" and dir == "right" then
    step = { { "-m", "window", id, "--resize", "right:" .. -STEP .. ":0" }, { "-m", "window", id, "--move", "rel:" .. STEP .. ":0" } }
  end

  local me = { released = false, steps = 0 }
  hold = me
  local before = loose and 0 or spill(query("--windows --space"), s)
  local initial = before
  -- Some apps apply their minimum size a moment after yabai returns, so a spill can show up
  -- after the per-step check passed. Once the resize ends, wait, re-check, and undo steps until
  -- nothing spills more than when the key went down.
  local function settle()
    hs.timer.doAfter(0.15, function()
      hs.task.new(yabai, function(_, out)
        if me.steps > 0 and spill(hs.json.decode(out), s) > initial then
          me.steps = me.steps - 1
          yabaiSeq({ resize(-dx, -dy) }, settle)
        end
      end, { "-m", "query", "--windows", "--space" }):start()
    end)
  end
  local function tick()
    if hold ~= me then return end
    if me.released and me.steps >= TAP_STEPS then
      hold = nil
      if not loose then settle() end
      return
    end
    yabaiSeq({ table.unpack(step) }, function(ok)
      if not ok then hold = nil return end
      me.steps = me.steps + 1
      if loose then return tick() end
      hs.task.new(yabai, function(_, out)
        local after = spill(hs.json.decode(out), s)
        if after > before then -- a neighbour hit its minimum: undo and stop
          hold = nil
          me.steps = me.steps - 1
          return yabaiSeq({ resize(-dx, -dy) }, settle)
        end
        before = after
        tick()
      end, { "-m", "query", "--windows", "--space" }):start()
    end)
  end
  tick()
end

local function releaseResize() if hold then hold.released = true end end
for _, dir in ipairs({ "left", "right", "up", "down" }) do
  hs.hotkey.bind({ "cmd", "ctrl" }, dir, function() startResize(dir) end, releaseResize)
end
-- Same actions for scripts and agents: hs -c 'aerisResize.start("left")' then aerisResize.release()
aerisResize = { start = startResize, release = releaseResize }
