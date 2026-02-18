local ns = _G.AzeronDisplayNS or {}
ns.modules = ns.modules or {}
ns.constants = ns.constants or {}

local Cooldowns = ns.modules.Cooldowns or {}

local function SN(v, fallback)
  local n = tonumber(tostring(v))
  if n == nil then return fallback end
  return n
end

function Cooldowns.GetExpectedDuration(spellID, overrides)
  local sid = SN(spellID, 0)
  if sid <= 0 then return nil end
  local o = overrides or ns.constants.SPECIAL_COOLDOWN_SPELLS or {}
  local override = o[sid]
  if override ~= nil then
    local ov = SN(override, 0)
    return (ov > 0) and ov or nil
  end
  if not GetSpellBaseCooldown then return nil end
  local ok, baseMS = pcall(GetSpellBaseCooldown, sid)
  if not ok then return nil end
  local baseSec = SN(baseMS, 0) / 1000
  if baseSec > 1.6 then
    return baseSec
  end
  return nil
end

function Cooldowns.UpdateSpecialState(bd, wowShown, wowStart, wowDur, now, expectedDur)
  local expected = SN(expectedDur, 0)
  if expected <= 0 then
    expected = SN(bd and bd._specCdFallbackDur, 0)
    if expected <= 0 then expected = 34.0 end
  end

  if wowShown then
    local wasShown = (bd and bd._specCdShown == true)
    if not wasShown and bd then
      bd._specCdShown = true
      bd._specCdStart = now
      local ws = SN(wowStart, 0)
      local wd = SN(wowDur, 0)
      if ws > 0 and wd > 1.6 and wd < 120 then
        bd._specCdDur = wd
        bd._specCdFallbackDur = wd
      else
        bd._specCdDur = expected
      end
    end
    local cs = SN(bd and bd._specCdStart, now)
    local cd = SN(bd and bd._specCdDur, expected)
    local remain = (cs > 0 and cd > 0) and math.max(0, (cs + cd) - now) or 0
    return cs, cd, remain
  end

  if bd then
    bd._specCdShown = false
    bd._specCdStart, bd._specCdDur = nil, nil
  end
  return 0, 0, 0
end

function Cooldowns.GetSpecialRemain(bd, now)
  local cs = SN(bd and bd._specCdStart, 0)
  local cd = SN(bd and bd._specCdDur, 0)
  if bd and bd._specCdShown == true and cs > 0 and cd > 0 then
    return math.max(0, (cs + cd) - now)
  end
  return 0
end

ns.modules.Cooldowns = Cooldowns
_G.AzeronDisplayNS = ns
