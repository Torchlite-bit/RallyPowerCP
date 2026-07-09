--=============================================================================
-- RallyPowerCP_AssignPanel.lua  -  the assignment panel (milestone step 3)
--
-- Five tabs over the two assignment stores:
--
--   Blessings  LIVE against the legacy PallyPower engine: rows are the
--              paladins known from PLPWR SELF broadcasts (AllPallys), cells
--              cycle through PallyPower_PerformCycle/Backwards - the SAME
--              functions the /pp grid uses - so every edit writes the legacy
--              tables and sends the byte-identical ASSIGN message. A paladin
--              can use this panel INSTEAD of the /pp grid, and raid paladins
--              running stock PallyPower/PallyPowerTW receive the assignments
--              exactly as if they came from it. (/pp remains available.)
--   Totems     shaman x element grid + covered party, over RallyPowerCP_Assign.
--   Buffs / Debuffs / Utility
--              duty lists from the module-declared catalog, over
--              RallyPowerCP_Assign: click cycles who's responsible.
--
-- The non-blessing tabs are LOCAL until the sync milestone: your own row is
-- authoritative (the strips already follow it); rows you set for others are a
-- leader's local plan that will start broadcasting when RPCX sync lands.
--
-- Entry points: right-click a strip's title area, or /rpc assign.
-- 1.12 rules: pooled rows (frames can't be deleted), implicit this/arg1,
-- Lua 5.0 (table.getn, no #/gmatch/select/%).
--=============================================================================

RallyPowerCP_Settings = RallyPowerCP_Settings or {}

local FRAME_W, FRAME_H = 470, 440
local NAME_W   = 92          -- row-label column width
local CELL     = 24          -- blessing cell pitch (22px button + 2 gap)
local ROW_H    = 24
local MAX_ROWS = 10          -- pooled rows per tab (plenty for one raid)

local frame                  -- the panel (created lazily)
local tabBtns  = {}
local panels   = {}
local currentTab

local TAB_INFO = {
    { label = "Blessings" },
    { label = "Totems"    },
    { label = "Buffs"     },
    { label = "Debuffs"   },
    { label = "Utility"   },
}
local DUTY_TAB = { [3] = "raidbuff", [4] = "debuff", [5] = "utility" }

-- Same skin family as the strips/options (Smooth + tooltip border).
local TAB_SKIN = {
    bgFile   = "Interface\\AddOns\\RallyPowerCP\\Skins\\Smooth",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = false, tileSize = 8, edgeSize = 8,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
}

local function Me() return UnitName("player") end

-- Leader-like: may edit OTHER people's rows (solo counts - there's only you).
local function LeaderLike()
    if GetNumRaidMembers() > 0 then
        return (IsRaidLeader() == 1) or (IsRaidOfficer() == 1)
    end
    if GetNumPartyMembers() > 0 then
        return IsPartyLeader() == 1
    end
    return true
end

-- Group members of one class token, self included. In test mode you are
-- always a candidate, so every tab is exercisable solo.
local function MembersOfClass(token)
    local out = {}
    local n = GetNumRaidMembers()
    if n > 0 then
        for i = 1, n do
            local u = "raid" .. i
            local _, cls = UnitClass(u)
            if cls == token and UnitName(u) then table.insert(out, UnitName(u)) end
        end
    else
        local _, mycls = UnitClass("player")
        if mycls == token then table.insert(out, Me()) end
        for i = 1, GetNumPartyMembers() do
            local u = "party" .. i
            local _, cls = UnitClass(u)
            if cls == token and UnitName(u) then table.insert(out, UnitName(u)) end
        end
    end
    if RallyPowerCP.IsTestMode and RallyPowerCP.IsTestMode() then
        local seen = false
        for i = 1, table.getn(out) do if out[i] == Me() then seen = true end end
        if not seen then table.insert(out, 1, Me()) end
    end
    return out
end

local function TitleCase(s)
    return string.upper(string.sub(s, 1, 1)) .. string.lower(string.sub(s, 2))
end

local function Msg(t)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffff00RallyPowerCP:|r " .. t)
end

--------------------------------------------------------------------------
-- shared widget helpers (cells are skinned Buttons; rows are pooled)
--------------------------------------------------------------------------

local function MakeCell(parent, w)
    local b = CreateFrame("Button", nil, parent)
    b:SetWidth(w); b:SetHeight(20)
    b:SetBackdrop(TAB_SKIN)
    b:SetBackdropColor(0.25, 0.25, 0.25, 0.5)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:EnableMouseWheel(true)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b); hl:SetTexture(1, 1, 1, 0.18)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.text = fs
    return b
end

local function MakeIconCell(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetWidth(22); b:SetHeight(22)
    b:SetBackdrop(TAB_SKIN)
    b:SetBackdropColor(0.25, 0.25, 0.25, 0.5)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:EnableMouseWheel(true)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b); hl:SetTexture(1, 1, 1, 0.18)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(18); icon:SetHeight(18)
    icon:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.icon = icon
    return b
end

local function RowLabel(parent)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetWidth(NAME_W - 4); fs:SetHeight(16)
    fs:SetJustifyH("LEFT")
    return fs
end

-- one wrapped grey note per panel (local-until-sync, empty states, hints)
local function MakeNote(parent)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetWidth(FRAME_W - 40); fs:SetHeight(30)
    fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP")
    return fs
end

local RefreshCurrent   -- forward declaration

--------------------------------------------------------------------------
-- BLESSINGS TAB (live: the legacy engine's own data and cycle functions)
--------------------------------------------------------------------------

local blessRows = {}       -- pooled: { label, cells = {1..10} }
local blessHeader = {}     -- 10 class-icon textures
local blessNote

local function PallyList()
    local out = {}
    if AllPallys then
        for name in pairs(AllPallys) do table.insert(out, name) end
    end
    table.sort(out)
    return out
end

local function BlessCellTip()
    if RallyPowerCP_Settings.tooltips == false then return end
    local pally, class = this.pally, this.classID
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    local clsName = (PallyPower_ClassID and PallyPower_ClassID[class]) or ("Class " .. class)
    GameTooltip:SetText(pally .. "  -  " .. clsName, 1, 1, 1)
    local bid = PallyPower_Assignments and PallyPower_Assignments[pally]
                and PallyPower_Assignments[pally][class] or -1
    if bid and bid ~= -1 and PallyPower_BlessingID and PallyPower_BlessingID[bid] then
        GameTooltip:AddLine(PallyPower_BlessingID[bid], 0.5, 1, 0.5)
    else
        GameTooltip:AddLine("No blessing assigned", 0.7, 0.7, 0.7)
    end
    GameTooltip:AddLine("Click: next - Right-click: previous - Wheel: cycle", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("Shift: set ALL classes at once", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function BlessCycle(pally, class, dir)
    if not (PallyPower_CanControl and PallyPower_CanControl(pally)) then
        Msg("You can't assign for " .. pally .. " (need lead/assist, or their Free Assign).")
        return
    end
    -- the legacy cycle assumes the row table exists (ParseMessage creates it)
    PallyPower_Assignments[pally] = PallyPower_Assignments[pally] or {}
    if dir < 0 then
        PallyPower_PerformCycleBackwards(pally, class, false)
    else
        PallyPower_PerformCycle(pally, class, false)
    end
    if RefreshCurrent then RefreshCurrent() end
end

local function BlessCellClick()
    BlessCycle(this.pally, this.classID, (arg1 == "RightButton") and -1 or 1)
end

local function BlessCellWheel()
    BlessCycle(this.pally, this.classID, (arg1 and arg1 > 0) and -1 or 1)
end

local function BuildBlessings(panel)
    -- header: one class icon per column (textures filled at refresh; the
    -- legacy tables are populated at runtime)
    for c = 0, 9 do
        local t = panel:CreateTexture(nil, "ARTWORK")
        t:SetWidth(20); t:SetHeight(20)
        t:SetPoint("TOPLEFT", panel, "TOPLEFT", NAME_W + c * CELL, -4)
        blessHeader[c] = t
    end
    for r = 1, MAX_ROWS do
        local row = { cells = {} }
        local y = -28 - (r - 1) * ROW_H
        row.label = RowLabel(panel)
        row.label:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, y - 3)
        for c = 0, 9 do
            local b = MakeIconCell(panel)
            b:SetPoint("TOPLEFT", panel, "TOPLEFT", NAME_W + c * CELL, y)
            b.classID = c
            b:SetScript("OnClick", BlessCellClick)
            b:SetScript("OnMouseWheel", BlessCellWheel)
            b:SetScript("OnEnter", BlessCellTip)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row.cells[c] = b
        end
        blessRows[r] = row
    end
    blessNote = MakeNote(panel)
    blessNote:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8, 6)
end

local function RefreshBlessings()
    for c = 0, 9 do
        if PallyPower_ClassTexture and PallyPower_ClassTexture[c] then
            blessHeader[c]:SetTexture(PallyPower_ClassTexture[c])
        end
    end
    local pallys = PallyList()
    local n = table.getn(pallys)
    for r = 1, MAX_ROWS do
        local row = blessRows[r]
        local pally = pallys[r]
        if pally then
            local control = PallyPower_CanControl and PallyPower_CanControl(pally)
            row.label:SetText("|cffffd100" .. pally .. "|r")
            for c = 0, 9 do
                local b = row.cells[c]
                b.pally = pally
                local bid = PallyPower_Assignments and PallyPower_Assignments[pally]
                            and PallyPower_Assignments[pally][c] or -1
                if bid and bid ~= -1 and BlessingIcon and BlessingIcon[bid] then
                    b.icon:SetTexture(BlessingIcon[bid])
                    b.icon:SetAlpha(1)
                    b:SetBackdropColor(0, 0.7, 0, 0.5)
                else
                    b.icon:SetTexture("Interface\\Buttons\\UI-EmptySlot")
                    b.icon:SetAlpha(0.25)
                    b:SetBackdropColor(0.25, 0.25, 0.25, 0.5)
                end
                if not control then b.icon:SetAlpha(0.4) end
                b:Show()
            end
        else
            row.label:SetText("")
            for c = 0, 9 do row.cells[c]:Hide() end
        end
    end
    if n == 0 then
        blessNote:SetText("No paladins known yet. Paladins appear here when they broadcast "
            .. "on PLPWR (join a group with one, or log in as one). Edits sync to stock "
            .. "PallyPower users unchanged.")
    else
        blessNote:SetText("Click a cell to cycle that paladin's blessing for the class. "
            .. "Byte-compatible with stock PallyPower - /pp still works too.")
    end
end

--------------------------------------------------------------------------
-- TOTEMS TAB (shaman x element + covered party, over the model)
--------------------------------------------------------------------------

local totemRows = {}
local totemNote
local A = nil            -- RallyPowerCP.Assign, bound at panel creation

local function ShortTotem(name)
    if not name then return "|cff888888-|r" end
    return string.gsub(name, " Totem$", "")
end

-- cycle nil -> option1 .. optionN -> nil for one shaman/element
local function CycleTotem(shaman, element, dir)
    local list = A.totems[element] or {}
    local n = table.getn(list)
    if n == 0 then return end
    local cur = A.GetTotem(shaman, element)
    local idx = 0
    for i = 1, n do if list[i].name == cur then idx = i end end
    idx = idx + dir
    if idx > n then idx = 0 elseif idx < 0 then idx = n end
    local ok = A.SetTotem(shaman, element, (idx > 0) and list[idx].name or nil)
    if not ok then Msg("You can't assign for " .. shaman .. " (need lead/assist).") end
    if RefreshCurrent then RefreshCurrent() end
end

local function CycleParty(shaman, dir)
    local cur = A.GetTotemParty(shaman) or 0        -- 0 = own subgroup
    local nxt = cur + dir
    if nxt > 8 then nxt = 0 elseif nxt < 0 then nxt = 8 end
    local ok = A.SetTotemParty(shaman, (nxt > 0) and nxt or nil)
    if not ok then Msg("You can't assign for " .. shaman .. " (need lead/assist).") end
    if RefreshCurrent then RefreshCurrent() end
end

local function TotemCellClick()
    if this.element then
        CycleTotem(this.shaman, this.element, (arg1 == "RightButton") and -1 or 1)
    else
        CycleParty(this.shaman, (arg1 == "RightButton") and -1 or 1)
    end
end

local function TotemCellWheel()
    local dir = (arg1 and arg1 > 0) and -1 or 1
    if this.element then CycleTotem(this.shaman, this.element, dir)
    else CycleParty(this.shaman, dir) end
end

local TOTEM_CELL_W = 66
local PARTY_CELL_W = 42

local function BuildTotems(panel)
    -- column headers
    local heads = { "Earth", "Fire", "Water", "Air", "Party" }
    for i = 1, 5 do
        local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        local w = (i == 5) and PARTY_CELL_W or TOTEM_CELL_W
        local x = NAME_W + (i - 1) * (TOTEM_CELL_W + 2)
        fs:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -6)
        fs:SetText(heads[i])
    end
    for r = 1, MAX_ROWS do
        local row = { cells = {} }
        local y = -24 - (r - 1) * ROW_H
        row.label = RowLabel(panel)
        row.label:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, y - 3)
        for i = 1, 5 do
            local w = (i == 5) and PARTY_CELL_W or TOTEM_CELL_W
            local b = MakeCell(panel, w)
            b:SetPoint("TOPLEFT", panel, "TOPLEFT", NAME_W + (i - 1) * (TOTEM_CELL_W + 2), y)
            b:SetScript("OnClick", TotemCellClick)
            b:SetScript("OnMouseWheel", TotemCellWheel)
            row.cells[i] = b
        end
        totemRows[r] = row
    end
    totemNote = MakeNote(panel)
    totemNote:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8, 6)
end

local ELEMENT_ORDER = { "Earth", "Fire", "Water", "Air" }

local function RefreshTotems()
    local shamans = MembersOfClass("SHAMAN")
    local n = table.getn(shamans)
    for r = 1, MAX_ROWS do
        local row = totemRows[r]
        local shaman = shamans[r]
        if shaman then
            row.label:SetText("|cffffd100" .. shaman .. "|r")
            for i = 1, 4 do
                local b = row.cells[i]
                b.shaman = shaman; b.element = ELEMENT_ORDER[i]
                local cur = A.GetTotem(shaman, ELEMENT_ORDER[i])
                b.text:SetText(ShortTotem(cur))
                b:SetBackdropColor(cur and 0 or 0.25, cur and 0.7 or 0.25, cur and 0 or 0.25, 0.5)
                b:Show()
            end
            local pb = row.cells[5]
            pb.shaman = shaman; pb.element = nil
            local party = A.GetTotemParty(shaman)
            pb.text:SetText(party and ("Grp " .. party) or "own")
            pb:SetBackdropColor(0.25, 0.25, 0.25, 0.5)
            pb:Show()
        else
            row.label:SetText("")
            for i = 1, 5 do row.cells[i]:Hide() end
        end
    end
    if n == 0 then
        totemNote:SetText("No shamans in your group. (Test mode adds yourself for previewing.)")
    else
        totemNote:SetText("Click an element to cycle that shaman's totem; Party = which group "
            .. "they cover. Local until the sync milestone: only your own row drives your strip.")
    end
end

--------------------------------------------------------------------------
-- DUTY TABS (Buffs / Debuffs / Utility over the catalog + model)
--------------------------------------------------------------------------

local dutyRows = { [3] = {}, [4] = {}, [5] = {} }
local dutyNote = {}

local function DutyList(tabkey)
    local out = {}
    for i = 1, table.getn(A.dutyOrder) do
        local def = A.duties[A.dutyOrder[i]]
        if def and def.tab == tabkey then table.insert(out, def) end
    end
    return out
end

-- Holders text: "-", "Name", "Name +2" (tooltip lists everyone)
local function HolderText(key)
    local holders = A.GetDutyCasters(key)
    local n = table.getn(holders)
    if n == 0 then return "|cff888888-|r", holders end
    local t = holders[1].caster
    if n > 1 then t = t .. " |cffaaaaaa+" .. (n - 1) .. "|r" end
    return t, holders
end

-- Leaders cycle none -> each candidate -> none (clearing other holders they
-- may edit); everyone else toggles their own claim.
local function CycleDutyHolder(key, dir)
    local def = A.duties[key]
    if not def then return end
    local cands = MembersOfClass(def.class)
    local holders = A.GetDutyCasters(key)

    if not LeaderLike() then
        local mine = false
        for i = 1, table.getn(holders) do
            if holders[i].caster == Me() then mine = true end
        end
        if mine then
            A.ClearDuty(Me(), key)
        else
            if not A.SetDuty(Me(), key, true) then
                Msg("Only lead/assist can assign " .. (def.spell or key) .. " to others.")
            end
        end
        if RefreshCurrent then RefreshCurrent() end
        return
    end

    local cur = holders[1] and holders[1].caster or nil
    local idx = 0
    local n = table.getn(cands)
    for i = 1, n do if cands[i] == cur then idx = i end end
    idx = idx + dir
    if idx > n then idx = 0 elseif idx < 0 then idx = n end
    for i = 1, table.getn(holders) do
        A.ClearDuty(holders[i].caster, key)
    end
    if idx > 0 then A.SetDuty(cands[idx], key, true) end
    if RefreshCurrent then RefreshCurrent() end
end

local function DutyCellClick()
    CycleDutyHolder(this.dutyKey, (arg1 == "RightButton") and -1 or 1)
end

local function DutyCellWheel()
    CycleDutyHolder(this.dutyKey, (arg1 and arg1 > 0) and -1 or 1)
end

local function DutyCellTip()
    if RallyPowerCP_Settings.tooltips == false then return end
    local def = A.duties[this.dutyKey]
    if not def then return end
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:SetText(def.spell or this.dutyKey, 1, 1, 1)
    local _, holders = HolderText(this.dutyKey)
    for i = 1, table.getn(holders) do
        local h = holders[i]
        local t = h.caster
        if type(h.target) == "string" then t = t .. "  ->  " .. h.target end
        GameTooltip:AddLine(t, 0.5, 1, 0.5)
    end
    if table.getn(holders) == 0 then GameTooltip:AddLine("Unassigned", 0.7, 0.7, 0.7) end
    GameTooltip:AddLine("Click: cycle who's responsible", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function BuildDutyTab(panel, tabIndex)
    for r = 1, MAX_ROWS + 2 do
        local row = {}
        local y = -6 - (r - 1) * ROW_H
        row.label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.label:SetWidth(210); row.label:SetHeight(16)
        row.label:SetJustifyH("LEFT")
        row.label:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, y - 3)
        row.cell = MakeCell(panel, 150)
        row.cell:SetPoint("TOPLEFT", panel, "TOPLEFT", 250, y)
        row.cell:SetScript("OnClick", DutyCellClick)
        row.cell:SetScript("OnMouseWheel", DutyCellWheel)
        row.cell:SetScript("OnEnter", DutyCellTip)
        row.cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
        dutyRows[tabIndex][r] = row
    end
    dutyNote[tabIndex] = MakeNote(panel)
    dutyNote[tabIndex]:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8, 6)
end

local function RefreshDutyTab(tabIndex)
    local defs = DutyList(DUTY_TAB[tabIndex])
    local rows = dutyRows[tabIndex]
    for r = 1, table.getn(rows) do
        local row = rows[r]
        local def = defs[r]
        if def then
            row.label:SetText("|cffffd100" .. (def.spell or def.key) .. "|r  |cff999999("
                .. TitleCase(def.class or "?") .. ")|r")
            row.cell.dutyKey = def.key
            local txt = HolderText(def.key)
            row.cell.text:SetText(txt)
            local holders = A.GetDutyCasters(def.key)
            if table.getn(holders) > 0 then
                row.cell:SetBackdropColor(0, 0.7, 0, 0.5)
            else
                row.cell:SetBackdropColor(0.25, 0.25, 0.25, 0.5)
            end
            row.cell:Show()
        else
            row.label:SetText("")
            row.cell:Hide()
        end
    end
    dutyNote[tabIndex]:SetText("Click an assignment to cycle who's responsible (lead/assist "
        .. "cycles anyone; others claim/unclaim themselves). Local until the sync milestone.")
end

--------------------------------------------------------------------------
-- frame + tabs
--------------------------------------------------------------------------

local function StyleTabs()
    for i = 1, table.getn(tabBtns) do
        local b = tabBtns[i]
        if i == currentTab then
            b:SetBackdropColor(0, 0.7, 0, 0.5)
            b.label:SetTextColor(1, 0.82, 0)
        else
            b:SetBackdropColor(0.25, 0.25, 0.25, 0.5)
            b.label:SetTextColor(0.7, 0.7, 0.7)
        end
    end
end

RefreshCurrent = function()
    if not frame or not frame:IsShown() then return end
    if currentTab == 1 then RefreshBlessings()
    elseif currentTab == 2 then RefreshTotems()
    elseif DUTY_TAB[currentTab] then RefreshDutyTab(currentTab) end
end

local function ShowTab(i)
    if not panels[i] then i = 1 end
    currentTab = i
    RallyPowerCP_Settings.assignLastTab = i
    for n = 1, table.getn(panels) do
        if n == i then panels[n]:Show() else panels[n]:Hide() end
    end
    StyleTabs()
    RefreshCurrent()
end

local function CreatePanel()
    A = RallyPowerCP.Assign

    local f = CreateFrame("Frame", "RallyPowerCP_AssignFrame", UIParent)
    frame = f
    f:SetWidth(FRAME_W); f:SetHeight(FRAME_H)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    f:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 5, right = 5, top = 5, bottom = 5 },
    })
    f:SetBackdropColor(0, 0, 0, 0.85)
    f:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() f:StartMoving() end)
    f:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    f:Hide()
    tinsert(UISpecialFrames, "RallyPowerCP_AssignFrame")   -- ESC closes

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", f, "TOP", 0, -10)
    title:SetText("|cffffd100RallyPowerCP|r Assignments")

    CreateFrame("Button", nil, f, "UIPanelCloseButton"):SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)

    -- tab row
    local tx = 10
    for i = 1, table.getn(TAB_INFO) do
        local idx = i
        local b = CreateFrame("Button", nil, f)
        b:SetWidth(86); b:SetHeight(22)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", tx, -30)
        b:SetBackdrop(TAB_SKIN)
        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("CENTER", b, "CENTER", 0, 0)
        fs:SetText(TAB_INFO[i].label)
        b.label = fs
        b:SetScript("OnClick", function() ShowTab(idx) end)
        tabBtns[i] = b
        tx = tx + 90
    end

    -- content panels
    for i = 1, table.getn(TAB_INFO) do
        local p = CreateFrame("Frame", nil, f)
        p:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -56)
        p:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)
        p:Hide()
        panels[i] = p
    end
    BuildBlessings(panels[1])
    BuildTotems(panels[2])
    BuildDutyTab(panels[3], 3)
    BuildDutyTab(panels[4], 4)
    BuildDutyTab(panels[5], 5)

    f:SetScript("OnShow", function()
        ShowTab(RallyPowerCP_Settings.assignLastTab or 1)
    end)

    -- slow repaint while open: rosters, legacy PLPWR traffic and remote
    -- assignment edits all land without any event of ours
    local accum = 0
    f:SetScript("OnUpdate", function()
        accum = accum + (arg1 or 0)
        if accum < 1 then return end
        accum = 0
        RefreshCurrent()
    end)

    -- repaint immediately when the model changes under us
    A.Subscribe(function() RefreshCurrent() end)
end

-- Entry point: right-click a strip's title, or /rpc assign.
function RallyPowerCP_AssignPanelToggle()
    if not frame then CreatePanel() end
    if frame:IsShown() then frame:Hide() else frame:Show() end
end
