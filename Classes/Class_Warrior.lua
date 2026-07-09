--=============================================================================
-- Class_Warrior.lua  -  Warrior module for RallyPowerCP
--
-- Battle Shout is a self-cast party buff: one cast refreshes nearby party
-- members (no per-member targeting), so - like the Warlock's armor button - it
-- is a single strip button that tracks the shout on YOU: green with a
-- cast-derived timer while it's up, red when it's missing. Click casts it.
--
-- Detection matches the buff icon against your own spellbook texture; the timer
-- is cast-derived (2-minute Vanilla default - one-line edit if Turtle differs).
--=============================================================================

local M = RallyPowerCP:NewClass("WARRIOR")

local SHOUT = { name = "Battle Shout", dur = 2 * 60 }

local strip
local deadline = 0

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
    { type = "header", label = "Shout" },
    { type = "check", key = "btn_shout", label = "Battle Shout button", default = true,
      onChange = function() RallyPowerCP.ReflowStrips() end },
}

-- Assignment model: Warrior debuff duties (no strip buttons yet - catalog only).
if RallyPowerCP.Assign then
    local D = RallyPowerCP.Assign.RegisterDuty
    D{ key="SUNDER",      wid=7, class="WARRIOR", tab="debuff", spell="Sunder Armor",       target="none", multi=false, dur=30 }
    D{ key="THUNDERCLAP", wid=8, class="WARRIOR", tab="debuff", spell="Thunder Clap",       target="none", multi=false, dur=30 }
    D{ key="DEMOSHOUT",   wid=9, class="WARRIOR", tab="debuff", spell="Demoralizing Shout", target="none", multi=false, dur=30 }
end
