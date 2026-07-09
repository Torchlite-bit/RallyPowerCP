--=============================================================================
-- Class_Priest.lua  -  Priest module for RallyPowerCP
--
-- A class-buff strip (like Mage/Druid): one button per raid class showing the
-- buff assigned to that class (Fortitude / Divine Spirit / Shadow Protection,
-- wheel-cycled). Left-click casts the group version, right-click tops off the
-- next member, hover opens the player pop-out. Plus the utility buttons
-- (PW: Shield / Fear Ward) appended to the same strip. All behaviour (scanning,
-- casting, timers, the strip) lives in the core; the module supplies the data.
--=============================================================================

local M = RallyPowerCP:NewClass("PRIEST")

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
M.utility = {
    { name = "Power Word: Shield", mode = "lowhp",  icon = "Spell_Holy_PowerWordShield",
      tip = "lowest-health member in range (your target first)" },
    { name = "Fear Ward",          mode = "target", icon = "Spell_Holy_Excorcism_02",
      tip = "your target, else yourself" },
}

function M:OnActivate()
    RallyPowerCP.BuildClassBuffs()
end

function M:Toggle()
    RallyPowerCP.BuildClassBuffs():Toggle()
end
