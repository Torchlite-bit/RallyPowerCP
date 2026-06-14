--=============================================================================
-- Class_Priest.lua  -  Priest module for RallyPowerCP
-- Registers with the core and supplies the Priest's group buffs and utility
-- spells. All behaviour (scanning, casting, the bar, timers) lives in the core.
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

-- Top-row utility buttons (situational single-target casts).
M.utility = {
    { name = "Power Word: Shield", mode = "lowhp",  icon = "Spell_Holy_PowerWordShield",
      tip = "lowest-health member in range (your target first)" },
    { name = "Fear Ward",          mode = "target", icon = "Spell_Holy_Excorcism_02",
      tip = "your target, else yourself" },
}
