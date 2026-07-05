--=============================================================================
-- RallyPowerCP_Popout.lua
--
-- The hover player pop-out for the PallyPower buff bar, rebuilt as an exact
-- replica of **PallyPower 3.3.5's `PallyPowerPopupTemplate`** (from the official
-- PallyPower Classic source, PallyPower_Wrath.xml) — the modern per-player
-- flyout the project is standardising on:
--
--   * 100x34 buttons, stacked flush, floating bare (no container panel)
--   * Skinned backdrop: the "Smooth" statusbar texture + Blizzard Tooltip
--     border (edge 8), coloured by buff state with the official defaults:
--       cBuffGood        0, 0.7, 0, 0.5   (green  - has the buff)
--       cBuffNeedAll     1, 0,   0, 0.5   (red    - missing it)
--       cBuffNeedSpecial 0, 0,   1, 0.5   (blue   - special / unknown state)
--   * Buff icon 16x16 top-left: alpha 1.0 when buffed, 0.4 when not
--   * White timer right of the icon (your personal cast countdown)
--   * Player name bottom-right
--   * "R" range letter top-right: green = in range, red = not visible
--     (official also uses yellow = visible-but-far; needs range data we
--     don't track yet)
--   * "D" dead marker left of the R, red when dead
--   * Main-tank icon left of the D for PallyPower-marked tanks
--   * Each row shows that player's INDIVIDUAL timer (your cast countdown), and
--     is CLICKABLE for a refresh, official-style:
--       Left-click  = Greater blessing on that player's class (out of combat)
--       Right-click = Normal single-target blessing — honours their individual
--                     assignment, and works in combat (the one action the spec
--                     permits while fighting)
--
-- Data mapping from the 1.12 engine's per-button lists (have/need/range/dead):
-- have -> green, need -> red, dead -> red + D, "not here" -> blue + red R
-- (the engine can't read a hidden player's buffs, so blue doubles as the
-- official "special" colour for unknown state).
--
-- Reads PallyPower's own per-button data and casts through its own spellbook
-- tables (AllPallys / GetNormalBlessings / duration constants); does not modify
-- the engine — it replaces only the buff-button hover handler (which showed a
-- text tooltip of the same data).
--=============================================================================

local ROW_W = 100            -- official popup button size
local ROW_H = 34

-- ApplySkin() equivalent: default skin "Smooth" + "Blizzard Tooltip" border.
local SKIN_BACKDROP = {
    bgFile   = "Interface\\AddOns\\RallyPowerCP\\Skins\\Smooth",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = false, tileSize = 8, edgeSize = 8,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
}

-- Official default colour presets (PallyPowerValues.lua).
local C_GOOD    = { r = 0, g = 0.7, b = 0, t = 0.5 }
local C_NEEDALL = { r = 1, g = 0,   b = 0, t = 0.5 }
local C_SPECIAL = { r = 0, g = 0,   b = 1, t = 0.5 }

local popout                 -- invisible container (created lazily)
local rows = {}              -- pooled player buttons
local curBtn                 -- the buff-bar button the pop-out is anchored to
local notOver = 0
local accum   = 0
local RefreshPopout          -- forward declaration (defined below)

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

-- Combat tracking (PLAYER_REGEN events; UnitAffectingCombat is unreliable here).
local inCombat = false
local combatWatch = CreateFrame("Frame", "RallyPowerCP_PopCombatWatch")
combatWatch:RegisterEvent("PLAYER_REGEN_DISABLED")
combatWatch:RegisterEvent("PLAYER_REGEN_ENABLED")
combatWatch:SetScript("OnEvent", function()
    inCombat = (event == "PLAYER_REGEN_DISABLED")
end)

local lastClick = 0          -- double-click reagent guard

-- SuperWoW: cast straight at a unit with no target juggling.
local HAS_SUPERWOW = (SUPERWOW_VERSION ~= nil)

-- Resolve a player (or pet) name to a castable unit id.
local function FindUnitByName(name)
    if not name then return nil end
    if UnitName("player") == name then return "player" end
    if UnitExists("pet") and UnitName("pet") == name then return "pet" end
    for i = 1, 4 do
        if UnitExists("party" .. i) and UnitName("party" .. i) == name then return "party" .. i end
        if UnitExists("partypet" .. i) and UnitName("partypet" .. i) == name then return "partypet" .. i end
    end
    for i = 1, 40 do
        if UnitExists("raid" .. i) and UnitName("raid" .. i) == name then return "raid" .. i end
        if UnitExists("raidpet" .. i) and UnitName("raidpet" .. i) == name then return "raidpet" .. i end
    end
    return nil
end

-- Cast a blessing on a specific unit, safely. Under SuperWoW we cast by name
-- directly at the unit (no target juggling); the spell name is resolved from the
-- spellbook index. Fallback (bare 1.12): the engine's proven pattern - disable
-- auto-self-cast, clear the target, enter targeting, target the unit, restore.
local function CastBlessingOn(unit, spellIdx)
    if HAS_SUPERWOW then
        local nm = GetSpellName(spellIdx, BOOKTYPE_SPELL)
        if nm then
            local rank = GetSpellRank and GetSpellRank(spellIdx, BOOKTYPE_SPELL)
            if rank and rank ~= "" then nm = nm .. "(" .. rank .. ")" end
            CastSpellByName(nm, unit)
            return true
        end
        -- if the name lookup somehow fails, fall through to the classic path
    end

    local restoreCVar = (GetCVar("autoSelfCast") == "1")
    if restoreCVar then SetCVar("autoSelfCast", "0") end
    local hadTarget = UnitExists("target")
    if hadTarget then ClearTarget() end

    CastSpell(spellIdx, BOOKTYPE_SPELL)
    local ok = false
    if SpellIsTargeting() then
        if SpellCanTargetUnit(unit) then
            SpellTargetUnit(unit)
            ok = true
        else
            SpellStopTargeting()
        end
    end

    if hadTarget then TargetLastTarget() end
    if restoreCVar then SetCVar("autoSelfCast", "1") end
    return ok
end

-- Click a popup row: left = Greater on that player (out of combat only),
-- right = Normal single-target (honours individual assignments; combat-legal).
local function PopRowOnClick()
    local pname = this.pname
    if not pname or not curBtn or not curBtn.buffID or not curBtn.classID then return end
    if GetTime() - lastClick < 0.7 then return end

    local me = UnitName("player")
    if not (AllPallys and AllPallys[me] and AllPallys[me][curBtn.buffID]) then return end

    local unit = FindUnitByName(pname)
    if not unit or not UnitIsVisible(unit) then
        PallyPower_ShowFeedback(pname .. " is not in range.", 0.5, 0.5, 1)
        return
    end
    if UnitIsDeadOrGhost(unit) then
        PallyPower_ShowFeedback(pname .. " is dead.", 1, 0, 0)
        return
    end

    local spellIdx, timerKind
    if arg1 == "RightButton" then
        -- Normal blessing; individual assignment overrides the class one.
        local useID = curBtn.buffID
        local ind = GetNormalBlessings(me, curBtn.classID, pname)
        if ind and ind ~= -1 and AllPallys[me][ind] then useID = ind end
        spellIdx = AllPallys[me][useID] and AllPallys[me][useID]["idsmall"]
        timerKind = "normal"
    else
        if inCombat then
            PallyPower_ShowFeedback("Greater blessings are disabled in combat - right-click for a single blessing.", 1, 1, 0)
            return
        end
        local entry = AllPallys[me][curBtn.buffID]
        spellIdx = entry and entry["id"]
        -- If no distinct Greater rank is known, this is really a normal cast.
        if entry and entry["id"] == entry["idsmall"] then timerKind = "normal" else timerKind = "greater" end
    end
    if not spellIdx then return end

    local cdStart = GetSpellCooldown(spellIdx, BOOKTYPE_SPELL)
    if cdStart and cdStart >= 1 then return end

    if CastBlessingOn(unit, spellIdx) then
        lastClick = GetTime()
        if timerKind == "greater" then
            LastCast[curBtn.buffID .. curBtn.classID] = PALLYPOWER_GREATERBLESSINGDURATION
        else
            LastCastPlayer[pname] = PALLYPOWER_NORMALBLESSINGDURATION
        end
        RefreshPopout()
    end
end

-- Ordered display list from PallyPower's own per-button name lists.
-- state: "have" | "need" | "dead" | "nothere"
local function Collect(btn)
    local list = {}
    local function add(names, state)
        if not names then return end
        for i = 1, table.getn(names) do
            local nm = names[i]
            local t = ""
            if state == "have" and LastCastPlayer and LastCastPlayer[nm] then
                t = PallyPower_FormatTime(LastCastPlayer[nm])
            end
            table.insert(list, { name = nm, state = state, timer = t })
        end
    end
    add(btn.need,  "need")
    add(btn.dead,  "dead")
    add(btn.range, "nothere")
    add(btn.have,  "have")
    return list
end

-- Build one popup button, laid out exactly like PallyPowerPopupTemplate.
local function GetRow(i)
    if rows[i] then return rows[i] end
    local r = CreateFrame("Button", "RallyPowerCP_Pop" .. i, popout)
    r:SetWidth(ROW_W); r:SetHeight(ROW_H)
    r:SetFrameStrata("DIALOG")
    r:SetBackdrop(SKIN_BACKDROP)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetScript("OnClick", PopRowOnClick)

    local icon = r:CreateTexture(nil, "OVERLAY")           -- $parentBuffIcon
    icon:SetWidth(16); icon:SetHeight(16)
    icon:SetPoint("TOPLEFT", r, "TOPLEFT", 4, -4)
    r.buffIcon = icon

    local time = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    time:SetWidth(40); time:SetHeight(16)                   -- $parentTime
    time:SetPoint("TOPLEFT", icon, "TOPRIGHT", 1, 0)
    time:SetJustifyH("LEFT")
    r.time = time

    local name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    name:SetWidth(92); name:SetHeight(16)                   -- $parentName
    name:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", -5, 3)
    name:SetJustifyH("RIGHT")
    r.name = name

    local rng = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rng:SetWidth(10); rng:SetHeight(10)                     -- $parentRng
    rng:SetPoint("TOPRIGHT", r, "TOPRIGHT", -6, -6)
    rng:SetJustifyH("RIGHT")
    rng:SetText("R")
    r.rng = rng

    local dead = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dead:SetWidth(10); dead:SetHeight(10)                   -- $parentDead
    dead:SetPoint("RIGHT", rng, "LEFT", -3, 0)
    dead:SetJustifyH("RIGHT")
    dead:SetText("D")
    r.dead = dead

    local tank = r:CreateTexture(nil, "OVERLAY")            -- $parentTankIcon
    tank:SetWidth(11); tank:SetHeight(11)
    tank:SetTexture("Interface\\GroupFrame\\UI-Group-MainTankIcon")
    tank:SetPoint("RIGHT", dead, "LEFT", -3, 0)
    r.tank = tank

    rows[i] = r
    return r
end

local function ApplyBackdropColor(r, preset)
    r:SetBackdropColor(preset.r, preset.g, preset.b, preset.t)
end

RefreshPopout = function()
    if not popout or not curBtn then return end
    local icon = curBtn.buffID and BlessingIcon and BlessingIcon[curBtn.buffID]
    local list = Collect(curBtn)
    local n = table.getn(list)
    local y = 0
    for i = 1, n do
        local d = list[i]
        local r = GetRow(i)
        r.pname = d.name
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", popout, "TOPLEFT", 0, y)

        if icon then r.buffIcon:SetTexture(icon) end
        r.name:SetText(d.name)
        r.time:SetText(d.timer)

        if d.state == "have" then
            ApplyBackdropColor(r, C_GOOD)
            r.buffIcon:SetAlpha(1)
            r.rng:SetTextColor(0, 1, 0); r.rng:SetAlpha(1)
            r.dead:SetAlpha(0)
        elseif d.state == "need" then
            ApplyBackdropColor(r, C_NEEDALL)
            r.buffIcon:SetAlpha(0.4)
            r.rng:SetTextColor(0, 1, 0); r.rng:SetAlpha(1)
            r.dead:SetAlpha(0)
        elseif d.state == "dead" then
            ApplyBackdropColor(r, C_NEEDALL)
            r.buffIcon:SetAlpha(0.4)
            r.rng:SetTextColor(0, 1, 0); r.rng:SetAlpha(1)
            r.dead:SetTextColor(1, 0, 0); r.dead:SetAlpha(1)
        else -- "nothere": buff state unknowable on 1.12
            ApplyBackdropColor(r, C_SPECIAL)
            r.buffIcon:SetAlpha(0.4)
            r.rng:SetTextColor(1, 0, 0); r.rng:SetAlpha(1)
            r.dead:SetAlpha(0)
        end

        if PallyPower_Tanks and PallyPower_Tanks[d.name] == true then
            r.tank:SetAlpha(1)
        else
            r.tank:SetAlpha(0)
        end

        r:Show()
        y = y - ROW_H
    end
    for i = n + 1, table.getn(rows) do rows[i]:Hide() end
    popout:SetHeight(n * ROW_H)
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
    -- Invisible container: the official popup buttons float bare, so the
    -- container exists only for layout and the keep-open hit-test.
    local p = CreateFrame("Frame", "RallyPowerCP_BlessingPopout", UIParent)
    p:SetWidth(ROW_W); p:SetHeight(ROW_H)
    p:SetFrameStrata("DIALOG")
    p:EnableMouse(false)
    p:Hide()
    p:SetScript("OnUpdate", PopoutOnUpdate)
    popout = p
end

function RallyPowerCP_BlessingPopout_Show(btn)
    if not btn or not btn.classID then return end
    if table.getn(Collect(btn)) == 0 then HidePopout(); return end
    if not popout then CreatePopout() end
    curBtn = btn
    notOver = 0
    popout:ClearAllPoints()
    popout:SetPoint("TOPRIGHT", btn, "TOPLEFT", -4, 0)   -- expand to the LEFT
    RefreshPopout()
    popout:Show()
end

-- Replace PallyPower's buff-button hover handler: the pop-out is the visual
-- version of the text tooltip it used to show. (Only the buff-bar XML calls
-- this handler, so nothing else is affected.)
function PallyPowerBuffButton_OnEnter(btn)
    RallyPowerCP_BlessingPopout_Show(btn)
end
