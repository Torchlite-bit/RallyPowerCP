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
--   * PALADIN  -> uses the original PallyPower bar/grid, now enhanced with the
--                 hover player pop-out (RallyPowerCP_Popout.lua). No separate bar.
--   * Any class with a registered module -> a movable, PallyPower-styled bar:
--       - one button per group buff; red+count = members missing it, faded =
--         covered; a countdown timer and a Have/Need/Not Here/Dead tooltip.
--       - left-click buffs/renews the next member; right-click casts the group
--         version; scroll the wheel to switch which buff a button tracks.
--       - optional top-row utility buttons (e.g. Priest PW: Shield / Fear Ward).
--       - an expiry "ding", a Smart Buff key binding, and minimap icon skins.
--
-- HOW BUFFS ARE DETECTED
--   Turtle 1.18.1 runs SuperWoW, which makes UnitBuff() *also* return the aura's
--   spell id. When present we match by spell id (exact - no icon collisions).
--   SuperWoW is required, but we fall back gracefully: if it is missing we match
--   by icon texture exactly like PallyPower/1.12 (UnitBuff returns only a texture
--   there). Each buff entry lists both its spell id(s) and its icon basename(s),
--   so the same data drives either path.
--
-- ADDING A CLASS
--   Copy an existing Classes\Class_<Name>.lua, change the token and the data,
--   and list the new file in RallyPowerCP.toc. Buff entry fields:
--     name      = exact single-target spell name (cast + spellbook check)
--     group     = exact group/greater spell name (optional, right-click cast)
--     ids       = { spellID, ... } applied-aura spell id(s)  [SuperWoW path]
--     icons     = { "IconBaseName", ... } applied-aura icon basename(s) [fallback]
--     pet       = true to also track the buff on pets (optional)
--     dur/gdur  = single/group buff duration in seconds (drives the timer)
--     selfcast  = true for shouts/auras cast on yourself that buff nearby party
--                 (e.g. Battle Shout): a click just casts it, no per-member aim
--=============================================================================

RallyPowerCP_Settings = RallyPowerCP_Settings or {}
RallyPowerCP_Roles    = RallyPowerCP_Roles or {}   -- [playerName] = "MT" | "MA" (local, per character)

-- SuperWoW capability flag. When true we use spell-id buff detection and direct
-- CastSpellByName(spell, unit) casting; when false we keep the icon-match +
-- CVar-target fallback so the addon still loads on a bare 1.12 client.
local HAS_SUPERWOW = (SUPERWOW_VERSION ~= nil)

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

-- Class-grouped grid state (Option A). The bar shows one row per class present
-- in the group; each row tracks the globally-selected buff (scroll to change it)
-- and breaks coverage down by class.
local CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local CLASS_SET = {}
for _, c in pairs(CLASS_ORDER) do CLASS_SET[c] = true end
local classUnits    = {}         -- [classToken] = { unitIDs of that class }
local presentClasses = {}        -- ordered list of class tokens with >=1 member
local rowNeed       = {}         -- [classToken][buffIndex] = members of that class missing it
local rowDeadline   = {}         -- [classToken][buffIndex] = earliest absolute expiry for that class
local classCursor   = {}         -- [classToken] = round-robin index for right-click cycling
local classRows     = {}         -- [classToken] = the row Button frame
local roster        = {}         -- flat unit list, reused by presence + scan
local lastPresentSig             -- signature of presentClasses, to detect changes
local popout                     -- the hover pop-out side panel (created lazily)
local popoutRows = {}            -- pooled per-player row buttons inside the panel
local popoutClass                -- class token the pop-out is currently showing
local popoutRow                  -- the class row the pop-out is anchored to

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

-- Pre-lowercase the icon sets once so scanning is cheap, and index the spell-id
-- sets for the SuperWoW path. Also build an icon -> buffs reverse map so we can
-- LEARN each buff's real aura id from the icon seed at runtime (SuperWoW gives
-- us the id alongside the icon), making detection exact without hard-coding ids
-- that might differ on Turtle.
local iconToBuffs = {}
local function BuildIconLookups()
    for k in pairs(iconToBuffs) do iconToBuffs[k] = nil end
    if not ACTIVE_BUFFS then return end
    for _, b in pairs(ACTIVE_BUFFS) do
        b._iconset = {}
        if b.icons then
            for _, ic in pairs(b.icons) do
                local lic = string.lower(ic)
                b._iconset[lic] = true
                iconToBuffs[lic] = iconToBuffs[lic] or {}
                table.insert(iconToBuffs[lic], b)
            end
        end
        b._idset = {}
        if b.ids then
            for _, id in pairs(b.ids) do
                b._idset[id] = true
            end
        end
    end
end

-- Learn: when SuperWoW hands us an aura's icon AND id, record that id onto every
-- buff that lists the icon, so subsequent matches are exact by id.
local function LearnAuraID(iconBase, id)
    if not id then return end
    local buffs = iconToBuffs[iconBase]
    if not buffs then return end
    for i = 1, table.getn(buffs) do
        buffs[i]._idset[id] = true
    end
end

-- Does this unit currently have buff b?
-- SuperWoW: UnitBuff(unit, j) additionally returns the aura's spell id, so we
-- match by id (exact). Fallback: match by icon texture, as on bare 1.12.
-- Used for SINGLE-unit checks (e.g. the click targeter). The roster scan uses
-- CollectUnitBuffs/HasCollected below instead, which reads each unit's buff
-- list only ONCE per scan no matter how many buffs we track.
local function UnitHasBuff(unit, b)
    local j = 1
    while true do
        local tex, _, id = UnitBuff(unit, j, true)   -- SuperWoW adds id as a return
        if not tex then
            tex = UnitBuff(unit, j)                   -- fallback signature, just in case
        end
        if not tex then break end
        local base = IconBase(tex)
        if HAS_SUPERWOW and id then
            LearnAuraID(base, id)
            if b._idset[id] then return true end
        end
        if b._iconset[base] then return true end
        j = j + 1
        if j > 40 then break end
    end
    return false
end

-- Single pass over a unit's buffs: fill `presentIcons` (icon path) with what's
-- present, and `presentIDs` (spell id) under SuperWoW.
local presentIcons = {}
local presentIDs = {}
local function CollectUnitBuffs(unit)
    for k in pairs(presentIcons) do presentIcons[k] = nil end
    for k in pairs(presentIDs) do presentIDs[k] = nil end
    local j = 1
    while j <= 40 do
        local tex, _, id = UnitBuff(unit, j, true)
        if not tex then tex = UnitBuff(unit, j) end
        if not tex then break end
        local base = IconBase(tex)
        presentIcons[base] = true
        if id then presentIDs[id] = true; LearnAuraID(base, id) end
        j = j + 1
    end
end

-- After CollectUnitBuffs(unit): does the collected set contain buff b?
local function HasCollected(b)
    if HAS_SUPERWOW then
        for id in pairs(b._idset) do
            if presentIDs[id] then return true end
        end
        -- fall through to icon match if this buff's id hasn't been learned yet
    end
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

-- English class token for a unit ("WARRIOR", "PRIEST", ...). Used to bucket the
-- roster by class for the grid. (Pets aren't bucketed; the grid is players-only.)
local function UnitClassToken(unit)
    local _, c = UnitClass(unit)
    return c
end

-- Bucket the player roster by class and build the ordered present-class list,
-- in CLASS_ORDER. Cheap: one UnitClass call per member, no buff reads. This is
-- what drives which rows the grid shows and which members each row buffs.
local function BuildClassPresence()
    for k in pairs(classUnits) do classUnits[k] = nil end
    local count = BuildRoster(roster, false)        -- players only
    for r = 1, count do
        local unit = roster[r]
        if UnitExists(unit) then
            local ct = UnitClassToken(unit)
            if ct and CLASS_SET[ct] then
                if not classUnits[ct] then classUnits[ct] = {} end
                table.insert(classUnits[ct], unit)
            end
        end
    end
    for k = table.getn(presentClasses), 1, -1 do presentClasses[k] = nil end
    local n = 0
    for ci = 1, table.getn(CLASS_ORDER) do
        local ct = CLASS_ORDER[ci]
        if classUnits[ct] and table.getn(classUnits[ct]) > 0 then
            n = n + 1; presentClasses[n] = ct
        end
    end
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
-- Single scrollable class row, sized to EXACTLY match PallyPower's buff-bar
-- button (100x36 with two 26x26 icons and a tooltip-textured backdrop coloured
-- by status), so it looks identical to the Paladin row.
local ROW_W      = 100
local ROW_HEIGHT = 36
local ROW_ICON   = 26
local ROW_GAP    = 0
local ROW_ALPHA  = 0.8
local ROW_BACKDROP = {
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 8, edgeSize = 8,
    insets = { left = 2, right = 2, top = 3, bottom = 2 },
}

-- Hover pop-out side panel: a stack of colour-coded player bars (PallyPower
-- player-list style), expanding to the LEFT of the class rows.
local POP_W       = 160          -- panel width
local POP_BAR_H   = 26           -- per-player bar height
local POP_BAR_GAP = 2            -- gap between player bars
local POP_PAD     = 4            -- inner padding

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

-- Low-level "cast `spell` on `unit`" primitive, returns true if it landed.
--   SuperWoW: CastSpellByName(spell, unit) casts straight at the unit without
--             ever touching the player's target. One call, nothing to restore.
--   Fallback (bare 1.12): PallyPower's exact flow - disable autoSelfCast, clear
--             the target so the targeting cursor is guaranteed to come up, direct
--             it with SpellTargetUnit, then restore the target and the CVar.
local function RawCastOnUnit(spell, unit)
    if not spell or not unit then return false end

    if HAS_SUPERWOW then
        CastSpellByName(spell, unit)
        return true
    end

    local restoreCVar = false
    if GetCVar("autoSelfCast") == "1" then
        restoreCVar = true
        SetCVar("autoSelfCast", "0")
    end

    -- If the unit IS our current friendly target, cast straight at them
    -- (clearing the target first would destroy the "target" unit reference).
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
    else
        landed = true            -- instant/self-target cast fired
    end
    if hadTarget then TargetLastTarget() end
    if restoreCVar then SetCVar("autoSelfCast", "1") end
    return landed
end

-- Cast a tracked buff on a unit and record its timer.
local function CastBuffOn(spell, unit, b, dur, isGroup)
    if not spell then return end
    if RawCastOnUnit(spell, unit) then
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

-- Reliable single-target cast with no timer tracking (utility spells).
local function CastSpellOnUnit(spell, unit)
    return RawCastOnUnit(spell, unit)
end

-- One-key smart buff (for the key binding): casts on the next group member
-- missing ANY of your tracked buffs — soonest-expiring buff types first.
-- Press it repeatedly to top off the whole group hands-free.
function RallyPowerCP_SmartBuff()
    if not ACTIVE_BUFFS then return end
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
local RefreshPopout              -- forward decl (defined in the pop-out section)

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

-- Helper: ensure shownIndex points at a usable buff (the globally-selected one).
local function EnsureShownBuff()
    if not ACTIVE_BUFFS then shownIndex = nil; return end
    if shownIndex and ACTIVE_BUFFS[shownIndex] and BuffIsUsable(ACTIVE_BUFFS[shownIndex]) then return end
    for i = 1, table.getn(ACTIVE_BUFFS) do
        if BuffIsUsable(ACTIVE_BUFFS[i]) then shownIndex = i; return end
    end
    shownIndex = nil
end

-- Per-class buff selection: each class row independently tracks one of the
-- player's buffs (scroll a row to change just that class's buff, PallyPower-style).
local rowBuff = {}               -- [classToken] = buff index shown/cast for that class

-- Return the usable buff index for class ct, defaulting to the first usable.
local function RowBuffIndex(ct)
    if not ACTIVE_BUFFS then return nil end
    local bi = rowBuff[ct]
    if bi and ACTIVE_BUFFS[bi] and BuffIsUsable(ACTIVE_BUFFS[bi]) then return bi end
    for i = 1, table.getn(ACTIVE_BUFFS) do
        if BuffIsUsable(ACTIVE_BUFFS[i]) then rowBuff[ct] = i; return i end
    end
    rowBuff[ct] = nil
    return nil
end

-- Scroll over a class row cycles that class's buff only (independent per class).
local function CycleRowBuff(ct, dir)
    if not ACTIVE_BUFFS then return end
    local nb = table.getn(ACTIVE_BUFFS)
    if nb <= 1 then return end
    local i = RowBuffIndex(ct) or 1
    local tries = 0
    repeat
        i = i + dir
        if i > nb then i = 1 elseif i < 1 then i = nb end
        tries = tries + 1
    until BuffIsUsable(ACTIVE_BUFFS[i]) or tries >= nb
    rowBuff[ct] = i
    if UpdateDisplays then UpdateDisplays() end
    if RefreshPopout and popout and popout:IsShown() and popoutClass == ct then RefreshPopout() end
end

-- Local per-player role tags (MT = main tank, MA = main assist), cycled with
-- CTRL+click on a pop-out player bar. Local only for now: not synced to other
-- RallyPowerCP users and not yet wired into smart targeting.
local ROLE_NEXT = { [""] = "MT", MT = "MA", MA = "" }
local function CycleRole(name)
    if not name then return end
    local nxt = ROLE_NEXT[RallyPowerCP_Roles[name] or ""] or ""
    if nxt == "" then RallyPowerCP_Roles[name] = nil else RallyPowerCP_Roles[name] = nxt end
end
local function RoleLabel(name)
    return (name and RallyPowerCP_Roles[name]) or "R"   -- unassigned shows an "R" slot
end
local function RoleColor(name)
    local r = name and RallyPowerCP_Roles[name]
    if r == "MT" then return 1, 0.82, 0          -- tank: gold
    elseif r == "MA" then return 0.4, 0.8, 1     -- assist: cyan
    else return 0.5, 1, 0.5 end                  -- unassigned: green (matches PallyPower)
end

-- Next member of class ct who needs buff b (renew=true also returns an already-
-- buffed member once everyone is covered, so a click can still refresh).
local function FindClassNeedy(ct, b, renew)
    local units = classUnits[ct]
    if not units then return nil end
    local cnt = table.getn(units)
    if cnt == 0 then return nil end
    local start = classCursor[ct] or 0
    local firstValid, firstIdx
    for step = 1, cnt do
        local idx = start + step
        while idx > cnt do idx = idx - cnt end
        local u = units[idx]
        if UnitIsBuffable(u) and UnitIsVisible(u) then
            if not UnitHasBuff(u, b) then
                classCursor[ct] = idx
                return u
            elseif renew and not firstValid then
                firstValid, firstIdx = u, idx
            end
        end
    end
    if renew and firstValid then classCursor[ct] = firstIdx; return firstValid end
    return nil
end

-- Smart top-off target within a class: missing first, else the lowest time left
-- (only under the 4-minute floor), using timers we recorded for our own casts.
local function FindClassSmartTarget(ct, b)
    local units = classUnits[ct]
    if not units then return nil end
    local lowU, lowRem
    for i = 1, table.getn(units) do
        local u = units[i]
        if UnitIsBuffable(u) and UnitIsVisible(u) then
            if not UnitHasBuff(u, b) then
                return u
            else
                local nm = UnitName(u)
                local dl = nm and expiry[nm] and expiry[nm][b.name or b.group]
                if dl then
                    local rem = dl - GetTime()
                    if rem < FOUR_MIN and (not lowRem or rem < lowRem) then lowRem = rem; lowU = u end
                end
            end
        end
    end
    return lowU
end

-- Scroll changes the globally-selected buff shown on every class row.
local function CycleBuff(dir)
    if not ACTIVE_BUFFS then return end
    local nb = table.getn(ACTIVE_BUFFS)
    if nb <= 1 then return end
    EnsureShownBuff()
    local i = shownIndex or 1
    local tries = 0
    repeat
        i = i + dir
        if i > nb then i = 1 elseif i < 1 then i = nb end
        tries = tries + 1
    until BuffIsUsable(ACTIVE_BUFFS[i]) or tries >= nb
    shownIndex = i
    if UpdateDisplays then UpdateDisplays() end
end

-- Tooltip for a class row: that class's members by Have/Need/Not Here/Dead.
local function ShowClassRowTooltip(row)
    local ct = row.classToken
    EnsureShownBuff()
    local b = shownIndex and ACTIVE_BUFFS[shownIndex]
    if not b then return end
    local clsName = string.upper(string.sub(ct, 1, 1)) .. string.lower(string.sub(ct, 2))
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(clsName .. "  -  " .. (b.name or b.group or "Buff"), 1, 1, 1)
    local have, need, range, dead = {}, {}, {}, {}
    local units = classUnits[ct] or {}
    for i = 1, table.getn(units) do
        local u = units[i]
        if UnitExists(u) and UnitIsConnected(u) then
            local nm = UnitName(u) or "?"
            if not UnitIsVisible(u) then table.insert(range, nm)
            elseif UnitIsDeadOrGhost(u) then
                if UnitHasBuff(u, b) then table.insert(have, nm) else table.insert(dead, nm) end
            elseif UnitHasBuff(u, b) then table.insert(have, nm)
            else table.insert(need, nm) end
        end
    end
    GameTooltip:AddLine(PallyPower_Have    .. table.concat(have,  ", "), 0.5, 1, 0.5)
    GameTooltip:AddLine(PallyPower_Need    .. table.concat(need,  ", "), 1, 0.5, 0.5)
    GameTooltip:AddLine(PallyPower_NotHere .. table.concat(range, ", "), 0.5, 0.5, 1)
    GameTooltip:AddLine(PallyPower_Dead    .. table.concat(dead,  ", "), 1, 0, 0)
    GameTooltip:AddLine(" ", 1, 1, 1)
    if table.getn(ACTIVE_BUFFS) > 1 then GameTooltip:AddLine("Scroll: switch buff", 0.6, 0.8, 1) end
    if b.group then GameTooltip:AddLine("Left-click: " .. b.group .. " on this class", 0.7, 0.7, 0.7) end
    GameTooltip:AddLine("Right-click: top off the next " .. clsName, 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

-- Click a class row: left = group version on this class, right = smart single
-- top-off within this class (combat-locked, 4-min floor).
local function ClassRowOnClick()
    local ct = this.classToken
    local bi = RowBuffIndex(ct)
    local b = bi and ACTIVE_BUFFS[bi]
    if not b then return end
    if GetTime() - lastCast < THROTTLE then return end

    if b.selfcast then
        if KNOWN[b.name] then
            CastSpellByName(b.name)
            RecordGroupExpiry("player", b, b.dur)
            AnnounceBuff(b.name, "player", false)
            StartThrottle(this)
        end
        auraDirty = true; lastScan = SCAN_INTERVAL
        return
    end

    if arg1 == "RightButton" then
        if inCombat then
            DEFAULT_CHAT_FRAME:AddMessage("|cffffff00RallyPowerCP:|r auto-buff is disabled in combat.")
            return
        end
        local unit = FindClassSmartTarget(ct, b)
        if not unit then
            DEFAULT_CHAT_FRAME:AddMessage("|cffffff00RallyPowerCP:|r " .. ct .. ": covered (4+ min left).")
            return
        end
        if b.name and KNOWN[b.name] then CastBuffOn(b.name, unit, b, b.dur, false); StartThrottle(this)
        elseif b.group and KNOWN[b.group] then CastBuffOn(b.group, unit, b, b.gdur, true); StartThrottle(this) end
        auraDirty = true; lastScan = SCAN_INTERVAL
        return
    end

    -- left-click: group version, covering this class's subgroup
    local unit = FindClassNeedy(ct, b, true)
    if not unit then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00RallyPowerCP:|r " .. ct .. ": no members in range.")
        return
    end
    if b.group and KNOWN[b.group] then CastBuffOn(b.group, unit, b, b.gdur, true); StartThrottle(this)
    elseif b.name and KNOWN[b.name] then CastBuffOn(b.name, unit, b, b.dur, false); StartThrottle(this) end
    auraDirty = true; lastScan = SCAN_INTERVAL
end

--=============================================================================
-- INTERACTIVE POP-OUT  (stage 2): hovering a class row opens a side panel that
-- lists every player in that class with their status colour and personal timer.
--   Left-click a player  : group version covering their subgroup (skipped if
--                           they already have it; disabled in combat).
--   Right-click a player : single-target on just that player (works in combat) —
--                           the "top off the one who missed it" action.
--=============================================================================

-- Cursor hit-test that works on the 1.12 client (scale-aware).
local function IsMouseOverFrame(frame)
    if not frame or not frame:IsVisible() then return false end
    local l = frame:GetLeft()
    if not l then return false end
    local b, w, h = frame:GetBottom(), frame:GetWidth(), frame:GetHeight()
    local scale = frame:GetEffectiveScale()
    local x, y = GetCursorPosition()
    x = x / scale; y = y / scale
    return x >= l and x <= l + w and y >= b and y <= b + h
end

local function HidePopout()
    if popout then popout:Hide() end
    popoutClass = nil; popoutRow = nil
end

-- Click a player row: left = group on their subgroup, right = single on them.
local function PopoutPlayerOnClick()
    local unit = this.unit
    if not unit or not UnitExists(unit) then return end
    if IsControlKeyDown() then                     -- CTRL+click: assign role (local)
        CycleRole(UnitName(unit))
        RefreshPopout()
        return
    end
    local bi = RowBuffIndex(popoutClass)
    local b = bi and ACTIVE_BUFFS[bi]
    if not b then return end
    if b.selfcast then return end                 -- shouts/auras have no per-player cast
    if GetTime() - lastCast < THROTTLE then return end

    if arg1 == "RightButton" then
        -- single-target on this player; permitted in combat (manual rebuff)
        if b.name and KNOWN[b.name] then
            CastBuffOn(b.name, unit, b, b.dur, false); StartThrottle(this)
        elseif b.group and KNOWN[b.group] then
            CastBuffOn(b.group, unit, b, b.gdur, true); StartThrottle(this)
        end
        auraDirty = true; lastScan = SCAN_INTERVAL
        return
    end

    -- left-click: group version covering this player's subgroup
    if inCombat then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00RallyPowerCP:|r group buffs are disabled in combat (right-click for a single buff).")
        return
    end
    -- smart prevention: don't waste a group cast on someone already buffed
    if UnitHasBuff(unit, b) then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00RallyPowerCP:|r " .. (UnitName(unit) or "?") .. " already has " .. (b.name or b.group) .. ".")
        return
    end
    if b.group and KNOWN[b.group] then
        CastBuffOn(b.group, unit, b, b.gdur, true); StartThrottle(this)
    elseif b.name and KNOWN[b.name] then
        CastBuffOn(b.name, unit, b, b.dur, false); StartThrottle(this)
    end
    auraDirty = true; lastScan = SCAN_INTERVAL
end

-- Refresh each visible player bar: status colour, buff icon, name, personal timer.
function RefreshPopout()
    if not popout or not popoutClass then return end
    local bi = RowBuffIndex(popoutClass)
    local b = bi and ACTIVE_BUFFS[bi]
    local units = classUnits[popoutClass] or {}
    local now = GetTime()
    local iconTex = b and b.icons and ("Interface\\Icons\\" .. (b.icons[1] or "INV_Misc_QuestionMark"))
    for i = 1, table.getn(popoutRows) do
        local pr = popoutRows[i]
        local unit = units[i]
        if unit and b and UnitExists(unit) then
            pr.unit = unit
            pr.name:SetText(UnitName(unit) or "?")
            if iconTex then pr.icon:SetTexture(iconTex) end
            local nm = UnitName(unit)
            pr.role:SetText(RoleLabel(nm))
            pr.role:SetTextColor(RoleColor(nm))
            local timerText = ""
            if not UnitIsVisible(unit) then
                pr:SetBackdropColor(0.3, 0.3, 0.9, ROW_ALPHA)      -- Not Here (blue)
            elseif UnitIsDeadOrGhost(unit) then
                pr:SetBackdropColor(0.5, 0.1, 0.1, ROW_ALPHA)      -- Dead (dark red)
            elseif UnitHasBuff(unit, b) then
                pr:SetBackdropColor(0, 1, 0, ROW_ALPHA)            -- Have (green)
                local dl
                if UnitIsUnit(unit, "player") then
                    local left = PlayerBuffTimeLeft(b)
                    if left then dl = now + left end
                elseif nm and expiry[nm] then
                    dl = expiry[nm][b.name or b.group]
                end
                if dl and dl > now then
                    local rem = dl - now
                    local m = math.floor(rem / 60)
                    timerText = string.format("%d:%02d", m, math.floor(rem - m * 60))
                end
            else
                pr:SetBackdropColor(1, 0, 0, ROW_ALPHA)            -- Need (red)
            end
            pr.timer:SetText(timerText)
            pr:Show()
        else
            pr:Hide()
        end
    end
end

local popoutNotOver = 0
local popoutAccum = 0
local function PopoutOnUpdate()
    if not popout:IsShown() then return end
    -- keep open while the cursor is over the anchor row OR the panel
    if IsMouseOverFrame(popoutRow) or IsMouseOverFrame(popout) then
        popoutNotOver = 0
    else
        popoutNotOver = popoutNotOver + (arg1 or 0)
        if popoutNotOver > 0.15 then HidePopout(); return end
    end
    popoutAccum = popoutAccum + (arg1 or 0)
    if popoutAccum >= 0.2 then popoutAccum = 0; RefreshPopout() end
end

local function GetPopoutRow(i)
    local pr = popoutRows[i]
    if pr then return pr end
    pr = CreateFrame("Button", "RallyPowerCP_PopRow" .. i, popout)
    pr:SetWidth(POP_W - 2 * POP_PAD); pr:SetHeight(POP_BAR_H)
    pr:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    pr:SetBackdrop(ROW_BACKDROP)
    pr:SetBackdropColor(0, 1, 0, ROW_ALPHA)
    local hl = pr:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(pr); hl:SetTexture(1, 1, 1, 0.18)
    local icon = pr:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(POP_BAR_H - 8); icon:SetHeight(POP_BAR_H - 8)
    icon:SetPoint("LEFT", pr, "LEFT", 4, 0)
    pr.icon = icon
    local name = pr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    name:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    name:SetPoint("RIGHT", pr, "RIGHT", -32, 0); name:SetJustifyH("LEFT")
    pr.name = name
    local role = pr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    role:SetPoint("TOPRIGHT", pr, "TOPRIGHT", -4, -2); role:SetJustifyH("RIGHT")
    pr.role = role
    local timer = pr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    timer:SetPoint("BOTTOMRIGHT", pr, "BOTTOMRIGHT", -4, 2); timer:SetJustifyH("RIGHT")
    pr.timer = timer
    pr:SetScript("OnClick", PopoutPlayerOnClick)
    popoutRows[i] = pr
    return pr
end

local function CreatePopout()
    local p = CreateFrame("Frame", "RallyPowerCP_Popout", UIParent)
    p:SetWidth(POP_W); p:SetHeight(40)
    p:SetBackdrop(ROW_BACKDROP)
    p:SetBackdropColor(0, 0, 0, 0.85)
    p:SetFrameStrata("DIALOG")
    p:EnableMouse(true)
    p:Hide()
    p:SetScript("OnUpdate", PopoutOnUpdate)
    popout = p
    return p
end

local function ShowPopout(row)
    if not popout then CreatePopout() end
    popoutClass = row.classToken
    popoutRow = row

    local units = classUnits[popoutClass] or {}
    local count = table.getn(units)
    local y = -POP_PAD
    for i = 1, count do
        local pr = GetPopoutRow(i)
        pr:ClearAllPoints()
        pr:SetPoint("TOPLEFT", popout, "TOPLEFT", POP_PAD, y)
        pr:SetWidth(POP_W - 2 * POP_PAD)
        y = y - (POP_BAR_H + POP_BAR_GAP)
    end
    for i = count + 1, table.getn(popoutRows) do popoutRows[i]:Hide() end

    local h = POP_PAD * 2 + count * POP_BAR_H
    if count > 1 then h = h + (count - 1) * POP_BAR_GAP end
    popout:SetHeight(h)
    popout:ClearAllPoints()
    popout:SetPoint("TOPRIGHT", row, "TOPLEFT", -2, 0)   -- expand to the LEFT
    popoutNotOver = 0
    RefreshPopout()
    popout:Show()
end

-- Build one class row, styled exactly like the PallyPower buff-bar button.
local function CreateClassRow(ct)
    local row = CreateFrame("Button", "RallyPowerCP_Row_" .. ct, bar)
    row:SetWidth(ROW_W); row:SetHeight(ROW_HEIGHT)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetBackdrop(ROW_BACKDROP)
    row:SetBackdropColor(0, 1, 0, ROW_ALPHA)
    row.classToken = ct

    local classIcon = row:CreateTexture(nil, "ARTWORK")
    classIcon:SetWidth(ROW_ICON); classIcon:SetHeight(ROW_ICON)
    classIcon:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -5)
    local cls = string.upper(string.sub(ct, 1, 1)) .. string.lower(string.sub(ct, 2))
    classIcon:SetTexture("Interface\\AddOns\\RallyPowerCP\\Icons\\" .. cls)
    row.classIcon = classIcon

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(ROW_ICON); icon:SetHeight(ROW_ICON)
    icon:SetPoint("TOPLEFT", classIcon, "TOPRIGHT", 4, 0)
    row.icon = icon

    local dim = row:CreateTexture(nil, "OVERLAY")
    dim:SetAllPoints(icon); dim:SetTexture(0, 0, 0, 0.55); dim:Hide()
    row.dim = dim

    local timer = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    timer:SetWidth(40); timer:SetHeight(16); timer:SetJustifyH("RIGHT")
    timer:SetPoint("TOPRIGHT", row, "TOPRIGHT", -5, 0)
    row.timer = timer

    local count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    count:SetWidth(40); count:SetHeight(16); count:SetJustifyH("RIGHT")
    count:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -5, 0)
    row.count = count

    row:SetScript("OnClick", ClassRowOnClick)
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", function() CycleRowBuff(this.classToken, (arg1 and arg1 > 0) and 1 or -1) end)
    row:SetScript("OnEnter", function() ShowPopout(this) end)
    row:SetScript("OnLeave", function() end)   -- pop-out self-hides when the cursor leaves both
    return row
end

local function LayoutButtons()
    if not bar then return end
    EnsureShownBuff()

    -- Hide all class rows first.
    for _, row in pairs(classRows) do row:Hide() end

    -- Top-row utility buttons (e.g. Priest PW: Shield / Fear Ward).
    local topY = -18
    local utilH = LayoutUtilityRow(topY)
    local y = topY - utilH

    -- One row per class present in the group, in CLASS_ORDER.
    local shown = 0
    for ci = 1, table.getn(presentClasses) do
        local ct = presentClasses[ci]
        local row = classRows[ct]
        if not row then row = CreateClassRow(ct); classRows[ct] = row end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", bar, "TOPLEFT", PAD, y)
        row:Show()
        y = y - (ROW_HEIGHT + ROW_GAP)
        shown = shown + 1
    end

    -- Size the bar to fit the utility row and the class rows.
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

    -- (1) Expiry-warning pass over EVERY buff (global earliest), so a buff not
    -- currently shown on the rows still dings and self-corrects on the tick.
    for i = 1, table.getn(ACTIVE_BUFFS) do
        local dl = minDeadline[i]
        if dl then
            local mr = dl - now
            if mr > 0 then
                if mr <= WARN_TIME then
                    if not warned[i] then
                        warned[i] = true
                        PlaySoundFile("Interface\\Addons\\RallyPowerCP\\Sounds\\ding.mp3")
                        local bb = ACTIVE_BUFFS[i]
                        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00RallyPowerCP:|r "
                            .. (bb.name or bb.group) .. " is about to expire!")
                    end
                else
                    warned[i] = nil
                end
            else
                minDeadline[i] = nil
                auraDirty = true
            end
        end
    end

    -- (2) Update each class row with ITS OWN selected buff's status for that class.
    for ci = 1, table.getn(presentClasses) do
        local ct = presentClasses[ci]
        local row = classRows[ct]
        if row and row:IsShown() then
            local bi = RowBuffIndex(ct)
            local b = bi and ACTIVE_BUFFS[bi]
            if b and b.icons then
                row.icon:SetTexture("Interface\\Icons\\" .. (b.icons[1] or "INV_Misc_QuestionMark"))
            end
            local need = (bi and rowNeed[ct] and rowNeed[ct][bi]) or 0
            local dl = bi and rowDeadline[ct] and rowDeadline[ct][bi]
            local mr = dl and (dl - now) or nil
            if need > 0 then
                row:SetBackdropColor(1, 0, 0, ROW_ALPHA)        -- red: someone needs it
                row.count:SetText(need)
            elseif mr and mr <= WARN_TIME then
                row:SetBackdropColor(1, 1, 0.5, ROW_ALPHA)      -- yellow: covered but expiring
                row.count:SetText("")
            else
                row:SetBackdropColor(0, 1, 0, ROW_ALPHA)        -- green: all covered
                row.count:SetText("")
            end
            if mr and mr > 0 then
                local m = math.floor(mr / 60)
                local s = math.floor(mr - m * 60)
                row.timer:SetText(string.format("%d:%02d", m, s))
            else
                row.timer:SetText("")
            end
            if row.dim and (now - lastCast) >= THROTTLE then row.dim:Hide() end
        end
    end
end

--=============================================================================
-- SCAN: count how many roster members still need each active buff
--=============================================================================
local function ScanRoster()
    if not ACTIVE_BUFFS then return end

    BuildClassPresence()   -- refresh classUnits + presentClasses (players only)

    -- Reset flat coverage (drives the expiry ding) and per-class coverage.
    for i = 1, table.getn(ACTIVE_BUFFS) do NEEDCOUNT[i] = 0; minDeadline[i] = nil end
    for ct in pairs(rowNeed) do rowNeed[ct] = nil end
    for ct in pairs(rowDeadline) do rowDeadline[ct] = nil end

    local now = GetTime()
    for ci = 1, table.getn(presentClasses) do
        local ct = presentClasses[ci]
        local units = classUnits[ct]
        rowNeed[ct] = {}
        rowDeadline[ct] = {}
        for r = 1, table.getn(units) do
            local unit = units[r]
            if UnitIsBuffable(unit) then
                local uname = UnitName(unit)
                CollectUnitBuffs(unit)              -- ONE buff-list read per unit
                local isPlayer = UnitIsUnit(unit, "player")
                for i = 1, table.getn(ACTIVE_BUFFS) do
                    local b = ACTIVE_BUFFS[i]
                    if BuffIsUsable(b) then
                        if not HasCollected(b) then
                            rowNeed[ct][i] = (rowNeed[ct][i] or 0) + 1
                            NEEDCOUNT[i] = NEEDCOUNT[i] + 1
                            -- buff gone: drop any stale recorded timer
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
                                    expiry[uname][b.name or b.group] = nil; dl = nil
                                end
                            end
                            if dl then
                                if not rowDeadline[ct][i] or dl < rowDeadline[ct][i] then
                                    rowDeadline[ct][i] = dl
                                end
                                if not minDeadline[i] or dl < minDeadline[i] then
                                    minDeadline[i] = dl
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Rebuild the rows only when the set of present classes actually changes.
    local sig = table.concat(presentClasses, ",")
    if sig ~= lastPresentSig then
        lastPresentSig = sig
        LayoutButtons()
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
        -- Paladins use the original PallyPower bar/grid (now with the hover
        -- player pop-out from RallyPowerCP_Popout.lua). No separate bar.
        ACTIVE_BUFFS = nil
        if bar then bar:Hide() end
        return
    end

    RallyPowerCP.active = RallyPowerCP.classes[PLAYER_CLASS]
    ACTIVE_BUFFS   = RallyPowerCP.active and RallyPowerCP.active.buffs
    ACTIVE_UTILITY = RallyPowerCP.active and RallyPowerCP.active.utility

    -- Modules that render their own strip instead of the buff grid (e.g. Shaman
    -- totems) do their setup here.
    if RallyPowerCP.active and RallyPowerCP.active.OnActivate then
        RallyPowerCP.active:OnActivate()
    end

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
        BuildClassPresence()
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
        if event == "PLAYER_LOGIN" and not HAS_SUPERWOW and not RallyPowerCP_Settings._swowNagged then
            RallyPowerCP_Settings._swowNagged = true
            DEFAULT_CHAT_FRAME:AddMessage("|cffffff00RallyPowerCP:|r SuperWoW not detected - running in 1.12 compatibility mode (icon-based buff detection). SuperWoW is recommended on Turtle for exact tracking.")
        end
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
    -- Strip-based modules (e.g. Shaman) manage their own show/hide.
    if RallyPowerCP.active and RallyPowerCP.active.Toggle then
        RallyPowerCP.active:Toggle()
        return true
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
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00RallyPowerCP:|r As a Paladin, use /pp for the blessing grid (it now has the hover player pop-out). /rpc icon changes the minimap icon.")
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
