--=============================================================================
-- Class_Druid.lua  -  Druid module for AegisRP
--
-- A class-buff strip (like Priest/Mage): one button per raid class showing the
-- buff assigned to that class. Wheel cycles Mark of the Wild <-> Thorns for
-- that class; left-click casts the group version, right-click tops off the next
-- member, hover opens the player pop-out. The engine (Core) drives coverage,
-- casting and the strip; the module only supplies the buff data.
--=============================================================================

local M = AegisRP:NewClass("DRUID")

M.buffs = {
    { name = "Mark of the Wild", group = "Gift of the Wild",
      icons = { "Spell_Nature_Regeneration" }, pet = true,
      dur = 30*60, gdur = 60*60 },
    { name = "Thorns",
      icons = { "Spell_Nature_Thorns" },
      dur = 10*60 },
}

function M:OnActivate()
    AegisRP.BuildClassBuffs()
end

function M:Toggle()
    AegisRP.BuildClassBuffs():Toggle()
end

-- Assignment model: Druid duties. Wids are stable.
if AegisRP.Assign then
    local D = AegisRP.Assign.RegisterDuty
    D{ key="MARK",      wid=5,  class="DRUID", tab="raidbuff", spell="Mark of the Wild", target="none",   multi=false, dur=30*60 }
    D{ key="THORNS",    wid=6,  class="DRUID", tab="raidbuff", spell="Thorns",           target="none",   multi=false, dur=10*60 }
    D{ key="INNERVATE", wid=20, class="DRUID", tab="utility",  spell="Innervate",        target="player", multi=true,  dur=0 }
end
