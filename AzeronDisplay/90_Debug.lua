local ns = _G.AzeronDisplayNS or {}
local out = ns.Print or print

SLASH_AZERONDISPLAY1 = "/azeron"
SlashCmdList["AZERONDISPLAY"] = function(msg)
  if ns.api and ns.api.HandleSlashCommand then
    ns.api.HandleSlashCommand(msg)
    return
  end
  out("AzeronDisplay: slash handler unavailable")
end
