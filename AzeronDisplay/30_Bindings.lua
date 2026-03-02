local ns = _G.AzeronDisplayNS or {}
ns.modules = ns.modules or {}

local Bindings = ns.modules.Bindings or {}
local D = {}

function Bindings.Init(deps)
  D = deps or {}
end

function Bindings.GetFrameHotKeyText(frame)
  if not frame then return nil end
  if frame.HotKey and frame.HotKey.GetText then
    return frame.HotKey:GetText()
  end
  if frame.GetName then
    local hk = _G[(frame:GetName() or "") .. "HotKey"]
    if hk and hk.GetText then
      return hk:GetText()
    end
  end
  return nil
end

function Bindings.FindActionButtonByKeyLabel(key)
  local want = D.NormalizeKeyToken and D.NormalizeKeyToken(key) or nil
  if not want then return nil, nil, nil end
  for i = 1, 12 do
    local f = _G["ActionButton" .. i]
    if f then
      local hk = D.NormalizeKeyToken and D.NormalizeKeyToken(Bindings.GetFrameHotKeyText(f)) or nil
      if hk and hk == want then
        local slot = f.action or (f.GetAttribute and f:GetAttribute("action")) or (D.GetRealActionSlot and D.GetRealActionSlot(i) or nil)
        slot = D.SafeNumber and D.SafeNumber(slot, nil) or slot
        if slot and HasAction and HasAction(slot) then
          return f, slot, i
        end
      end
    end
  end
  return nil, nil, nil
end

function Bindings.ResolveWoWBindingFrameAndSlot(bindKey)
  if not bindKey or bindKey == "" then return nil, nil, nil, nil, nil end

  local raw = GetBindingAction and GetBindingAction(bindKey) or nil
  local function keyLabelFallback()
    local abFrame, abSlot, abButton = Bindings.FindActionButtonByKeyLabel(bindKey)
    if abFrame and abSlot then
      local rawAB = raw or ("ACTIONBUTTON" .. tostring(abButton))
      return rawAB, abFrame, abSlot, 1, abButton
    end
    return nil, nil, nil, nil, nil
  end

  if not raw or raw == "" then
    return keyLabelFallback()
  end

  local an = raw:match("^ACTIONBUTTON(%d+)$")
  if an then
    local btnNum = tonumber(an)
    local frame = _G["ActionButton" .. tostring(btnNum)]
    local slot = frame and (frame.action or (frame.GetAttribute and frame:GetAttribute("action"))) or (D.GetRealActionSlot and D.GetRealActionSlot(btnNum) or nil)
    slot = D.SafeNumber and D.SafeNumber(slot, nil) or slot
    if not slot then
      return keyLabelFallback()
    end
    return raw, frame, slot, 1, btnNum
  end

  local bn, bt = raw:match("^MULTIACTIONBAR(%d+)BUTTON(%d+)$")
  if bn and bt then
    local barNum, btnNum = tonumber(bn), tonumber(bt)
    local prefix = D.MULTIBAR_PREFIX and D.MULTIBAR_PREFIX[barNum] or nil
    local frame = prefix and _G[prefix .. tostring(btnNum)] or nil
    local slot = frame and (frame.action or (frame.GetAttribute and frame:GetAttribute("action"))) or (D.GetMultiBarActionSlot and D.GetMultiBarActionSlot(barNum, btnNum) or nil)
    slot = D.SafeNumber and D.SafeNumber(slot, nil) or slot
    if not slot then
      return keyLabelFallback()
    end
    return raw, frame, slot, barNum, btnNum
  end

  local fr, ff, fs, fb, fbtn = keyLabelFallback()
  if ff and fs then
    return raw, ff, fs, fb, fbtn
  end
  return raw, nil, nil, nil, nil
end

function Bindings.GetBindingInfo(key, modifier)
  local bindKey = key
  if modifier and modifier ~= "NONE" then
    bindKey = modifier .. "-" .. key
  end

  local abFrame, abSlot, abButton = Bindings.FindActionButtonByKeyLabel(bindKey)
  if abFrame and abSlot then
    local name = D.GetActionDisplayName and D.GetActionDisplayName(abSlot) or nil
    return name or ("Action " .. tostring(abButton)), GetActionTexture(abSlot), abSlot, nil, abFrame
  end

  local binding = GetBindingAction and GetBindingAction(bindKey) or nil
  if not binding or binding == "" then return "Unbound", nil, nil, nil, nil end

  local sn = binding:match("^SPELL (.+)$")
  if sn then
    local icon = D.GetSpellTextureByName and D.GetSpellTextureByName(sn) or nil
    return sn, icon, nil, sn, nil
  end

  local mn = binding:match("^MACRO (.+)$")
  if mn then
    local _, icon = GetMacroInfo(mn)
    return mn, icon, nil, nil, nil
  end

  local an = binding:match("^ACTIONBUTTON(%d+)$")
  if an then
    local wowFrame = _G["ActionButton" .. an]
    local slot = nil
    if wowFrame then
      slot = wowFrame.action or (wowFrame.GetAttribute and wowFrame:GetAttribute("action")) or nil
    end
    if not slot then
      slot = D.GetRealActionSlot and D.GetRealActionSlot(tonumber(an)) or nil
    end
    slot = D.SafeNumber and D.SafeNumber(slot, nil) or slot
    if not (slot and HasAction and HasAction(slot)) then
      return ("Action " .. tostring(an) .. " (Empty)"), nil, nil, nil, wowFrame
    end
    local icon = GetActionTexture(slot)
    local name = D.GetActionDisplayName and D.GetActionDisplayName(slot) or nil
    return name or ("Action " .. an), icon, slot, nil, wowFrame
  end

  local bn, bt = binding:match("^MULTIACTIONBAR(%d+)BUTTON(%d+)$")
  if bn and bt then
    local af, as, ab = Bindings.FindActionButtonByKeyLabel(bindKey)
    if af and as then
      local name = D.GetActionDisplayName and D.GetActionDisplayName(as) or nil
      return name or ("Action " .. tostring(ab)), GetActionTexture(as), as, nil, af
    end
    local barNum, btnNum = tonumber(bn), tonumber(bt)
    local prefix = D.MULTIBAR_PREFIX and D.MULTIBAR_PREFIX[tonumber(bn)] or nil
    local wowFrame = prefix and _G[prefix .. bt] or nil
    local slot = nil
    if wowFrame then
      slot = wowFrame.action or (wowFrame.GetAttribute and wowFrame:GetAttribute("action")) or nil
    end
    if not slot then
      slot = D.GetMultiBarActionSlot and D.GetMultiBarActionSlot(barNum, btnNum) or nil
    end
    slot = D.SafeNumber and D.SafeNumber(slot, nil) or slot
    if not (slot and HasAction and HasAction(slot)) then
      return ("Bar" .. tostring(bn) .. " #" .. tostring(bt) .. " (Empty)"), nil, nil, nil, wowFrame
    end
    local name = D.GetActionDisplayName and D.GetActionDisplayName(slot) or nil
    return name or ("Bar" .. bn .. " #" .. bt), GetActionTexture(slot), slot, nil, wowFrame
  end

  return binding, nil, nil, nil, nil
end

ns.modules.Bindings = Bindings
_G.AzeronDisplayNS = ns
