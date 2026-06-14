--=============================================================================
-- Class_Druid.lua  -  Druid module for RallyPowerCP
--=============================================================================

local M = RallyPowerCP:NewClass("DRUID")

M.buffs = {
    { name = "Mark of the Wild", group = "Gift of the Wild",
      icons = { "Spell_Nature_Regeneration" }, pet = true,
      dur = 30*60, gdur = 60*60 },
    { name = "Thorns",
      icons = { "Spell_Nature_Thorns" },
      dur = 10*60 },
}
