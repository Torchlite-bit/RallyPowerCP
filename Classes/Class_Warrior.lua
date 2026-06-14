--=============================================================================
-- Class_Warrior.lua  -  Warrior module for RallyPowerCP  (NEW in 0.2.0)
-- Battle Shout is a "self-cast" party buff: you cast it once and it refreshes
-- party members in range (no per-member targeting). The core's selfcast path
-- handles the click; coverage and the timer still work normally.
--=============================================================================

local M = RallyPowerCP:NewClass("WARRIOR")

M.buffs = {
    { name = "Battle Shout",
      icons = { "Ability_Warrior_BattleShout" },
      dur = 2*60, selfcast = true },
}
