--=============================================================================
-- RallyPowerCP_Options.lua  -  tabbed options frame (Settings / Buttons / Raid)
--
-- Milestone A of docs\OPTIONS_UI_SPEC.md. Hand-built from 1.12 building
-- blocks (no Ace3): OptionsCheckButtonTemplate / OptionsSliderTemplate /
-- UIDropDownMenuTemplate / GameMenuButtonTemplate, ESC-close via
-- UISpecialFrames, handlers on the implicit `this`/`arg1`.
--
-- One generic renderer serves every tab. It renders "descriptor" lists whose
-- entries follow the M.optionsInfo module contract:
--
--   { type = "header", label = "Section" }
--   { type = "check",  key = "btn_earth", label = "...", default = true,
--     tip = "...", onChange = fn(value) }
--   { type = "select", key = "shamanSel.Earth", label = "...",
--     values = fn() -> { "name" | { value = v, text = label }, ... },
--     get = fn() -> effective value  (optional; defaults to the saved key) }
--   { type = "slider", key = "uiScale", label = "...", min=, max=, step=,
--     default = 1 }
--   { type = "button", label = "...", func = fn, tip = "..." }
--   { type = "note",   label = "wrapped text", height = 28 }
--
-- Binding: `key` is a path into RallyPowerCP_Settings with one optional dotted
-- level ("roguePoison.mh"). Reads fall back to `default` when the key is
-- absent (nothing is written until the user touches a control); checks write
-- an explicit false so default-on settings can be turned off. Optional
-- `get`/`set` override the read/write entirely (test mode, effective values).
--
-- The Settings tab is this file's own descriptor; the Buttons tab is
-- generated from the active class module (M.buffs / M.utility auto-checks +
-- M.optionsInfo); the Raid tab is the Milestone-B stub.
--=============================================================================

RallyPowerCP_Settings = RallyPowerCP_Settings or {}

local FRAME_W, FRAME_H = 360, 430
local PAD_X = 16                       -- left inset for controls
local NOTE_W = FRAME_W - 44            -- wrap width for note text

local optFrame                         -- the frame (created lazily)
local panels = {}                      -- [tabIndex] = content Frame
local tabBtns = {}                     -- [tabIndex] = tab Button
local controls = {}                    -- every bound control, for Refresh
local ctlCounter = 0                   -- unique global names for templates
local currentTab = nil

local TAB_INFO = {
    { label = "Settings" },
    { label = "Buttons"  },
    { label = "Raid"     },
}

-- Same skin family as the strips (Smooth + tooltip border, official look).
local TAB_SKIN = {
    bgFile   = "Interface\\AddOns\\RallyPowerCP\\Skins\\Smooth",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = false, tileSize = 8, edgeSize = 8,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
}

--------------------------------------------------------------------------
-- settings binding (one optional dotted level: "roguePoison.mh")
--------------------------------------------------------------------------

local function GetPath(key)
    local dot = string.find(key, "%.")
    if dot then
        local a = string.sub(key, 1, dot - 1)
        local b = string.sub(key, dot + 1)
        local t = RallyPowerCP_Settings[a]
        if type(t) == "table" then return t[b] end
        return nil
    end
    return RallyPowerCP_Settings[key]
end

local function SetPath(key, v)
    local dot = string.find(key, "%.")
    if dot then
        local a = string.sub(key, 1, dot - 1)
        local b = string.sub(key, dot + 1)
        if type(RallyPowerCP_Settings[a]) ~= "table" then
            RallyPowerCP_Settings[a] = {}
        end
        RallyPowerCP_Settings[a][b] = v
    else
        RallyPowerCP_Settings[key] = v
    end
end

local RefreshControls   -- forward declaration (EntrySet calls it)

local function EntryGet(entry)
    if entry.get then return entry.get() end
    if not entry.key then return nil end
    local v = GetPath(entry.key)
    if v == nil then return entry.default end
    return v
end

local function EntrySet(entry, v)
    if entry.set then
        entry.set(v)
    elseif entry.key then
        SetPath(entry.key, v)
    end
    if entry.onChange then entry.onChange(v) end
    RefreshControls()
end

--------------------------------------------------------------------------
-- widget helpers
--------------------------------------------------------------------------

local function NextName()
    ctlCounter = ctlCounter + 1
    return "RallyPowerCP_OptCtl" .. ctlCounter
end

-- 1.12's UIDropDownMenu_SetWidth reads the implicit `this`; set it explicitly
-- so the call also works from plain code (harmless on the 2-arg signature).
local function DropDownSetWidth(dd, w)
    local saved = this
    this = dd
    UIDropDownMenu_SetWidth(w, dd)
    this = saved
end

-- Normalise a values() result: items may be plain strings or {value=,text=}.
local function NormItems(entry)
    local raw = (entry.values and entry.values()) or {}
    local out = {}
    for i = 1, table.getn(raw) do
        local it = raw[i]
        if type(it) == "table" then
            table.insert(out, { value = it.value, text = it.text or it.value })
        else
            table.insert(out, { value = it, text = it })
        end
    end
    return out
end

local function CurrentItemText(entry)
    local cur = EntryGet(entry)
    local items = NormItems(entry)
    for i = 1, table.getn(items) do
        if items[i].value == cur then return items[i].text end
    end
    if cur == nil then return "" end
    return tostring(cur)
end

--------------------------------------------------------------------------
-- the renderer: one creator per entry type, each returns the next y cursor
--------------------------------------------------------------------------

local function AddHeader(parent, y, entry)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD_X - 4, y - 4)
    fs:SetText(entry.label)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetTexture(0.8, 0.65, 0.2)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD_X - 4, y - 20)
    line:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(PAD_X - 4), y - 20)
    line:SetAlpha(0.35)
    return y - 26
end

local function AddCheck(parent, y, entry)
    local name = NextName()
    local cb = CreateFrame("CheckButton", name, parent, "OptionsCheckButtonTemplate")
    cb:SetWidth(24); cb:SetHeight(24)
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD_X - 2, y)
    getglobal(name .. "Text"):SetText(entry.label)
    cb.tooltipText = entry.tip
    cb.entry = entry
    cb:SetScript("OnClick", function()
        EntrySet(this.entry, this:GetChecked() and true or false)
    end)
    cb.Refresh = function()
        cb:SetChecked(EntryGet(entry) and 1 or nil)
    end
    cb.Refresh()
    table.insert(controls, cb)
    return y - 24
end

local function AddSlider(parent, y, entry)
    local name = NextName()
    local sl = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    sl:SetWidth(200); sl:SetHeight(16)
    sl:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD_X + 2, y - 16)
    sl:SetMinMaxValues(entry.min, entry.max)
    sl:SetValueStep(entry.step or 0.05)
    getglobal(name .. "Low"):SetText(entry.min)
    getglobal(name .. "High"):SetText(entry.max)
    sl.entry = entry
    sl.updating = false
    local function LabelText(v)
        getglobal(name .. "Text"):SetText(entry.label .. ": "
            .. string.format((entry.step or 0.05) >= 1 and "%d" or "%.2f", v))
    end
    sl:SetScript("OnValueChanged", function()
        local step = this.entry.step or 0.05
        local v = this:GetValue()
        v = this.entry.min + math.floor((v - this.entry.min) / step + 0.5) * step
        v = math.floor(v * 100 + 0.5) / 100
        LabelText(v)
        if this.updating then return end
        local cur = EntryGet(this.entry)
        if type(cur) == "number" and math.abs(cur - v) < 0.001 then return end
        EntrySet(this.entry, v)
    end)
    sl.Refresh = function()
        local v = EntryGet(entry)
        if type(v) ~= "number" then v = entry.default or entry.min end
        sl.updating = true
        sl:SetValue(v)
        sl.updating = false
        LabelText(v)
    end
    sl.Refresh()
    table.insert(controls, sl)
    return y - 44
end

local function AddSelect(parent, y, entry)
    local name = NextName()
    local caption = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    caption:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD_X - 2, y - 10)
    caption:SetText(entry.label)
    local dd = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
    -- the template carries ~16px of built-in horizontal padding
    dd:SetPoint("TOPLEFT", parent, "TOPLEFT", 118, y + 2)
    dd.entry = entry
    UIDropDownMenu_Initialize(dd, function()
        local cur = EntryGet(dd.entry)
        local items = NormItems(dd.entry)
        for i = 1, table.getn(items) do
            local it = items[i]
            local info = {}
            info.text = it.text
            info.value = it.value
            if it.value == cur then info.checked = 1 end
            info.func = function()
                EntrySet(dd.entry, it.value)
                getglobal(name .. "Text"):SetText(it.text)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    DropDownSetWidth(dd, 130)
    dd.Refresh = function()
        getglobal(name .. "Text"):SetText(CurrentItemText(entry))
    end
    dd.Refresh()
    table.insert(controls, dd)
    return y - 34
end

local function AddButtonCtl(parent, y, entry)
    local name = NextName()
    local btn = CreateFrame("Button", name, parent, "GameMenuButtonTemplate")
    btn:SetWidth(130); btn:SetHeight(21)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD_X - 2, y - 4)
    btn:SetText(entry.label)
    btn.entry = entry
    btn:SetScript("OnClick", function()
        if this.entry.func then this.entry.func() end
        RefreshControls()
    end)
    if entry.tip then
        btn:SetScript("OnEnter", function()
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            GameTooltip:SetText(this.entry.tip, 1, 1, 1, 1, 1)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return y - 30
end

local function AddNote(parent, y, entry)
    local h = entry.height or 28
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD_X - 4, y - 4)
    fs:SetWidth(NOTE_W)
    fs:SetHeight(h)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetText(entry.label)
    return y - h - 8
end

local CREATORS = {
    header = AddHeader,
    check  = AddCheck,
    slider = AddSlider,
    select = AddSelect,
    button = AddButtonCtl,
    note   = AddNote,
}

local function BuildControls(parent, entries)
    local y = -6
    for i = 1, table.getn(entries) do
        local entry = entries[i]
        local make = CREATORS[entry.type]
        if make then y = make(parent, y, entry) end
    end
end

-- Re-read every bound value (cheap: settings only, no game API). Called after
-- any change and on a slow tick while the frame is open, so the dropdowns
-- round-trip with the mouse-wheel selections made on the strips.
RefreshControls = function()
    for _, c in ipairs(controls) do
        if c.Refresh then c.Refresh() end
    end
end

--------------------------------------------------------------------------
-- tab descriptors
--------------------------------------------------------------------------

local function ResetFramePositions()
    local kill = {}
    for k in pairs(RallyPowerCP_Settings) do
        if string.find(k, "^stripPos_") then table.insert(kill, k) end
    end
    for _, k in ipairs(kill) do RallyPowerCP_Settings[k] = nil end
    if RallyPowerCP.strips then
        for _, S in pairs(RallyPowerCP.strips) do
            S.frame:ClearAllPoints()
            S.frame:SetPoint("CENTER", UIParent, "CENTER", 260, 0)
        end
    end
    RallyPowerCP_ResetBarPosition()
    DEFAULT_CHAT_FRAME:AddMessage("|cffffff00RallyPowerCP:|r Frame positions reset.")
end

local SETTINGS_INFO = {
    { type = "header", label = "When to show" },
    { type = "check", key = "showSolo",  label = "Show when solo",  default = true,
      onChange = function() RallyPowerCP_ApplyVisibility() end },
    { type = "check", key = "showParty", label = "Show in a party", default = true,
      onChange = function() RallyPowerCP_ApplyVisibility() end },
    { type = "check", key = "showRaid",  label = "Show in a raid",  default = true,
      onChange = function() RallyPowerCP_ApplyVisibility() end },
    { type = "check", key = "tooltips",  label = "Show tooltips",   default = true },
    { type = "check", key = "testMode",  label = "Test mode",       default = false,
      tip = "Same as /rpc test: every option is shown (unlearned ones marked *) and clicks simulate casts.",
      set = function(v) RallyPowerCP_SetTestMode(v) end },
    { type = "header", label = "Looks" },
    { type = "slider", key = "uiScale", label = "UI scale",
      min = 0.5, max = 1.5, step = 0.05, default = 1.0,
      onChange = function() RallyPowerCP_ApplyUIScale() end },
    { type = "select", key = "minimapSkin", label = "Minimap icon", default = "blue",
      values = function()
          local out = {}
          for i = 1, table.getn(RallyPowerCP_MinimapSkins) do
              local v = RallyPowerCP_MinimapSkins[i]
              local lbl = (RallyPowerCP_MinimapSkinLabels and RallyPowerCP_MinimapSkinLabels[v]) or v
              table.insert(out, { value = v, text = lbl })
          end
          return out
      end,
      set = function(v) RallyPowerCP_ApplyMinimapSkin(v) end },
    { type = "check", key = "locked", label = "Lock frame positions", default = false },
    { type = "button", label = "Reset Frames", func = ResetFramePositions,
      tip = "Move every RallyPowerCP frame back to its default position." },
}

-- The Buttons tab: generated from the active class module. Grid classes get
-- auto-checks from M.buffs/M.utility; strip classes declare M.optionsInfo;
-- Paladins are pointed at the legacy /pp options (locked decision).
local function ButtonsTabEntries()
    local entries = {}
    local _, cls = UnitClass("player")
    if cls == "PALADIN" then
        table.insert(entries, { type = "note", height = 56, label =
            "Paladin buttons are configured in the classic PallyPower options: "
            .. "/pp, then Options. The legacy engine stays authoritative for the "
            .. "blessing grid; aura/seal/RF extras arrive in a later milestone." })
        return entries
    end
    local M = RallyPowerCP.active
    if not M then
        table.insert(entries, { type = "note", label =
            "No RallyPowerCP module is active for this class." })
        return entries
    end
    if M.buffs and table.getn(M.buffs) > 0 then
        table.insert(entries, { type = "header", label = "Tracked buffs" })
        for i = 1, table.getn(M.buffs) do
            local b = M.buffs[i]
            local nm = b.name or b.group
            table.insert(entries, { type = "check", key = "gridbuff_" .. nm,
                label = nm, default = true,
                onChange = function() RallyPowerCP_GridRefresh() end })
        end
    end
    if M.utility and table.getn(M.utility) > 0 then
        table.insert(entries, { type = "check", key = "utilRow",
            label = "Utility buttons (top row)", default = true,
            onChange = function() RallyPowerCP_GridRefresh() end })
    end
    if M.optionsInfo then
        for i = 1, table.getn(M.optionsInfo) do
            table.insert(entries, M.optionsInfo[i])
        end
    end
    if table.getn(entries) == 0 then
        table.insert(entries, { type = "note", label =
            "This class has no configurable buttons yet." })
    end
    return entries
end

local RAID_INFO = {
    { type = "header", label = "Raid" },
    { type = "note", height = 44, label =
        "Raid roles & auto-buff overrides arrive with the Assignment & Sync "
        .. "milestone (MT/MA roles, Free Assignment, auto-buff by role)." },
}

--------------------------------------------------------------------------
-- tabs + frame
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

local function ShowTab(i)
    if not panels[i] then i = 1 end
    currentTab = i
    RallyPowerCP_Settings.optLastTab = i
    for n = 1, table.getn(panels) do
        if n == i then panels[n]:Show() else panels[n]:Hide() end
    end
    -- build lazily on first show (the Buttons tab needs the active module,
    -- which exists once the player is in the world)
    local p = panels[i]
    if not p.built then
        p.built = true
        if i == 1 then BuildControls(p, SETTINGS_INFO)
        elseif i == 2 then BuildControls(p, ButtonsTabEntries())
        else BuildControls(p, RAID_INFO) end
    end
    StyleTabs()
    RefreshControls()
end

local function CreateOptionsFrame()
    local f = CreateFrame("Frame", "RallyPowerCP_OptionsFrame", UIParent)
    optFrame = f
    f:SetWidth(FRAME_W); f:SetHeight(FRAME_H)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
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
    tinsert(UISpecialFrames, "RallyPowerCP_OptionsFrame")   -- ESC closes

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", f, "TOP", 0, -10)
    title:SetText("|cffffd100RallyPowerCP|r Options")

    CreateFrame("Button", nil, f, "UIPanelCloseButton"):SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)

    -- tab row
    local tx = 10
    for i = 1, table.getn(TAB_INFO) do
        local idx = i
        local b = CreateFrame("Button", nil, f)
        b:SetWidth(76); b:SetHeight(22)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", tx, -30)
        b:SetBackdrop(TAB_SKIN)
        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("CENTER", b, "CENTER", 0, 0)
        fs:SetText(TAB_INFO[i].label)
        b.label = fs
        b:SetScript("OnClick", function() ShowTab(idx) end)
        tabBtns[i] = b
        tx = tx + 80
    end

    -- content panels
    for i = 1, table.getn(TAB_INFO) do
        local p = CreateFrame("Frame", nil, f)
        p:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -56)
        p:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)
        p:Hide()
        panels[i] = p
    end

    f:SetScript("OnShow", function()
        ShowTab(RallyPowerCP_Settings.optLastTab or 1)
    end)

    -- slow settings-only refresh while open, so strip-wheel changes show up
    local accum = 0
    f:SetScript("OnUpdate", function()
        accum = accum + (arg1 or 0)
        if accum < 0.5 then return end
        accum = 0
        RefreshControls()
    end)
end

-- Entry point: /rpc options and the minimap right-click (non-Paladins).
function RallyPowerCP_OptionsToggle()
    if not optFrame then CreateOptionsFrame() end
    if optFrame:IsShown() then optFrame:Hide() else optFrame:Show() end
end
