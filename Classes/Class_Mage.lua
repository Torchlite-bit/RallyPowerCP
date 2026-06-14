--=============================================================================
-- Class_Mage.lua  -  Mage module for RallyPowerCP
--=============================================================================

local M = RallyPowerCP:NewClass("MAGE")

M.buffs = {
    { name = "Arcane Intellect", group = "Arcane Brilliance",
      icons = { "Spell_Holy_MagicalSentry", "Spell_Holy_ArcaneIntellect" },
      dur = 30*60, gdur = 60*60 },
}
