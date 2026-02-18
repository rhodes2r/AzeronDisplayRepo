local ns = _G.AzeronDisplayNS or {}
ns.constants = ns.constants or {}

-- Spell IDs that should use state-driven cooldown handling.
-- Duration is in seconds and can be tuned per spell.
ns.constants.SPECIAL_COOLDOWN_SPELLS = ns.constants.SPECIAL_COOLDOWN_SPELLS or {
  [22812] = 34.0, -- Barkskin
}

_G.AzeronDisplayNS = ns
