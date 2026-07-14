--=============================================================================
-- RallyPowerCP_Assign.lua  -  the shared assignment data model
-- (docs\DESIGN_ASSIGNMENTS.md - step 1 of the Assignment & Sync milestone)
--
-- One caster-major store covering the totem and duty domains, with the
-- blessing domain delegated to the UNTOUCHED PallyPower tables (locked
-- interop decision: no blessing data is ever copied out of the legacy
-- engine). The sync protocol (step 2) serializes caster blocks from here;
-- the assignment panel (step 3) renders them; the strips already read their
-- own row ("effective selection" = my assignment first, my local preference
-- second).
--
--   RallyPowerCP_Assign = {                 -- SavedVariablePerCharacter
--     v = 1,
--     casters = {
--       ["Stormtide"] = {
--         class = "SHAMAN",                 -- English token, set on write
--         seq   = 12,                       -- bumped on every local edit
--                                           -- (reserved: sync LWW ordering)
--         totem = { Earth = "Strength of Earth Totem", party = 2 },
--         duty  = { SUNDER = true, SOULSTONE = "Seraphine", FEARWARD = "@TANK" },
--       },
--     },
--   }
--
-- Duty values are scalars: true (untargeted - kill-target debuffs, raid
-- buffs), "PlayerName" (Soulstone, Innervate), or "@ROLE" ("@MT"/"@MA"/...,
-- resolved at cast time through the role tables; player names can never
-- contain '@'). What a duty key MEANS lives in the catalog the class modules
-- register at load (RegisterDuty); totem options come from Class_Shaman
-- (RegisterTotems). Catalog `wid`s are the stable numeric wire ids reserved
-- for the future RPCX protocol: append-only, never renumbered, never reused.
--
-- Runtime status ("actually up", vs "assigned") is the separate, NEVER-saved
-- mirror RallyPowerCP.AssignStatus with the same keying; the strip modules
-- write their own cast-derived timers through it today, and sync (step 2)
-- fills other casters' entries from broadcast cast times.
--=============================================================================

RallyPowerCP_Assign = RallyPowerCP_Assign or {}
if not RallyPowerCP_Assign.v then RallyPowerCP_Assign.v = 1 end
RallyPowerCP_Assign.casters = RallyPowerCP_Assign.casters or {}

RallyPowerCP.AssignStatus = {}   -- [caster][domain][slot] = { expires=, ... }

local A = {}
RallyPowerCP.Assign = A

--------------------------------------------------------------------------
-- catalogs (registered by the class modules at load; pure static data)
--------------------------------------------------------------------------

A.duties = {}          -- [key] = { key, wid, class, tab, spell, target, multi, dur }
A.dutyOrder = {}       -- keys in registration order (the panel iterates this)
A.totems = {}          -- [element] = { { name=, wid=, dur= }, ... }
A.elements = {}        -- ordered element keys

function A.RegisterDuty(def)
    if not def or not def.key or A.duties[def.key] then return end
    A.duties[def.key] = def
    table.insert(A.dutyOrder, def.key)
end

function A.RegisterTotems(element, list)
    if A.totems[element] then return end
    A.totems[element] = list
    table.insert(A.elements, element)
end

--------------------------------------------------------------------------
-- change notification (the panel subscribes; strips poll their own tick)
--------------------------------------------------------------------------

local listeners = {}
function A.Subscribe(fn) table.insert(listeners, fn) end

local function Notify(domain, caster)
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn, domain, caster)
        if not ok then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff5555RallyPowerCP error:|r "
                .. tostring(err) .. " |cffaaaaaa(assignment listener)|r")
        end
    end
end

--------------------------------------------------------------------------
-- store internals
--------------------------------------------------------------------------

-- English class token for a group member (nil when not resolvable).
local function ClassOf(name)
    if name == UnitName("player") then
        local _, cls = UnitClass("player")
        return cls
    end
    local n = GetNumRaidMembers()
    if n > 0 then
        for i = 1, n do
            if UnitName("raid" .. i) == name then
                local _, cls = UnitClass("raid" .. i)
                return cls
            end
        end
        return nil
    end
    for i = 1, GetNumPartyMembers() do
        if UnitName("party" .. i) == name then
            local _, cls = UnitClass("party" .. i)
            return cls
        end
    end
    return nil
end

local function Block(name, create)
    local c = RallyPowerCP_Assign.casters[name]
    if not c and create then
        c = { seq = 0 }
        RallyPowerCP_Assign.casters[name] = c
    end
    return c
end

local function Touch(c, name)
    c.seq = (c.seq or 0) + 1
    c.class = c.class or ClassOf(name)
end

--------------------------------------------------------------------------
-- permissions: self, or lead/assist. This is the LOCAL edit rule (strip
-- self-assign and, later, the panel); acceptance of remote writes - and the
-- Free Assignment flag - is the sync layer's job (step 2), exactly as in
-- PallyPower's ASSIGN handling.
--------------------------------------------------------------------------

-- Am I (the player) raid lead / assist / party leader? TRUTHY-safe: the
-- 1.12 Is*Leader() API returns 1-or-nil on some clients and true-or-false on
-- others, so we never compare == 1 (PallyPower treats them as booleans too,
-- e.g. PallyPower_CanControl). Solo counts as leading a party of one, and
-- test mode always leads (the preview raid must be fully editable).
function A.IAmLead()
    if GetNumRaidMembers() > 0 then
        return (IsRaidLeader() or IsRaidOfficer()) and true or false
    end
    if GetNumPartyMembers() > 0 then
        return IsPartyLeader() and true or false
    end
    return true   -- solo: you lead your party of one (test mode included, so
                  -- the preview raid is editable; grouped test respects the
                  -- real leader so a party simulates lead/member roles)
end

-- Best-effort English class token for a caster (block cache -> roster ->
-- preview raid). nil when we genuinely can't tell (offline/out-of-range).
local function ClassKnown(name)
    local c = RallyPowerCP_Assign.casters[name]
    if c and c.class then return c.class end
    local cls = ClassOf(name)
    if cls then return cls end
    if RallyPowerCP.PreviewNames then return RallyPowerCP.PreviewNames[name] end
    return nil
end

-- Free Assignment: a raid-wide flag the LEADER controls (synced over RPCX).
-- When on, any member may edit any row - so the leader can let people spread
-- the assignments out themselves. Mirrors PallyPower's free-assign intent.
function A.GetFreeAssign()
    return RallyPowerCP_Assign.freeAssign and true or false
end

-- Only a leader may flip it locally; the sync layer relays a remote leader's
-- flip through A.ApplyFreeAssign (no gate - the sender was already checked).
function A.SetFreeAssign(on)
    if not A.IAmLead() then return false end
    RallyPowerCP_Assign.freeAssign = on and true or false
    Notify("free", nil)
    return true
end

function A.ApplyFreeAssign(on)
    RallyPowerCP_Assign.freeAssign = on and true or false
    Notify("free", nil)
end

function A.CanEdit(editor, caster)
    if editor == caster then return true end
    if editor == UnitName("player") then
        return A.IAmLead() or A.GetFreeAssign()
    end
    return false
end

local function Editable(caster)
    return A.CanEdit(UnitName("player"), caster)
end

--------------------------------------------------------------------------
-- totem domain: shaman x element -> totem spell name, plus a covered party
--------------------------------------------------------------------------

function A.SetTotem(caster, element, totemName)
    if not Editable(caster) then return false end
    local c = Block(caster, true)
    c.totem = c.totem or {}
    c.totem[element] = totemName
    Touch(c, caster)
    Notify("totem", caster)
    return true
end

function A.GetTotem(caster, element)
    local c = Block(caster)
    return c and c.totem and c.totem[element]
end

-- party: 1-8 = the group this shaman covers; nil = their own subgroup
function A.SetTotemParty(caster, party)
    if not Editable(caster) then return false end
    local c = Block(caster, true)
    c.totem = c.totem or {}
    c.totem.party = party
    Touch(c, caster)
    Notify("totem", caster)
    return true
end

function A.GetTotemParty(caster)
    local c = Block(caster)
    return c and c.totem and c.totem.party
end

--------------------------------------------------------------------------
-- duty domain: dutyKey -> true | "PlayerName" | "@ROLE"
--------------------------------------------------------------------------

function A.SetDuty(caster, dutyKey, value)
    local def = A.duties[dutyKey]
    if not def then return false end
    if not Editable(caster) then return false end
    -- a duty may only be held by a caster of its class (a priest can't take
    -- Sunder Armor). Enforced only when the caster's class is known, and only
    -- for assignments - clearing (value == nil) is always allowed.
    if value ~= nil and def.class then
        local cls = ClassKnown(caster)
        if cls and cls ~= def.class then return false end
    end
    if value ~= nil and def.target == "none" then value = true end
    local c = Block(caster, true)
    c.duty = c.duty or {}
    c.duty[dutyKey] = value
    Touch(c, caster)
    Notify("duty", caster)
    return true
end

function A.ClearDuty(caster, dutyKey)
    return A.SetDuty(caster, dutyKey, nil)
end

--------------------------------------------------------------------------
-- class-buff domain (blessing-shaped): caster x legacy class id 0-9 ->
-- buff spell name. The catalog is the caster class's own M.buffs list
-- (RallyPowerCP.classes[token].buffs); the class-buff strips read their
-- own row through this, exactly like blessings drive the paladin bar.
--------------------------------------------------------------------------

function A.SetClassBuff(caster, classID, buffName)
    if not Editable(caster) then return false end
    local c = Block(caster, true)
    c.cbuff = c.cbuff or {}
    c.cbuff[classID] = buffName
    Touch(c, caster)
    Notify("cbuff", caster)
    return true
end

function A.GetClassBuff(caster, classID)
    local c = Block(caster)
    return c and c.cbuff and c.cbuff[classID]
end

function A.GetDuty(caster, dutyKey)
    local c = Block(caster)
    return c and c.duty and c.duty[dutyKey]
end

-- Whole caster block (the sync unit; treat as read-only outside this file).
function A.GetCaster(name)
    return Block(name)
end

--------------------------------------------------------------------------
-- derived views (rebuilt on demand - raid-size loops are trivial next to
-- the 1-second roster scan; never stored, never a second source of truth)
--------------------------------------------------------------------------

-- duty-major view: who holds a duty -> array of { caster =, target = }
function A.GetDutyCasters(dutyKey)
    local out = {}
    for name, c in pairs(RallyPowerCP_Assign.casters) do
        local v = c.duty and c.duty[dutyKey]
        if v then table.insert(out, { caster = name, target = v }) end
    end
    return out
end

-- Which subgroup a member is in (raid 1-8; party/solo counts as group 1).
local function SubgroupOf(name)
    local n = GetNumRaidMembers()
    if n > 0 then
        for i = 1, n do
            local rname, _, subgroup = GetRaidRosterInfo(i)
            if rname == name then return subgroup end
        end
    end
    return 1
end

-- [party][element] = array of { caster =, totem = }; an explicit party
-- assignment wins, otherwise the shaman covers their own subgroup.
function A.GetTotemCoverage()
    local cov = {}
    for name, c in pairs(RallyPowerCP_Assign.casters) do
        if c.totem then
            local party = c.totem.party or SubgroupOf(name)
            for i = 1, table.getn(A.elements) do
                local el = A.elements[i]
                local tn = c.totem[el]
                if tn then
                    cov[party] = cov[party] or {}
                    cov[party][el] = cov[party][el] or {}
                    table.insert(cov[party][el], { caster = name, totem = tn })
                end
            end
        end
    end
    return cov
end

--------------------------------------------------------------------------
-- roster pruning (mirrors PallyPower: leavers drop out of the plan; your
-- own block always survives, so a leader's plan persists across relogs)
--------------------------------------------------------------------------

function A.PruneToRoster()
    local present = {}
    present[UnitName("player")] = true
    local n = GetNumRaidMembers()
    if n > 0 then
        for i = 1, n do
            local rname = GetRaidRosterInfo(i)
            if rname then present[rname] = true end
        end
    else
        for i = 1, GetNumPartyMembers() do
            local pn = UnitName("party" .. i)
            if pn then present[pn] = true end
        end
    end
    -- while test mode is on, the preview raid's rows survive a roster change
    -- so the panel stays usable in a party (they never touch the wire either)
    local testing = RallyPowerCP.IsTestMode and RallyPowerCP.IsTestMode()
    local preview = RallyPowerCP.PreviewNames
    local kill = {}
    for name in pairs(RallyPowerCP_Assign.casters) do
        if not present[name] and not (testing and preview and preview[name]) then
            table.insert(kill, name)
        end
    end
    for _, name in ipairs(kill) do
        RallyPowerCP_Assign.casters[name] = nil
        RallyPowerCP.AssignStatus[name] = nil
    end
    -- heal duties held by a caster of the wrong class (stale data from before
    -- class-matching was enforced), where the class is known
    local healed = false
    for name, c in pairs(RallyPowerCP_Assign.casters) do
        if c.duty then
            local cls = ClassKnown(name)
            if cls then
                for key, val in pairs(c.duty) do
                    local def = A.duties[key]
                    if val and def and def.class and def.class ~= cls then
                        c.duty[key] = nil
                        healed = true
                    end
                end
            end
        end
    end
    if table.getn(kill) > 0 or healed then Notify("prune", nil) end
end

--------------------------------------------------------------------------
-- blessing domain: ADAPTER over the untouched PallyPower engine. Reads and
-- writes go straight to the legacy tables and out over the byte-identical
-- PLPWR messages via the engine's own send path.
--------------------------------------------------------------------------

function A.GetBlessing(pally, classID)
    local t = PallyPower_Assignments and PallyPower_Assignments[pally]
    local v = t and t[classID]
    if v == nil then return -1 end
    return v
end

function A.SetBlessing(pally, classID, bid)
    if not PallyPower_Assignments then return false end
    if not Editable(pally) then return false end
    PallyPower_Assignments[pally] = PallyPower_Assignments[pally] or {}
    PallyPower_Assignments[pally][classID] = bid
    if PallyPower_SendMessage then
        PallyPower_SendMessage("ASSIGN " .. pally .. " " .. classID .. " " .. bid)
    end
    Notify("blessings", pally)
    return true
end

function A.GetNormalBlessing(pally, classID, tname)
    if GetNormalBlessings then
        return GetNormalBlessings(pally, classID, tname)
    end
    return -1
end

function A.SetNormalBlessing(pally, classID, tname, bid)
    if not SetNormalBlessings then return false end
    if not Editable(pally) then return false end
    SetNormalBlessings(pally, classID, tname, bid)
    if PallyPower_SendMessage then
        PallyPower_SendMessage("NASSIGN " .. pally .. " " .. classID .. " " .. tname .. " " .. bid)
    end
    Notify("blessings", pally)
    return true
end

--------------------------------------------------------------------------
-- role domain: ADAPTER over PallyPower's own Tanks/Healers tables. Reusing
-- them (not a parallel store) means roles are shared byte-for-byte with
-- stock PallyPower over the legacy PLPWR channel AND drive its own tank
-- logic (e.g. no Salvation on a marked tank). Nothing role-related rides
-- RPCX. A player marked here shows up in a stock-PallyPower user's raid and
-- vice versa.
--------------------------------------------------------------------------

-- Preview-raid roles/overrides live here (never saved, never broadcast), so
-- a solo tester can mark preview tanks without polluting the real
-- PallyPower_Tanks table or the PLPWR wire.
local previewRoles = {}          -- [name] = "TANK" | "HEALER"
local previewTankBless = {}      -- [name][classID] = bid

local function IsPreview(name)
    return RallyPowerCP.PreviewNames and RallyPowerCP.PreviewNames[name]
end

function A.GetRole(name)
    if IsPreview(name) then return previewRoles[name] end
    if PallyPower_Tanks and PallyPower_Tanks[name] then return "TANK" end
    if PallyPower_Healers and PallyPower_Healers[name] then return "HEALER" end
    return nil
end

-- role = "TANK" | "HEALER" | nil. Leader-gated (roles are a raid-wide plan);
-- sends the byte-identical TANK/HEALER/CLTNK/CLHLR messages PallyPower uses.
function A.SetRole(name, role)
    if not (A.IAmLead() or A.GetFreeAssign()) then return false end
    -- leaving the tank role also drops the tank's blessing override (we
    -- present it as "the tank's blessing"), so an ex-tank stops overriding
    -- their class blessing
    if role ~= "TANK" and A.GetRole(name) == "TANK" then
        local tok = ClassKnown(name)
        local cid = tok and RallyPowerCP.Token2ClassID and RallyPowerCP.Token2ClassID[tok]
        if cid then A.SetTankBlessing(name, cid, -1) end
    end
    if IsPreview(name) then
        previewRoles[name] = role     -- sandbox: no legacy table, no wire
        Notify("role", name)
        return true
    end
    PallyPower_Tanks = PallyPower_Tanks or {}
    PallyPower_Healers = PallyPower_Healers or {}
    local wasTank, wasHealer = PallyPower_Tanks[name], PallyPower_Healers[name]
    PallyPower_Tanks[name] = nil
    PallyPower_Healers[name] = nil
    local send = PallyPower_SendMessage
    if role == "TANK" then
        PallyPower_Tanks[name] = true
        if send then send("TANK " .. name) end
    elseif role == "HEALER" then
        PallyPower_Healers[name] = true
        if send then send("HEALER " .. name) end
    else
        if wasTank and send then send("CLTNK " .. name) end
        if wasHealer and send then send("CLHLR " .. name) end
    end
    Notify("role", name)
    return true
end

--------------------------------------------------------------------------
-- tank blessing override: the blessing a specific player (tank) gets instead
-- of their class default. This is PallyPower's per-player NormalAssignments,
-- byte-identical NASSIGN. Read from any known paladin; write to every paladin
-- the editor controls, so the tank gets it whoever buffs them.
--------------------------------------------------------------------------

function A.GetTankBlessing(tname, classID)
    if IsPreview(tname) then
        local t = previewTankBless[tname]
        return (t and t[classID]) or -1
    end
    if not AllPallys then return -1 end
    for pally in pairs(AllPallys) do
        local bid = A.GetNormalBlessing(pally, classID, tname)
        if bid and bid ~= -1 then return bid end
    end
    return -1
end

-- Can any known paladin actually cast blessing `bid`? (the override only
-- fires when the paladin has that blessing - PallyPower.lua line 3232 - so a
-- non-castable pick silently drops the tank's blessing.)
function A.TankBlessingCastable(bid)
    if bid == -1 then return true end
    if not AllPallys then return false end
    for pally in pairs(AllPallys) do
        if PallyPower_CanBuff and PallyPower_CanBuff(pally, bid) then return true end
    end
    return false
end

function A.SetTankBlessing(tname, classID, bid)
    if IsPreview(tname) then
        previewTankBless[tname] = previewTankBless[tname] or {}
        previewTankBless[tname][classID] = bid   -- sandbox: no legacy, no wire
        Notify("blessings", tname)
        return true
    end
    if not AllPallys then return false end
    local any = false
    for pally in pairs(AllPallys) do
        -- only set the override on paladins that can cast it (clear always);
        -- a non-castable override would just drop the tank's blessing
        if bid == -1 or (PallyPower_CanBuff and PallyPower_CanBuff(pally, bid)) then
            if A.SetNormalBlessing(pally, classID, tname, bid) then any = true end
        end
    end
    if any then Notify("blessings", tname) end
    return any
end

--------------------------------------------------------------------------
-- sync bridge (step 2): the RPCX layer decodes a remote caster block and
-- installs it here. Whole-block REPLACE (the sender is authoritative for
-- that caster), then the same Notify the panel already listens to. Kept in
-- this file so Notify stays private; the sync module owns the wire.
--------------------------------------------------------------------------

function A.ApplyRemoteBlock(caster, block)
    if not caster or not block then return end
    block.class = block.class or ClassOf(caster)
    RallyPowerCP_Assign.casters[caster] = block
    Notify("sync", caster)
end

function A.RemoveRemoteBlock(caster)
    if not caster then return end
    RallyPowerCP_Assign.casters[caster] = nil
    RallyPowerCP.AssignStatus[caster] = nil
    Notify("sync", caster)
end

--------------------------------------------------------------------------
-- runtime status mirror (assigned vs actually-up; GetTime-based, never
-- saved). info tables carry { expires = <GetTime deadline>, name=/target= }.
--------------------------------------------------------------------------

function A.SetStatus(caster, domain, slot, info)
    local S = RallyPowerCP.AssignStatus
    if info == nil then
        local c = S[caster]
        if c and c[domain] then c[domain][slot] = nil end
        return
    end
    S[caster] = S[caster] or {}
    S[caster][domain] = S[caster][domain] or {}
    S[caster][domain][slot] = info
end

function A.GetStatus(caster, domain, slot)
    local c = RallyPowerCP.AssignStatus[caster]
    local d = c and c[domain]
    return d and d[slot]
end
