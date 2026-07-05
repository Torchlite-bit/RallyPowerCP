--=============================================================================
-- Class_Shaman.lua  -  Shaman totem module for RallyPowerCP
--
-- Shaman is the first class that does NOT use the buff grid: totems are party
-- auras dropped at your feet, not buffs cast on other players. So instead of the
-- class-row grid + player pop-out, the Shaman gets its OWN compact strip of four
-- element buttons (Earth / Fire / Water / Air) - the "cycle button" pattern the
-- other utility classes (Mage debuff, Warlock curse, Hunter sting, Warrior
-- debuff) will reuse.
--
-- Per element button:
--   * Mouse-wheel  = pick which totem to drop for that element (known totems only)
--   * Left-click   = drop the selected totem (self-cast; works in combat)
--   * Shows the totem's real spellbook icon, green when it's down (with a
--     countdown) / red when it isn't.
--
-- Timers are cast-derived (start when YOU drop the totem) - the same approach
-- the buff bar uses, since the 1.12 client has no totem-duration API. The real
-- icon and rank come from your spellbook (no icon guessing). Totem NAMES are the
-- exact spell names so CastSpellByName + spellbook lookup match on Turtle.
--
-- SuperWoW note: this v1 tracks/drops YOUR OWN totems. Cross-shaman coordination
-- ("whose totem covers which party") uses SuperWoW's totem owner-suffix and
-- lands with the shared assignment/sync milestone.
--=============================================================================

local M = RallyPowerCP:NewClass("SHAMAN")

local HAS_SUPERWOW = (SUPERWOW_VERSION ~= nil)

-- Totem data. name = exact spell name; dur = seconds (vanilla defaults - adjust
-- if Turtle differs, like blessings did); icon = fallback only (the real icon is
-- read from your spellbook once known).
local ELEMENTS = {
  { key = "Earth", tint = {0.60,0.40,0.20}, totems = {
      { name = "Strength of Earth Totem", dur = 120, icon = "Spell_Nature_EarthBindTotem" },
      { name = "Stoneskin Totem",         dur = 120, icon = "Spell_Nature_StoneSkinTotem" },
      { name = "Tremor Totem",            dur = 120, icon = "Spell_Nature_TremorTotem" },
      { name = "Earthbind Totem",         dur = 45,  icon = "Spell_Nature_StrengthOfEarthTotem" },
      { name = "Stoneclaw Totem",         dur = 15,  icon = "Spell_Nature_StoneClawTotem" },
  }},
  { key = "Fire", tint = {0.83,0.41,0.12}, totems = {
      { name = "Searing Totem",           dur = 60,  icon = "Spell_Fire_SearingTotem" },
      { name = "Magma Totem",             dur = 20,  icon = "Spell_Fire_SelfDestruct" },
      { name = "Fire Nova Totem",         dur = 5,   icon = "Spell_Fire_SealOfFire" },
      { name = "Flametongue Totem",       dur = 120, icon = "Spell_Nature_GuardianWard" },
      { name = "Frost Resistance Totem",  dur = 120, icon = "Spell_FrostResistanceTotem_01" },
  }},
  { key = "Water", tint = {0.18,0.50,0.70}, totems = {
      { name = "Mana Spring Totem",       dur = 60,  icon = "Spell_Nature_ManaRegenTotem" },
      { name = "Healing Stream Totem",    dur = 60,  icon = "INV_Spear_04" },
      { name = "Mana Tide Totem",         dur = 12,  icon = "Spell_Frost_SummonWaterElemental" },
      { name = "Poison Cleansing Totem",  dur = 120, icon = "Spell_Nature_PoisonCleansingTotem" },
      { name = "Disease Cleansing Totem", dur = 120, icon = "Spell_Nature_DiseaseCleansingTotem" },
      { name = "Fire Resistance Totem",   dur = 120, icon = "Spell_FireResistanceTotem_01" },
  }},
  { key = "Air", tint = {0.12,0.62,0.53}, totems = {
      { name = "Windfury Totem",          dur = 120, icon = "Spell_Nature_Windfury" },
      { name = "Grace of Air Totem",      dur = 120, icon = "Spell_Nature_InvisibilityTotem" },
      { name = "Nature Resistance Totem", dur = 120, icon = "Spell_Nature_NatureResistanceTotem" },
      { name = "Windwall Totem",          dur = 120, icon = "Spell_Nature_EarthBind" },
      { name = "Grounding Totem",         dur = 45,  icon = "Spell_Nature_GroundingTotem" },
      { name = "Sentry Totem",            dur = 300, icon = "Spell_Nature_RemoveCurse" },
      { name = "Tranquil Air Totem",      dur = 120, icon = "Spell_Nature_Brilliance" },
  }},
}

-- Layout
local STRIP_W = 138
local BTN_H   = 30
local SKIN = {
    bgFile   = "Interface\\AddOns\\RallyPowerCP\\Skins\\Smooth",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = false, tileSize = 8, edgeSize = 8,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
}
local C_DOWN = { 0, 0.7, 0, 0.5 }     -- totem is out (green)
local C_OUT  = { 1, 0,   0, 0.5 }     -- nothing down (red)

-- State
local strip                 -- the frame
local buttons = {}          -- one per element
local known = {}            -- [totemName] = { index, texture }
local active = {}           -- [elementKey] = { name, deadline }
local built = false

RallyPowerCP_Settings = RallyPowerCP_Settings or {}

local function fmt(t)
    if not t or t < 0 then return "" end
    local m = math.floor(t / 60)
    return string.format("%d:%02d", m, math.floor(t - m * 60))
end

-- Which totems in an element does the player actually know? (ordered subset)
local function KnownList(el)
    local out = {}
    for _, t in ipairs(el.totems) do
        if known[t.name] then table.insert(out, t) end
    end
    return out
end

-- Currently selected totem for an element (persisted by name), defaulting to the
-- first known totem.
local function Selected(el)
    local list = KnownList(el)
    if table.getn(list) == 0 then return nil end
    RallyPowerCP_Settings.shamanSel = RallyPowerCP_Settings.shamanSel or {}
    local want = RallyPowerCP_Settings.shamanSel[el.key]
    if want then
        for _, t in ipairs(list) do if t.name == want then return t end end
    end
    return list[1]
end

local function SetSelected(el, totem)
    RallyPowerCP_Settings.shamanSel = RallyPowerCP_Settings.shamanSel or {}
    RallyPowerCP_Settings.shamanSel[el.key] = totem.name
end

-- Rebuild the known-totem map from the spellbook (captures real icon + index).
local function RebuildKnownTotems()
    for k in pairs(known) do known[k] = nil end
    local i = 1
    while true do
        local sn = GetSpellName(i, "spell")
        if not sn then break end
        -- keep the highest-rank slot (later entries) for each spell name
        for _, el in ipairs(ELEMENTS) do
            for _, t in ipairs(el.totems) do
                if t.name == sn then
                    known[sn] = { index = i, texture = GetSpellTexture(i, "spell") }
                end
            end
        end
        i = i + 1
    end
end

-- Drop the selected totem for an element.
local function DropTotem(el)
    local t = Selected(el)
    if not t then return end
    local slot = known[t.name]
    if not slot then return end

    -- don't start a false timer if it's on cooldown
    local start, dur = GetSpellCooldown(slot.index, "spell")
    if start and dur and dur > 1.5 and (start + dur - GetTime()) > 1.5 then
        return
    end

    if HAS_SUPERWOW then
        CastSpellByName(t.name)          -- totems self-cast at your feet, no unit
    else
        CastSpell(slot.index, "spell")
    end
    active[el.key] = { name = t.name, deadline = GetTime() + t.dur }
end

-- ---- UI ----
local function ButtonOnClick()
    if arg1 == "RightButton" then
        active[this.elKey] = nil         -- clear the tracked timer (manual pickup)
        M.Refresh()
        return
    end
    for _, el in ipairs(ELEMENTS) do
        if el.key == this.elKey then DropTotem(el); break end
    end
    M.Refresh()
end

local function ButtonOnWheel()
    local el
    for _, e in ipairs(ELEMENTS) do if e.key == this.elKey then el = e end end
    if not el then return end
    local list = KnownList(el)
    local n = table.getn(list)
    if n == 0 then return end
    local cur = Selected(el)
    local idx = 1
    for i, t in ipairs(list) do if t.name == cur.name then idx = i end end
    idx = idx + (arg1 > 0 and -1 or 1)
    if idx < 1 then idx = n elseif idx > n then idx = 1 end
    SetSelected(el, list[idx])
    M.Refresh()
end

local function ButtonOnEnter()
    local el
    for _, e in ipairs(ELEMENTS) do if e.key == this.elKey then el = e end end
    if not el then return end
    GameTooltip:SetOwner(this, "ANCHOR_LEFT")
    GameTooltip:AddLine(el.key .. " Totem")
    local sel = Selected(el)
    if sel then
        GameTooltip:AddLine(sel.name, 1, 1, 1)
        GameTooltip:AddLine("Scroll to change, click to drop.", 0.6, 0.6, 0.6)
    else
        GameTooltip:AddLine("No " .. el.key .. " totem learned.", 1, 0.5, 0.5)
    end
    GameTooltip:Show()
end

local function BuildStrip()
    if built then return end
    strip = CreateFrame("Frame", "RallyPowerCP_ShamanBar", UIParent)
    strip:SetWidth(STRIP_W)
    strip:SetHeight(BTN_H * table.getn(ELEMENTS) + 20)
    strip:SetMovable(true)
    strip:EnableMouse(true)
    strip:RegisterForDrag("LeftButton")
    strip:SetScript("OnDragStart", function() strip:StartMoving() end)
    strip:SetScript("OnDragStop", function()
        strip:StopMovingOrSizing()
        local p, _, _, x, y = strip:GetPoint()
        RallyPowerCP_Settings.shamanPos = { p = p, x = x, y = y }
    end)

    -- restore position
    local pos = RallyPowerCP_Settings.shamanPos
    if pos then strip:SetPoint(pos.p, UIParent, pos.p, pos.x, pos.y)
    else strip:SetPoint("CENTER", UIParent, "CENTER", 260, 0) end

    -- header (also a drag handle)
    local hdr = strip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdr:SetPoint("TOP", strip, "TOP", 0, -2)
    hdr:SetText("|cffffd100Totems|r")

    local y = -18
    for _, el in ipairs(ELEMENTS) do
        local b = CreateFrame("Button", "RallyPowerCP_Totem" .. el.key, strip)
        b:SetWidth(STRIP_W); b:SetHeight(BTN_H)
        b:SetPoint("TOPLEFT", strip, "TOPLEFT", 0, y)
        b:SetBackdrop(SKIN)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:EnableMouseWheel(true)
        b.elKey = el.key

        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetWidth(BTN_H - 6); icon:SetHeight(BTN_H - 6)
        icon:SetPoint("LEFT", b, "LEFT", 3, 0)
        b.icon = icon

        local eln = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        eln:SetPoint("TOPLEFT", icon, "TOPRIGHT", 5, -1)
        eln:SetJustifyH("LEFT")
        b.eln = eln

        local tn = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        tn:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 5, 1)
        tn:SetWidth(STRIP_W - BTN_H - 34); tn:SetJustifyH("LEFT")
        b.tn = tn

        local tm = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        tm:SetPoint("RIGHT", b, "RIGHT", -4, 0)
        tm:SetJustifyH("RIGHT")
        b.tm = tm

        b:SetScript("OnClick", ButtonOnClick)
        b:SetScript("OnMouseWheel", ButtonOnWheel)
        b:SetScript("OnEnter", ButtonOnEnter)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)

        buttons[el.key] = b
        y = y - BTN_H
    end

    -- timer tick
    local accum = 0
    strip:SetScript("OnUpdate", function()
        accum = accum + (arg1 or 0)
        if accum < 0.25 then return end
        accum = 0
        M.Refresh()
    end)

    built = true
end

function M.Refresh()
    if not built then return end
    local now = GetTime()
    for _, el in ipairs(ELEMENTS) do
        local b = buttons[el.key]
        local sel = Selected(el)
        b.eln:SetText("|cffffd100" .. el.key .. "|r")

        if sel then
            local slot = known[sel.name]
            b.icon:SetTexture((slot and slot.texture) or ("Interface\\Icons\\" .. sel.icon))
            -- strip the trailing " Totem" for the compact sublabel
            local short = string.gsub(sel.name, " Totem$", "")
            b.tn:SetText(short)
        else
            b.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            b.tn:SetText("|cff888888none|r")
        end

        local a = active[el.key]
        if a and a.deadline > now then
            b:SetBackdropColor(C_DOWN[1], C_DOWN[2], C_DOWN[3], C_DOWN[4])
            b.icon:SetAlpha(1)
            b.tm:SetText(fmt(a.deadline - now))
        else
            if a then active[el.key] = nil end
            b:SetBackdropColor(C_OUT[1], C_OUT[2], C_OUT[3], C_OUT[4])
            b.icon:SetAlpha(sel and 0.5 or 0.3)
            b.tm:SetText("")
        end
    end
end

-- ---- module hooks called by the Core ----
function M:OnActivate()
    BuildStrip()
    RebuildKnownTotems()
    self.Refresh()
    if RallyPowerCP_Settings.shamanHidden then strip:Hide() else strip:Show() end
end

function M:Toggle()
    if not built then BuildStrip() end
    if strip:IsShown() then
        strip:Hide(); RallyPowerCP_Settings.shamanHidden = true
    else
        strip:Show(); RallyPowerCP_Settings.shamanHidden = false
    end
end

-- keep known totems fresh as ranks are learned
local ev = CreateFrame("Frame")
ev:RegisterEvent("SPELLS_CHANGED")
ev:SetScript("OnEvent", function()
    if built then RebuildKnownTotems(); M.Refresh() end
end)
