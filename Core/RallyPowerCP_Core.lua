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
--                 hover player pop-out (RallyPowerCP_Popout.lua). No separate UI.
--   * Priest/Mage/Druid -> the class-buff strip (RallyPowerCP.BuildClassBuffs):
--       one strip button per raid class showing that class's assigned buff;
--       red+count = members missing it, green+timer = covered; scroll a button
--       to switch that class's buff, left-click casts the group version,
--       right-click tops off the next member, hover opens the player pop-out.
--       Priest also appends its utility buttons (PW: Shield / Fear Ward).
--       Everything (frame, drag, scale grip, position) comes from the strip
--       engine, so these read identically to Shaman/Hunter/Warlock/Rogue.
--   * The engine also provides an expiry "ding", a Smart Buff key binding, and
--     the shared minimap icon skins.
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
local SCAN_INTERVAL = 1.0        -- default seconds between roster rescans
-- Scan-frequency slider (options): how often ScanRoster runs. The force idiom
-- `lastScan = ScanInterval()` still triggers a scan on the next tick.
local function ScanInterval() return RallyPowerCP_Settings.scanFreq or SCAN_INTERVAL end

-- Line-of-sight gate: reuses the legacy engine's UnitXP SP3 check (shared
-- PP_PerUser.useunitxp_sp3 setting). Returns true when the feature is off or
-- UnitXP.dll isn't loaded, so targeting is unaffected unless the user opts in.
local function InLoS(u)
    return (not PallyPower_CheckTargetLoS) or PallyPower_CheckTargetLoS(u)
end
local lastCast = 0               -- throttle guard: GetTime() of the last cast
local THROTTLE = 1.5             -- seconds a click is ignored after casting (= GCD)
local FOUR_MIN = 240             -- right-click won't overwrite a buff with this much left
local inCombat = false           -- tracked via PLAYER_REGEN_DISABLED/ENABLED (1.12-safe)

-- Class-grouped state: the class-buff strip shows one button per class present
-- in the group; each button tracks its own selected buff (scroll to change it)
-- and coverage is broken down by class.
local CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local CLASS_SET = {}
for _, c in pairs(CLASS_ORDER) do CLASS_SET[c] = true end
-- legacy PallyPower class ids (the blessing grid's column order); shared
-- with the assignment panel and the class-buff domain of the model
local TOKEN2ID = { WARRIOR = 0, ROGUE = 1, PRIEST = 2, DRUID = 3, PALADIN = 4,
                   HUNTER = 5, MAGE = 6, WARLOCK = 7, SHAMAN = 8 }
RallyPowerCP.Token2ClassID = TOKEN2ID
local classUnits    = {}         -- [classToken] = { unitIDs of that class }
local presentClasses = {}        -- ordered list of class tokens with >=1 member
local rowNeed       = {}         -- [classToken][buffIndex] = members of that class missing it
local rowDeadline   = {}         -- [classToken][buffIndex] = earliest absolute expiry for that class
local classCursor   = {}         -- [classToken] = round-robin index for right-click cycling
local roster        = {}         -- flat unit list, reused by presence + scan
local lastPresentSig             -- signature of presentClasses, to detect changes
local classStrip                 -- the class-buff strip (Priest/Mage/Druid; built lazily)
local popout                     -- the hover pop-out side panel (created lazily)
local popoutRows = {}            -- pooled per-player row buttons inside the panel
local popoutClass                -- class token the pop-out is currently showing
local popoutRow                  -- the class button the pop-out is anchored to

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
    -- Test mode: pretend every buff this class defines is learned, so the full
    -- kit can be previewed on an under-levelled character.
    if RallyPowerCP_Settings.testMode and ACTIVE_BUFFS then
        for _, b in pairs(ACTIVE_BUFFS) do
            if b.name then KNOWN[b.name] = true end
            if b.group then KNOWN[b.group] = true end
        end
    end
end

-- A buff is "usable" if the player knows either its single or group form and
-- it isn't switched off on the options Buttons tab (explicit false; absent
-- means enabled). This is the single choke point the wheel/rows flow through.
local function BuffIsUsable(b)
    if RallyPowerCP_Settings["gridbuff_" .. (b.name or b.group or "")] == false then
        return false
    end
    if b.name and KNOWN[b.name] then return true end
    if b.group and KNOWN[b.group] then return true end
    return false
end

--=============================================================================
-- SHARED LOOK  (the class-buff UI is a strip: Core\RallyPowerCP_Strip.lua
-- builds the frame and buttons; only the pop-out geometry lives here)
--=============================================================================
-- Hover pop-out: 100x34 player rows replicating PallyPowerPopupTemplate,
-- stacked flush and floating bare, expanding to the LEFT of the class buttons
-- (mirror of Core\RallyPowerCP_Popout.lua, the Paladin reference).
local POP_ROW_W = 100
local POP_ROW_H = 34
local ROW_BACKDROP = {
    bgFile   = "Interface\\AddOns\\RallyPowerCP\\Skins\\Smooth",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = false, tileSize = 8, edgeSize = 8,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
}
-- official presets from PallyPowerValues.lua
local C_GOOD    = { r = 0, g = 0.7, b = 0, t = 0.5 }
local C_NEEDALL = { r = 1, g = 0,   b = 0, t = 0.5 }
local C_SPECIAL = { r = 0, g = 0,   b = 1, t = 0.5 }

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
        if UnitIsBuffable(u) and UnitIsVisible(u) and InLoS(u) then
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
    -- Test mode: SIMULATE - record the timer and announce, cast nothing.
    if RallyPowerCP_Settings.testMode then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[test]|r would cast " .. spell .. " on " .. (UnitName(unit) or unit))
        if isGroup then RecordGroupExpiry(unit, b, dur)
        else RecordExpiry(unit, b, dur) end
        return
    end
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
        if UnitIsBuffable(u) and UnitIsVisible(u) and InLoS(u) then
            local mh = UnitHealthMax(u)
            if mh and mh > 0 then
                local pct = UnitHealth(u) / mh
                if pct < bestPct then bestPct = pct; best = u end
            end
        end
    end
    return best
end

-- Reliable single-target cast with no timer tracking (utility spells).
local function CastSpellOnUnit(spell, unit)
    if RallyPowerCP_Settings.testMode then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[test]|r would cast " .. tostring(spell) .. " on " .. (UnitName(unit) or tostring(unit)))
        return true
    end
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
                auraDirty = true; lastScan = ScanInterval()
                return
            end
            local unit = FindUnitToBuff(b, false)
            if unit then
                local spell = (b.name and KNOWN[b.name]) and b.name or b.group
                CastBuffOn(spell, unit, b, (spell == b.name) and b.dur or b.gdur,
                           spell == b.group)
                auraDirty = true; lastScan = ScanInterval()
                return
            end
        end
    end
end

-- Throttle guard: record the cast time and spin the button's cooldown swirl so
-- it's visually obvious you can't usefully click again until the GCD is up.
local function StartThrottle(btn)
    lastCast = GetTime()
    if btn and btn.dim then btn.dim:Show() end
end

-- unitID for a raid/party member by name (nil if not present).
local function UnitIdOf(name)
    if not name then return nil end
    if name == UnitName("player") then return "player" end
    local n = GetNumRaidMembers()
    if n > 0 then
        for i = 1, n do if UnitName("raid" .. i) == name then return "raid" .. i end end
    else
        for i = 1, GetNumPartyMembers() do if UnitName("party" .. i) == name then return "party" .. i end end
    end
    return nil
end

-- A present, alive member marked with the given role (over PallyPower's own
-- Tanks/Healers tables, so it honours marks from any PallyPower user).
local function FirstRoleUnit(role)
    local tbl = (role == "TANK") and PallyPower_Tanks or PallyPower_Healers
    if not tbl then return nil end
    for name in pairs(tbl) do
        if tbl[name] then
            local uid = UnitIdOf(name)
            if uid and UnitExists(uid) and not UnitIsDeadOrGhost(uid) then return uid end
        end
    end
    return nil
end

-- Resolve a utility button's assigned target: my duty value for it, if it's a
-- @ROLE or a specific player. Returns a unitID or nil (fall back to `mode`).
local function ResolveDutyTarget(dutyKey)
    if not (dutyKey and RallyPowerCP.Assign) then return nil end
    local v = RallyPowerCP.Assign.GetDuty(UnitName("player"), dutyKey)
    if type(v) ~= "string" then return nil end
    if v == "@TANK" then return FirstRoleUnit("TANK") end
    if v == "@HEALER" then return FirstRoleUnit("HEALER") end
    return UnitIdOf(v)                      -- a specific player name
end

-- Click handler for a utility button (PW: Shield, Fear Ward, ...).
local function UtilityOnClick()
    local u = ACTIVE_UTILITY and ACTIVE_UTILITY[this.utilIndex]
    if not u then return end
    if not KNOWN[u.name] then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00RallyPowerCP:|r You haven't learned " .. u.name .. ".")
        return
    end
    -- an assigned @TANK/@HEALER (or player) target wins over the default mode
    local target = u.duty and ResolveDutyTarget(u.duty)
    if target and not (UnitExists(target) and UnitIsBuffable(target)) then target = nil end
    if not target then
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
    end
    if not target then target = "player" end
    if CastSpellOnUnit(u.name, target) then
        AnnounceBuff(u.name, target, false)
    end
end

-- Forward declarations: the pop-out refresher and the class-strip refresher
-- are defined further down but referenced by the wheel/scan closures above.
local RefreshClassStrip
local RefreshPopout

-- Per-class buff selection: each class button independently tracks one of the
-- player's buffs (scroll a row to change just that class's buff, PallyPower-style).
local rowBuff = {}               -- [classToken] = buff index shown/cast for that class

-- Return the usable buff index for class ct, defaulting to the first usable.
local function RowBuffIndex(ct)
    if not ACTIVE_BUFFS then return nil end
    -- Effective selection (DESIGN_ASSIGNMENTS.md 9): my row in the shared
    -- model first (the panel's Raid Buffs grid writes it), the local wheel
    -- choice second, first usable buff last.
    if RallyPowerCP.Assign then
        local want = RallyPowerCP.Assign.GetClassBuff(UnitName("player"), TOKEN2ID[ct])
        if want then
            for i = 1, table.getn(ACTIVE_BUFFS) do
                local bb = ACTIVE_BUFFS[i]
                if (bb.name == want or bb.group == want) and BuffIsUsable(bb) then
                    return i
                end
            end
        end
    end
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
    -- wheeling self-assigns in the shared model (step-1b style), so the
    -- panel's Raid Buffs grid and this strip are two views of one row
    if RallyPowerCP.Assign and ACTIVE_BUFFS[i] then
        RallyPowerCP.Assign.SetClassBuff(UnitName("player"), TOKEN2ID[ct],
            ACTIVE_BUFFS[i].name or ACTIVE_BUFFS[i].group)
    end
    if RefreshClassStrip then RefreshClassStrip() end
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
        if UnitIsBuffable(u) and UnitIsVisible(u) and InLoS(u) then
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
        if UnitIsBuffable(u) and UnitIsVisible(u) and InLoS(u) then
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

-- Click a class button: left = group version on this class, right = smart
-- single top-off within this class (combat-locked, 4-min floor). `btn` is the
-- strip button (carries .classToken); `mb` is the mouse button.
local function ClassButtonOnClick(btn, mb)
    local ct = btn.classToken
    local bi = RowBuffIndex(ct)
    local b = bi and ACTIVE_BUFFS[bi]
    if not b then return end
    if GetTime() - lastCast < THROTTLE then return end

    if b.selfcast then
        if KNOWN[b.name] then
            CastSpellByName(b.name)
            RecordGroupExpiry("player", b, b.dur)
            AnnounceBuff(b.name, "player", false)
            StartThrottle(btn)
        end
        auraDirty = true; lastScan = ScanInterval()
        return
    end

    if mb == "RightButton" then
        if inCombat then
            DEFAULT_CHAT_FRAME:AddMessage("|cffffff00RallyPowerCP:|r auto-buff is disabled in combat.")
            return
        end
        local unit = FindClassSmartTarget(ct, b)
        if not unit then
            DEFAULT_CHAT_FRAME:AddMessage("|cffffff00RallyPowerCP:|r " .. ct .. ": covered (4+ min left).")
            return
        end
        if b.name and KNOWN[b.name] then CastBuffOn(b.name, unit, b, b.dur, false); StartThrottle(btn)
        elseif b.group and KNOWN[b.group] then CastBuffOn(b.group, unit, b, b.gdur, true); StartThrottle(btn) end
        auraDirty = true; lastScan = ScanInterval()
        return
    end

    -- left-click: group version, covering this class's subgroup
    local unit = FindClassNeedy(ct, b, true)
    if not unit then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00RallyPowerCP:|r " .. ct .. ": no members in range.")
        return
    end
    if b.group and KNOWN[b.group] then CastBuffOn(b.group, unit, b, b.gdur, true); StartThrottle(btn)
    elseif b.name and KNOWN[b.name] then CastBuffOn(b.name, unit, b, b.dur, false); StartThrottle(btn) end
    auraDirty = true; lastScan = ScanInterval()
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
        auraDirty = true; lastScan = ScanInterval()
        return
    end

    -- left-click: group version covering this player's subgroup
    if inCombat then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00RallyPowerCP:|r group buffs are disabled in combat (right-click for a single buff).")
        return
    end
    -- Smart buffs (default on): don't waste a group cast on someone already
    -- buffed. Turn the option off to allow re-casting on covered players.
    if RallyPowerCP_Settings.smartBuffs ~= false and UnitHasBuff(unit, b) then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00RallyPowerCP:|r " .. (UnitName(unit) or "?") .. " already has " .. (b.name or b.group) .. ".")
        return
    end
    if b.group and KNOWN[b.group] then
        CastBuffOn(b.group, unit, b, b.gdur, true); StartThrottle(this)
    elseif b.name and KNOWN[b.name] then
        CastBuffOn(b.name, unit, b, b.dur, false); StartThrottle(this)
    end
    auraDirty = true; lastScan = ScanInterval()
end

-- Refresh each visible player row with the official popup states:
--   not visible -> C_SPECIAL (blue), dim icon, red R
--   dead        -> C_NEEDALL (red),  dim icon, green R, red D
--   has buff    -> C_GOOD (green),   full icon
--   needs it    -> C_NEEDALL (red),  dim icon
-- Local MT/MA role markers ride the official tank icon (white / cyan tint).
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
            local nm = UnitName(unit)
            pr.name:SetText(nm or "?")
            if iconTex then pr.icon:SetTexture(iconTex) end
            local timerText = ""
            if not UnitIsVisible(unit) then
                pr:SetBackdropColor(C_SPECIAL.r, C_SPECIAL.g, C_SPECIAL.b, C_SPECIAL.t)
                pr.icon:SetAlpha(0.4)
                pr.rng:SetTextColor(1, 0, 0); pr.rng:SetAlpha(1)
                pr.dead:SetAlpha(0)
            elseif UnitIsDeadOrGhost(unit) then
                pr:SetBackdropColor(C_NEEDALL.r, C_NEEDALL.g, C_NEEDALL.b, C_NEEDALL.t)
                pr.icon:SetAlpha(0.4)
                pr.rng:SetTextColor(0, 1, 0); pr.rng:SetAlpha(1)
                pr.dead:SetTextColor(1, 0, 0); pr.dead:SetAlpha(1)
            elseif UnitHasBuff(unit, b) then
                pr:SetBackdropColor(C_GOOD.r, C_GOOD.g, C_GOOD.b, C_GOOD.t)
                pr.icon:SetAlpha(1)
                pr.rng:SetTextColor(0, 1, 0); pr.rng:SetAlpha(1)
                pr.dead:SetAlpha(0)
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
                pr:SetBackdropColor(C_NEEDALL.r, C_NEEDALL.g, C_NEEDALL.b, C_NEEDALL.t)
                pr.icon:SetAlpha(0.4)
                pr.rng:SetTextColor(0, 1, 0); pr.rng:SetAlpha(1)
                pr.dead:SetAlpha(0)
            end
            pr.timer:SetText(timerText)
            local role = nm and RallyPowerCP_Roles[nm]
            if role == "MT" then
                pr.tank:SetVertexColor(1, 1, 1); pr.tank:SetAlpha(1)
            elseif role == "MA" then
                pr.tank:SetVertexColor(0.4, 0.8, 1); pr.tank:SetAlpha(1)
            else
                pr.tank:SetAlpha(0)
            end
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

-- Build one popup row, laid out exactly like PallyPowerPopupTemplate
-- (mirror of GetRow in Core\RallyPowerCP_Popout.lua).
local function GetPopoutRow(i)
    local pr = popoutRows[i]
    if pr then return pr end
    pr = CreateFrame("Button", "RallyPowerCP_PopRow" .. i, popout)
    pr:SetWidth(POP_ROW_W); pr:SetHeight(POP_ROW_H)
    pr:SetFrameStrata("DIALOG")
    pr:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    pr:SetBackdrop(ROW_BACKDROP)
    local hl = pr:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(pr); hl:SetTexture(1, 1, 1, 0.18)

    local icon = pr:CreateTexture(nil, "OVERLAY")           -- $parentBuffIcon
    icon:SetWidth(16); icon:SetHeight(16)
    icon:SetPoint("TOPLEFT", pr, "TOPLEFT", 4, -4)
    pr.icon = icon

    local timer = pr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    timer:SetWidth(40); timer:SetHeight(16)                 -- $parentTime
    timer:SetPoint("TOPLEFT", icon, "TOPRIGHT", 1, 0)
    timer:SetJustifyH("LEFT")
    pr.timer = timer

    local name = pr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    name:SetWidth(92); name:SetHeight(16)                   -- $parentName
    name:SetPoint("BOTTOMRIGHT", pr, "BOTTOMRIGHT", -5, 3)
    name:SetJustifyH("RIGHT")
    pr.name = name

    local rng = pr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rng:SetWidth(10); rng:SetHeight(10)                     -- $parentRng
    rng:SetPoint("TOPRIGHT", pr, "TOPRIGHT", -6, -6)
    rng:SetJustifyH("RIGHT")
    rng:SetText("R")
    pr.rng = rng

    local dead = pr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dead:SetWidth(10); dead:SetHeight(10)                   -- $parentDead
    dead:SetPoint("RIGHT", rng, "LEFT", -3, 0)
    dead:SetJustifyH("RIGHT")
    dead:SetText("D")
    pr.dead = dead

    local tank = pr:CreateTexture(nil, "OVERLAY")           -- $parentTankIcon
    tank:SetWidth(11); tank:SetHeight(11)
    tank:SetTexture("Interface\\GroupFrame\\UI-Group-MainTankIcon")
    tank:SetPoint("RIGHT", dead, "LEFT", -3, 0)
    pr.tank = tank

    pr:SetScript("OnClick", PopoutPlayerOnClick)
    popoutRows[i] = pr
    return pr
end

local function CreatePopout()
    -- Bare container: the official popup rows float with their own backdrops,
    -- so this frame exists only for layout and the keep-open hit-test.
    local p = CreateFrame("Frame", "RallyPowerCP_Popout", UIParent)
    p:SetWidth(POP_ROW_W); p:SetHeight(POP_ROW_H)
    p:SetFrameStrata("DIALOG")
    p:SetScale(RallyPowerCP_Settings.uiScale or 1)
    p:EnableMouse(false)
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
    local y = 0
    for i = 1, count do
        local pr = GetPopoutRow(i)
        pr:ClearAllPoints()
        pr:SetPoint("TOPLEFT", popout, "TOPLEFT", 0, y)
        y = y - POP_ROW_H                                -- stacked flush
    end
    for i = count + 1, table.getn(popoutRows) do popoutRows[i]:Hide() end

    popout:SetHeight(count * POP_ROW_H)
    popout:ClearAllPoints()
    popout:SetPoint("TOPRIGHT", row, "TOPLEFT", -4, 0)   -- expand to the LEFT
    popoutNotOver = 0
    RefreshPopout()
    popout:Show()
end

-- Is class ct shown on the strip right now? Present in the group, or always in
-- test mode (so the full nine-button layout previews solo).
local function ClassPresent(ct)
    if RallyPowerCP.IsTestMode and RallyPowerCP.IsTestMode() then return true end
    for i = 1, table.getn(presentClasses) do
        if presentClasses[i] == ct then return true end
    end
    return false
end

local function TitleCase(s)
    return string.upper(string.sub(s, 1, 1)) .. string.lower(string.sub(s, 2))
end

-- Class icon for a row: the legacy engine's texture set (honours HD Icons),
-- with the addon's own art as fallback.
local function ClassIconPath(ct)
    local id = TOKEN2ID[ct]
    if PallyPower_ClassTexture and id and PallyPower_ClassTexture[id] then
        return PallyPower_ClassTexture[id]
    end
    return "Interface\\AddOns\\RallyPowerCP\\Icons\\" .. TitleCase(ct)
end

-- One class-buff button def for the shared strip, in the paladin buff bar's
-- exact anatomy: class icon + buff icon side by side (no text labels; the
-- pop-out and tooltips carry the words), need-count / timer at the right,
-- backdrop coloured by coverage. Wheel cycles that class's buff; L = group
-- cast, R = smart single top-off; hover opens the player pop-out.
local function ClassButtonDef(ct)
    return {
        key = "cls_" .. string.lower(ct),
        visible = function() return ClassPresent(ct) end,
        refresh = function(b)
            b:SetIcon(ClassIconPath(ct))
            b:SetLabel(""); b:SetSub("")
            local bi = RowBuffIndex(ct)
            local bd = bi and ACTIVE_BUFFS[bi]
            if not bd then
                b:SetIcon2(nil); b:SetTimer(""); b:SetState("off"); return
            end
            b:SetIcon2(bd.icons and ("Interface\\Icons\\" .. (bd.icons[1] or "INV_Misc_QuestionMark")) or nil)
            local need = (rowNeed[ct] and rowNeed[ct][bi]) or 0
            local dl = rowDeadline[ct] and rowDeadline[ct][bi]
            local now = GetTime()
            local mr = dl and (dl - now) or nil
            if need > 0 then
                b:SetState("need")                              -- red: someone needs it
                b:SetTimer("|cffffffff" .. need .. "|r")
            elseif mr and mr <= WARN_TIME then
                b:SetBackdropColor(1, 1, 0.5, RallyPowerCP_Settings.stripAlpha or 0.5)   -- yellow: covered but expiring
                b.icon:SetAlpha(1)
                if b.icon2 then b.icon2:SetAlpha(1) end
                local m = math.floor(mr / 60)
                b:SetTimer(string.format("%d:%02d", m, math.floor(mr - m * 60)))
            else
                b:SetState("good")                              -- green: all covered
                if mr and mr > 0 then
                    local m = math.floor(mr / 60)
                    b:SetTimer(string.format("%d:%02d", m, math.floor(mr - m * 60)))
                else
                    b:SetTimer("")
                end
            end
        end,
        onClick = function(b, mb) ClassButtonOnClick(b, mb) end,
        onWheel = function(b, delta) CycleRowBuff(ct, (delta and delta > 0) and 1 or -1) end,
        onEnter = function(b) ShowPopout(b) end,
        onLeave = function() end,    -- pop-out self-hides when the cursor leaves both
    }
end

-- One utility button def (Priest PW: Shield / Fear Ward): the same strip
-- anatomy, cast on click.
local function UtilityButtonDef(u, uidx)
    local short = u.name
    local _, _, after = string.find(u.name, ": (.+)")
    if after then short = after end
    return {
        key = "util_" .. uidx,
        visible = function() return KNOWN[u.name] and RallyPowerCP_Settings.utilRow ~= false end,
        refresh = function(b)
            b:SetLabel("|cffffd100" .. short .. "|r")
            -- show the assigned role target (Fear Ward -> Tank) when I hold it
            local roleTag
            if u.duty and RallyPowerCP.Assign then
                local v = RallyPowerCP.Assign.GetDuty(UnitName("player"), u.duty)
                if v == "@TANK" then roleTag = "on Tank"
                elseif v == "@HEALER" then roleTag = "on Healer"
                elseif type(v) == "string" then roleTag = "on " .. v end
            end
            if roleTag then
                b:SetSub("|cff88ccff" .. roleTag .. "|r")
                b:SetState("good")
            else
                b:SetSub(u.tip and ("|cff999999" .. u.tip .. "|r") or "")
                b:SetState("off")
            end
            b:SetIcon(GetSpellIconByName(u.name) or ("Interface\\Icons\\" .. (u.icon or "INV_Misc_QuestionMark")))
            b:SetTimer("")
        end,
        onClick = function(b) b.utilIndex = uidx; UtilityOnClick() end,
        tooltip = function(b, tt)
            tt:AddLine(u.name, 1, 1, 1)
            local roleTgt
            if u.duty and RallyPowerCP.Assign then
                local v = RallyPowerCP.Assign.GetDuty(UnitName("player"), u.duty)
                if v == "@TANK" then roleTgt = "the marked Tank"
                elseif v == "@HEALER" then roleTgt = "the marked Healer"
                elseif type(v) == "string" then roleTgt = v end
            end
            if roleTgt then
                tt:AddLine("Assigned: cast on " .. roleTgt, 0.6, 1, 0.6)
                tt:AddLine("(falls back to " .. (u.tip or "target") .. " if not present)", 0.6, 0.6, 0.6)
            else
                tt:AddLine("Click: cast on " .. (u.tip or "target"), 0.8, 0.8, 0.8)
            end
        end,
    }
end

-- Build the shared class-buff strip (Priest / Mage / Druid). One button per
-- class in CLASS_ORDER plus the module's utility buttons; presence gating and
-- the drag/scale/position furniture all come from the strip engine, so these
-- classes read identically to Shaman / Hunter / Warlock / Rogue.
function RallyPowerCP.BuildClassBuffs()
    if classStrip then return classStrip end
    local title = PLAYER_CLASS and TitleCase(PLAYER_CLASS) or "Buffs"
    classStrip = RallyPowerCP.NewStrip("classbuffs", title)
    for ci = 1, table.getn(CLASS_ORDER) do
        local ct = CLASS_ORDER[ci]
        local b = classStrip:AddButton(ClassButtonDef(ct))
        b.classToken = ct
    end
    if ACTIVE_UTILITY then
        for i = 1, table.getn(ACTIVE_UTILITY) do
            classStrip:AddButton(UtilityButtonDef(ACTIVE_UTILITY[i], i))
        end
    end
    classStrip:Finish()
    RefreshClassStrip = function()
        if classStrip then classStrip:Refresh() end
    end
    return classStrip
end

--=============================================================================
-- CHEAP PER-SECOND TICK: countdown text + expiry warning. Pure arithmetic on
-- stored deadlines — zero UnitBuff/API calls — so it can run every second.
--=============================================================================
-- (forward-declared above) Cheap per-second tick: the expiry-warning ding, plus
-- a strip repaint. The per-class button visuals live in ClassButtonDef.refresh
-- (driven by the strip's own 0.25s ticker); this only handles the global ding
-- and keeps the strip current between roster scans.
function UpdateDisplays()
    if not ACTIVE_BUFFS then return end
    local now = GetTime()

    -- Expiry-warning pass over EVERY buff (global earliest), so a buff not
    -- currently shown still dings and self-corrects on the tick.
    for i = 1, table.getn(ACTIVE_BUFFS) do
        local dl = minDeadline[i]
        if dl then
            local mr = dl - now
            if mr > 0 then
                if mr <= WARN_TIME then
                    if not warned[i] then
                        warned[i] = true
                        -- "Sound when a buff runs out" toggle (default on).
                        if RallyPowerCP_Settings.expirySound ~= false then
                            PlaySoundFile("Interface\\Addons\\RallyPowerCP\\Sounds\\ding.mp3")
                        end
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

    if RefreshClassStrip then RefreshClassStrip() end
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

    -- Re-flow the strip (show/hide + collapse) only when the set of present
    -- classes actually changes.
    local sig = table.concat(presentClasses, ",")
    if sig ~= lastPresentSig then
        lastPresentSig = sig
        if classStrip then classStrip:Reflow() end
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
        -- player pop-out from RallyPowerCP_Popout.lua). No separate strip.
        ACTIVE_BUFFS = nil
        return
    end

    RallyPowerCP.active = RallyPowerCP.classes[PLAYER_CLASS]
    ACTIVE_BUFFS   = RallyPowerCP.active and RallyPowerCP.active.buffs
    ACTIVE_UTILITY = RallyPowerCP.active and RallyPowerCP.active.utility

    -- Every non-paladin module builds its own strip UI here: Shaman totems,
    -- Hunter stings, Warlock/Rogue duties, the Warrior shout, and the
    -- Priest/Mage/Druid class-buff strip (RallyPowerCP.BuildClassBuffs).
    if RallyPowerCP.active and RallyPowerCP.active.OnActivate then
        RallyPowerCP.active:OnActivate()
    end

    -- Strip-only modules (no tracked group buffs) are fully set up now.
    if not ACTIVE_BUFFS or table.getn(ACTIVE_BUFFS) == 0 then
        ACTIVE_BUFFS = nil
        return
    end

    -- Class-buff modules additionally drive the Core coverage engine that feeds
    -- the strip's per-class need counts, timers and pop-out.
    BuildIconLookups()
    RebuildKnownSpells()
    local ok, err = pcall(function()
        BuildClassPresence()
        if classStrip then classStrip:Reflow() end
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
        RallyPowerCP_ApplyVisibility()    -- honor show-solo/party/raid
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
            if classStrip then classStrip:Reflow() end
            auraDirty = true
        end
    elseif event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
        RallyPowerCP_ApplyVisibility()    -- group size may have crossed a show rule
        if PLAYER_CLASS and PLAYER_CLASS ~= "PALADIN" then
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
    if lastScan >= ScanInterval() then
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
    -- Every non-paladin class now renders a strip and manages its own show/hide.
    if RallyPowerCP.active and RallyPowerCP.active.Toggle then
        RallyPowerCP.active:Toggle()
        return true
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cffffff00RallyPowerCP:|r No tracked buffs for your class yet.")
    return true
end

-- Is the player a class the class bar serves? (used by the minimap routing)
function RallyPowerCP_IsClassBarUser()
    return PLAYER_CLASS ~= nil and PLAYER_CLASS ~= "PALADIN"
end

--=============================================================================
-- OPTIONS HOOKS  (shared by /rpc and Core\RallyPowerCP_Options.lua)
--=============================================================================

-- Central test-mode switch: one code path for /rpc test AND the options check.
function RallyPowerCP_SetTestMode(on)
    on = on and true or false
    if on == (RallyPowerCP_Settings.testMode and true or false) then return end
    RallyPowerCP_Settings.testMode = on
    if on then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00RallyPowerCP:|r |cffff8800TEST MODE ON|r - all options are shown (unlearned ones marked), and clicks SIMULATE casts: timers and colours run, but nothing is actually cast. /rpc test again to turn off.")
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00RallyPowerCP:|r Test mode off - back to live casting and your real spellbook.")
        -- Leaving test mode drops the preview raid's totem/duty rows from the
        -- assignment store (your own block survives PruneToRoster) and the
        -- preview paladins' blessing table.
        if RallyPowerCP.Assign then
            RallyPowerCP.Assign.PruneToRoster()
        end
        RallyPowerCP_Settings.testBless = nil
    end
    if RallyPowerCP.active and RallyPowerCP.active.OnActivate then
        RallyPowerCP.active:OnActivate()
    end
    if PLAYER_CLASS == "PALADIN" then
        -- Repaint the legacy bar now so its test-mode all-class buttons appear
        -- (or clear) immediately instead of on the next engine scan.
        if PallyPower_UpdateUI then PallyPower_UpdateUI() end
    elseif PLAYER_CLASS then
        RebuildKnownSpells()
        if classStrip then classStrip:Reflow() end
        auraDirty = true
    end
end

-- Options hook: a gridbuff_*/utilRow flag changed - re-derive and re-flow.
function RallyPowerCP_GridRefresh()
    if not ACTIVE_BUFFS then return end
    RebuildKnownSpells()
    if classStrip then classStrip:Reflow() end
    auraDirty = true
end

-- Show-when-solo/party/raid gate (Settings tab; absent settings mean shown).
function RallyPowerCP_VisibilityAllowed()
    local key
    if GetNumRaidMembers() > 0 then key = "showRaid"
    elseif GetNumPartyMembers() > 0 then key = "showParty"
    else key = "showSolo" end
    return RallyPowerCP_Settings[key] ~= false
end

-- ANDed with the per-frame hidden flags: hiding here never overwrites what the
-- user toggled by hand, and the Paladin legacy frames are deliberately exempt.
-- Every non-paladin class UI (including the class-buff strip) is a registered
-- strip, so one loop covers them all.
function RallyPowerCP_ApplyVisibility()
    local ok = RallyPowerCP_VisibilityAllowed()
    if RallyPowerCP.strips then
        for k, S in pairs(RallyPowerCP.strips) do
            if not ok then S.frame:Hide()
            elseif not RallyPowerCP_Settings["stripHidden_" .. k] then S.frame:Show() end
        end
    end
end

-- Options hook: live UI-scale application (every strip + the pop-out; the
-- Paladin engine keeps its own scale settings under /pp Options).
function RallyPowerCP_ApplyUIScale()
    local s = RallyPowerCP_Settings.uiScale or 1
    if RallyPowerCP.strips then
        -- the global slider re-unifies every strip: per-strip grip scales
        -- are cleared so the slider does what it says
        for key, S in pairs(RallyPowerCP.strips) do
            RallyPowerCP_Settings["stripScale_" .. key] = nil
            S.frame:SetScale(s)
        end
    end
    if popout then popout:SetScale(s) end
end

-- Class-buff strip back to its default anchor (shared by /rpc reset and Reset
-- Frames). Other strips are handled by the options Reset Frames sweep.
function RallyPowerCP_ResetBarPosition()
    RallyPowerCP_Settings["stripPos_classbuffs"] = nil
    if classStrip and classStrip.frame then
        classStrip.frame:ClearAllPoints()
        classStrip.frame:SetPoint("CENTER", UIParent, "CENTER", 260, 0)
    end
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
RallyPowerCP_MinimapSkinLabels = SKIN_LABEL   -- exposed for the options dropdown

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

    -- Test mode: preview every option and simulate casts (for under-levelled
    -- characters). Available to every class.
    if msg == "test" then
        RallyPowerCP_SetTestMode(not RallyPowerCP_Settings.testMode)
        return
    end

    -- Options frame: every class (the Settings + Buttons tabs adapt per class;
    -- Paladins get the merged legacy PallyPower settings).
    if msg == "options" or msg == "opt" or msg == "config" then
        if RallyPowerCP_OptionsToggle then RallyPowerCP_OptionsToggle() end
        return
    end

    -- Escape hatch: the classic PallyPower options frame, in case something
    -- wasn't migrated into the panel.
    if msg == "legacy" then
        if PallyPower_Options then PallyPower_Options() end
        return
    end

    -- Assignment panel: every class (Blessings tab drives the legacy PLPWR
    -- tables; the other tabs drive the shared assignment model).
    if msg == "assign" or msg == "assignments" then
        if RallyPowerCP_AssignPanelToggle then RallyPowerCP_AssignPanelToggle() end
        return
    end

    -- Force a full assignment re-sync (request others' + push mine). Every
    -- class; blessings still sync separately over PLPWR.
    if msg == "sync" then
        if RallyPowerCP_SyncNow then RallyPowerCP_SyncNow() end
        return
    end

    if PLAYER_CLASS == "PALADIN" then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00RallyPowerCP:|r As a Paladin, use /pp for the blessing grid (it now has the hover player pop-out). /rpc assign opens the assignment panel; /rpc sync re-syncs assignments; /rpc options opens the settings (right-click the minimap icon); /rpc legacy opens the classic PallyPower frame; /rpc icon changes the minimap icon.")
        return
    end
    if msg == "reset" then
        RallyPowerCP_ResetBarPosition()
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00RallyPowerCP:|r Bar position reset.")
        return
    end
    RallyPowerCP_ToggleBar()
end

-- Shared accessor for the class modules / strip engine.
function RallyPowerCP.IsTestMode()
    return RallyPowerCP_Settings.testMode and true or false
end
