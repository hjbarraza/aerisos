-- Linux-style mouse clipboard for macOS.
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
