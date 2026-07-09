--=============================================================================
-- RallyPowerCP_UI.lua  -  shared widget factory (loads BEFORE Core and Strip)
--
-- One definition, two callers. The strip engine (Strip.lua) and the grid
-- engine (Core.lua) both build the SAME 100x34 paladin-template button here,
-- so the nine class modules can never drift into two visual families again.
--
--   b = RallyPowerCP.UI.CreateButton(parent, name)
--     -> a 100x34 Button on the Smooth skin with a 26px left icon, a gold
--        top label, a grey bottom sub-label and a right-aligned timer, plus
--        the helpers b:SetIcon / SetLabel / SetSub / SetTimer / SetState.
--     The caller anchors it and wires its own OnClick / OnMouseWheel / OnEnter.
--
--   RallyPowerCP.UI.HeaderText(title)  -> the gold title, "[TEST]"-tagged in
--        test mode (the shared strip/grid header text).
--
--   RallyPowerCP.UI.AddScaleGrip(frame, key)  -> the PallyPower drag-to-scale
--        grip (our own copy of PallyPowerResizeTemplate + the scaling maths;
--        we never call the legacy functions). Persists RallyPowerCP_Settings
--        ["scale_"..key] and is re-applied at frame creation via
--        RallyPowerCP.UI.EffectiveScale(key).
--=============================================================================

RallyPowerCP = RallyPowerCP or {}
RallyPowerCP.classes = RallyPowerCP.classes or {}   -- Core:NewClass fills this
RallyPowerCP.UI = RallyPowerCP.UI or {}
RallyPowerCP_Settings = RallyPowerCP_Settings or {}

-- Paladin-template geometry (locked): 100x34, 26px icon, 2px gap.
local BTN_W   = 100
local BTN_H   = 34
local BTN_GAP = 2
RallyPowerCP.UI.BTN_W   = BTN_W
RallyPowerCP.UI.BTN_H   = BTN_H
RallyPowerCP.UI.BTN_GAP = BTN_GAP

local SKIN = {
    bgFile   = "Interface\\AddOns\\RallyPowerCP\\Skins\\Smooth",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = false, tileSize = 8, edgeSize = 8,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
}
-- Official status presets (PallyPowerValues.lua), 0.5 alpha.
local COLORS = {
    good = { 0, 0.7, 0, 0.5 },
    need = { 1, 0,   0, 0.5 },
    off  = { 0.25, 0.25, 0.25, 0.5 },
}

--------------------------------------------------------------------------
-- the button helpers (shared by every strip and grid button)
--------------------------------------------------------------------------
local function Btn_SetIcon(self, tex)  self.icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark") end
local function Btn_SetLabel(self, txt) self.eln:SetText(txt or "") end
local function Btn_SetSub(self, txt)   self.tn:SetText(txt or "") end
local function Btn_SetTimer(self, txt) self.tm:SetText(txt or "") end
local function Btn_SetState(self, st)
    local c = COLORS[st] or COLORS.off
    self:SetBackdropColor(c[1], c[2], c[3], c[4])
    self.icon:SetAlpha(st == "good" and 1 or 0.55)
end

-- Build one paladin-template button. The caller anchors it and adds handlers.
function RallyPowerCP.UI.CreateButton(parent, name)
    local b = CreateFrame("Button", name, parent)
    b:SetWidth(BTN_W); b:SetHeight(BTN_H)
    b:SetBackdrop(SKIN)

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(26); icon:SetHeight(26)
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
    return b
end

-- Gold title, tagged "[TEST]" while test mode is on (strip + grid headers).
function RallyPowerCP.UI.HeaderText(title)
    if RallyPowerCP.IsTestMode and RallyPowerCP.IsTestMode() then
        return "|cffffd100" .. (title or "") .. "|r |cffff8800[TEST]|r"
    end
    return "|cffffd100" .. (title or "") .. "|r"
end

--------------------------------------------------------------------------
-- drag-to-scale grip (our own copy of the legacy PallyPowerResizeTemplate;
-- read PallyPower.xml / PallyPower_StartScaling for the reference).
--
-- The legacy grip re-pins the frame's top-left every tick to keep it fixed
-- while scaling; that is bound to PallyPower's own frames and PP_PerUser, so
-- we don't reuse it. Ours computes a stable scale from how far the cursor has
-- travelled from the grab point (never reading the frame's own moving
-- geometry, so it cannot run away on a centre-anchored frame), throttled at
-- 0.25s like the original, and clamped to a sane range.
--------------------------------------------------------------------------
local GRIP_TEX = "Interface\\AddOns\\RallyPowerCP\\PallyPower-ResizeGrip"
local SCALE_MIN, SCALE_MAX = 0.5, 2.0

local sTarget, sKey, sStartScale, sCX0, sCY0, sBase
local sAccum = 0

local function ClampScale(s)
    if s < SCALE_MIN then return SCALE_MIN end
    if s > SCALE_MAX then return SCALE_MAX end
    return s
end

-- Per-frame override wins over the global uiScale slider (a grip drag is an
-- explicit per-frame choice); Reset Frames clears the override.
function RallyPowerCP.UI.EffectiveScale(key)
    local s = key and RallyPowerCP_Settings["scale_" .. key]
    if s then return s end
    return RallyPowerCP_Settings.uiScale or 1
end

function RallyPowerCP.UI.ApplyScale(frame, key, s)
    s = ClampScale(s)
    frame:SetScale(s)
    if key then RallyPowerCP_Settings["scale_" .. key] = s end
    return s
end

local function ScaleTick()
    sAccum = sAccum + (arg1 or 0)
    if sAccum < 0.25 then return end
    sAccum = 0
    if not sTarget then return end
    local cx, cy = GetCursorPosition()
    -- down-right of the grab point grows the frame; up-left shrinks it
    local d = (cx - sCX0) + (sCY0 - cy)
    if d < 32 and d > -32 then return end          -- ignore jitter (legacy 32px)
    RallyPowerCP.UI.ApplyScale(sTarget, sKey, sStartScale + d / sBase)
end

local scaleTicker = CreateFrame("Frame", "RallyPowerCP_ScaleTicker", UIParent)
scaleTicker:Hide()
scaleTicker:SetScript("OnUpdate", ScaleTick)

local function Grip_OnMouseDown()
    if arg1 ~= "LeftButton" then return end
    this:LockHighlight()
    sTarget = this.scaleFrame
    sKey = this.scaleKey
    sStartScale = sTarget:GetScale() or 1
    sCX0, sCY0 = GetCursorPosition()
    sBase = sTarget:GetWidth() * (sTarget:GetEffectiveScale() or 1)
    if not sBase or sBase < 1 then sBase = 100 end
    sAccum = 0
    scaleTicker:Show()
end

local function Grip_OnMouseUp()
    if arg1 ~= "LeftButton" then return end
    scaleTicker:Hide()
    sTarget = nil
    this:UnlockHighlight()
end

function RallyPowerCP.UI.AddScaleGrip(frame, key)
    if frame.scaleGrip then return frame.scaleGrip end
    local grip = CreateFrame("Button", nil, frame)
    grip:SetWidth(16); grip:SetHeight(16)
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    grip:SetFrameLevel(frame:GetFrameLevel() + 5)
    grip:SetNormalTexture(GRIP_TEX)
    -- highlight as a HIGHLIGHT-layer texture with additive blend (the XML
    -- template's alphaMode="ADD"); LockHighlight() drives this layer too.
    local hl = grip:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture(GRIP_TEX)
    hl:SetBlendMode("ADD")
    hl:SetAllPoints(grip)
    grip.scaleFrame = frame
    grip.scaleKey = key
    grip:SetScript("OnMouseDown", Grip_OnMouseDown)
    grip:SetScript("OnMouseUp", Grip_OnMouseUp)
    frame.scaleGrip = grip
    return grip
end
