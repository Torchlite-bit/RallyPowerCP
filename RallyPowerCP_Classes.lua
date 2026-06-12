--=============================================================================
-- RallyPowerCP_Classes.lua
-- All-class buff tracking module for RallyPowerCP (Turtle WoW 1.18.1 / 1.12 client)
--
-- Author: Subtilizer (Torchlite)
--
-- WHAT THIS DOES
--   * Auto-detects the logged-in player's class.
--   * PALADIN  -> does nothing. The original PallyPower grid/buffbar owns the UI,
--                 so the Paladin experience is 100% unchanged.
--   * EVERY OTHER CLASS -> builds a small, movable "RallyPower" bar (styled to
--                 match PallyPower) that shows each group buff that class provides
--                 and how many party/raid members are still missing it.
--                 Red = someone needs it, faded = everyone is covered.
--                 Left-click  = cast the single-target buff (rebuff your target).
--                 Right-click = cast the group/greater version (if you know it).
--
-- HOW BUFFS ARE DETECTED (important on the 1.12 client)
--   On the 1.12 client you cannot read another player's buff *names* directly;
--   UnitBuff() only gives you a texture path. So, exactly like PallyPower does,
--   we identify buffs by their icon texture. Each buff below lists the icon(s)
--   its applied aura uses. To add a class/buff, just add a row to
--   RallyPowerCP_ClassBuffs with the correct icon name(s).
--
-- EXTENDING
--   Add classes/buffs to RallyPowerCP_ClassBuffs. Fields:
--     name   = exact single-target spell name (for casting + spellbook check)
--     group  = exact group/greater spell name (optional, right-click cast)
--     icons  = { "IconBaseName", ... } one or more applied-aura icon basenames
--     pet    = true if this buff is worth tracking on pets too (default false)
--=============================================================================

RallyPowerCP_Settings = RallyPowerCP_Settings or {}

local PLAYER_CLASS               -- e.g. "PRIEST"  (English, locale-independent)
local ACTIVE_BUFFS = {}          -- the buff list for PLAYER_CLASS (or nil)
local KNOWN = {}                 -- set of spell names the player actually knows
local NEEDCOUNT = {}             -- per-buff: how many roster members still need it
local lastScan = 0
local SCAN_INTERVAL = 1.0        -- seconds between roster rescans
local bar                        -- the bar frame (created lazily)
local buttons = {}               -- bar buttons, one per active buff

-- Timer tracking (PallyPower-style): we record an expiry time whenever WE cast
-- a buff (keyed by the recipient's character name), and we read exact times for
-- buffs on OURSELF via the player-buff API. The 1.12 client gives no way to
-- read remaining time on other players' buffs, so — exactly like PallyPower —
-- timers come from our own casts; the coverage scan self-corrects if a buff
-- drops early or a cast actually failed.
local expiry = {}                -- expiry[charName][buffName] = GetTime() deadline
local minRemain = {}             -- per active buff: soonest expiry among holders
local warned = {}                -- per active buff: ding played for this cycle?
local WARN_TIME = 60             -- seconds left when the warning ding plays

--=============================================================================
-- BUFF DATA TABLE  (keyed by the English class token from UnitClass)
--=============================================================================
--   Fields: name/group (spell names), icons (applied-aura icon basenames),
--   pet (track on pets), dur/gdur (single/group buff duration in seconds —
--   used for the countdown timers; edit here if Turtle tunes a duration).
RallyPowerCP_ClassBuffs = {
    PRIEST = {
        { name = "Power Word: Fortitude", group = "Prayer of Fortitude",
          icons = { "Spell_Holy_WordFortitude" }, pet = true,
          dur = 30*60, gdur = 60*60 },
        { name = "Divine Spirit",         group = "Prayer of Spirit",
          icons = { "Spell_Holy_DivineSpirit", "Spell_Holy_PrayerofSpirit" },
          dur = 30*60, gdur = 60*60 },
        { name = "Shadow Protection",     group = "Prayer of Shadow Protection",
          icons = { "Spell_Shadow_AntiShadow" },
          dur = 10*60, gdur = 20*60 },
    },

    MAGE = {
        { name = "Arcane Intellect",      group = "Arcane Brilliance",
          icons = { "Spell_Holy_MagicalSentry", "Spell_Holy_ArcaneIntellect" },
          dur = 30*60, gdur = 60*60 },
    },

    DRUID = {
        { name = "Mark of the Wild",      group = "Gift of the Wild",
          icons = { "Spell_Nature_Regeneration" }, pet = true,
          dur = 30*60, gdur = 60*60 },
        { name = "Thorns",
          icons = { "Spell_Nature_Thorns" },
          dur = 10*60 },
    },

    -- ---- Stubs below: add icons/names to enable. They will simply not show
    --      until they contain at least one entry. Left here as a guide. ----
    WARRIOR = {
        -- Battle Shout is a short, in-combat shout rather than a maintained
        -- raid buff, so it is intentionally left out of the reminder for now.
    },
    HUNTER  = {
        -- Trueshot Aura is an aura, active while the hunter is grouped.
    },
    SHAMAN  = {
        -- Totems are range auras, tracked differently; planned for a later build.
    },
    WARLOCK = {},
    ROGUE   = {},
}

--=============================================================================
-- HELPERS
--=============================================================================

-- Return the lowercased final path segment of a texture, e.g.
-- "Interface\\Icons\\Spell_Holy_WordFortitude" -> "spell_holy_wordfortitude"
local function IconBase(tex)
    if not tex then return nil end
    local base = tex
    local s, e = string.find(base, "([^\\]+)$")
    if s then base = string.sub(base, s, e) end
    return string.lower(base)
end

-- Pre-lowercase the icon sets once so scanning is cheap.
local function BuildIconLookups()
    if not ACTIVE_BUFFS then return end
    for _, b in pairs(ACTIVE_BUFFS) do
        b._iconset = {}
        if b.icons then
            for _, ic in pairs(b.icons) do
                b._iconset[string.lower(ic)] = true
            end
        end
    end
end

-- Does this unit currently have buff b? (matched by icon texture)
local function UnitHasBuff(unit, b)
    local j = 1
    while true do
        local tex = UnitBuff(unit, j, true)   -- 1.12/Turtle: returns icon texture
        if not tex then
            tex = UnitBuff(unit, j)            -- fallback signature, just in case
        end
        if not tex then break end
        if b._iconset[IconBase(tex)] then return true end
        j = j + 1
        if j > 40 then break end
    end
    return false
end

-- Is this unit a valid, buffable group member right now?
local function UnitIsBuffable(unit)
    if not UnitExists(unit) then return false end
    if not UnitIsConnected(unit) then return false end
    if UnitIsDeadOrGhost(unit) then return false end
    return true
end

-- Build the current party/raid roster as a list of unit IDs (includes "player").
local function BuildRoster(out, withPets)
    local n = 0
    local numRaid = GetNumRaidMembers()
    if numRaid > 0 then
        local i = 1
        while i <= numRaid do
            n = n + 1; out[n] = "raid" .. i
            if withPets then n = n + 1; out[n] = "raidpet" .. i end
            i = i + 1
        end
    else
        n = n + 1; out[n] = "player"
        if withPets then n = n + 1; out[n] = "pet" end
        local numParty = GetNumPartyMembers()
        local i = 1
        while i <= numParty do
            n = n + 1; out[n] = "party" .. i
            if withPets then n = n + 1; out[n] = "partypet" .. i end
            i = i + 1
        end
    end
    return n
end

--=============================================================================
-- SPELLBOOK KNOWLEDGE  -- only show buttons for spells the player actually has
--=============================================================================
local function RebuildKnownSpells()
    for k in pairs(KNOWN) do KNOWN[k] = nil end
    local i = 1
    while true do
        local spellName = GetSpellName(i, BOOKTYPE_SPELL)
        if not spellName then break end
        KNOWN[spellName] = true
        i = i + 1
    end
end

-- A buff is "usable" if the player knows either its single or group form.
local function BuffIsUsable(b)
    if b.name and KNOWN[b.name] then return true end
    if b.group and KNOWN[b.group] then return true end
    return false
end

--=============================================================================
-- THE BAR  (created in Lua, styled to match PallyPower's dark panel)
--=============================================================================
local BTN_SIZE   = 32
local PAD        = 6
local ROW_H      = BTN_SIZE + 4
local TIMER_W    = 44                      -- room for "59:59" beside the icon
local BAR_W      = PAD + BTN_SIZE + 4 + TIMER_W + PAD

local function SavePosition()
    if not bar then return end
    local point, _, relPoint, x, y = bar:GetPoint()
    RallyPowerCP_Settings.barPoint   = point
    RallyPowerCP_Settings.barRelPoint = relPoint
    RallyPowerCP_Settings.barX = x
    RallyPowerCP_Settings.barY = y
end

-- Exact remaining time of buff b on the PLAYER (real data via the 1.12 API).
local function PlayerBuffTimeLeft(b)
    local i = 0
    while i < 32 do
        local idx = GetPlayerBuff(i, "HELPFUL")
        if not idx or idx < 0 then break end
        local tex = GetPlayerBuffTexture(idx)
        if tex and b._iconset[IconBase(tex)] then
            return GetPlayerBuffTimeLeft(idx)
        end
        i = i + 1
    end
    return nil
end

-- Find the next group member (or pet) who is missing buff b.
-- Prefers your current friendly target if THEY are missing it.
local findRoster = {}
local function FindNeedyUnit(b)
    if UnitExists("target") and UnitIsFriend("player", "target")
       and UnitIsBuffable("target") and not UnitHasBuff("target", b) then
        return "target"
    end
    local count = BuildRoster(findRoster, b.pet and true or false)
    for r = 1, count do
        local u = findRoster[r]
        if UnitIsBuffable(u) then
            local isPet = (string.find(u, "pet") ~= nil)
            if (not isPet or b.pet) and not UnitHasBuff(u, b) then
                return u
            end
        end
    end
    return nil
end

local function RecordExpiry(unit, b, dur)
    if not dur then return end
    local nm = UnitName(unit)
    if not nm then return end
    expiry[nm] = expiry[nm] or {}
    expiry[nm][b.name or b.group] = GetTime() + dur
end

-- For a group-version cast on `unit`, record expiry for that unit's whole
-- subgroup (party: everyone; raid: the unit's raid subgroup).
local function RecordGroupExpiry(unit, b, dur)
    if not dur then return end
    local numRaid = GetNumRaidMembers()
    if numRaid > 0 then
        local _, _, uidx = string.find(unit, "raid(%d+)")
        uidx = tonumber(uidx)
        if not uidx then RecordExpiry(unit, b, dur) return end
        local _, _, sub = GetRaidRosterInfo(uidx)
        local targetSub = sub
        for i = 1, numRaid do
            local nm, _, isub = GetRaidRosterInfo(i)
            if nm and isub == targetSub then
                expiry[nm] = expiry[nm] or {}
                expiry[nm][b.name or b.group] = GetTime() + dur
            end
        end
    else
        RecordExpiry("player", b, dur)
        for i = 1, GetNumPartyMembers() do
            RecordExpiry("party" .. i, b, dur)
        end
    end
end

-- Cast `spell` on `unit` using PallyPower's proven 1.12 pattern:
-- with no/hostile target, CastSpellByName raises the targeting cursor and
-- SpellTargetUnit directs it (this also kills the auto-self-cast problem);
-- with a DIFFERENT friendly target selected, briefly retarget and swap back.
local function CastBuffOn(spell, unit, b, dur, isGroup)
    if not spell then return end
    if UnitExists("target") and UnitIsFriend("player", "target")
       and not UnitIsUnit("target", unit) then
        TargetUnit(unit)
        CastSpellByName(spell)
        if SpellIsTargeting() then SpellTargetUnit(unit) end
        if SpellIsTargeting() then SpellStopTargeting() end
        TargetLastTarget()
    else
        CastSpellByName(spell)
        if SpellIsTargeting() then SpellTargetUnit(unit) end
        if SpellIsTargeting() then
            -- couldn't land it (range/LoS) — cancel cleanly, record nothing
            SpellStopTargeting()
            return
        end
    end
    if isGroup then RecordGroupExpiry(unit, b, dur)
    else RecordExpiry(unit, b, dur) end
end

local function ButtonOnClick()
    -- arg1 holds the mouse button on the 1.12 client
    local idx = this.buffIndex
    local b = ACTIVE_BUFFS[idx]
    if not b then return end

    local unit = FindNeedyUnit(b) or "player"   -- all covered: refresh self
    if arg1 == "RightButton" and b.group and KNOWN[b.group] then
        CastBuffOn(b.group, unit, b, b.gdur, true)
    elseif b.name and KNOWN[b.name] then
        CastBuffOn(b.name, unit, b, b.dur, false)
    elseif b.group and KNOWN[b.group] then
        CastBuffOn(b.group, unit, b, b.gdur, true)
    end
    lastScan = SCAN_INTERVAL   -- rescan promptly to refresh counts/timers
end

local function CreateBar()
    if bar then return bar end

    bar = CreateFrame("Frame", "RallyPowerCP_Bar", UIParent)
    bar:SetWidth(BAR_W)
    bar:SetHeight(ROW_H + 18)
    bar:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    bar:SetBackdropColor(0, 0, 0, 0.7)
    bar:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    bar:SetMovable(true)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() bar:StartMoving() end)
    bar:SetScript("OnDragStop", function() bar:StopMovingOrSizing(); SavePosition() end)

    -- Restore saved position, else default to center-right.
    if RallyPowerCP_Settings.barPoint then
        bar:SetPoint(RallyPowerCP_Settings.barPoint, UIParent,
                     RallyPowerCP_Settings.barRelPoint,
                     RallyPowerCP_Settings.barX, RallyPowerCP_Settings.barY)
    else
        bar:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
    end

    -- Title strip
    local title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOP", bar, "TOP", 0, -4)
    local cname = PLAYER_CLASS and (string.sub(PLAYER_CLASS,1,1)
                  .. string.lower(string.sub(PLAYER_CLASS,2))) or "Buffs"
    title:SetText(cname)
    bar.title = title

    return bar
end

local function LayoutButtons()
    if not bar then return end
    -- Build the list of usable buffs (known spells only).
    local visible = {}
    if ACTIVE_BUFFS then
        for i = 1, table.getn(ACTIVE_BUFFS) do
            local b = ACTIVE_BUFFS[i]
            if BuffIsUsable(b) then table.insert(visible, i) end
        end
    end

    -- Hide all old buttons first.
    for _, btn in pairs(buttons) do btn:Hide() end

    local y = -18
    local shown = 0
    for slot = 1, table.getn(visible) do
        local buffIndex = visible[slot]
        local b = ACTIVE_BUFFS[buffIndex]
        local btn = buttons[slot]
        if not btn then
            btn = CreateFrame("Button", "RallyPowerCP_BarBtn" .. slot, bar)
            btn:SetWidth(BTN_SIZE); btn:SetHeight(BTN_SIZE)
            btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

            local bg = btn:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints(btn)
            bg:SetTexture(1, 0, 0, 0.35)
            btn.bg = bg

            local icon = btn:CreateTexture(nil, "ARTWORK")
            icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
            icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
            btn.icon = icon

            local count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
            count:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
            btn.count = count

            -- countdown readout to the right of the icon (like the Pally bar)
            local timer = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            timer:SetPoint("LEFT", btn, "RIGHT", 4, 0)
            timer:SetJustifyH("LEFT")
            btn.timer = timer

            btn:SetScript("OnClick", ButtonOnClick)
            btn:SetScript("OnEnter", function()
                GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                local bb = ACTIVE_BUFFS[this.buffIndex]
                GameTooltip:SetText(bb.name or bb.group or "Buff", 1, 1, 1)
                GameTooltip:AddLine("Left-click: buff the next group member missing it", 0.8, 0.8, 0.8)
                if bb.group then
                    GameTooltip:AddLine("Right-click: " .. bb.group .. " on their group", 0.8, 0.8, 0.8)
                end
                GameTooltip:AddLine("Timer shows the soonest expiry you've cast", 0.6, 0.6, 0.6)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

            buttons[slot] = btn
        end

        btn.buffIndex = buffIndex
        -- Icon: use the first icon basename for display.
        local iconName = (b.icons and b.icons[1]) or "INV_Misc_QuestionMark"
        btn.icon:SetTexture("Interface\\Icons\\" .. iconName)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", bar, "TOPLEFT", PAD, y)
        btn:Show()
        y = y - ROW_H
        shown = shown + 1
    end

    bar:SetHeight(18 + shown * ROW_H + 6)
    if shown == 0 then bar:Hide() end
end

--=============================================================================
-- SCAN: count how many roster members still need each active buff
--=============================================================================
local roster = {}
local function ScanRoster()
    if not ACTIVE_BUFFS or PLAYER_CLASS == "PALADIN" then return end

    -- Does any active buff want pets? Then include pets in the roster.
    local withPets = false
    for i = 1, table.getn(ACTIVE_BUFFS) do
        if ACTIVE_BUFFS[i].pet then withPets = true break end
    end

    local count = BuildRoster(roster, withPets)

    for i = 1, table.getn(ACTIVE_BUFFS) do NEEDCOUNT[i] = 0; minRemain[i] = nil end

    local now = GetTime()
    for r = 1, count do
        local unit = roster[r]
        if UnitIsBuffable(unit) then
            local isPet = (string.find(unit, "pet") ~= nil)
            local uname = UnitName(unit)
            for i = 1, table.getn(ACTIVE_BUFFS) do
                local b = ACTIVE_BUFFS[i]
                if BuffIsUsable(b) and (not isPet or b.pet) then
                    if not UnitHasBuff(unit, b) then
                        NEEDCOUNT[i] = NEEDCOUNT[i] + 1
                        -- buff is gone: drop any stale recorded timer
                        if uname and expiry[uname] then
                            expiry[uname][b.name or b.group] = nil
                        end
                    else
                        -- buff present: figure out time left for the countdown
                        local left = nil
                        if UnitIsUnit(unit, "player") then
                            left = PlayerBuffTimeLeft(b)   -- exact, via API
                        elseif uname and expiry[uname] then
                            local dl = expiry[uname][b.name or b.group]
                            if dl then
                                left = dl - now
                                if left <= 0 then
                                    expiry[uname][b.name or b.group] = nil
                                    left = nil
                                end
                            end
                        end
                        if left and (not minRemain[i] or left < minRemain[i]) then
                            minRemain[i] = left
                        end
                    end
                end
            end
        end
    end

    -- Expiry warning ding (same sound + spirit as the Paladin bar)
    for i = 1, table.getn(ACTIVE_BUFFS) do
        local mr = minRemain[i]
        if mr and mr <= WARN_TIME and mr > 0 then
            if not warned[i] then
                warned[i] = true
                PlaySoundFile("Interface\\Addons\\RallyPowerCP\\Sounds\\ding.mp3")
                local b = ACTIVE_BUFFS[i]
                DEFAULT_CHAT_FRAME:AddMessage("|cffffff00RallyPowerCP:|r "
                    .. (b.name or b.group) .. " is about to expire!")
            end
        else
            warned[i] = nil   -- re-arm once refreshed (or no timer tracked)
        end
    end

    -- Update button visuals.
    if not bar then return end
    for slot = 1, table.getn(buttons) do
        local btn = buttons[slot]
        if btn and btn:IsShown() then
            local need = NEEDCOUNT[btn.buffIndex] or 0
            if need > 0 then
                btn.bg:SetTexture(0.8, 0.1, 0.1, 0.6)   -- red: someone needs it
                btn.count:SetText(need)
                btn.icon:SetVertexColor(1, 1, 1)
            else
                btn.bg:SetTexture(0.1, 0.6, 0.1, 0.25)  -- green/faded: all covered
                btn.count:SetText("")
                btn.icon:SetVertexColor(0.55, 0.55, 0.55)
            end
            -- countdown readout (soonest expiry among tracked holders)
            local mr = minRemain[btn.buffIndex]
            if mr then
                local m = math.floor(mr / 60)
                local s = math.floor(mr - m * 60)
                btn.timer:SetText(string.format("%d:%02d", m, s))
                if mr <= WARN_TIME then
                    btn.timer:SetTextColor(1, 0.25, 0.25)   -- red: about to expire
                else
                    btn.timer:SetTextColor(0.9, 0.9, 0.9)
                end
            else
                btn.timer:SetText("")
            end
        end
    end
end

--=============================================================================
-- ACTIVATION
--=============================================================================
local function Activate()
    local _, classToken = UnitClass("player")
    PLAYER_CLASS = classToken

    if PLAYER_CLASS == "PALADIN" then
        -- Hand everything to the original PallyPower engine. Stay dormant.
        ACTIVE_BUFFS = nil
        if bar then bar:Hide() end
        return
    end

    ACTIVE_BUFFS = RallyPowerCP_ClassBuffs[PLAYER_CLASS]

    -- Empty/undefined class table -> nothing to show (e.g. Warrior/Rogue for now).
    if not ACTIVE_BUFFS or table.getn(ACTIVE_BUFFS) == 0 then
        ACTIVE_BUFFS = nil
        if bar then bar:Hide() end
        return
    end

    BuildIconLookups()
    RebuildKnownSpells()
    CreateBar()
    LayoutButtons()
    if RallyPowerCP_Settings.hidden then bar:Hide() else bar:Show() end
    ScanRoster()
end

--=============================================================================
-- EVENT FRAME  (separate from PallyPower's, so the Paladin engine is untouched)
--=============================================================================
local f = CreateFrame("Frame", "RallyPowerCP_ClassFrame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("SPELLS_CHANGED")
f:RegisterEvent("PARTY_MEMBERS_CHANGED")
f:RegisterEvent("RAID_ROSTER_UPDATE")
f:RegisterEvent("UNIT_AURA")
f:RegisterEvent("PLAYER_AURAS_CHANGED")

f:SetScript("OnEvent", function()
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        Activate()
        RallyPowerCP_ApplyMinimapSkin()   -- restore the saved icon skin
    elseif event == "SPELLS_CHANGED" then
        if PLAYER_CLASS and PLAYER_CLASS ~= "PALADIN" then
            RebuildKnownSpells()
            LayoutButtons()
            ScanRoster()
        end
    elseif PLAYER_CLASS and PLAYER_CLASS ~= "PALADIN" then
        -- roster/aura changed: rescan on the next throttled tick
        lastScan = SCAN_INTERVAL
    end
end)

f:SetScript("OnUpdate", function()
    if not ACTIVE_BUFFS then return end
    lastScan = lastScan + (arg1 or 0)
    if lastScan >= SCAN_INTERVAL then
        lastScan = 0
        ScanRoster()
    end
end)

--=============================================================================
-- SLASH COMMAND: /rpc  (toggle the class bar; paladins are told to use /pp)
--=============================================================================
-- Global toggle, callable from the slash command AND the minimap button.
-- Returns true if it handled a class bar; false if the caller (minimap) should
-- fall back to the Paladin behaviour.
function RallyPowerCP_ToggleBar()
    if PLAYER_CLASS == "PALADIN" then
        return false   -- let the Paladin engine handle it
    end
    if not ACTIVE_BUFFS then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00RallyPowerCP:|r No tracked group buffs for your class yet.")
        return true
    end
    if bar and bar:IsShown() then
        bar:Hide(); RallyPowerCP_Settings.hidden = true
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00RallyPowerCP:|r Bar hidden (/rpc to show).")
    else
        if not bar then CreateBar(); LayoutButtons() end
        bar:Show()
        RallyPowerCP_Settings.hidden = false
        ScanRoster()
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00RallyPowerCP:|r Bar shown.")
    end
    return true
end

-- Is the player a class the class bar serves? (used by the minimap routing)
function RallyPowerCP_IsClassBarUser()
    return PLAYER_CLASS ~= nil and PLAYER_CLASS ~= "PALADIN"
end

--=============================================================================
-- MINIMAP ICON SKINS  (shared minimap button -> works for every class)
--=============================================================================
RallyPowerCP_MinimapSkins = { "blue", "ivory", "white", "gold", "pearl" }
local SKIN_FILE = {
    blue  = "Minimap",        -- the default (also the XML fallback)
    ivory = "Minimap_ivory",
    white = "Minimap_white",
    gold  = "Minimap_gold",
    pearl = "Minimap_pearl",
}
local SKIN_LABEL = {
    blue="Blue & Gold", ivory="Ivory & Gold", white="White & Gold",
    gold="Gold & White", pearl="Pearl & Gold",
}

function RallyPowerCP_ApplyMinimapSkin(name)
    name = name or RallyPowerCP_Settings.minimapSkin or "blue"
    if not SKIN_FILE[name] then name = "blue" end
    RallyPowerCP_Settings.minimapSkin = name
    local btn = getglobal("PallyPowerMinimapButton")
    if not btn then return end
    local base = "Interface\\AddOns\\RallyPowerCP\\Icons\\" .. SKIN_FILE[name]
    btn:SetNormalTexture(base)
    btn:SetPushedTexture(base .. "_Down")
end

-- Cycle to the next skin, or set one directly by name. Callable from the slash
-- command and from a shift-click on the minimap button.
function RallyPowerCP_MinimapSkinCommand(arg)
    arg = arg and string.gsub(arg, "^%s*(.-)%s*$", "%1") or ""
    if arg ~= "" and SKIN_FILE[arg] then
        RallyPowerCP_ApplyMinimapSkin(arg)
    else
        local cur = RallyPowerCP_Settings.minimapSkin or "blue"
        local idx = 1
        for i = 1, table.getn(RallyPowerCP_MinimapSkins) do
            if RallyPowerCP_MinimapSkins[i] == cur then idx = i end
        end
        idx = idx + 1
        if idx > table.getn(RallyPowerCP_MinimapSkins) then idx = 1 end
        RallyPowerCP_ApplyMinimapSkin(RallyPowerCP_MinimapSkins[idx])
    end
    local cur = RallyPowerCP_Settings.minimapSkin
    DEFAULT_CHAT_FRAME:AddMessage("|cffffff00RallyPowerCP:|r Minimap icon: |cffffd700"
        .. (SKIN_LABEL[cur] or cur) .. "|r  (/rpc icon to cycle, or shift-click the icon)")
end

SLASH_RALLYPOWERCP1 = "/rpc"
SlashCmdList["RALLYPOWERCP"] = function(msg)
    msg = string.lower(msg or "")

    -- Icon skin toggle: available to EVERY class (the minimap button is shared).
    if msg == "icon" then
        RallyPowerCP_MinimapSkinCommand("")
        return
    end
    if string.sub(msg, 1, 5) == "icon " then
        RallyPowerCP_MinimapSkinCommand(string.sub(msg, 6))
        return
    end

    if PLAYER_CLASS == "PALADIN" then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00RallyPowerCP:|r As a Paladin, use /pp for the blessing grid. (/rpc icon changes the minimap icon.)")
        return
    end
    if msg == "reset" then
        RallyPowerCP_Settings.barPoint = nil
        if bar then
            bar:ClearAllPoints()
            bar:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
        end
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00RallyPowerCP:|r Bar position reset.")
        return
    end
    RallyPowerCP_ToggleBar()
end
