# 📋 RallyPowerCP — Shared Assignment Data Model (design)

Milestone step 1 of *Assignment & Sync*. This document defines the table
shapes **before any code is written**. Consumers: the sync protocol (step 2)
and the assignment panel (step 3). Scope: the model only — no wire protocol,
no frames.

**Requirements recap (CLAUDE.md):** one table shape covering blessings (keep
PallyPower's existing format), totems (`shaman × element → totem + party`)
and duties (`debuff/utility → caster`); multi-caster from day one; both sync
and the panel consume it. Lua 5.0, 1.12 client.

---

## 1. The one relation underneath all three domains

Every assignment in the game reduces to:

```
(caster, slot) → choice [, scope]
```

| Domain | caster | slot | choice | scope |
|---|---|---|---|---|
| Blessings | a paladin | target class (0–9) | blessing id (0–5) | raid-wide, per class |
| — normal overrides | a paladin | class + player name | blessing id | one player |
| Totems | a shaman | element (Earth/Fire/Water/Air) | totem spell | one party (1–8) |
| Duties | any player | duty key (SUNDER, SOULSTONE…) | on/off | none / a player / a role |

**Storage is caster-major** — `casters[name] → that player's whole plan` —
for the same reasons PallyPower is:

1. **The sync unit is one caster's block.** "Broadcast own assignments"
   (milestone step 2) is a serialize of `casters[me]`. Receiving stores
   `casters[sender]`. Identical to how `SELF`/`ASSIGN` work today.
2. **Permissions attach to the caster name.** PallyPower's receive rule —
   accept if `sender == name`, or sender is lead/assist, or Free Assignment
   is on — carries over verbatim to every domain.
3. **Roster pruning is one key delete.** Player leaves raid →
   `casters[name] = nil`, exactly like `PallyPower_Assignments[name] = nil`
   on `RAID_ROSTER_UPDATE`.
4. **Multi-caster is free.** Two warlocks each soulstoning a different healer
   are just two caster blocks. Conflicts/duplicates (two rogues both claiming
   Expose Armor) are *representable*, and the panel flags them from the
   derived duty-major index (§5) instead of the store forbidding them.

The `debuff/utility → caster` view the panel shows is a **derived index**,
rebuilt on change notification — never a second source of truth.

---

## 2. Root table (new SavedVariablePerCharacter)

```lua
RallyPowerCP_Assign = {
    v = 1,                         -- schema version (migrations + sync handshake)
    casters = {
        -- [playerName] = one caster block, see below
        ["Stormtide"] = {
            class = "SHAMAN",      -- English class token; set on write, used for
                                   -- pruning sanity + panel row grouping
            seq   = 12,            -- monotonic edit counter, bumped on every local
                                   -- write to this block. Reserved for sync (step 2):
                                   -- receivers keep the highest seq per caster
                                   -- (last-writer-wins with a real ordering).
            totem = { ... },       -- §3, shamans only
            duty  = { ... },       -- §4, any class
        },
    },
}
```

- Persisted per character, like `PallyPower_Assignments` — a raid leader's
  plan survives a relog; pruned on roster update the same way.
- **Blessings are deliberately NOT in this table** (§6). They stay in the
  legacy `PallyPower_*` tables (locked decision: byte-compatible PLPWR
  interop, wrap don't rewrite). The model *wraps* them behind the same API.
- Only hash parts, no arrays with holes, no metatable magic in saved data —
  clean for 1.12's saved-variable writer and Lua 5.0 iteration (`pairs`,
  `table.getn` where lists appear).

## 3. Totem block — `shaman × element → totem + party`

```lua
totem = {
    Earth = "Strength of Earth Totem",  -- exact spell name; nil = unassigned
    Fire  = "Searing Totem",
    Water = "Mana Spring Totem",
    Air   = "Windfury Totem",
    party = 2,                          -- 1-8 = which group this shaman covers;
                                        -- nil = "own subgroup" (follows the shaman)
}
```

- Element keys are the fixed strings already used by `Class_Shaman.ELEMENTS`
  (`Earth/Fire/Water/Air`).
- Choices are **exact spell names**, matching how the whole codebase casts
  (`FindSpell`/`CastSpellByName`) and immune to catalog reordering. Wire
  compaction to numeric ids is the sync layer's job (§7) — storage stays
  readable and directly castable.
- `party` lives on the block, not per element: one shaman covers one group
  with all four drops (matches the concept panel's single Party column).

## 4. Duty block — `debuff/utility/raid-buff → caster`

```lua
duty = {
    -- [dutyKey] = true | "PlayerName" | "@ROLE"
    SUNDER    = true,          -- untargeted duty: maintain on the kill target
    SOULSTONE = "Seraphine",   -- targeted duty: value = the recipient
    FEARWARD  = "@TANK",       -- role-targeted: resolved via role tables at cast time
}
```

Value encoding (Lua 5.0-friendly scalars, no nested tables):

| Value | Meaning |
|---|---|
| `true` | duty claimed, no target (kill-target debuffs, raid-wide buffs) |
| `"Name"` | duty aimed at that player (Soulstone, Innervate, Fear Ward) |
| `"@MT"` / `"@MA"` / `"@HEALERS"` | duty aimed at a role, resolved at cast time |
| absent / `nil` | not assigned |

Player names can never contain `@` (client rule), so the prefix is a safe
discriminator. Role tokens resolve through the existing tables:
`RallyPowerCP_Roles` (local MT/MA markers) and `PallyPower_Tanks` /
`PallyPower_Healers` (already synced via `TANK`/`HEALER` on PLPWR). This is
the hook that finally unlocks **Priest Tank Shield**.

### 4.1 The duty catalog (static data, declared by class modules)

Assignments reference duty *keys*; what a key **means** is declared once, by
the owning class module, into a catalog the panel and sync both read. Nothing
class-specific lives in the engine — same contract as `NewClass`/`M.buffs`.

```lua
RallyPowerCP.Assign.RegisterDuty{
    key    = "SUNDER",          -- stable string key (storage + code)
    wid    = 1,                 -- stable numeric wire id (§7): append-only, never reused
    class  = "WARRIOR",         -- who can hold it (panel filters candidates)
    tab    = "debuff",          -- panel tab: "raidbuff" | "debuff" | "utility"
    spell  = "Sunder Armor",    -- exact spell name (icon via FindSpell, cast path)
    target = "none",            -- "none" | "player" | "role"  (validates the value)
    multi  = false,             -- is >1 caster meaningful (panel warns on duplicates
                                -- when false; never *blocks* — the store allows it)
    dur    = 30,                -- seconds, drives the status timer (§8)
}
```

The concept panel's three duty tabs are one domain filtered by `tab`:

- **Raid Buffs**: `FORTITUDE`, `SPIRIT`, `SHADOWPROT` (Priest), `INTELLECT`
  (Mage), `MARK`, `THORNS` (Druid) — `target="none"`, the grid classes'
  "who maintains this buff" row.
- **Debuffs**: `SUNDER`, `EXPOSE`, `THUNDERCLAP`, `DEMOSHOUT` (Warrior/Rogue),
  `CURSE_ELEMENTS`, `CURSE_SHADOW`, … (Warlock), `WINTERSCHILL`/`SCORCH`
  (Mage), `STING_SERPENT`, `STING_VIPER`, `STING_SCORPID` (Hunter) —
  `target="none"`.
- **Utility**: `SOULSTONE` (`target="player"`), `FEARWARD`,
  `INNERVATE` (`target="player"` or `"role"`).

Note the cycle-strip options become *separate duty keys* (three sting keys,
not one "sting" key with a choice) — a duty is a yes/no claim plus optional
target, which keeps values scalar. The strip still renders one button; it
shows whichever sting key I hold (§9).

Shaman element options live in a parallel **totem catalog** derived from the
existing `ELEMENTS` table in `Class_Shaman.lua` (each totem gains a `wid`);
no second copy of the totem list is created.

## 5. Derived views (built, never stored)

```lua
Assign.GetDutyCasters(dutyKey)  ->  { {caster="Ironclad", target=true}, ... }
Assign.GetTotemCoverage()       ->  [party][element] = { {caster=, totem=}, ... }
```

Rebuilt lazily on a dirty flag set by the change notification (§9). Raid-size
loops (≤40 casters × a handful of slots) are trivial next to the existing
1-second roster scan, so no incremental bookkeeping.

## 6. Blessings — adapter over the legacy engine (unchanged tables)

The blessing store **is and remains**:

```lua
PallyPower_Assignments[pally][classID]  = blessingID   -- greater, classID 0-9 (9=Pet)
PallyPower_NormalAssignments[pally][classID][playerName] = blessingID
PallyPower_AuraAssignments[pally] = auraID
PallyPower_SealAssignments[pally] = sealID
```

synced by the untouched `SELF`/`ASSIGN`/`NASSIGN`/`AASSIGN`/`SASSIGN` PLPWR
messages. The model adds **accessors only**, so panel code addresses all
three domains through one API:

```lua
Assign.GetBlessing(pally, classID)           -- reads PallyPower_Assignments
Assign.SetBlessing(pally, classID, bid)      -- writes it AND sends the legacy
                                             -- ASSIGN message via the engine's own
                                             -- send path (byte-identical wire)
Assign.GetNormalBlessing(pally, classID, playerName)
Assign.SetNormalBlessing(pally, classID, playerName, bid)
```

No blessing data is ever copied into `RallyPowerCP_Assign` — one source of
truth, zero interop risk, honours "wrap, don't rewrite".

## 7. Wire-format reservations (designed now, used in step 2)

The model stores strings; the `RPCX` protocol will not. Reservations made
now so step 2 needs no schema change:

- Every catalog entry (duty and totem) carries a **stable numeric `wid`** —
  append-only, never renumbered, never reused. Cross-version clients ignore
  unknown wids instead of misparsing (spell *names* never cross the wire, so
  Turtle renames can't break sync either).
- `casters[name].seq` orders updates: a receiver drops a block older than
  the one it holds. Leader writes will ride a flag that bypasses seq (leader
  always wins), mirroring PallyPower's permission model.
- `v` (schema version) goes into the sync hello for a compatibility check.
- Blessings ride PLPWR untouched; only totem/duty blocks ride RPCX.

## 8. Runtime status mirror (NOT saved, separate table)

"Assigned" (intent, persisted) and "actually up" (observed, ephemeral) never
mix. The status table mirrors the assignment keying exactly:

```lua
RallyPowerCP.AssignStatus = {
    -- [casterName] = {
    --     totem = { Earth = { name="Strength of Earth Totem", expires=t }, ... },
    --     duty  = { SUNDER = { expires=t, target="Golemagg" }, ... },
    -- }
}
```

Today it is filled only from **my own casts** (the existing cast-derived
timers in the shaman/hunter/… modules move their state here); step 2 fills
other casters' entries from broadcast cast times / SuperWoW
`UNIT_CASTEVENT`. The panel renders assigned-vs-up from the two tables
without either knowing about the other's lifecycle. `GetTime()`-based
deadlines, meaningless across sessions — hence never saved.

## 9. API surface and integration

```lua
local A = RallyPowerCP.Assign

-- mutators (validate via catalog, bump seq, fire change event; "editor" defaults
-- to the local player — CanEdit() gates panel writes, sync gates remote ones)
A.SetTotem(caster, element, totemName)      A.SetTotemParty(caster, party)
A.SetDuty(caster, dutyKey, value)           A.ClearDuty(caster, dutyKey)

-- readers
A.GetTotem(caster, element)                 A.GetTotemParty(caster)
A.GetDuty(caster, dutyKey)                  A.GetDutyCasters(dutyKey)
A.GetCaster(name)                           -- whole block (sync serializes this)

-- policy / lifecycle
A.CanEdit(editorName, casterName)           -- self, or lead/assist, or free-assign
A.PruneToRoster(rosterSet)                  -- drop absent casters (roster event)
A.Subscribe(fn)                             -- fn(domain, casterName) on any change
```

**Strip modules become views of my own row.** Effective selection =
assignment first, local preference second:

```lua
effective totem for Earth =
    A.GetTotem(me, "Earth")                  -- someone (or I) assigned it
    or RallyPowerCP_Settings.shamanSel.Earth -- my solo/offline preference
    or first known totem                     -- current fallback, unchanged
```

Wheeling a strip button keeps writing the local preference and — when
grouped and permitted — also self-assigns (`A.SetTotem(me, …)`), which is
exactly PallyPower's free-assign behaviour of editing your own row. Solo
behaviour is byte-for-byte what ships today; `shamanSel` / `hunterSting` /
`lockCurse` / `roguePoison` stay as the preference layer, no migration.

**File layout:** new `Core\RallyPowerCP_Assign.lua`, listed in the .toc
after `RallyPowerCP_Strip.lua` and **before the class modules** (they call
`RegisterDuty` at load). Popout still loads last.

## 10. Worked example (10-man: 1 shaman, 2 warlocks, 1 warrior, 1 priest)

```lua
RallyPowerCP_Assign = {
    v = 1,
    casters = {
        Stormtide  = { class="SHAMAN",  seq=4,
                       totem = { Earth="Strength of Earth Totem", Air="Windfury Totem", party=2 } },
        Soulbrand  = { class="WARLOCK", seq=2,
                       duty = { CURSE_ELEMENTS=true, SOULSTONE="Seraphine" } },
        Hexweaver  = { class="WARLOCK", seq=1,
                       duty = { CURSE_SHADOW=true, SOULSTONE="Mindveil" } },   -- multi-caster: 2nd stone
        Ironclad   = { class="WARRIOR", seq=7, duty = { SUNDER=true } },
        Seraphine  = { class="PRIEST",  seq=3, duty = { FORTITUDE=true, FEARWARD="@TANK" } },
    },
}
```

Panel reads: Totems tab → row Stormtide, party 2, Earth/Air set, Fire/Water
empty; Debuffs tab → `GetDutyCasters("CURSE_ELEMENTS")` = Soulbrand;
Utility tab → two Soulstone rows (`multi=true`, no warning). Sync sends:
one block per caster. Blessings tab reads the untouched PallyPower tables.

## 11. Explicitly out of scope here

- The `RPCX` message grammar, throttling, and REQ/CLEAR flows — step 2
  (only the `wid`/`seq`/`v` reservations above bind it).
- Panel frames/tabs — step 3 (this model is its complete data source).
- Aura/seal *assignment* UI beyond the legacy engine (already synced on
  PLPWR; adapter accessors can be added the same way as blessings if the
  panel wants a column).
- Turtle-specific duty durations — Vanilla defaults in the catalog, marked
  for on-realm verification like every other duration in the addon.

## 12. Decisions called out for review

1. **Caster-major storage with derived duty-major views** (§1) — the
   milestone phrase "duty → caster" is delivered as the query API, not the
   storage orientation.
2. **Blessings stay legacy; adapter only** (§6). The unified model never
   holds a copy.
3. **Spell names in storage, numeric wids on the wire** (§3, §7).
4. **Cycle options = distinct duty keys** with scalar values (§4.1), not one
   key with an option field.
5. **Strip wheel = local preference + self-assignment**; assignment wins
   over preference when present (§9).
6. **Intent vs status split**: persisted `RallyPowerCP_Assign` vs ephemeral
   `RallyPowerCP.AssignStatus` (§8).
