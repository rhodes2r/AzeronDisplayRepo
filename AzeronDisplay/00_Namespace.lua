local addonName, ns = ...

if type(ns) ~= "table" then
  ns = {}
end

_G.AzeronDisplayNS = ns
ns.addonName = addonName or "AzeronDisplay"
ns.modules = ns.modules or {}
ns.constants = ns.constants or {}
ns.api = ns.api or {}
