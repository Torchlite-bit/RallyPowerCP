--=============================================================================
-- RallyPowerCP_AssignPanel.lua  -  "Who covers what" (milestone step 3)
--
-- The raid-leader coordination grid, styled after
-- docs\RallyPowerCP_assignment_concept.html: dark gold-framed panel, five
-- tabs, class-coloured caster rows, chip cells, a coverage line, and the
-- classic PallyPower bottom-button row (Refresh / Clear / Options / Reset
-- Position / Presets).
--
--   Blessings   LIVE against the legacy PallyPower engine: rows are the
--               paladins known from PLPWR SELF broadcasts (AllPallys), cells
--               cycle through PallyPower_PerformCycle/Backwards - the SAME
--               functions the /pp grid uses - so every edit writes the legacy
--               tables and sends the byte-identical ASSIGN message. Paladins
--               on stock PallyPower/PallyPowerTW interoperate unchanged.
--   Totems      shaman x element grid + auto group, over RallyPowerCP_Assign.
--   Raid Buffs   caster x class buff grid (Priest/Mage/Druid), over the model.
--   Debuffs / Utility
--               duty cards from the module-declared catalog: click cycles
--               who's responsible. All non-blessing tabs sync over RPCX
--               (Core\RallyPowerCP_Sync.lua) to other RallyPowerCP users.
--
-- TEST MODE seats a full fake 40-man raid of lore characters (every class,
-- with specs) so each tab is exercisable solo. Fake blessing edits stay in a
-- session-only table (the legacy tables and the PLPWR wire are never touched
-- for fake names); fake totem/duty rows live in the normal store and are
-- swept by PruneToRoster when test mode turns off.
--
-- Entry points: right-click a strip's title area, right-click the paladin
-- buff bar (grafted below - PallyPower.lua stays untouched), or /rpc assign.
-- 1.12 rules: pooled rows (frames can't be deleted), implicit this/arg1,
-- Lua 5.0 (table.getn, no #/gmatch/select/%).
--=============================================================================

RallyPowerCP_Settings = RallyPowerCP_Settings or {}

local A = RallyPowerCP.Assign   -- loads before this file (TOC order)

--------------------------------------------------------------------------
-- theme (colors lifted from the concept page)
--------------------------------------------------------------------------

local FRAME_W, FRAME_H = 760, 680
local NAME_W   = 170         -- caster-name + skills column (blessings tab)
local ROW_H    = 40
local CELL_H   = 36          -- concept cells, scaled to fit ten columns
local MAX_ROWS = 8           -- pooled caster rows per grid tab
local DUTY_POOL = 16         -- pooled duty cards (2 columns x 8 rows)

local GOLD        = { 0.78, 0.67, 0.43 }
local GOLD_BRIGHT = { 0.96, 0.88, 0.66 }
local GOLD_DIM    = { 0.48, 0.40, 0.26 }
local INK         = { 0.91, 0.87, 0.78 }
local INK_DIM     = { 0.60, 0.56, 0.47 }
local INK_FAINT   = { 0.44, 0.40, 0.33 }
local OK_GREEN    = { 0.36, 0.88, 0.48 }
local GAP_RED     = { 1.00, 0.42, 0.42 }

local CLASS_RGB = {
    WARRIOR = { 0.78, 0.61, 0.43 }, PALADIN = { 0.96, 0.55, 0.73 },
    HUNTER  = { 0.67, 0.83, 0.45 }, ROGUE   = { 1.00, 0.96, 0.41 },
    PRIEST  = { 0.92, 0.92, 0.92 }, SHAMAN  = { 0.23, 0.63, 1.00 },
    MAGE    = { 0.41, 0.80, 0.94 }, WARLOCK = { 0.58, 0.51, 0.79 },
    DRUID   = { 1.00, 0.49, 0.04 },
}
local ECOL = {
    Earth = { 0.55, 0.35, 0.17 }, Fire = { 0.83, 0.41, 0.12 },
    Water = { 0.18, 0.50, 0.69 }, Air  = { 0.12, 0.62, 0.53 },
}

-- legacy blessing-grid class ids 0-9 (PallyPower's own column order) plus
-- the classic frame's two extra columns: 10 = Aura, 11 = Seal
local CLASS_LABEL = { [0] = "Warrior", "Rogue", "Priest", "Druid", "Paladin",
                      "Hunter", "Mage", "Warlock", "Shaman", "Pet",
                      "Aura", "Seal" }
local BLESS_COLS = 11        -- grid columns run 0..11
local FAKE_MAX = { [10] = 6, [11] = 5 }   -- preview cycle: 7 auras, 6 seals
local BLESS_ROWS = 6         -- blessing rows are tall (two skills strips)
local BLESS_ROW_H = 62

-- display order: Aura and Seal lead the grid (slots 1-2), then the classes
local COL_AT = { [0] = 10, [1] = 11 }
for c = 0, 9 do COL_AT[c + 2] = c end

-- vanilla max ranks (preview paladins only)
local BLESS_MAXRANK = { [0] = 6, 7, 1, 3, 1, 1 }
local AURA_MAXRANK  = { [0] = 7, 5, 1, 3, 3, 3, 1 }

-- aura ids shown in the skills row: Devotion, Retribution, Concentration,
-- Sanctity. The resistance auras are identical on every paladin (no ranks
-- worth comparing, no talents), so they'd only add noise.
local AURA_SHOW = { 0, 1, 2, 6 }

local PANEL_BD = {
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}
local CELL_BD = {
    bgFile   = "Interface\\AddOns\\RallyPowerCP\\Skins\\Smooth",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = false, tileSize = 8, edgeSize = 8,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
}

-- Icon paths are DISPLAY-ONLY fallbacks for duties of other classes (your own
-- class resolves from the spellbook first). Verify on Turtle; fix here.
local DUTY_ICONS = {
    FORTITUDE   = "Interface\\Icons\\Spell_Holy_WordFortitude",
    SPIRIT      = "Interface\\Icons\\Spell_Holy_DivineSpirit",
    SHADOWPROT  = "Interface\\Icons\\Spell_Shadow_AntiShadow",
    INTELLECT   = "Interface\\Icons\\Spell_Holy_MagicalSentry",
    MARK        = "Interface\\Icons\\Spell_Nature_Regeneration",
    THORNS      = "Interface\\Icons\\Spell_Nature_Thorns",
    SUNDER      = "Interface\\Icons\\Ability_Warrior_Sunder",
    THUNDERCLAP = "Interface\\Icons\\Spell_Nature_ThunderClap",
    DEMOSHOUT   = "Interface\\Icons\\Ability_Warrior_WarCry",
    EXPOSE      = "Interface\\Icons\\Ability_Warrior_Riposte",
    SCORCH      = "Interface\\Icons\\Spell_Fire_SoulBurn",
    CURSE_ELEMENTS     = "Interface\\Icons\\Spell_Shadow_ChillTouch",
    CURSE_SHADOW       = "Interface\\Icons\\Spell_Shadow_CurseOfAchimonde",
    CURSE_WEAKNESS     = "Interface\\Icons\\Spell_Shadow_CurseOfMannoroth",
    CURSE_RECKLESSNESS = "Interface\\Icons\\Spell_Shadow_UnholyStrength",
    CURSE_TONGUES      = "Interface\\Icons\\Spell_Shadow_CurseOfTounges",
    CURSE_AGONY        = "Interface\\Icons\\Spell_Shadow_CurseOfSargeras",
    CURSE_DOOM         = "Interface\\Icons\\Spell_Shadow_AuraOfDarkness",
    STING_SERPENT = "Interface\\Icons\\Ability_Hunter_Quickshot",
    STING_VIPER   = "Interface\\Icons\\Ability_Hunter_AimedShot",
    STING_SCORPID = "Interface\\Icons\\Ability_Hunter_CriticalShot",
    SOULSTONE   = "Interface\\Icons\\Spell_Shadow_SoulGem",
    FEARWARD    = "Interface\\Icons\\Spell_Holy_Excorcism",
    PWSHIELD    = "Interface\\Icons\\Spell_Holy_PowerWordShield",
    INNERVATE   = "Interface\\Icons\\Spell_Nature_Lightning",
}

-- Totem chip icons, keyed by full spell name. Display-only fallbacks for
-- shamans other than yourself (your own spellbook resolves first, exactly);
-- verify on Turtle and fix here if any icon looks wrong.
local TOTEM_ICONS = {
    ["Strength of Earth Totem"] = "Interface\\Icons\\Spell_Nature_EarthBindTotem",
    ["Stoneskin Totem"]         = "Interface\\Icons\\Spell_Nature_StoneSkinTotem",
    ["Tremor Totem"]            = "Interface\\Icons\\Spell_Nature_TremorTotem",
    ["Earthbind Totem"]         = "Interface\\Icons\\Spell_Nature_StrengthOfEarthTotem02",
    ["Stoneclaw Totem"]         = "Interface\\Icons\\Spell_Nature_StoneClawTotem",
    ["Searing Totem"]           = "Interface\\Icons\\Spell_Fire_SearingTotem",
    ["Magma Totem"]             = "Interface\\Icons\\Spell_Fire_SelfDestruct",
    ["Fire Nova Totem"]         = "Interface\\Icons\\Spell_Fire_SealOfFire",
    ["Flametongue Totem"]       = "Interface\\Icons\\Spell_Nature_GuardianWard",
    ["Frost Resistance Totem"]  = "Interface\\Icons\\Spell_FrostResistanceTotem_01",
    ["Mana Spring Totem"]       = "Interface\\Icons\\Spell_Nature_ManaRegenTotem",
    ["Healing Stream Totem"]    = "Interface\\Icons\\INV_Spear_04",
    ["Mana Tide Totem"]         = "Interface\\Icons\\Spell_Frost_SummonWaterElemental",
    ["Poison Cleansing Totem"]  = "Interface\\Icons\\Spell_Nature_PoisonCleansingTotem",
    ["Disease Cleansing Totem"] = "Interface\\Icons\\Spell_Nature_DiseaseCleansingTotem",
    ["Fire Resistance Totem"]   = "Interface\\Icons\\Spell_FireResistanceTotem_01",
    ["Windfury Totem"]          = "Interface\\Icons\\Spell_Nature_Windfury",
    ["Grace of Air Totem"]      = "Interface\\Icons\\Spell_Nature_InvisibilityTotem",
    ["Nature Resistance Totem"] = "Interface\\Icons\\Spell_Nature_NatureResistanceTotem",
    ["Windwall Totem"]          = "Interface\\Icons\\Spell_Nature_EarthBind",
    ["Grounding Totem"]         = "Interface\\Icons\\Spell_Nature_GroundingTotem",
    ["Sentry Totem"]            = "Interface\\Icons\\Spell_Nature_RemoveCurse",
    ["Tranquil Air Totem"]      = "Interface\\Icons\\Spell_Nature_Brilliance",
}

--------------------------------------------------------------------------
-- test-mode preview raid: 40 lore characters, every class and spec.
-- Session-only names; nothing about them ever reaches the PLPWR wire.
--------------------------------------------------------------------------

local ROSTER40 = {
    { "Varian",     "WARRIOR", "Protection" },
    { "Grommash",   "WARRIOR", "Fury" },
    { "Saurfang",   "WARRIOR", "Arms" },
    { "Muradin",    "WARRIOR", "Fury" },
    { "Broxigar",   "WARRIOR", "Arms" },
    { "Garrosh",    "WARRIOR", "Fury" },
    { "Valeera",    "ROGUE",   "Combat" },
    { "Garona",     "ROGUE",   "Subtlety" },
    { "Mathias",    "ROGUE",   "Assassination" },
    { "Vanessa",    "ROGUE",   "Combat" },
    { "Rexxar",     "HUNTER",  "Beast Mastery" },
    { "Alleria",    "HUNTER",  "Marksmanship" },
    { "Sylvanas",   "HUNTER",  "Marksmanship" },
    { "Halduron",   "HUNTER",  "Survival" },
    { "Jaina",      "MAGE",    "Frost" },
    { "Khadgar",    "MAGE",    "Arcane" },
    { "Antonidas",  "MAGE",    "Frost" },
    { "Rhonin",     "MAGE",    "Fire" },
    { "Aegwynn",    "MAGE",    "Arcane" },
    { "Guldan",     "WARLOCK", "Destruction" },
    { "Wilfred",    "WARLOCK", "Affliction" },
    { "Ritssyn",    "WARLOCK", "Demonology" },
    { "Kanrethad",  "WARLOCK", "Destruction" },
    { "Anduin",     "PRIEST",  "Holy" },
    { "Velen",      "PRIEST",  "Discipline" },
    { "Tyrande",    "PRIEST",  "Holy" },
    { "Moira",      "PRIEST",  "Shadow" },
    { "Benedictus", "PRIEST",  "Holy" },
    { "Whitemane",  "PRIEST",  "Discipline" },
    { "Malfurion",  "DRUID",   "Restoration" },
    { "Cenarius",   "DRUID",   "Balance" },
    { "Hamuul",     "DRUID",   "Restoration" },
    { "Fandral",    "DRUID",   "Feral" },
    { "Thrall",     "SHAMAN",  "Enhancement" },
    { "Drekthar",   "SHAMAN",  "Restoration" },
    { "Nobundo",    "SHAMAN",  "Elemental" },
    { "Rehgar",     "SHAMAN",  "Enhancement" },
    { "Uther",      "PALADIN", "Holy" },
    { "Arthas",     "PALADIN", "Retribution" },
    { "Tirion",     "PALADIN", "Protection" },
}
local FAKE, SPEC, FAKE_GROUP = {}, {}, {}
for i, r in ipairs(ROSTER40) do
    FAKE[r[1]] = r[2]; SPEC[r[1]] = r[3]
    FAKE_GROUP[r[1]] = math.floor((i - 1) / 5) + 1   -- groups 1-8, five a group
end

--------------------------------------------------------------------------
-- shared state + small helpers
--------------------------------------------------------------------------

local frame                  -- the panel (created lazily)
local tabBtns  = {}
local panels   = {}
local currentTab
local pills    = {}

-- Preview-paladin blessings: [fakePally][classID] = bid. Saved with the
-- settings so they survive /reload while test mode stays on (the Core clears
-- the table when test mode turns off); the legacy tables and the PLPWR wire
-- never see fake names.
local function TestBless()
    RallyPowerCP_Settings.testBless = RallyPowerCP_Settings.testBless or {}
    return RallyPowerCP_Settings.testBless
end

local TAB_INFO = {
    { label = "Blessings",  live = true  },
    { label = "Totems",     live = false },
    { label = "Raid Buffs", live = false },
    { label = "Debuffs",    live = false },
    { label = "Utility",    live = false },
}
-- tabs 4/5 are duty-card lists; tab 3 is the caster x class buff grid
local DUTY_TAB = { [4] = "debuff", [5] = "utility" }

local function Me() return UnitName("player") end

local function Msg(t)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffff00RallyPowerCP:|r " .. t)
end

local function TitleCase(s)
    if not s then return "?" end
    return string.upper(string.sub(s, 1, 1)) .. string.lower(string.sub(s, 2))
end

-- May I edit OTHER people's rows? (test mode = always: it's a preview)
local function LeaderLike()
    if RallyPowerCP.IsTestMode() then return true end
    if GetNumRaidMembers() > 0 then
        return (IsRaidLeader() == 1) or (IsRaidOfficer() == 1)
    end
    if GetNumPartyMembers() > 0 then
        return IsPartyLeader() == 1
    end
    return true   -- solo: you lead a party of one
end

-- Group members of one class token: you first, then the real roster, then
-- (test mode) the preview raid's members of that class.
local function MembersOfClass(token)
    local out, seen = {}, {}
    local function add(name)
        if name and not seen[name] then seen[name] = true; table.insert(out, name) end
    end
    local _, mycls = UnitClass("player")
    if mycls == token then add(Me()) end
    local n = GetNumRaidMembers()
    if n > 0 then
        for i = 1, n do
            local u = "raid" .. i
            local _, cls = UnitClass(u)
            if cls == token then add(UnitName(u)) end
        end
    else
        for i = 1, GetNumPartyMembers() do
            local u = "party" .. i
            local _, cls = UnitClass(u)
            if cls == token then add(UnitName(u)) end
        end
    end
    if RallyPowerCP.IsTestMode() then
        for _, r in ipairs(ROSTER40) do
            if r[2] == token then add(r[1]) end
        end
    end
    return out
end

-- Row subtitle: "Holy Paladin *" for preview raiders, "Paladin - you" for
-- yourself, plain class for everyone else.
local function SubFor(name, token)
    if RallyPowerCP.IsTestMode() and FAKE[name] and name ~= Me() then
        return (SPEC[name] or "") .. " " .. TitleCase(FAKE[name]) .. " |cffff8800*|r"
    end
    if name == Me() then return TitleCase(token) .. " - you" end
    return TitleCase(token)
end

local function ElementList()
    if A and table.getn(A.elements) > 0 then return A.elements end
    return { "Earth", "Fire", "Water", "Air" }
end

-- 9px/10px themed FontString factory
local function Fnt(parent, size, c, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetFont("Fonts\\FRIZQT__.TTF", size)
    fs:SetTextColor(c[1], c[2], c[3])
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

-- skinned clickable cell (grid cells, chips, cards all start here)
local function MakeCell(parent, w, h)
    local b = CreateFrame("Button", nil, parent)
    b:SetWidth(w); b:SetHeight(h)
    b:SetBackdrop(CELL_BD)
    b:SetBackdropColor(0.10, 0.088, 0.07, 0.92)
    b:SetBackdropBorderColor(0.05, 0.05, 0.05, 1)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:EnableMouseWheel(true)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b); hl:SetTexture(1, 1, 1, 0.13)
    return b
end

-- Real spell tooltip (name, rank, description) when the spell is in YOUR
-- spellbook, so the assigner can read what each spell does; the caller
-- appends assignment context after it. Returns false when the spell isn't
-- known so the caller draws its plain header instead.
local function SpellTip(owner, spellName)
    if not spellName then return false end
    local sp = RallyPowerCP.FindSpell and RallyPowerCP.FindSpell(spellName)
    if not sp or not sp.index then return false end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetSpell(sp.index, "spell")   -- literal: BOOKTYPE_SPELL may not exist
    return true
end

-- OnEnter errors die silently in 1.12 (the tooltip just never appears), so
-- every tooltip handler goes through this: failures print like the panel's
-- refresh errors instead of vanishing.
local function SafeTip(fn)
    return function()
        local ok, err = pcall(fn)
        if not ok then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff5555RallyPowerCP error:|r "
                .. tostring(err) .. " |cffaaaaaa(tooltip)|r")
        end
    end
end

local RefreshCurrent   -- forward declaration (handlers below close over it)

--------------------------------------------------------------------------
-- BLESSINGS TAB - live rows through the legacy engine; preview rows local
--------------------------------------------------------------------------

local blessRows   = {}
local blessHeader = {}

-- A row is a "preview" row when the name is a test-raid paladin that the
-- legacy engine does NOT know (a real guildie named Uther stays real).
local function IsFakeRow(name)
    if not RallyPowerCP.IsTestMode() then return false end
    if AllPallys and AllPallys[name] then return false end
    return FAKE[name] == "PALADIN"
end

-- Paladin rows: you first, the real AllPallys sorted, then the preview raid.
local function PallyList()
    local out, seen = {}, {}
    if AllPallys then
        for name in pairs(AllPallys) do
            if not seen[name] then seen[name] = true; table.insert(out, name) end
        end
    end
    table.sort(out)
    for i, n in ipairs(out) do
        if n == Me() then table.remove(out, i); table.insert(out, 1, n); break end
    end
    if RallyPowerCP.IsTestMode() then
        for _, r in ipairs(ROSTER40) do
            if r[2] == "PALADIN" and not seen[r[1]] then
                seen[r[1]] = true; table.insert(out, r[1])
            end
        end
    end
    return out
end

local function BlessBid(pally, class)
    local bid
    if IsFakeRow(pally) then
        local t = TestBless()[pally]
        bid = t and t[class]
    elseif class == 10 then
        bid = PallyPower_AuraAssignments and PallyPower_AuraAssignments[pally]
    elseif class == 11 then
        bid = PallyPower_SealAssignments and PallyPower_SealAssignments[pally]
    else
        local t = PallyPower_Assignments and PallyPower_Assignments[pally]
        bid = t and t[class]
    end
    if bid == nil then bid = -1 end
    return bid
end

-- icon / localized name for a column's assignment (10 = aura, 11 = seal)
local function BlessIconFor(class, bid)
    if class == 10 then return AuraIcons and AuraIcons[bid] end
    if class == 11 then return SealIcons and SealIcons[bid] end
    return BlessingIcon and BlessingIcon[bid]
end

local function BlessNameFor(class, bid)
    local t
    if class == 10 then t = PallyPower_AuraID
    elseif class == 11 then t = PallyPower_SealID
    else t = PallyPower_BlessingID end
    return t and t[bid]
end

-- Full spellbook name for a cell. The legacy ID tables hold SHORT names
-- ("Wisdom", "Retribution", "the Crusader") - rebuilt here with the same
-- patterns the locale scans with ("Blessing of (.*)", "(.*) Aura",
-- "Seal of (.*)"), so FindSpell can hit the real spellbook entry and the
-- tooltip can show the actual spell text.
local function BlessSpellName(class, bid)
    local short = BlessNameFor(class, bid)
    if not short then return nil end
    if class == 10 then return short .. " Aura" end
    if class == 11 then return "Seal of " .. short end
    return "Blessing of " .. short
end

-- letter fallback when the icon tables aren't populated (odd class states)
local function BlessAbbrev(class, bid)
    local n = BlessNameFor(class, bid)
    if not n then return "?" end
    local _, _, w = string.find(n, "of%s+(%a+)")
    return string.sub(w or n, 1, 2)
end

-- Per-paladin blessing skills (icon strip under the name, like the classic
-- frame's left column): [bid 0-5] = { rank, talent } plus the Symbol of Kings
-- count. Real paladins come from AllPallys (SELF/SYMCOUNT broadcasts);
-- preview paladins get max ranks with +5 talent on their spec's blessing.
local function SkillsFor(pally)
    if IsFakeRow(pally) then
        local talentBid = (SPEC[pally] == "Holy") and 0 or 1  -- Wisdom / Might
        local out = {}
        for id = 0, 5 do
            out[id] = { rank = BLESS_MAXRANK[id], talent = (id == talentBid) and 5 or 0 }
        end
        return out, 20
    end
    local sk = AllPallys and AllPallys[pally]
    if not sk then return nil end
    return sk, sk.symbols
end

-- Aura ranks/talents for the second skills row (talents improve auras, so
-- the assigner can see who's best specced for the aura duty).
local function AuraSkillsFor(pally)
    if IsFakeRow(pally) then
        local out = {}
        for id = 0, 6 do
            local tal = 0
            if SPEC[pally] == "Protection" and id == 0 then tal = 5 end   -- Devotion
            if SPEC[pally] == "Retribution" and id == 1 then tal = 3 end  -- Retribution
            out[id] = { rank = AURA_MAXRANK[id], talent = tal }
        end
        return out
    end
    return AllPallysAuras and AllPallysAuras[pally]
end

local function BlessCycle(pally, class, dir)
    if IsFakeRow(pally) then
        -- preview store only: the wire and the legacy tables never see fakes
        local tb = TestBless()
        tb[pally] = tb[pally] or {}
        local cur = tb[pally][class]
        if cur == nil then cur = -1 end
        if class == 10 then
            -- cycle only the rankable auras (resistances skipped)
            local n = table.getn(AURA_SHOW)
            local idx = 0
            for i = 1, n do if AURA_SHOW[i] == cur then idx = i end end
            idx = idx + dir
            if idx > n then idx = 0 elseif idx < 0 then idx = n end
            cur = (idx > 0) and AURA_SHOW[idx] or -1
        else
            local top = FAKE_MAX[class] or 5
            cur = cur + dir
            if cur > top then cur = -1 elseif cur < -1 then cur = top end
        end
        if IsShiftKeyDown() and class <= 9 then
            for c = 0, 9 do tb[pally][c] = cur end   -- aura/seal excluded, as legacy
        else
            tb[pally][class] = cur
        end
        RefreshCurrent()
        return
    end
    if not (PallyPower_CanControl and PallyPower_CanControl(pally)) then
        Msg("You can't assign for " .. pally .. " (need lead/assist, or their Free Assign).")
        return
    end
    if class == 10 then
        -- Aura cycling skips the resistance auras (identical on every
        -- paladin). Same table write + byte-identical AASSIGN message the
        -- legacy right-click clear path sends; the legacy aura cycle itself
        -- can't filter (PallyPower.lua stays untouched).
        PallyPower_AuraAssignments = PallyPower_AuraAssignments or {}
        local known = AllPallysAuras and AllPallysAuras[pally]
        local list = {}
        for i = 1, table.getn(AURA_SHOW) do
            local id = AURA_SHOW[i]
            if (not known) or known[id] then table.insert(list, id) end
        end
        local n = table.getn(list)
        local cur = PallyPower_AuraAssignments[pally]
        if cur == nil then cur = -1 end
        local idx = 0
        for i = 1, n do if list[i] == cur then idx = i end end
        idx = idx + dir
        if idx > n then idx = 0 elseif idx < 0 then idx = n end
        local aid = (idx > 0) and list[idx] or -1
        PallyPower_AuraAssignments[pally] = aid
        if PallyPower_SendMessage then
            PallyPower_SendMessage("AASSIGN " .. pally .. " " .. aid)
        end
        if PallyPower_UpdateUI then pcall(PallyPower_UpdateUI) end
        RefreshCurrent()
        return
    end
    -- the legacy cycle assumes the row table exists (ParseMessage creates it)
    PallyPower_Assignments[pally] = PallyPower_Assignments[pally] or {}
    if dir < 0 then
        PallyPower_PerformCycleBackwards(pally, class, false)
    else
        PallyPower_PerformCycle(pally, class, false)
    end
    RefreshCurrent()
end

local function BlessCellClick()
    BlessCycle(this.pally, this.classID, (arg1 == "RightButton") and -1 or 1)
end

local function BlessCellWheel()
    BlessCycle(this.pally, this.classID, (arg1 and arg1 > 0) and -1 or 1)
end

local function BlessCellTip()
    if RallyPowerCP_Settings.tooltips == false then return end
    local pally, class = this.pally, this.classID
    local bid = BlessBid(pally, class)
    local spellName = (bid >= 0) and BlessNameFor(class, bid) or nil
    -- real spell tooltip first (description readable by the assigner),
    -- assignment context appended under it
    if spellName and SpellTip(this, BlessSpellName(class, bid)) then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(pally .. "  -  " .. (CLASS_LABEL[class] or "?"), 1, 1, 1)
    else
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText(pally .. "  -  " .. (CLASS_LABEL[class] or "?"), 1, 1, 1)
        if spellName then
            GameTooltip:AddLine(spellName, 0.5, 1, 0.5)
        else
            local what = (class == 10 and "aura") or (class == 11 and "seal") or "blessing"
            GameTooltip:AddLine("No " .. what .. " assigned", 0.7, 0.7, 0.7)
        end
    end
    GameTooltip:AddLine("Click: next  -  Right-click: previous  -  Wheel: cycle", 0.6, 0.6, 0.6)
    if class <= 9 then
        GameTooltip:AddLine("Shift: set ALL classes at once", 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

local function BuildBlessings(p)
    -- column headers: Aura and Seal lead, then class icons (COL_AT order)
    for pos = 0, BLESS_COLS do
        local c = COL_AT[pos]
        local t = p:CreateTexture(nil, "ARTWORK")
        t:SetWidth(24); t:SetHeight(24)
        t:SetPoint("TOPLEFT", p, "TOPLEFT", NAME_W + pos * 44 + 9, -42)
        local l = Fnt(p, 8, c >= 10 and GOLD or INK_DIM, "CENTER")
        l:SetWidth(44); l:SetHeight(9)
        l:SetPoint("TOPLEFT", p, "TOPLEFT", NAME_W + pos * 44 - 1, -68)
        l:SetText(CLASS_LABEL[c])
        blessHeader[c] = t
    end
    -- separator between the name/skills column and the assignment grid
    local sep = p:CreateTexture(nil, "ARTWORK")
    sep:SetTexture(0.78, 0.67, 0.43)
    sep:SetAlpha(0.25)
    sep:SetWidth(1); sep:SetHeight(44 + BLESS_ROWS * BLESS_ROW_H)
    sep:SetPoint("TOPLEFT", p, "TOPLEFT", NAME_W - 12, -40)
    for r = 1, BLESS_ROWS do
        local row = { cells = {}, skillIcon = {}, skillText = {},
                      auraIcon = {}, auraText = {} }
        local y = -84 - (r - 1) * BLESS_ROW_H
        row.name = Fnt(p, 11, INK)
        row.name:SetWidth(NAME_W - 22); row.name:SetHeight(12)
        row.name:SetPoint("TOPLEFT", p, "TOPLEFT", 6, y - 2)
        row.sub = Fnt(p, 8, INK_FAINT)
        row.sub:SetWidth(NAME_W - 22); row.sub:SetHeight(9)
        row.sub:SetPoint("TOPLEFT", p, "TOPLEFT", 6, y - 15)
        -- skills strip 1: the paladin's six blessings, rank+talent on each icon
        for id = 0, 5 do
            local si = p:CreateTexture(nil, "ARTWORK")
            si:SetWidth(16); si:SetHeight(16)
            si:SetPoint("TOPLEFT", p, "TOPLEFT", 6 + id * 22, y - 26)
            si:Hide()
            local st = Fnt(p, 8, GOLD_BRIGHT, "RIGHT")
            st:SetWidth(24); st:SetHeight(9)
            st:SetPoint("BOTTOMRIGHT", si, "BOTTOMRIGHT", 4, -2)
            row.skillIcon[id] = si
            row.skillText[id] = st
        end
        -- skills strip 2: the rankable auras (resistance auras skipped -
        -- identical on every paladin)
        for i = 1, table.getn(AURA_SHOW) do
            local id = AURA_SHOW[i]
            local si = p:CreateTexture(nil, "ARTWORK")
            si:SetWidth(16); si:SetHeight(16)
            si:SetPoint("TOPLEFT", p, "TOPLEFT", 6 + (i - 1) * 22, y - 45)
            si:Hide()
            local st = Fnt(p, 8, GOLD_BRIGHT, "RIGHT")
            st:SetWidth(24); st:SetHeight(9)
            st:SetPoint("BOTTOMRIGHT", si, "BOTTOMRIGHT", 4, -2)
            row.auraIcon[id] = si
            row.auraText[id] = st
        end
        for pos = 0, BLESS_COLS do
            local c = COL_AT[pos]
            local b = MakeCell(p, 42, CELL_H)
            -- vertically centred against the 62px row (name + two skill strips)
            b:SetPoint("TOPLEFT", p, "TOPLEFT", NAME_W + pos * 44,
                y - (BLESS_ROW_H - CELL_H) / 2)
            b.classID = c
            local icon = b:CreateTexture(nil, "ARTWORK")
            icon:SetWidth(28); icon:SetHeight(28)
            icon:SetPoint("CENTER", b, "CENTER", 0, 0)
            b.icon = icon
            local txt = Fnt(b, 12, GOLD_BRIGHT, "CENTER")
            txt:SetPoint("CENTER", b, "CENTER", 0, 0)
            b.text = txt
            b:SetScript("OnClick", BlessCellClick)
            b:SetScript("OnMouseWheel", BlessCellWheel)
            b:SetScript("OnEnter", SafeTip(BlessCellTip))
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            b:Hide()
            row.cells[c] = b
        end
        blessRows[r] = row
    end
end

local function RefreshBlessings(p)
    for c = 0, 9 do
        if PallyPower_ClassTexture and PallyPower_ClassTexture[c] then
            blessHeader[c]:SetTexture(PallyPower_ClassTexture[c])
        end
    end
    if AuraIcons and AuraIcons[0] then blessHeader[10]:SetTexture(AuraIcons[0]) end
    if SealIcons and SealIcons[0] then blessHeader[11]:SetTexture(SealIcons[0]) end
    local pallys = PallyList()
    local pc = CLASS_RGB.PALADIN
    for r = 1, BLESS_ROWS do
        local row = blessRows[r]
        local pally = pallys[r]
        if pally then
            local fake = IsFakeRow(pally)
            local control = fake or (PallyPower_CanControl and PallyPower_CanControl(pally))
            row.name:SetText(pally)
            row.name:SetTextColor(pc[1], pc[2], pc[3])
            -- sub line carries the Symbol of Kings count (SYMCOUNT broadcasts)
            local sk, symbols = SkillsFor(pally)
            local sub = SubFor(pally, "PALADIN")
            if symbols then
                sub = sub .. "  |cffffe080" .. symbols .. " sym|r"
            end
            row.sub:SetText(sub)
            -- skills strip 1: available blessings, "rank+talent" on each icon
            for id = 0, 5 do
                local entry = sk and sk[id]
                if type(entry) == "table" and entry.rank then
                    row.skillIcon[id]:SetTexture(BlessingIcon and BlessingIcon[id])
                    row.skillIcon[id]:Show()
                    local tal = tonumber(entry.talent) or 0
                    row.skillText[id]:SetText(entry.rank .. (tal > 0 and ("+" .. tal) or ""))
                    row.skillText[id]:Show()
                else
                    row.skillIcon[id]:Hide()
                    row.skillText[id]:Hide()
                end
            end
            -- skills strip 2: their rankable auras with rank+talent
            local ak = AuraSkillsFor(pally)
            for i = 1, table.getn(AURA_SHOW) do
                local id = AURA_SHOW[i]
                local entry = ak and ak[id]
                if type(entry) == "table" and entry.rank then
                    row.auraIcon[id]:SetTexture(AuraIcons and AuraIcons[id])
                    row.auraIcon[id]:Show()
                    local tal = tonumber(entry.talent) or 0
                    row.auraText[id]:SetText(entry.rank .. (tal > 0 and ("+" .. tal) or ""))
                    row.auraText[id]:Show()
                else
                    row.auraIcon[id]:Hide()
                    row.auraText[id]:Hide()
                end
            end
            for c = 0, BLESS_COLS do
                local b = row.cells[c]
                b.pally = pally
                local bid = BlessBid(pally, c)
                if bid >= 0 then
                    local tex = BlessIconFor(c, bid)
                    if tex then
                        b.icon:SetTexture(tex)
                        b.icon:Show()
                        b.text:SetText("")
                    else
                        b.icon:Hide()
                        b.text:SetText(BlessAbbrev(c, bid))
                    end
                    b.icon:SetAlpha(control and 1 or 0.4)
                    b:SetBackdropColor(0.13, 0.115, 0.085, 0.95)
                else
                    b.icon:Hide()
                    b.text:SetText("+")
                    b.text:SetTextColor(INK_FAINT[1], INK_FAINT[2], INK_FAINT[3])
                    b:SetBackdropColor(0.10, 0.088, 0.07, 0.6)
                end
                if bid >= 0 then
                    b.text:SetTextColor(GOLD_BRIGHT[1], GOLD_BRIGHT[2], GOLD_BRIGHT[3])
                end
                b:Show()
            end
        else
            row.name:SetText(""); row.sub:SetText("")
            for id = 0, 5 do
                row.skillIcon[id]:Hide(); row.skillText[id]:Hide()
            end
            for i = 1, table.getn(AURA_SHOW) do
                row.auraIcon[AURA_SHOW[i]]:Hide()
                row.auraText[AURA_SHOW[i]]:Hide()
            end
            for c = 0, BLESS_COLS do row.cells[c]:Hide() end
        end
    end
    -- coverage: any class (pets excluded) nobody blesses
    if table.getn(pallys) == 0 then
        p.cover:SetText("")
        p.hint:SetText("No paladins known yet - they appear when they broadcast on PLPWR "
            .. "(group with one, or /rpc test for the preview raid).")
        return
    end
    local gaps = {}
    for c = 0, 8 do
        local got = false
        for _, pl in ipairs(pallys) do
            if BlessBid(pl, c) >= 0 then got = true end
        end
        if not got then table.insert(gaps, CLASS_LABEL[c]) end
    end
    if table.getn(gaps) == 0 then
        p.cover:SetTextColor(OK_GREEN[1], OK_GREEN[2], OK_GREEN[3])
        p.cover:SetText("Coverage: every class has a blessing.")
    else
        p.cover:SetTextColor(GAP_RED[1], GAP_RED[2], GAP_RED[3])
        p.cover:SetText("No blessing: " .. table.concat(gaps, ", "))
    end
    p.hint:SetText("Click a cell to cycle that paladin's blessing, aura or seal "
        .. "(right-click backwards, shift = all classes). Byte-compatible with stock PallyPower.")
end

--------------------------------------------------------------------------
-- TOTEMS TAB - party column + shaman x element chips, over the model
--------------------------------------------------------------------------

local totemRows = {}
local PARTY_W, ELEM_W = 64, 116

local function ShortTotem(name)
    if not name then return nil end
    name = string.gsub(name, " Totem$", "")
    name = string.gsub(name, "^Strength of ", "Str. of ")
    name = string.gsub(name, " Resistance$", " Res.")
    return name
end

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
    RefreshCurrent()
end

-- The group column is AUTOMATIC: totems only reach the shaman's own
-- subgroup, so showing anything else would let assignments disagree with
-- reality. Real members come from the raid roster; preview raiders have
-- fixed groups (five a group).
local function GroupOf(name)
    local n = GetNumRaidMembers()
    if n > 0 then
        for i = 1, n do
            local rname, _, subgroup = GetRaidRosterInfo(i)
            if rname == name then return subgroup end
        end
    end
    if RallyPowerCP.IsTestMode() and FAKE_GROUP[name] then
        return FAKE_GROUP[name]
    end
    return 1
end

-- Chip icon for a totem: your own spellbook first (exact), static fallback
-- for other shamans' totems.
local function TotemIconFor(totemName)
    if not totemName then return nil end
    local sp = RallyPowerCP.FindSpell and RallyPowerCP.FindSpell(totemName)
    if sp and sp.texture then return sp.texture end
    return TOTEM_ICONS[totemName]
end

local function TotemCellClick()
    if this.element then
        CycleTotem(this.shaman, this.element, (arg1 == "RightButton") and -1 or 1)
    end
end

local function TotemCellWheel()
    if this.element then
        CycleTotem(this.shaman, this.element, (arg1 and arg1 > 0) and -1 or 1)
    end
end

local function TotemCellTip()
    if RallyPowerCP_Settings.tooltips == false then return end
    if this.element then
        local cur = A.GetTotem(this.shaman, this.element)
        -- real spell tooltip when the totem is in your spellbook
        if cur and SpellTip(this, cur) then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(this.shaman .. "  -  " .. this.element, 1, 1, 1)
        else
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            GameTooltip:SetText(this.shaman .. "  -  " .. this.element, 1, 1, 1)
            if cur then GameTooltip:AddLine(cur, 0.5, 1, 0.5)
            else GameTooltip:AddLine("No totem assigned", 0.7, 0.7, 0.7) end
        end
        GameTooltip:AddLine("Click: next  -  Right-click: previous  -  Wheel: cycle", 0.6, 0.6, 0.6)
    else
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText(this.shaman .. "  -  group", 1, 1, 1)
        GameTooltip:AddLine("Group " .. GroupOf(this.shaman), 0.5, 1, 0.5)
        GameTooltip:AddLine("Set automatically from the raid roster - totems only reach "
            .. "the shaman's own subgroup.", 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

local function BuildTotems(p)
    local heads = { "Group" }
    local els = ElementList()
    for i = 1, table.getn(els) do table.insert(heads, els[i]) end
    for i = 1, table.getn(heads) do
        local x = (i == 1) and NAME_W or (NAME_W + PARTY_W + 4 + (i - 2) * (ELEM_W + 2))
        local w = (i == 1) and PARTY_W or ELEM_W
        local col = (i == 1) and INK_DIM or (ECOL[heads[i]] or INK_DIM)
        local shade = { col[1] * 1.5, col[2] * 1.5, col[3] * 1.5 }
        if shade[1] > 1 then shade[1] = 1 end
        if shade[2] > 1 then shade[2] = 1 end
        if shade[3] > 1 then shade[3] = 1 end
        local fs = Fnt(p, 10, shade, "CENTER")
        fs:SetWidth(w); fs:SetHeight(11)
        fs:SetPoint("TOPLEFT", p, "TOPLEFT", x, -48)
        fs:SetText(heads[i])
    end
    for r = 1, MAX_ROWS do
        local row = { cells = {} }
        local y = -64 - (r - 1) * ROW_H
        row.name = Fnt(p, 11, INK)
        row.name:SetWidth(NAME_W - 10); row.name:SetHeight(12)
        row.name:SetPoint("TOPLEFT", p, "TOPLEFT", 6, y - 3)
        row.sub = Fnt(p, 8, INK_FAINT)
        row.sub:SetWidth(NAME_W - 10); row.sub:SetHeight(9)
        row.sub:SetPoint("TOPLEFT", p, "TOPLEFT", 6, y - 17)
        for i = 1, 1 + table.getn(els) do
            local x = (i == 1) and NAME_W or (NAME_W + PARTY_W + 4 + (i - 2) * (ELEM_W + 2))
            local w = (i == 1) and PARTY_W or ELEM_W
            local b = MakeCell(p, w, CELL_H)
            b:SetPoint("TOPLEFT", p, "TOPLEFT", x, y)
            if i == 1 then
                -- group cell: centred read-only text
                local txt = Fnt(b, 10, INK, "CENTER")
                txt:SetWidth(w - 4); txt:SetHeight(CELL_H)
                txt:SetPoint("CENTER", b, "CENTER", 0, 0)
                b.text = txt
            else
                -- element chip: totem icon + name
                local icon = b:CreateTexture(nil, "ARTWORK")
                icon:SetWidth(26); icon:SetHeight(26)
                icon:SetPoint("LEFT", b, "LEFT", 4, 0)
                b.icon = icon
                local txt = Fnt(b, 9, INK)
                txt:SetWidth(w - 38); txt:SetHeight(CELL_H - 4)
                txt:SetPoint("LEFT", b, "LEFT", 33, 0)
                b.text = txt
            end
            b:SetScript("OnClick", TotemCellClick)
            b:SetScript("OnMouseWheel", TotemCellWheel)
            b:SetScript("OnEnter", SafeTip(TotemCellTip))
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            b:Hide()
            row.cells[i] = b
        end
        totemRows[r] = row
    end
end

local function RefreshTotems(p)
    local els = ElementList()
    local shamans = MembersOfClass("SHAMAN")
    local sc = CLASS_RGB.SHAMAN
    for r = 1, MAX_ROWS do
        local row = totemRows[r]
        local shaman = shamans[r]
        if shaman then
            row.name:SetText(shaman)
            row.name:SetTextColor(sc[1], sc[2], sc[3])
            row.sub:SetText(SubFor(shaman, "SHAMAN"))
            local pb = row.cells[1]
            pb.shaman = shaman; pb.element = nil
            pb.text:SetText("Grp " .. GroupOf(shaman))
            pb.text:SetTextColor(INK[1], INK[2], INK[3])
            pb:SetBackdropColor(0.10, 0.088, 0.07, 0.92)
            pb:Show()
            for i = 1, table.getn(els) do
                local b = row.cells[i + 1]
                local el = els[i]
                b.shaman = shaman; b.element = el
                local cur = A.GetTotem(shaman, el)
                if cur then
                    local ec = ECOL[el] or { 0.2, 0.2, 0.2 }
                    local tex = TotemIconFor(cur)
                    if tex then b.icon:SetTexture(tex); b.icon:Show()
                    else b.icon:Hide() end
                    b.text:SetText(ShortTotem(cur))
                    b.text:SetTextColor(1, 1, 1)
                    b:SetBackdropColor(ec[1], ec[2], ec[3], 0.55)
                else
                    b.icon:Hide()
                    b.text:SetText("+")
                    b.text:SetTextColor(INK_FAINT[1], INK_FAINT[2], INK_FAINT[3])
                    b:SetBackdropColor(0.10, 0.088, 0.07, 0.6)
                end
                b:Show()
            end
        else
            row.name:SetText(""); row.sub:SetText("")
            for i = 1, table.getn(row.cells) do row.cells[i]:Hide() end
        end
    end
    if table.getn(shamans) == 0 then
        p.cover:SetText("")
        p.hint:SetText("No shamans in your group. /rpc test seats the preview raid so you "
            .. "can try the panel solo.")
        return
    end
    local gaps = {}
    for i = 1, table.getn(els) do
        local got = false
        for _, s in ipairs(shamans) do
            if A.GetTotem(s, els[i]) then got = true end
        end
        if not got then table.insert(gaps, els[i]) end
    end
    if table.getn(gaps) == 0 then
        p.cover:SetTextColor(OK_GREEN[1], OK_GREEN[2], OK_GREEN[3])
        p.cover:SetText("Coverage: every element is assigned.")
    else
        p.cover:SetTextColor(GAP_RED[1], GAP_RED[2], GAP_RED[3])
        p.cover:SetText("No totem: " .. table.concat(gaps, ", "))
    end
    p.hint:SetText("Click an element to cycle that shaman's totem. Group = their current "
        .. "subgroup (automatic - totems only reach their own group). Synced to the raid; "
        .. "each shaman's row drives their strip.")
end

--------------------------------------------------------------------------
-- RAID BUFFS TAB - the blessings tab's shape applied to Priest/Mage/Druid:
-- a caster x class grid over the model's class-buff domain. Each cell is
-- which buff that caster gives that class; a caster's own class-buff strip
-- follows their row (step-1b), so assigning here retargets their buttons
-- and lets buffers split the raid by class.
--------------------------------------------------------------------------

local buffRows = {}
local buffHeader = {}
local BUFF_ROWS = 9
local BUFFER_CLASSES = { "PRIEST", "MAGE", "DRUID" }

local function BuffCatalog(token)
    local m = RallyPowerCP.classes and RallyPowerCP.classes[token]
    return (m and m.buffs) or {}
end

-- rows: the buffers of the three classes (you first within your class);
-- preview raiders capped at three per class so all three classes fit
local function BufferList()
    local out = {}
    for _, tok in ipairs(BUFFER_CLASSES) do
        local fakes = 0
        local members = MembersOfClass(tok)
        for i = 1, table.getn(members) do
            local nm = members[i]
            if RallyPowerCP.IsTestMode() and FAKE[nm] and nm ~= Me() then
                fakes = fakes + 1
                if fakes <= 3 then table.insert(out, { name = nm, token = tok }) end
            else
                table.insert(out, { name = nm, token = tok })
            end
        end
    end
    return out
end

local function BuffIconFor(token, buffName)
    local cat = BuffCatalog(token)
    for i = 1, table.getn(cat) do
        local bd = cat[i]
        if (bd.name == buffName or bd.group == buffName) and bd.icons and bd.icons[1] then
            return "Interface\\Icons\\" .. bd.icons[1]
        end
    end
    return nil
end

local function CycleClassBuff(caster, token, classID, dir)
    local cat = BuffCatalog(token)
    local n = table.getn(cat)
    if n == 0 then return end
    local cur = A.GetClassBuff(caster, classID)
    local idx = 0
    for i = 1, n do
        if (cat[i].name or cat[i].group) == cur then idx = i end
    end
    idx = idx + dir
    if idx > n then idx = 0 elseif idx < 0 then idx = n end
    local val = nil
    if idx > 0 then val = cat[idx].name or cat[idx].group end
    if not A.SetClassBuff(caster, classID, val) then
        Msg("You can't assign for " .. caster .. " (need lead/assist).")
    end
    RefreshCurrent()
end

local function BuffCellClick()
    CycleClassBuff(this.caster, this.token, this.classID, (arg1 == "RightButton") and -1 or 1)
end

local function BuffCellWheel()
    CycleClassBuff(this.caster, this.token, this.classID, (arg1 and arg1 > 0) and -1 or 1)
end

local function BuffCellTip()
    if RallyPowerCP_Settings.tooltips == false then return end
    local cur = A.GetClassBuff(this.caster, this.classID)
    if cur and SpellTip(this, cur) then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(this.caster .. "  -  " .. (CLASS_LABEL[this.classID] or "?"), 1, 1, 1)
    else
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText(this.caster .. "  -  " .. (CLASS_LABEL[this.classID] or "?"), 1, 1, 1)
        if cur then GameTooltip:AddLine(cur, 0.5, 1, 0.5)
        else GameTooltip:AddLine("No buff assigned", 0.7, 0.7, 0.7) end
    end
    GameTooltip:AddLine("Click: next  -  Right-click: previous  -  Wheel: cycle", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function BuildBuffGrid(p)
    for c = 0, 9 do
        local t = p:CreateTexture(nil, "ARTWORK")
        t:SetWidth(24); t:SetHeight(24)
        t:SetPoint("TOPLEFT", p, "TOPLEFT", NAME_W + c * 44 + 9, -42)
        local l = Fnt(p, 8, INK_DIM, "CENTER")
        l:SetWidth(44); l:SetHeight(9)
        l:SetPoint("TOPLEFT", p, "TOPLEFT", NAME_W + c * 44 - 1, -68)
        l:SetText(CLASS_LABEL[c])
        buffHeader[c] = t
    end
    for r = 1, BUFF_ROWS do
        local row = { cells = {} }
        local y = -84 - (r - 1) * ROW_H
        row.name = Fnt(p, 11, INK)
        row.name:SetWidth(NAME_W - 22); row.name:SetHeight(12)
        row.name:SetPoint("TOPLEFT", p, "TOPLEFT", 6, y - 3)
        row.sub = Fnt(p, 8, INK_FAINT)
        row.sub:SetWidth(NAME_W - 22); row.sub:SetHeight(9)
        row.sub:SetPoint("TOPLEFT", p, "TOPLEFT", 6, y - 17)
        for c = 0, 9 do
            local b = MakeCell(p, 42, CELL_H)
            b:SetPoint("TOPLEFT", p, "TOPLEFT", NAME_W + c * 44, y)
            b.classID = c
            local icon = b:CreateTexture(nil, "ARTWORK")
            icon:SetWidth(28); icon:SetHeight(28)
            icon:SetPoint("CENTER", b, "CENTER", 0, 0)
            b.icon = icon
            local txt = Fnt(b, 12, GOLD_BRIGHT, "CENTER")
            txt:SetPoint("CENTER", b, "CENTER", 0, 0)
            b.text = txt
            b:SetScript("OnClick", BuffCellClick)
            b:SetScript("OnMouseWheel", BuffCellWheel)
            b:SetScript("OnEnter", SafeTip(BuffCellTip))
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            b:Hide()
            row.cells[c] = b
        end
        buffRows[r] = row
    end
end

local function RefreshBuffGrid(p)
    for c = 0, 9 do
        if PallyPower_ClassTexture and PallyPower_ClassTexture[c] then
            buffHeader[c]:SetTexture(PallyPower_ClassTexture[c])
        end
    end
    local rows = BufferList()
    for r = 1, BUFF_ROWS do
        local row = buffRows[r]
        local entry = rows[r]
        if entry then
            local cc = CLASS_RGB[entry.token] or INK
            row.name:SetText(entry.name)
            row.name:SetTextColor(cc[1], cc[2], cc[3])
            row.sub:SetText(SubFor(entry.name, entry.token))
            for c = 0, 9 do
                local b = row.cells[c]
                b.caster = entry.name; b.token = entry.token
                local cur = A.GetClassBuff(entry.name, c)
                if cur then
                    local tex = BuffIconFor(entry.token, cur)
                    if tex then
                        b.icon:SetTexture(tex); b.icon:Show(); b.icon:SetAlpha(1)
                        b.text:SetText("")
                    else
                        b.icon:Hide()
                        b.text:SetText(string.sub(cur, 1, 2))
                        b.text:SetTextColor(GOLD_BRIGHT[1], GOLD_BRIGHT[2], GOLD_BRIGHT[3])
                    end
                    b:SetBackdropColor(0.13, 0.115, 0.085, 0.95)
                else
                    b.icon:Hide()
                    b.text:SetText("+")
                    b.text:SetTextColor(INK_FAINT[1], INK_FAINT[2], INK_FAINT[3])
                    b:SetBackdropColor(0.10, 0.088, 0.07, 0.6)
                end
                b:Show()
            end
        else
            row.name:SetText(""); row.sub:SetText("")
            for c = 0, 9 do row.cells[c]:Hide() end
        end
    end
    if table.getn(rows) == 0 then
        p.cover:SetText("")
        p.hint:SetText("No priests, mages or druids in your group. /rpc test seats the "
            .. "preview raid so you can try the panel solo.")
        return
    end
    local gaps = {}
    for c = 0, 8 do
        local got = false
        for i = 1, table.getn(rows) do
            if A.GetClassBuff(rows[i].name, c) then got = true end
        end
        if not got then table.insert(gaps, CLASS_LABEL[c]) end
    end
    if table.getn(gaps) == 0 then
        p.cover:SetTextColor(OK_GREEN[1], OK_GREEN[2], OK_GREEN[3])
        p.cover:SetText("Coverage: every class has a buffer.")
    else
        p.cover:SetTextColor(GAP_RED[1], GAP_RED[2], GAP_RED[3])
        p.cover:SetText("No buffer: " .. table.concat(gaps, ", "))
    end
    p.hint:SetText("Click a cell to cycle which buff that caster gives the class - their own "
        .. "strip follows their row, so buffers can split the raid by class. Synced to the raid.")
end

--------------------------------------------------------------------------
-- DUTY TABS - Debuffs / Utility as two-column cards
--------------------------------------------------------------------------

local dutyCards = { [4] = {}, [5] = {} }

local function DutyList(tabkey)
    local out = {}
    for i = 1, table.getn(A.dutyOrder) do
        local def = A.duties[A.dutyOrder[i]]
        if def and def.tab == tabkey then table.insert(out, def) end
    end
    return out
end

local function DutyIcon(def)
    if def.spell then
        local sp = RallyPowerCP.FindSpell and RallyPowerCP.FindSpell(def.spell)
        if sp and sp.texture then return sp.texture end
    end
    return DUTY_ICONS[def.key]
end

-- Holders text: "-", "Name", "Name +2" (tooltip lists everyone)
local function HolderText(key)
    local holders = A.GetDutyCasters(key)
    local n = table.getn(holders)
    if n == 0 then return nil, holders end
    local t = holders[1].caster
    if n > 1 then t = t .. " +" .. (n - 1) end
    return t, holders
end

-- Lead/assist (or test mode) cycles none -> each candidate -> none; everyone
-- else toggles their own claim.
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
        RefreshCurrent()
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
    RefreshCurrent()
end

local function DutyCardClick()
    CycleDutyHolder(this.dutyKey, (arg1 == "RightButton") and -1 or 1)
end

local function DutyCardWheel()
    CycleDutyHolder(this.dutyKey, (arg1 and arg1 > 0) and -1 or 1)
end

local function DutyCardTip()
    if RallyPowerCP_Settings.tooltips == false then return end
    local def = A.duties[this.dutyKey]
    if not def then return end
    -- real spell tooltip when the duty's spell is in your spellbook
    if SpellTip(this, def.spell) then
        GameTooltip:AddLine(" ")
    else
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText(def.spell or this.dutyKey, 1, 1, 1)
    end
    local _, holders = HolderText(this.dutyKey)
    for i = 1, table.getn(holders) do
        local h = holders[i]
        local t = h.caster
        if type(h.target) == "string" then t = t .. "  ->  " .. h.target end
        GameTooltip:AddLine(t, 0.5, 1, 0.5)
    end
    if table.getn(holders) == 0 then GameTooltip:AddLine("Unassigned", 0.7, 0.7, 0.7) end
    GameTooltip:AddLine("Click: cycle who's responsible (right-click backwards)", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function BuildDutyTab(p, tabIndex)
    for i = 1, DUTY_POOL do
        local col = math.mod(i - 1, 2)          -- 0 left, 1 right
        local rowN = math.floor((i - 1) / 2)
        local card = MakeCell(p, 346, 46)
        card:SetPoint("TOPLEFT", p, "TOPLEFT", col * 366, -46 - rowN * 48)
        local icon = card:CreateTexture(nil, "ARTWORK")
        icon:SetWidth(32); icon:SetHeight(32)
        icon:SetPoint("LEFT", card, "LEFT", 8, 0)
        card.icon = icon
        card.name = Fnt(card, 11, INK)
        card.name:SetWidth(200); card.name:SetHeight(12)
        card.name:SetPoint("TOPLEFT", card, "TOPLEFT", 48, -9)
        card.sub = Fnt(card, 9, INK_FAINT)
        card.sub:SetWidth(200); card.sub:SetHeight(10)
        card.sub:SetPoint("TOPLEFT", card, "TOPLEFT", 48, -26)
        card.holder = Fnt(card, 11, INK, "RIGHT")
        card.holder:SetWidth(90); card.holder:SetHeight(12)
        card.holder:SetPoint("RIGHT", card, "RIGHT", -8, 0)
        card:SetScript("OnClick", DutyCardClick)
        card:SetScript("OnMouseWheel", DutyCardWheel)
        card:SetScript("OnEnter", SafeTip(DutyCardTip))
        card:SetScript("OnLeave", function() GameTooltip:Hide() end)
        card:Hide()
        dutyCards[tabIndex][i] = card
    end
end

local function RefreshDutyTab(p, tabIndex)
    local defs = DutyList(DUTY_TAB[tabIndex])
    local cards = dutyCards[tabIndex]
    local assigned = 0
    for i = 1, DUTY_POOL do
        local card = cards[i]
        local def = defs[i]
        if def then
            card.dutyKey = def.key
            local tex = DutyIcon(def)
            if tex then card.icon:SetTexture(tex); card.icon:Show()
            else card.icon:Hide() end
            card.name:SetText(def.spell or def.key)
            card.sub:SetText(TitleCase(def.class)
                .. (def.multi and " - any number" or " - one owner"))
            local txt = HolderText(def.key)
            if txt then
                assigned = assigned + 1
                local cc = CLASS_RGB[def.class] or INK
                card.holder:SetText(txt)
                card.holder:SetTextColor(cc[1], cc[2], cc[3])
                card:SetBackdropColor(0.13, 0.115, 0.085, 0.95)
            else
                card.holder:SetText("-")
                card.holder:SetTextColor(INK_FAINT[1], INK_FAINT[2], INK_FAINT[3])
                card:SetBackdropColor(0.10, 0.088, 0.07, 0.7)
            end
            card:Show()
        else
            card:Hide()
        end
    end
    local total = table.getn(defs)
    p.note:SetText(assigned .. "/" .. total .. " assigned")
    if total > assigned then
        p.note:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    else
        p.note:SetTextColor(OK_GREEN[1], OK_GREEN[2], OK_GREEN[3])
    end
    p.cover:SetText("")
    p.hint:SetText("Click a card to cycle who's responsible (lead/assist cycles anyone; "
        .. "others claim or unclaim themselves). Synced to the raid.")
end

--------------------------------------------------------------------------
-- status pills (top right, concept header): TEST / leader / free assign / sync
--------------------------------------------------------------------------

local function MakePill(parent, w)
    local b = CreateFrame("Button", nil, parent)
    b:SetWidth(w); b:SetHeight(17)
    b:SetBackdrop(CELL_BD)
    b:SetBackdropColor(0.09, 0.08, 0.06, 0.9)
    b:SetBackdropBorderColor(0.23, 0.20, 0.15, 1)
    local fs = Fnt(b, 9, INK_DIM, "CENTER")
    fs:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.text = fs
    return b
end

local function UpdatePills()
    if not pills.leader then return end
    if RallyPowerCP.IsTestMode() then
        pills.test:Show()
    else
        pills.test:Hide()
    end
    local lead
    if GetNumRaidMembers() > 0 then
        lead = (IsRaidLeader() == 1) or (IsRaidOfficer() == 1)
        pills.leader.text:SetText(lead and "|cff5be07a\226\151\143|r Lead/Assist"
                                       or "|cff777777\226\151\143|r Member")
    elseif GetNumPartyMembers() > 0 then
        lead = (IsPartyLeader() == 1)
        pills.leader.text:SetText(lead and "|cff5be07a\226\151\143|r Party Lead"
                                       or "|cff777777\226\151\143|r Member")
    else
        pills.leader.text:SetText("|cff5be07a\226\151\143|r Solo")
    end
    if PP_PerUser then
        pills.free:Show()
        if PP_PerUser.freeassign then
            pills.free.text:SetText("|cff5be07a\226\151\143|r Free Assign: on")
        else
            pills.free.text:SetText("|cff777777\226\151\143|r Free Assign: off")
        end
    else
        pills.free:Hide()
    end
end

--------------------------------------------------------------------------
-- frame, tabs, bottom buttons
--------------------------------------------------------------------------

local function StyleTabs()
    for i = 1, table.getn(tabBtns) do
        local b = tabBtns[i]
        if i == currentTab then
            -- active tab merges into the content box (same fill, gold edge)
            b:SetBackdropColor(0.08, 0.072, 0.058, 1)
            b:SetBackdropBorderColor(GOLD_DIM[1], GOLD_DIM[2], GOLD_DIM[3], 1)
            b.label:SetTextColor(GOLD_BRIGHT[1], GOLD_BRIGHT[2], GOLD_BRIGHT[3])
        else
            b:SetBackdropColor(0.06, 0.052, 0.042, 0.95)
            b:SetBackdropBorderColor(0.18, 0.16, 0.12, 1)
            b.label:SetTextColor(INK_DIM[1], INK_DIM[2], INK_DIM[3])
        end
    end
end

local function RefreshInner()
    UpdatePills()
    local p = panels[currentTab]
    if currentTab == 1 then RefreshBlessings(p)
    elseif currentTab == 2 then RefreshTotems(p)
    elseif currentTab == 3 then RefreshBuffGrid(p)
    elseif DUTY_TAB[currentTab] then RefreshDutyTab(p, currentTab) end
end

RefreshCurrent = function()
    if not frame or not frame:IsShown() then return end
    local ok, err = pcall(RefreshInner)
    if not ok then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff5555RallyPowerCP error:|r "
            .. tostring(err) .. " |cffaaaaaa(assignment panel)|r")
    end
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

-- Clear = the CURRENT tab only (blessings go through the legacy CLEAR
-- broadcast; totem/duty rows clear for every caster you may edit).
local function ClearCurrentTab()
    if currentTab == 1 then
        RallyPowerCP_Settings.testBless = nil
        if PallyPower_Clear then PallyPower_Clear() end
        Msg("Blessing assignments cleared (for everyone you may edit).")
    elseif currentTab == 2 then
        local els = ElementList()
        for _, s in ipairs(MembersOfClass("SHAMAN")) do
            if A.CanEdit(Me(), s) then
                for i = 1, table.getn(els) do A.SetTotem(s, els[i], nil) end
                A.SetTotemParty(s, nil)
            end
        end
        Msg("Totem assignments cleared.")
    elseif currentTab == 3 then
        for _, entry in ipairs(BufferList()) do
            if A.CanEdit(Me(), entry.name) then
                for c = 0, 9 do A.SetClassBuff(entry.name, c, nil) end
            end
        end
        Msg("Raid buff assignments cleared.")
    elseif DUTY_TAB[currentTab] then
        for _, def in ipairs(DutyList(DUTY_TAB[currentTab])) do
            local holders = A.GetDutyCasters(def.key)
            for i = 1, table.getn(holders) do
                if A.CanEdit(Me(), holders[i].caster) then
                    A.ClearDuty(holders[i].caster, def.key)
                end
            end
        end
        Msg("Assignments on this tab cleared.")
    end
    RefreshCurrent()
end

local function CreatePanel()
    local f = CreateFrame("Frame", "RallyPowerCP_AssignFrame", UIParent)
    frame = f
    f:SetWidth(FRAME_W); f:SetHeight(FRAME_H)
    f:SetScale(RallyPowerCP_Settings.assignScale or 1)   -- before the SetPoint
    local pos = RallyPowerCP_Settings.assignPos
    if pos then f:SetPoint(pos.p, UIParent, pos.rel or pos.p, pos.x, pos.y)
    else f:SetPoint("CENTER", UIParent, "CENTER", 0, 30) end
    f:SetBackdrop(PANEL_BD)
    f:SetBackdropColor(0.055, 0.05, 0.04, 0.96)
    f:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() f:StartMoving() end)
    f:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        -- keep the relative point: grip-scaling re-anchors TOPLEFT->BOTTOMLEFT
        local p, _, rp, x, y = f:GetPoint()
        RallyPowerCP_Settings.assignPos = { p = p, rel = rp, x = x, y = y }
    end)
    f:Hide()
    tinsert(UISpecialFrames, "RallyPowerCP_AssignFrame")   -- ESC closes

    -- header: eyebrow + title (concept), close button, status pills
    local eyebrow = Fnt(f, 9, GOLD_DIM)
    eyebrow:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -12)
    eyebrow:SetText("RALLYPOWERCP  \194\183  ASSIGNMENTS")
    local h1 = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    h1:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -24)
    h1:SetTextColor(GOLD_BRIGHT[1], GOLD_BRIGHT[2], GOLD_BRIGHT[3])
    h1:SetText("Who Covers What")

    CreateFrame("Button", nil, f, "UIPanelCloseButton"):SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)

    -- pills right-to-left: sync, free assign, leader, test
    pills.sync = MakePill(f, 72)
    pills.sync:SetPoint("TOPRIGHT", f, "TOPRIGHT", -34, -26)
    pills.sync.text:SetText("|cff5b8fff\226\151\143|r SYNC")
    pills.sync:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_LEFT")
        GameTooltip:SetText("Sync", 1, 1, 1)
        GameTooltip:AddLine("Blessings sync over PLPWR (stock-PallyPower compatible).", 0.6, 1, 0.6, 1)
        GameTooltip:AddLine("Totems, duties and raid buffs sync over RPCX to other", 0.6, 1, 0.6, 1)
        GameTooltip:AddLine("RallyPowerCP users. /rpc sync forces a refresh.", 0.6, 1, 0.6, 1)
        GameTooltip:Show()
    end)
    pills.sync:SetScript("OnLeave", function() GameTooltip:Hide() end)

    pills.free = MakePill(f, 108)
    pills.free:SetPoint("RIGHT", pills.sync, "LEFT", -4, 0)
    pills.free:SetScript("OnClick", function()
        if not PP_PerUser then return end
        PP_PerUser.freeassign = not PP_PerUser.freeassign
        if PallyPower_SendSelf then pcall(PallyPower_SendSelf) end
        UpdatePills()
    end)
    pills.free:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_LEFT")
        GameTooltip:SetText("Free Assignment", 1, 1, 1)
        GameTooltip:AddLine("When ON, anyone may edit YOUR row (not just lead/assist).", 0.8, 0.8, 0.8, 1)
        GameTooltip:AddLine("Click to toggle.", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    pills.free:SetScript("OnLeave", function() GameTooltip:Hide() end)

    pills.leader = MakePill(f, 88)
    pills.leader:SetPoint("RIGHT", pills.free, "LEFT", -4, 0)

    pills.test = MakePill(f, 78)
    pills.test:SetPoint("RIGHT", pills.leader, "LEFT", -4, 0)
    pills.test.text:SetText("|cffff8800\226\151\143|r TEST RAID")
    pills.test:Hide()

    -- tab row
    for i = 1, table.getn(TAB_INFO) do
        local idx = i
        local b = CreateFrame("Button", nil, f)
        b:SetWidth(114); b:SetHeight(26)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", 14 + (i - 1) * 116, -50)
        b:SetBackdrop(CELL_BD)
        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("CENTER", b, "CENTER", 0, 0)
        local dot = TAB_INFO[i].live and "|cff5be07a\226\151\143|r " or "|cffd8b98a\226\151\143|r "
        fs:SetText(dot .. TAB_INFO[i].label)
        b.label = fs
        b:SetScript("OnClick", function() ShowTab(idx) end)
        tabBtns[i] = b
    end

    -- content box
    -- tabs sit flush on the box top edge (concept: attached tabs)
    local box = CreateFrame("Frame", nil, f)
    box:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -75)
    box:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 62)
    box:SetBackdrop(PANEL_BD)
    box:SetBackdropColor(0.08, 0.072, 0.058, 0.9)
    box:SetBackdropBorderColor(0.23, 0.20, 0.15, 1)

    -- content panels + per-tab chrome (title, desc, note, hint, coverage)
    local CHROME = {
        { "Blessings", "Each paladin's blessing per class, plus their aura and seal - the live PallyPower grid." },
        { "Totems", "Which totem each shaman drops per element, and which group they cover." },
        { "Raid buff coverage", "Which buff each priest, mage and druid gives every class - their strips follow their rows." },
        { "Target debuff duty", "Who maintains each debuff on the kill target." },
        { "Utility & cooldowns", "Soulstones, tank shields, fear ward, innervate." },
    }
    for i = 1, table.getn(TAB_INFO) do
        local p = CreateFrame("Frame", nil, box)
        p:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -8)
        p:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -10, 6)
        p:Hide()
        local t = Fnt(p, 15, GOLD_BRIGHT)
        t:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
        t:SetText(CHROME[i][1])
        local d = Fnt(p, 10, INK_DIM)
        d:SetWidth(520); d:SetHeight(11)
        d:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -21)
        d:SetText(CHROME[i][2])
        p.note = Fnt(p, 11, GOLD, "RIGHT")
        p.note:SetWidth(130); p.note:SetHeight(12)
        p.note:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, -4)
        p.hint = Fnt(p, 9, INK_FAINT)
        p.hint:SetWidth(708); p.hint:SetHeight(22)
        p.hint:SetJustifyV("BOTTOM")
        p.hint:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 0, 14)
        p.cover = Fnt(p, 10, INK_DIM)
        p.cover:SetWidth(708); p.cover:SetHeight(11)
        p.cover:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 0, 1)
        panels[i] = p
    end
    BuildBlessings(panels[1])
    BuildTotems(panels[2])
    BuildBuffGrid(panels[3])
    BuildDutyTab(panels[4], 4)
    BuildDutyTab(panels[5], 5)

    -- bottom buttons: the classic PallyPower frame's row, on our panel
    local function BottomButton(name, label, onclick)
        local b = CreateFrame("Button", name, f, "GameMenuButtonTemplate")
        b:SetWidth(100); b:SetHeight(21)
        b:SetText(label)
        b:SetScript("OnClick", onclick)
        return b
    end
    local bRefresh = BottomButton("RallyPowerCP_AssignBtnRefresh", "Refresh", function()
        if PallyPower_Refresh then pcall(PallyPower_Refresh) end
        RefreshCurrent()
    end)
    bRefresh:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 10)
    local bClear = BottomButton("RallyPowerCP_AssignBtnClear", "Clear", ClearCurrentTab)
    bClear:SetPoint("RIGHT", bRefresh, "LEFT", -4, 0)
    local bOptions = BottomButton("RallyPowerCP_AssignBtnOptions", "Options", function()
        if RallyPowerCP_OptionsToggle then RallyPowerCP_OptionsToggle() end
    end)
    bOptions:SetPoint("RIGHT", bClear, "LEFT", -4, 0)
    local bReset = BottomButton("RallyPowerCP_AssignBtnReset", "Reset Position", function()
        RallyPowerCP_Settings.assignPos = nil
        RallyPowerCP_Settings.assignScale = nil
        f:SetScale(1)
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
    end)
    bReset:SetPoint("RIGHT", bOptions, "LEFT", -4, 0)

    -- scale grip, bottom-right (the PallyPower resize corner); scaling
    -- re-anchors the frame, so persist the new position with the scale
    RallyPowerCP.AddScaleGrip(f, "assignScale", function()
        RallyPowerCP_Settings.assignPos = { p = "TOPLEFT", rel = "BOTTOMLEFT",
            x = f:GetLeft(), y = f:GetTop() }
    end)
    -- blessing presets are a paladin feature (same dropdown as the classic frame)
    local _, mycls = UnitClass("player")
    if mycls == "PALADIN" and PallyPowerMinimapPresetsDropDown then
        local bPresets = BottomButton("RallyPowerCP_AssignBtnPresets", "Presets", function()
            PallyPowerMinimapPresetsDropDown.point = "TOPRIGHT"
            PallyPowerMinimapPresetsDropDown.relativePoint = "BOTTOMLEFT"
            ToggleDropDownMenu(1, nil, PallyPowerMinimapPresetsDropDown,
                "RallyPowerCP_AssignBtnPresets", 0, 0)
        end)
        bPresets:SetPoint("RIGHT", bReset, "LEFT", -4, 0)
    end

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

-- Entry points: strip title right-click, paladin buff bar right-click,
-- /rpc assign.
function RallyPowerCP_AssignPanelToggle()
    if not frame then CreatePanel() end
    if frame:IsShown() then frame:Hide() else frame:Show() end
end

--------------------------------------------------------------------------
-- legacy grafts (PallyPower.lua/.xml stay untouched - we replace globals
-- and re-script XML buttons at load, exactly like the pop-out does)
--------------------------------------------------------------------------

-- Right-clicking the paladin buff bar opens OUR panel; a left-click keeps
-- the classic assignment frame (still reachable, aura/seal columns included).
if PallyPowerBuffBar_MouseUp then
    local origMouseUp = PallyPowerBuffBar_MouseUp
    PallyPowerBuffBar_MouseUp = function()
        local wasShown = PallyPowerFrame and PallyPowerFrame:IsVisible()
        origMouseUp()
        if arg1 == "RightButton" and PallyPowerFrame
           and PallyPowerFrame:IsVisible() and not wasShown then
            PallyPowerFrame:Hide()
            RallyPowerCP_AssignPanelToggle()
        end
    end
end

-- The classic frame's Options button opens OUR tabbed options panel (the
-- classic options frame stays reachable via /rpc legacy).
if PallyPowerFrameOptions then
    PallyPowerFrameOptions:SetScript("OnClick", function()
        if RallyPowerCP_OptionsToggle then
            RallyPowerCP_OptionsToggle()
        elseif PallyPower_Options then
            PallyPower_Options()
        end
    end)
end
