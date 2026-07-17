--=============================================================================
-- Class_Shaman.lua  -  Shaman totem module for AegisRP
--
-- Four cycle buttons on the shared strip engine (paladin-template 100x34
-- buttons): Earth / Fire / Water / Air.
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
