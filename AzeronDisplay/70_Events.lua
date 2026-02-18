local ns = _G.AzeronDisplayNS or {}
ns.modules = ns.modules or {}

local Events = ns.modules.Events or {}

function Events.HandleEvent(ctx, event)
  if not ctx or not event then return false end

  if event == "UPDATE_BINDINGS" then
    if ctx.UpdateBindings then ctx.UpdateBindings() end
    return true
  end

  if event == "ACTIONBAR_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_CHARGES" then
    if ctx.UpdateCooldowns then ctx.UpdateCooldowns() end
    return true
  end

  if event == "ACTIONBAR_SLOT_CHANGED" or event == "ACTIONBAR_PAGE_CHANGED" then
    local inCombat = ctx.InCombatLockdown and ctx.InCombatLockdown() or false
    if inCombat then
      if ctx.SetPendingBindingRefresh then ctx.SetPendingBindingRefresh(true) end
      if ctx.UpdateCooldowns then ctx.UpdateCooldowns() end
    else
      if ctx.UpdateBindings then ctx.UpdateBindings() end
    end
    if ctx.UpdateUsability then ctx.UpdateUsability() end
    return true
  end

  if event == "PLAYER_REGEN_ENABLED" then
    if ctx.GetPendingBindingRefresh and ctx.GetPendingBindingRefresh() then
      if ctx.SetPendingBindingRefresh then ctx.SetPendingBindingRefresh(false) end
      if ctx.UpdateBindings then ctx.UpdateBindings() end
    end
    if ctx.UpdateCooldowns then ctx.UpdateCooldowns() end
    if ctx.UpdateUsability then ctx.UpdateUsability() end
    return true
  end

  if event == "ACTIONBAR_UPDATE_USABLE"
      or event == "ACTIONBAR_UPDATE_STATE"
      or event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW"
      or event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE"
      or event == "PLAYER_ENTERING_WORLD" then
    if ctx.UpdateUsability then ctx.UpdateUsability() end
    return true
  end

  return false
end

ns.modules.Events = Events
_G.AzeronDisplayNS = ns
