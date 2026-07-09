--=============================================================================
-- Class_Druid.lua  -  Druid module for RallyPowerCP
--
-- A class-buff strip (like Priest/Mage): one button per raid class showing the
-- buff assigned to that class. Wheel cycles Mark of the Wild <-> Thorns for
-- that class; left-click casts the group version, right-click tops off the next
-- member, hover opens the player pop-out. The engine (Core) drives coverage,
-- casting and the strip; the module only supplies the buff data.
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

function M:OnActivate()
    RallyPowerCP.BuildClassBuffs()
end

function M:Toggle()
    RallyPowerCP.BuildClassBuffs():Toggle()
end
