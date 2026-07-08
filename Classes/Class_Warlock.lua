--=============================================================================
-- Class_Warlock.lua  -  Warlock module for RallyPowerCP
--
-- Three buttons on the shared strip:
--
--   ARMOR     - your personal armor buff (Demon Armor / Demon Skin, highest
--               known). Green with a timer while it's on you, red when missing.
--               Click to (re)cast.
--   SOULSTONE - the spec's glow-state button. Green when a Soulstone is in your
--               bags and off cooldown; red while it's on cooldown (shows the
--               cooldown); grey when you have none (click then CREATES one).
--               Left-click uses it on your friendly target, or yourself.
--   CURSE     - cycle which curse you're assigned to keep on the target
--               (Elements / Shadow / Agony / Weakness / Tongues / Recklessness /
--               Doom - whichever you know). Green while it's on the target.
--
-- Detection matches debuff/buff icons against your own spellbook textures, with
-- SuperWoW id-learning on top. Timers are cast-derived.
--=============================================================================

local M = RallyPowerCP:NewClass("WARLOCK")

local ARMORS = {
    { name = "Demon Armor", dur = 30 * 60 },
    { name = "Demon Skin",  dur = 30 * 60 },
}
local CURSES = {
    { name = "Curse of the Elements",  dur = 5 * 60 },
    { name = "Curse of Shadow",        dur = 5 * 60 },
    { name = "Curse of Weakness",      dur = 2 * 60 },
    { name = "Curse of Recklessness",  dur = 2 * 60 },
    { name = "Curse of Tongues",       dur = 30 },
    { name = "Curse of Agony",         dur = 24 },
    { name = "Curse of Doom",          dur = 60 },
}

local strip
local armorDeadline = 0
local curseApplied = {}   -- [curseName] = { target, deadline }

-- highest known armor (test mode: first defined, marked simulated)
local function BestArmor()
    for _, a in ipairs(ARMORS) do
        local sp = RallyPowerCP.FindSpell(a.name)
        if sp then
            a._tex = RallyPowerCP.TexBase(sp.texture); a._icon = sp.texture; a._sim = nil
            return a
        end
    end
    if RallyPowerCP.IsTestMode() then
        local a = ARMORS[1]
        a._icon = nil; a._sim = true
        return a
    end
    return nil
end

-- is my armor buff on ME? (player buffs: icon match vs spellbook texture; the
-- shared debuff helper works on buffs too via UnitBuff scan here)
local function ArmorUp(a)
    if not a then return false end
    local j = 1
    while j <= 32 do
        local tex = UnitBuff("player", j)
        if not tex then break end
        if RallyPowerCP.TexBase(tex) == a._tex then return true end
        j = j + 1
    end
    return false
end

local function KnownCurses()
    local out = {}
    local test = RallyPowerCP.IsTestMode()
    for _, c in ipairs(CURSES) do
        local sp = RallyPowerCP.FindSpell(c.name)
        if sp then
            c._tex = RallyPowerCP.TexBase(sp.texture); c._icon = sp.texture; c._sim = nil
            table.insert(out, c)
        elseif test then
            c._icon = nil; c._sim = true
            table.insert(out, c)
        end
    end
    return out
end

local function SelectedCurse()
    local list = KnownCurses()
    if table.getn(list) == 0 then return nil, list end
    local want = RallyPowerCP_Settings.lockCurse
    for _, c in ipairs(list) do if c.name == want then return c, list end end
    return list[1], list
end

-- highest "Create Soulstone" rank in the spellbook
local function CreateSpell()
    local found = nil
    local i = 1
    while true do
        local sn = GetSpellName(i, "spell")
        if not sn then break end
        if string.find(sn, "Create Soulstone", 1, true) then found = i end
        i = i + 1
    end
    return found
end

local function BuildUI()
    if strip then return end
    strip = RallyPowerCP.NewStrip("warlock", "Warlock")

    -- ARMOR
    strip:AddButton{
        key = "armor",
        refresh = function(b)
            local a = BestArmor()
            if not a then
                b:SetIcon(nil); b:SetLabel("|cffffd100Armor|r")
                b:SetSub("|cff888888none known|r"); b:SetTimer(""); b:SetState("off"); return
            end
            b:SetIcon(a._icon); b:SetLabel("|cffffd100Armor|r")
            b:SetSub(a.name .. (a._sim and " |cffff8800*|r" or ""))
            if RallyPowerCP.IsTestMode() then
                if armorDeadline > GetTime() then
                    b:SetState("good"); b:SetTimer(RallyPowerCP.FmtTime(armorDeadline - GetTime()))
                else
                    b:SetState("need"); b:SetTimer("")
                end
                return
            end
            if ArmorUp(a) then
                b:SetState("good")
                if armorDeadline > GetTime() then
                    b:SetTimer(RallyPowerCP.FmtTime(armorDeadline - GetTime()))
                else b:SetTimer("") end
            else
                b:SetState("need"); b:SetTimer("")
            end
        end,
        onClick = function(b)
            local a = BestArmor()
            if not a then return end
            if RallyPowerCP.IsTestMode() then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[test]|r would cast " .. a.name)
                armorDeadline = GetTime() + a.dur
                return
            end
            CastSpellByName(a.name)
            armorDeadline = GetTime() + a.dur
        end,
        tooltip = function(b, tt)
            tt:AddLine("Armor")
            local a = BestArmor()
            if a then tt:AddLine(a.name, 1, 1, 1); tt:AddLine("Click to refresh.", 0.6, 0.6, 0.6) end
        end,
    }

    -- SOULSTONE
    strip:AddButton{
        key = "soulstone",
        refresh = function(b)
            b:SetLabel("|cffffd100Soulstone|r")
            local bag, slot, name = RallyPowerCP.FindBagItem("Soulstone")
            if bag then
                b:SetIcon(GetContainerItemInfo(bag, slot))
                b:SetSub(name)
                local start, dur = GetContainerItemCooldown(bag, slot)
                if start and dur and dur > 1.5 and (start + dur) > GetTime() then
                    b:SetState("need")
                    b:SetTimer(RallyPowerCP.FmtTime(start + dur - GetTime()))
                else
                    b:SetState("good"); b:SetTimer("")
                end
            else
                local ci = CreateSpell()
                b:SetIcon(ci and GetSpellTexture(ci, "spell") or nil)
                b:SetSub("|cff888888create one|r"); b:SetTimer(""); b:SetState("off")
            end
        end,
        onClick = function(b)
            local bag, slot = RallyPowerCP.FindBagItem("Soulstone")
            if not bag then
                local ci = CreateSpell()
                if ci then CastSpell(ci, "spell") end
                return
            end
            local start, dur = GetContainerItemCooldown(bag, slot)
            if start and dur and dur > 1.5 and (start + dur) > GetTime() then return end
            -- use on friendly target, else self
            UseContainerItem(bag, slot)
            if SpellIsTargeting() then
                local unit = "player"
                if UnitExists("target") and UnitIsFriend("player", "target") then unit = "target" end
                if SpellCanTargetUnit(unit) then SpellTargetUnit(unit)
                else SpellStopTargeting() end
            end
        end,
        tooltip = function(b, tt)
            tt:AddLine("Soulstone")
            local bag, slot, name = RallyPowerCP.FindBagItem("Soulstone")
            if bag then
                tt:AddLine(name, 1, 1, 1)
                tt:AddLine("Click: use on friendly target (or yourself).", 0.6, 0.6, 0.6)
            else
                tt:AddLine("None in bags - click to create one.", 1, 0.7, 0.4)
            end
        end,
    }

    -- CURSE
    strip:AddButton{
        key = "curse",
        refresh = function(b)
            local c = SelectedCurse()
            if not c then
                b:SetIcon(nil); b:SetLabel("|cffffd100Curse|r")
                b:SetSub("|cff888888none known|r"); b:SetTimer(""); b:SetState("off"); return
            end
            b:SetIcon(c._icon); b:SetLabel("|cffffd100Curse|r")
            b:SetSub(string.gsub(c.name, "^Curse of ", "") .. (c._sim and " |cffff8800*|r" or ""))
            if RallyPowerCP.IsTestMode() then
                local a = curseApplied[c.name]
                if a and a.deadline > GetTime() then
                    b:SetState("good"); b:SetTimer(RallyPowerCP.FmtTime(a.deadline - GetTime()))
                else
                    b:SetState("need"); b:SetTimer("")
                end
                return
            end
            if not UnitExists("target") or UnitIsFriend("player", "target") then
                b:SetTimer(""); b:SetState("off"); return
            end
            if RallyPowerCP.UnitHasDebuffEntry("target", c) then
                b:SetState("good")
                local a = curseApplied[c.name]
                if a and a.target == UnitName("target") and a.deadline > GetTime() then
                    b:SetTimer(RallyPowerCP.FmtTime(a.deadline - GetTime()))
                else b:SetTimer("") end
            else
                b:SetState("need"); b:SetTimer("")
            end
        end,
        onClick = function(b)
            local c = SelectedCurse()
            if not c then return end
            if RallyPowerCP.IsTestMode() then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[test]|r would apply " .. c.name)
                curseApplied[c.name] = { target = "(test)", deadline = GetTime() + c.dur }
                return
            end
            if not UnitExists("target") or UnitIsFriend("player", "target") then return end
            if RallyPowerCP.CastAtTarget(c.name) then
                curseApplied[c.name] = { target = UnitName("target"), deadline = GetTime() + c.dur }
            end
        end,
        onWheel = function(b, delta)
            local sel, list = SelectedCurse()
            local n = table.getn(list)
            if n == 0 then return end
            local idx = 1
            for i, c in ipairs(list) do if c.name == sel.name then idx = i end end
            idx = idx + (delta > 0 and -1 or 1)
            if idx < 1 then idx = n elseif idx > n then idx = 1 end
            RallyPowerCP_Settings.lockCurse = list[idx].name
        end,
        tooltip = function(b, tt)
            tt:AddLine("Curse duty")
            local c = SelectedCurse()
            if c then
                tt:AddLine(c.name, 1, 1, 1)
                tt:AddLine("Scroll to change, click to apply to your target.", 0.6, 0.6, 0.6)
            end
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

-- Options descriptor (Buttons tab). The curse select binds to the lockCurse
-- key the mouse-wheel writes; `get` shows the effective (fallback) selection.
M.optionsInfo = {
    { type = "header", label = "Strip buttons" },
    { type = "check", key = "btn_armor", label = "Armor button", default = true,
      onChange = function() RallyPowerCP.ReflowStrips() end },
    { type = "check", key = "btn_soulstone", label = "Soulstone button", default = true,
      onChange = function() RallyPowerCP.ReflowStrips() end },
    { type = "check", key = "btn_curse", label = "Curse button", default = true,
      onChange = function() RallyPowerCP.ReflowStrips() end },
    { type = "header", label = "Curse duty" },
    { type = "select", key = "lockCurse", label = "Curse",
      values = function()
          local out = {}
          for _, c in ipairs(KnownCurses()) do
              local nm = string.gsub(c.name, "^Curse of ", "")
              if c._sim then nm = nm .. " *" end
              table.insert(out, { value = c.name, text = nm })
          end
          return out
      end,
      get = function()
          local c = SelectedCurse()
          if c then return c.name end
          return nil
      end },
}
