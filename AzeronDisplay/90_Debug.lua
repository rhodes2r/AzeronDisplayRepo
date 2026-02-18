local ns = _G.AzeronDisplayNS or {}

SLASH_AZERONDISPLAY1 = "/azeron"
SlashCmdList["AZERONDISPLAY"] = function(msg)
  if ns.api and ns.api.HandleSlashCommand then
    ns.api.HandleSlashCommand(msg)
    return
  end
  print("AzeronDisplay: slash handler unavailable")
end
