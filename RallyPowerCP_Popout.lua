--=============================================================================
-- RallyPowerCP_Popout.lua
--
-- Adds the colour-coded player-list pop-out to the ORIGINAL PallyPower buff-bar
-- blessing buttons. Hover a class button on the buff bar and a panel expands to
-- its left listing every player in that class — green Have / red Need / blue Not
-- Here / dark-red Dead — each with the blessing icon, the player's name, a tank
-- marker, and their personal timer.
--
-- It is SELF-CONTAINED: it reads PallyPower's own per-button data
-- (btn.classID / btn.buffID / btn.need / btn.have / btn.range / btn.dead) and
-- the LastCastPlayer[name] timers. It does NOT modify the PallyPower engine; it
-- simply wraps the existing PallyPowerBuffButton_OnEnter handler, so the classic
-- bar keeps working exactly as before.
--=============================================================================

local POP_W   = 164          -- panel width
local BAR_H   = 24           -- per-player bar height
local BAR_GAP = 2            -- gap between bars
local PAD     = 5            -- inner padding

local BACKDROP = {
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 8, edgeSize = 8,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

local popout                 -- the panel frame (created lazily)
local rows = {}              -- pooled player-bar frames
local curBtn                 -- the buff-bar button the pop-out is anchored to
local notOver = 0
local accum   = 0

-- Scale-aware cursor hit-test (works on the 1.12 client).
local function IsMouseOver(frame)
    if not frame or not frame:IsVisible() then return false end
    local l = frame:GetLeft()
    if not l then return false end
    local b, w, h = frame:GetBottom(), frame:GetWidth(), frame:GetHeight()
    local s = frame:GetEffectiveScale()
    local x, y = GetCursorPosition()
    x = x / s; y = y / s
    return x >= l and x <= l + w and y >= b and y <= b + h
end

local function HidePopout()
    if popout then popout:Hide() end
    curBtn = nil
end

-- Build the ordered display list for a button from PallyPower's own name lists.
-- Returns an array of { name, r, g, b, timer }.
local function Collect(btn)
    local list = {}
    local function add(names, rr, gg, bb, withTimer)
        if not names then return end
        for i = 1, table.getn(names) do
            local nm = names[i]
            local t = ""
            if withTimer and LastCastPlayer and LastCastPlayer[nm] then
                t = PallyPower_FormatTime(LastCastPlayer[nm])
            end
            table.insert(list, { name = nm, r = rr, g = gg, b = bb, timer = t })
        end
    end
    add(btn.need,  0.80, 0.12, 0.12, false)   -- Need      (red)
    add(btn.dead,  0.45, 0.10, 0.10, false)   -- Dead      (dark red)
    add(btn.range, 0.30, 0.30, 0.85, false)   -- Not Here  (blue)
    add(btn.have,  0.12, 0.65, 0.12, true)    -- Have       (green, with timer)
    return list
end

local function GetRow(i)
    if rows[i] then return rows[i] end
    local r = CreateFrame("Frame", "RallyPowerCP_BPopRow" .. i, popout)
    r:SetWidth(POP_W - 2 * PAD); r:SetHeight(BAR_H)
    r:SetBackdrop(BACKDROP)
    local ic = r:CreateTexture(nil, "ARTWORK")
    ic:SetWidth(BAR_H - 6); ic:SetHeight(BAR_H - 6)
    ic:SetPoint("LEFT", r, "LEFT", 3, 0)
    r.icon = ic
    local nm = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nm:SetPoint("LEFT", ic, "RIGHT", 4, 0)
    nm:SetPoint("RIGHT", r, "RIGHT", -30, 0)
    nm:SetJustifyH("LEFT")
    r.name = nm
    local role = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    role:SetPoint("TOPRIGHT", r, "TOPRIGHT", -3, -2)
    role:SetJustifyH("RIGHT")
    r.role = role
    local tm = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tm:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", -3, 2)
    tm:SetJustifyH("RIGHT")
    r.timer = tm
    rows[i] = r
    return r
end

local function RefreshPopout()
    if not popout or not curBtn then return end
    local icon = curBtn.buffID and BlessingIcon and BlessingIcon[curBtn.buffID]
    local list = Collect(curBtn)
    local n = table.getn(list)
    local y = -PAD
    for i = 1, n do
        local r = GetRow(i)
        local d = list[i]
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", popout, "TOPLEFT", PAD, y)
        r:SetBackdropColor(d.r, d.g, d.b, 0.85)
        if icon then r.icon:SetTexture(icon) end
        r.name:SetText(d.name)
        r.timer:SetText(d.timer)
        if PallyPower_Tanks and PallyPower_Tanks[d.name] == true then
            r.role:SetText("MT"); r.role:SetTextColor(1, 0.82, 0)
        else
            r.role:SetText("")
        end
        r:Show()
        y = y - (BAR_H + BAR_GAP)
    end
    for i = n + 1, table.getn(rows) do rows[i]:Hide() end
    local h = PAD * 2 + n * BAR_H
    if n > 1 then h = h + (n - 1) * BAR_GAP end
    popout:SetHeight(h)
end

local function PopoutOnUpdate()
    if not popout:IsShown() then return end
    if IsMouseOver(curBtn) or IsMouseOver(popout) then
        notOver = 0
    else
        notOver = notOver + (arg1 or 0)
        if notOver > 0.2 then HidePopout(); return end
    end
    accum = accum + (arg1 or 0)
    if accum >= 0.25 then accum = 0; RefreshPopout() end
end

local function CreatePopout()
    local p = CreateFrame("Frame", "RallyPowerCP_BlessingPopout", UIParent)
    p:SetWidth(POP_W); p:SetHeight(40)
    p:SetBackdrop(BACKDROP)
    p:SetBackdropColor(0, 0, 0, 0.9)
    p:SetFrameStrata("DIALOG")
    p:EnableMouse(true)
    p:Hide()
    p:SetScript("OnUpdate", PopoutOnUpdate)
    popout = p
end

function RallyPowerCP_BlessingPopout_Show(btn)
    if not btn or not btn.classID then return end
    -- Nothing to list (no group / no assignment) -> don't show an empty panel.
    if table.getn(Collect(btn)) == 0 then HidePopout(); return end
    if not popout then CreatePopout() end
    curBtn = btn
    notOver = 0
    popout:ClearAllPoints()
    popout:SetPoint("TOPRIGHT", btn, "TOPLEFT", -4, 0)   -- expand to the LEFT
    RefreshPopout()
    popout:Show()
end

-- Replace PallyPower's buff-button hover handler. The original only showed a
-- text tooltip of the same Have/Need/Not-Here/Dead data; our pop-out is the
-- visual version of it, so we show the pop-out instead. (Only the buff-bar XML
-- calls this handler, so nothing else is affected.)
function PallyPowerBuffButton_OnEnter(btn)
    RallyPowerCP_BlessingPopout_Show(btn)
end
