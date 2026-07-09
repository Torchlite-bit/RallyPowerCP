# CLAUDE.md — RallyPowerCP

Project brief for Claude Code. Read this fully before editing anything.

## What this is

**RallyPowerCP** extends the PallyPower paladin buff addon to **all nine
classes** — a unified raid buff/utility coordinator for **Turtle WoW 1.18.1**,
which is a **1.12.1 client (Lua 5.0)** with the **SuperWoW** and **VanillaFixes**
client mods. It is a fork of PallyPowerTW; the **visual and functional gold
standard is PallyPower 3.3.5 (WotLK)** — reference source:
`github.com/AznamirWoW/PallyPower` (clone it; `PallyPower_Wrath.xml` +
`PallyPowerValues.lua` are the spec for frames, colors, dimensions).

Current version: **0.12.0**. See `CHANGELOG.md` for the full history and
`docs/` for the design documents and interactive HTML concepts.

## Hard environment rules (violating these bricks the addon)

**Lua 5.0, not 5.1.** Never use:
- `#` length operator → use `table.getn(t)`
- `string.gmatch` → use `string.gfind`
- `select(...)` → does not exist
- numeric `%` modulo → use `math.mod`
- varargs beyond the implicit `arg` table

**1.12 widget API:**
- Frame handlers receive **implicit globals**: `this`, `event`, `arg1`… —
  there is no `self`/`event` parameter.
- **Definition order matters**: a `local function` must be defined before any
  reference, or forward-declared (`local Foo` … later `Foo = function() end`).
- No `C_Timer`, no secure templates, **no combat lockdown** (casting from code
  is legal in combat — a genuine advantage over retail).
- Timers/tickers = `OnUpdate` with an accumulator on `arg1`.

**SuperWoW** (detected via `SUPERWOW_VERSION`) — always guard and always keep a
bare-1.12 fallback:
- `UnitBuff(unit, i)` additionally returns the aura **spell id** (3rd return);
  `UnitDebuff` returns it 4th.
- `CastSpellByName(spell, unit)` casts directly at the unit (no target dance).
- Buff/debuff **ids are learned at runtime** from the icon seed — never
  hard-code aura ids (Turtle's may differ from Vanilla).

**Turtle deltas:** blessing durations are forced (10 min normal / 30 min
greater). Totem/sting/curse durations use Vanilla defaults at the top of each
class module — verify on-realm and edit there if Turtle differs. Spell-name
matching is exact; if a Turtle rename breaks a lookup, fix the name string.

## Verification workflow (mandatory)

After **every** edit:

```
python3 scripts/verify.py
```

Checks structural balance and Lua 5.1-isms across `Core/` + `Classes/`. There
is no standalone Lua here; the real test is in-game — errors print to chat
(the Core wraps risky paths in `pcall` and prints `RallyPowerCP error: …`).
Use `/rpc test` (test mode) to exercise everything on an under-levelled
character: all options appear (unlearned marked `*`), clicks simulate casts
and start real timers.

## Architecture map

Load order (`RallyPowerCP.toc`):
```
Locale\*                       localization
PallyPower\*                   the ORIGINAL PallyPower engine (see below)
Core\RallyPowerCP_Core.lua     class-independent coverage engine + class-buff strip
Core\RallyPowerCP_Strip.lua    shared strip engine + helpers
Classes\Class_*.lua            one module per class
Core\RallyPowerCP_Options.lua  the tabbed options frame
Core\RallyPowerCP_Popout.lua   loads LAST (legacy hover handler + paladin test graft)
```

**Every non-paladin class is now a strip.** There is one visual family: the
100×34 paladin-template button, stacked in a movable titled strip (drag dot,
scale grip, saved position). Priest/Mage/Druid render the **class-buff strip**
(`RallyPowerCP.BuildClassBuffs`, one button per raid class, with the player
pop-out on hover); Warrior/Shaman/Hunter/Warlock/Rogue render their own
self-contained strips. No bespoke grid bar exists anymore.

**Paladin = the legacy engine, wrapped not rewritten (locked decision).**
`PallyPower\PallyPower.lua/.xml` run unmodified; `PallyPower.xml` loads its lua
via a relative `<Script>` (they must stay in the same folder). The player
pop-out (`Core\RallyPowerCP_Popout.lua`) grafts onto its buff bar by replacing
`PallyPowerBuffButton_OnEnter`, reading the engine's own per-button data
(`btn.have/need/range/dead`, `LastCastPlayer`) and casting through its
spellbook tables (`AllPallys`, `GetNormalBlessings`). The pop-out rows are an
exact replica of the WotLK `PallyPowerPopupTemplate` (100×34, Smooth skin +
Blizzard Tooltip border, official colors: Good `0,0.7,0` / NeedAll `1,0,0` /
Special `0,0,1`, all 0.5 alpha).

**Class-buff classes** (Priest, Mage, Druid): declare
`M = RallyPowerCP:NewClass("TOKEN"); M.buffs = { {name, group, icons, ids?,
pet, dur, gdur, selfcast}, ... }` (+ optional `M.utility`), plus
`M:OnActivate()` = `RallyPowerCP.BuildClassBuffs()` and `M:Toggle()` =
`RallyPowerCP.BuildClassBuffs():Toggle()`. The Core scans the roster, detects
by SuperWoW spell-id (learned from the icon seed) with icon fallback, casts via
`CastBuffOn`, and renders one strip button per raid class (wheel = which buff
for that class, L = group cast, R = smart single, hover = player pop-out).

**Strip classes** (Warrior, Shaman, Hunter, Warlock, Rogue): declare
`M:OnActivate()` (build UI) and `M:Toggle()`. Build UI with the strip engine:
```
strip = RallyPowerCP.NewStrip(key, title)
strip:AddButton{ refresh=fn(b), onClick=fn(b,btn), onWheel=fn(b,delta), tooltip=fn(b,tt) }
strip:Finish()
```
Button helpers inside `refresh`: `b:SetIcon/SetLabel/SetSub/SetTimer` and
`b:SetState("good"|"need"|"off")`. Engine helpers (all cached where hot):
`RallyPowerCP.FindSpell(name)` (spellbook, invalidated on SPELLS_CHANGED),
`FindBagItem(pattern)` (bags, invalidated on BAG_UPDATE),
`UnitHasDebuffEntry(unit, entry)` (icon-seed id-learning),
`CastAtTarget(name)`, `FmtTime(sec)`, `TexBase(path)`,
`RallyPowerCP.IsTestMode()`.
**Buttons are 100×34, 26px icon, 2px gap — the paladin template. Locked.**

**Saved variables:** `RallyPowerCP_Settings` (per character: `testMode`,
strip positions `stripPos_*`, selections `shamanSel`/`hunterSting`/
`lockCurse`/`roguePoison`, hidden flags) + the legacy `PallyPower_*` tables.

## Locked design decisions

1. **PallyPower 3.3.5 parity** — extract exact specs from the reference repo
   before styling anything; never approximate from screenshots.
2. **PLPWR sync interop** — paladin blessing sync stays byte-compatible with
   stock PallyPower/PallyPowerTW; new-class data rides an extended channel.
3. **Paladin engine: wrap, don't rewrite.**
4. **v1 modules are personal-accurate**; cross-player coordination belongs to
   the sync milestone.
5. Non-Paladin classes are **deliberately simplified subsets** of the Paladin
   template (see `docs/DESIGN_ALLCLASSES.md`).

## Next milestone: Assignment & Sync (in this internal order)

1. **Shared assignment data model** — one table shape covering: blessings
   (keep PallyPower's existing format), totems (`shaman × element → totem +
   party`), and duties (`debuff/utility → caster`). Both sync and the panel
   consume this model; design it multi-caster from day one.
2. **Sync protocol** — broadcast own assignments + cast times; receive and
   store others'; leader / "Free Assignment" permissions. Paladin messages
   unchanged on `PLPWR`; new prefix (e.g. `RPCX`) for the rest. Consider
   SuperWoW `UNIT_CASTEVENT` for cast-exact shared timers. Requires
   two-client testing.
3. **Assignment panel** — the five-tab frame from
   `docs/RallyPowerCP_assignment_concept.html` (Blessings live; Totems, Raid
   Buffs, Debuffs, Utility). Replicate frame specs from the 3.3.5 reference
   the same way the pop-out was done.

Small stragglers that can slot in anytime: Mage/Warrior debuff-duty buttons
(30 minutes each on `UnitHasDebuffEntry`), Priest Tank Shield (wants the role
table from sync), Paladin aura/seal/RF toggles (legacy self-bar already
provides them).

**Parallel milestone — Options UI (`docs/OPTIONS_UI_SPEC.md`):** the tabbed
settings frame (reference: PallyPower Classic's Settings/Buttons/Raid tabs).
Its Settings + Buttons tabs are pure local config and can be built **now**,
independent of sync; its Raid tab (roles, auto-buff overrides, Free
Assignment) belongs to the sync milestone and ships as a stub until then.
Follow the spec's module `optionsInfo` contract so one Buttons tab serves
every class.

## Working style

- Version-bump `RallyPowerCP.toc` + README, and write a `CHANGELOG.md` entry
  for every release; be explicit about limitations and Turtle-unverified
  values.
- When behavior must match PallyPower, **read its source and reuse its data**
  rather than re-implementing (see how the pop-out consumes engine tables).
- Commit small; test in-game between steps; `/reload` is the loop.
