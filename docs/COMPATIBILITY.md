# 🔧 RallyPowerCP — Client Compatibility Strategy (SuperWoW + VanillaFixes)

**Platform:** Turtle WoW 1.18.1 — a **1.12.1** custom client (Lua 5.0)
**Required client mods:** **SuperWoW** and **VanillaFixes**
**Status:** planning doc for the "make it 1.18.1-native" pass, written after
Phase 1 (the Paladin pop-out reached PallyPower-3.3.5 parity, v0.5.1).

---

## The core reframe

The addon we forked is **PallyPower Classic**, whose living codebase targets
**Blizzard's Classic Era / WotLK** client (Ace3, secure templates, modern API).
We are porting its *design* onto a **1.12.1** client. Two jobs, in order:

1. **Compatibility pass** — make the Paladin addon genuinely native to Turtle
   1.18.1 on the 1.12 client, using SuperWoW where it removes a limitation.
2. **All-class rollout** — then extend to Shaman, Priest, Mage, Druid, Warlock,
   Warrior. **Most non-Paladin classes are intentionally simplified/"dumbed
   down"** versions of the Paladin template, not full re-implementations.

The two required client mods do very different things, and it's important not to
conflate them.

---

## VanillaFixes — a runtime requirement, *not* a coding surface

VanillaFixes eliminates stutter and animation lag by forcing the client to use a
high-precision timer. Key facts for us:

- It exposes **no Lua API**. There is nothing for the addon to call or detect.
- It doesn't modify the executable or run during gameplay — it's unloaded by the
  time you reach the login screen.
- **Implication for RallyPowerCP:** it is purely an install-time prerequisite
  for players (smoother client, better `OnUpdate` cadence). We **document** it as
  required; we **do not** code against it. Our `OnUpdate`-driven timers simply
  benefit from the steadier frame timing.

That's the whole story for VanillaFixes. Everything below is SuperWoW.

---

## SuperWoW — the features that change how we build

SuperWoW extends the 1.12 API. Several features directly reverse compromises
currently baked into the addon. Grouped by how much they change our plans:

### 🔴 Game-changers (adopt during the compatibility pass)

**1. `UnitBuff` / `UnitDebuff` now return the aura's spell ID.**
Today we identify buffs by **icon texture** because 1.12 can't read buff *names*
on other units, and many buffs share an icon. With SuperWoW we can read the
actual **spell ID** of each aura on any unit.
- *Replaces:* the icon-basename matching in the Core scanner and everywhere
  `UnitHasBuff` guesses by texture.
- *Wins:* exact detection (no more "same icon" collisions), correct rank/variant
  detection, and it generalises cleanly to every class's buffs and debuffs.
- *Also:* `GetPlayerBuffID(buffindex)` and `SpellInfo(spellid)` (name, rank,
  texture, min/max range) give us a real spell database at runtime — no more
  hard-coded icon tables per class.

**2. `CastSpellByName(spell, unit)` — cast directly on a unit.**
SuperWoW lets `CastSpellByName` take a **unit as the 2nd argument**.
- *Replaces:* the entire `autoSelfCast` CVar dance + `ClearTarget` →
  `CastSpell` → `SpellTargetUnit` → `TargetLastTarget` pipeline in both the Core
  caster and the new pop-out click handler.
- *Wins:* casting becomes a single call that can't disturb the player's current
  target — dramatically simpler and less fragile. This is the single biggest
  code-simplification opportunity in the port.

**3. `UNIT_CASTEVENT` — real cast tracking.**
A true event for cast start/finish/interrupt/channel/swing, with caster GUID,
target GUID, event type, **spell id**, and duration.
- *Enables:* knowing precisely when *we* land a blessing/buff (start a timer at
  the exact cast), and seeing other players' casts.
- *Feeds:* the M1 "shared timers" idea — combined with GUIDs this makes timer
  bookkeeping far more accurate than "count down from when I clicked".

### 🟡 Strong enablers (use as we build the relevant class/feature)

**4. GUIDs everywhere.** `UnitExists` returns a GUID; unit functions accept a
GUID; nameplates expose GUIDs via `frame:GetName(1)`. Lets us track a specific
player/pet/totem unambiguously across the roster — better than name matching
(which breaks on cross-realm/duplicate names and pets).

**5. Owner suffix + totem/pet awareness.** Any unit function accepts an `owner`
suffix (e.g. `UnitName("targetowner")` on a totem returns the Shaman). Unit
frames/combat log append the **owner name** to pets and totems.
- *Directly enables the Shaman module:* totems become trackable (who dropped
  what, whose totem is whose party) — the single hardest class in the spec.

**6. Marker-unit access + solo markers.** Any unit function accepts `mark1`..
`mark8` to resolve the marked unit; `SetRaidTarget` takes a `local` flag to mark
solo. Useful for role/target coordination (tanks, assist, curse targets).

**7. `UNIT_CASTEVENT` + ranged/aimed shot fixes, absorb/heal in combat log.**
Peripheral to buffs, but relevant when we get to debuff-duty classes (Hunter
stings, Warrior/Rogue debuffs) that need to see hits/casts land.

### 🟢 Minor / situational

- `SpellInfo` **min/max range to target** → real range checks (improves the
  pop-out's "R" range indicator, which today can't show the yellow
  "visible-but-far" state).
- `TrackUnit` / `UnitPosition` (friendly units) → potential range/positioning
  aids.
- Larger macro limits, chat/combat-log niceties → not needed by this addon.

---

## What the compatibility pass actually changes in our code

Concrete, in priority order:

1. **Buff detection → spell IDs.** Replace icon-basename matching with
   `UnitBuff`/`UnitDebuff` spell-id reads (fallback to icon match only if
   SuperWoW is absent — see the guard below). Central to the Core scanner.
2. **Casting → `CastSpellByName(spell, unit)`.** Rip out the CVar/target dance
   in the Core caster and the pop-out click handler; replace with the direct
   unit cast. Keep the cooldown check and the double-click guard.
3. **Timers → `UNIT_CASTEVENT`.** Start per-target timers on the confirmed cast
   event (with the real spell id + duration) instead of on click. Keeps the
   pop-out's individual timers honest, and lays groundwork for M1 shared timers.
4. **Identity → GUIDs.** Where we currently match by unit name, prefer GUIDs for
   the roster/pop-out so pets, totems, and duplicate names behave.

Each of these is a *simplification* — SuperWoW lets us delete fragile 1.12
workarounds, not add complexity.

### Compatibility guard

SuperWoW is **required**, but we should fail gracefully and detect it:

```lua
local HAS_SUPERWOW = (SUPERWOW_VERSION ~= nil)
```

- If present (the norm on Turtle): use the spell-id / direct-cast / cast-event
  paths.
- If absent: keep the current icon-match + CVar-cast fallback so the addon still
  loads, and print a one-time notice that SuperWoW is recommended/required for
  full accuracy.

This keeps a single codebase that's *native* to the SuperWoW client without
hard-crashing a player who hasn't installed it yet.

---

## How this reshapes the roadmap

- **New milestone, inserted before the class rollout — M0.5 "1.18.1-native
  pass":** adopt features 1–4 above in the Core + Paladin path, behind the
  `HAS_SUPERWOW` guard. Outcome: the Paladin addon is genuinely native to Turtle
  1.18.1, and the plumbing every other class will inherit (detection, casting,
  timers) is the good SuperWoW version, not the 1.12-workaround version.
- **Then the class rollout (Shaman, Priest, Mage, Druid, Warlock, Warrior)**
  builds on that native plumbing. Because most classes are **simplified**
  versions of the Paladin template, and because SuperWoW gives real spell-id
  detection and one-call casting, each class module stays small: declare its
  buffs/debuffs (by spell id) and lean on the shared engine.
- **Shaman specifically** now has a real path via the **owner suffix / totem
  awareness** (feature 5) — worth keeping as its own milestone, but no longer
  blocked on guesswork.

---

## Open questions to confirm before the pass

- **Minimum SuperWoW version** we target (the spell-id returns and
  `CastSpellByName(unit)` must be present in Turtle's bundled build). We gate on
  `SUPERWOW_VERSION`; do we also want a minimum-version check?
- **Turtle deltas:** Turtle 1.18.1 has its own custom spells/ranks/durations
  (blessings already needed forced Turtle durations). The spell-id approach must
  use Turtle's ids where they differ from Vanilla. We'll verify ids on-realm.
- **Keep interop** with stock PallyPower/PallyPowerTW on `PLPWR` — unchanged by
  this pass, but the sync payload should stay compatible even as our internal
  detection moves to spell ids.

---

## TL;DR

- **VanillaFixes:** install-time requirement, smoother timing, **no code**.
- **SuperWoW:** the real porting surface — adopt **spell-id buff detection**,
  **`CastSpellByName(spell, unit)`**, **`UNIT_CASTEVENT` timers**, and **GUIDs**.
  These *remove* 1.12 hacks rather than add complexity.
- **Do the 1.18.1-native pass on Paladin first**, behind a `HAS_SUPERWOW` guard,
  then roll the (mostly simplified) other classes onto that native plumbing.
