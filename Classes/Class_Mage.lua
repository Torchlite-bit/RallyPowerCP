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

-- Assignment model: Mage duties. Wids are stable.
if RallyPowerCP.Assign then
    local D = RallyPowerCP.Assign.RegisterDuty
    D{ key="INTELLECT", wid=4,  class="MAGE", tab="raidbuff", spell="Arcane Intellect", target="none", multi=false, dur=30*60 }
    D{ key="SCORCH",    wid=13, class="MAGE", tab="debuff",   spell="Scorch",           target="none", multi=false, dur=30 }
end
