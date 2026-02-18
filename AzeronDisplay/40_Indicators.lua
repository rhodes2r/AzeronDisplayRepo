local ns = _G.AzeronDisplayNS or {}
ns.modules = ns.modules or {}

local Indicators = ns.modules.Indicators or {}

function Indicators.UpdateUsability(ctx)
  if not ctx then return end
  local ms = ctx.currentModifierState or "NONE"
  local buttons = ctx.buttons or {}

  local glowingSources = ctx.CollectGlowingWoWSources and ctx.CollectGlowingWoWSources() or {}
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
        local slot = (ctx.GetLiveActionSlotFromBinding and ctx.GetLiveActionSlotFromBinding(bd)) or bd.actionSlot
        bd.actionSlot = slot
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

      local slot = bd and (ctx.GetLiveActionSlotFromBinding and ctx.GetLiveActionSlotFromBinding(bd))
      if bd and slot then bd.actionSlot = slot end
      if slot and glowingSlots[slot] then
        showProc = true
        procSource = glowingSourceBySlot[slot]
      end

      if not showProc and bd and bd.wowFrame and ctx.IsWoWButtonPressed and ctx.IsWoWButtonPressed(bd.wowFrame) then
        showPressed = true
      end

      if showPressed then
        if btn.activeBorder then btn.activeBorder:Show() end
        if btn.activePressFrame then btn.activePressFrame:Hide() end
        if btn.activeFill then btn.activeFill:Hide() end
      else
        if btn.activeBorder then btn.activeBorder:Hide() end
        if btn.activePressFrame then btn.activePressFrame:Hide() end
        if btn.activeFill then btn.activeFill:Hide() end
      end

      if showProc then
        if ctx.ApplyProcSourceVisual then
          ctx.ApplyProcSourceVisual(btn, procSource and procSource.frame or nil)
        end
        if btn.borderFrame then btn.borderFrame:Hide() end
        if btn.procBorderFrame then btn.procBorderFrame:Hide() end
        if btn.procBorder then btn.procBorder:Show() end
        if ctx.EnsureProcAnimation then
          ctx.EnsureProcAnimation(btn)
        end
        if btn.procAnimGroup and not btn._procAnimPlaying then
          btn.procAnimGroup:Play()
          btn._procAnimPlaying = true
        end
      else
        if btn.borderFrame then btn.borderFrame:Show() end
        if btn.procBorderFrame then btn.procBorderFrame:Hide() end
        if ctx.StopProcAnimation then
          ctx.StopProcAnimation(btn)
        end
        if btn.procBorder then
          btn.procBorder:Hide()
        end
      end
    end
  end
end

ns.modules.Indicators = Indicators
_G.AzeronDisplayNS = ns
