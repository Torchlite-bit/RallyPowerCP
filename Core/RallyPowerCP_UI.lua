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

