--=============================================================================
-- Class_Shaman.lua  -  Shaman totem module for AegisRP
--
-- Five buttons on the shared strip engine (paladin-template 100x34
-- buttons): All Totems, then Earth / Fire / Water / Air.
--   All Totems   = one click drops the selected totem of every element in
--     order, pacing the casts through the shared global cooldown and
--     skipping totems on a real cooldown; right-click clears every timer.
--   Mouse-wheel  = pick which totem to drop for that element (known totems only)
--   Left-click   = drop the selected totem (self-cast; works in combat)
--   Right-click  = clear the tracked timer (you picked the totem back up)
--   Green + countdown while your totem is down, red when it isn't.
--
-- Icons come from your spellbook (no guessing); timers are cast-derived (the
-- 1.12 client has no totem-duration API), with a cooldown check so a totem on
-- cooldown never starts a false timer. Selected totems save per character.
--
-- v1 tracks/drops YOUR OWN totems; cross-shaman coordination (whose totem
-- covers which party, via SuperWoW's owner-suffix) lands with the sync
-- milestone.
--=============================================================================

local M = AegisRP:NewClass("SHAMAN")

local HAS_SUPERWOW = (SUPERWOW_VERSION ~= nil)

-- name = exact spell name; dur = seconds (vanilla defaults - one-line edits if
-- Turtle differs, as blessings did).
local ELEMENTS = {
  { key = "Earth", totems = {
      { name = "Strength of Earth Totem", dur = 120 },
      { name = "Stoneskin Totem",         dur = 120 },
      { name = "Tremor Totem",            dur = 120 },
      { name = "Earthbind Totem",         dur = 45  },
      { name = "Stoneclaw Totem",         dur = 15  },
  }},
  { key = "Fire", totems = {
      { name = "Searing Totem",           dur = 60  },
      { name = "Magma Totem",             dur = 20  },
      { name = "Fire Nova Totem",         dur = 5   },
      { name = "Flametongue Totem",       dur = 120 },
      { name = "Frost Resistance Totem",  dur = 120 },
  }},
  { key = "Water", totems = {
      { name = "Mana Spring Totem",       dur = 60  },
      { name = "Healing Stream Totem",    dur = 60  },
      { name = "Mana Tide Totem",         dur = 12  },
      { name = "Poison Cleansing Totem",  dur = 120 },
      { name = "Disease Cleansing Totem", dur = 120 },
      { name = "Fire Resistance Totem",   dur = 120 },
  }},
  { key = "Air", totems = {
      { name = "Windfury Totem",          dur = 120 },
      { name = "Grace of Air Totem",      dur = 120 },
      { name = "Nature Resistance Totem", dur = 120 },
      { name = "Windwall Totem",          dur = 120 },
      { name = "Grounding Totem",         dur = 45  },
      { name = "Sentry Totem",            dur = 300 },
      { name = "Tranquil Air Totem",      dur = 120 },
  }},
}

local strip
local active = {}   -- [elementKey] = { name, deadline }

-- Known totems for an element (spellbook lookup gives icon + castability).
-- Test mode lists EVERY totem; unlearned ones carry _sim = true.
local function KnownList(el)
    local out = {}
    local test = AegisRP.IsTestMode()
    for _, t in ipairs(el.totems) do
        local sp = AegisRP.FindSpell(t.name)
        if sp then
            t._icon = sp.texture
            t._index = sp.index
            t._sim = nil
            table.insert(out, t)
        elseif test then
            t._icon = nil
            t._index = nil
            t._sim = true
            table.insert(out, t)
        end
    end
    return out
end

-- Effective selection (design DESIGN_ASSIGNMENTS.md 9): my assignment in the
-- shared model first, my local preference second, first known totem last.
-- An assignment naming a totem I don't know falls through gracefully.
local function Selected(el)
    local list = KnownList(el)
    if table.getn(list) == 0 then return nil, list end
    AegisRP_Settings.shamanSel = AegisRP_Settings.shamanSel or {}
    local want = AegisRP.Assign.GetTotem(UnitName("player"), el.key)
    if want then
        for _, t in ipairs(list) do if t.name == want then return t, list end end
    end
    want = AegisRP_Settings.shamanSel[el.key]
    if want then
        for _, t in ipairs(list) do if t.name == want then return t, list end end
    end
    return list[1], list
end

-- Pick a totem for an element: writes the local preference AND self-assigns in
-- the shared model (wheeling = editing my own row, PallyPower free-assign
-- style). The wheel and the options dropdown both come through here.
local function SelectTotem(el, name)
    AegisRP_Settings.shamanSel = AegisRP_Settings.shamanSel or {}
    AegisRP_Settings.shamanSel[el.key] = name
    AegisRP.Assign.SetTotem(UnitName("player"), el.key, name)
end

local function DropTotem(el)
    local t = Selected(el)
    if not t then return end
    -- Test mode / unlearned: SIMULATE - start the timer, cast nothing.
    if AegisRP.IsTestMode() or t._sim then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[test]|r would drop " .. t.name)
        active[el.key] = { name = t.name, deadline = GetTime() + t.dur }
        return
    end
    -- don't start a false timer if it's on cooldown
    local start, dur = GetSpellCooldown(t._index, "spell")
    if start and dur and dur > 1.5 and (start + dur - GetTime()) > 1.5 then return end
    if HAS_SUPERWOW then
        CastSpellByName(t.name)            -- totems self-cast at your feet
    else
        CastSpell(t._index, "spell")
    end
    active[el.key] = { name = t.name, deadline = GetTime() + t.dur }
end

--------------------------------------------------------------------------
-- "All Totems": one click drops the selected totem of every element, in
-- ELEMENTS order (Earth > Fire > Water > Air). Totems share the global
-- cooldown, so the casts can't all fire in one handler - an OnUpdate pump
-- casts the next one the moment the GCD clears (~1.5s apart; casting from
-- code is legal on the 1.12 client). Totems on a REAL cooldown (Grounding,
-- Mana Tide, Fire Nova...) are skipped, per "all totems not on CD".
--------------------------------------------------------------------------
local dropQueue = {}    -- elements still waiting to cast, head first
local dropTotal = 0     -- queue size at click time (for the x/y display)
local dropAbort = 0     -- failsafe deadline: never pump longer than this
local pump = CreateFrame("Frame")
pump:Hide()
pump.elapsed = 0

local function PumpStop()
    dropQueue = {}
    pump:Hide()
end

pump:SetScript("OnUpdate", function()
    this.elapsed = this.elapsed + arg1
    if this.elapsed < 0.1 then return end
    this.elapsed = 0
    if GetTime() > dropAbort then PumpStop(); return end
    local el = dropQueue[1]
    if not el then PumpStop(); return end
    local t = Selected(el)
    if not t or t._sim then table.remove(dropQueue, 1); return end
    local start, dur = GetSpellCooldown(t._index, "spell")
    if start and dur and dur > 0 and (start + dur - GetTime()) > 0 then
        -- longer than the GCD = a real cooldown: skip this totem entirely
        if dur > 1.5 then table.remove(dropQueue, 1) end
        return                       -- GCD (or just skipped): wait for next tick
    end
    table.remove(dropQueue, 1)
    if HAS_SUPERWOW then
        CastSpellByName(t.name)
    else
        CastSpell(t._index, "spell")
    end
    active[el.key] = { name = t.name, deadline = GetTime() + t.dur }
    if strip then strip:Refresh() end
end)

local function DropAll()
    -- Test mode: DropTotem simulates instantly, so no pacing needed.
    if AegisRP.IsTestMode() then
        for _, el in ipairs(ELEMENTS) do
            if Selected(el) then DropTotem(el) end
        end
        return
    end
    dropQueue = {}
    for _, el in ipairs(ELEMENTS) do
        if Selected(el) then table.insert(dropQueue, el) end
    end
    dropTotal = table.getn(dropQueue)
    if dropTotal == 0 then return end
    dropAbort = GetTime() + 10
    pump.elapsed = 0
    pump:Show()                      -- first cast lands on the next tick
end

-- Class icon for the button face (same source as the class-buff strips:
-- the legacy engine's texture set, our bundled art as fallback).
local function ShamanIcon()
    local id = AegisRP.Token2ClassID and AegisRP.Token2ClassID["SHAMAN"]
    if PallyPower_ClassTexture and id and PallyPower_ClassTexture[id] then
        return PallyPower_ClassTexture[id]
    end
    return "Interface\\AddOns\\Aegis_RallyPower\\Icons\\Shaman"
end

local function AllButton()
    return {
        key = "all",
        refresh = function(b)
            b:SetIcon(ShamanIcon())
            b:SetLabel("|cffffd100All|r")
            local total, down = 0, 0
            local soonest
            for _, el in ipairs(ELEMENTS) do
                if Selected(el) then
                    total = total + 1
                    local a = active[el.key]
                    if a and a.deadline > GetTime() then
                        down = down + 1
                        if not soonest or a.deadline < soonest then soonest = a.deadline end
                    end
                end
            end
            if total == 0 then
                b:SetSub("|cff888888no totems|r"); b:SetTimer(""); b:SetState("off")
            elseif table.getn(dropQueue) > 0 then
                b:SetSub("dropping " .. (dropTotal - table.getn(dropQueue)) .. "/" .. dropTotal)
                b:SetTimer(""); b:SetState("need")
            elseif down >= total then
                b:SetSub("all " .. total .. " down"); b:SetState("good")
                b:SetTimer(soonest and AegisRP.FmtTime(soonest - GetTime()) or "")
            else
                b:SetSub("drop " .. (total - down)); b:SetTimer(""); b:SetState("need")
            end
        end,
        onClick = function(b, btn)
            if btn == "RightButton" then
                PumpStop()
                active = {}          -- picked everything back up
                return
            end
            DropAll()
        end,
        tooltip = function(b, tt)
            tt:AddLine("All Totems")
            tt:AddLine("Click to drop your four selected totems in order,", 0.6, 0.6, 0.6)
            tt:AddLine("pacing through the global cooldown (~1.5s apart).", 0.6, 0.6, 0.6)
            tt:AddLine("Totems on cooldown are skipped.", 0.6, 0.6, 0.6)
            tt:AddLine("Right-click to clear all totem timers.", 0.6, 0.6, 0.6)
        end,
    }
end

local function ElementButton(el)
    return {
        key = el.key,
        refresh = function(b)
            b:SetLabel("|cffffd100" .. el.key .. "|r")
            local sel = Selected(el)
            if sel then
                b:SetIcon(sel._icon)
                local nm = string.gsub(sel.name, " Totem$", "")
                if sel._sim then nm = nm .. " |cffff8800*|r" end
                b:SetSub(nm)
            else
                b:SetIcon(nil)
                b:SetSub("|cff888888none|r")
            end
            local a = active[el.key]
            if a and a.deadline > GetTime() then
                b:SetState("good")
                b:SetTimer(AegisRP.FmtTime(a.deadline - GetTime()))
            else
                if a then active[el.key] = nil end
                b:SetState(sel and "need" or "off")
                b:SetTimer("")
            end
        end,
        onClick = function(b, btn)
            if btn == "RightButton" then
                active[el.key] = nil       -- picked the totem back up
                return
            end
            DropTotem(el)
        end,
        onWheel = function(b, delta)
            local sel, list = Selected(el)
            local n = table.getn(list)
            if n == 0 then return end
            local idx = 1
            for i, t in ipairs(list) do if t.name == sel.name then idx = i end end
            idx = idx + (delta > 0 and -1 or 1)
            if idx < 1 then idx = n elseif idx > n then idx = 1 end
            SelectTotem(el, list[idx].name)
        end,
        tooltip = function(b, tt)
            tt:AddLine(el.key .. " Totem")
            local sel = Selected(el)
            if sel then
                tt:AddLine(sel.name, 1, 1, 1)
                tt:AddLine("Scroll to change, click to drop.", 0.6, 0.6, 0.6)
            else
                tt:AddLine("No " .. el.key .. " totem learned.", 1, 0.5, 0.5)
            end
        end,
    }
end

local function BuildUI()
    if strip then return end
    strip = AegisRP.NewStrip("shaman", "Totems")
    strip:AddButton(AllButton())
    for _, el in ipairs(ELEMENTS) do
        strip:AddButton(ElementButton(el))
    end
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

--------------------------------------------------------------------------
-- Options descriptor (Buttons tab): per-element button enables + totem
-- choices. The selects bind to the same shamanSel.* keys the mouse-wheel
-- writes - dropdown and wheel are two views of one setting.
--------------------------------------------------------------------------
M.optionsInfo = {}
table.insert(M.optionsInfo, { type = "header", label = "Totem buttons" })
table.insert(M.optionsInfo, {
    type = "check", key = "btn_all",
    label = "All Totems button (drop all four)", default = true,
    onChange = function() AegisRP.ReflowStrips() end,
})
for _, el in ipairs(ELEMENTS) do
    local elc = el
    table.insert(M.optionsInfo, {
        type = "check", key = "btn_" .. string.lower(elc.key),
        label = elc.key .. " totem button", default = true,
        onChange = function() AegisRP.ReflowStrips() end,
    })
end
table.insert(M.optionsInfo, { type = "header", label = "Selected totems" })
for _, el in ipairs(ELEMENTS) do
    local elc = el
    table.insert(M.optionsInfo, {
        type = "select", key = "shamanSel." .. elc.key, label = elc.key,
        values = function()
            local out = {}
            for _, t in ipairs(KnownList(elc)) do
                local nm = string.gsub(t.name, " Totem$", "")
                if t._sim then nm = nm .. " *" end
                table.insert(out, { value = t.name, text = nm })
            end
            return out
        end,
        get = function()
            local t = Selected(elc)
            if t then return t.name end
            return nil
        end,
        set = function(v) SelectTotem(elc, v) end,   -- preference + self-assign
    })
end

--------------------------------------------------------------------------
-- Assignment model: register the totem catalog (sync + panel read this).
-- Wids are positional over these fixed lists - append new totems at the END
-- of an element, never reorder (wids must stay stable for the wire).
--------------------------------------------------------------------------
if AegisRP.Assign then
    local twid = 0
    for _, el in ipairs(ELEMENTS) do
        local list = {}
        for _, t in ipairs(el.totems) do
            twid = twid + 1
            table.insert(list, { name = t.name, wid = twid, dur = t.dur })
        end
        AegisRP.Assign.RegisterTotems(el.key, list)
    end
end
