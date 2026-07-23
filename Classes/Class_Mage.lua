--=============================================================================
-- Class_Mage.lua  -  Mage module for AegisRP
--
-- A class-buff strip (like Priest/Druid): one button per raid class showing the
-- Intellect buff assigned to that class. Left-click casts the group version
-- (Arcane Brilliance), right-click tops off the next member, hover opens the
-- player pop-out. The engine (Core) drives coverage, casting and the strip.
--=============================================================================

local M = AegisRP:NewClass("MAGE")

M.buffs = {
    { name = "Arcane Intellect", group = "Arcane Brilliance",
      icons = { "Spell_Holy_MagicalSentry", "Spell_Holy_ArcaneIntellect" },
      dur = 30*60, gdur = 60*60 },
}

M.debuffs = {
    { name = "Scorch", dur = 30,
      icon = "Spell_Fire_SoulBurn" },
}

function M:OnActivate()
    AegisRP.BuildClassBuffs()
end

function M:Toggle()
    AegisRP.BuildClassBuffs():Toggle()
end

-- Assignment model: Mage duties. Wids are stable.
if AegisRP.Assign then
    local D = AegisRP.Assign.RegisterDuty
    D{ key="INTELLECT", wid=4,  class="MAGE", tab="raidbuff", spell="Arcane Intellect", target="none", multi=false, dur=30*60 }
    D{ key="SCORCH",    wid=13, class="MAGE", tab="debuff",   spell="Scorch",           target="none", multi=false, dur=30 }
end
