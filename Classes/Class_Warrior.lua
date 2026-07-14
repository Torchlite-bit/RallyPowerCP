--=============================================================================
-- Class_Warrior.lua  -  Warrior module for RallyPowerCP
--
-- Two strip buttons:
--   Battle Shout - a self-cast party buff (one cast refreshes nearby party,
--     no per-member targeting); tracks the shout on YOU, green + cast-derived
--     timer while up, red when missing, click casts.
--   Sunder Armor - a target debuff; tracks it on your current target via the
--     icon-seed matcher, green + timer while it's on the target, red when
--     missing, grey with no hostile target; click applies/refreshes it.
--
-- Detection matches the buff/debuff icon against your own spellbook texture;
-- timers are cast-derived (Vanilla defaults - one-line edits if Turtle differs).
--=============================================================================

local M = RallyPowerCP:NewClass("WARRIOR")

local SHOUT = { name = "Battle Shout", dur = 2 * 60 }
-- Sunder Armor: a target debuff (Vanilla 30s per stack). The button tracks it
-- on your current target via the icon-seed matcher and casts/refreshes it.
local SUNDER = { name = "Sunder Armor", dur = 30, icon = "Interface\\Icons\\Ability_Warrior_Sunder" }

local strip
local deadline = 0
local sunder = { target = nil, deadline = 0 }   -- cast-derived timer on the target

-- Is Battle Shout on me? (player-buff icon match vs the spellbook texture.)
local function ShoutUp()
    if not SHOUT._tex then return false end
    local j = 1
    while j <= 32 do
        local tex = UnitBuff("player", j)
        if not tex then break end
        if RallyPowerCP.TexBase(tex) == SHOUT._tex then return true end
        j = j + 1
    end
    return false
end

local function BuildUI()
    if strip then return end
    strip = RallyPowerCP.NewStrip("warrior", "Shout")
    strip:AddButton{
        key = "shout",
        refresh = function(b)
            local sp = RallyPowerCP.FindSpell(SHOUT.name)
            local test = RallyPowerCP.IsTestMode()
            if not sp and not test then
                b:SetIcon(nil); b:SetLabel("|cffffd100Shout|r")
                b:SetSub("|cff888888not learned|r"); b:SetTimer(""); b:SetState("off")
                return
            end
            if sp then SHOUT._tex = RallyPowerCP.TexBase(sp.texture) end
            b:SetIcon(sp and sp.texture or nil)
            b:SetLabel("|cffffd100Shout|r")
            b:SetSub("Battle" .. ((not sp) and " |cffff8800*|r" or ""))
            -- Test mode: state runs purely off the simulated timer.
            if test then
                if deadline > GetTime() then
                    b:SetState("good"); b:SetTimer(RallyPowerCP.FmtTime(deadline - GetTime()))
                else
                    b:SetState("need"); b:SetTimer("")
                end
                return
            end
            if ShoutUp() then
                b:SetState("good")
                if deadline > GetTime() then
                    b:SetTimer(RallyPowerCP.FmtTime(deadline - GetTime()))
                else b:SetTimer("") end
            else
                b:SetState("need"); b:SetTimer("")
            end
        end,
        onClick = function(b)
            local sp = RallyPowerCP.FindSpell(SHOUT.name)
            if RallyPowerCP.IsTestMode() then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[test]|r would cast " .. SHOUT.name)
                deadline = GetTime() + SHOUT.dur
                return
            end
            if not sp then return end
            CastSpellByName(SHOUT.name)          -- self-cast; refreshes nearby party
            deadline = GetTime() + SHOUT.dur
        end,
        tooltip = function(b, tt)
            tt:AddLine("Battle Shout")
            tt:AddLine("Click to cast (refreshes nearby party).", 0.6, 0.6, 0.6)
        end,
    }
    strip:AddButton{
        key = "sunder",
        refresh = function(b)
            local sp = RallyPowerCP.FindSpell(SUNDER.name)
            local test = RallyPowerCP.IsTestMode()
            if not sp and not test then
                b:SetIcon(nil); b:SetLabel("|cffffd100Sunder|r")
                b:SetSub("|cff888888not learned|r"); b:SetTimer(""); b:SetState("off")
                return
            end
            if sp then SUNDER._tex = RallyPowerCP.TexBase(sp.texture) end
            b:SetIcon(sp and sp.texture or SUNDER.icon)
            b:SetLabel("|cffffd100Sunder|r")
            b:SetSub("Armor" .. ((not sp) and " |cffff8800*|r" or ""))
            -- Test mode: state runs purely off the simulated timer.
            if test then
                if sunder.deadline > GetTime() then
                    b:SetState("good"); b:SetTimer(RallyPowerCP.FmtTime(sunder.deadline - GetTime()))
                else
                    b:SetState("need"); b:SetTimer("")
                end
                return
            end
            if not UnitExists("target") or UnitIsFriend("player", "target") then
                b:SetTimer(""); b:SetState("off")
                return
            end
            if RallyPowerCP.UnitHasDebuffEntry("target", SUNDER) then
                b:SetState("good")
                if sunder.target == UnitName("target") and sunder.deadline > GetTime() then
                    b:SetTimer(RallyPowerCP.FmtTime(sunder.deadline - GetTime()))
                else
                    b:SetTimer("")
                end
            else
                b:SetState("need"); b:SetTimer("")
            end
        end,
        onClick = function(b)
            local sp = RallyPowerCP.FindSpell(SUNDER.name)
            if RallyPowerCP.IsTestMode() then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[test]|r would apply " .. SUNDER.name)
                sunder = { target = "(test)", deadline = GetTime() + SUNDER.dur }
                return
            end
            if not sp then return end
            if not UnitExists("target") or UnitIsFriend("player", "target") then return end
            if RallyPowerCP.CastAtTarget(SUNDER.name) then
                sunder = { target = UnitName("target"), deadline = GetTime() + SUNDER.dur }
            end
        end,
        tooltip = function(b, tt)
            tt:AddLine("Sunder Armor")
            tt:AddLine("Click to apply/refresh on your target.", 0.6, 0.6, 0.6)
        end,
    }
    strip:Finish()
end

function M:OnActivate()
    BuildUI()
    strip:Refresh()
end

function M:Toggle()
    if not strip then BuildUI() end
    strip:Toggle()
end

M.optionsInfo = {
    { type = "header", label = "Buttons" },
    { type = "check", key = "btn_shout", label = "Battle Shout button", default = true,
      onChange = function() RallyPowerCP.ReflowStrips() end },
    { type = "check", key = "btn_sunder", label = "Sunder Armor button", default = true,
      onChange = function() RallyPowerCP.ReflowStrips() end },
}

-- Assignment model: Warrior debuff duties (Sunder has a strip button above;
-- Thunder Clap / Demoralizing Shout are catalog-only).
if RallyPowerCP.Assign then
    local D = RallyPowerCP.Assign.RegisterDuty
    D{ key="SUNDER",      wid=7, class="WARRIOR", tab="debuff", spell="Sunder Armor",       target="none", multi=false, dur=30 }
    -- Thunder Clap / Demoralizing Shout are group-utility debuffs, not the
    -- "one caster maintains it on the kill target" kind; hidden from the
    -- Debuffs tab (wids stay reserved, and the model/sync still carry them).
    D{ key="THUNDERCLAP", wid=8, class="WARRIOR", tab="debuff", spell="Thunder Clap",       target="none", multi=false, dur=30, hidden=true }
    D{ key="DEMOSHOUT",   wid=9, class="WARRIOR", tab="debuff", spell="Demoralizing Shout", target="none", multi=false, dur=30, hidden=true }
end
