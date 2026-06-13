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
local ACTIVE_UTILITY             -- utility-spell list for PLAYER_CLASS (or nil)
local KNOWN = {}                 -- set of spell names the player actually knows
local NEEDCOUNT = {}             -- per-buff: how many roster members still need it
local lastScan = 0
local SCAN_INTERVAL = 1.0        -- seconds between roster rescans
local bar                        -- the bar frame (created lazily)
local buttons = {}               -- bar buttons, one per active buff
local utilButtons = {}           -- top-row utility buttons (e.g. PW:Shield)

-- Timer tracking (PallyPower-style): we record an expiry time whenever WE cast
-- a buff (keyed by the recipient's character name), and we read exact times for
-- buffs on OURSELF via the player-buff API. The 1.12 client gives no way to
-- read remaining time on other players' buffs, so — exactly like PallyPower —
-- timers come from our own casts; the coverage scan self-corrects if a buff
-- drops early or a cast actually failed.
local expiry = {}                -- expiry[charName][buffName] = GetTime() deadline
local minDeadline = {}           -- per active buff: soonest absolute expiry (GetTime-based)
local warned = {}                -- per active buff: ding played for this cycle?
local WARN_TIME = 60             -- seconds left when the warning ding plays
local auraDirty = true           -- something changed: full roster rescan needed
local sinceFullScan = 0          -- safety-net full scan every FULL_SCAN_FALLBACK
local FULL_SCAN_FALLBACK = 5.0

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
-- CLASS UTILITY BUTTONS  (top row, like the Paladin seal / righteous-fury
-- buttons). Situational single-target casts rather than maintained buffs.
--   mode "lowhp"  : cast on your friendly target if you have one, else the
--                   lowest-health-percent in-range living group member.
--   mode "target" : cast on your friendly target, else yourself.
-- Icons are pulled live from your spellbook so they're always correct; the
-- `icon` field is only a fallback if the spell isn't found.
--=============================================================================
RallyPowerCP_ClassUtility = {
    PRIEST = {
        { name = "Power Word: Shield", mode = "lowhp",  icon = "Spell_Holy_PowerWordShield",
          tip = "lowest-health member in range (your target first)" },
        { name = "Fear Ward",          mode = "target", icon = "Spell_Holy_Excorcism_02",
          tip = "your target, else yourself" },
    },
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
-- Used for SINGLE-unit checks (e.g. the click targeter). The roster scan uses
-- CollectUnitBuffs/HasCollected below instead, which reads each unit's buff
-- list only ONCE per scan no matter how many buffs we track.
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

-- Single pass over a unit's buffs: fill `presentIcons` with every icon base.
local presentIcons = {}
local function CollectUnitBuffs(unit)
    for k in pairs(presentIcons) do presentIcons[k] = nil end
    local j = 1
    while j <= 40 do
        local tex = UnitBuff(unit, j, true)
        if not tex then tex = UnitBuff(unit, j) end
        if not tex then break end
        presentIcons[IconBase(tex)] = true
        j = j + 1
    end
end

-- After CollectUnitBuffs(unit): does the collected set contain buff b?
local function HasCollected(b)
    for ic in pairs(b._iconset) do
        if presentIcons[ic] then return true end
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
local UTIL_SIZE  = 28
local UTIL_GAP   = 4
local UTIL_ROW_H = UTIL_SIZE + 6

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

-- Scratch roster tables (declared before the functions that close over them).
local findRoster = {}
local findRoster2 = {}

-- Is `unit` actually part of our party/raid (not a random NPC/stranger)?
local function UnitIsGroupMember(unit)
    local count = BuildRoster(findRoster2, true)
    for r = 1, count do
        if UnitIsUnit(unit, findRoster2[r]) then return true end
    end
    return false
end

-- Round-robin cursor per buff: remembers the roster index we last cast on so
-- the NEXT click continues from the following member (wrapping around). This is
-- what makes repeated clicks cycle the whole group instead of locking onto the
-- first needy unit (which, with the player first in the roster, was you).
local cursor = {}

-- Pick a unit to (re)buff with buff b.
--   renew = false : only a member MISSING the buff (used by the Smart Buff key,
--                   which tops off the group then stops).
--   renew = true  : the click behaviour — a member missing it FIRST (efficient
--                   coverage), but if everyone in range already has it, return
--                   the next member anyway so you can RENEW at any time. A
--                   friendly group-member target is always (re)buffed on renew.
local function FindUnitToBuff(b, renew)
    if UnitExists("target") and UnitIsFriend("player", "target")
       and UnitIsBuffable("target") and UnitIsVisible("target")
       and UnitIsGroupMember("target") then
        if renew or not UnitHasBuff("target", b) then
            return "target"
        end
    end

    local count = BuildRoster(findRoster, b.pet and true or false)
    if count == 0 then return nil end
    local key = b.name or b.group
    local start = cursor[key] or 0
    local firstValid, firstValidIdx   -- for renew fallback when none are missing

    -- Walk the roster starting just AFTER the last unit we buffed, wrapping.
    local step = 1
    while step <= count do
        local idx = start + step
        while idx > count do idx = idx - count end
        local u = findRoster[idx]
        -- UnitIsVisible filters out members too far away to cast on, so a click
        -- never wastes itself on someone across the zone.
        if UnitIsBuffable(u) and UnitIsVisible(u) then
            local isPet = (string.find(u, "pet") ~= nil)
            if (not isPet or b.pet) then
                if not UnitHasBuff(u, b) then
                    cursor[key] = idx
                    return u                       -- missing it: top priority
                elseif renew and not firstValid then
                    firstValid, firstValidIdx = u, idx   -- remember to renew
                end
            end
        end
        step = step + 1
    end

    if renew and firstValid then
        cursor[key] = firstValidIdx
        return firstValid                          -- everyone covered: renew next
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

-- Announce a cast in green, exactly like the Paladin module. Reuses
-- PallyPower_ShowFeedback so it honours the user's chat-vs-UIErrors feedback
-- setting and the [RallyPowerCP] prefix; falls back to green chat text.
local function AnnounceBuff(spell, unit, isGroup)
    local name = UnitName(unit) or "?"
    local msg
    if isGroup then
        msg = "Casting " .. spell .. " on " .. name .. "'s group"
    else
        local locClass = UnitClass(unit) or ""
        msg = format(PallyPower_Casting or "Casting %s on %s (%s)", spell, locClass, name)
    end
    if PallyPower_ShowFeedback then
        PallyPower_ShowFeedback(msg, 0, 1, 0)
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RallyPowerCP] " .. msg .. "|r")
    end
end

-- Cast `spell` on `unit` using PallyPower's EXACT casting flow (copied from
-- its blessing cast): temporarily disable the autoSelfCast CVar, clear the
-- target so the targeting cursor is GUARANTEED to come up, direct it with
-- SpellTargetUnit, then restore the player's target and the CVar. This is
-- what makes one click reliably land on the chosen group member.
local function CastBuffOn(spell, unit, b, dur, isGroup)
    if not spell then return end

    local restoreCVar = false
    if GetCVar("autoSelfCast") == "1" then
        restoreCVar = true
        SetCVar("autoSelfCast", "0")
    end

    -- If the chosen unit IS our current friendly target, cast straight at them
    -- (clearing the target first would destroy the "target" unit reference).
    if UnitExists("target") and UnitIsUnit("target", unit)
       and UnitIsFriend("player", "target") then
        CastSpellByName(spell)
        if restoreCVar then SetCVar("autoSelfCast", "1") end
        AnnounceBuff(spell, unit, isGroup)
        if isGroup then RecordGroupExpiry(unit, b, dur)
        else RecordExpiry(unit, b, dur) end
        return
    end

    local hadTarget = UnitExists("target")
    ClearTarget()

    CastSpellByName(spell)

    local landed = false
    if SpellIsTargeting() then
        if SpellCanTargetUnit(unit) then
            SpellTargetUnit(unit)
            landed = not SpellIsTargeting()
        end
        if SpellIsTargeting() then
            SpellStopTargeting()          -- couldn't land it — cancel cleanly
        end
    end

    if hadTarget then TargetLastTarget() end
    if restoreCVar then SetCVar("autoSelfCast", "1") end

    if landed then
        AnnounceBuff(spell, unit, isGroup)
        if isGroup then RecordGroupExpiry(unit, b, dur)
        else RecordExpiry(unit, b, dur) end
    end
end

-- Resolve a spell's real icon from the spellbook (so utility buttons always
-- show the correct art regardless of hard-coded guesses).
local function GetSpellIconByName(spellName)
    local i = 1
    while true do
        local nm = GetSpellName(i, BOOKTYPE_SPELL)
        if not nm then break end
        if nm == spellName then return GetSpellTexture(i, BOOKTYPE_SPELL) end
        i = i + 1
    end
    return nil
end

-- Lowest-health-percent living group member in range (your friendly group-
-- member target wins if you have one). Used by "lowhp" utility buttons.
local utilScratch = {}
local function LowestHealthUnit()
    if UnitExists("target") and UnitIsFriend("player", "target")
       and UnitIsBuffable("target") and UnitIsVisible("target")
       and UnitIsGroupMember("target") then
        return "target"
    end
    local count = BuildRoster(utilScratch, false)
    local best, bestPct = nil, 2
    for r = 1, count do
        local u = utilScratch[r]
        if UnitIsBuffable(u) and UnitIsVisible(u) then
            local mh = UnitHealthMax(u)
            if mh and mh > 0 then
                local pct = UnitHealth(u) / mh
                if pct < bestPct then bestPct = pct; best = u end
            end
        end
    end
    return best
end

-- Categorize the whole group for buff b into the 4 PallyPower tooltip lists.
local tipScratch = {}
local function BuildBuffStatus(b, have, need, range, dead)
    local count = BuildRoster(tipScratch, b.pet and true or false)
    for r = 1, count do
        local u = tipScratch[r]
        if UnitExists(u) and UnitIsConnected(u) then
            local nm = UnitName(u) or "?"
            if not UnitIsVisible(u) then
                table.insert(range, nm)                 -- Not Here (out of range)
            elseif UnitIsDeadOrGhost(u) then
                if UnitHasBuff(u, b) then table.insert(have, nm)
                else table.insert(dead, nm) end
            elseif UnitHasBuff(u, b) then
                table.insert(have, nm)
            else
                table.insert(need, nm)
            end
        end
    end
end

-- Reliable single-target cast with no timer tracking (utility spells). Same
-- autoSelfCast/ClearTarget technique as CastBuffOn. Returns true if it landed.
local function CastSpellOnUnit(spell, unit)
    if not spell or not unit then return false end
    local restoreCVar = false
    if GetCVar("autoSelfCast") == "1" then restoreCVar = true; SetCVar("autoSelfCast", "0") end

    if UnitExists("target") and UnitIsUnit("target", unit)
       and UnitIsFriend("player", "target") then
        CastSpellByName(spell)
        if restoreCVar then SetCVar("autoSelfCast", "1") end
        return true
    end

    local hadTarget = UnitExists("target")
    ClearTarget()
    CastSpellByName(spell)
    local landed = false
    if SpellIsTargeting() then
        if SpellCanTargetUnit(unit) then
            SpellTargetUnit(unit)
            landed = not SpellIsTargeting()
        end
        if SpellIsTargeting() then SpellStopTargeting() end
    end
    if hadTarget then TargetLastTarget() end
    if restoreCVar then SetCVar("autoSelfCast", "1") end
    return landed
end

-- One-key smart buff (for the key binding): casts on the next group member
-- missing ANY of your tracked buffs — soonest-expiring buff types first.
-- Press it repeatedly to top off the whole group hands-free.
function RallyPowerCP_SmartBuff()
    if not ACTIVE_BUFFS or PLAYER_CLASS == "PALADIN" then return end
    for i = 1, table.getn(ACTIVE_BUFFS) do
        local b = ACTIVE_BUFFS[i]
        if BuffIsUsable(b) and (NEEDCOUNT[i] or 0) > 0 then
            local unit = FindUnitToBuff(b, false)
            if unit then
                local spell = (b.name and KNOWN[b.name]) and b.name or b.group
                CastBuffOn(spell, unit, b, (spell == b.name) and b.dur or b.gdur,
                           spell == b.group)
                auraDirty = true; lastScan = SCAN_INTERVAL
                return
            end
        end
    end
end

local function ButtonOnClick()
    -- arg1 holds the mouse button on the 1.12 client
    local idx = this.buffIndex
    local b = ACTIVE_BUFFS[idx]
    if not b then return end

    local unit = FindUnitToBuff(b, true)
    if not unit then
        -- nobody in range at all (everyone too far / offline / dead)
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00RallyPowerCP:|r "
            .. (b.name or b.group) .. ": no group members in range.")
        return
    end
    if arg1 == "RightButton" and b.group and KNOWN[b.group] then
        CastBuffOn(b.group, unit, b, b.gdur, true)
    elseif b.name and KNOWN[b.name] then
        CastBuffOn(b.name, unit, b, b.dur, false)
    elseif b.group and KNOWN[b.group] then
        CastBuffOn(b.group, unit, b, b.gdur, true)
    end
    auraDirty = true; lastScan = SCAN_INTERVAL   -- prompt full rescan
end

-- Click handler for a top-row utility button (PW: Shield, Fear Ward, ...).
local function UtilityOnClick()
    local u = ACTIVE_UTILITY and ACTIVE_UTILITY[this.utilIndex]
    if not u then return end
    if not KNOWN[u.name] then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00RallyPowerCP:|r You haven't learned " .. u.name .. ".")
        return
    end
    local target
    if u.mode == "lowhp" then
        target = LowestHealthUnit()
    else  -- "target": friendly target, else self
        if UnitExists("target") and UnitIsFriend("player", "target")
           and UnitIsBuffable("target") then
            target = "target"
        else
            target = "player"
        end
    end
    if not target then target = "player" end
    if CastSpellOnUnit(u.name, target) then
        AnnounceBuff(u.name, target, false)
    end
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

-- Build/refresh the top-row utility buttons. Returns the row height used.
-- Forward declaration: scroll/click closures below reach the display refresher,
-- whose full definition lives after the layout functions.
local UpdateDisplays

-- Build the Have / Need / Not Here / Dead tooltip for whatever buff a button is
-- currently set to. Re-callable so a scroll refreshes the open tooltip in place.
local function ShowBuffTooltip(btn)
    local bb = ACTIVE_BUFFS and ACTIVE_BUFFS[btn.buffIndex]
    if not bb then return end
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    GameTooltip:SetText(bb.name or bb.group or "Buff", 1, 1, 1)
    local have, need, range, dead = {}, {}, {}, {}
    BuildBuffStatus(bb, have, need, range, dead)
    GameTooltip:AddLine(PallyPower_Have    .. table.concat(have,  ", "), 0.5, 1, 0.5)
    GameTooltip:AddLine(PallyPower_Need    .. table.concat(need,  ", "), 1, 0.5, 0.5)
    GameTooltip:AddLine(PallyPower_NotHere .. table.concat(range, ", "), 0.5, 0.5, 1)
    GameTooltip:AddLine(PallyPower_Dead    .. table.concat(dead,  ", "), 1, 0, 0)
    GameTooltip:AddLine(" ", 1, 1, 1)
    if ACTIVE_BUFFS and table.getn(ACTIVE_BUFFS) > 1 then
        GameTooltip:AddLine("Scroll: switch buff", 0.6, 0.8, 1)
    end
    GameTooltip:AddLine("Left-click: buff / renew next member", 0.7, 0.7, 0.7)
    if bb.group then
        GameTooltip:AddLine("Right-click: " .. bb.group .. " on their group", 0.7, 0.7, 0.7)
    end
    GameTooltip:Show()
end

-- Point a button at buff index `idx` and refresh its icon.
local function SetButtonBuff(btn, idx)
    btn.buffIndex = idx
    local b = ACTIVE_BUFFS[idx]
    local iconName = (b.icons and b.icons[1]) or "INV_Misc_QuestionMark"
    btn.icon:SetTexture("Interface\\Icons\\" .. iconName)
end

-- Mouse-wheel: cycle a button through the class's usable buffs (dir +1/-1),
-- skipping unlearned spells and wrapping. The count, timer, button color and
-- the Have/Need/Not Here/Dead tooltip all follow automatically because they key
-- off the button's buffIndex (the scan already tracks every buff).
local function CycleButtonBuff(btn, dir)
    if not ACTIVE_BUFFS then return end
    local n = table.getn(ACTIVE_BUFFS)
    if n <= 1 then return end
    local i = btn.buffIndex or 1
    local tries = 0
    repeat
        i = i + dir
        if i > n then i = 1 elseif i < 1 then i = n end
        tries = tries + 1
    until BuffIsUsable(ACTIVE_BUFFS[i]) or tries >= n
    SetButtonBuff(btn, i)
    if UpdateDisplays then UpdateDisplays() end   -- refresh count/timer at once
    ShowBuffTooltip(btn)                           -- refresh the open tooltip
end

local function LayoutUtilityRow(topY)
    for _, ub in pairs(utilButtons) do ub:Hide() end
    if not ACTIVE_UTILITY then return 0 end

    -- only utilities whose spell the player knows
    local usable = {}
    for i = 1, table.getn(ACTIVE_UTILITY) do
        if KNOWN[ACTIVE_UTILITY[i].name] then table.insert(usable, i) end
    end
    if table.getn(usable) == 0 then return 0 end

    local x = PAD
    for slot = 1, table.getn(usable) do
        local uidx = usable[slot]
        local u = ACTIVE_UTILITY[uidx]
        local ub = utilButtons[slot]
        if not ub then
            ub = CreateFrame("Button", "RallyPowerCP_Util" .. slot, bar)
            ub:SetWidth(UTIL_SIZE); ub:SetHeight(UTIL_SIZE)
            ub:RegisterForClicks("LeftButtonUp")
            local ic = ub:CreateTexture(nil, "ARTWORK")
            ic:SetAllPoints(ub)
            ub.icon = ic
            ub:SetScript("OnClick", UtilityOnClick)
            ub:SetScript("OnEnter", function()
                local uu = ACTIVE_UTILITY[this.utilIndex]
                GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                GameTooltip:SetText(uu.name, 1, 1, 1)
                GameTooltip:AddLine("Click: cast on " .. (uu.tip or "target"), 0.8, 0.8, 0.8)
                GameTooltip:Show()
            end)
            ub:SetScript("OnLeave", function() GameTooltip:Hide() end)
            utilButtons[slot] = ub
        end
        ub.utilIndex = uidx
        local tex = GetSpellIconByName(u.name) or ("Interface\\Icons\\" .. (u.icon or "INV_Misc_QuestionMark"))
        ub.icon:SetTexture(tex)
        ub:ClearAllPoints()
        ub:SetPoint("TOPLEFT", bar, "TOPLEFT", x, topY)
        ub:Show()
        x = x + UTIL_SIZE + UTIL_GAP
    end
    return UTIL_ROW_H
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

    -- Hide all old buff buttons first.
    for _, btn in pairs(buttons) do btn:Hide() end

    -- Top-row utility buttons (e.g. Priest PW: Shield / Fear Ward).
    local topY = -18
    local utilH = LayoutUtilityRow(topY)
    local y = topY - utilH

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
            btn:EnableMouseWheel(true)
            btn:SetScript("OnMouseWheel", function()
                CycleButtonBuff(this, (arg1 and arg1 > 0) and 1 or -1)
            end)
            btn:SetScript("OnEnter", function() ShowBuffTooltip(this) end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

            buttons[slot] = btn
        end

        SetButtonBuff(btn, buffIndex)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", bar, "TOPLEFT", PAD, y)
        btn:Show()
        y = y - ROW_H
        shown = shown + 1
    end

    -- Size the bar to fit the utility row and the buff rows.
    local utilWidth = 0
    if ACTIVE_UTILITY and utilH > 0 then
        local nUtil = 0
        for i = 1, table.getn(ACTIVE_UTILITY) do
            if KNOWN[ACTIVE_UTILITY[i].name] then nUtil = nUtil + 1 end
        end
        utilWidth = PAD + nUtil * (UTIL_SIZE + UTIL_GAP) - UTIL_GAP + PAD
    end
    bar:SetWidth(math.max(BAR_W, utilWidth))
    bar:SetHeight(18 + utilH + shown * ROW_H + 6)
    if shown == 0 and utilH == 0 then bar:Hide() end
end

--=============================================================================
-- CHEAP PER-SECOND TICK: countdown text + expiry warning. Pure arithmetic on
-- stored deadlines — zero UnitBuff/API calls — so it can run every second.
--=============================================================================
-- (forward-declared above) Cheap per-second tick: countdown text + warning.
function UpdateDisplays()
    if not bar or not ACTIVE_BUFFS then return end
    local now = GetTime()
    for slot = 1, table.getn(buttons) do
        local btn = buttons[slot]
        if btn and btn:IsShown() then
            local i = btn.buffIndex
            local need = NEEDCOUNT[i] or 0
            if need > 0 then
                btn.bg:SetTexture(0.8, 0.1, 0.1, 0.6)   -- red: someone needs it
                btn.count:SetText(need)
                btn.icon:SetVertexColor(1, 1, 1)
            else
                btn.bg:SetTexture(0.1, 0.6, 0.1, 0.25)  -- green/faded: all covered
                btn.count:SetText("")
                btn.icon:SetVertexColor(0.55, 0.55, 0.55)
            end
            local dl = minDeadline[i]
            local mr = dl and (dl - now) or nil
            if mr and mr > 0 then
                local m = math.floor(mr / 60)
                local s = math.floor(mr - m * 60)
                btn.timer:SetText(string.format("%d:%02d", m, s))
                if mr <= WARN_TIME then
                    btn.timer:SetTextColor(1, 0.25, 0.25)   -- red: about to expire
                    if not warned[i] then
                        warned[i] = true
                        PlaySoundFile("Interface\\Addons\\RallyPowerCP\\Sounds\\ding.mp3")
                        local b = ACTIVE_BUFFS[i]
                        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00RallyPowerCP:|r "
                            .. (b.name or b.group) .. " is about to expire!")
                    end
                else
                    btn.timer:SetTextColor(0.9, 0.9, 0.9)
                    warned[i] = nil   -- re-armed: it was refreshed
                end
            else
                btn.timer:SetText("")
                if dl then
                    minDeadline[i] = nil
                    auraDirty = true   -- a deadline just lapsed: verify coverage
                end
            end
        end
    end
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

    for i = 1, table.getn(ACTIVE_BUFFS) do NEEDCOUNT[i] = 0; minDeadline[i] = nil end

    local now = GetTime()
    for r = 1, count do
        local unit = roster[r]
        if UnitIsBuffable(unit) then
            local isPet = (string.find(unit, "pet") ~= nil)
            local uname = UnitName(unit)
            CollectUnitBuffs(unit)              -- ONE buff-list read per unit
            local isPlayer = UnitIsUnit(unit, "player")
            for i = 1, table.getn(ACTIVE_BUFFS) do
                local b = ACTIVE_BUFFS[i]
                if BuffIsUsable(b) and (not isPet or b.pet) then
                    if not HasCollected(b) then
                        NEEDCOUNT[i] = NEEDCOUNT[i] + 1
                        -- buff is gone: drop any stale recorded timer
                        if uname and expiry[uname] then
                            expiry[uname][b.name or b.group] = nil
                        end
                    else
                        -- buff present: compute its absolute deadline
                        local dl = nil
                        if isPlayer then
                            local left = PlayerBuffTimeLeft(b)   -- exact, via API
                            if left then dl = now + left end
                        elseif uname and expiry[uname] then
                            dl = expiry[uname][b.name or b.group]
                            if dl and dl <= now then
                                expiry[uname][b.name or b.group] = nil
                                dl = nil
                            end
                        end
                        if dl and (not minDeadline[i] or dl < minDeadline[i]) then
                            minDeadline[i] = dl
                        end
                    end
                end
            end
        end
    end

    UpdateDisplays()
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
    ACTIVE_UTILITY = RallyPowerCP_ClassUtility[PLAYER_CLASS]

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
            auraDirty = true
        end
    elseif PLAYER_CLASS and PLAYER_CLASS ~= "PALADIN" then
        auraDirty = true   -- roster/aura changed: full rescan on the next tick
    end
end)

f:SetScript("OnUpdate", function()
    if not ACTIVE_BUFFS then return end
    local dt = arg1 or 0
    lastScan = lastScan + dt
    sinceFullScan = sinceFullScan + dt
    if lastScan >= SCAN_INTERVAL then
        lastScan = 0
        -- Full roster scans only when something changed (or as a slow safety
        -- net); otherwise just the zero-API-call countdown tick.
        if auraDirty or sinceFullScan >= FULL_SCAN_FALLBACK then
            auraDirty = false
            sinceFullScan = 0
            ScanRoster()
        else
            UpdateDisplays()
        end
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
