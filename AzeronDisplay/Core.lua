-- Azeron Keybind Display - Core.lua
-- Three independent sections: Main Grid, D-Pad, Numpad
-- Buttons mirror WoW action buttons: icons, cooldown spirals, usability, proc glow

local ADDON_NAME = "AzeronDisplay"
local NS = _G.AzeronDisplayNS or {}
_G.AzeronDisplayNS = NS

local DEBUG_TAB_NAME = "DBG_RUN"
local _basePrint = _G.print
local function GetDebugOutputFrame()
  for i = 1, 10 do
    local tab = _G["ChatFrame" .. i .. "Tab"]
    local frame = _G["ChatFrame" .. i]
    if tab and frame and tab.GetText and tab:GetText() == DEBUG_TAB_NAME then
      return frame
    end
  end
  return nil
end
NS.Print = function(...)
  local n = select("#", ...)
  local msg = ""
  for i = 1, n do
    local ok, s = pcall(tostring, select(i, ...))
    local part = (ok and type(s) == "string") and s or "<secret>"
    if msg == "" then
      msg = part
    else
      local okJoin, joined = pcall(function(a, b) return a .. " " .. b end, msg, part)
      msg = okJoin and joined or (msg .. " <secret>")
    end
  end
  local f = GetDebugOutputFrame()
  if f and f.AddMessage then
    local okAdd = pcall(f.AddMessage, f, msg)
    if not okAdd then
      _basePrint(msg)
    end
  else
    _basePrint(msg)
  end
end
local print = NS.Print

AzeronDisplayDB = AzeronDisplayDB or {}
local DB

local editMode = false
local buttons = {}
local sectionFrames = {}
local cooldownLocks = {}
local cddiffTicker = nil

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
local CooldownEngineModule = NS.modules and NS.modules.CooldownEngine or nil
local BindingsModule = NS.modules and NS.modules.Bindings or nil
local IndicatorsModule = NS.modules and NS.modules.Indicators or nil
local ConfigModule = NS.modules and NS.modules.Config or nil
local RuntimeModule = NS.modules and NS.modules.Runtime or nil
local EventsModule = NS.modules and NS.modules.Events or nil

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
    elseif wf.GetName then
      local n = wf:GetName() or ""
      local ab = n:match("^ActionButton(%d+)$")
      if ab then
        slot = SafeNumber(GetRealActionSlot(tonumber(ab)), slot)
      else
        for bar, prefix in pairs(MULTIBAR_PREFIX) do
          local b = n:match("^" .. prefix .. "(%d+)$")
          if b then
            slot = SafeNumber(GetMultiBarActionSlot(bar, tonumber(b)), slot)
            break
          end
        end
      end
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
  return BindingsModule.GetFrameHotKeyText(frame)
end

local function FindActionButtonByKeyLabel(key)
  return BindingsModule.FindActionButtonByKeyLabel(key)
end

local function ResolveWoWBindingFrameAndSlot(bindKey)
  return BindingsModule.ResolveWoWBindingFrameAndSlot(bindKey)
end

if CooldownEngineModule and CooldownEngineModule.Init then
  CooldownEngineModule.Init({
    SafeNumber = SafeNumber,
    NormalizeCooldownPair = NormalizeCooldownPair,
    GetBaseKey = GetBaseKey,
    ResolveWoWBindingFrameAndSlot = ResolveWoWBindingFrameAndSlot,
    GetLiveActionSlotFromBinding = GetLiveActionSlotFromBinding,
    GetActionSpellCandidates = GetActionSpellCandidates,
    GetCActionBarCooldown = GetCActionBarCooldown,
    GetSpellCooldownFromActionSlot = GetSpellCooldownFromActionSlot,
    GetWoWButtonCooldown = GetWoWButtonCooldown,
    IsWoWButtonCooldownShown = IsWoWButtonCooldownShown,
    GetWoWButtonIconTexture = GetWoWButtonIconTexture,
    CooldownModule = CooldownModule,
    SPECIAL_COOLDOWN_SPELLS = SPECIAL_COOLDOWN_SPELLS,
    cooldownLocks = cooldownLocks,
  })
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
  return BindingsModule.GetBindingInfo(key, modifier)
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
    -- CooldownEngine toggles this at runtime.
    btn.cooldown:SetHideCountdownNumbers(true)
  end
  do
    local cdRegion = nil
    local regions = { btn.cooldown:GetRegions() }
    for _, r in ipairs(regions) do
      if r and r.GetObjectType and r:GetObjectType() == "FontString" then
        cdRegion = r
        break
      end
    end
    if cdRegion and cdRegion.SetFont then
      cdRegion:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
      cdRegion:SetTextColor(1, 0.95, 0.6, 1)
      cdRegion:ClearAllPoints()
      cdRegion:SetPoint("CENTER", 0, 0)
      btn._cdTextRegion = cdRegion
      btn._cdTextHidden = true
    end
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
  local mainScale = ClampNumber(DB and DB.settings and DB.settings.main and DB.settings.main.scale, 0.4, 2.0, 1.0)
  local numpadScale = ClampNumber(DB and DB.settings and DB.settings.numpad and DB.settings.numpad.scale, 0.4, 2.0, 1.0)

  if btn.keyLabel then
    btn.keyLabel:SetFont(STANDARD_TEXT_FONT, keyTextSize, "OUTLINE")
    if btn.info and btn.info.section == "numpad" then
      local ratio = mainScale / math.max(0.01, numpadScale)
      btn.keyLabel:SetScale(ClampNumber(ratio, 0.5, 3.0, 1.0))
    else
      btn.keyLabel:SetScale(1.0)
    end
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
        if nb.name ~= "Unbound" then
          if nb.icon == nil then nb.icon = old.icon end
          if nb.actionSlot == nil then nb.actionSlot = old.actionSlot end
          if nb.wowFrame == nil then nb.wowFrame = old.wowFrame end
        end
        nb._activeCooldownSig = old._activeCooldownSig
        nb._activeCooldownStart = old._activeCooldownStart
        nb._activeCooldownDur = old._activeCooldownDur
        nb._activeCooldownEnd = old._activeCooldownEnd
        nb._cooldownSig = old._cooldownSig
        nb._cooldownStart = old._cooldownStart
        nb._cooldownDur = old._cooldownDur
        nb._specCdShown = old._specCdShown
        nb._specCdStart = old._specCdStart
        nb._specCdDur = old._specCdDur
        nb._wowCdShown = old._wowCdShown
        nb._wowCdStart = old._wowCdStart
        nb._wowCdDur = old._wowCdDur
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
        if CooldownEngineModule and CooldownEngineModule.UpdateButtonCooldown then
          CooldownEngineModule.UpdateButtonCooldown(btn, bd, ms)
        end
      else
        if CooldownEngineModule and CooldownEngineModule.ClearButtonCooldownVisuals then
          CooldownEngineModule.ClearButtonCooldownVisuals(btn)
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
end

---------------------------------------------------------------------------
-- Update: usability coloring, range, active highlight, proc glow
---------------------------------------------------------------------------
UpdateUsability = function()
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
  return ConfigModule.CreateConfigSlider(parent, label, minVal, maxVal, step, fmt, getValue, setValue, yOffset)
end

local function CreateConfigCheckbox(parent, label, getValue, setValue, x, y)
  return ConfigModule.CreateConfigCheckbox(parent, label, getValue, setValue, x, y)
end

local function CreateConfigDropdown(parent, label, options, getValue, setValue, yOffset)
  return ConfigModule.CreateConfigDropdown(parent, label, options, getValue, setValue, yOffset)
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
anchor:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
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
  else
    EventsModule.HandleEvent({
      UpdateBindings = UpdateBindings,
      UpdateCooldowns = UpdateCooldowns,
      UpdateUsability = UpdateUsability,
      InCombatLockdown = InCombatLockdown,
      GetPendingBindingRefresh = function() return pendingBindingRefresh end,
      SetPendingBindingRefresh = function(v) pendingBindingRefresh = v and true or false end,
    }, event)
  end
end)

-- Fast OnUpdate: modifier detection + usability/range (throttled to ~20fps)
local runtimeState = (RuntimeModule and RuntimeModule.NewState and RuntimeModule.NewState()) or nil
local function OnModifierStateChanged(newMod)
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
end
anchor:SetScript("OnUpdate", function(self, elapsed)
  RuntimeModule.HandleOnUpdate({
    updateThreshold = 0.02,
    cooldownThreshold = 0.10,
    GetCurrentModifierState = GetCurrentModifierState,
    GetModifierState = function() return currentModifierState end,
    SetModifierState = function(v) currentModifierState = v end,
    OnModifierChanged = OnModifierStateChanged,
    UpdateCooldowns = UpdateCooldowns,
    UpdateUsability = UpdateUsability,
  }, runtimeState, elapsed)
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
NS.api = NS.api or {}
NS.api.HandleSlashCommand = function(msg)
  local cmd, rest = "", ""
  if msg and msg:match("%S") then
    cmd, rest = msg:match("^%s*(%S+)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
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
    print("  /azeron refresh — Rebuild bindings/icons/cooldowns now")
    print("  /azeron resetkeys — Reset all base key mappings")
    print("  /azeron getbindicon <key> — Debug binding info")
    print("  /azeron keystate <key> — Direct WoW key->action button state (single source)")
    print("  /azeron cddebug [key] — Dump cooldown/charge state (optional key filter)")
    print("  /azeron cdbybutton <ActionBarButtonName> — Raw CooldownFrame test (macro-equivalent)")
    print("  /azeron cddiff <key> <seconds> — Per-second Azeron vs WoW cooldown trace")
    print("  /azeron procdebug — Show active rotation recommendations")
    print("  /azeron procsource — Dump source WoW glow frame style info")
    print("  Right-click any button to change its base key.")

  elseif cmd == "edit" then
    ToggleEditMode()

  elseif cmd == "reset" then
    ResetPositions()

  elseif cmd == "config" then
    OpenConfigFrame()

  elseif cmd == "refresh" then
    currentModifierState = nil
    UpdateBindings()
    UpdateCooldowns()
    UpdateUsability()
    print(ADDON_NAME .. ": refreshed bindings/icons/cooldowns")

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

  elseif cmd == "cdbybutton" then
    local buttonName = rest and rest:match("^%s*(.-)%s*$") or ""
    if buttonName == "" then
      print("Usage: /azeron cdbybutton <ActionBarButtonName>")
      return
    end
    local b = _G[buttonName]
    local c = b and (b.cooldown or _G[(b.GetName and b:GetName() or "") .. "Cooldown"]) or nil
    local s, d = 0, 0
    local sRaw, dRaw = 0, 0
    if c and c.GetCooldownTimes then
      s, d = c:GetCooldownTimes()
      sRaw, dRaw = s, d
      s = tonumber(tostring(s)) or 0
      d = tonumber(tostring(d)) or 0
    end
    local nowMS = (GetTime and GetTime() or 0) * 1000
    local shown = (c and c.IsShown and c:IsShown()) and true or false
    print(format("%.1f", max(0, (s + d - nowMS) / 1e3)), shown)
    if not b then
      print(ADDON_NAME .. ": button '" .. tostring(buttonName) .. "' not found")
      return
    end

    local slot = b.action or (b.GetAttribute and b:GetAttribute("action")) or nil
    slot = SafeNumber(slot, nil)
    local actionType, actionID = nil, nil
    if slot and GetActionInfo then
      local ok, at, aid = pcall(GetActionInfo, slot)
      if ok then
        actionType, actionID = at, aid
      end
    end
    local spellIDs = slot and GetActionSpellCandidates(slot) or {}
    local spellID = spellIDs and spellIDs[1] or nil
    local aStart, aDur = 0, 0
    if slot and GetActionCooldown then
      local ok, as, ad = pcall(GetActionCooldown, slot)
      if ok then
        aStart, aDur = NormalizeCooldownPair(as, ad)
      end
    end
    local apiStart, apiDur = 0, 0
    if slot then
      local cs, cd = GetCActionBarCooldown(slot, (actionType == "spell") and actionID or spellID)
      apiStart, apiDur = SafeNumber(cs, 0), SafeNumber(cd, 0)
    end
    local charges, maxCharges, chargeStart, chargeDur = nil, nil, 0, 0
    if slot and GetActionCharges then
      local ok, c1, c2, cs, cd = pcall(GetActionCharges, slot)
      if ok then
        charges, maxCharges = c1, c2
        chargeStart, chargeDur = SafeNumber(cs, 0), SafeNumber(cd, 0)
      end
    end
    local count = nil
    if slot and GetActionCount then
      local ok, n = pcall(GetActionCount, slot)
      if ok then count = n end
    end
    local usable, noMana, inRange = nil, nil, nil
    if slot and IsUsableAction then
      local ok, u, nm = pcall(IsUsableAction, slot)
      if ok then usable, noMana = u, nm end
    end
    if slot and IsActionInRange then
      local ok, r = pcall(IsActionInRange, slot)
      if ok then inRange = r end
    end
    local iconTex = GetWoWButtonIconTexture(b, slot) or (slot and GetActionTexture and GetActionTexture(slot)) or nil
    local iconMark = GetChatIconMarkup(iconTex, 14)
    local now = GetTime and GetTime() or 0
    local cdRemain = max(0, (s + d - nowMS) / 1e3)
    local actionRemain = (aStart > 0 and aDur > 0) and max(0, (aStart + aDur) - now) or 0
    local apiRemain = (apiStart > 0 and apiDur > 0) and max(0, (apiStart + apiDur) - now) or 0
    local chargeRemain = (chargeStart > 0 and chargeDur > 0) and max(0, (chargeStart + chargeDur) - now) or 0
    print(
      ADDON_NAME .. ": button=" .. tostring(buttonName)
      .. " slot=" .. tostring(slot or "-")
      .. " actionType=" .. tostring(actionType or "-")
      .. " actionID=" .. tostring(actionID or "-")
      .. " spellID=" .. tostring(spellID or "-")
      .. " sMS=" .. tostring(tonumber(tostring(sRaw)) or 0)
      .. " dMS=" .. tostring(tonumber(tostring(dRaw)) or 0)
      .. " cd=" .. format("%.1f", cdRemain)
      .. " actionCd=" .. format("%.1f", actionRemain)
      .. " apiCd=" .. format("%.1f", apiRemain)
      .. " shown=" .. tostring(shown)
      .. " charges=" .. tostring(charges) .. "/" .. tostring(maxCharges)
      .. " chargeCD=" .. format("%.1f", chargeRemain)
      .. " count=" .. tostring(count)
      .. " usable=" .. tostring(usable)
      .. " noMana=" .. tostring(noMana)
      .. " inRange=" .. tostring(inRange)
      .. " icon=" .. iconMark
    )

  elseif cmd == "cddiff" then
    local keyArg, secArg = rest:match("^%s*(%S+)%s*(%S*)%s*$")
    if not keyArg or keyArg == "" then
      print("Usage: /azeron cddiff <key> <seconds>")
      return
    end
    local filter = string.upper(tostring(keyArg))
    local duration = ClampNumber(tonumber(secArg or ""), 1, 60, 10)

    local targetBtn = nil
    for _, btn in ipairs(buttons) do
      local baseKey = string.upper(tostring(GetBaseKey(btn.keyID) or ""))
      local keyID = string.upper(tostring(btn.keyID or ""))
      if baseKey == filter or keyID == filter then
        targetBtn = btn
        break
      end
    end
    if not targetBtn then
      print(ADDON_NAME .. ": cddiff key '" .. filter .. "' not found in Azeron layout")
      return
    end

    if cddiffTicker and cddiffTicker.Cancel then
      pcall(cddiffTicker.Cancel, cddiffTicker)
      cddiffTicker = nil
    end

    local tick = 0
    print(ADDON_NAME .. ": cddiff start key=" .. tostring(targetBtn.keyID) .. " base=" .. tostring(GetBaseKey(targetBtn.keyID)) .. " duration=" .. tostring(duration) .. "s")
    cddiffTicker = C_Timer.NewTicker(1, function()
      tick = tick + 1
      local now = GetTime and GetTime() or 0
      local ms = currentModifierState or "NONE"
      local bd = targetBtn.bindings and (targetBtn.bindings[ms] or targetBtn.bindings["NONE"]) or nil
      if not bd then
        print(ADDON_NAME .. ": cddiff t=" .. tostring(tick) .. " no-binding")
        if tick >= duration and cddiffTicker and cddiffTicker.Cancel then pcall(cddiffTicker.Cancel, cddiffTicker); cddiffTicker = nil end
        return
      end

      local baseKey = GetBaseKey(targetBtn.keyID)
      local modKey = (ms == "NONE") and nil or ms
      local dn, iconNow, slotNow, snNow, wowFrameNow = GetBindingInfo(baseKey, modKey)
      if wowFrameNow then bd.wowFrame = wowFrameNow end
      if slotNow then bd.actionSlot = slotNow end

      local liveSlot = GetLiveActionSlotFromBinding({
        actionSlot = slotNow or bd.actionSlot,
        wowFrame = wowFrameNow or bd.wowFrame,
        spellName = snNow or bd.spellName,
      })
      liveSlot = SafeNumber(liveSlot, nil)

      local actionType, actionID = nil, nil
      if liveSlot and GetActionInfo then
        local okAI, at, aid = pcall(GetActionInfo, liveSlot)
        if okAI then actionType, actionID = at, aid end
      end

      local resolvedSpellID = 0
      if actionType == "spell" then
        resolvedSpellID = SafeNumber(actionID, 0)
      end
      if resolvedSpellID <= 0 and liveSlot then
        local ids = GetActionSpellCandidates(liveSlot) or {}
        resolvedSpellID = SafeNumber(ids[1], 0)
      end

      local wowShown, wowRemain = false, 0
      local wf = wowFrameNow or bd.wowFrame
      if wf then
        local cdf = wf.cooldown or wf.Cooldown
        if (not cdf) and wf.GetName then
          local fn = wf:GetName() or ""
          cdf = _G[fn .. "Cooldown"] or _G[fn .. "SpellCooldown"]
        end
        if cdf and cdf.IsShown then
          wowShown = cdf:IsShown() and true or false
        end
        if cdf and cdf.GetCooldownTimes then
          local okCT, sMS, dMS = pcall(cdf.GetCooldownTimes, cdf)
          if okCT then
            local s = SafeNumber(sMS, 0); local d = SafeNumber(dMS, 0)
            if s > 100000 then s = s / 1000 end
            if d > 100000 then d = d / 1000 end
            if s > 0 and d > 0 then
              wowRemain = math.max(0, (s + d) - now)
            end
          end
        end
      end

      local spellShown, spellRemain, isOnGCD = false, 0, false
      local spellStart, spellDur = 0, 0
      if resolvedSpellID > 0 and C_Spell and C_Spell.GetSpellCooldown then
        local okSC, info = pcall(C_Spell.GetSpellCooldown, resolvedSpellID)
        if okSC and info then
          isOnGCD = (tostring(info.isOnGCD or "false") == "true")
          spellStart, spellDur = NormalizeCooldownPair(SafeNumber(info.startTime, 0), SafeNumber(info.duration, 0))
          spellShown = (spellStart > 0 and spellDur > 0)
          if spellShown then
            spellRemain = math.max(0, (spellStart + spellDur) - now)
          end
        end
      end

      local chCur, chMax, chRemain = nil, nil, 0
      if resolvedSpellID > 0 and C_Spell and C_Spell.GetSpellCharges then
        local okCH, a, b, c, d = pcall(C_Spell.GetSpellCharges, resolvedSpellID)
        if okCH then
          if type(a) == "table" then
            chCur = SafeNumber(a.currentCharges or a.charges, nil)
            chMax = SafeNumber(a.maxCharges, nil)
            local cs, cd = NormalizeCooldownPair(SafeNumber(a.cooldownStartTime or a.chargeStartTime, 0), SafeNumber(a.cooldownDuration or a.chargeDuration, 0))
            if cs > 0 and cd > 0 then chRemain = math.max(0, (cs + cd) - now) end
          else
            chCur = SafeNumber(a, nil)
            chMax = SafeNumber(b, nil)
            local cs, cd = NormalizeCooldownPair(SafeNumber(c, 0), SafeNumber(d, 0))
            if cs > 0 and cd > 0 then chRemain = math.max(0, (cs + cd) - now) end
          end
        end
      end

      local azShown, azRemain = false, 0
      if targetBtn.cooldown and targetBtn.cooldown.IsShown then
        azShown = targetBtn.cooldown:IsShown() and true or false
      end
      if targetBtn.cooldown and targetBtn.cooldown.GetCooldownTimes then
        local okAT, sMS, dMS = pcall(targetBtn.cooldown.GetCooldownTimes, targetBtn.cooldown)
        if okAT then
          local s = SafeNumber(sMS, 0); local d = SafeNumber(dMS, 0)
          if s > 100000 then s = s / 1000 end
          if d > 100000 then d = d / 1000 end
          if s > 0 and d > 0 then
            azRemain = math.max(0, (s + d) - now)
          end
        end
      end

      print(
        ADDON_NAME .. ": cddiff t=" .. tostring(tick)
        .. " key=" .. tostring(targetBtn.keyID)
        .. " ms=" .. tostring(ms)
        .. " slot=" .. tostring(liveSlot or "-")
        .. " action=" .. tostring(actionType or "-") .. "/" .. tostring(actionID or "-")
        .. " sid=" .. tostring(resolvedSpellID or 0)
        .. " wow=" .. tostring(wowShown) .. "/" .. string.format("%.1f", wowRemain)
        .. " spell=" .. tostring(spellShown) .. "/" .. string.format("%.1f", spellRemain)
        .. " gcd=" .. tostring(isOnGCD)
        .. " ch=" .. tostring(chCur) .. "/" .. tostring(chMax) .. " chRem=" .. string.format("%.1f", chRemain)
        .. " az=" .. tostring(azShown) .. "/" .. string.format("%.1f", azRemain)
        .. " azCharge=" .. tostring(bd._isChargeSpell)
        .. " azRech=" .. tostring(bd._chargeRecharging)
        .. " azUseDur=" .. tostring(bd._useChargeDurationObj)
      )

      if tick >= duration then
        if cddiffTicker and cddiffTicker.Cancel then pcall(cddiffTicker.Cancel, cddiffTicker) end
        cddiffTicker = nil
        print(ADDON_NAME .. ": cddiff done key=" .. tostring(targetBtn.keyID))
      end
    end)

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
