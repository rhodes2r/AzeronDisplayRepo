local ns = _G.AzeronDisplayNS or {}
ns.modules = ns.modules or {}

local Runtime = ns.modules.Runtime or {}

function Runtime.NewState()
  return {
    updateAccum = 0,
    cooldownAccum = 0,
  }
end

function Runtime.HandleOnUpdate(ctx, state, elapsed)
  if not ctx or not state then return end
  state.updateAccum = state.updateAccum + (elapsed or 0)
  state.cooldownAccum = state.cooldownAccum + (elapsed or 0)

  if state.updateAccum < (ctx.updateThreshold or 0.02) then
    return
  end
  state.updateAccum = 0

  local getMod = ctx.GetCurrentModifierState
  local curMod = ctx.GetModifierState
  local setMod = ctx.SetModifierState
  local onMod = ctx.OnModifierChanged
  local updateCooldowns = ctx.UpdateCooldowns
  local updateUsability = ctx.UpdateUsability

  if getMod and curMod and setMod then
    local newMod = getMod()
    if newMod ~= curMod() then
      setMod(newMod)
      if onMod then onMod(newMod) end
      if updateCooldowns then updateCooldowns() end
    end
  end

  if state.cooldownAccum >= (ctx.cooldownThreshold or 0.10) then
    state.cooldownAccum = 0
    if updateCooldowns then updateCooldowns() end
  end

  if updateUsability then updateUsability() end
end

ns.modules.Runtime = Runtime
_G.AzeronDisplayNS = ns
