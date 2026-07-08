--=============================================================================
-- Class_Hunter.lua  -  Hunter sting module for RallyPowerCP
--
-- One cycle button: which sting you maintain on the target.
--   Mouse-wheel = pick the sting (only ones you know)
--   Left-click  = cast it on your current target
--   Green + timer while YOUR sting is on the target, red when the target is
--   missing it, grey with no target.
--
-- Detection matches the debuff's icon against your own spellbook texture (no
-- hard-coded icons); under SuperWoW the real aura id is learned from that seed
-- and matching becomes exact. Timers are cast-derived per target.
--=============================================================================

local M = RallyPowerCP:NewClass("HUNTER")

local STINGS = {
    { name = "Serpent Sting", dur = 15 },
    { name = "Scorpid Sting", dur = 20 },
    { name = "Viper Sting",   dur = 8  },
}

local strip
local applied = {}   -- [stingName] = { target = name, deadline = t }

local function Known()
    local out = {}
    local test = RallyPowerCP.IsTestMode()
    for _, s in ipairs(STINGS) do
        local sp = RallyPowerCP.FindSpell(s.name)
        if sp then
            s._tex = RallyPowerCP.TexBase(sp.texture)
            s._icon = sp.texture
            s._sim = nil
            table.insert(out, s)
        elseif test then
            s._icon = nil
            s._sim = true
            table.insert(out, s)
        end
    end
    return out
end

local function Selected()
    local list = Known()
    if table.getn(list) == 0 then return nil, list end
    local want = RallyPowerCP_Settings.hunterSting
    for _, s in ipairs(list) do
        if s.name == want then return s, list end
    end
    return list[1], list
end

local function BuildUI()
    if strip then return end
    strip = RallyPowerCP.NewStrip("hunter", "Stings")
    strip:AddButton{
        key = "sting",
        refresh = function(b)
            local s = Selected()
            if not s then
                b:SetIcon(nil); b:SetLabel("|cffffd100Sting|r")
                b:SetSub("|cff888888none known|r"); b:SetTimer(""); b:SetState("off")
                return
            end
            b:SetIcon(s._icon)
            b:SetLabel("|cffffd100Sting|r")
            local nm = string.gsub(s.name, " Sting$", "")
            if s._sim then nm = nm .. " |cffff8800*|r" end
            b:SetSub(nm)
            -- Test mode: state runs purely off the simulated timer.
            if RallyPowerCP.IsTestMode() then
                local a = applied[s.name]
                if a and a.deadline > GetTime() then
                    b:SetState("good"); b:SetTimer(RallyPowerCP.FmtTime(a.deadline - GetTime()))
                else
                    b:SetState("need"); b:SetTimer("")
                end
                return
            end
            if not UnitExists("target") or UnitIsFriend("player", "target") then
                b:SetTimer(""); b:SetState("off")
                return
            end
            if RallyPowerCP.UnitHasDebuffEntry("target", s) then
                b:SetState("good")
                local a = applied[s.name]
                if a and a.target == UnitName("target") and a.deadline > GetTime() then
                    b:SetTimer(RallyPowerCP.FmtTime(a.deadline - GetTime()))
                else
                    b:SetTimer("")
                end
            else
                b:SetState("need"); b:SetTimer("")
            end
        end,
        onClick = function(b, btn)
            local s = Selected()
            if not s then return end
            if RallyPowerCP.IsTestMode() then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[test]|r would apply " .. s.name)
                applied[s.name] = { target = "(test)", deadline = GetTime() + s.dur }
                return
            end
            if not UnitExists("target") or UnitIsFriend("player", "target") then return end
            if RallyPowerCP.CastAtTarget(s.name) then
                applied[s.name] = { target = UnitName("target"), deadline = GetTime() + s.dur }
            end
        end,
        onWheel = function(b, delta)
            local sel, list = Selected()
            local n = table.getn(list)
            if n == 0 then return end
            local idx = 1
            for i, s in ipairs(list) do if s.name == sel.name then idx = i end end
            idx = idx + (delta > 0 and -1 or 1)
            if idx < 1 then idx = n elseif idx > n then idx = 1 end
            RallyPowerCP_Settings.hunterSting = list[idx].name
        end,
        tooltip = function(b, tt)
            tt:AddLine("Sting duty")
            local s = Selected()
            if s then
                tt:AddLine(s.name, 1, 1, 1)
                tt:AddLine("Scroll to change, click to apply to your target.", 0.6, 0.6, 0.6)
            else
                tt:AddLine("No stings learned yet.", 1, 0.5, 0.5)
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

-- Options descriptor (Buttons tab). The select binds to the hunterSting key
-- the mouse-wheel writes; `get` shows the effective (fallback) selection.
M.optionsInfo = {
    { type = "header", label = "Sting duty" },
    { type = "check", key = "btn_sting", label = "Sting button", default = true,
      onChange = function() RallyPowerCP.ReflowStrips() end },
    { type = "select", key = "hunterSting", label = "Sting",
      values = function()
          local out = {}
          for _, s in ipairs(Known()) do
              local nm = string.gsub(s.name, " Sting$", "")
              if s._sim then nm = nm .. " *" end
              table.insert(out, { value = s.name, text = nm })
          end
          return out
      end,
      get = function()
          local s = Selected()
          if s then return s.name end
          return nil
      end },
}
