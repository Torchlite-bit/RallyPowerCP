--=============================================================================
-- Aegis_Strip.lua  -  shared utility-strip engine
--
-- The reusable machinery behind every "cycle button" class (Hunter stings,
-- Warlock curses/armor/soulstone, Rogue poisons/expose, Warrior debuffs, and
-- eventually a refactored Shaman): a movable titled strip of skinned buttons,
-- where each button is pure BEHAVIOUR supplied by the class module:
--
--   strip = AegisRP.NewStrip("hunter", "Stings")
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

AegisRP_Settings = AegisRP_Settings or {}

-- Registry of live strips ([key] = strip object). The options UI iterates it
-- for re-flow, scale and position resets; only the active class's strip exists.
AegisRP.strips = AegisRP.strips or {}

local SKIN = {
    bgFile   = "Interface\\AddOns\\Aegis_RallyPower\\Skins\\Smooth",
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
function AegisRP.TexBase(path)
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
function AegisRP.FindSpell(name)
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
function AegisRP.FindBagItem(pattern)
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
local inv = CreateFrame("Frame", "AegisRP_StripCacheWatch")
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
function AegisRP.UnitHasDebuffEntry(unit, entry)
    if not UnitExists(unit) then return false end
    entry._ids = entry._ids or {}
    local j = 1
    while j <= 24 do
        local tex, _, _, id = UnitDebuff(unit, j)
        if not tex then break end
        local base = AegisRP.TexBase(tex)
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
function AegisRP.CastAtTarget(name)
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
AegisRP.FmtTime = fmtTime

local function Btn_SetIcon(self, tex)  self.icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark") end
local function Btn_SetLabel(self, txt) self.eln:SetText(txt or "") end
local function Btn_SetSub(self, txt)   self.tn:SetText(txt or "") end
local function Btn_SetTimer(self, txt) self.tm:SetText(txt or "") end

-- Optional second icon (paladin-bar look: class icon + buff icon side by
-- side); created lazily so single-icon buttons pay nothing.
local function Btn_SetIcon2(self, tex)
    if not self.icon2 then
        if not tex then return end
        local i2 = self:CreateTexture(nil, "ARTWORK")
        i2:SetWidth(26); i2:SetHeight(26)
        i2:SetPoint("LEFT", self, "LEFT", 33, 0)
        self.icon2 = i2
    end
    if tex then self.icon2:SetTexture(tex); self.icon2:Show()
    else self.icon2:Hide() end
end

local function Btn_SetState(self, st)
    local c = COLORS[st] or COLORS.off
    local a = AegisRP_Settings.stripAlpha
    if a == nil then a = c[4] end                 -- Transparency slider (default 0.5)
    self:SetBackdropColor(c[1], c[2], c[3], a)
    self.icon:SetAlpha(st == "good" and 1 or 0.55)
    if self.icon2 then self.icon2:SetAlpha(st == "good" and 1 or 0.55) end
end

--------------------------------------------------------------------------
-- Scale grip, borrowed from PallyPower's resize corner (same art, same
-- cursor math as PallyPower_StartScaling/ScaleFrame) but self-contained:
-- the legacy functions hard-code their own frame names and PP_PerUser
-- keys, so they are not callable for our frames. Drag the grip and the
-- frame rescales around its TOPLEFT (clamped 0.5-2.0); scale and the
-- re-anchored position persist per frame.
--------------------------------------------------------------------------

local GRIP_TEX = "Interface\\AddOns\\Aegis_RallyPower\\PallyPower-ResizeGrip"
local scaling = {}
local scaleDriver = CreateFrame("Frame")
scaleDriver:Hide()

local function ApplyScale(frame, scale)
    if scale < 0.5 then scale = 0.5 elseif scale > 2 then scale = 2 end
    local old = frame:GetScale() or 1
    local x = (frame:GetLeft() or 0) * old
    local y = (frame:GetTop() or 0) * old
    frame:SetScale(scale)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    return scale
end

scaleDriver:SetScript("OnUpdate", function()
    local f = scaling.frame
    if not f then scaleDriver:Hide(); return end
    scaling.t = (scaling.t or 0) + (arg1 or 0)
    if scaling.t < 0.08 then return end
    scaling.t = 0
    local eff = f:GetEffectiveScale()
    local left = (f:GetLeft() or 0) * eff
    local top = (f:GetTop() or 0) * eff
    local cx, cy = GetCursorPosition()
    local newscale
    -- drive off the longer axis, exactly like the legacy grip
    if scaling.w > scaling.h then
        if (cx - left) > 32 then newscale = (cx - left) / scaling.w end
    else
        if (top - cy) > 32 then newscale = (top - cy) / scaling.h end
    end
    if newscale then
        newscale = ApplyScale(f, newscale)
        AegisRP_Settings[scaling.scaleKey] = newscale
        if scaling.onChanged then scaling.onChanged(newscale) end
    end
end)

-- onChanged(scale) runs after every applied step - use it to persist the
-- re-anchored position (GetLeft/GetTop are SetPoint-compatible offsets at
-- the frame's current scale).
function AegisRP.AddScaleGrip(frame, scaleKey, onChanged)
    local grip = CreateFrame("Button", nil, frame)
    grip:SetWidth(16); grip:SetHeight(16)
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    grip:SetFrameLevel(frame:GetFrameLevel() + 10)
    grip:SetNormalTexture(GRIP_TEX)
    local hl = grip:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(grip)
    hl:SetTexture(GRIP_TEX)
    hl:SetBlendMode("ADD")
    grip:SetScript("OnMouseDown", function()
        if arg1 ~= "LeftButton" then return end
        if AegisRP_Settings.locked then return end
        scaling.frame = frame
        scaling.scaleKey = scaleKey
        scaling.onChanged = onChanged
        scaling.t = 0
        local pscale = frame:GetParent():GetEffectiveScale()
        scaling.w = frame:GetWidth() * pscale
        scaling.h = frame:GetHeight() * pscale
        scaleDriver:Show()
    end)
    grip:SetScript("OnMouseUp", function()
        scaleDriver:Hide()
        scaling.frame = nil
    end)
    grip:SetScript("OnEnter", function()
        if AegisRP_Settings.tooltips == false then return end
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        if AegisRP_Settings.locked then
            GameTooltip:SetText("Frames locked", 1, 0.5, 0.5)
        else
            GameTooltip:SetText("Drag to scale", 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return grip
end

function AegisRP.NewStrip(key, title)
    local S = { key = key, buttons = {} }
    local posKey = "stripPos_" .. key
    local hidKey = "stripHidden_" .. key

    local f = CreateFrame("Frame", "AegisRP_Strip_" .. key, UIParent)
    S.frame = f
    AegisRP.strips[key] = S
    f:SetWidth(STRIP_W)
    -- per-strip grip scale wins; the global slider resets it (see Core)
    f:SetScale(AegisRP_Settings["stripScale_" .. key]
        or AegisRP_Settings.uiScale or 1)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function()
        if AegisRP_Settings.locked then return end
        f:StartMoving()
    end)
    f:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        -- keep the relative point: grip-scaling re-anchors TOPLEFT->BOTTOMLEFT
        local p, _, rp, x, y = f:GetPoint()
        AegisRP_Settings[posKey] = { p = p, rel = rp, x = x, y = y }
    end)
    -- Right-click on the strip frame (the title area - the buttons swallow
    -- their own clicks) opens the assignment panel.
    f:SetScript("OnMouseUp", function()
        if arg1 == "RightButton" and AegisRP_AssignPanelToggle then
            AegisRP_AssignPanelToggle()
        end
    end)

    local hdr = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdr:SetPoint("TOP", f, "TOP", 0, -2)
    S.header = hdr
    S.title = title
    local function SetHeader()
        if AegisRP.IsTestMode and AegisRP.IsTestMode() then
            hdr:SetText("|cffffd100" .. title .. "|r |cffff8800[TEST]|r")
        else
            hdr:SetText("|cffffd100" .. title .. "|r")
        end
    end
    S.SetHeader = SetHeader
    SetHeader()

    function S:AddButton(def)
        local i = table.getn(self.buttons) + 1
        local b = CreateFrame("Button", "AegisRP_Strip_" .. key .. "_" .. i, f)
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
        b.SetIcon2 = Btn_SetIcon2
        b.def = def

        b:SetScript("OnClick", function()
            if def.onClick then def.onClick(b, arg1); S:Refresh() end
        end)
        b:SetScript("OnMouseWheel", function()
            if def.onWheel then def.onWheel(b, arg1); S:Refresh() end
        end)
        b:SetScript("OnEnter", function()
            -- A button may take over hover entirely (the class-buff buttons use
            -- this for the paladin-style player pop-out instead of a tooltip).
            if def.onEnter then def.onEnter(b); return end
            if AegisRP_Settings.tooltips == false then return end
            if def.tooltip then
                GameTooltip:SetOwner(b, "ANCHOR_LEFT")
                def.tooltip(b, GameTooltip)
                GameTooltip:Show()
            end
        end)
        b:SetScript("OnLeave", function()
            if def.onLeave then def.onLeave(b); return end
            GameTooltip:Hide()
        end)

        table.insert(self.buttons, b)
        return b
    end

    function S:Refresh()
        if self.SetHeader then self.SetHeader() end
        for _, b in ipairs(self.buttons) do
            if b.def.refresh then b.def.refresh(b) end
        end
    end

    -- Re-anchor only the enabled buttons and collapse the frame height around
    -- them. A button is disabled when the options Buttons tab wrote an explicit
    -- false to "btn_" .. lower(def.key); absent means enabled. A def.visible()
    -- predicate gates it further (the class-buff strips use it for roster
    -- presence: absent classes hide, test mode shows all).
    function S:Reflow()
        local horiz = AegisRP_Settings.stripHorizontal and true or false
        local shown = 0
        for _, b in ipairs(self.buttons) do
            if AegisRP_Settings["btn_" .. string.lower(b.def.key or "")] == false
               or (b.def.visible and not b.def.visible()) then
                b:Hide()
            else
                b:ClearAllPoints()
                if horiz then
                    b:SetPoint("TOPLEFT", f, "TOPLEFT", shown * (STRIP_W + BTN_GAP), -18)
                else
                    b:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -18 - shown * (BTN_H + BTN_GAP))
                end
                b:Show()
                shown = shown + 1
            end
        end
        if horiz then
            local w = shown * STRIP_W
            if shown > 1 then w = w + (shown - 1) * BTN_GAP end
            if w < STRIP_W then w = STRIP_W end
            f:SetWidth(w)
            f:SetHeight(18 + BTN_H + 2)
        else
            f:SetWidth(STRIP_W)
            local h = 18 + shown * BTN_H + 2
            if shown > 1 then h = h + (shown - 1) * BTN_GAP end
            f:SetHeight(h)
        end
    end

    function S:Finish()
        self:Reflow()
        local pos = AegisRP_Settings[posKey]
        if pos then f:SetPoint(pos.p, UIParent, pos.rel or pos.p, pos.x, pos.y)
        else f:SetPoint("CENTER", UIParent, "CENTER", 260, 0) end
        -- scale grip (bottom-right, PallyPower art); scaling re-anchors the
        -- frame, so persist the new position alongside the scale
        if not S.grip then
            S.grip = AegisRP.AddScaleGrip(f, "stripScale_" .. key, function()
                AegisRP_Settings[posKey] = { p = "TOPLEFT", rel = "BOTTOMLEFT",
                    x = f:GetLeft(), y = f:GetTop() }
            end)
        end
        local accum = 0
        f:SetScript("OnUpdate", function()
            accum = accum + (arg1 or 0)
            if accum < 0.25 then return end
            accum = 0
            S:Refresh()
        end)
        self:Refresh()
        if AegisRP_Settings[hidKey] then f:Hide() else f:Show() end
    end

    function S:Toggle()
        if f:IsShown() then f:Hide(); AegisRP_Settings[hidKey] = true
        else f:Show(); AegisRP_Settings[hidKey] = false end
    end

    function S:Show() f:Show(); AegisRP_Settings[hidKey] = false end

    return S
end

-- Options hook: re-flow every live strip after a per-button enable changed.
function AegisRP.ReflowStrips()
    for _, S in pairs(AegisRP.strips) do
        S:Reflow()
        S:Refresh()
    end
end
