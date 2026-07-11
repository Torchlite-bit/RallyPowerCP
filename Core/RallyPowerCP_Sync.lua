--=============================================================================
-- RallyPowerCP_Sync.lua  -  the RPCX sync protocol (Assignment & Sync step 2)
--
-- Broadcasts the totem / duty / raid-buff-grid assignments the model stores
-- (RallyPowerCP_Assign) to the raid, receives and stores others', and gates
-- edits by permission. BLESSINGS ARE UNTOUCHED - they keep riding the legacy
-- PLPWR channel through the engine's own SELF/ASSIGN/AASSIGN/... messages;
-- RPCX carries only what PallyPower never knew about.
--
-- Grammar (docs\DESIGN_SYNC.md): space-delimited head, ";"-delimited payload
--   <v> REQ
--   <v> BLK <caster> <seq> <payload>      payload = cTOKEN;t<wids>;d<entries>;b<pairs>
--   <v> CLR <caster>
-- Wids never cross the wire as spell names (Turtle-rename safe); unknown wids
-- are skipped, not errored (forward-compat). Permission mirrors PallyPower:
-- accept a block for CASTER from SENDER iff sender==caster or sender is
-- lead/assist. Conflicts resolve arrival-order last-writer-wins, exactly as
-- PallyPower resolves two people editing one blessing.
--
-- 1.12 rules: implicit event/arg1..arg4, OnUpdate accumulator, Lua 5.0
-- (table.getn/concat, string.gfind not gmatch, no #/select/%).
--=============================================================================

local A = RallyPowerCP.Assign
if not A then return end        -- Assign.lua loads first; defensive

local PREFIX      = "RPCX"
local PROTO_V     = 1
local FLUSH_DELAY = 0.5         -- debounce a burst of edits into one send
local REQ_THROTTLE = 3         -- min seconds between our own REQ storms
local MAX_LEN     = 250         -- addon-message payload ceiling (warn only)

local applyingRemote = false    -- true while installing a received block
local dirty = {}                -- set of caster names pending broadcast
local freeDirty = false         -- Free Assignment flag changed, pending send
local flushAccum = 0
local lastReq = -100

--------------------------------------------------------------------------
-- helpers + lazy catalog reverse maps (catalogs register at class-module
-- load, which is before this file, but building lazily is robust either way)
--------------------------------------------------------------------------

local function Me() return UnitName("player") end

local function ClassOf(name)
    if name == Me() then local _, c = UnitClass("player"); return c end
    local n = GetNumRaidMembers()
    if n > 0 then
        for i = 1, n do
            if UnitName("raid" .. i) == name then local _, c = UnitClass("raid" .. i); return c end
        end
        return nil
    end
    for i = 1, GetNumPartyMembers() do
        if UnitName("party" .. i) == name then local _, c = UnitClass("party" .. i); return c end
    end
    return nil
end

local totemByWid, dutyByWid
local function BuildMaps()
    totemByWid = {}
    for element, list in pairs(A.totems or {}) do
        for i = 1, table.getn(list) do
            local t = list[i]
            if t.wid then totemByWid[t.wid] = { element = element, name = t.name } end
        end
    end
    dutyByWid = {}
    for key, def in pairs(A.duties or {}) do
        if def.wid then dutyByWid[def.wid] = def end
    end
end

local function TotemByWid() if not totemByWid then BuildMaps() end return totemByWid end
local function DutyByWid()  if not dutyByWid  then BuildMaps() end return dutyByWid  end

local function TotemWid(element, name)
    local list = A.totems and A.totems[element]
    if not list then return nil end
    for i = 1, table.getn(list) do
        if list[i].name == name then return list[i].wid end
    end
    return nil
end

local function BuffCatalog(token)
    local m = RallyPowerCP.classes and RallyPowerCP.classes[token]
    return (m and m.buffs) or {}
end

-- buff index into a class catalog, matched on name-or-group (the same value
-- the class-buff domain stores)
local function BuffIndex(cat, value)
    for i = 1, table.getn(cat) do
        if (cat[i].name == value) or (cat[i].group == value) then return i end
    end
    return nil
end

--------------------------------------------------------------------------
-- permission (PallyPower-faithful): who may assert a block for a caster
--------------------------------------------------------------------------

local function LeaderLike(name)
    return PallyPower_CheckRaidLeader and PallyPower_CheckRaidLeader(name)
end

local function CanAccept(sender, caster)
    if sender == caster then return true end
    -- a leader may set anyone's block; Free Assignment opens it to everyone
    return (LeaderLike(sender) and true or false) or A.GetFreeAssign()
end

-- may I broadcast this caster's block? (my own always; others' if I lead -
-- A.IAmLead is party-leader-safe, unlike PallyPower_CheckRaidLeader(Me),
-- which never matches the player's own party leadership). Preview-raid rows
-- never hit the wire.
local function MayAssert(caster)
    if RallyPowerCP.PreviewNames and RallyPowerCP.PreviewNames[caster] then return false end
    return caster == Me() or A.IAmLead()
end

--------------------------------------------------------------------------
-- serialize / deserialize one caster block
--------------------------------------------------------------------------

local function SerializeBlock(name)
    local c = A.GetCaster(name)
    if not c then return nil end
    local token = c.class or ClassOf(name)
    local parts = {}
    if token then table.insert(parts, "c" .. token) end

    if c.totem then
        local wids = {}
        for element, tname in pairs(c.totem) do
            if element ~= "party" and tname then
                local wid = TotemWid(element, tname)
                if wid then table.insert(wids, wid) end
            end
        end
        if table.getn(wids) > 0 then table.insert(parts, "t" .. table.concat(wids, ",")) end
    end

    if c.duty then
        local ents = {}
        for key, val in pairs(c.duty) do
            local def = A.duties and A.duties[key]
            if def and def.wid and val then
                local e = tostring(def.wid)
                if type(val) == "string" then e = e .. "=" .. val end  -- name or @ROLE
                table.insert(ents, e)
            end
        end
        if table.getn(ents) > 0 then table.insert(parts, "d" .. table.concat(ents, ",")) end
    end

    if c.cbuff and token then
        local cat = BuffCatalog(token)
        local ents = {}
        for classID, value in pairs(c.cbuff) do
            local idx = BuffIndex(cat, value)
            if idx then table.insert(ents, classID .. "." .. idx) end
        end
        if table.getn(ents) > 0 then table.insert(parts, "b" .. table.concat(ents, ",")) end
    end

    return table.concat(parts, ";")
end

local function DeserializeBlock(caster, seq, payload)
    local block = { seq = tonumber(seq) or 0 }
    local rawB = nil
    for section in string.gfind(payload or "", "[^;]+") do
        local tag = string.sub(section, 1, 1)
        local data = string.sub(section, 2)
        if tag == "c" then
            block.class = data
        elseif tag == "t" then
            block.totem = block.totem or {}
            for widS in string.gfind(data, "[^,]+") do
                local info = TotemByWid()[tonumber(widS)]
                if info then block.totem[info.element] = info.name end
            end
        elseif tag == "d" then
            block.duty = block.duty or {}
            for ent in string.gfind(data, "[^,]+") do
                local _, _, widS, tgt = string.find(ent, "^(%d+)=?(.*)$")
                local def = widS and DutyByWid()[tonumber(widS)]
                if def then
                    if tgt == nil or tgt == "" then block.duty[def.key] = true
                    else block.duty[def.key] = tgt end
                end
            end
        elseif tag == "b" then
            rawB = data                       -- resolved after class is known
        end
    end
    local token = block.class or ClassOf(caster)
    block.class = token
    if rawB and token then
        local cat = BuffCatalog(token)
        block.cbuff = {}
        for ent in string.gfind(rawB, "[^,]+") do
            local _, _, cidS, idxS = string.find(ent, "^(%d+)%.(%d+)$")
            local cid = tonumber(cidS)
            local bd = cat and idxS and cat[tonumber(idxS)]
            if cid ~= nil and bd then block.cbuff[cid] = bd.name or bd.group end
        end
    end
    return block
end

--------------------------------------------------------------------------
-- send
--------------------------------------------------------------------------

local function RawSend(msg)
    -- test mode is a local sandbox: never broadcast (preview edits, and even
    -- real ones, stay off the wire so a tester can't pollute a live raid)
    if RallyPowerCP.IsTestMode and RallyPowerCP.IsTestMode() then return end
    if string.len(msg) > MAX_LEN then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff5555RallyPowerCP:|r assignment too large to "
            .. "sync in one message (" .. string.len(msg) .. " chars) - some of it may not "
            .. "reach others until chunking lands.")
    end
    if GetNumRaidMembers() > 0 then
        SendAddonMessage(PREFIX, msg, "RAID", Me())
    elseif GetNumPartyMembers() > 0 then
        SendAddonMessage(PREFIX, msg, "PARTY", Me())
    end
    -- solo: nothing to send
end

local function SendBlock(name)
    local payload = SerializeBlock(name)
    if not payload or payload == "" then return end
    local c = A.GetCaster(name)
    local seq = (c and c.seq) or 0
    RawSend(PROTO_V .. " BLK " .. name .. " " .. seq .. " " .. payload)
end

local function SendREQ()
    RawSend(PROTO_V .. " REQ")
end

--------------------------------------------------------------------------
-- dirty set + debounced flush
--------------------------------------------------------------------------

local function MarkDirty(caster)
    if not caster then return end
    if not MayAssert(caster) then return end
    dirty[caster] = true
end

-- queue every block I'm authoritative for (my own; all, if I lead) - used on
-- login, roster change, and as the reply to a REQ
local function MarkAuthoritativeDirty()
    local iLead = A.IAmLead()
    for name in pairs(RallyPowerCP_Assign.casters) do
        if name == Me() or iLead then dirty[name] = true end
    end
    dirty[Me()] = true          -- always assert myself, even with an empty block skipped later
    if iLead then freeDirty = true end   -- announce the Free Assignment state
end

local function Flush()
    -- Free Assignment: only a leader announces it (a caster block skip below
    -- still lets FA go out on its own)
    if freeDirty and A.IAmLead() then
        RawSend(PROTO_V .. " FA " .. (A.GetFreeAssign() and "1" or "0"))
    end
    freeDirty = false
    local any = false
    for name in pairs(dirty) do any = true; break end
    if not any then return end
    local pending = dirty
    dirty = {}
    for name in pairs(pending) do
        if MayAssert(name) then SendBlock(name) end
    end
end

--------------------------------------------------------------------------
-- receive
--------------------------------------------------------------------------

local function Receive(sender, msg)
    if sender == Me() then return end            -- our own echo
    local tok = {}
    for w in string.gfind(msg, "%S+") do table.insert(tok, w) end
    if tonumber(tok[1]) ~= PROTO_V then return end   -- version we don't speak
    local cmd = tok[2]

    if cmd == "REQ" then
        MarkAuthoritativeDirty()                 -- reply on the next flush tick
        return
    end

    if cmd == "BLK" then
        local caster, seq, payload = tok[3], tok[4], tok[5]
        if not caster then return end
        if not CanAccept(sender, caster) then return end
        local block = DeserializeBlock(caster, seq, payload)
        applyingRemote = true
        A.ApplyRemoteBlock(caster, block)
        applyingRemote = false
        return
    end

    if cmd == "CLR" then
        local caster = tok[3]
        if caster and CanAccept(sender, caster) then
            applyingRemote = true
            A.RemoveRemoteBlock(caster)
            applyingRemote = false
        end
        return
    end

    if cmd == "FA" then
        -- only a leader may set the raid-wide Free Assignment flag
        if LeaderLike(sender) then
            applyingRemote = true
            A.ApplyFreeAssign(tok[3] == "1")
            applyingRemote = false
        end
        return
    end
end

--------------------------------------------------------------------------
-- local-edit hook: broadcast the changed caster (guarded against the echo
-- of remote applies, and against the domains that ride PLPWR instead)
--------------------------------------------------------------------------

A.Subscribe(function(domain, caster)
    if applyingRemote then return end
    if domain == "free" then
        freeDirty = true          -- leader flipped Free Assignment; broadcast it
        return
    end
    if domain == "totem" or domain == "duty" or domain == "cbuff" then
        MarkDirty(caster)
    end
end)

--------------------------------------------------------------------------
-- request-on-join / roster maintenance
--------------------------------------------------------------------------

local function RequestSync()
    local now = GetTime()
    if now - lastReq < REQ_THROTTLE then return end
    lastReq = now
    SendREQ()                    -- others reply with their blocks
    MarkAuthoritativeDirty()     -- and I push mine to them
end

local f = CreateFrame("Frame")
f:RegisterEvent("CHAT_MSG_ADDON")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("RAID_ROSTER_UPDATE")
f:RegisterEvent("PARTY_MEMBERS_CHANGED")
f:SetScript("OnEvent", function()
    if event == "CHAT_MSG_ADDON" then
        if arg1 == PREFIX and (arg3 == "RAID" or arg3 == "PARTY") then
            local ok, err = pcall(Receive, arg4, arg2)
            if not ok then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff5555RallyPowerCP error:|r "
                    .. tostring(err) .. " |cffaaaaaa(sync receive)|r")
            end
        end
    else
        -- entering world / roster change: drop leavers, then reconcile
        if A.PruneToRoster then A.PruneToRoster() end
        RequestSync()
    end
end)

f:SetScript("OnUpdate", function()
    flushAccum = flushAccum + (arg1 or 0)
    if flushAccum < FLUSH_DELAY then return end
    flushAccum = 0
    local ok, err = pcall(Flush)
    if not ok then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff5555RallyPowerCP error:|r "
            .. tostring(err) .. " |cffaaaaaa(sync flush)|r")
    end
end)

-- Exposed for /rpc sync debugging (force a full re-broadcast + request).
function RallyPowerCP_SyncNow()
    lastReq = -100
    RequestSync()
    DEFAULT_CHAT_FRAME:AddMessage("|cffffff00RallyPowerCP:|r assignment sync requested.")
end
