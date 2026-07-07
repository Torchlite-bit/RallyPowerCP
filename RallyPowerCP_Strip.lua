--=============================================================================
-- RallyPowerCP_Strip.lua  -  shared utility-strip engine
--
-- The reusable machinery behind every "cycle button" class (Hunter stings,
-- Warlock curses/armor/soulstone, Rogue poisons/expose, Warrior debuffs, and
-- eventually a refactored Shaman): a movable titled strip of skinned buttons,
-- where each button is pure BEHAVIOUR supplied by the class module:
--
--   strip = RallyPowerCP.NewStrip("hunter", "Stings")
--   strip:AddButton{
--       key     = "sting",
--       refresh = function(b) ... set b.icon/b.label/b.sub/b.timer + state ... end,
--       onClick = function(b, mouseBtn) ... end,       -- optional
--       onWheel = function(b, delta) ... end,          -- optional
--       tooltip = function(b, tt) tt:AddLine(...) end, -- optional
--   }
--   strip:Finish()   -- sizes the frame, restores position, starts the ticker
--
-- Inside refresh, helpers on the button:
--   b:SetIcon(tex) b:SetLabel(txt) b:SetSub(txt) b:SetTimer(txt)
--   b:SetState("good"|"need"|"off")   -- green / red / neutral backdrop
--
-- The strip is per-character positioned (saved under its key), participates in
-- the Core's OnActivate/Toggle hooks via the returned object, and ticks every
-- 0.25s calling each button's refresh.
--
-- Also exported: spellbook + target-debuff helpers shared by these classes.
--=============================================================================

local HAS_SUPERWOW = (SUPERWOW_VERSION ~= nil)

RallyPowerCP_Settings = RallyPowerCP_Settings or {}

local SKIN = {
    bgFile   = "Interface\\AddOns\\RallyPowerCP\\Skins\\Smooth",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = false, tileSize = 8, edgeSize = 8,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
}
local COLORS = {
    good = { 0, 0.7, 0, 0.5 },
    need = { 1, 0,   0, 0.5 },
    off  = { 0.25, 0.25, 0.25, 0.5 },
}

-- Paladin-template geometry: PallyPower's buttons are 100x34 with a 26px icon;
-- the strip mirrors that exactly so every class reads as one family.
local STRIP_W = 100
local BTN_H   = 34
local BTN_GAP = 2

--------------------------------------------------------------------------
-- shared helpers
--------------------------------------------------------------------------

-- last path segment, lowercased ("Interface\Icons\Foo_Bar" -> "foo_bar")
function RallyPowerCP.TexBase(path)
    if not path then return "" end
    local s = string.lower(path)
    local last = s
    for seg in string.gfind(s, "[^\\/]+") do last = seg end
    return last
end

-- Find a spell in YOUR spellbook by exact name; returns { index, texture } of
-- the highest rank, or nil. Cached: modules call this inside 4Hz refresh ticks,
-- so results are cached and invalidated on SPELLS_CHANGED.
local spellCache = {}
function RallyPowerCP.FindSpell(name)
    local hit = spellCache[name]
    if hit ~= nil then
        if hit == false then return nil end
        return hit
    end
    local found = nil
    local i = 1
    while true do
        local sn = GetSpellName(i, "spell")
        if not sn then break end
        if sn == name then
            found = { index = i, texture = GetSpellTexture(i, "spell") }
        end
        i = i + 1
    end
    spellCache[name] = found or false
    return found
end

-- Bag scan: highest item whose name matches `pattern` (plain find).
-- Returns bag, slot, name or nil. Later bags/slots win, which favours the
-- highest rank when several match. Bag contents are cached and invalidated on
-- BAG_UPDATE, since strips poll every 0.25s.
local bagCache = nil
local function BagContents()
    if bagCache then return bagCache end
    bagCache = {}
    for bag = 0, 4 do
        local n = GetContainerNumSlots(bag)
        for slot = 1, n do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local _, _, iname = string.find(link, "%[(.-)%]")
                if iname then
                    table.insert(bagCache, { bag = bag, slot = slot, name = iname })
                end
            end
        end
    end
    return bagCache
end
function RallyPowerCP.FindBagItem(pattern)
    local fb, fs, fn = nil, nil, nil
    local items = BagContents()
    for _, it in ipairs(items) do
        if string.find(it.name, pattern, 1, true) then
            fb, fs, fn = it.bag, it.slot, it.name
        end
    end
    return fb, fs, fn
end

-- cache invalidation
local inv = CreateFrame("Frame", "RallyPowerCP_StripCacheWatch")
inv:RegisterEvent("SPELLS_CHANGED")
inv:RegisterEvent("BAG_UPDATE")
inv:SetScript("OnEvent", function()
    if event == "SPELLS_CHANGED" then
        for k in pairs(spellCache) do spellCache[k] = nil end
    else
        bagCache = nil
    end
end)

-- Target-debuff presence with SuperWoW id-learning.
-- `entry` carries: _tex (spellbook texture base) and _ids (learned id set).
-- Returns true if the debuff is on the given unit.
function RallyPowerCP.UnitHasDebuffEntry(unit, entry)
    if not UnitExists(unit) then return false end
    entry._ids = entry._ids or {}
    local j = 1
    while j <= 24 do
        local tex, _, _, id = UnitDebuff(unit, j)
        if not tex then break end
        local base = RallyPowerCP.TexBase(tex)
        if HAS_SUPERWOW and id then
            if entry._ids[id] then return true end
            if entry._tex and base == entry._tex then
                entry._ids[id] = true          -- learn the real id from the icon seed
                return true
            end
        elseif entry._tex and base == entry._tex then
            return true
        end
        j = j + 1
    end
    return false
end

-- Cast an offensive spell at your current (hostile) target.
function RallyPowerCP.CastAtTarget(name)
    if not UnitExists("target") then return false end
    if HAS_SUPERWOW then
        CastSpellByName(name, "target")
    else
        CastSpellByName(name)              -- lands on the selected target
    end
    return true
end

--------------------------------------------------------------------------
-- the strip factory
--------------------------------------------------------------------------

local function fmtTime(t)
    if not t or t < 0 then return "" end
    local m = math.floor(t / 60)
    return string.format("%d:%02d", m, math.floor(t - m * 60))
end
RallyPowerCP.FmtTime = fmtTime

local function Btn_SetIcon(self, tex)  self.icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark") end
local function Btn_SetLabel(self, txt) self.eln:SetText(txt or "") end
local function Btn_SetSub(self, txt)   self.tn:SetText(txt or "") end
local function Btn_SetTimer(self, txt) self.tm:SetText(txt or "") end
local function Btn_SetState(self, st)
    local c = COLORS[st] or COLORS.off
    self:SetBackdropColor(c[1], c[2], c[3], c[4])
    self.icon:SetAlpha(st == "good" and 1 or 0.55)
end

function RallyPowerCP.NewStrip(key, title)
    local S = { key = key, buttons = {} }
    local posKey = "stripPos_" .. key
    local hidKey = "stripHidden_" .. key

    local f = CreateFrame("Frame", "RallyPowerCP_Strip_" .. key, UIParent)
    S.frame = f
    f:SetWidth(STRIP_W)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() f:StartMoving() end)
    f:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local p, _, _, x, y = f:GetPoint()
        RallyPowerCP_Settings[posKey] = { p = p, x = x, y = y }
    end)

    local hdr = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdr:SetPoint("TOP", f, "TOP", 0, -2)
    S.header = hdr
    S.title = title
    local function SetHeader()
        if RallyPowerCP.IsTestMode and RallyPowerCP.IsTestMode() then
            hdr:SetText("|cffffd100" .. title .. "|r |cffff8800[TEST]|r")
        else
            hdr:SetText("|cffffd100" .. title .. "|r")
        end
    end
    S.SetHeader = SetHeader
    SetHeader()

    function S:AddButton(def)
        local i = table.getn(self.buttons) + 1
        local b = CreateFrame("Button", "RallyPowerCP_Strip_" .. key .. "_" .. i, f)
        b:SetWidth(STRIP_W); b:SetHeight(BTN_H)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -18 - (i - 1) * (BTN_H + BTN_GAP))
        b:SetBackdrop(SKIN)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:EnableMouseWheel(true)

        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetWidth(26); icon:SetHeight(26)                 -- template icon size
        icon:SetPoint("LEFT", b, "LEFT", 4, 0)
        b.icon = icon

        local eln = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        eln:SetPoint("TOPLEFT", icon, "TOPRIGHT", 4, -3); eln:SetJustifyH("LEFT")
        b.eln = eln

        local tm = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        tm:SetPoint("TOPRIGHT", b, "TOPRIGHT", -4, -5); tm:SetJustifyH("RIGHT")
        b.tm = tm

        local tn = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        tn:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 4, 3)
        tn:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -4, 3)
        tn:SetJustifyH("LEFT")
        b.tn = tn

        b.SetIcon = Btn_SetIcon; b.SetLabel = Btn_SetLabel
        b.SetSub = Btn_SetSub; b.SetTimer = Btn_SetTimer; b.SetState = Btn_SetState
        b.def = def

        b:SetScript("OnClick", function()
            if def.onClick then def.onClick(b, arg1); S:Refresh() end
        end)
        b:SetScript("OnMouseWheel", function()
            if def.onWheel then def.onWheel(b, arg1); S:Refresh() end
        end)
        b:SetScript("OnEnter", function()
            if def.tooltip then
                GameTooltip:SetOwner(b, "ANCHOR_LEFT")
                def.tooltip(b, GameTooltip)
                GameTooltip:Show()
            end
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)

        table.insert(self.buttons, b)
        return b
    end

    function S:Refresh()
        if self.SetHeader then self.SetHeader() end
        for _, b in ipairs(self.buttons) do
            if b.def.refresh then b.def.refresh(b) end
        end
    end

    function S:Finish()
        local n = table.getn(self.buttons)
        local h = 18 + n * BTN_H + 2
        if n > 1 then h = h + (n - 1) * BTN_GAP end
        f:SetHeight(h)
        local pos = RallyPowerCP_Settings[posKey]
        if pos then f:SetPoint(pos.p, UIParent, pos.p, pos.x, pos.y)
        else f:SetPoint("CENTER", UIParent, "CENTER", 260, 0) end
        local accum = 0
        f:SetScript("OnUpdate", function()
            accum = accum + (arg1 or 0)
            if accum < 0.25 then return end
            accum = 0
            S:Refresh()
        end)
        self:Refresh()
        if RallyPowerCP_Settings[hidKey] then f:Hide() else f:Show() end
    end

    function S:Toggle()
        if f:IsShown() then f:Hide(); RallyPowerCP_Settings[hidKey] = true
        else f:Show(); RallyPowerCP_Settings[hidKey] = false end
    end

    function S:Show() f:Show(); RallyPowerCP_Settings[hidKey] = false end

    return S
end
