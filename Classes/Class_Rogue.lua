--=============================================================================
-- Class_Rogue.lua  -  Rogue module for RallyPowerCP
--
-- Three buttons on the shared strip:
--
--   EXPOSE ARMOR - duty button: green while Expose Armor is on your target,
--                  red when it's missing. Click to apply (needs combo points -
--                  the game will tell you if you have none).
--   MAIN HAND    - poison slot. Wheel picks which poison TYPE to use (from the
--   OFF HAND       poisons actually in your bags - highest rank wins); click
--                  applies it to that weapon. Green with the real remaining
--                  time + charges while the weapon is coated, red when bare.
--
-- Weapon poison state comes from GetWeaponEnchantInfo() - the real enchant
-- expiration and charges, not a guess. Debuff detection matches your spellbook
-- texture with SuperWoW id-learning on top.
--=============================================================================

local M = RallyPowerCP:NewClass("ROGUE")

local EXPOSE = { name = "Expose Armor", dur = 30 }
local POISONS = { "Instant Poison", "Deadly Poison", "Crippling Poison",
                  "Mind-numbing Poison", "Wound Poison" }

local strip
local exposeApplied = nil    -- { target, deadline }

-- which poison types are in the bags right now? returns ordered list of names.
-- Test mode lists every type so the cycle can be previewed with empty bags.
local function BagPoisons()
    local out = {}
    local test = RallyPowerCP.IsTestMode()
    for _, p in ipairs(POISONS) do
        local bag = RallyPowerCP.FindBagItem(p)
        if bag or test then table.insert(out, p) end
    end
    return out
end

local function SelectedPoison(handKey)
    local list = BagPoisons()
    if table.getn(list) == 0 then return nil, list end
    RallyPowerCP_Settings.roguePoison = RallyPowerCP_Settings.roguePoison or {}
    local want = RallyPowerCP_Settings.roguePoison[handKey]
    for _, p in ipairs(list) do if p == want then return p, list end end
    return list[1], list
end

local function CyclePoison(handKey, delta)
    local sel, list = SelectedPoison(handKey)
    local n = table.getn(list)
    if n == 0 then return end
    local idx = 1
    for i, p in ipairs(list) do if p == sel then idx = i end end
    idx = idx + (delta > 0 and -1 or 1)
    if idx < 1 then idx = n elseif idx > n then idx = 1 end
    RallyPowerCP_Settings.roguePoison = RallyPowerCP_Settings.roguePoison or {}
    RallyPowerCP_Settings.roguePoison[handKey] = list[idx]
end

local function ApplyPoison(handKey)
    local sel = SelectedPoison(handKey)
    if not sel then return end
    local bag, slot = RallyPowerCP.FindBagItem(sel)
    if not bag then return end
    UseContainerItem(bag, slot)                 -- pick up the "apply" cursor
    PickupInventoryItem(handKey == "mh" and 16 or 17)  -- drop it on the weapon
end

-- one poison-slot button definition
local function PoisonButton(handKey, label)
    return {
        key = "poison_" .. handKey,
        refresh = function(b)
            b:SetLabel("|cffffd100" .. label .. "|r")
            local sel = SelectedPoison(handKey)
            if sel then
                local bag, slot = RallyPowerCP.FindBagItem(sel)
                b:SetIcon(bag and GetContainerItemInfo(bag, slot) or nil)
                b:SetSub(string.gsub(sel, " Poison$", ""))
            else
                b:SetIcon(nil); b:SetSub("|cff888888no poisons|r")
            end
            local hasMH, expMH, chMH, hasOH, expOH, chOH = GetWeaponEnchantInfo()
            local has, exp, ch
            if handKey == "mh" then has, exp, ch = hasMH, expMH, chMH
            else has, exp, ch = hasOH, expOH, chOH end
            if has then
                b:SetState("good")
                local t = (exp or 0) / 1000
                local txt = RallyPowerCP.FmtTime(t)
                if ch and ch > 0 then txt = txt .. " |cffaaaaaa(" .. ch .. ")|r" end
                b:SetTimer(txt)
            else
                b:SetState(sel and "need" or "off"); b:SetTimer("")
            end
        end,
        onClick = function(b) ApplyPoison(handKey) end,
        onWheel = function(b, delta) CyclePoison(handKey, delta) end,
        tooltip = function(b, tt)
            tt:AddLine(label .. " poison")
            local sel = SelectedPoison(handKey)
            if sel then
                tt:AddLine(sel, 1, 1, 1)
                tt:AddLine("Scroll to change, click to apply.", 0.6, 0.6, 0.6)
            else
                tt:AddLine("No poisons in your bags.", 1, 0.5, 0.5)
            end
        end,
    }
end

local function BuildUI()
    if strip then return end
    strip = RallyPowerCP.NewStrip("rogue", "Rogue")

    -- EXPOSE ARMOR
    strip:AddButton{
        key = "expose",
        refresh = function(b)
            local sp = RallyPowerCP.FindSpell(EXPOSE.name)
            local test = RallyPowerCP.IsTestMode()
            if not sp and not test then
                b:SetIcon(nil); b:SetLabel("|cffffd100Expose|r")
                b:SetSub("|cff888888not learned|r"); b:SetTimer(""); b:SetState("off"); return
            end
            if sp then EXPOSE._tex = RallyPowerCP.TexBase(sp.texture) end
            b:SetIcon(sp and sp.texture or nil)
            b:SetLabel("|cffffd100Expose|r")
            b:SetSub("Armor" .. ((not sp) and " |cffff8800*|r" or ""))
            if test then
                local a = exposeApplied
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
            if RallyPowerCP.UnitHasDebuffEntry("target", EXPOSE) then
                b:SetState("good")
                local a = exposeApplied
                if a and a.target == UnitName("target") and a.deadline > GetTime() then
                    b:SetTimer(RallyPowerCP.FmtTime(a.deadline - GetTime()))
                else b:SetTimer("") end
            else
                b:SetState("need"); b:SetTimer("")
            end
        end,
        onClick = function(b)
            if RallyPowerCP.IsTestMode() then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[test]|r would apply Expose Armor")
                exposeApplied = { target = "(test)", deadline = GetTime() + EXPOSE.dur }
                return
            end
            if not UnitExists("target") or UnitIsFriend("player", "target") then return end
            if RallyPowerCP.CastAtTarget(EXPOSE.name) then
                exposeApplied = { target = UnitName("target"), deadline = GetTime() + EXPOSE.dur }
            end
        end,
        tooltip = function(b, tt)
            tt:AddLine("Expose Armor duty")
            tt:AddLine("Click to apply to your target (uses combo points).", 0.6, 0.6, 0.6)
        end,
    }

    strip:AddButton(PoisonButton("mh", "Main Hand"))
    strip:AddButton(PoisonButton("oh", "Off Hand"))

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

-- Options descriptor (Buttons tab). The poison selects bind to the same
-- roguePoison.mh/.oh keys the mouse-wheel writes; `get` shows the effective
-- (fallback) selection.
local function PoisonSelectEntry(handKey, label)
    return { type = "select", key = "roguePoison." .. handKey, label = label,
      values = function()
          local out = {}
          for _, p in ipairs(BagPoisons()) do
              table.insert(out, { value = p, text = string.gsub(p, " Poison$", "") })
          end
          return out
      end,
      get = function()
          local p = SelectedPoison(handKey)   -- first return only (drops the list)
          return p
      end }
end

M.optionsInfo = {
    { type = "header", label = "Strip buttons" },
    { type = "check", key = "btn_expose", label = "Expose Armor button", default = true,
      onChange = function() RallyPowerCP.ReflowStrips() end },
    { type = "check", key = "btn_poison_mh", label = "Main-hand button", default = true,
      onChange = function() RallyPowerCP.ReflowStrips() end },
    { type = "check", key = "btn_poison_oh", label = "Off-hand button", default = true,
      onChange = function() RallyPowerCP.ReflowStrips() end },
    { type = "header", label = "Poisons" },
    PoisonSelectEntry("mh", "Main hand"),
    PoisonSelectEntry("oh", "Off hand"),
}
