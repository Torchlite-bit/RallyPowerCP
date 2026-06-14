--=============================================================================
-- RallyPowerCP_Core.lua
-- Class-independent engine for RallyPowerCP's all-class buff bar.
-- (Turtle WoW 1.18.1 / 1.12 client).  Author: Subtilizer (Torchlite)
--
-- ARCHITECTURE (AutoRota-style)
--   This file is the engine. It knows nothing about specific classes. Each
--   Classes\Class_<Name>.lua registers itself via RallyPowerCP:NewClass(token)
--   and supplies the DATA (which buffs, which utility spells). On login the core
--   picks the module matching the player's class and drives everything from it.
--
-- WHAT THE ENGINE DOES
--   * PALADIN  -> stays dormant. The original PallyPower grid owns that UI, so
--                 the Paladin experience is 100% unchanged.
--   * Any class with a registered module -> a movable, PallyPower-styled bar:
--       - one button per group buff; red+count = members missing it, faded =
--         covered; a countdown timer and a Have/Need/Not Here/Dead tooltip.
--       - left-click buffs/renews the next member; right-click casts the group
--         version; scroll the wheel to switch which buff a button tracks.
--       - optional top-row utility buttons (e.g. Priest PW: Shield / Fear Ward).
--       - an expiry "ding", a Smart Buff key binding, and minimap icon skins.
--
-- HOW BUFFS ARE DETECTED (important on the 1.12 client)
--   You cannot read another player's buff *names* on 1.12 - UnitBuff() returns
--   only a texture path. So, exactly like PallyPower, buffs are matched by icon
--   texture. Each buff entry lists the icon basename(s) its applied aura uses.
--
-- ADDING A CLASS
--   Copy an existing Classes\Class_<Name>.lua, change the token and the data,
--   and list the new file in RallyPowerCP.toc. Buff entry fields:
--     name      = exact single-target spell name (cast + spellbook check)
--     group     = exact group/greater spell name (optional, right-click cast)
--     icons     = { "IconBaseName", ... } applied-aura icon basename(s)
--     pet       = true to also track the buff on pets (optional)
--     dur/gdur  = single/group buff duration in seconds (drives the timer)
--     selfcast  = true for shouts/auras cast on yourself that buff nearby party
--                 (e.g. Battle Shout): a click just casts it, no per-member aim
--=============================================================================

RallyPowerCP_Settings = RallyPowerCP_Settings or {}

--=============================================================================
-- RallyPowerCP class-module registry  (AutoRota-style).
-- The core below is class-independent. Each Classes\Class_<Name>.lua registers
-- itself via RallyPowerCP:NewClass("<TOKEN>") and fills in .buffs (and optionally
-- .utility). On login the core selects the module matching the player's class
-- and drives the bar entirely from its data. __index inheritance means a class
-- module can call shared core methods as self:Something() if it ever needs
-- custom behaviour; today the modules are pure data.
--=============================================================================
RallyPowerCP = RallyPowerCP or { classes = {}, active = nil }

function RallyPowerCP:NewClass(token)
    local m = setmetatable({ classToken = token, buffs = {}, utility = nil },
                           { __index = self })
    self.classes[token] = m
    return m
end

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
local shownIndex                 -- which buff the single class button currently shows
local lastCast = 0               -- throttle guard: GetTime() of the last cast
local THROTTLE = 1.5             -- seconds a click is ignored after casting (= GCD)
local FOUR_MIN = 240             -- right-click won't overwrite a buff with this much left
local smartRoster = {}           -- scratch for the smart-auto-buff scan
local inCombat = false           -- tracked via PLAYER_REGEN_DISABLED/ENABLED (1.12-safe)

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
-- Single scrollable class row (PallyPower-style): icon on the left, big timer
-- on the right, on a coloured status bar.
local ROW_W      = 190
local ROW_HEIGHT = 40
local ROW_ICON   = 34
local ROW_GAP    = 4

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
            if b.selfcast then
                CastSpellByName(b.name)
                RecordGroupExpiry("player", b, b.dur)
                AnnounceBuff(b.name, "player", false)
                auraDirty = true; lastScan = SCAN_INTERVAL
                return
            end
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

-- Smart auto-buff target (right-click): the single most-needy member of the
-- raid for buff b. A member MISSING the buff is top priority; otherwise the one
-- with the least time left, but only if under the 4-minute reagent-saving floor.
-- Members we have no timer for (someone else buffed them) count as covered,
-- since the 1.12 client can't tell us how long their buff has left.
local function FindSmartBuffTarget(b)
    local count = BuildRoster(smartRoster, b.pet and true or false)
    local lowU, lowRem
    for r = 1, count do
        local u = smartRoster[r]
        if UnitIsBuffable(u) and UnitIsVisible(u) then
            if not UnitHasBuff(u, b) then
                return u                      -- missing it: cast now
            else
                local nm = UnitName(u)
                local dl = nm and expiry[nm] and expiry[nm][b.name or b.group]
                if dl then
                    local rem = dl - GetTime()
                    if rem < FOUR_MIN and (not lowRem or rem < lowRem) then
                        lowRem = rem; lowU = u
                    end
                end
            end
        end
    end
    return lowU
end

-- Throttle guard: record the cast time and spin the button's cooldown swirl so
-- it's visually obvious you can't usefully click again until the GCD is up.
local function StartThrottle(btn)
    lastCast = GetTime()
    if btn and btn.dim then btn.dim:Show() end
end

local function ButtonOnClick()
    -- arg1 holds the mouse button on the 1.12 client
    local idx = this.buffIndex
    local b = ACTIVE_BUFFS[idx]
    if not b then return end

    -- Throttle guard: ignore a click that lands within the GCD of the last cast,
    -- so a panicked double-click can't burn a second set of reagents.
    if GetTime() - lastCast < THROTTLE then return end

    -- Self-cast shouts/auras (e.g. Battle Shout): one cast refreshes nearby party.
    if b.selfcast then
        if KNOWN[b.name] then
            CastSpellByName(b.name)
            RecordGroupExpiry("player", b, b.dur)
            AnnounceBuff(b.name, "player", false)
            StartThrottle(this)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cffffff00RallyPowerCP:|r You haven't learned " .. b.name .. ".")
        end
        auraDirty = true; lastScan = SCAN_INTERVAL
        return
    end

    if arg1 == "RightButton" then
        -- Smart auto-buff: top off the single most-needy member with the normal
        -- (single-target) version. Disabled in combat; respects the 4-min floor.
        if inCombat then
            DEFAULT_CHAT_FRAME:AddMessage("|cffffff00RallyPowerCP:|r auto-buff is disabled in combat.")
            return
        end
        local unit = FindSmartBuffTarget(b)
        if not unit then
            DEFAULT_CHAT_FRAME:AddMessage("|cffffff00RallyPowerCP:|r "
                .. (b.name or b.group) .. ": everyone in range is covered (4+ min left).")
            return
        end
        if b.name and KNOWN[b.name] then
            CastBuffOn(b.name, unit, b, b.dur, false); StartThrottle(this)
        elseif b.group and KNOWN[b.group] then
            CastBuffOn(b.group, unit, b, b.gdur, true); StartThrottle(this)
        end
        auraDirty = true; lastScan = SCAN_INTERVAL
        return
    end

    -- Left-click: cast the GROUP/raid-wide version, covering a whole subgroup at
    -- once (renew-capable: tops off the next subgroup once everyone is covered).
    local unit = FindUnitToBuff(b, true)
    if not unit then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00RallyPowerCP:|r "
            .. (b.name or b.group) .. ": no group members in range.")
        return
    end
    if b.group and KNOWN[b.group] then
        CastBuffOn(b.group, unit, b, b.gdur, true); StartThrottle(this)
    elseif b.name and KNOWN[b.name] then
        CastBuffOn(b.name, unit, b, b.dur, false); StartThrottle(this)
    end
    auraDirty = true; lastScan = SCAN_INTERVAL
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
    if bb.selfcast then
        GameTooltip:AddLine("Click: cast (refreshes nearby party)", 0.7, 0.7, 0.7)
    else
        if bb.group then
            GameTooltip:AddLine("Left-click: " .. bb.group .. " (covers a group)", 0.7, 0.7, 0.7)
        else
            GameTooltip:AddLine("Left-click: buff / renew next member", 0.7, 0.7, 0.7)
        end
        GameTooltip:AddLine("Right-click: smart top-off (out of combat)", 0.7, 0.7, 0.7)
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
    shownIndex = i                                 -- remember across relayouts
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
    -- Usable buffs (known spells only).
    local visible = {}
    if ACTIVE_BUFFS then
        for i = 1, table.getn(ACTIVE_BUFFS) do
            if BuffIsUsable(ACTIVE_BUFFS[i]) then table.insert(visible, i) end
        end
    end

    -- Hide everything first; we render ONE scrollable class row (scroll to switch
    -- which buff it shows) rather than all buffs at once.
    for _, btn in pairs(buttons) do btn:Hide() end

    -- Top-row utility buttons (e.g. Priest PW: Shield / Fear Ward).
    local topY = -18
    local utilH = LayoutUtilityRow(topY)
    local y = topY - utilH

    local shown = 0
    if table.getn(visible) > 0 then
        -- Which buff to show: the remembered one if still usable, else the first.
        -- shownIndex persists across the frequent SPELLS_CHANGED relayouts and is
        -- reset on a class change in Activate().
        local okRemembered = shownIndex and ACTIVE_BUFFS[shownIndex]
            and BuffIsUsable(ACTIVE_BUFFS[shownIndex])
        if not okRemembered then shownIndex = visible[1] end

        local btn = buttons[1]
        if not btn then
            btn = CreateFrame("Button", "RallyPowerCP_BarBtn1", bar)
            btn:SetWidth(ROW_W); btn:SetHeight(ROW_HEIGHT)
            btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

            local bg = btn:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints(btn)
            bg:SetTexture(0.1, 0.6, 0.1, 0.25)
            btn.bg = bg

            local icon = btn:CreateTexture(nil, "ARTWORK")
            icon:SetWidth(ROW_ICON); icon:SetHeight(ROW_ICON)
            icon:SetPoint("LEFT", btn, "LEFT", 4, 0)
            btn.icon = icon

            -- throttle indicator: a simple dark overlay shown briefly after a
            -- cast (no Cooldown frame template, which isn't reliable on 1.12).
            local dim = btn:CreateTexture(nil, "OVERLAY")
            dim:SetAllPoints(icon)
            dim:SetTexture(0, 0, 0, 0.55)
            dim:Hide()
            btn.dim = dim

            local count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
            count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
            btn.count = count

            local timer = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            timer:SetPoint("RIGHT", btn, "RIGHT", -10, 0)
            timer:SetJustifyH("RIGHT")
            btn.timer = timer

            btn:SetScript("OnClick", ButtonOnClick)
            btn:EnableMouseWheel(true)
            btn:SetScript("OnMouseWheel", function()
                CycleButtonBuff(this, (arg1 and arg1 > 0) and 1 or -1)
            end)
            btn:SetScript("OnEnter", function() ShowBuffTooltip(this) end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

            buttons[1] = btn
        end

        SetButtonBuff(btn, shownIndex)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", bar, "TOPLEFT", PAD, y)
        btn:Show()
        y = y - (ROW_HEIGHT + ROW_GAP)
        shown = 1
    end

    -- Size the bar to fit the utility row and the single class row.
    local utilWidth = 0
    if ACTIVE_UTILITY and utilH > 0 then
        local nUtil = 0
        for i = 1, table.getn(ACTIVE_UTILITY) do
            if KNOWN[ACTIVE_UTILITY[i].name] then nUtil = nUtil + 1 end
        end
        utilWidth = PAD + nUtil * (UTIL_SIZE + UTIL_GAP) - UTIL_GAP + PAD
    end
    local rowWidth = (shown > 0) and (PAD + ROW_W + PAD) or 0
    bar:SetWidth(math.max(math.max(BAR_W, utilWidth), rowWidth))
    bar:SetHeight(18 + utilH + shown * (ROW_HEIGHT + ROW_GAP) + 6)
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

    -- (1) Expiry-warning pass over EVERY buff, so a buff you're not currently
    -- showing on the single row still dings and self-corrects on the tick.
    for i = 1, table.getn(ACTIVE_BUFFS) do
        local dl = minDeadline[i]
        if dl then
            local mr = dl - now
            if mr > 0 then
                if mr <= WARN_TIME then
                    if not warned[i] then
                        warned[i] = true
                        PlaySoundFile("Interface\\Addons\\RallyPowerCP\\Sounds\\ding.mp3")
                        local b = ACTIVE_BUFFS[i]
                        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00RallyPowerCP:|r "
                            .. (b.name or b.group) .. " is about to expire!")
                    end
                else
                    warned[i] = nil   -- re-armed: it was refreshed past the warning
                end
            else
                minDeadline[i] = nil
                auraDirty = true      -- a deadline just lapsed: verify coverage
            end
        end
    end

    -- (2) Update the single visible class row from its current buff.
    for slot = 1, table.getn(buttons) do
        local btn = buttons[slot]
        if btn and btn:IsShown() then
            local i = btn.buffIndex
            local need = NEEDCOUNT[i] or 0
            if need > 0 then
                btn.bg:SetTexture(0.55, 0.1, 0.1, 0.5)   -- red bar: someone needs it
                btn.count:SetText(need)
                btn.icon:SetVertexColor(1, 1, 1)
            else
                btn.bg:SetTexture(0.12, 0.5, 0.12, 0.5)  -- green bar: all covered
                btn.count:SetText("")
                btn.icon:SetVertexColor(1, 1, 1)
            end
            local dl = minDeadline[i]
            local mr = dl and (dl - now) or nil
            if mr and mr > 0 then
                local m = math.floor(mr / 60)
                local s = math.floor(mr - m * 60)
                btn.timer:SetText(string.format("%d:%02d", m, s))
                if mr <= WARN_TIME then
                    btn.timer:SetTextColor(1, 0.4, 0.4)    -- red: about to expire
                else
                    btn.timer:SetTextColor(0.9, 1.0, 0.5)  -- pale gold, like the Pally bar
                end
            else
                btn.timer:SetText("")
            end
            -- clear the throttle dim once the global cooldown window has passed
            if btn.dim and (now - lastCast) >= THROTTLE then btn.dim:Hide() end
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

    RallyPowerCP.active = RallyPowerCP.classes[PLAYER_CLASS]
    ACTIVE_BUFFS   = RallyPowerCP.active and RallyPowerCP.active.buffs
    ACTIVE_UTILITY = RallyPowerCP.active and RallyPowerCP.active.utility

    -- Empty/undefined class table -> nothing to show (e.g. Rogue, or any class
    -- with no registered module yet).
    if not ACTIVE_BUFFS or table.getn(ACTIVE_BUFFS) == 0 then
        ACTIVE_BUFFS = nil
        if bar then bar:Hide() end
        return
    end

    BuildIconLookups()
    RebuildKnownSpells()
    shownIndex = nil          -- start on the first usable buff for this class
    -- Guard the bar build: if anything errors on a custom client, report it in
    -- chat instead of letting the bar silently fail to appear.
    local ok, err = pcall(function()
        CreateBar()
        LayoutButtons()
        if RallyPowerCP_Settings.hidden then bar:Hide() else bar:Show() end
        ScanRoster()
    end)
    if not ok then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff5555RallyPowerCP error:|r " .. tostring(err)
            .. " |cffaaaaaa(please report this)|r")
    end
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
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")

f:SetScript("OnEvent", function()
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        Activate()
        RallyPowerCP_ApplyMinimapSkin()   -- restore the saved icon skin
    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
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
