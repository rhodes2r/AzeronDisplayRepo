local ns = _G.AzeronDisplayNS or {}
ns.modules = ns.modules or {}

local CooldownEngine = ns.modules.CooldownEngine or {}
local D = {}
local scratchCooldown = nil

local function fallbackSafeNumber(v, fallback)
  local n = tonumber(tostring(v))
  if n == nil then return fallback end
  return n
end

local function clearButtonCooldownVisuals(btn)
  if not btn then return end
  if btn.cooldown then
    btn.cooldown:Clear()
    if btn.cooldown.SetHideCountdownNumbers then
      btn.cooldown:SetHideCountdownNumbers(true)
    end
  end
  btn._cdTextHidden = true
  if btn._cdTextRegion and btn._cdTextRegion.SetTextColor then
    btn._cdTextRegion:SetTextColor(0, 0, 0, 0)
  end
  btn._lastCdStart, btn._lastCdDur = nil, nil
  if btn.icon and btn.icon.SetDesaturated then
    btn.icon:SetDesaturated(false)
  end
  if btn.disabledTint then
    btn.disabledTint:Hide()
  end
  if btn.cooldownText then
    btn.cooldownText:SetText("")
  end
  if btn.countText then
    btn.countText:SetText("")
  end
end

local function setNativeCooldownText(btn, show)
  if not btn or not btn.cooldown then return end
  local wantHide = not show
  if btn.cooldown.SetHideCountdownNumbers and btn._cdTextHidden ~= wantHide then
    btn.cooldown:SetHideCountdownNumbers(wantHide)
    btn._cdTextHidden = wantHide
  end
  if btn._cdTextRegion and btn._cdTextRegion.SetTextColor then
    if show then
      btn._cdTextRegion:SetTextColor(1, 0.95, 0.6, 1)
    else
      btn._cdTextRegion:SetTextColor(0, 0, 0, 0)
    end
  end
end

local function isLikelyGCDCandidate(startTime, duration, isOnGCD, gcdStart, gcdDuration)
  local s = tonumber(tostring(startTime)) or 0
  local d = tonumber(tostring(duration)) or 0
  if s <= 0 or d <= 0 then return false end
  if not isOnGCD then return false end

  -- Generic GCD window.
  if d <= 1.7 then
    return true
  end

  -- If we have explicit GCD timing, match against it.
  local gs = tonumber(tostring(gcdStart)) or 0
  local gd = tonumber(tostring(gcdDuration)) or 0
  if gs > 0 and gd > 0 then
    if math.abs(s - gs) <= 0.15 and math.abs(d - gd) <= 0.20 then
      return true
    end
  end

  return false
end

function CooldownEngine.Init(deps)
  D = deps or {}
  if not scratchCooldown and CreateFrame then
    scratchCooldown = CreateFrame("Cooldown", nil, UIParent, "CooldownFrameTemplate")
    if scratchCooldown then
      scratchCooldown:Hide()
    end
  end
end

function CooldownEngine.UpdateButtonCooldown(btn, bd, modifierState)
  if not btn or not bd then
    clearButtonCooldownVisuals(btn)
    return
  end

  local SafeNumber = D.SafeNumber or fallbackSafeNumber
  local NormalizeCooldownPair = D.NormalizeCooldownPair
  local GetBaseKey = D.GetBaseKey
  local ResolveWoWBindingFrameAndSlot = D.ResolveWoWBindingFrameAndSlot
  local GetLiveActionSlotFromBinding = D.GetLiveActionSlotFromBinding
  local GetWoWButtonCooldown = D.GetWoWButtonCooldown
  local GetActionSpellCandidates = D.GetActionSpellCandidates
  local GetSpellCooldownFromActionSlot = D.GetSpellCooldownFromActionSlot
  local CooldownModule = D.CooldownModule

  local ms = modifierState or "NONE"
  local baseKey = GetBaseKey and GetBaseKey(btn.keyID) or btn.keyID
  local bindKey = (ms == "NONE") and baseKey or (ms .. "-" .. baseKey)
  local resolvedFrame, resolvedSlot = nil, nil
  if ResolveWoWBindingFrameAndSlot then
    local _, rf, rs = ResolveWoWBindingFrameAndSlot(bindKey)
    resolvedFrame, resolvedSlot = rf, rs
  end
  if resolvedFrame then bd.wowFrame = resolvedFrame end
  if resolvedSlot then bd.actionSlot = resolvedSlot end

  local cdStart, cdDur = 0, 0
  local cdRawStart, cdRawDur = nil, nil
  local charges, maxCharges = nil, nil
  local chargeStart, chargeDur = 0, 0
  local stackCount = nil
  local hasAction = false
  local slot = GetLiveActionSlotFromBinding and GetLiveActionSlotFromBinding(bd) or nil
  if (not slot or slot <= 0) and bd._lastGoodSlot then
    slot = SafeNumber(bd._lastGoodSlot, nil)
  end
  if slot then
    bd.actionSlot = slot
    bd._lastGoodSlot = slot
    hasAction = (HasAction and HasAction(slot)) and true or false
    if (not hasAction) and bd.icon ~= nil then
      bd.icon = nil
      if btn.icon then
        btn.icon:SetTexture(nil)
      end
    end
    if GetActionTexture then
      local liveIcon = GetActionTexture(slot)
      if liveIcon then
        local iconSig = tostring(slot) .. "|" .. tostring(liveIcon)
        if bd._liveIconSig == iconSig then
          bd._liveIconSeen = SafeNumber(bd._liveIconSeen, 0) + 1
        else
          bd._liveIconSig = iconSig
          bd._liveIconSeen = 1
        end
        if liveIcon ~= bd.icon and SafeNumber(bd._liveIconSeen, 0) >= 2 then
          bd.icon = liveIcon
          if btn.icon then
            btn.icon:SetTexture(liveIcon)
          end
        end
      end
    end
  end
  local now = GetTime and GetTime() or 0
  if slot and hasAction then
    local ids = GetActionSpellCandidates and GetActionSpellCandidates(slot) or {}
    local resolvedSpellID = SafeNumber(ids[1], 0)
    if resolvedSpellID <= 0 and GetActionInfo then
      local okai, at, aid = pcall(GetActionInfo, slot)
      if okai and at == "spell" then
        resolvedSpellID = SafeNumber(aid, 0)
      end
    end
    bd._resolvedSpellID = resolvedSpellID

    local function probeShown(s, d)
      if not scratchCooldown then return false end
      local psNum = SafeNumber(s, nil)
      local pdNum = SafeNumber(d, nil)
      local ps, pd = s, d
      if psNum and pdNum then
        ps, pd = NormalizeCooldownPair(psNum, pdNum)
        if ps <= 0 or pd <= 0 then
          return false
        end
      end
      scratchCooldown:Hide()
      local ok = pcall(scratchCooldown.SetCooldown, scratchCooldown, ps, pd)
      if not ok then
        scratchCooldown:Hide()
        return false
      end
      local shown = scratchCooldown:IsShown() and true or false
      scratchCooldown:Hide()
      return shown, ps, pd, psNum, pdNum
    end

    local mainShown, mainStart, mainDur = false, 0, 0
    local mainRawStart, mainRawDur = nil, nil
    local spellIsOnGCD = false
    local gcdStart, gcdDur = 0, 0
    do
      -- Capture current GCD timing once per tick.
      if C_Spell and C_Spell.GetSpellCooldown then
        local gok, ginfo = pcall(C_Spell.GetSpellCooldown, 61304)
        if gok and ginfo then
          gcdStart, gcdDur = NormalizeCooldownPair(SafeNumber(ginfo.startTime, 0), SafeNumber(ginfo.duration, 0))
        end
      end

      -- Prefer direct spell cooldown path (CooldownCompanion-style).
      if resolvedSpellID > 0 and C_Spell and C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, resolvedSpellID)
        if ok and info then
          spellIsOnGCD = (tostring(info.isOnGCD or "false") == "true")
          local mShown, ms, md, msNum, mdNum = probeShown(info.startTime, info.duration)
          if mShown then
            local notOnlyGCD = not spellIsOnGCD
            if mdNum and mdNum > 0 and mdNum <= 1.6 then
              notOnlyGCD = false
            end
            if notOnlyGCD and isLikelyGCDCandidate(ms, md, spellIsOnGCD, gcdStart, gcdDur) then
              notOnlyGCD = false
            end
            if notOnlyGCD then
              mainShown, mainStart, mainDur = true, ms, md
              mainRawStart, mainRawDur = info.startTime, info.duration
            end
          end
        end
      end
      if (not mainShown) and GetWoWButtonCooldown then
        local ws, wd = GetWoWButtonCooldown(bd)
        local mShown, ms, md = probeShown(ws, wd)
        if mShown and not isLikelyGCDCandidate(ms, md, spellIsOnGCD, gcdStart, gcdDur) then
          mainShown, mainStart, mainDur = true, ms, md
          mainRawStart, mainRawDur = ws, wd
        end
      end
      if (not mainShown) and GetActionCooldown then
        local ok, s, d = pcall(GetActionCooldown, slot)
        if ok then
          local mShown, ms, md = probeShown(s, d)
          if mShown and not isLikelyGCDCandidate(ms, md, spellIsOnGCD, gcdStart, gcdDur) then
            mainShown, mainStart, mainDur = true, ms, md
            mainRawStart, mainRawDur = s, d
          end
        end
      end
      if (not mainShown) and GetSpellCooldownFromActionSlot then
        local ss, sd = GetSpellCooldownFromActionSlot(slot, resolvedSpellID)
        local mShown, ms, md = probeShown(ss, sd)
        if mShown and not isLikelyGCDCandidate(ms, md, spellIsOnGCD, gcdStart, gcdDur) then
          mainShown, mainStart, mainDur = true, ms, md
          mainRawStart, mainRawDur = ss, sd
        end
      end
    end

    if GetActionCharges then
      local okc, c, mc, cs, cd = pcall(GetActionCharges, slot)
      if okc then
        charges, maxCharges = c, mc
        chargeStart, chargeDur = NormalizeCooldownPair(cs, cd)
      end
    end
    if GetActionCount then
      local okn, n = pcall(GetActionCount, slot)
      if okn then stackCount = n end
    end

    local safeCharges = SafeNumber(charges, nil)
    local safeMaxCharges = SafeNumber(maxCharges, nil)
    local safeCStart = SafeNumber(chargeStart, 0)
    local safeCDur = SafeNumber(chargeDur, 0)
    local chargeShown = false
    local chargeRawStart, chargeRawDur = nil, nil
    if safeCharges and safeMaxCharges and safeMaxCharges > 0 and safeCharges < safeMaxCharges then
      local cShown, cs, cd = probeShown(safeCStart, safeCDur)
      if cShown then
        chargeShown = true
        safeCStart, safeCDur = cs, cd
        chargeRawStart, chargeRawDur = chargeStart, chargeDur
      end
    end

    local mainRemain = (SafeNumber(mainStart, nil) and SafeNumber(mainDur, nil)) and math.max(0, (mainStart + mainDur) - now) or 0
    local chargeRemain = (SafeNumber(safeCStart, nil) and SafeNumber(safeCDur, nil)) and math.max(0, (safeCStart + safeCDur) - now) or 0
    if chargeShown and (not mainShown or chargeRemain > mainRemain) then
      cdStart, cdDur = safeCStart, safeCDur
      cdRawStart, cdRawDur = chargeRawStart, chargeRawDur
    elseif mainShown then
      cdStart, cdDur = mainStart, mainDur
      cdRawStart, cdRawDur = mainRawStart, mainRawDur
    end
  end

  if not hasAction then
    bd._specCdShown = false
    bd._specCdStart, bd._specCdDur = nil, nil
    bd._wowCdShown = false
    bd._wowCdStart, bd._wowCdDur = nil, nil
    bd._resolvedSpellID = nil
  end
  local safeStart = SafeNumber(cdStart, 0)
  local safeDur = SafeNumber(cdDur, 0)
  if safeStart > 0 and safeDur > 0 then
    safeStart, safeDur = NormalizeCooldownPair(safeStart, safeDur)
  end

  local specCdRemain = 0
  local specialTextMode = false
  if CooldownModule and CooldownModule.GetSpecialRemain then
    specCdRemain = SafeNumber(CooldownModule.GetSpecialRemain(bd, now), 0)
    specialTextMode = (specCdRemain > 0)
  end

  local safeCharges = SafeNumber(charges, nil)
  local safeMaxCharges = SafeNumber(maxCharges, nil)
  local safeStackCount = SafeNumber(stackCount, nil)
  local displayStart, displayDur = safeStart, safeDur
  local hasDisplayCooldown = false
  if cdRawStart ~= nil and cdRawDur ~= nil then
    hasDisplayCooldown = true
  elseif displayStart > 0 and displayDur > 0 then
    hasDisplayCooldown = true
  end
  local remain = (displayStart > 0 and displayDur > 0) and math.max(0, (displayStart + displayDur) - now) or 0
  if hasDisplayCooldown then
    if specialTextMode then
      btn.cooldown:Clear()
      btn._lastCdStart, btn._lastCdDur = nil, nil
    else
      if cdRawStart ~= nil and cdRawDur ~= nil then
        btn.cooldown:SetCooldown(cdRawStart, cdRawDur)
      else
        local changed = (not btn._lastCdStart)
          or math.abs((btn._lastCdStart or 0) - displayStart) > 0.15
          or math.abs((btn._lastCdDur or 0) - displayDur) > 0.15
        if changed then
          btn.cooldown:SetCooldown(displayStart, displayDur)
          btn._lastCdStart, btn._lastCdDur = displayStart, displayDur
        end
      end
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
    setNativeCooldownText(btn, true)
    if btn.cooldownText then btn.cooldownText:SetText("") end
  else
    btn.cooldown:Clear()
    setNativeCooldownText(btn, false)
    btn._lastCdStart, btn._lastCdDur = nil, nil
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
end

CooldownEngine.ClearButtonCooldownVisuals = clearButtonCooldownVisuals

ns.modules.CooldownEngine = CooldownEngine
_G.AzeronDisplayNS = ns
