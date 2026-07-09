--=============================================================================
-- Class_Mage.lua  -  Mage module for RallyPowerCP
--
-- A class-buff strip (like Priest/Druid): one button per raid class showing the
-- Intellect buff assigned to that class. Left-click casts the group version
-- (Arcane Brilliance), right-click tops off the next member, hover opens the
-- player pop-out. The engine (Core) drives coverage, casting and the strip.
--=============================================================================

local M = RallyPowerCP:NewClass("MAGE")

M.buffs = {
    { name = "Arcane Intellect", group = "Arcane Brilliance",
      icons = { "Spell_Holy_MagicalSentry", "Spell_Holy_ArcaneIntellect" },
      dur = 30*60, gdur = 60*60 },
}

function M:OnActivate()
    RallyPowerCP.BuildClassBuffs()
end

function M:Toggle()
    RallyPowerCP.BuildClassBuffs():Toggle()
end
