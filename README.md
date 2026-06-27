# RallyPowerCP

**All-class buff management for Turtle WoW 1.18.1 (1.12 client).**
By **Subtilizer (Torchlite)** · version **0.3.2** · see [CHANGELOG.md](CHANGELOG.md).

Built on **PallyPowerTW** (by ivanovlk) and the original **PallyPower** team.

RallyPowerCP keeps PallyPower's Paladin blessing/seal/aura grid exactly as it
was, and adds an auto-detecting buff tracker for every other buffing class. Log
in on a Paladin and you get the full PallyPower grid, unchanged. Log in on a
Priest, Mage, Druid, or Warrior and you instead get a matching bar that tracks
*your* class's group buffs across the party/raid. - see [ROADMAP.md](ROADMAP.md).

---

## What you get per class

| Class | What the bar does |
|-------|-------------------|
| **Paladin** | The original PallyPower grid (blessings, seals, auras). The class bar stays dormant. |
| **Priest** | Power Word: Fortitude, Divine Spirit, Shadow Protection — plus a utility row: PW: Shield and Fear Ward. |
| **Mage** | Arcane Intellect. |
| **Druid** | Mark of the Wild, Thorns. |
| **Warrior** | Battle Shout (self-cast; one click refreshes nearby party). |

More classes are planned — Hunter, Shaman, and Warlock need a different model
(auras, totems, utility) and are on the roadmap in the changelog.

## The class bar

The bar is organized like PallyPower's: **one row per class** present in your
party/raid (in PallyPower's class order), each styled like the Paladin buff-bar
button — your class icon, the buff icon, a status colour (red = someone needs it,
yellow = expiring, green = covered), a count, and that class's earliest timer.

- **Scroll the mouse wheel** over a class row to change *that class's* buff. Each
  row tracks its own buff, so (for example) the Druid row can show Thorns while
  the Mage row shows Arcane Brilliance.
- **Left-click a class row** casts the group/raid version on that class, cycling
  through its members; **right-click** smart-tops-off the one member of that
  class who needs it most (disabled in combat; won't overwrite a buff with 4+
  minutes left).
- **Hover a class row** to open a **pop-out to its left** — a stack of colour-coded
  player bars (green Have / red Need / blue Not Here / dark-red Dead), each with
  the buff icon, the player's name, their personal timer, and a role marker.
  In the pop-out, **left-click a player** to cover their subgroup with the group
  version (skipped if they already have it; disabled in combat), or
  **right-click a player** to single-target just them — which works in combat,
  for topping off the one person who missed it.
- **CTRL+click a player** in the pop-out to set their role: Main Tank (gold) →
  Main Assist (cyan) → none. Roles are saved per character. *(For now they're
  local — not yet shared with other RallyPowerCP users or used by smart
  targeting; that's coming in the role/sync update.)*
- **Countdown timers** turn the row yellow and play a **ding** at 60 seconds
  left — for every tracked buff, even one scrolled off the rows. Times are exact
  for buffs on you; for others they count down from your cast (the 1.12 client
  can't read other players' buff durations — the same limit PallyPower works
  around the same way).
- **Utility row** (currently Priest): situational single-target casts. PW: Shield
  goes to your target, else the lowest-health member in range; Fear Ward goes to
  your target, else you.
- Only buffs you've learned appear, so the bar scales with level/spec.
- **Drag** to move; position is saved per character.

## Commands & key binding

| Command | Description |
|---------|-------------|
| `/pp`, `/pallypower`, `/rp`, `/rallypower` | Paladin grid / buff bar (PallyPower) |
| `/rpc` | Toggle the all-class buff bar (non-Paladins) |
| `/rpc reset` | Reset the class bar's position |
| `/rpc icon` | Cycle the minimap icon skin (any class; or **shift-click** the icon) |
| `/rpc icon <name>` | Set a skin directly: `blue`, `ivory`, `white`, `gold`, `pearl` |

Bind **"Smart buff: next member missing any buff"** under RallyPowerCP in the
Key Bindings menu to top off the group hands-free — each press buffs the next
member missing anything.

## Minimap icon

Shown for every class (toggle it in Options). **Left-click** opens the right
thing for your class — the Paladin grid on a Paladin, the class bar on everyone
else. **Right-click** opens Options. **Shift-click** cycles the icon skin. Five
skins ship (Blue & Gold default, Ivory, White, Gold, Pearl).

## Installation

1. Put the `RallyPowerCP` folder in `Interface/AddOns/` (the folder name must
   match `RallyPowerCP.toc`).
2. That's it — all art, sounds, and textures are bundled, and every path is
   verified against a real file.

## Architecture (for tinkering)

RallyPowerCP's all-class bar follows an AutoRota-style layout:

- **`RallyPowerCP_Core.lua`** — the class-independent engine: roster scanning,
  buff detection, casting, the bar UI, timers, tooltips, scrolling, minimap
  skins, and slash commands. It knows nothing about specific classes.
- **`Classes\Class_<Name>.lua`** — one module per class. Each registers with
  `RallyPowerCP:NewClass("TOKEN")` and supplies only its data.

The Paladin side is the original PallyPower engine (`PallyPower.lua` + `.xml`)
and is deliberately left intact.

### Adding a class or buff

Copy an existing `Classes\Class_<Name>.lua`, change the token and data, and list
the file in `RallyPowerCP.toc`. Buff entry fields:

```lua
{ name     = "Power Word: Fortitude",        -- single-target spell name
  group    = "Prayer of Fortitude",          -- group/greater version (optional)
  icons    = { "Spell_Holy_WordFortitude" }, -- applied-aura icon basename(s)
  pet      = true,                           -- also track on pets (optional)
  dur      = 30*60, gdur = 60*60,            -- durations in seconds (timers)
  selfcast = true }                          -- shout/aura cast on self (optional)
```

Buffs are detected by **icon texture** — the only reliable way to read another
player's buffs on the 1.12 client.

## Compatibility

- **Paladin sync works.** RallyPowerCP keeps PallyPower's sync channel (prefix
  `PLPWR`) and message format, so a RallyPowerCP Paladin coordinates blessings
  with players running original PallyPower / PallyPowerTW in both directions.
- **The class bar is local-only** — it sends nothing over the network, so it
  can't conflict with anyone, but it also doesn't coordinate between two casters
  of the same class yet (that's the cross-caster sync on the roadmap).

## Known limitations

- On the 1.12 client there is no way to read how much time is left on another
  player's buff, so non-self timers count down from your own casts.
- "In range" uses the game's visibility check, which is a wider radius than buff
  range; an out-of-range cast cancels cleanly and the next click moves on.
- PW: Shield can't see who your tank is yet (role assignment is on the roadmap),
  and it may pick a Weakened-Soul target, in which case the cast simply fizzles.

# 🛡️ RallyPowerCP — Roadmap

**Author:** Subtilizer (Torchlite)
**Target:** Turtle WoW 1.18.1 (1.12 client, Lua 5.0)
**Current version:** 0.3.2
**Goal of this document:** turn the functional spec into an *ordered* plan —
what's done, what depends on what, and the sequence to reach a full 1.0.

This is the planning companion to the functional spec. The spec defines *what*
every feature does; this defines *in what order* we build them and *why*.

---

## North Star

RallyPowerCP is an **all-class raid buff / debuff / utility coordinator** for
Turtle WoW, modelled on PallyPower but extended so every class — not just
Paladins — gets the same fast assign-and-rebuff workflow. A Druid coordinates
Mark/Gift/Thorns, a Shaman coordinates totems per party, a Warrior coordinates
who maintains Sunder, and so on — each through one consistent interface.

Two design commitments drive the architecture:

1. **Paladin is the baseline.** The Paladin blessing model is the reference
   implementation. Every other class follows its patterns for the grid,
   assignment, sync, and combat rules. Today the code is backwards — Paladin
   runs in a separate legacy engine while the new classes use a fresh modular
   system Paladin doesn't participate in. A core goal of this roadmap is to
   **flip that**: make Paladin *just another module* in the same system.

2. **One module per class (AutoRota-style).** The Core is class-independent.
   Each class ships a self-contained `Classes\Class_<Name>.lua` that the Core
   loads based on the player's class. Adding or changing a class never touches
   the engine — exactly the compartmentalisation we used in AutoRota.

---

## Architecture principles

### The Core / Module split

- **Core (`RallyPowerCP_Core.lua`)** owns everything class-independent: the bar,
  the grid, the pop-out, roster scanning, buff/debuff detection, the cast
  pipeline, combat lockout, sync, saved variables, options, slash commands, and
  the minimap button.
- **Modules (`Classes\Class_<Name>.lua`)** own only *data and class-specific
  behaviour*. Each registers itself via `RallyPowerCP:NewClass("<TOKEN>")` and
  declares what it needs. The Core picks `active = classes[PLAYER_CLASS]` on
  login and drives the UI from that.

### Every class has two halves

The spec splits each class into the same two regions, and so should the code:

- **Grid Layout** — *friendly-class buffs* applied across the raid (Fortitude,
  Mark, Arcane Intellect, Blessings). This half is **largely built**.
- **Top Anchor Controls** — *global utility that does not target a friendly
  class*: personal auras/seals, enemy debuffs, totems, soulstones, stings,
  shouts. This half is **mostly not built** and is where the remaining work
  lives.

### Target module interface (what each `Class_<Name>.lua` declares)

```
local M = RallyPowerCP:NewClass("DRUID")

M.grid = {            -- friendly-buff grid entries (the existing model)
  { name, group, icons = { ... }, pet, dur, gdur, selfcast },
  ...
}

M.anchor = {          -- NEW: top-anchor controls, one entry per button
  { kind = "cycle",  ... },   -- wheel through options (curses, stings, totem choices)
  { kind = "assign", ... },   -- duty assignment (who maintains Sunder / Expose)
  { kind = "totem",  ... },   -- four-element totem assignment (Shaman)
  { kind = "special",... },   -- bespoke logic + glow states (Soulstone)
  { kind = "self",   ... },   -- personal toggles (auras, seals, Righteous Fury)
}
```

The Core renders and wires each `kind` generically, so a new class is *data plus
a small amount of class glue*, never a new engine. Defining these `kind`s once
(in the Top Anchor framework milestone) is what makes Warrior, Rogue, Mage,
Hunter, and Warlock cheap instead of five separate builds.

---

## Status — done through 0.3.2

The **entire friendly-buff grid half** is complete for every class that has one:

- **Grid + class rows** — one row per class present, class icon + buff icon +
  earliest timer + needy count, styled like the Paladin buff bar.
- **Interactive pop-out** — hover a class row to open a left-expanding panel of
  colour-coded player bars (green Have / red Need / blue Not Here / dark-red
  Dead), each with buff icon, name, personal timer, and a role marker.
- **Per-class mouse-wheel** — each row cycles *its own* buff (Druid row toggles
  Mark → Gift → Thorns independently of other rows).
- **Casting** — left-click group version, right-click smart top-off / single
  target; combat lockout (right-click single is the only in-combat action);
  4-minute no-overwrite guard; throttle guard; 60-second "ding".
- **Local role markers** — CTRL+click a player cycles Main Tank / Main Assist
  (saved per character; not yet synced or wired to targeting).
- **Class modules shipped** — Priest (Fortitude / Divine Spirit / Shadow
  Protection + PW:Shield / Fear Ward utility), Mage (Arcane Int/Brilliance),
  Druid (Mark/Gift + Thorns), Warrior (Battle Shout). Paladin runs in the
  original PallyPower engine (works, but separate — see M0).
- **Plumbing** — minimap button + skins, slash commands, saved position.

### Known 1.12 client limits we design around

- Can't read *names* of buffs on other players → detect by icon texture.
- Can't read *remaining time* on other players' buffs → timers count from *your*
  cast. **Sharing cast times over sync (M1) is the only way to fix this.**
- Reliable cast = clear self-cast CVar, ClearTarget, cast, SpellTargetUnit,
  restore.

---

## Why the order matters (dependency chain)

Most remaining spec features are **coordination** features — a leader assigns who
does what and everyone sees it. That creates a hard dependency order:

1. **Unify the architecture first (M0).** Sync, roles, and the Top Anchor should
   be built *once* into a single Core that every module — Paladin included —
   inherits. Building them while Paladin is still a separate engine means
   building them twice. So the cleanup/baseline work comes first.
2. **Then the coordination backbone (M1).** Sync + roles + Free Assignment Mode.
   This converts RallyPowerCP from a personal helper into a raid tool, and fixes
   the "can't see others' timers" limit. The Priest Tank Shield, and every
   debuff-duty feature, depend on it.
3. **Then the Top Anchor framework + debuff model (M2).** A reusable control
   strip and a reusable "who maintains this enemy debuff" model, designed once.
4. **Then the per-class Top Anchor modules (M3).** Each class drops onto the M2
   framework as an independent point release, in whatever priority you choose.
5. **Polish to 1.0 (M4).**

---

## Milestones

### M0 — Foundation & Cleanup *(target 0.4.x)* — “Paladin becomes the baseline”

**Goal:** stop having two parallel systems. Establish the Paladin module as the
canonical reference and bring the legacy PallyPower base into the unified,
modular architecture.

**Scope**
- Define the **canonical module interface** (the `M.grid` / `M.anchor` shape
  above), derived from the Paladin model.
- Create **`Class_Paladin.lua`** expressing the blessing set in the module
  format, so Paladin is conceptually "just another module." *(Staged — see the
  risk note; this wraps/aligns the existing engine rather than rewriting it
  wholesale.)*
- **Reconcile the seams** between `PallyPower.lua` (the mature paladin engine)
  and `RallyPowerCP_Core.lua`: one options panel, one slash-command surface, one
  minimap entry, one consolidated set of saved variables.
- **Dead-code cleanup** — remove the orphaned single-row pop-out functions and
  any unreferenced tables left from earlier iterations.
- **Naming decision** — choose whether to migrate internal `PallyPower_*` symbols
  to `RallyPowerCP_*` or leave them for stability, and document the call.

**Depends on:** nothing — this is the base everything else builds on.

**Definition of done:** Paladin is selectable through the same module path as the
other classes; there is one options/slash/minimap surface; no orphaned code; the
module interface is documented in-repo.

> **Risk note:** the paladin engine is the most mature, working part of the
> project. M0 should be **staged and low-risk** — wrap and align it behind the
> module interface and clean the seams; do **not** attempt a big-bang rewrite of
> the blessing/sync logic. Deep migration of its internals can be deferred
> indefinitely as long as it presents through the common interface.

---

### M1 — Coordination Backbone *(target 0.5.x)* — sync, roles, free assignment

**Goal:** make assignments and timers shared across RallyPowerCP users, so the
addon coordinates a raid instead of one player.

**Scope**
- **Addon-message sync** for the class bar, mirroring the proven PallyPower
  approach (its own prefix; throttled). Share **assignments** and **cast times**
  between RallyPowerCP users.
- **Real role system** — tank / healer / assist tables built on the existing
  local CTRL+click markers, now **synced**; resolve conflicts sanely.
- **Wire roles into targeting** — deliver the **Priest Tank Shield**: a control
  that shields assigned Main Tanks / Main Assists without hunting the grid.
- **Free Assignment Mode** — leader toggle that lets non-leaders edit their own
  buff/debuff/aura assignments; enforced through sync.
- Formalise **combat lockout** as a shared rule (already implemented client-side).

**Depends on:** M0 (sync/role hooks live in the unified Core).

**Definition of done:** two RallyPowerCP users see the same assignments; a buff
cast by one shows a real countdown on the other; Free Assignment Mode gates edits
by leader status; the Priest Tank Shield targets assigned roles.

---

### M2 — Top Anchor Framework + Debuff Model + Drag Dot *(target 0.6.x)*

**Goal:** build the reusable machinery that makes every utility/debuff class
cheap, plus the global control surface from the spec.

**Scope**
- **Top Anchor control strip** — a reusable Core region above the grid that
  renders the `M.anchor` `kind`s (`cycle`, `assign`, `totem`, `special`,
  `self`) generically.
- **Enemy-debuff "duty" model (designed once)** — detect a debuff on the current
  target, assign a player to maintain it, and show covered / slipping / missing.
  This single model serves Warrior, Rogue, Mage, Hunter, and Warlock.
- **The Drag Dot** (spec) — top-center handle: hover tooltip; left-click
  locks (red) / unlocks (green) with 30-second auto-lock; right-click opens Buff
  Assignment config; shift-right-click opens the Options Panel.

**Depends on:** M1 (duty assignment is a coordination feature; uses sync).

**Definition of done:** a placeholder `assign`/`cycle` control can be dropped into
any class module and works end-to-end (render, assign, sync, status colour); the
Drag Dot exposes lock + both config menus.

---

### M3 — Per-Class Top Anchor Modules *(target 0.7.x – 0.9.x)*

Each class is an independent point release on the M2 framework. Build order is
**flexible** — reorder freely by your priorities. Suggested order by
value-to-effort:

| Order | Class | Top Anchor work | Notes |
|------|--------|-----------------|-------|
| 1 | **Priest** | Tank Shield | Mostly delivered in M1; confirm + polish |
| 2 | **Warrior** | Sunder / Thunder Clap / Demo Shout duty | Module exists; Battle Shout done |
| 3 | **Shaman** | 4-element totem assignment per party | Flagship; largest single module |
| 4 | **Warlock** | Curse cycle + Soulstone button (glow states) | Two bespoke `kind`s |
| 5 | **Hunter** | Serpent / Viper / Scorpid sting duty | Straight `assign`/`cycle` |
| 6 | **Rogue** | Expose Armor duty (coordinated w/ Warrior Sunder) | Shares Warrior's armor logic |
| 7 | **Mage** | Frostbolt / Scorch debuff coordination | Small; grid half already done |
| 8 | **Paladin** | Auras / Seals / Righteous Fury (self toggles) | Completes the baseline class |

**Depends on:** M2 (framework + debuff model + duty assignment).

**Definition of done (per class):** the class's Top Anchor controls render,
assign, sync, and track status; documented in CHANGELOG; localised strings added.

---

### M4 — Polish & Spec Fidelity *(approaching 1.0)*

**Goal:** close the gaps between "works" and "matches the spec exactly."

**Scope**
- **Pets as their own grid row** (currently players-only).
- **Two-column layout decision** — the spec describes an always-visible Left
  (player/status) + Right (class/buff) column grid; the current build uses a
  single class row + hover pop-out. Decide whether to match the spec literally
  or keep the (arguably cleaner) current approach, and align.
- **Options Panel** completeness (all toggles surfaced; Free Assignment, skins,
  thresholds, sound).
- **Localisation** pass for all new strings (deDE / esES already scaffolded).
- Final cleanup, performance check on 40-man, edge-case pass on the pop-out
  hover timing and left-anchor screen-edge behaviour.

**Definition of done:** every line item in the functional spec is represented in
the build.

---

### 1.0 — Full spec coverage

All classes, both halves (Grid + Top Anchor), shared assignments and roles, Free
Assignment Mode, the Drag Dot and Options Panel, pets, and a unified codebase
with Paladin as a first-class module.

---

## Design decisions to settle (not yet locked)

- **Paladin internals:** wrap-and-align only, or eventually migrate
  `PallyPower.lua` logic into Core? (M0 assumes wrap-and-align.)
- **Symbol naming:** migrate internal `PallyPower_*` to `RallyPowerCP_*`, or keep
  for stability?
- **Grid layout:** literal two-column spec layout vs. current row + pop-out.
- **Sync scope:** RallyPowerCP-only protocol, or stay interoperable with stock
  PallyPower/PallyPowerTW on the shared paladin prefix where it overlaps?
- **Role taxonomy:** keep MT / MA, or expand (Healer, Off-Tank, Kicker, etc.)?

---

## Risks & guardrails

- **Touching the paladin engine (M0)** is the highest-risk work in the project —
  stage it, wrap don't rewrite, keep the working blessing/sync path intact.
- **Sync (M1)** is invisible until tested with a second client — budget time for
  two-account testing; throttle carefully on the 1.12 message pipeline.
- **Debuff model (M2)** must be designed before the first debuff class, or it
  gets reinvented five times. Design once, reuse everywhere.
- **1.12 verification:** no standalone Lua available, so keep running the
  paren/brace/keyword-balance + definition-order check after every edit, and
  test in-client.

---

## Appendix — Spec coverage matrix

| Class | Grid (friendly buffs) | Top Anchor (utility/debuff) |
|-------|----------------------|------------------------------|
| Paladin | ✅ via legacy engine → **module in M0** | ❌ Auras/Seals/RF (M3) |
| Priest | ✅ Fort / Spirit / Shadow Prot | ⚠️ Tank Shield (M1) |
| Druid | ✅ Mark/Gift + Thorns | — none required |
| Mage | ✅ Arcane Int/Brilliance | ❌ Frostbolt/Scorch (M3) |
| Warrior | — none required | ⚠️ Battle Shout done; Sunder/TC/Demo (M3) |
| Shaman | — none required | ❌ Totems ×4 (M3, flagship) |
| Warlock | ⚠️ Blood Pact (minor) | ❌ Curses + Soulstone (M3) |
| Hunter | — none required | ❌ Stings ×3 (M3) |
| Rogue | — none required | ❌ Expose Armor (M3) |

✅ done · ⚠️ partial · ❌ not started · — not applicable

**Cross-cutting (all classes):** sync + shared timers (M1), role system (M1),
Free Assignment Mode (M1), Drag Dot + Options Panel (M2), pets row (M4).

## Credits

- RallyPowerCP by **Subtilizer (Torchlite)**.
- Based on **PallyPowerTW** by ivanovlk.
- Original PallyPower by Hjorim / Sneakyfoot / Rake / Xerron / Azgaardian /
  Aznamir. Spanish localization by Nuevemasnueve.
