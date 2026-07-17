--=============================================================================
-- Class_Priest.lua  -  Priest module for AegisRP
--
-- A class-buff strip (like Mage/Druid): one button per raid class showing the
-- buff assigned to that class (Fortitude / Divine Spirit / Shadow Protection,
-- wheel-cycled). Left-click casts the group version, right-click tops off the
-- next member, hover opens the player pop-out. Plus a utility button (Fear
-- Ward) appended to the same strip. All behaviour (scanning, casting, timers,
-- the strip) lives in the core; the module supplies the data.
--=============================================================================

local M = AegisRP:NewClass("PRIEST")

-- Maintained group buffs (single-target name + group/greater version).
M.buffs = {
    { name = "Power Word: Fortitude", group = "Prayer of Fortitude",
      icons = { "Spell_Holy_WordFortitude" }, pet = true,
      dur = 30*60, gdur = 60*60 },
    { name = "Divine Spirit",         group = "Prayer of Spirit",
      icons = { "Spell_Holy_DivineSpirit", "Spell_Holy_PrayerofSpirit" },
      dur = 30*60, gdur = 60*60 },
    { name = "Shadow Protection",     group = "Prayer of Shadow Protection",
      icons = { "Spell_Shadow_AntiShadow" },
      dur = 10*60, gdur = 20*60 },
}

-- Utility buttons (situational single-target casts), appended to the strip.
-- `duty` links the button to its assignment duty: when you hold that duty
-- with a @TANK/@HEALER target (Roles tab / Utility tab), the button casts on
-- the marked role member instead of its default `mode` target.
M.utility = {
    { name = "Fear Ward",          mode = "target", duty = "FEARWARD",
      icon = "Spell_Holy_Excorcism_02",
      tip = "your target, else yourself" },
}

function M:OnActivate()
    AegisRP.BuildClassBuffs()
end

function M:Toggle()
    AegisRP.BuildClassBuffs():Toggle()
end

-- Assignment model: Priest duties (raid buffs + utility). Wids are stable.
if AegisRP.Assign then
    local D = AegisRP.Assign.RegisterDuty
    D{ key="FORTITUDE",  wid=1,  class="PRIEST", tab="raidbuff", spell="Power Word: Fortitude", target="none",   multi=false, dur=30*60 }
    D{ key="SPIRIT",     wid=2,  class="PRIEST", tab="raidbuff", spell="Divine Spirit",          target="none",   multi=false, dur=30*60 }
    D{ key="SHADOWPROT", wid=3,  class="PRIEST", tab="raidbuff", spell="Shadow Protection",      target="none",   multi=false, dur=10*60 }
    D{ key="FEARWARD",   wid=18, class="PRIEST", tab="utility",  spell="Fear Ward",              target="player", multi=false, dur=0 }
    -- wid 19 (PW: Shield) is retired - it's spammed reactively, not a
    -- maintained/assigned duty. Never reuse wid 19 (wire stays forward-safe).
end
