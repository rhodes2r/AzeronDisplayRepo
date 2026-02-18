-- Azeron Keybind Display - Core.lua
-- Three independent sections: Main Grid, D-Pad, Numpad
-- Buttons mirror WoW action buttons: icons, cooldown spirals, usability, proc glow

local ADDON_NAME = "AzeronDisplay"
local NS = _G.AzeronDisplayNS or {}
_G.AzeronDisplayNS = NS

AzeronDisplayDB = AzeronDisplayDB or {}
local DB

local editMode = false
local buttons = {}
local sectionFrames = {}
local cooldownLocks = {}

-- Button size (fixed), spacing (configurable, default 1)
local BTN_SIZE = 42
local BTN_SPACING = 1
local BTN_STEP = BTN_SIZE + BTN_SPACING -- 43

local DEFAULT_SETTINGS = {
  main = { scale = 1.0, visible = true },
  dpad = { scale = 1.0, visible = true },
  numpad = { scale = 1.0, visible = true },
  padding = 1,
  keyTextSize = 10,
  keydown = { width = 6, height = 6, alpha = 0.9, z = 5 },
  proc = { width = 6, height = 6, alpha = 1.0, z = 6, anim = 1, style = 1 },
}

local PROC_ANIMATIONS = {
  { value = 1, text = "Pulse" },
  { value = 2, text = "Breathing" },
  { value = 3, text = "Flash" },
  { value = 4, text = "Rotate CW" },
  { value = 5, text = "Rotate CCW" },
  { value = 6, text = "Color Pulse" },
}

local PROC_BORDER_STYLES = {
  { value = 1, text = "Cyan Classic", color = { 0.20, 0.78, 1.00 }, blend = "ADD", alphaMul = 1.00, sizeMul = 1.00 },
  { value = 2, text = "Arcane Bright", color = { 0.35, 0.90, 1.00 }, blend = "ADD", alphaMul = 1.20, sizeMul = 1.03 },
  { value = 3, text = "Frost Thin", color = { 0.25, 0.66, 1.00 }, blend = "BLEND", alphaMul = 1.05, sizeMul = 0.97 },
  { value = 4, text = "Electric", color = { 0.60, 1.00, 1.00 }, blend = "ADD", alphaMul = 1.35, sizeMul = 1.05 },
  { value = 5, text = "Ice White", color = { 0.88, 0.96, 1.00 }, blend = "ADD", alphaMul = 1.10, sizeMul = 1.00 },
  { value = 6, text = "Deep Blue", color = { 0.10, 0.45, 1.00 }, blend = "ADD", alphaMul = 1.25, sizeMul = 1.02 },
}
local PROC_BORDER_TEXTURE = "Interface\\Buttons\\UI-ActionButton-Border"
local SPECIAL_COOLDOWN_SPELLS = (NS.constants and NS.constants.SPECIAL_COOLDOWN_SPELLS) or {
  [22812] = 34.0, -- Barkskin
}
local CooldownModule = NS.modules and NS.modules.Cooldowns or nil
local BindingsModule = NS.modules and NS.modules.Bindings or nil
local IndicatorsModule = NS.modules and NS.modules.Indicators or nil
local ConfigModule = NS.modules and NS.modules.Config or nil

local function ClampNumber(v, minV, maxV, fallback)
  local n = tonumber(v)
  if not n then return fallback end
  if n < minV then return minV end
  if n > maxV then return maxV end
  return n
end

local function SafeNumber(v, fallback)
  local n = tonumber(tostring(v))
  if n == nil then return fallback end
  return n
end

local function SafeBool(v, fallback)
  if v == nil then return fallback end
  if type(v) == "boolean" then return v end
  local n = SafeNumber(v, nil)
  if n ~= nil then
    if n == 1 then return true end
    if n == 0 then return false end
  end
  return fallback
end

local function NormalizeCooldownPair(startTime, duration)
  local rawS = SafeNumber(startTime, 0)
  local rawD = SafeNumber(duration, 0)
  local s, d = rawS, rawD
  -- Some APIs can surface ms-like values; normalize to seconds.
  -- For CooldownFrame:GetCooldownTimes(), start and duration are both ms.
  if rawS > 100000 then
    s = rawS / 1000
    if rawD > 0 then d = rawD / 1000 end
  elseif rawD > 100000 then
    d = rawD / 1000
  end
  return s, d
end

-- Sections: cols/rows — pixel sizes computed at runtime from BTN_STEP
local SECTIONS = {
  main   = { label = "Main",   cols = 6, rows = 5 },
  dpad   = { label = "D-Pad",  cols = 3, rows = 3 },
  numpad = { label = "Mouse Side", cols = 3, rows = 5 },
}
local SECTION_ORDER = { "main", "dpad", "numpad" }

-- Key layout: col/row relative to section frame (pixel pos computed from BTN_STEP)
-- Main row 3 spans cols 0-5 (Tab..T), rows 1/2/4/5 use cols 1-4
local keyLayout = {
  -- Main row 1
  { id = "Z",  col = 1, row = 0, section = "main" },
  { id = "X",  col = 2, row = 0, section = "main" },
  { id = "C",  col = 3, row = 0, section = "main" },
  { id = "V",  col = 4, row = 0, section = "main" },
  -- Main row 2
  { id = "1",  col = 1, row = 1, section = "main" },
  { id = "2",  col = 2, row = 1, section = "main" },
  { id = "3",  col = 3, row = 1, section = "main" },
  { id = "4",  col = 4, row = 1, section = "main" },
  -- Main row 3 (full width: Tab + 4 + T)
  { id = "TAB", col = 0, row = 2, section = "main" },
  { id = "5",   col = 1, row = 2, section = "main" },
  { id = "6",   col = 2, row = 2, section = "main" },
  { id = "7",   col = 3, row = 2, section = "main" },
  { id = "8",   col = 4, row = 2, section = "main" },
  { id = "T",   col = 5, row = 2, section = "main" },
  -- Main row 4
  { id = "F1", col = 1, row = 3, section = "main" },
  { id = "F2", col = 2, row = 3, section = "main" },
  { id = "F3", col = 3, row = 3, section = "main" },
  { id = "F4", col = 4, row = 3, section = "main" },
  -- Main row 5 (blank — right-click to assign)
  { id = "MAIN_B1", col = 1, row = 4, section = "main" },
  { id = "MAIN_B2", col = 2, row = 4, section = "main" },
  { id = "MAIN_B3", col = 3, row = 4, section = "main" },
  { id = "MAIN_B4", col = 4, row = 4, section = "main" },

  -- D-Pad (5-button cross)
  { id = "UP",     col = 1, row = 0, section = "dpad" },
  { id = "LEFT",   col = 0, row = 1, section = "dpad" },
  { id = "DPAD_C", col = 1, row = 1, section = "dpad" },
  { id = "RIGHT",  col = 2, row = 1, section = "dpad" },
  { id = "DOWN",   col = 1, row = 2, section = "dpad" },

  -- Mouse Side (3 cols x 5 rows container, 12 active slots)
  { id = "NUMPAD7", col = 0, row = 0, section = "numpad" },
  { id = "NUMPAD8", col = 1, row = 0, section = "numpad" },
  { id = "NUMPAD9", col = 2, row = 0, section = "numpad" },
  { id = "NUMPAD4", col = 0, row = 1, section = "numpad" },
  { id = "NUMPAD5", col = 1, row = 1, section = "numpad" },
  { id = "NUMPAD6", col = 2, row = 1, section = "numpad" },
  { id = "NP_07",   col = 0, row = 2, section = "numpad" },
  { id = "NP_08",   col = 1, row = 2, section = "numpad" },
  { id = "NP_09",   col = 2, row = 2, section = "numpad" },
  { id = "NP_10",   col = 0, row = 3, section = "numpad" },
  { id = "NP_11",   col = 1, row = 3, section = "numpad" },
  { id = "NP_12",   col = 2, row = 3, section = "numpad" },
}

---------------------------------------------------------------------------
-- Modifier state
---------------------------------------------------------------------------
local currentModifierState = "NONE"
local MODIFIER_STATES = { "NONE", "CTRL", "SHIFT", "ALT", "CTRLSHIFT", "CTRLALT", "SHIFTALT", "CTRLSHIFTALT" }

local function GetCurrentModifierState()
  local c, s, a = IsControlKeyDown(), IsShiftKeyDown(), IsAltKeyDown()
  if c and s and a then return "CTRLSHIFTALT"
  elseif c and s then return "CTRLSHIFT"
  elseif c and a then return "CTRLALT"
  elseif s and a then return "SHIFTALT"
  elseif c then return "CTRL"
  elseif s then return "SHIFT"
  elseif a then return "ALT"
  else return "NONE" end
end

local function GetBaseKey(id)
  return DB.keyMap[id] or id
end

local function GetDisplayKeyText(baseKey)
  if not baseKey or baseKey == "" then return "" end
  local t = tostring(baseKey):upper()
  t = t:gsub("NUMPAD", "N")
  t = t:gsub("BUTTON", "M")
  t = t:gsub("MOUSEWHEELUP", "MWU")
  t = t:gsub("MOUSEWHEELDOWN", "MWD")
  return t
end

local function EnsureSettingsDefaults()
  DB.settings = DB.settings or {}

  -- Migrate legacy flat settings if present.
  if DB.settings.mainScale ~= nil then
    DB.settings.main = DB.settings.main or {}
    DB.settings.main.scale = DB.settings.main.scale or DB.settings.mainScale
  end
  if DB.settings.dpadScale ~= nil then
    DB.settings.dpad = DB.settings.dpad or {}
    DB.settings.dpad.scale = DB.settings.dpad.scale or DB.settings.dpadScale
  end
  if DB.settings.numpadScale ~= nil then
    DB.settings.numpad = DB.settings.numpad or {}
    DB.settings.numpad.scale = DB.settings.numpad.scale or DB.settings.numpadScale
  end

  -- Migrate legacy indicator settings if present.
  DB.settings.keydown = DB.settings.keydown or {}
  if DB.settings.keydownWidth ~= nil and DB.settings.keydown.width == nil then DB.settings.keydown.width = DB.settings.keydownWidth end
  if DB.settings.keydownHeight ~= nil and DB.settings.keydown.height == nil then DB.settings.keydown.height = DB.settings.keydownHeight end
  if DB.settings.keydownAlpha ~= nil and DB.settings.keydown.alpha == nil then DB.settings.keydown.alpha = DB.settings.keydownAlpha end
  if DB.settings.keydownZ ~= nil and DB.settings.keydown.z == nil then DB.settings.keydown.z = DB.settings.keydownZ end

  DB.settings.proc = DB.settings.proc or {}
  if DB.settings.procWidth ~= nil and DB.settings.proc.width == nil then DB.settings.proc.width = DB.settings.procWidth end
  if DB.settings.procHeight ~= nil and DB.settings.proc.height == nil then DB.settings.proc.height = DB.settings.procHeight end
  if DB.settings.procAlpha ~= nil and DB.settings.proc.alpha == nil then DB.settings.proc.alpha = DB.settings.procAlpha end
  if DB.settings.procZ ~= nil and DB.settings.proc.z == nil then DB.settings.proc.z = DB.settings.procZ end
  if DB.settings.procStyle ~= nil and DB.settings.proc.style == nil then DB.settings.proc.style = DB.settings.procStyle end

  if DB.settings.textSize ~= nil and DB.settings.keyTextSize == nil then
    DB.settings.keyTextSize = DB.settings.textSize
  end

  for _, k in ipairs({ "main", "dpad", "numpad" }) do
    DB.settings[k] = DB.settings[k] or {}
    if DB.settings[k].scale == nil then DB.settings[k].scale = DEFAULT_SETTINGS[k].scale end
    if DB.settings[k].visible == nil then DB.settings[k].visible = DEFAULT_SETTINGS[k].visible end
  end

  if DB.settings.padding == nil then DB.settings.padding = DEFAULT_SETTINGS.padding end
  if DB.settings.keyTextSize == nil then DB.settings.keyTextSize = DEFAULT_SETTINGS.keyTextSize end

  DB.settings.keydown = DB.settings.keydown or {}
  DB.settings.keydown.width = ClampNumber(DB.settings.keydown.width, 2, 30, DEFAULT_SETTINGS.keydown.width)
  DB.settings.keydown.height = ClampNumber(DB.settings.keydown.height, 2, 30, DEFAULT_SETTINGS.keydown.height)
  DB.settings.keydown.alpha = ClampNumber(DB.settings.keydown.alpha, 0.2, 1.0, DEFAULT_SETTINGS.keydown.alpha)
  DB.settings.keydown.z = math.floor(ClampNumber(DB.settings.keydown.z, -8, 7, DEFAULT_SETTINGS.keydown.z) + 0.5)

  DB.settings.proc = DB.settings.proc or {}
  DB.settings.proc.width = ClampNumber(DB.settings.proc.width, 2, 50, DEFAULT_SETTINGS.proc.width)
  DB.settings.proc.height = ClampNumber(DB.settings.proc.height, 2, 50, DEFAULT_SETTINGS.proc.height)
  DB.settings.proc.alpha = ClampNumber(DB.settings.proc.alpha, 0.2, 2.0, DEFAULT_SETTINGS.proc.alpha)
  DB.settings.proc.z = math.floor(ClampNumber(DB.settings.proc.z, -8, 7, DEFAULT_SETTINGS.proc.z) + 0.5)
  DB.settings.proc.anim = math.floor(ClampNumber(DB.settings.proc.anim, 1, 6, DEFAULT_SETTINGS.proc.anim) + 0.5)
  DB.settings.proc.style = math.floor(ClampNumber(DB.settings.proc.style, 1, 6, DEFAULT_SETTINGS.proc.style) + 0.5)
end

---------------------------------------------------------------------------
-- Spell / action helpers (12.0 Midnight compatible)
---------------------------------------------------------------------------
local function GetSpellTextureByName(name)
  if not name then return nil end
  if C_Spell and C_Spell.GetSpellTexture then
    return C_Spell.GetSpellTexture(name)
  elseif GetSpellInfo then
    local _, _, icon = GetSpellInfo(name)
    return icon
  end
end

local function GetSpellNameByID(spellID)
  if not spellID then return nil end
  if C_Spell and C_Spell.GetSpellName then
    return C_Spell.GetSpellName(spellID)
  elseif GetSpellInfo then
    return (GetSpellInfo(spellID))
  end
end

local function GetSpellIDByName(name)
  if not name then return nil end
  if C_Spell and C_Spell.GetSpellInfo then
    local info = C_Spell.GetSpellInfo(name)
    if info then return info.spellID end
  end
  return nil
end

local function GetRealActionSlot(num)
  local f = _G["ActionButton" .. num]
  if f then
    return f.action or f:GetAttribute("action") or num
  end
  return num
end

local MULTIBAR_PREFIX = {
  [1] = "MultiBarBottomLeftButton", [2] = "MultiBarBottomRightButton",
  [3] = "MultiBarRightButton",     [4] = "MultiBarLeftButton",
  [5] = "MultiBar5Button",         [6] = "MultiBar6Button",
  [7] = "MultiBar7Button",         [8] = "MultiBar8Button",
}
local MULTIBAR_BASE = {
  [1] = 60, [2] = 48, [3] = 24, [4] = 36,
  [5] = 144, [6] = 156, [7] = 168, [8] = 180,
}

local function GetMultiBarActionSlot(bar, btn)
  local prefix = MULTIBAR_PREFIX[bar]
  if prefix then
    local f = _G[prefix .. btn]
    if f then
      return f.action or f:GetAttribute("action") or (MULTIBAR_BASE[bar] and MULTIBAR_BASE[bar] + btn)
    end
  end
  return MULTIBAR_BASE[bar] and MULTIBAR_BASE[bar] + btn
end

-- Resolve actual ability name + spellID from an action slot
local function GetActionDisplayName(slot)
  if not slot or not HasAction or not HasAction(slot) then return nil, nil end
  local actionType, id = GetActionInfo(slot)
  if actionType == "spell" then
    return GetSpellNameByID(id) or ("Spell " .. tostring(id)), id
  elseif actionType == "macro" then
    local name = GetMacroInfo(id)
    return name or "Macro", nil
  elseif actionType == "item" then
    if C_Item and C_Item.GetItemNameByID then
      return C_Item.GetItemNameByID(id) or "Item", nil
    end
    return "Item", nil
  end
  return nil, nil
end

-- Check if a WoW action button frame has its proc glow showing
local function IsWoWButtonGlowing(frame)
  if not frame then return false end
  -- 12.0 Midnight: AssistedCombatHighlightFrame
  if frame.AssistedCombatHighlightFrame and frame.AssistedCombatHighlightFrame.IsShown and frame.AssistedCombatHighlightFrame:IsShown() then
    return true
  end
  -- Fallback: SpellActivationAlert (older retail)
  if frame.SpellActivationAlert and frame.SpellActivationAlert.IsShown and frame.SpellActivationAlert:IsShown() then
    return true
  end
  return false
end

local function IsWoWButtonPressed(frame)
  if not frame or not frame.GetButtonState then return false end
  local ok, state = pcall(frame.GetButtonState, frame)
  return ok and state == "PUSHED"
end

local function GetProcCandidateScore(bd)
  local slot = tonumber(bd and bd.actionSlot) or 9999
  local primaryPenalty = (slot >= 1 and slot <= 12) and 0 or 10000
  return primaryPenalty + slot
end

local function GetBarButtonFromFrame(frame)
  if not frame or not frame.GetName then return nil, nil end
  local name = frame:GetName() or ""
  local n = name:match("^ActionButton(%d+)$")
  if n then
    return 1, tonumber(n)
  end
  for bar, prefix in pairs(MULTIBAR_PREFIX) do
    local b = name:match("^" .. prefix .. "(%d+)$")
    if b then
      return bar + 1, tonumber(b)
    end
  end
  return nil, nil
end

local function GetSourceIconTexture(frame, slot)
  if frame and frame.icon and frame.icon.GetTexture then
    return frame.icon:GetTexture()
  end
  if slot and GetActionTexture then
    return GetActionTexture(slot)
  end
  return nil
end

local function GetLiveActionSlotFromBinding(bd)
  if not bd then return nil end
  local slot = SafeNumber(bd.actionSlot, nil)
  local wf = bd.wowFrame
  if wf then
    local live = wf.action
    if live == nil and wf.GetAttribute then
      live = wf:GetAttribute("action")
    end
    local liveNum = SafeNumber(live, nil)
    if liveNum then
      slot = liveNum
    end
  end
  return slot
end

local function GetWoWButtonCooldown(bd)
  if not bd or not bd.wowFrame then return 0, 0 end
  local frame = bd.wowFrame
  local cd = nil
  if frame.cooldown then
    cd = frame.cooldown
  elseif frame.Cooldown then
    cd = frame.Cooldown
  elseif frame.GetName then
    local fn = frame:GetName() or ""
    cd = _G[fn .. "Cooldown"] or _G[fn .. "SpellCooldown"]
  end
  if (not cd) and frame.GetNumChildren and frame.GetChildren then
    local n = frame:GetNumChildren() or 0
    if n > 0 then
      for i = 1, n do
        local child = select(i, frame:GetChildren())
        if child and child.GetObjectType and child:GetObjectType() == "Cooldown" then
          cd = child
          break
        end
      end
    end
  end
  if not cd then
    return 0, 0
  end
  if cd and cd.GetCooldownTimes then
    local ok, sMS, dMS = pcall(cd.GetCooldownTimes, cd)
    if ok then
      local s = SafeNumber(sMS, 0)
      local d = SafeNumber(dMS, 0)
      if s > 100000 then s = s / 1000 end
      if d > 100000 then d = d / 1000 end
      return s, d
    end
  end
  return 0, 0
end

local function IsWoWButtonCooldownShown(bd)
  if not bd or not bd.wowFrame then return false end
  local frame = bd.wowFrame
  local cd = frame.cooldown or frame.Cooldown
  if (not cd) and frame.GetName then
    local fn = frame:GetName() or ""
    cd = _G[fn .. "Cooldown"] or _G[fn .. "SpellCooldown"]
  end
  if cd and cd.IsShown then
    return cd:IsShown() and true or false
  end
  return false
end

local function GetCActionBarCooldown(slot, actionID)
  if (not slot and not actionID) or not C_ActionBar then return 0, 0, nil end
  local detail = {
    ref = nil,
    startTime = 0,
    duration = 0,
    isEnabled = nil,
    modRate = nil,
    activeCategory = nil,
    timeUntilEndOfStartRecovery = 0,
    isOnGCD = nil,
    source = "none",
  }

  local function fromActionCooldownRef(ref)
    if not ref or not C_ActionBar.GetActionCooldown then return nil, nil, nil end
    local ok, a, b, c = pcall(C_ActionBar.GetActionCooldown, ref)
    if not ok then return nil, nil, nil end
    detail.ref = ref
    detail.source = "GetActionCooldown"
    if type(a) == "table" then
      detail.startTime, detail.duration = NormalizeCooldownPair(a.startTime or a.start or a.cooldownStartTime, a.duration or a.cooldownDuration)
      detail.isEnabled = a.isEnabled
      detail.modRate = a.modRate
      detail.activeCategory = a.activeCategory
      detail.timeUntilEndOfStartRecovery = SafeNumber(a.timeUntilEndOfStartRecovery, 0)
      detail.isOnGCD = a.isOnGCD
      local s = detail.startTime
      local d = detail.duration
      local rec = detail.timeUntilEndOfStartRecovery
      if d > 0 then
        if s <= 0 then s = (GetTime and GetTime() or 0) end
        return s, d, detail
      end
      if rec > 0 then
        return (GetTime and GetTime() or 0), rec, detail
      end
      return 0, 0, detail
    else
      local s, d = NormalizeCooldownPair(a, b)
      detail.startTime = s
      detail.duration = d
      detail.isEnabled = c
      if d > 0 then
        if s <= 0 then s = (GetTime and GetTime() or 0) end
        return s, d, detail
      end
      return 0, 0, detail
    end
  end

  -- Prefer spell/actionID ref first, then slot.
  do
    local tried = {}
    local refs = { actionID, slot }
    for _, ref in ipairs(refs) do
      local rn = SafeNumber(ref, nil)
      if rn and not tried[rn] then
        tried[rn] = true
        local s, d, det = fromActionCooldownRef(rn)
        if s ~= nil and d ~= nil then
          if d > 0 then return s, d, det end
          detail = det or detail
        end
      end
    end
  end

  -- Compatibility fallback.
  if slot and C_ActionBar.GetCooldownInfo then
    local ok, info = pcall(C_ActionBar.GetCooldownInfo, slot)
    if ok and info then
      local s, d = NormalizeCooldownPair(info.startTime, info.duration)
      local tStartRecovery = SafeNumber(info.timeUntilEndOfStartRecovery, 0)
      detail.ref = SafeNumber(slot, nil)
      detail.startTime = s
      detail.duration = d
      detail.isEnabled = info.isEnabled
      detail.modRate = info.modRate
      detail.activeCategory = info.activeCategory
      detail.timeUntilEndOfStartRecovery = tStartRecovery
      detail.isOnGCD = info.isOnGCD
      detail.source = "GetCooldownInfo"
      if d > 0 then
        if s <= 0 then s = (GetTime and GetTime() or 0) end
        return s, d, detail
      end
      if tStartRecovery > 0 then
        return (GetTime and GetTime() or 0), tStartRecovery, detail
      end
    end
  end
  return 0, 0, detail
end

local function GetActionSpellCandidates(slot)
  if not slot then return {}, {} end
  local ids, srcByID = {}, {}
  local seen = {}

  local function add(id, src)
    local n = SafeNumber(id, nil)
    if not n or n <= 0 or seen[n] then return end
    seen[n] = true
    ids[#ids + 1] = n
    srcByID[n] = src
  end

  -- Prefer action payload spell first; this tends to be more stable for cooldown tracking.
  if GetActionInfo then
    local ok, actionType, actionID = pcall(GetActionInfo, slot)
    if ok then
      if actionType == "spell" then
        add(actionID, "GetActionInfo")
      end
    end
  end
  if GetActionSpellID then
    local ok, sid = pcall(GetActionSpellID, slot)
    if ok then add(sid, "GetActionSpellID") end
  end

  return ids, srcByID
end

local function GetSpellCooldownFromActionSlot(slot, fallbackSpellID)
  if not slot then return 0, 0, nil, {} end
  local spellIDs = GetActionSpellCandidates(slot)
  if (#spellIDs == 0) and fallbackSpellID then
    local fb = SafeNumber(fallbackSpellID, nil)
    if fb and fb > 0 then
      spellIDs = { fb }
    end
  end
  if #spellIDs == 0 then
    return 0, 0, nil, spellIDs
  end

  -- Prefer C_Spell on modern clients.
  if C_Spell and C_Spell.GetSpellCooldown then
    for i = 1, #spellIDs do
      local sid = spellIDs[i]
      local ok, info = pcall(C_Spell.GetSpellCooldown, sid)
      if ok and info then
        local s, d = NormalizeCooldownPair(info.startTime, info.duration)
        local tStartRecovery = SafeNumber(info.timeUntilEndOfStartRecovery, 0)
        if d > 0 then
          if s <= 0 then s = (GetTime and GetTime() or 0) end
          return s, d, sid, spellIDs
        end
        if tStartRecovery > 0 then
          return (GetTime and GetTime() or 0), tStartRecovery, sid, spellIDs
        end
      end
    end
  end

  -- Compatibility fallback.
  if GetSpellCooldown then
    for i = 1, #spellIDs do
      local sid = spellIDs[i]
      local ok, s, d = pcall(GetSpellCooldown, sid)
      if ok then
        s, d = NormalizeCooldownPair(s, d)
        if d > 0 then
          if s <= 0 then s = (GetTime and GetTime() or 0) end
          return s, d, sid, spellIDs
        end
      end
    end
  end

  return 0, 0, spellIDs[1], spellIDs
end

local function GetWoWButtonIconTexture(frame, slot)
  if not frame then
    return slot and GetActionTexture and GetActionTexture(slot) or nil
  end
  if frame.icon and frame.icon.GetTexture then
    local t = frame.icon:GetTexture()
    if t then return t end
  end
  if frame.Icon and frame.Icon.GetTexture then
    local t = frame.Icon:GetTexture()
    if t then return t end
  end
  if slot and GetActionTexture then
    return GetActionTexture(slot)
  end
  return nil
end

local function NormalizeKeyToken(s)
  if not s then return nil end
  return tostring(s):upper():gsub("%s+", ""):gsub("%-", "")
end

if BindingsModule and BindingsModule.Init then
  BindingsModule.Init({
    NormalizeKeyToken = NormalizeKeyToken,
    SafeNumber = SafeNumber,
    GetRealActionSlot = GetRealActionSlot,
    GetMultiBarActionSlot = GetMultiBarActionSlot,
    GetActionDisplayName = GetActionDisplayName,
    GetSpellTextureByName = GetSpellTextureByName,
    MULTIBAR_PREFIX = MULTIBAR_PREFIX,
  })
end

local function GetFrameHotKeyText(frame)
  if BindingsModule and BindingsModule.GetFrameHotKeyText then
    return BindingsModule.GetFrameHotKeyText(frame)
  end
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

local function FindActionButtonByKeyLabel(key)
  if BindingsModule and BindingsModule.FindActionButtonByKeyLabel then
    return BindingsModule.FindActionButtonByKeyLabel(key)
  end
  local want = NormalizeKeyToken(key)
  if not want then return nil, nil, nil end
  for i = 1, 12 do
    local f = _G["ActionButton" .. i]
    if f then
      local hk = NormalizeKeyToken(GetFrameHotKeyText(f))
      if hk and hk == want then
        local slot = f.action or (f.GetAttribute and f:GetAttribute("action")) or GetRealActionSlot(i)
        slot = SafeNumber(slot, nil)
        -- Only treat Action Bar 1 as canonical when this button actually has an action.
        if slot and HasAction and HasAction(slot) then
          return f, slot, i
        end
      end
    end
  end
  return nil, nil, nil
end

local function ResolveWoWBindingFrameAndSlot(bindKey)
  if BindingsModule and BindingsModule.ResolveWoWBindingFrameAndSlot then
    return BindingsModule.ResolveWoWBindingFrameAndSlot(bindKey)
  end
  if not bindKey or bindKey == "" then return nil, nil, nil, nil, nil end
  local abFrame, abSlot, abButton = FindActionButtonByKeyLabel(bindKey)
  if abFrame and abSlot then
    local rawAB = GetBindingAction and GetBindingAction(bindKey) or ("ACTIONBUTTON" .. tostring(abButton))
    return rawAB, abFrame, abSlot, 1, abButton
  end
  local raw = GetBindingAction and GetBindingAction(bindKey) or nil
  if not raw or raw == "" then return nil, nil, nil, nil, nil end

  local an = raw:match("^ACTIONBUTTON(%d+)$")
  if an then
    local btnNum = tonumber(an)
    local frame = _G["ActionButton" .. tostring(btnNum)]
    local slot = frame and (frame.action or (frame.GetAttribute and frame:GetAttribute("action"))) or GetRealActionSlot(btnNum)
    return raw, frame, SafeNumber(slot, nil), 1, btnNum
  end

  local bn, bt = raw:match("^MULTIACTIONBAR(%d+)BUTTON(%d+)$")
  if bn and bt then
    local abFrame, abSlot, abButton = FindActionButtonByKeyLabel(bindKey)
    if abFrame and abSlot then
      -- Canonicalize to Action Bar 1 when key label is visibly present there.
      return raw, abFrame, abSlot, 1, abButton
    end
    local barNum, btnNum = tonumber(bn), tonumber(bt)
    local prefix = MULTIBAR_PREFIX[barNum]
    local frame = prefix and _G[prefix .. tostring(btnNum)] or nil
    local slot = frame and (frame.action or (frame.GetAttribute and frame:GetAttribute("action"))) or GetMultiBarActionSlot(barNum, btnNum)
    return raw, frame, SafeNumber(slot, nil), barNum, btnNum
  end

  return raw, nil, nil, nil, nil
end

local function CollectGlowingWoWSources()
  local out = {}
  local seen = {}

  local function addFrame(frame, bar, button)
    if not frame or seen[frame] then return end
    if not IsWoWButtonGlowing(frame) then return end
    seen[frame] = true
    local slot = frame.action or (frame.GetAttribute and frame:GetAttribute("action")) or nil
    out[#out + 1] = {
      frame = frame,
      frameName = frame.GetName and frame:GetName() or "?",
      bar = bar,
      button = button,
      slot = slot,
      icon = GetSourceIconTexture(frame, slot),
    }
  end

  for i = 1, 12 do
    addFrame(_G["ActionButton" .. i], 1, i)
  end
  local scanBars = {
    [2] = "MultiBarBottomLeftButton",
    [3] = "MultiBarBottomRightButton",
    [4] = "MultiBarRightButton",
  }
  for bar, prefix in pairs(scanBars) do
    for i = 1, 12 do
      addFrame(_G[prefix .. i], bar, i)
    end
  end

  return out
end

local function GetChatIconMarkup(iconTex, size)
  if not iconTex then return "[no-icon]" end
  local s = tonumber(size) or 14
  return "|T" .. tostring(iconTex) .. ":" .. s .. ":" .. s .. ":0:0:64:64:4:60:4:60|t"
end

local function GetGlowFrameSignature(frame)
  if not frame then return "hl=none" end
  local src = frame.AssistedCombatHighlightFrame or frame.SpellActivationAlert or frame.overlay
  if not src then return "hl=missing" end

  local srcName = src.GetName and src:GetName() or "unnamed"
  local srcAlpha = src.GetAlpha and src:GetAlpha() or 0
  local shown = src.IsShown and src:IsShown() or false

  local texPath, blend, ra, ga, ba, aa = "none", "?", 1, 1, 1, 1
  if src.GetRegions then
    local regions = { src:GetRegions() }
    for i = 1, #regions do
      local r = regions[i]
      if r and r.GetObjectType and r:GetObjectType() == "Texture" then
        texPath = r.GetTexture and r:GetTexture() or "none"
        blend = r.GetBlendMode and r:GetBlendMode() or "?"
        if r.GetVertexColor then
          local vr, vg, vb, va = r:GetVertexColor()
          ra, ga, ba, aa = vr or 1, vg or 1, vb or 1, va or 1
        end
        break
      end
    end
  end

  return string.format(
    "hl=%s shown=%s a=%.2f tex=%s blend=%s rgba=%.2f,%.2f,%.2f,%.2f",
    tostring(srcName),
    tostring(shown),
    tonumber(srcAlpha) or 0,
    tostring(texPath),
    tostring(blend),
    tonumber(ra) or 1, tonumber(ga) or 1, tonumber(ba) or 1, tonumber(aa) or 1
  )
end

local function GetGlowTexture(frame)
  if not frame then return nil end
  local src = frame.AssistedCombatHighlightFrame or frame.SpellActivationAlert or frame.overlay
  if not src or not src.GetRegions then return nil end
  local regions = { src:GetRegions() }
  for i = 1, #regions do
    local r = regions[i]
    if r and r.GetObjectType and r:GetObjectType() == "Texture" then
      return r.GetTexture and r:GetTexture() or nil
    end
  end
  return nil
end

local function GetGlowVisualData(frame)
  if not frame then return nil end
  local sourceType = nil
  local src = nil
  if frame.AssistedCombatHighlightFrame and frame.AssistedCombatHighlightFrame.IsShown and frame.AssistedCombatHighlightFrame:IsShown() then
    src = frame.AssistedCombatHighlightFrame
    sourceType = "assisted"
  elseif frame.SpellActivationAlert and frame.SpellActivationAlert.IsShown and frame.SpellActivationAlert:IsShown() then
    src = frame.SpellActivationAlert
    sourceType = "spellalert"
  elseif frame.overlay and type(frame.overlay.IsShown) == "function" and frame.overlay:IsShown() then
    src = frame.overlay
    sourceType = "overlay"
  end
  if not src then return nil end

  local data = {
    sourceType = sourceType,
    alpha = (src.GetAlpha and src:GetAlpha()) or 1,
    texture = nil,
    blend = nil,
    r = 1, g = 1, b = 1, a = 1,
  }

  if src.GetRegions then
    local regions = { src:GetRegions() }
    for i = 1, #regions do
      local region = regions[i]
      if region and region.GetObjectType and region:GetObjectType() == "Texture" then
        data.texture = region.GetTexture and region:GetTexture() or nil
        data.blend = region.GetBlendMode and region:GetBlendMode() or nil
        if region.GetVertexColor then
          local vr, vg, vb, va = region:GetVertexColor()
          data.r, data.g, data.b, data.a = vr or 1, vg or 1, vb or 1, va or 1
        end
        break
      end
    end
  end

  return data
end

local function ApplyProcSourceVisual(btn, sourceFrame)
  if not btn then return end
  local data = GetGlowVisualData(sourceFrame)
  if not data then return end

  local intensity = btn._procIntensity or 1.0
  local alphaScale = math.min(1.0, intensity)
  local colorBoost = math.max(0, intensity - 1.0)
  local r = math.min(1.0, (data.r or 1) + (1.0 - (data.r or 1)) * colorBoost)
  local g = math.min(1.0, (data.g or 1) + (1.0 - (data.g or 1)) * colorBoost)
  local b = math.min(1.0, (data.b or 1) + (1.0 - (data.b or 1)) * colorBoost)
  local a = data.a or 1
  local baseAlpha = math.min(1.0, (data.alpha or 1) * alphaScale)

  -- Retail 12.0 assisted-combat proc border is cyan; raw region color can be white.
  if data.sourceType == "assisted" then
    r, g, b, a = 0.18, 0.80, 1.00, 1.00
  end

  -- Keep source hue, but avoid near-black borders by lifting brightness proportionally.
  local luminance = (0.2126 * r) + (0.7152 * g) + (0.0722 * b)
  if luminance < 0.25 then
    local gain = 0.25 / math.max(0.01, luminance)
    r = math.min(1.0, r * gain)
    g = math.min(1.0, g * gain)
    b = math.min(1.0, b * gain)
  end
  if baseAlpha < 0.35 then
    baseAlpha = 0.35
  end

  -- Unified proc border: single art for all proc types.
  if btn.procBorder then
    btn.procBorder:SetTexture(PROC_BORDER_TEXTURE)
    btn.procBorder:SetBlendMode("ADD")
    btn.procBorder:SetVertexColor(r, g, b, a)
    btn.procBorder:SetAlpha(baseAlpha)
  end
  btn._procR, btn._procG, btn._procB, btn._procA = r, g, b, a
  btn._procBaseAlpha = baseAlpha
end

-- Returns: displayName, iconTex, actionSlot, spellName, wowBtnFrame
local function GetBindingInfo(key, modifier)
  if BindingsModule and BindingsModule.GetBindingInfo then
    return BindingsModule.GetBindingInfo(key, modifier)
  end
  local bindKey = key
  if modifier and modifier ~= "NONE" then
    bindKey = modifier .. "-" .. key
  end
  local abFrame, abSlot, abButton = FindActionButtonByKeyLabel(bindKey)
  if abFrame and abSlot then
    local name = GetActionDisplayName(abSlot)
    return name or ("Action " .. tostring(abButton)), GetActionTexture(abSlot), abSlot, nil, abFrame
  end
  local binding = GetBindingAction(bindKey)
  if not binding or binding == "" then return "Unbound", nil, nil, nil, nil end

  -- SPELL
  local sn = binding:match("^SPELL (.+)$")
  if sn then
    return sn, GetSpellTextureByName(sn), nil, sn, nil
  end

  -- MACRO
  local mn = binding:match("^MACRO (.+)$")
  if mn then
    local _, icon = GetMacroInfo(mn)
    return mn, icon, nil, nil, nil
  end

  -- ACTIONBUTTON
  local an = binding:match("^ACTIONBUTTON(%d+)$")
  if an then
    local slot = GetRealActionSlot(tonumber(an))
    local icon = HasAction(slot) and GetActionTexture(slot) or nil
    local name = GetActionDisplayName(slot)
    local wowFrame = _G["ActionButton" .. an]
    return name or ("Action " .. an), icon, slot, nil, wowFrame
  end

  -- MULTIACTIONBAR
  local bn, bt = binding:match("^MULTIACTIONBAR(%d+)BUTTON(%d+)$")
  if bn and bt then
    local abFrame, abSlot, abButton = FindActionButtonByKeyLabel(key)
    if abFrame and abSlot then
      local name = GetActionDisplayName(abSlot)
      return name or ("Action " .. tostring(abButton)), GetActionTexture(abSlot), abSlot, nil, abFrame
    end
    local slot = GetMultiBarActionSlot(tonumber(bn), tonumber(bt))
    local prefix = MULTIBAR_PREFIX[tonumber(bn)]
    local wowFrame = prefix and _G[prefix .. bt] or nil
    if slot and HasAction and HasAction(slot) then
      local name = GetActionDisplayName(slot)
      return name or ("Bar" .. bn .. " #" .. bt), GetActionTexture(slot), slot, nil, wowFrame
    end
    return "Bar" .. bn .. " #" .. bt, nil, slot, nil, wowFrame
  end

  return binding, nil, nil, nil, nil
end

---------------------------------------------------------------------------
-- Forward declarations
---------------------------------------------------------------------------
local UpdateBindings, UpdateCooldowns, UpdateUsability, OpenKeyEditor
local ApplyButtonVisualSettings, RefreshAllVisualSettings

---------------------------------------------------------------------------
-- Edit mode
---------------------------------------------------------------------------
local function ApplyEditModeVisuals()
  for _, sKey in ipairs(SECTION_ORDER) do
    local f = sectionFrames[sKey]
    if f then
      f.bg:SetColorTexture(0, 0, 0, editMode and 0.4 or 0)
      if editMode then f.label:Show() else f.label:Hide() end
      f:SetMovable(editMode)
    end
  end
end

local function ToggleEditMode()
  editMode = not editMode
  ApplyEditModeVisuals()
  print(ADDON_NAME .. ": Edit mode " .. (editMode and "ON" or "OFF"))
end

---------------------------------------------------------------------------
-- Section frame creation
---------------------------------------------------------------------------
local function CreateSectionFrame(sKey)
  local def = SECTIONS[sKey]
  local w = def.cols * BTN_STEP
  local h = def.rows * BTN_STEP

  local f = CreateFrame("Frame", ADDON_NAME .. "_" .. sKey, UIParent)
  f:SetSize(w, h)
  f:EnableMouse(true)
  f:SetMovable(false)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self)
    if editMode then self:StartMoving() end
  end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, ox, oy = self:GetPoint(1)
    DB.sectionPositions[sKey] = { point = p, relPoint = rp, x = ox, y = oy }
  end)

  -- Background (invisible by default, shown in edit mode)
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints()
  f.bg:SetColorTexture(0, 0, 0, 0)

  -- Label (edit mode only, floats above frame)
  f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.label:SetPoint("BOTTOM", f, "TOP", 0, 2)
  f.label:SetText(def.label)
  f.label:SetTextColor(1, 0.82, 0, 1)
  f.label:Hide()

  -- Edit toggle button (floats above top-right)
  f.editBtn = CreateFrame("Button", nil, f)
  f.editBtn:SetSize(16, 16)
  f.editBtn:SetPoint("BOTTOMLEFT", f, "TOPRIGHT", 2, 2)
  f.editBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-CollapseButton-Up")
  f.editBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
  f.editBtn:SetScript("OnClick", ToggleEditMode)

  -- Position
  local saved = DB.sectionPositions[sKey]
  if saved then
    f:SetPoint(saved.point or "CENTER", UIParent, saved.relPoint or "CENTER", saved.x or 0, saved.y or 0)
  else
    local defaults = { main = { -150, 0 }, dpad = { 150, 60 }, numpad = { 150, -80 } }
    local d = defaults[sKey]
    f:SetPoint("CENTER", UIParent, "CENTER", d[1], d[2])
  end

  -- Scale and visibility
  local s = DB.settings[sKey]
  f:SetScale(s and s.scale or 1.0)
  if s and s.visible == false then f:Hide() end

  sectionFrames[sKey] = f
  return f
end

---------------------------------------------------------------------------
-- Button creation — mirrors WoW action button appearance
---------------------------------------------------------------------------
local function CreateKeyButton(info, parent)
  local btn = CreateFrame("Button", nil, parent)
  btn:SetSize(BTN_SIZE, BTN_SIZE)
  btn:SetPoint("TOPLEFT", parent, "TOPLEFT", info.col * BTN_STEP, -info.row * BTN_STEP)
  btn.keyID = info.id
  btn.info = info
  btn:EnableMouse(true)

  -- Slot background fill
  btn.slotBg = btn:CreateTexture(nil, "BACKGROUND")
  btn.slotBg:SetSize(BTN_SIZE - 6, BTN_SIZE - 6)
  btn.slotBg:SetPoint("CENTER")
  btn.slotBg:SetTexture("Interface\\Buttons\\WHITE8X8")
  btn.slotBg:SetVertexColor(0, 0, 0, 0.65)

  -- Icon
  btn.icon = btn:CreateTexture(nil, "ARTWORK")
  btn.icon:SetSize(BTN_SIZE - 4, BTN_SIZE - 4)
  btn.icon:SetPoint("CENTER")
  btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  btn.icon:SetDesaturated(false)

  -- Disabled-state tint (used for cooldown-locked abilities like Barkskin).
  btn.disabledTint = btn:CreateTexture(nil, "OVERLAY", nil, 1)
  btn.disabledTint:SetSize(BTN_SIZE - 4, BTN_SIZE - 4)
  btn.disabledTint:SetPoint("CENTER")
  btn.disabledTint:SetTexture("Interface\\Buttons\\WHITE8X8")
  btn.disabledTint:SetVertexColor(0, 0, 0, 0.38)
  btn.disabledTint:Hide()

  -- Cooldown spiral
  btn.cooldown = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
  btn.cooldown:SetSize(BTN_SIZE - 4, BTN_SIZE - 4)
  btn.cooldown:SetPoint("CENTER")
  btn.cooldown:SetDrawEdge(true)
  if btn.cooldown.SetHideCountdownNumbers then
    -- Use addon-controlled numeric text only; Blizzard countdown text can desync.
    btn.cooldown:SetHideCountdownNumbers(true)
  end

  -- Text overlay above cooldown swipe so numbers remain readable.
  btn.textOverlay = CreateFrame("Frame", nil, btn)
  btn.textOverlay:SetAllPoints(btn)
  btn.textOverlay:SetFrameStrata(btn:GetFrameStrata())
  btn.textOverlay:SetFrameLevel(btn:GetFrameLevel() + 30)

  -- Cooldown remaining text (center).
  btn.cooldownText = btn.textOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  btn.cooldownText:SetPoint("CENTER", btn.textOverlay, "CENTER", 0, 0)
  btn.cooldownText:SetTextColor(1, 0.95, 0.6, 1)
  btn.cooldownText:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
  if btn.cooldownText.SetDrawLayer then
    btn.cooldownText:SetDrawLayer("OVERLAY", 7)
  end
  btn.cooldownText:SetText("")

  -- Stack/charge count text (bottom-right).
  btn.countText = btn.textOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  btn.countText:SetPoint("BOTTOMRIGHT", btn.textOverlay, "BOTTOMRIGHT", -2, 2)
  btn.countText:SetTextColor(1, 1, 1, 1)
  btn.countText:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
  if btn.countText.SetDrawLayer then
    btn.countText:SetDrawLayer("OVERLAY", 7)
  end
  btn.countText:SetText("")

  -- Normal border (rounded dark frame for empty/action slots)
  btn.borderFrame = CreateFrame("Frame", nil, btn, BackdropTemplateMixin and "BackdropTemplate" or nil)
  btn.borderFrame:SetPoint("TOPLEFT", btn, "TOPLEFT", -1, 1)
  btn.borderFrame:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, -1)
  if btn.borderFrame.SetBackdrop then
    btn.borderFrame:SetBackdrop({
      bgFile = "Interface\\Buttons\\WHITE8X8",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true,
      tileSize = 8,
      edgeSize = 10,
      insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    btn.borderFrame:SetBackdropColor(0, 0, 0, 0.15)
    btn.borderFrame:SetBackdropBorderColor(0.55, 0.55, 0.55, 0.9)
  end

  -- Proc border replacement frame (used to replace normal border while proc is active).
  btn.procBorderFrame = CreateFrame("Frame", nil, btn, BackdropTemplateMixin and "BackdropTemplate" or nil)
  btn.procBorderFrame:SetPoint("TOPLEFT", btn, "TOPLEFT", -1, 1)
  btn.procBorderFrame:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, -1)
  if btn.procBorderFrame.SetBackdrop then
    btn.procBorderFrame:SetBackdrop({
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 22,
      insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    btn.procBorderFrame:SetBackdropColor(0, 0, 0, 0)
    btn.procBorderFrame:SetBackdropBorderColor(0.20, 0.78, 1.00, 1.0)
  end
  btn.procBorderFrame:Hide()


  -- Active action highlight (white/silver, for IsCurrentAction — stance, channel, toggle)
  btn.activeBorder = btn:CreateTexture(nil, "OVERLAY", nil, 1)
  btn.activeBorder:SetSize(BTN_SIZE + 6, BTN_SIZE + 6)
  btn.activeBorder:SetPoint("CENTER")
  btn.activeBorder:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
  btn.activeBorder:SetBlendMode("ADD")
  btn.activeBorder:SetVertexColor(1.0, 0.84, 0.02, 1.0)
  btn.activeBorder:SetAlpha(1.0)
  btn.activeBorder:Hide()

  -- Keypress edge-only frame (avoids square fill artifacts from texture borders).
  btn.activePressFrame = CreateFrame("Frame", nil, btn, BackdropTemplateMixin and "BackdropTemplate" or nil)
  btn.activePressFrame:SetPoint("TOPLEFT", btn, "TOPLEFT", -1, 1)
  btn.activePressFrame:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, -1)
  if btn.activePressFrame.SetBackdrop then
    btn.activePressFrame:SetBackdrop({
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 20,
      insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    btn.activePressFrame:SetBackdropColor(0, 0, 0, 0)
    btn.activePressFrame:SetBackdropBorderColor(1.0, 0.92, 0.18, 1.0)
  end
  btn.activePressFrame:Hide()

  -- Keypress fill (yellow tint across the button face).
  btn.activeFill = btn:CreateTexture(nil, "OVERLAY", nil, 0)
  btn.activeFill:SetSize(BTN_SIZE, BTN_SIZE)
  btn.activeFill:SetPoint("CENTER")
  btn.activeFill:SetTexture("Interface\\Buttons\\WHITE8X8")
  btn.activeFill:SetBlendMode("ADD")
  btn.activeFill:SetVertexColor(1.0, 0.82, 0.10, 0.45)
  btn.activeFill:Hide()

  -- Proc/rotation recommendation glow (golden, for AssistedCombatHighlightFrame)
  btn.procBorder = btn:CreateTexture(nil, "OVERLAY", nil, 2)
  btn.procBorder:SetSize(BTN_SIZE + 6, BTN_SIZE + 6)
  btn.procBorder:SetPoint("CENTER")
  btn.procBorder:SetTexture(PROC_BORDER_TEXTURE)
  btn.procBorder:SetBlendMode("ADD")
  -- Midnight assisted-combat proc style is blue/cyan, not classic gold.
  btn.procBorder:SetVertexColor(0.20, 0.78, 1.00, 1)
  btn.procBorder:SetAlpha(1.0)
  btn.procBorder:Hide()

  -- Compact key label (top-right corner, inside button)
  btn.keyLabel = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  btn.keyLabel:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -3, -2)
  btn.keyLabel:SetWidth(BTN_SIZE - 4)
  btn.keyLabel:SetJustifyH("RIGHT")
  btn.keyLabel:SetTextColor(1, 1, 1, 0.9)
  btn.keyLabel:SetWordWrap(false)
  btn.keyLabel:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")

  ApplyButtonVisualSettings(btn)

  -- Right-click opens key editor; mouseover shows current binding tooltip.
  btn:RegisterForClicks("RightButtonUp")
  btn:SetScript("OnClick", function(self, button)
    if button == "RightButton" then OpenKeyEditor(self.keyID) end
  end)
  btn:SetScript("OnEnter", function(self)
    local ms = currentModifierState or "NONE"
    local bd = self.bindings and self.bindings[ms]
    if not bd then return end

    if GameTooltip_SetDefaultAnchor then
      GameTooltip_SetDefaultAnchor(GameTooltip, self)
    else
      GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    end
    if bd.actionSlot and HasAction and HasAction(bd.actionSlot) then
      GameTooltip:SetAction(bd.actionSlot)
      GameTooltip:Show()
      return
    end

    if bd.spellName then
      local spellID = GetSpellIDByName(bd.spellName)
      if spellID and GameTooltip.SetSpellByID then
        GameTooltip:SetSpellByID(spellID)
      else
        GameTooltip:SetText(bd.spellName)
      end
      GameTooltip:Show()
      return
    end

    if bd.name and bd.name ~= "Unbound" then
      GameTooltip:SetText(bd.name)
      GameTooltip:Show()
    end
  end)
  btn:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  btn.bindings = {}
  return btn
end

ApplyButtonVisualSettings = function(btn)
  if not btn then return end
  local keydownRaw = DB and DB.settings and DB.settings.keydown or DEFAULT_SETTINGS.keydown
  local procRaw = DB and DB.settings and DB.settings.proc or DEFAULT_SETTINGS.proc
  local keydown = {
    width = ClampNumber(keydownRaw.width, 2, 30, DEFAULT_SETTINGS.keydown.width),
    height = ClampNumber(keydownRaw.height, 2, 30, DEFAULT_SETTINGS.keydown.height),
    alpha = ClampNumber(keydownRaw.alpha, 0.2, 1.0, DEFAULT_SETTINGS.keydown.alpha),
    z = math.floor(ClampNumber(keydownRaw.z, -8, 7, DEFAULT_SETTINGS.keydown.z) + 0.5),
  }
  local proc = {
    width = ClampNumber(procRaw.width, 2, 50, DEFAULT_SETTINGS.proc.width),
    height = ClampNumber(procRaw.height, 2, 50, DEFAULT_SETTINGS.proc.height),
    alpha = ClampNumber(procRaw.alpha, 0.2, 2.0, DEFAULT_SETTINGS.proc.alpha),
    z = math.floor(ClampNumber(procRaw.z, -8, 7, DEFAULT_SETTINGS.proc.z) + 0.5),
    anim = math.floor(ClampNumber(procRaw.anim, 1, 6, DEFAULT_SETTINGS.proc.anim) + 0.5),
  }
  local keyTextSize = math.floor(ClampNumber(DB and DB.settings and DB.settings.keyTextSize, 6, 24, DEFAULT_SETTINGS.keyTextSize) + 0.5)

  if btn.keyLabel then
    btn.keyLabel:SetFont(STANDARD_TEXT_FONT, keyTextSize, "OUTLINE")
  end

  if btn.activeBorder then
    btn.activeBorder:SetSize(BTN_SIZE + (keydown.width or 6) + 20, BTN_SIZE + (keydown.height or 6) + 20)
    btn.activeBorder:SetAlpha(math.max(0.90, math.min(1.0, (keydown.alpha or 0.9) * 1.20)))
    local kz = math.max(-8, math.min(7, keydown.z or 1))
    btn.activeBorder:SetDrawLayer("OVERLAY", kz)
  end
  if btn.activePressFrame then
    local halfExtraW = math.max(0, (keydown.width - 2) / 2)
    local halfExtraH = math.max(0, (keydown.height - 2) / 2)
    btn.activePressFrame:ClearAllPoints()
    btn.activePressFrame:SetPoint("TOPLEFT", btn, "TOPLEFT", -1 - halfExtraW, 1 + halfExtraH)
    btn.activePressFrame:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1 + halfExtraW, -1 - halfExtraH)
    if btn.activePressFrame.SetBackdrop then
      local edgeSize = math.max(18, math.min(36, math.floor((keydown.width or 6) * 0.45 + 18)))
      btn.activePressFrame:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = edgeSize,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
      })
      btn.activePressFrame:SetBackdropColor(0, 0, 0, 0)
      btn.activePressFrame:SetBackdropBorderColor(1.0, 0.92, 0.18, math.max(0.92, math.min(1.0, (keydown.alpha or 0.9) * 1.10)))
    end
  end
  if btn.activeFill then
    btn.activeFill:SetSize(BTN_SIZE + (keydown.width or 6), BTN_SIZE + (keydown.height or 6))
    btn.activeFill:SetAlpha(math.min(0.85, (keydown.alpha or 0.9) * 0.5))
  end

  if btn.procBorder then
    local intensity = proc.alpha or 1.0
    local t = math.max(0, intensity - 1.0)
    local baseR, baseG, baseB = 1.0, 0.82, 0.0
    local r = baseR + (1.00 - baseR) * t
    local g = baseG + (1.00 - baseG) * t
    local b = baseB
    btn.procBorder:SetSize(BTN_SIZE + (proc.width or 6) + 8, BTN_SIZE + (proc.height or 6) + 8)
    btn.procBorder:SetAlpha(math.min(1.0, intensity * 0.95))
    -- Draw behind icon so only border/outside glow is visible.
    btn.procBorder:SetDrawLayer("OVERLAY", proc.z or 2)
    btn.procBorder:SetTexture(PROC_BORDER_TEXTURE)
    btn.procBorder:SetBlendMode("ADD")
    btn.procBorder:SetScale(1)
    btn.procBorder:SetRotation(0)
    btn.procBorder:SetVertexColor(r, g, b, 1)
    btn._procAnimType = proc.anim
    btn._procBaseAlpha = math.min(1.0, intensity)
    btn._procIntensity = intensity
  end

  if btn.procBorderFrame then
    local halfExtraW = math.max(0, (proc.width - 2) / 2)
    local halfExtraH = math.max(0, (proc.height - 2) / 2)
    btn.procBorderFrame:ClearAllPoints()
    btn.procBorderFrame:SetPoint("TOPLEFT", btn, "TOPLEFT", -1 - halfExtraW, 1 + halfExtraH)
    btn.procBorderFrame:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1 + halfExtraW, -1 - halfExtraH)
    if btn.procBorderFrame.SetBackdrop then
      -- Keep proc border visually thick even when proc width/height is small.
      local edgeSize = math.max(22, math.min(36, math.floor((proc.width or 6) * 0.30 + 22)))
      btn.procBorderFrame:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = edgeSize,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
      })
      btn.procBorderFrame:SetBackdropColor(0, 0, 0, 0)
    end
  end

end

local function StopProcAnimation(btn)
  if not btn then return end
  if btn.procAnimGroup and btn.procAnimGroup:IsPlaying() then
    btn.procAnimGroup:Stop()
  end
  if btn.procBorder then
    btn.procBorder:SetScale(1)
    btn.procBorder:SetRotation(0)
    btn.procBorder:SetTexture(PROC_BORDER_TEXTURE)
    btn.procBorder:SetBlendMode("ADD")
    btn.procBorder:SetVertexColor(
      btn._procR or 1.0,
      btn._procG or 0.82,
      btn._procB or 0.0,
      btn._procA or 1.0
    )
    btn.procBorder:SetAlpha(btn._procBaseAlpha or 1.0)
  end
  btn._procAnimPlaying = false
end

local function EnsureProcAnimation(btn)
  if not btn or not btn.procBorder then return end
  local animType = btn._procAnimType or 1
  if btn.procAnimGroup and btn.procAnimGroup._type == animType then
    return
  end
  if btn.procAnimGroup then
    btn.procAnimGroup:Stop()
    btn.procAnimGroup = nil
  end

  local g = btn.procBorder:CreateAnimationGroup()
  g:SetLooping("REPEAT")
  g._type = animType

  if animType == 1 then
    local a1 = g:CreateAnimation("Alpha")
    a1:SetFromAlpha(btn._procBaseAlpha or 1.0)
    a1:SetToAlpha(math.max(0.45, (btn._procBaseAlpha or 1.0) * 0.55))
    a1:SetDuration(0.32)
    a1:SetOrder(1)
    local a2 = g:CreateAnimation("Alpha")
    a2:SetFromAlpha(math.max(0.45, (btn._procBaseAlpha or 1.0) * 0.55))
    a2:SetToAlpha(btn._procBaseAlpha or 1.0)
    a2:SetDuration(0.32)
    a2:SetOrder(2)
  elseif animType == 2 then
    local s1 = g:CreateAnimation("Scale")
    s1:SetScale(1.08, 1.08)
    s1:SetOrigin("CENTER", 0, 0)
    s1:SetDuration(0.38)
    s1:SetOrder(1)
    local s2 = g:CreateAnimation("Scale")
    s2:SetScale(0.925, 0.925)
    s2:SetOrigin("CENTER", 0, 0)
    s2:SetDuration(0.38)
    s2:SetOrder(2)
  elseif animType == 3 then
    local a1 = g:CreateAnimation("Alpha")
    a1:SetFromAlpha(btn._procBaseAlpha or 1.0)
    a1:SetToAlpha(0.35)
    a1:SetDuration(0.12)
    a1:SetOrder(1)
    local a2 = g:CreateAnimation("Alpha")
    a2:SetFromAlpha(0.35)
    a2:SetToAlpha(btn._procBaseAlpha or 1.0)
    a2:SetDuration(0.12)
    a2:SetOrder(2)
  elseif animType == 4 then
    local s1 = g:CreateAnimation("Scale")
    s1:SetScale(1.14, 1.14)
    s1:SetOrigin("CENTER", 0, 0)
    s1:SetDuration(0.28)
    s1:SetOrder(1)
    local s2 = g:CreateAnimation("Scale")
    s2:SetScale(0.875, 0.875)
    s2:SetOrigin("CENTER", 0, 0)
    s2:SetDuration(0.28)
    s2:SetOrder(2)
  elseif animType == 5 then
    local a1 = g:CreateAnimation("Alpha")
    a1:SetFromAlpha(btn._procBaseAlpha or 1.0)
    a1:SetToAlpha(0.55)
    a1:SetDuration(0.09)
    a1:SetOrder(1)
    local a2 = g:CreateAnimation("Alpha")
    a2:SetFromAlpha(0.55)
    a2:SetToAlpha(btn._procBaseAlpha or 1.0)
    a2:SetDuration(0.09)
    a2:SetOrder(2)
    local a3 = g:CreateAnimation("Alpha")
    a3:SetFromAlpha(btn._procBaseAlpha or 1.0)
    a3:SetToAlpha(0.72)
    a3:SetDuration(0.18)
    a3:SetOrder(3)
    local a4 = g:CreateAnimation("Alpha")
    a4:SetFromAlpha(0.72)
    a4:SetToAlpha(btn._procBaseAlpha or 1.0)
    a4:SetDuration(0.18)
    a4:SetOrder(4)
  else
    local a1 = g:CreateAnimation("Alpha")
    a1:SetFromAlpha(btn._procBaseAlpha or 1.0)
    a1:SetToAlpha(0.50)
    a1:SetDuration(0.22)
    a1:SetOrder(1)
    local a2 = g:CreateAnimation("Alpha")
    a2:SetFromAlpha(0.50)
    a2:SetToAlpha(btn._procBaseAlpha or 1.0)
    a2:SetDuration(0.22)
    a2:SetOrder(2)
    g:SetScript("OnLoop", function()
      if not btn.procBorder then return end
      if btn._procColorFlip then
        btn.procBorder:SetVertexColor(btn._procR or 0.20, btn._procG or 0.78, btn._procB or 1.00, 1.0)
      else
        local lr = math.min(1.0, (btn._procR or 0.20) + 0.08)
        local lg = math.min(1.0, (btn._procG or 0.78) + 0.06)
        local lb = math.min(1.0, (btn._procB or 1.00) + 0.00)
        btn.procBorder:SetVertexColor(lr, lg, lb, 1.0)
      end
      btn._procColorFlip = not btn._procColorFlip
    end)
  end

  btn.procAnimGroup = g
end

RefreshAllVisualSettings = function()
  for _, btn in ipairs(buttons) do
    ApplyButtonVisualSettings(btn)
  end
end

---------------------------------------------------------------------------
-- Key Editor (right-click popup)
---------------------------------------------------------------------------
local editor, editorTitle, editorKeyInput
local editorPreviewRows = {}
local currentEditButtonID = nil

local function CreateEditorFrame()
  if editor then return editor end

  editor = CreateFrame("Frame", ADDON_NAME .. "Editor", UIParent)
  editor:SetSize(400, 340)
  editor:SetPoint("CENTER")
  editor:SetMovable(true)
  editor:EnableMouse(true)
  editor:SetClampedToScreen(true)
  editor:SetToplevel(true)
  editor:SetFrameStrata("HIGH")
  editor:SetFrameLevel(100)
  editor:RegisterForDrag("LeftButton")
  editor:SetScript("OnDragStart", function(self) self:StartMoving() end)
  editor:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

  local border = editor:CreateTexture(nil, "BORDER")
  border:SetAllPoints()
  border:SetColorTexture(0.3, 0.3, 0.3, 1)

  local bg = editor:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", 2, -2)
  bg:SetPoint("BOTTOMRIGHT", -2, 2)
  bg:SetColorTexture(0.05, 0.05, 0.05, 0.95)

  editorTitle = editor:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  editorTitle:SetPoint("TOP", 0, -15)
  editorTitle:SetTextColor(1, 1, 1, 1)

  local btnClose = CreateFrame("Button", nil, editor, "UIPanelCloseButton")
  btnClose:SetPoint("TOPRIGHT", -10, -10)
  btnClose:SetScript("OnClick", function() editor:Hide() end)

  local inst = editor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  inst:SetPoint("TOP", editorTitle, "BOTTOM", 0, -10)
  inst:SetText("Enter the WoW key name for this button:")
  inst:SetTextColor(0.8, 0.8, 0.8, 1)

  editorKeyInput = CreateFrame("EditBox", nil, editor, "InputBoxTemplate")
  editorKeyInput:SetSize(200, 30)
  editorKeyInput:SetPoint("TOP", inst, "BOTTOM", 0, -8)
  editorKeyInput:SetAutoFocus(false)
  editorKeyInput:SetMaxLetters(30)

  local examples = editor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  examples:SetPoint("TOP", editorKeyInput, "BOTTOM", 0, -4)
  examples:SetText("Examples: 1, F2, Z, NUMPAD5, TAB, UP")
  examples:SetTextColor(0.6, 0.6, 0.6, 1)

  local header = editor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  header:SetPoint("TOP", examples, "BOTTOM", 0, -14)
  header:SetText("Keybind Preview:")
  header:SetTextColor(1, 1, 0.5, 1)

  local modifiers = {
    { key = "NONE",  label = "Default", color = { 0.5, 0.5, 1.0 } },
    { key = "CTRL",  label = "CTRL",    color = { 1.0, 0.5, 0.5 } },
    { key = "SHIFT", label = "SHIFT",   color = { 0.5, 1.0, 0.5 } },
    { key = "ALT",   label = "ALT",     color = { 1.0, 1.0, 0.5 } },
  }

  for i, modInfo in ipairs(modifiers) do
    local row = CreateFrame("Frame", nil, editor)
    row:SetSize(360, 36)
    row:SetPoint("TOP", header, "BOTTOM", 0, -4 - ((i - 1) * 38))

    local rowBg = row:CreateTexture(nil, "BACKGROUND")
    rowBg:SetAllPoints()
    rowBg:SetColorTexture(0.1, 0.1, 0.1, 0.5)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(32, 32)
    row.icon:SetPoint("LEFT", 4, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    row.modLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.modLabel:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.modLabel:SetText(modInfo.label)
    row.modLabel:SetTextColor(modInfo.color[1], modInfo.color[2], modInfo.color[3], 1)
    row.modLabel:SetWidth(60)
    row.modLabel:SetJustifyH("LEFT")

    row.bindLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.bindLabel:SetPoint("LEFT", row.modLabel, "RIGHT", 8, 0)
    row.bindLabel:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.bindLabel:SetJustifyH("LEFT")
    row.bindLabel:SetTextColor(0.7, 0.7, 0.7, 1)

    row.modifierKey = modInfo.key
    editorPreviewRows[i] = row
  end

  local function RefreshPreview(key)
    for _, row in ipairs(editorPreviewRows) do
      local mod = row.modifierKey == "NONE" and nil or row.modifierKey
      local dn, iconTex = GetBindingInfo(key, mod)
      row.icon:SetTexture(iconTex)
      row.bindLabel:SetText(dn or "—")
    end
  end

  editorKeyInput:SetScript("OnTextChanged", function(self, userInput)
    if userInput then RefreshPreview(self:GetText():upper()) end
  end)

  local btnSave = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
  btnSave:SetSize(100, 28)
  btnSave:SetPoint("BOTTOMRIGHT", -12, 12)
  btnSave:SetText("Save")
  btnSave:SetScript("OnClick", function()
    if not currentEditButtonID then return end
    local newKey = editorKeyInput:GetText():upper()
    if newKey == "" then return end
    DB.keyMap[currentEditButtonID] = newKey
    currentModifierState = nil
    UpdateBindings()
    editor:Hide()
    print(ADDON_NAME .. ": '" .. currentEditButtonID .. "' -> key '" .. newKey .. "'")
  end)

  local btnDefault = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
  btnDefault:SetSize(120, 28)
  btnDefault:SetPoint("RIGHT", btnSave, "LEFT", -8, 0)
  btnDefault:SetText("Reset Default")
  btnDefault:SetScript("OnClick", function()
    if not currentEditButtonID then return end
    DB.keyMap[currentEditButtonID] = nil
    currentModifierState = nil
    UpdateBindings()
    editor:Hide()
    print(ADDON_NAME .. ": '" .. currentEditButtonID .. "' reset to default")
  end)

  local btnCancel = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
  btnCancel:SetSize(80, 28)
  btnCancel:SetPoint("RIGHT", btnDefault, "LEFT", -8, 0)
  btnCancel:SetText("Cancel")
  btnCancel:SetScript("OnClick", function() editor:Hide() end)

  editor.RefreshPreview = RefreshPreview
  return editor
end

OpenKeyEditor = function(buttonID)
  if not editor then CreateEditorFrame() end
  currentEditButtonID = buttonID
  local key = GetBaseKey(buttonID)
  editorTitle:SetText("Set Base Key: " .. buttonID)
  editorKeyInput:SetText(key)
  editor.RefreshPreview(key)
  editor:ClearAllPoints()
  editor:SetPoint("CENTER")
  editor:Show()
  editor:Raise()
end

---------------------------------------------------------------------------
-- Update: refresh all button bindings for all modifier states
---------------------------------------------------------------------------
UpdateBindings = function()
  for i, info in ipairs(keyLayout) do
    local sFrame = sectionFrames[info.section]
    if not sFrame then return end

    local btn = buttons[i]
    if not btn then
      btn = CreateKeyButton(info, sFrame)
      buttons[i] = btn
    end

    local baseKey = GetBaseKey(info.id)
    local oldBindings = btn.bindings or {}
    local newBindings = {}
    for _, mod in ipairs(MODIFIER_STATES) do
      local m = mod == "NONE" and nil or mod
      local dn, icon, slot, sn, wowFrame = GetBindingInfo(baseKey, m)
      local old = oldBindings[mod]
      local nb = {
        name = dn,
        icon = icon,
        actionSlot = slot,
        spellName = sn,
        wowFrame = wowFrame,
      }
      -- Preserve last-known runtime data if this refresh returns partial/empty values.
      if old then
        if nb.icon == nil then nb.icon = old.icon end
        if nb.actionSlot == nil then nb.actionSlot = old.actionSlot end
        if nb.wowFrame == nil then nb.wowFrame = old.wowFrame end
        nb._activeCooldownSig = old._activeCooldownSig
        nb._activeCooldownStart = old._activeCooldownStart
        nb._activeCooldownDur = old._activeCooldownDur
        nb._activeCooldownEnd = old._activeCooldownEnd
        nb._cooldownSig = old._cooldownSig
        nb._cooldownStart = old._cooldownStart
        nb._cooldownDur = old._cooldownDur
      end
      newBindings[mod] = nb
    end
    btn.bindings = newBindings

    -- Show current modifier's icon and compact key label
    local ms = currentModifierState or "NONE"
    local bd = btn.bindings[ms]
    btn.icon:SetTexture(bd and bd.icon or nil)
    local keyText = GetDisplayKeyText(baseKey)
    if bd and bd.name and bd.name ~= "Unbound" and keyText ~= "" then
      btn.keyLabel:SetText(keyText)
    else
      btn.keyLabel:SetText("")
    end
  end
  UpdateCooldowns()
  UpdateUsability()
end

---------------------------------------------------------------------------
-- Update: cooldown spirals
---------------------------------------------------------------------------
UpdateCooldowns = function()
  local ms = currentModifierState or "NONE"
  for _, btn in ipairs(buttons) do
    if btn and btn.cooldown and btn.bindings then
      local bd = btn.bindings[ms]
      if bd then
        local baseKey = GetBaseKey(btn.keyID)
        local bindKey = (ms == "NONE") and baseKey or (ms .. "-" .. baseKey)
        local lockKey = tostring(bindKey or btn.keyID or "")
        local _, resolvedFrame, resolvedSlot = ResolveWoWBindingFrameAndSlot(bindKey)
        if resolvedFrame then bd.wowFrame = resolvedFrame end
        if resolvedSlot then bd.actionSlot = resolvedSlot end

        local cdStart, cdDur = 0, 0
        local actionStart, actionDur = 0, 0
        local apiStart, apiDur = 0, 0
        local spellStart, spellDur = 0, 0
        local wowStart, wowDur = 0, 0
        local wowShown = false
        local charges, maxCharges = nil, nil
        local chargeStart, chargeDur = nil, nil
        local stackCount = nil
        local hasRealAction = false
        local isSpecialCooldownBinding = false
        local specialCooldownExpected = nil
        local slot = GetLiveActionSlotFromBinding(bd)
        if (not slot or slot <= 0) and bd._lastGoodSlot then
          slot = SafeNumber(bd._lastGoodSlot, nil)
        end
        local actionSig = "none"
        if slot then
          bd.actionSlot = slot
          bd._lastGoodSlot = slot
          actionSig = tostring(slot)
          hasRealAction = (HasAction and HasAction(slot)) and true or false
        end
        if slot then
          local hasAction = hasRealAction
          local slotActionType, slotActionID = nil, nil
          if GetActionInfo then
            local okai, at, aid = pcall(GetActionInfo, slot)
            if okai then
              slotActionType, slotActionID = at, aid
            end
          end
          local primarySpellID = nil
          local spellIDs = nil
          do
            local ids = GetActionSpellCandidates(slot)
            spellIDs = ids
            primarySpellID = ids[1]
            if (not primarySpellID) and bd._lastActionSig == actionSig then
              local cached = SafeNumber(bd._lastPrimarySpellID, nil)
              if cached and cached > 0 then
                primarySpellID = cached
                spellIDs = { cached }
              end
            end
            if primarySpellID and primarySpellID > 0 then
              bd._lastActionSig = actionSig
              bd._lastPrimarySpellID = primarySpellID
            end
            local resolvedSpellID = SafeNumber(primarySpellID, 0)
            if not resolvedSpellID or resolvedSpellID <= 0 then
              if slotActionType == "spell" then
                resolvedSpellID = SafeNumber(slotActionID, 0)
              else
                resolvedSpellID = 0
              end
            end
            if CooldownModule and CooldownModule.GetExpectedDuration then
              specialCooldownExpected = CooldownModule.GetExpectedDuration(resolvedSpellID, SPECIAL_COOLDOWN_SPELLS)
            else
              specialCooldownExpected = SPECIAL_COOLDOWN_SPELLS[resolvedSpellID]
            end
            isSpecialCooldownBinding = (resolvedSpellID > 0)
          end
          if GetActionCooldown then
            local ok, s, d = pcall(GetActionCooldown, slot)
            if ok then
              actionStart, actionDur = NormalizeCooldownPair(s, d)
            end
          end
          do
            local as, ad = GetCActionBarCooldown(slot, primarySpellID or ((slotActionType == "spell") and slotActionID or nil))
            apiStart, apiDur = SafeNumber(as, 0), SafeNumber(ad, 0)
          end
          do
            local ss, sd = GetSpellCooldownFromActionSlot(slot, primarySpellID)
            spellStart, spellDur = NormalizeCooldownPair(ss, sd)
          end
          do
            local ws, wd = GetWoWButtonCooldown(bd)
            wowStart, wowDur = NormalizeCooldownPair(ws, wd)
            wowShown = IsWoWButtonCooldownShown(bd)
            -- Guard against stale frame cooldowns from mismatched icon sources.
            if (not isSpecialCooldownBinding) and wowDur > 0 and hasAction and bd.wowFrame and GetActionTexture then
              local slotIcon = GetActionTexture(slot)
              local frameIcon = GetWoWButtonIconTexture(bd.wowFrame, slot)
              if slotIcon and frameIcon and slotIcon ~= frameIcon then
                wowStart, wowDur = 0, 0
              end
            end
          end

          local now = GetTime and GetTime() or 0
          local bestRemain = 0
          local nativeBestRemain = 0
          local function considerTimer(s, d)
            if s > 0 and d > 0 then
              -- Ignore global-cooldown-like timers to avoid false positives.
              if d <= 1.6 then
                return 0
              end
              local r = math.max(0, (s + d) - now)
              if r > bestRemain then
                bestRemain = r
                cdStart, cdDur = s, d
              end
              return r
            end
            return 0
          end
          local actionRemain = considerTimer(actionStart, actionDur)
          local apiRemain = considerTimer(apiStart, apiDur)
          local wowRemain = considerTimer(wowStart, wowDur)

          if isSpecialCooldownBinding then
            if CooldownModule and CooldownModule.UpdateSpecialState then
              local cs, cd = CooldownModule.UpdateSpecialState(
                bd,
                wowShown,
                wowStart,
                wowDur,
                now,
                specialCooldownExpected
              )
              cdStart, cdDur = SafeNumber(cs, 0), SafeNumber(cd, 0)
            else
              local expectedDur = SafeNumber(specialCooldownExpected, 0)
              if expectedDur <= 0 then
                expectedDur = SafeNumber(bd._specCdFallbackDur, 0)
              end
              if wowShown then
                local wasShown = (bd._specCdShown == true)
                if not wasShown then
                  bd._specCdShown = true
                  bd._specCdStart = now
                  local ws, wd = NormalizeCooldownPair(wowStart, wowDur)
                  if ws > 0 and wd > 1.6 and wd < 120 then
                    bd._specCdDur = wd
                    bd._specCdFallbackDur = wd
                  else
                    bd._specCdDur = expectedDur
                  end
                end
                local cs = SafeNumber(bd._specCdStart, now)
                local cd = SafeNumber(bd._specCdDur, expectedDur)
                cdStart, cdDur = cs, cd
              else
                cdStart, cdDur = 0, 0
                bd._specCdShown = false
                bd._specCdStart, bd._specCdDur = nil, nil
              end
            end
            bestRemain = (cdStart > 0 and cdDur > 0) and math.max(0, (cdStart + cdDur) - now) or 0
          end
          nativeBestRemain = math.max(actionRemain, apiRemain, wowRemain)
          if nativeBestRemain > 0 then
            bd._spellTrustSig = actionSig
            bd._spellTrustUntil = now + nativeBestRemain + 0.5
          end
          local spellTrusted = (bd._spellTrustSig == actionSig) and (SafeNumber(bd._spellTrustUntil, 0) > now)
          if nativeBestRemain > 0 or spellTrusted then
            considerTimer(spellStart, spellDur)
          end
          if GetActionCharges then
            local okc, c, mc, cs, cd = pcall(GetActionCharges, slot)
            if okc then
              charges, maxCharges, chargeStart, chargeDur = c, mc, cs, cd
            end
          end
          if GetActionCount then
            local okn, n = pcall(GetActionCount, slot)
            if okn then stackCount = n end
          end
        end
        local now = GetTime and GetTime() or 0
        if not hasRealAction then
          bd._specCdShown = false
          bd._specCdStart, bd._specCdDur = nil, nil
        end
        local safeStart = SafeNumber(cdStart, 0)
        local safeDur = SafeNumber(cdDur, 0)
        if safeStart > 0 and safeDur > 0 then
          safeStart, safeDur = NormalizeCooldownPair(safeStart, safeDur)
        end
        if isSpecialCooldownBinding then
          bd._activeCooldownSig, bd._activeCooldownStart, bd._activeCooldownDur, bd._activeCooldownEnd = nil, nil, nil, nil
          cooldownLocks[lockKey] = nil
        else
          local activeSig = tostring(bd._activeCooldownSig or "")
          local activeStart = SafeNumber(bd._activeCooldownStart, 0)
          local activeDur = SafeNumber(bd._activeCooldownDur, 0)
          local activeEnd = SafeNumber(bd._activeCooldownEnd, 0)
          local lock = cooldownLocks[lockKey]
          local lockSig = lock and tostring(lock.sig or "") or ""
          local lockStart = lock and SafeNumber(lock.start, 0) or 0
          local lockDur = lock and SafeNumber(lock.dur, 0) or 0
          local lockEnd = lock and SafeNumber(lock.endsAt, 0) or 0
          if activeSig ~= "" and actionSig ~= "none" and activeSig ~= actionSig then
            bd._activeCooldownSig, bd._activeCooldownStart, bd._activeCooldownDur, bd._activeCooldownEnd = nil, nil, nil, nil
            activeSig, activeStart, activeDur, activeEnd = "", 0, 0, 0
          end
          if safeStart > 0 and safeDur > 0 then
            local remain = math.max(0, (safeStart + safeDur) - now)
            bd._activeCooldownSig = actionSig
            bd._activeCooldownStart = safeStart
            bd._activeCooldownDur = safeDur
            bd._activeCooldownEnd = now + remain
            cooldownLocks[lockKey] = {
              sig = actionSig,
              start = safeStart,
              dur = safeDur,
              endsAt = now + remain,
            }
          else
            if ((activeSig == actionSig) or (actionSig == "none" and activeSig ~= ""))
               and activeStart > 0 and activeDur > 0 and activeEnd > now + 0.05 then
              safeStart, safeDur = activeStart, activeDur
            elseif ((lockSig == actionSig) or (actionSig == "none" and lockSig ~= ""))
               and lockStart > 0 and lockDur > 0 and lockEnd > now + 0.05 then
              safeStart, safeDur = lockStart, lockDur
              bd._activeCooldownSig = lockSig
              bd._activeCooldownStart = lockStart
              bd._activeCooldownDur = lockDur
              bd._activeCooldownEnd = lockEnd
            else
              bd._activeCooldownSig, bd._activeCooldownStart, bd._activeCooldownDur, bd._activeCooldownEnd = nil, nil, nil, nil
              if actionSig ~= "none" then
                cooldownLocks[lockKey] = nil
              end
            end
          end
        end

        local specCdStart = SafeNumber(bd._specCdStart, 0)
        local specCdDur = SafeNumber(bd._specCdDur, 0)
        local specCdRemain = 0
        if CooldownModule and CooldownModule.GetSpecialRemain then
          specCdRemain = SafeNumber(CooldownModule.GetSpecialRemain(bd, now), 0)
        else
          specCdRemain = (bd._specCdShown == true and specCdStart > 0 and specCdDur > 0)
              and math.max(0, (specCdStart + specCdDur) - now) or 0
        end
        local specialTextMode = isSpecialCooldownBinding or (specCdRemain > 0)

        local safeCStart = SafeNumber(chargeStart, 0)
        local safeCDur = SafeNumber(chargeDur, 0)
        local safeCharges = SafeNumber(charges, nil)
        local safeMaxCharges = SafeNumber(maxCharges, nil)
        local safeStackCount = SafeNumber(stackCount, nil)
        local displayStart, displayDur = safeStart, safeDur
        if specCdRemain > 0 then
          displayStart, displayDur = specCdStart, specCdDur
        end
        local hasChargeRecharge = (safeCStart > 0 and safeCDur > 0 and safeCharges ~= nil and safeMaxCharges ~= nil and safeCharges < safeMaxCharges)
        if hasChargeRecharge then
          local cdRemain = (safeStart > 0 and safeDur > 0) and math.max(0, (safeStart + safeDur) - now) or 0
          local chargeRemain = math.max(0, (safeCStart + safeCDur) - now)
          -- Prefer the longer-running timer so we do not drop to blank after GCD.
          if chargeRemain > cdRemain then
            displayStart, displayDur = safeCStart, safeCDur
          end
        end
        if displayStart > 0 and displayDur > 0 then
          local remain = math.max(0, (displayStart + displayDur) - now)
          if specialTextMode then
            -- Special cooldowns: text-first cooldown display; avoid spiral artifacts.
            btn.cooldown:Clear()
          else
            btn.cooldown:SetCooldown(displayStart, displayDur)
          end
          if specialTextMode and remain > 0 then
            if btn.icon and btn.icon.SetDesaturated then
              btn.icon:SetDesaturated(true)
            end
            if btn.disabledTint then
              btn.disabledTint:Show()
            end
          else
            if btn.icon and btn.icon.SetDesaturated then
              btn.icon:SetDesaturated(false)
            end
            if btn.disabledTint then
              btn.disabledTint:Hide()
            end
          end
          if btn.cooldownText then
            if remain >= 10 then
              btn.cooldownText:SetText(tostring(math.floor(remain + 0.5)))
            elseif remain > 0 then
              btn.cooldownText:SetText(string.format("%.1f", remain))
            else
              btn.cooldownText:SetText("")
            end
          end
        else
          btn.cooldown:Clear()
          if btn.icon and btn.icon.SetDesaturated then
            btn.icon:SetDesaturated(false)
          end
          if btn.disabledTint then
            btn.disabledTint:Hide()
          end
          if btn.cooldownText then btn.cooldownText:SetText("") end
        end

        if btn.countText then
          local c = safeCharges
          local mc = safeMaxCharges
          local sc = safeStackCount
          if c and mc and mc > 1 then
            btn.countText:SetText(tostring(c))
          elseif sc and sc > 1 then
            btn.countText:SetText(tostring(sc))
          else
            btn.countText:SetText("")
          end
        end
      else
        btn.cooldown:Clear()
        if btn.icon and btn.icon.SetDesaturated then
          btn.icon:SetDesaturated(false)
        end
        if btn.disabledTint then
          btn.disabledTint:Hide()
        end
        if btn.cooldownText then btn.cooldownText:SetText("") end
        if btn.countText then btn.countText:SetText("") end
      end
    end
  end
end

---------------------------------------------------------------------------
-- Update: usability coloring, range, active highlight, proc glow
---------------------------------------------------------------------------
UpdateUsability = function()
  if IndicatorsModule and IndicatorsModule.UpdateUsability then
    IndicatorsModule.UpdateUsability({
      currentModifierState = currentModifierState,
      buttons = buttons,
      CollectGlowingWoWSources = CollectGlowingWoWSources,
      GetLiveActionSlotFromBinding = GetLiveActionSlotFromBinding,
      IsWoWButtonPressed = IsWoWButtonPressed,
      ApplyProcSourceVisual = ApplyProcSourceVisual,
      EnsureProcAnimation = EnsureProcAnimation,
      StopProcAnimation = StopProcAnimation,
    })
    return
  end
  local ms = currentModifierState or "NONE"
  local glowingSources = CollectGlowingWoWSources()
  local glowingSlots = {}
  local glowingSourceBySlot = {}
  for _, src in ipairs(glowingSources) do
    if src and src.slot then
      local nslot = tonumber(src.slot)
      if nslot then
        glowingSlots[nslot] = true
        if not glowingSourceBySlot[nslot] then
          glowingSourceBySlot[nslot] = src
        end
      end
    end
  end

  for _, btn in ipairs(buttons) do
    if btn and btn.bindings then
      local bd = btn.bindings[ms]
      local showPressed = false
      local showProc = false
      local procSource = nil

      if bd and bd.actionSlot and HasAction and HasAction(bd.actionSlot) then
        local slot = GetLiveActionSlotFromBinding(bd) or bd.actionSlot
        bd.actionSlot = slot
        -- Usability coloring
        local usable, noMana = IsUsableAction(slot)
        local inRange = IsActionInRange(slot)
        if inRange == false then
          btn.icon:SetVertexColor(1, 0.1, 0.1)
        elseif not usable then
          btn.icon:SetVertexColor(0.4, 0.4, 0.4)
        elseif noMana then
          btn.icon:SetVertexColor(0.2, 0.2, 1)
        else
          btn.icon:SetVertexColor(1, 1, 1)
        end
      else
        btn.icon:SetVertexColor(1, 1, 1)
      end

      -- Proc / rotation recommendation: show for all glowing source slots.
      local slot = bd and GetLiveActionSlotFromBinding(bd)
      if bd and slot then bd.actionSlot = slot end
      if slot and glowingSlots[slot] then
        showProc = true
        procSource = glowingSourceBySlot[slot]
      end

      -- Keypress indicator: only while mapped WoW button is physically pressed.
      if not showProc and bd and bd.wowFrame and IsWoWButtonPressed(bd.wowFrame) then
        showPressed = true
      end

      -- Keypress highlight/fill
      if showPressed then
        if btn.activeBorder then btn.activeBorder:Show() end
        if btn.activePressFrame then btn.activePressFrame:Hide() end
        if btn.activeFill then btn.activeFill:Hide() end
      else
        if btn.activeBorder then btn.activeBorder:Hide() end
        if btn.activePressFrame then btn.activePressFrame:Hide() end
        if btn.activeFill then btn.activeFill:Hide() end
      end
      -- Proc recommendation glow (golden)
      if showProc then
        ApplyProcSourceVisual(btn, procSource and procSource.frame or nil)
        if btn.borderFrame then btn.borderFrame:Hide() end
        if btn.procBorderFrame then btn.procBorderFrame:Hide() end
        if btn.procBorder then btn.procBorder:Show() end
        EnsureProcAnimation(btn)
        if btn.procAnimGroup and not btn._procAnimPlaying then
          btn.procAnimGroup:Play()
          btn._procAnimPlaying = true
        end
      else
        if btn.borderFrame then btn.borderFrame:Show() end
        if btn.procBorderFrame then btn.procBorderFrame:Hide() end
        StopProcAnimation(btn)
        btn.procBorder:Hide()
      end
    end
  end
end

---------------------------------------------------------------------------
-- Position / Scale helpers
---------------------------------------------------------------------------
local function ResetPositions()
  DB.sectionPositions = {}
  for key, f in pairs(sectionFrames) do
    f:ClearAllPoints()
    local defaults = { main = { -150, 0 }, dpad = { 150, 60 }, numpad = { 150, -80 } }
    local d = defaults[key]
    f:SetPoint("CENTER", UIParent, "CENTER", d[1], d[2])
  end
  print(ADDON_NAME .. ": Positions reset")
end

local function SetSectionScale(sKey, s, silent)
  s = tonumber(s) or 1.0
  if not SECTIONS[sKey] then
    if not silent then
      print(ADDON_NAME .. ": Unknown section '" .. sKey .. "'. Use: main, dpad, numpad")
    end
    return
  end
  DB.settings[sKey].scale = s
  if sectionFrames[sKey] then sectionFrames[sKey]:SetScale(s) end
  if not silent then
    print(ADDON_NAME .. ": " .. sKey .. " scale = " .. tostring(s))
  end
end

local function SetAllScales(s, silent)
  for key in pairs(SECTIONS) do SetSectionScale(key, s, silent) end
end

local function ReflowLayout()
  for sKey, f in pairs(sectionFrames) do
    local def = SECTIONS[sKey]
    if f and def then
      f:SetSize(def.cols * BTN_STEP, def.rows * BTN_STEP)
    end
  end
  for _, btn in ipairs(buttons) do
    if btn and btn.info and sectionFrames[btn.info.section] then
      btn:ClearAllPoints()
      btn:SetPoint("TOPLEFT", sectionFrames[btn.info.section], "TOPLEFT", btn.info.col * BTN_STEP, -btn.info.row * BTN_STEP)
    end
  end
end

local function SetPadding(p, silent)
  local n = tonumber(p)
  if not n or n < 0 then
    if not silent then
      print(ADDON_NAME .. ": Invalid padding '" .. tostring(p) .. "'. Use 0 or greater.")
    end
    return
  end
  n = math.floor(n + 0.5)
  DB.settings.padding = n
  BTN_SPACING = n
  BTN_STEP = BTN_SIZE + BTN_SPACING
  ReflowLayout()
  if not silent then
    print(ADDON_NAME .. ": Padding = " .. tostring(n))
  end
end

local function SetSectionVisible(sKey, visible, silent)
  if not SECTIONS[sKey] then return end
  DB.settings[sKey].visible = visible and true or false
  if sectionFrames[sKey] then
    if visible then sectionFrames[sKey]:Show() else sectionFrames[sKey]:Hide() end
  end
  if not silent then
    print(ADDON_NAME .. ": " .. sKey .. " " .. (visible and "shown" or "hidden"))
  end
end

local function SetKeyTextSize(v, silent)
  local n = tonumber(v) or DEFAULT_SETTINGS.keyTextSize
  n = math.max(6, math.min(24, math.floor(n + 0.5)))
  DB.settings.keyTextSize = n
  RefreshAllVisualSettings()
  if not silent then
    print(ADDON_NAME .. ": key text size = " .. tostring(n))
  end
end

local function SetEffectSetting(kind, field, v, minV, maxV, silent)
  DB.settings[kind] = DB.settings[kind] or {}
  local n = tonumber(v)
  if not n then return end
  n = math.max(minV, math.min(maxV, n))
  if field == "z" or field == "anim" or field == "style" then n = math.floor(n + 0.5) end
  DB.settings[kind][field] = n
  RefreshAllVisualSettings()
  if kind == "proc" then
    for _, btn in ipairs(buttons) do
      StopProcAnimation(btn)
    end
    if UpdateUsability then
      UpdateUsability()
    end
  end
  if not silent then
    print(ADDON_NAME .. ": " .. kind .. " " .. field .. " = " .. tostring(n))
  end
end

local function ResetIndicatorVisuals(silent)
  DB.settings.keydown.width = DEFAULT_SETTINGS.keydown.width
  DB.settings.keydown.height = DEFAULT_SETTINGS.keydown.height
  DB.settings.keydown.alpha = DEFAULT_SETTINGS.keydown.alpha
  DB.settings.keydown.z = DEFAULT_SETTINGS.keydown.z
  DB.settings.proc.width = DEFAULT_SETTINGS.proc.width
  DB.settings.proc.height = DEFAULT_SETTINGS.proc.height
  DB.settings.proc.alpha = DEFAULT_SETTINGS.proc.alpha
  DB.settings.proc.z = DEFAULT_SETTINGS.proc.z
  DB.settings.proc.anim = DEFAULT_SETTINGS.proc.anim
  DB.settings.proc.style = DEFAULT_SETTINGS.proc.style
  RefreshAllVisualSettings()
  if not silent then
    print(ADDON_NAME .. ": keydown/proc visuals reset to defaults")
  end
end

local configFrame
local configCategoryID
local configCategory
local configRegisteredSettings
local configRegisteredLegacy
local configWidgets = {}

local function CreateConfigSlider(parent, label, minVal, maxVal, step, fmt, getValue, setValue, yOffset)
  if ConfigModule and ConfigModule.CreateConfigSlider then
    return ConfigModule.CreateConfigSlider(parent, label, minVal, maxVal, step, fmt, getValue, setValue, yOffset)
  end
  local container = CreateFrame("Frame", nil, parent)
  container:SetSize(340, 40)
  container:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOffset)

  local title = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
  title:SetText(label)

  local valueText = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  valueText:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)

  local slider = CreateFrame("Slider", nil, container, "OptionsSliderTemplate")
  slider:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -14)
  slider:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, -14)
  slider:SetMinMaxValues(minVal, maxVal)
  slider:SetValueStep(step)
  slider:SetObeyStepOnDrag(true)
  if slider.Low then slider.Low:SetText("") end
  if slider.High then slider.High:SetText("") end
  if slider.Text then slider.Text:SetText("") end

  slider:SetScript("OnValueChanged", function(self, val)
    if not self._ready then return end
    local rounded = step < 1 and (math.floor((val / step) + 0.5) * step) or math.floor(val + 0.5)
    valueText:SetText(string.format(fmt, rounded))
    setValue(rounded)
  end)

  local function Refresh()
    local v = getValue()
    slider._ready = false
    slider:SetValue(v)
    valueText:SetText(string.format(fmt, v))
    slider._ready = true
  end
  return container, Refresh
end

local function CreateConfigCheckbox(parent, label, getValue, setValue, x, y)
  if ConfigModule and ConfigModule.CreateConfigCheckbox then
    return ConfigModule.CreateConfigCheckbox(parent, label, getValue, setValue, x, y)
  end
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  local text = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
  text:SetText(label)
  cb:SetScript("OnClick", function(self)
    setValue(self:GetChecked() and true or false)
  end)
  local function Refresh()
    cb:SetChecked(getValue() and true or false)
  end
  return cb, Refresh
end

local function CreateConfigDropdown(parent, label, options, getValue, setValue, yOffset)
  if ConfigModule and ConfigModule.CreateConfigDropdown then
    return ConfigModule.CreateConfigDropdown(parent, label, options, getValue, setValue, yOffset)
  end
  local container = CreateFrame("Frame", nil, parent)
  container:SetSize(340, 56)
  container:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOffset)

  local title = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
  title:SetText(label)

  local dd = CreateFrame("Frame", nil, container, "UIDropDownMenuTemplate")
  dd:SetPoint("TOPLEFT", container, "TOPLEFT", -16, -16)
  UIDropDownMenu_SetWidth(dd, 180)
  UIDropDownMenu_JustifyText(dd, "LEFT")

  UIDropDownMenu_Initialize(dd, function(self, level)
    for _, opt in ipairs(options) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = opt.text
      info.value = opt.value
      info.checked = (getValue() == opt.value)
      info.func = function()
        UIDropDownMenu_SetSelectedValue(dd, opt.value)
        setValue(opt.value)
      end
      UIDropDownMenu_AddButton(info, level)
    end
  end)

  local function Refresh()
    local v = getValue()
    UIDropDownMenu_SetSelectedValue(dd, v)
    for _, opt in ipairs(options) do
      if opt.value == v then
        UIDropDownMenu_SetText(dd, opt.text)
        break
      end
    end
  end

  return container, Refresh
end

local function CreateConfigFrame()
  if configFrame then return configFrame end
  configFrame = CreateFrame("Frame", ADDON_NAME .. "ConfigPanel")
  configFrame.name = "AzeronDisplay"
  configFrame:SetSize(560, 620)
  configFrame:Hide()

  local title = configFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("AzeronDisplay")

  local subtitle = configFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
  subtitle:SetText("Layout, key text, and proc/key-press indicator settings")

  local scroll = CreateFrame("ScrollFrame", nil, configFrame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 12, -54)
  scroll:SetPoint("BOTTOMRIGHT", -28, 10)

  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(500, 1080)
  scroll:SetScrollChild(content)

  local sectionLayout = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  sectionLayout:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -8)
  sectionLayout:SetText("Layout")

  local _, refreshPadding = CreateConfigSlider(content, "Button Padding", 0, 10, 1, "%.0f",
    function() return BTN_SPACING end,
    function(v) SetPadding(v, true) end,
    -36)
  configWidgets[#configWidgets + 1] = refreshPadding

  local _, refreshMainScale = CreateConfigSlider(content, "Main Scale", 0.4, 2.0, 0.05, "%.2f",
    function() return DB and DB.settings and DB.settings.main and DB.settings.main.scale or 1.0 end,
    function(v) SetSectionScale("main", v, true) end,
    -86)
  configWidgets[#configWidgets + 1] = refreshMainScale

  local _, refreshDpadScale = CreateConfigSlider(content, "D-Pad Scale", 0.4, 2.0, 0.05, "%.2f",
    function() return DB and DB.settings and DB.settings.dpad and DB.settings.dpad.scale or 1.0 end,
    function(v) SetSectionScale("dpad", v, true) end,
    -136)
  configWidgets[#configWidgets + 1] = refreshDpadScale

  local _, refreshMouseScale = CreateConfigSlider(content, "Mouse Side Scale", 0.4, 2.0, 0.05, "%.2f",
    function() return DB and DB.settings and DB.settings.numpad and DB.settings.numpad.scale or 1.0 end,
    function(v) SetSectionScale("numpad", v, true) end,
    -186)
  configWidgets[#configWidgets + 1] = refreshMouseScale

  local _, refreshMainVisible = CreateConfigCheckbox(content, "Show Main",
    function() return DB and DB.settings and DB.settings.main and DB.settings.main.visible ~= false end,
    function(v) SetSectionVisible("main", v, true) end,
    20, -236)
  configWidgets[#configWidgets + 1] = refreshMainVisible

  local _, refreshDpadVisible = CreateConfigCheckbox(content, "Show D-Pad",
    function() return DB and DB.settings and DB.settings.dpad and DB.settings.dpad.visible ~= false end,
    function(v) SetSectionVisible("dpad", v, true) end,
    20, -264)
  configWidgets[#configWidgets + 1] = refreshDpadVisible

  local _, refreshMouseVisible = CreateConfigCheckbox(content, "Show Mouse Side",
    function() return DB and DB.settings and DB.settings.numpad and DB.settings.numpad.visible ~= false end,
    function(v) SetSectionVisible("numpad", v, true) end,
    20, -292)
  configWidgets[#configWidgets + 1] = refreshMouseVisible

  local sectionText = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  sectionText:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -342)
  sectionText:SetText("Text")

  local _, refreshKeyTextSize = CreateConfigSlider(content, "Button Text Size", 6, 24, 1, "%.0f",
    function() return DB and DB.settings and DB.settings.keyTextSize or DEFAULT_SETTINGS.keyTextSize end,
    function(v) SetKeyTextSize(v, true) end,
    -370)
  configWidgets[#configWidgets + 1] = refreshKeyTextSize

  local sectionKeyDown = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  sectionKeyDown:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -420)
  sectionKeyDown:SetText("Key Press Indicator (white border)")

  local _, refreshKDWidth = CreateConfigSlider(content, "Keydown Width", 0, 30, 1, "%.0f",
    function() return DB and DB.settings and DB.settings.keydown and DB.settings.keydown.width or DEFAULT_SETTINGS.keydown.width end,
    function(v) SetEffectSetting("keydown", "width", v, 0, 30, true) end,
    -448)
  configWidgets[#configWidgets + 1] = refreshKDWidth

  local _, refreshKDHeight = CreateConfigSlider(content, "Keydown Height", 0, 30, 1, "%.0f",
    function() return DB and DB.settings and DB.settings.keydown and DB.settings.keydown.height or DEFAULT_SETTINGS.keydown.height end,
    function(v) SetEffectSetting("keydown", "height", v, 0, 30, true) end,
    -498)
  configWidgets[#configWidgets + 1] = refreshKDHeight

  local _, refreshKDAlpha = CreateConfigSlider(content, "Keydown Intensity", 0.1, 1.0, 0.05, "%.2f",
    function() return DB and DB.settings and DB.settings.keydown and DB.settings.keydown.alpha or DEFAULT_SETTINGS.keydown.alpha end,
    function(v) SetEffectSetting("keydown", "alpha", v, 0.1, 1.0, true) end,
    -548)
  configWidgets[#configWidgets + 1] = refreshKDAlpha

  local _, refreshKDZ = CreateConfigSlider(content, "Keydown Z", -8, 7, 1, "%.0f",
    function() return DB and DB.settings and DB.settings.keydown and DB.settings.keydown.z or DEFAULT_SETTINGS.keydown.z end,
    function(v) SetEffectSetting("keydown", "z", v, -8, 7, true) end,
    -598)
  configWidgets[#configWidgets + 1] = refreshKDZ

  local sectionProc = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  sectionProc:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -648)
  sectionProc:SetText("Rotation Proc Indicator (gold border)")

  local _, refreshProcWidth = CreateConfigSlider(content, "Proc Width", 0, 50, 1, "%.0f",
    function() return DB and DB.settings and DB.settings.proc and DB.settings.proc.width or DEFAULT_SETTINGS.proc.width end,
    function(v) SetEffectSetting("proc", "width", v, 0, 50, true) end,
    -676)
  configWidgets[#configWidgets + 1] = refreshProcWidth

  local _, refreshProcHeight = CreateConfigSlider(content, "Proc Height", 0, 50, 1, "%.0f",
    function() return DB and DB.settings and DB.settings.proc and DB.settings.proc.height or DEFAULT_SETTINGS.proc.height end,
    function(v) SetEffectSetting("proc", "height", v, 0, 50, true) end,
    -726)
  configWidgets[#configWidgets + 1] = refreshProcHeight

  local _, refreshProcAlpha = CreateConfigSlider(content, "Proc Intensity", 0.1, 2.0, 0.05, "%.2f",
    function() return DB and DB.settings and DB.settings.proc and DB.settings.proc.alpha or DEFAULT_SETTINGS.proc.alpha end,
    function(v) SetEffectSetting("proc", "alpha", v, 0.1, 2.0, true) end,
    -776)
  configWidgets[#configWidgets + 1] = refreshProcAlpha

  local _, refreshProcZ = CreateConfigSlider(content, "Proc Z", -8, 7, 1, "%.0f",
    function() return DB and DB.settings and DB.settings.proc and DB.settings.proc.z or DEFAULT_SETTINGS.proc.z end,
    function(v) SetEffectSetting("proc", "z", v, -8, 7, true) end,
    -826)
  configWidgets[#configWidgets + 1] = refreshProcZ

  local _, refreshProcAnim = CreateConfigDropdown(content, "Proc Animation",
    PROC_ANIMATIONS,
    function() return DB and DB.settings and DB.settings.proc and DB.settings.proc.anim or DEFAULT_SETTINGS.proc.anim end,
    function(v) SetEffectSetting("proc", "anim", v, 1, 6, true) end,
    -876)
  configWidgets[#configWidgets + 1] = refreshProcAnim

  configFrame:SetScript("OnShow", function()
    for _, fn in ipairs(configWidgets) do fn() end
  end)

  if Settings and Settings.RegisterCanvasLayoutCategory and not configRegisteredSettings then
    local category = Settings.RegisterCanvasLayoutCategory(configFrame, "AzeronDisplay", "AzeronDisplay")
    Settings.RegisterAddOnCategory(category)
    configCategory = category
    configRegisteredSettings = true
    if category and category.GetID then
      configCategoryID = category:GetID()
    end
  end

  if InterfaceOptions_AddCategory and not configRegisteredLegacy then
    InterfaceOptions_AddCategory(configFrame)
    configRegisteredLegacy = true
  end
  return configFrame
end

local function OpenConfigFrame()
  local f = CreateConfigFrame()
  if Settings and Settings.OpenToCategory then
    local target = configCategoryID or configCategory
    if target then
      Settings.OpenToCategory(target)
      Settings.OpenToCategory(target)
      return
    end
  end
  if InterfaceOptionsFrame_OpenToCategory then
    InterfaceOptionsFrame_OpenToCategory(f)
    InterfaceOptionsFrame_OpenToCategory(f)
  elseif f then
    f:Show()
    f:Raise()
  end
end

---------------------------------------------------------------------------
-- Event / update anchor
---------------------------------------------------------------------------
local anchor = CreateFrame("Frame", ADDON_NAME .. "Anchor", UIParent)
anchor:SetSize(1, 1)
anchor:SetPoint("CENTER")
anchor:RegisterEvent("PLAYER_LOGIN")
anchor:RegisterEvent("UPDATE_BINDINGS")
anchor:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
anchor:RegisterEvent("SPELL_UPDATE_COOLDOWN")
anchor:RegisterEvent("SPELL_UPDATE_CHARGES")
anchor:RegisterEvent("ACTIONBAR_UPDATE_USABLE")
anchor:RegisterEvent("ACTIONBAR_UPDATE_STATE")
anchor:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
anchor:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
anchor:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
anchor:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
anchor:RegisterEvent("PLAYER_REGEN_ENABLED")
anchor:RegisterEvent("PLAYER_ENTERING_WORLD")
local pendingBindingRefresh = false
anchor:SetScript("OnEvent", function(self, event)
  if event == "PLAYER_LOGIN" then
    AzeronDisplayDB = AzeronDisplayDB or {}
    DB = AzeronDisplayDB
    DB.keyMap = DB.keyMap or {}
    DB.sectionPositions = DB.sectionPositions or {}
    EnsureSettingsDefaults()
    DB.positions = nil -- wipe old per-button positions

    BTN_SPACING = DB.settings.padding or DEFAULT_SETTINGS.padding
    BTN_STEP = BTN_SIZE + BTN_SPACING

    for _, sKey in ipairs(SECTION_ORDER) do
      CreateSectionFrame(sKey)
    end
    CreateConfigFrame()

    UpdateBindings()
    RefreshAllVisualSettings()
    ReflowLayout()
    ApplyEditModeVisuals()

    -- Auto-refresh ticker (cooldowns/usability only; avoid full binding rebuild churn)
    C_Timer.NewTicker(2, function()
      for _, f in pairs(sectionFrames) do
        if f:IsShown() then
          UpdateCooldowns()
          UpdateUsability()
          return
        end
      end
    end)
  elseif event == "UPDATE_BINDINGS" then
    UpdateBindings()
  elseif event == "ACTIONBAR_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_CHARGES" then
    UpdateCooldowns()
  elseif event == "ACTIONBAR_SLOT_CHANGED" or event == "ACTIONBAR_PAGE_CHANGED" then
    -- During combat these events can thrash transient binding/slot reads.
    -- Keep runtime visuals updating and defer full binding rebuild until combat ends.
    if InCombatLockdown and InCombatLockdown() then
      pendingBindingRefresh = true
      UpdateCooldowns()
    else
      UpdateBindings()
    end
    UpdateUsability()
  elseif event == "PLAYER_REGEN_ENABLED" then
    if pendingBindingRefresh then
      pendingBindingRefresh = false
      UpdateBindings()
    end
    UpdateCooldowns()
    UpdateUsability()
  elseif event == "ACTIONBAR_UPDATE_USABLE"
      or event == "ACTIONBAR_UPDATE_STATE"
      or event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW"
      or event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE"
      or event == "PLAYER_ENTERING_WORLD" then
    UpdateUsability()
  end
end)

-- Fast OnUpdate: modifier detection + usability/range (throttled to ~20fps)
local updateAccum = 0
local cooldownAccum = 0
anchor:SetScript("OnUpdate", function(self, elapsed)
  updateAccum = updateAccum + elapsed
  cooldownAccum = cooldownAccum + elapsed
  if updateAccum < 0.02 then return end
  updateAccum = 0

  local newMod = GetCurrentModifierState()
  if newMod ~= currentModifierState then
    currentModifierState = newMod
    for _, btn in ipairs(buttons) do
      if btn and btn.bindings then
        local bd = btn.bindings[newMod]
        btn.icon:SetTexture(bd and bd.icon or nil)
        local keyText = GetDisplayKeyText(GetBaseKey(btn.keyID))
        if bd and bd.name and bd.name ~= "Unbound" and keyText ~= "" then
          btn.keyLabel:SetText(keyText)
        else
          btn.keyLabel:SetText("")
        end
      end
    end
    UpdateCooldowns()
  end
  if cooldownAccum >= 0.10 then
    cooldownAccum = 0
    UpdateCooldowns()
  end
  UpdateUsability()
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
NS.api = NS.api or {}
NS.api.HandleSlashCommand = function(msg)
  local cmd, rest = "", ""
  if msg and msg:match("%S") then
    cmd, rest = msg:lower():match("^%s*(%S+)%s*(.-)%s*$")
    cmd = cmd or ""
    rest = rest or ""
  end

  if cmd == "help" then
    print(ADDON_NAME .. " Commands:")
    print("  /azeron — Toggle all sections")
    print("  /azeron show <section> — Show section (main/dpad/numpad)")
    print("  /azeron hide <section> — Hide section")
    print("  /azeron edit — Toggle edit mode (drag sections)")
    print("  /azeron reset — Reset section positions")
    print("  /azeron scale <section> <number> — Set section scale")
    print("  /azeron scale <number> — Set all scales")
    print("  /azeron padding <number> — Set button spacing")
    print("  /azeron textsize <number> — Set key text size")
    print("  /azeron keydown <width|height|alpha|z> <value> — Set key-press indicator")
    print("  /azeron proc <width|height|alpha|z|anim> <value> — Set proc indicator")
    print("  /azeron indicatorsreset — Reset keydown/proc visuals")
    print("  /azeron config — Open AddOns config panel")
    print("  /azeron resetkeys — Reset all base key mappings")
    print("  /azeron getbindicon <key> — Debug binding info")
    print("  /azeron keystate <key> — Direct WoW key->action button state (single source)")
    print("  /azeron cddebug [key] — Dump cooldown/charge state (optional key filter)")
    print("  /azeron procdebug — Show active rotation recommendations")
    print("  /azeron procsource — Dump source WoW glow frame style info")
    print("  Right-click any button to change its base key.")

  elseif cmd == "edit" then
    ToggleEditMode()

  elseif cmd == "reset" then
    ResetPositions()

  elseif cmd == "config" then
    OpenConfigFrame()

  elseif cmd == "scale" then
    local parts = {}
    for w in rest:gmatch("%S+") do parts[#parts + 1] = w end
    if #parts == 2 then
      SetSectionScale(parts[1], tonumber(parts[2]))
    elseif #parts == 1 then
      local val = tonumber(parts[1])
      if val then SetAllScales(val) else print("Usage: /azeron scale [section] <number>") end
    else
      print("Usage: /azeron scale [section] <number>")
    end

  elseif cmd == "padding" then
    if rest == "" then
      print("Usage: /azeron padding <number>  (current: " .. BTN_SPACING .. ")")
    else
      SetPadding(rest)
    end

  elseif cmd == "textsize" then
    if rest == "" then
      print("Usage: /azeron textsize <number>")
    else
      SetKeyTextSize(rest)
    end

  elseif cmd == "keydown" or cmd == "proc" then
    local field, val = rest:match("^(%S+)%s+(%S+)$")
    if not field or not val then
      print("Usage: /azeron " .. cmd .. " <width|height|alpha|z|anim> <value>")
      return
    end
    field = field:lower()
    if field == "width" then
      local maxW = (cmd == "proc") and 50 or 30
      SetEffectSetting(cmd, "width", val, 0, maxW)
    elseif field == "height" then
      local maxH = (cmd == "proc") and 50 or 30
      SetEffectSetting(cmd, "height", val, 0, maxH)
    elseif field == "alpha" then
      local maxA = (cmd == "proc") and 2.0 or 1.0
      SetEffectSetting(cmd, "alpha", val, 0.1, maxA)
    elseif field == "z" then
      SetEffectSetting(cmd, "z", val, -8, 7)
    elseif field == "anim" and cmd == "proc" then
      SetEffectSetting(cmd, "anim", val, 1, 6)
    else
      print("Usage: /azeron " .. cmd .. " <width|height|alpha|z|anim> <value>")
    end

  elseif cmd == "indicatorsreset" then
    ResetIndicatorVisuals()

  elseif cmd == "show" then
    local sec = rest:lower()
    if sectionFrames[sec] then
      SetSectionVisible(sec, true)
    else print("Usage: /azeron show main|dpad|numpad") end

  elseif cmd == "hide" then
    local sec = rest:lower()
    if sectionFrames[sec] then
      SetSectionVisible(sec, false)
    else print("Usage: /azeron hide main|dpad|numpad") end

  elseif cmd == "resetkeys" then
    wipe(DB.keyMap)
    currentModifierState = nil
    UpdateBindings()
    print(ADDON_NAME .. ": All base key mappings reset")

  elseif cmd == "getbindicon" then
    if not rest or rest == "" then
      print("Usage: /azeron getbindicon <key>")
      return
    end
    local inputKey = rest:upper():gsub("%+", "-"):gsub("%s+", "-")
    local resolvedKey = inputKey
    for _, info in ipairs(keyLayout) do
      if info.id == inputKey then
        resolvedKey = GetBaseKey(inputKey)
        break
      end
    end
    local dn, icon, slot, sn, wowFrame = GetBindingInfo(resolvedKey, nil)
    local frameName = wowFrame and wowFrame:GetName() or "none"
    local rawBinding = GetBindingAction and GetBindingAction(resolvedKey) or nil
    print(ADDON_NAME .. ": input=" .. inputKey
      .. " baseKey=" .. tostring(resolvedKey)
      .. " rawBinding=" .. tostring(rawBinding or "-")
      .. " -> " .. tostring(dn)
      .. " | icon=" .. tostring(icon)
      .. " | slot=" .. tostring(slot)
      .. " | frame=" .. frameName)

  elseif cmd == "keystate" then
    local key = (rest and rest ~= "") and rest:upper():gsub("%+", "-"):gsub("%s+", "-") or nil
    if not key then
      print("Usage: /azeron keystate <key>")
      return
    end
    local raw, frame, slot, bar, button = ResolveWoWBindingFrameAndSlot(key)
    if not raw then
      print(ADDON_NAME .. ": key=" .. key .. " rawBinding=none")
      return
    end

    local actionType, actionID = nil, nil
    local cdStart, cdDur = 0, 0
    local spellCdRemain = 0
    local apiCdRemain = 0
    local apiDetail = nil
    local charges, maxCharges, cStart, cDur = nil, nil, nil, nil
    local count = nil
    local wowShown, wowCdRemain = false, 0
    local icon = nil
    local proc, pressed = false, false
    local actionBtnFrameName, actionBtnSlot = "none", nil
    local actionBtnType, actionBtnID = nil, nil
    local actionBtnCdRemain = 0

    if slot then
      if GetActionInfo then
        local ok, at, aid = pcall(GetActionInfo, slot)
        if ok then actionType, actionID = at, aid end
      end
      if GetActionCooldown then
        local ok, s, d = pcall(GetActionCooldown, slot)
        if ok then cdStart, cdDur = SafeNumber(s, 0), SafeNumber(d, 0) end
      end
      local spellIDsLive = GetActionSpellCandidates(slot)
      local fallbackSpellID = spellIDsLive[1] or ((actionType == "spell") and actionID or nil)
      local ss, sd, spellID, spellIDs = GetSpellCooldownFromActionSlot(slot, fallbackSpellID)
      ss, sd = SafeNumber(ss, 0), SafeNumber(sd, 0)
      if ss > 0 and sd > 0 then
        local now = GetTime and GetTime() or 0
        spellCdRemain = math.max(0, (ss + sd) - now)
        if cdStart <= 0 or cdDur <= 0 then
          cdStart, cdDur = ss, sd
        end
      end
      if not actionID and spellID then actionID = spellID end
      local as, ad, apiDet = GetCActionBarCooldown(slot, (actionType == "spell") and actionID or nil)
      apiDetail = apiDet
      as, ad = SafeNumber(as, 0), SafeNumber(ad, 0)
      if as > 0 and ad > 0 then
        local now = GetTime and GetTime() or 0
        apiCdRemain = math.max(0, (as + ad) - now)
        if cdStart <= 0 or cdDur <= 0 then
          cdStart, cdDur = as, ad
        end
      end
      if GetActionCharges then
        local ok, c, mc, cs, cd = pcall(GetActionCharges, slot)
        if ok then
          charges, maxCharges = SafeNumber(c, nil), SafeNumber(mc, nil)
          cStart, cDur = SafeNumber(cs, nil), SafeNumber(cd, nil)
        end
      end
      if GetActionCount then
        local ok, n = pcall(GetActionCount, slot)
        if ok then count = SafeNumber(n, nil) end
      end
      if GetActionTexture then
        icon = GetActionTexture(slot)
      end
    end

    if button then
      local ab = _G["ActionButton" .. tostring(button)]
      if ab then
        actionBtnFrameName = ab:GetName() or actionBtnFrameName
        actionBtnSlot = SafeNumber(ab.action or (ab.GetAttribute and ab:GetAttribute("action")), nil)
        if actionBtnSlot and GetActionInfo then
          local ok, at, aid = pcall(GetActionInfo, actionBtnSlot)
          if ok then actionBtnType, actionBtnID = at, aid end
        end
        if actionBtnSlot and GetActionCooldown then
          local ok, s, d = pcall(GetActionCooldown, actionBtnSlot)
          if ok then
            s, d = SafeNumber(s, 0), SafeNumber(d, 0)
            local now = GetTime and GetTime() or 0
            actionBtnCdRemain = (s > 0 and d > 0) and math.max(0, (s + d) - now) or 0
          end
        end
      end
    end

    if frame then
      icon = GetWoWButtonIconTexture(frame, slot) or icon
      proc = IsWoWButtonGlowing(frame)
      pressed = IsWoWButtonPressed(frame)
      local wowStart, wowDur = GetWoWButtonCooldown({ wowFrame = frame })
      wowStart, wowDur = SafeNumber(wowStart, 0), SafeNumber(wowDur, 0)
      local now = GetTime and GetTime() or 0
      wowCdRemain = (wowStart > 0 and wowDur > 0) and math.max(0, (wowStart + wowDur) - now) or 0
      local cdf = frame.cooldown or frame.Cooldown
      if not cdf and frame.GetName then
        local fn = frame:GetName() or ""
        cdf = _G[fn .. "Cooldown"] or _G[fn .. "SpellCooldown"]
      end
      if cdf and cdf.IsShown then wowShown = cdf:IsShown() and true or false end
    end

    local now = GetTime and GetTime() or 0
    local cdRemain = (cdStart > 0 and cdDur > 0) and math.max(0, (cdStart + cdDur) - now) or 0
    local chargeRemain = (cStart and cDur and cStart > 0 and cDur > 0) and math.max(0, (cStart + cDur) - now) or 0
    local iconMark = GetChatIconMarkup(icon, 14)
    local frameName = frame and frame:GetName() or "none"
    print(ADDON_NAME .. ": key=" .. key
      .. " rawBinding=" .. tostring(raw)
      .. " bar=" .. tostring(bar or "-")
      .. " button=" .. tostring(button or "-")
      .. " slot=" .. tostring(slot or "-")
      .. " frame=" .. tostring(frameName)
      .. " actionBtnFrame=" .. tostring(actionBtnFrameName)
      .. " actionBtnSlot=" .. tostring(actionBtnSlot or "-")
      .. " actionBtnType=" .. tostring(actionBtnType or "-")
      .. " actionBtnID=" .. tostring(actionBtnID or "-")
      .. " actionBtnCd=" .. string.format("%.1f", actionBtnCdRemain)
      .. " actionType=" .. tostring(actionType or "-")
      .. " actionID=" .. tostring(actionID or "-")
      .. " cd=" .. string.format("%.1f", cdRemain)
      .. " spellCd=" .. string.format("%.1f", spellCdRemain)
      .. " apiCd=" .. string.format("%.1f", apiCdRemain)
      .. " apiRef=" .. tostring(apiDetail and apiDetail.ref or "-")
      .. " apiSrc=" .. tostring(apiDetail and apiDetail.source or "-")
      .. " apiStart=" .. string.format("%.1f", SafeNumber(apiDetail and apiDetail.startTime, 0))
      .. " apiDur=" .. string.format("%.1f", SafeNumber(apiDetail and apiDetail.duration, 0))
      .. " apiRec=" .. string.format("%.1f", SafeNumber(apiDetail and apiDetail.timeUntilEndOfStartRecovery, 0))
      .. " apiEnabled=" .. tostring(apiDetail and apiDetail.isEnabled)
      .. " apiOnGCD=" .. tostring(apiDetail and apiDetail.isOnGCD)
      .. " apiMod=" .. tostring(apiDetail and apiDetail.modRate)
      .. " apiCat=" .. tostring(apiDetail and apiDetail.activeCategory)
      .. " wowCd=" .. string.format("%.1f", wowCdRemain)
      .. " wowShown=" .. tostring(wowShown)
      .. " charges=" .. tostring(charges) .. "/" .. tostring(maxCharges)
      .. " chargeCD=" .. string.format("%.1f", chargeRemain)
      .. " spellIDsLive=" .. ((spellIDsLive and #spellIDsLive > 0) and table.concat(spellIDsLive, ",") or "-")
      .. " spellFallback=" .. tostring(fallbackSpellID or "-")
      .. " spellIDs=" .. ((spellIDs and #spellIDs > 0) and table.concat(spellIDs, ",") or "-")
      .. " count=" .. tostring(count)
      .. " proc=" .. tostring(proc)
      .. " pressed=" .. tostring(pressed)
      .. " icon=" .. iconMark)

  elseif cmd == "cddebug" then
    local ms = currentModifierState or "NONE"
    local filter = (rest and rest ~= "") and rest:upper() or nil
    if filter then
      local key = filter:gsub("%+", "-"):gsub("%s+", "-")
      local raw, frame, slot, bar, button = ResolveWoWBindingFrameAndSlot(key)
      if not raw then
        print(ADDON_NAME .. ": cddebug key=" .. key .. " rawBinding=none")
        return
      end
      local now = GetTime and GetTime() or 0
      local msNow = GetCurrentModifierState()
      local lockKey = ((msNow and msNow ~= "NONE") and (msNow .. "-" .. key)) or key
      local lock = cooldownLocks[lockKey] or cooldownLocks[key]
      local cdStart, cdDur = 0, 0
      local apiDetail = nil
      local aidType, aid = nil, nil
      local spellIDs = {}
      if slot and GetActionInfo then
        local okai, at, aID = pcall(GetActionInfo, slot)
        if okai then aidType, aid = at, aID end
      end
      do
        local ids = GetActionSpellCandidates(slot)
        spellIDs = ids
      end
      if slot and GetActionCooldown then
        local ok, s, d = pcall(GetActionCooldown, slot)
        if ok then
          cdStart, cdDur = SafeNumber(s, 0), SafeNumber(d, 0)
        end
      end
      if slot then
        local as, ad, apiDet = GetCActionBarCooldown(slot, spellIDs[1] or ((aidType == "spell") and aid or nil))
        apiDetail = apiDet
        as, ad = SafeNumber(as, 0), SafeNumber(ad, 0)
        if (cdStart <= 0 or cdDur <= 0) and ad > 0 then cdStart, cdDur = as, ad end
      end
      local fallbackSpellID = spellIDs[1] or ((aidType == "spell") and aid or nil)
      local ss, sd, spellID, spellIDsFromCooldown = GetSpellCooldownFromActionSlot(slot, fallbackSpellID)
      ss, sd = SafeNumber(ss, 0), SafeNumber(sd, 0)
      local scRemain = (ss > 0 and sd > 0) and math.max(0, (ss + sd) - now) or 0
      local cdRemain = (cdStart > 0 and cdDur > 0) and math.max(0, (cdStart + cdDur) - now) or 0
      local wowStart, wowDur = GetWoWButtonCooldown({ wowFrame = frame })
      wowStart, wowDur = SafeNumber(wowStart, 0), SafeNumber(wowDur, 0)
      local wowRemain = (wowStart > 0 and wowDur > 0) and math.max(0, (wowStart + wowDur) - now) or 0
      local charges, maxCharges, cStart, cDur = nil, nil, nil, nil
      if slot and GetActionCharges then
        local ok, c, mc, cs, cd = pcall(GetActionCharges, slot)
        if ok then
          charges, maxCharges = SafeNumber(c, nil), SafeNumber(mc, nil)
          cStart, cDur = SafeNumber(cs, nil), SafeNumber(cd, nil)
        end
      end
      local chargeRemain = (cStart and cDur and cStart > 0 and cDur > 0) and math.max(0, (cStart + cDur) - now) or 0
      local icon = GetWoWButtonIconTexture(frame, slot) or (slot and GetActionTexture and GetActionTexture(slot) or nil)
      local iconMark = GetChatIconMarkup(icon, 14)
      local frameName = frame and frame:GetName() or "none"
      print(ADDON_NAME .. ": cddebug key=" .. key
        .. " rawBinding=" .. tostring(raw)
        .. " bar=" .. tostring(bar or "-")
        .. " button=" .. tostring(button or "-")
        .. " slot=" .. tostring(slot or "-")
        .. " frame=" .. tostring(frameName)
        .. " cd=" .. string.format("%.1f", cdRemain)
        .. " spellCd=" .. string.format("%.1f", scRemain)
        .. " wowCd=" .. string.format("%.1f", wowRemain)
        .. " charges=" .. tostring(charges) .. "/" .. tostring(maxCharges)
        .. " chargeCD=" .. string.format("%.1f", chargeRemain)
        .. " spellID=" .. tostring(spellID or "-")
        .. " spellIDsLive=" .. ((spellIDs and #spellIDs > 0) and table.concat(spellIDs, ",") or "-")
        .. " spellFallback=" .. tostring(fallbackSpellID or "-")
        .. " spellIDs=" .. (((spellIDsFromCooldown and #spellIDsFromCooldown > 0) and table.concat(spellIDsFromCooldown, ",")) or ((spellIDs and #spellIDs > 0) and table.concat(spellIDs, ",") or "-"))
        .. " apiRef=" .. tostring(apiDetail and apiDetail.ref or "-")
        .. " apiSrc=" .. tostring(apiDetail and apiDetail.source or "-")
        .. " apiStart=" .. string.format("%.1f", SafeNumber(apiDetail and apiDetail.startTime, 0))
        .. " apiDur=" .. string.format("%.1f", SafeNumber(apiDetail and apiDetail.duration, 0))
        .. " apiRec=" .. string.format("%.1f", SafeNumber(apiDetail and apiDetail.timeUntilEndOfStartRecovery, 0))
        .. " apiEnabled=" .. tostring(apiDetail and apiDetail.isEnabled)
        .. " apiOnGCD=" .. tostring(apiDetail and apiDetail.isOnGCD)
        .. " apiMod=" .. tostring(apiDetail and apiDetail.modRate)
        .. " apiCat=" .. tostring(apiDetail and apiDetail.activeCategory)
        .. " lock=" .. tostring(lock and lock.sig or "-")
        .. " lockRemain=" .. string.format("%.1f", lock and math.max(0, (SafeNumber(lock.endsAt, 0) - now)) or 0)
        .. " icon=" .. iconMark)
      return
    end
    local found = false
    local filterDiag = nil
    for _, btn in ipairs(buttons) do
      if btn and btn.bindings then
        if (not filter) or string.upper(tostring(btn.keyID or "")) == filter then
          local bd = btn.bindings[ms]
          if bd then
            -- Resolve using the same base-key path used by normal updates.
            local baseKey = GetBaseKey(btn.keyID)
            local modKey = (ms == "NONE") and nil or ms
            local dnNow, iconNow, slotNow, snNow, wowFrameNow = GetBindingInfo(baseKey, modKey)
            local debugBD = {
              name = dnNow or bd.name,
              icon = (iconNow ~= nil) and iconNow or bd.icon,
              actionSlot = (slotNow ~= nil) and slotNow or bd.actionSlot,
              spellName = (snNow ~= nil) and snNow or bd.spellName,
              wowFrame = (wowFrameNow ~= nil) and wowFrameNow or bd.wowFrame,
            }

            local slot = GetLiveActionSlotFromBinding(debugBD)
            local cdStart, cdDur = 0, 0
            local charges, maxCharges, cStart, cDur = nil, nil, nil, nil
            local icon = nil

            if slot and GetActionCooldown then
              local ok, s, d = pcall(GetActionCooldown, slot)
              if ok then
                cdStart, cdDur = SafeNumber(s, 0), SafeNumber(d, 0)
              end
            end
            if slot and GetActionCharges then
              local okc, c, mc, cs, cd = pcall(GetActionCharges, slot)
              if okc then
                charges, maxCharges = SafeNumber(c, nil), SafeNumber(mc, nil)
                cStart, cDur = SafeNumber(cs, nil), SafeNumber(cd, nil)
              end
            end
            if slot and GetActionTexture then
              icon = GetActionTexture(slot)
            end

            local now = GetTime and GetTime() or 0
            local cdRemain = (cdStart > 0 and cdDur > 0) and math.max(0, (cdStart + cdDur) - now) or 0
            local cRemain = (cStart and cDur and cStart > 0 and cDur > 0) and math.max(0, (cStart + cDur) - now) or 0
            local actionTypeForSpell, actionIDForSpell = nil, nil
            if slot and GetActionInfo then
              local okai2, at2, aid2 = pcall(GetActionInfo, slot)
              if okai2 then
                actionTypeForSpell, actionIDForSpell = at2, aid2
              end
            end
            local localSpellIDs = GetActionSpellCandidates(slot)
            local localFallbackSpellID = localSpellIDs[1] or ((actionTypeForSpell == "spell") and actionIDForSpell or nil)
            local scStart, scDur, scSpellID = GetSpellCooldownFromActionSlot(slot, localFallbackSpellID)
            scStart, scDur = SafeNumber(scStart, 0), SafeNumber(scDur, 0)
            local spellRemain = (scStart > 0 and scDur > 0) and math.max(0, (scStart + scDur) - now) or 0
            local wowStart, wowDur = GetWoWButtonCooldown(debugBD)
            wowStart, wowDur = SafeNumber(wowStart, 0), SafeNumber(wowDur, 0)
            local wowRemain = (wowStart > 0 and wowDur > 0) and math.max(0, (wowStart + wowDur) - now) or 0
            local capiStart, capiDur = GetCActionBarCooldown(slot)
            capiStart, capiDur = SafeNumber(capiStart, 0), SafeNumber(capiDur, 0)
            local capiRemain = (capiStart > 0 and capiDur > 0) and math.max(0, (capiStart + capiDur) - now) or 0
            local wowShown = false
            local wowIcon = nil
            if debugBD.wowFrame then
              local f = debugBD.wowFrame
              local cdf = f.cooldown or f.Cooldown
              if not cdf and f.GetName then
                local fn = f:GetName() or ""
                cdf = _G[fn .. "Cooldown"] or _G[fn .. "SpellCooldown"]
              end
              if cdf and cdf.IsShown then
                wowShown = cdf:IsShown() and true or false
              end
              wowIcon = GetWoWButtonIconTexture(f, slot)
            end
            local iconMark = GetChatIconMarkup(icon, 14)
            local wowIconMark = GetChatIconMarkup(wowIcon, 14)
            local bdIconMark = GetChatIconMarkup(debugBD.icon, 14)
            local frameName = debugBD.wowFrame and debugBD.wowFrame:GetName() or "none"
            local bindKey = baseKey
            if ms and ms ~= "NONE" then
              bindKey = ms .. "-" .. baseKey
            end
            local rawBinding = GetBindingAction and GetBindingAction(bindKey) or nil
            if rawBinding and tostring(rawBinding):match("^ACTIONBUTTON%d+$") then
              local actionType, actionID = nil, nil
              if slot and GetActionInfo then
                local okai, at, aid = pcall(GetActionInfo, slot)
                if okai then
                  actionType, actionID = at, aid
                end
              end
              local hasActiveCd = (cdRemain > 0) or (spellRemain > 0) or (wowRemain > 0) or (capiRemain > 0) or (cRemain > 0)
              if hasActiveCd then
                print(ADDON_NAME .. ": key=" .. tostring(btn.keyID)
                  .. " baseKey=" .. tostring(baseKey)
                  .. " slot=" .. tostring(debugBD.actionSlot)
                  .. " liveSlot=" .. tostring(slot)
                  .. " frame=" .. tostring(frameName)
                  .. " rawBinding=" .. tostring(rawBinding or "-")
                  .. " actionType=" .. tostring(actionType or "-")
                  .. " actionID=" .. tostring(actionID or "-")
                  .. " spellID=" .. tostring(scSpellID or "-")
                  .. " wowShown=" .. tostring(wowShown)
                  .. " cd=" .. string.format("%.1f", cdRemain)
                  .. " spellCd=" .. string.format("%.1f", spellRemain)
                  .. " wowCd=" .. string.format("%.1f", wowRemain)
                  .. " apiCd=" .. string.format("%.1f", capiRemain)
                  .. " charges=" .. tostring(charges) .. "/" .. tostring(maxCharges)
                  .. " chargeCD=" .. string.format("%.1f", cRemain)
                  .. " slotIcon=" .. iconMark
                  .. " wowIcon=" .. wowIconMark
                  .. " bdIcon=" .. bdIconMark)
                found = true
              elseif filter and string.upper(tostring(btn.keyID or "")) == filter then
                filterDiag = {
                  key = tostring(btn.keyID),
                  baseKey = tostring(baseKey),
                  slot = tostring(slot or "-"),
                  frameName = tostring(frameName),
                  rawBinding = tostring(rawBinding or "-"),
                  cd = cdRemain,
                  spellCd = spellRemain,
                  wowCd = wowRemain,
                  apiCd = capiRemain,
                  chargeCd = cRemain,
                }
              end
            end
          end
        end
      end
    end
    if not found then
      if filter then
        if filterDiag then
          print(ADDON_NAME .. ": no active ACTIONBUTTON cooldown for '" .. filter .. "'"
            .. " (rawBinding=" .. filterDiag.rawBinding
            .. " slot=" .. filterDiag.slot
            .. " frame=" .. filterDiag.frameName
            .. " cd=" .. string.format("%.1f", SafeNumber(filterDiag.cd, 0))
            .. " spellCd=" .. string.format("%.1f", SafeNumber(filterDiag.spellCd, 0))
            .. " wowCd=" .. string.format("%.1f", SafeNumber(filterDiag.wowCd, 0))
            .. " apiCd=" .. string.format("%.1f", SafeNumber(filterDiag.apiCd, 0))
            .. " chargeCD=" .. string.format("%.1f", SafeNumber(filterDiag.chargeCd, 0))
            .. ")")
        else
          print(ADDON_NAME .. ": no active ACTIONBUTTON cooldown for '" .. filter .. "'")
        end
      else
        print(ADDON_NAME .. ": no active ACTIONBUTTON cooldowns to report")
      end
    end

  elseif cmd == "procdebug" then
    -- Scan our Azeron buttons for active proc glow (AssistedCombatHighlightFrame)
    local ms = currentModifierState or "NONE"
    local found = false
    for _, btn in ipairs(buttons) do
      if btn and btn.bindings then
        local bd = btn.bindings[ms]
        if bd and bd.wowFrame and IsWoWButtonGlowing(bd.wowFrame) then
          local frameName = bd.wowFrame:GetName() or "?"
          print(ADDON_NAME .. ": PROC on [" .. btn.keyID .. "] " .. tostring(bd.name) .. " frame=" .. frameName .. " slot=" .. tostring(bd.actionSlot))
          found = true
        end
      end
    end
    if not found then
      print(ADDON_NAME .. ": No active proc detected.")
    end

  elseif cmd == "procsource" then
    local ms = currentModifierState or "NONE"
    local sources = CollectGlowingWoWSources()
    local foundCount = #sources
    local uniqueSources = {}
    local uniqueList = {}
    local bestEntry, bestScore

    for _, src in ipairs(sources) do
      local sourceID = tostring(src.bar or "?") .. ":" .. tostring(src.button or "?") .. ":" .. tostring(src.slot or "?")
      local entry = uniqueSources[sourceID]
      if not entry then
        entry = {
          frameName = src.frameName,
          glowSig = GetGlowFrameSignature(src.frame),
          glowTex = GetGlowTexture(src.frame),
          bar = src.bar,
          button = src.button,
          slot = src.slot,
          iconTex = src.icon,
          keybinds = {},
          hits = 0,
          score = 999999,
        }
        uniqueSources[sourceID] = entry
        uniqueList[#uniqueList + 1] = entry
      end

      local slotNum = tonumber(src.slot)
      if slotNum then
        for _, btn in ipairs(buttons) do
          if btn and btn.bindings then
            local bd = btn.bindings[ms]
            if bd and tonumber(bd.actionSlot) == slotNum then
              local kb = GetDisplayKeyText(GetBaseKey(btn.keyID))
              kb = (kb ~= "" and kb) or "-"
              entry.keybinds[kb] = true
              entry.hits = entry.hits + 1
              local s = GetProcCandidateScore(bd)
              if s < entry.score then
                entry.score = s
              end
            end
          end
        end
      end

      if entry.score < (bestScore or 999999) then
        bestScore = entry.score
        bestEntry = entry
      end
    end

    if foundCount > 0 then
      table.sort(uniqueList, function(a, b)
        local as = a.score or 999999
        local bs = b.score or 999999
        if as ~= bs then return as < bs end
        local ab = tonumber(a.button) or 999
        local bb = tonumber(b.button) or 999
        return ab < bb
      end)
      for _, entry in ipairs(uniqueList) do
        local keybindList = {}
        for kb in pairs(entry.keybinds) do
          keybindList[#keybindList + 1] = kb
        end
        table.sort(keybindList)
        local iconMark = GetChatIconMarkup(entry.iconTex, 14)
        local glowMark = GetChatIconMarkup(entry.glowTex, 14)
        print(ADDON_NAME .. ": source frame=" .. tostring(entry.frameName)
          .. " bar=" .. tostring(entry.bar or "?")
          .. " button=" .. tostring(entry.button or "?")
          .. " slot=" .. tostring(entry.slot)
          .. " keybind=" .. (next(keybindList) and table.concat(keybindList, ",") or "-")
          .. " hits=" .. tostring(entry.hits)
          .. " icon=" .. iconMark
          .. " texPreview=" .. glowMark
          .. " " .. tostring(entry.glowSig or "hl=?"))
      end
      print(ADDON_NAME .. ": procsource candidates=" .. tostring(#uniqueList) .. " (raw hits=" .. tostring(foundCount) .. ")")
      if bestEntry then
        local keybindList = {}
        for kb in pairs(bestEntry.keybinds) do
          keybindList[#keybindList + 1] = kb
        end
        table.sort(keybindList)
        local iconMark = GetChatIconMarkup(bestEntry.iconTex, 14)
        local glowMark = GetChatIconMarkup(bestEntry.glowTex, 14)
        print(ADDON_NAME .. ": selected source"
          .. " keybind=" .. (next(keybindList) and table.concat(keybindList, ",") or "-")
          .. " bar=" .. tostring(bestEntry.bar or "?")
          .. " button=" .. tostring(bestEntry.button or "?")
          .. " slot=" .. tostring(bestEntry.slot or "?")
          .. " icon=" .. iconMark
          .. " texPreview=" .. glowMark
          .. " " .. tostring(bestEntry.glowSig or "hl=?"))
      end
    else
      print(ADDON_NAME .. ": no active source glow frame found")
    end

  elseif cmd == "" then
    local anyVisible = false
    for _, f in pairs(sectionFrames) do
      if f:IsShown() then anyVisible = true; break end
    end
    for key, f in pairs(sectionFrames) do
      if anyVisible then
        f:Hide()
      else
        f:Show()
        DB.settings[key].visible = true
      end
    end
    print(ADDON_NAME .. (anyVisible and ": hidden" or ": shown"))

  else
    print(ADDON_NAME .. ": Unknown command '" .. cmd .. "'. Try /azeron help")
  end
end

NS.api = NS.api or {}
NS.api.UpdateBindings = UpdateBindings
NS.api.UpdateCooldowns = UpdateCooldowns
NS.api.UpdateUsability = UpdateUsability
NS.api.ToggleEditMode = ToggleEditMode
NS.api.OpenConfigFrame = OpenConfigFrame
