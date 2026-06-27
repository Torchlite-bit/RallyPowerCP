# 🛡️ RallyPowerCP — Roadmap

**Author:** Subtilizer (Torchlite)
**Target:** Turtle WoW 1.18.1 (1.12 client, Lua 5.0)
**Current version:** 0.3.2
**Goal of this document:** turn the functional spec into an *ordered* plan —
what's done, what depends on what, and the sequence to reach a full 1.0.

This is the planning companion to the functional spec. The spec defines *what*
every feature does; this defines *in what order* we build them and *why*.

> **Locked decisions (this revision):**
> - **Sync stays compatible** with stock PallyPower / PallyPowerTW on the shared
>   paladin prefix where the two overlap. RallyPowerCP extends the protocol for
>   the new classes but does not break paladin interop.
> - **Layout = the PallyPower paladin self-bar, universally.** A single vertical
>   strip of buttons per class — *not* the two-column grid. Paladin is the
>   literal template for every class's bar.

---

## North Star

RallyPowerCP is an **all-class raid buff / debuff / utility coordinator** for
Turtle WoW, modelled on PallyPower but extended so every class — not just
Paladins — gets the same fast assign-and-rebuff workflow, in the same compact
button bar a paladin already uses.

Two design commitments drive the architecture:

1. **Paladin is the baseline — in code *and* in layout.** The paladin blessing
   model is the reference implementation, and the paladin self-bar is the
   reference UI. Every other class follows both. Today the code is backwards:
   Paladin runs in a separate legacy engine while the new classes use a fresh
   modular system Paladin doesn't participate in. A core goal of this roadmap is
   to **flip that** — make Paladin *just another module* in the same system, and
   make its bar the template all classes render into.

2. **One module per class (AutoRota-style).** The Core is class-independent.
   Each class ships a self-contained `Classes\Class_<Name>.lua` that the Core
   loads based on the player's class. Adding or changing a class never touches
   the engine — exactly the compartmentalisation we used in AutoRota.

---

## The universal layout — a single vertical button strip

Every class renders the **same shape**: one movable vertical strip of buttons,
top to bottom, exactly like the paladin self-bar. The module decides which
buttons appear and in what order.

```
Paladin   :  [ Aura ▾ ] [ Righteous Fury ⊙ ] [ Seal ▾ ] [ Blessing ▾ ]
Warlock   :  [ Armor ⊙ ] [ Soulstone ◎ ] [ Curse ▾ ]
Shaman    :  [ Earth ▾ ] [ Fire ▾ ] [ Water ▾ ] [ Air ▾ ]
Warrior   :  [ Battle Shout ] [ Sunder ▾ ] [ Thunder Clap ] [ Demo Shout ]
Priest    :  [ Tank Shield ] [ Fortitude/Spirit/Shadow ▾ ]
Mage      :  [ Arcane Int ▾ ] [ Frost/Scorch debuff ▾ ]
Druid     :  [ Mark/Thorns ▾ ]
Hunter    :  [ Sting ▾ ]
Rogue     :  [ Expose Armor ]
```

The two halves the spec describes map onto **regions of this one strip**:

- **Top buttons — self / global controls.** Personal toggles and utilities that
  don't target a friendly class: auras, Righteous Fury, seals (Paladin); armor
  (Warlock); Inner Fire / Tank Shield (Priest). This is the spec's "Top Anchor."
- **Lower buttons — buff / duty.** The things assigned across the raid:
  blessings, Fortitude, Mark, curses, totems, stings, shouts. This is the spec's
  "Grid Layout" plus the assigned debuffs.

### How the existing grid + pop-out fits in *(proposed — confirm)*

The per-class buff coverage and the colour-coded **player pop-out** we already
built (0.1–0.3) are **not thrown away**. They become the **detail view behind a
buff button**: hovering the blessing/Fortitude/Mark button expands the per-class
breakdown and the per-player bars (Have / Need / Not Here / Dead, with
left=group, right=single, CTRL=role). So the work survives — it just moves from
"the always-visible main bar" to "the pop-out behind the buff button," matching
how a paladin's blessing button opens the class breakdown.

> This reframes the current always-visible class-row grid into a hover-expansion
> off one buff button. **Please confirm this mapping** before M2 builds it.

---

## Architecture principles

### The Core / Module split

- **Core (`RallyPowerCP_Core.lua`)** owns everything class-independent: the
  button strip, button rendering by `kind`, the buff pop-out, roster scanning,
  buff/debuff detection, the cast pipeline, combat lockout, sync, saved
  variables, options, slash commands, and the minimap button.
- **Modules (`Classes\Class_<Name>.lua`)** own only *data and class-specific
  behaviour*. Each registers via `RallyPowerCP:NewClass("<TOKEN>")` and declares
  its ordered list of buttons. The Core picks `active = classes[PLAYER_CLASS]`
  on login and builds the strip from it.

### Target module interface

```
local M = RallyPowerCP:NewClass("WARLOCK")

-- Buttons render top-to-bottom in one vertical strip.
M.bar = {
  { kind = "self",    ... },  -- personal toggle: armor, Righteous Fury, seal, Inner Fire
  { kind = "special", ... },  -- bespoke logic + glow states: Soulstone (target select)
  { kind = "cycle",   ... },  -- wheel through assigned options: curse, sting, totem, Mark/Thorns
  { kind = "buff",    ... },  -- friendly-buff button: blessing, Fortitude, Mark, Arcane Int
                              --   (drives per-class coverage + the player pop-out)
  { kind = "assign",  ... },  -- duty assignment: who maintains Sunder / Expose
  { kind = "totem",   ... },  -- Shaman element slot (one per element)
}
```

The Core renders and wires each `kind` generically, so a new class is *data plus
a little glue*, never a new engine. Defining these `kind`s once (in the M2
framework) is what makes Warrior, Rogue, Mage, Hunter, and Warlock cheap instead
of five separate builds.

---

## Status — done through 0.3.2

The **entire friendly-buff half** is complete for every class that has one — it
just currently renders as the always-visible grid rather than the button strip:

- **Class rows + coverage** — class icon + buff icon + earliest timer + needy
  count, styled like the paladin buff bar. *(Becomes the buff-button expansion.)*
- **Interactive pop-out** — left-expanding panel of colour-coded player bars
  (green Have / red Need / blue Not Here / dark-red Dead), each with buff icon,
  name, personal timer, and a role marker. *(Reused as-is.)*
- **Per-class mouse-wheel** — each buff cycles its own options (Mark → Gift →
  Thorns). *(Becomes per-button wheel.)*
- **Casting** — left = group, right = smart top-off / single target; combat
  lockout (right-click single is the only in-combat action); 4-minute
  no-overwrite guard; throttle guard; 60-second "ding".
- **Local role markers** — CTRL+click a player cycles Main Tank / Main Assist
  (per character; not yet synced or wired to targeting).
- **Class modules shipped** — Priest (Fortitude / Divine Spirit / Shadow
  Protection + PW:Shield / Fear Ward), Mage (Arcane Int/Brilliance), Druid
  (Mark/Gift + Thorns), Warrior (Battle Shout). Paladin runs in the original
  PallyPower engine (works, but separate — see M0).
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

1. **Unify the architecture first (M0).** Sync, roles, the button strip, and the
   Top Anchor should be built *once* into a single Core that every module —
   Paladin included — inherits. Building them while Paladin is a separate engine
   means building them twice. The cleanup/baseline work comes first.
2. **Then the coordination backbone (M1).** Sync + roles + Free Assignment Mode.
   Converts RallyPowerCP from a personal helper into a raid tool, and fixes the
   "can't see others' timers" limit. The Priest Tank Shield and every
   debuff-duty feature depend on it.
3. **Then the button-strip + Top Anchor framework + debuff model (M2).** The
   universal strip, a reusable "who maintains this enemy debuff" model, and the
   Drag Dot — designed once.
4. **Then the per-class buttons (M3).** Each class drops onto the M2 framework as
   an independent point release, in whatever priority you choose.
5. **Polish to 1.0 (M4).**

---

## Milestones

### M0 — Foundation & Cleanup *(target 0.4.x)* — “Paladin becomes the baseline”

**Goal:** stop having two parallel systems. Establish the Paladin module as the
canonical reference — in both code and layout — and bring the legacy PallyPower
base into the unified, modular architecture.

**Scope**
- Define the **canonical module interface** (the `M.bar` button list above),
  derived from the paladin self-bar.
- Create **`Class_Paladin.lua`** expressing auras / Righteous Fury / seals /
  blessings as buttons in the strip format. *(Staged — wraps/aligns the existing
  engine, does not rewrite it; see risk note.)*
- **Reconcile the seams** between `PallyPower.lua` and `RallyPowerCP_Core.lua`:
  one options panel, one slash surface, one minimap entry, one consolidated set
  of saved variables.
- **Dead-code cleanup** — remove orphaned single-row pop-out functions and
  unreferenced tables from earlier iterations.
- **Naming decision** — migrate internal `PallyPower_*` symbols to
  `RallyPowerCP_*` or leave for stability; document the call.

**Depends on:** nothing — this is the base everything else builds on.

**Definition of done:** Paladin is selectable through the same module path as the
other classes and renders in the shared strip; one options/slash/minimap surface;
no orphaned code; the module interface is documented in-repo.

> **Risk note:** the paladin engine is the most mature, working part of the
> project. M0 is **staged and low-risk** — wrap and align it behind the module
> interface and clean the seams; do **not** rewrite the blessing/sync logic.
> Deep migration of its internals can be deferred indefinitely as long as it
> presents through the common interface.

---

### M1 — Coordination Backbone *(target 0.5.x)* — sync, roles, free assignment

**Goal:** make assignments and timers shared across users, so the addon
coordinates a raid instead of one player.

**Scope**
- **Addon-message sync** for the strip, mirroring the proven PallyPower approach
  and **staying interoperable with stock PallyPower / PallyPowerTW on the shared
  paladin prefix** where they overlap. New-class data rides an extended channel
  so paladin interop is never broken.
- **Real role system** — tank / healer / assist tables built on the existing
  local CTRL+click markers, now **synced**, with sane conflict resolution.
- **Wire roles into targeting** — deliver the **Priest Tank Shield**: shields
  assigned Main Tanks / Main Assists without hunting the grid.
- **Free Assignment Mode** — leader toggle letting non-leaders edit their own
  assignments; enforced through sync.
- Formalise **combat lockout** as a shared rule (already implemented).

**Depends on:** M0 (sync/role hooks live in the unified Core).

**Definition of done:** two RallyPowerCP users see the same assignments; a
paladin running stock PallyPower still syncs blessings with us; a buff cast by one
user shows a real countdown on another; Free Assignment gates edits by leader
status; the Priest Tank Shield targets assigned roles.

---

### M2 — Button Strip + Top Anchor Framework + Debuff Model + Drag Dot *(target 0.6.x)*

**Goal:** build the universal strip and the reusable machinery that makes every
utility/debuff class cheap, plus the global controls from the spec.

**Scope**
- **The vertical button strip** as a Core component that renders `M.bar` entries
  by `kind` (`self`, `buff`, `cycle`, `assign`, `totem`, `special`), and folds
  the existing per-class coverage + player pop-out in behind `buff` buttons.
- **Enemy-debuff "duty" model (designed once)** — detect a debuff on the current
  target, assign a player to maintain it, show covered / slipping / missing.
  Serves Warrior, Rogue, Mage, Hunter, Warlock.
- **The Drag Dot** (spec) — top-center handle: hover tooltip; left-click locks
  (red) / unlocks (green) with 30-second auto-lock; right-click opens Buff
  Assignment config; shift-right-click opens the Options Panel.

**Depends on:** M1 (duty assignment is a coordination feature; uses sync).

**Definition of done:** a placeholder button of each `kind` drops into any module
and works end-to-end (render, assign, sync, status colour, hover detail); the
Drag Dot exposes lock + both config menus.

---

### M3 — Per-Class Buttons *(target 0.7.x – 0.9.x)*

Each class is an independent point release on the M2 framework. Build order is
**flexible** — reorder by your priorities. Suggested order by value-to-effort:

| Order | Class | Buttons to add | Notes |
|------|--------|----------------|-------|
| 1 | **Priest** | Tank Shield | Mostly delivered in M1; confirm + polish |
| 2 | **Warrior** | Sunder / Thunder Clap / Demo Shout duty | Module exists; Battle Shout done |
| 3 | **Shaman** | Earth / Fire / Water / Air totem assignment | Flagship; largest single module |
| 4 | **Warlock** | Armor (self) + Soulstone (target + glow) + Curse cycle | Two bespoke `kind`s |
| 5 | **Hunter** | Serpent / Viper / Scorpid sting duty | Straight `cycle`/`assign` |
| 6 | **Rogue** | Expose Armor duty (coordinated w/ Warrior Sunder) | Shares Warrior's armor logic |
| 7 | **Mage** | Frostbolt / Scorch debuff coordination | Small; buff half already done |
| 8 | **Paladin** | Auras / Seals / Righteous Fury (self toggles) | Completes the baseline class |

**Depends on:** M2 (framework + debuff model + duty assignment).

**Definition of done (per class):** the class's buttons render, assign, sync, and
track status; documented in CHANGELOG; localised strings added.

---

### M4 — Polish & Spec Fidelity *(approaching 1.0)*

**Goal:** close the gaps between "works" and "matches the spec exactly."

**Scope**
- **Pets as their own coverage row** in the buff pop-out (currently players-only).
- **Options Panel** completeness (Free Assignment, skins, thresholds, sound).
- **Localisation** pass for all new strings (deDE / esES already scaffolded).
- Final cleanup, performance check on 40-man, edge-case pass on the pop-out
  hover timing and strip screen-edge behaviour.

**Definition of done:** every line item in the functional spec is represented in
the build.

---

### 1.0 — Full spec coverage

All classes, both halves (self controls + buff/duty), shared assignments and
roles, Free Assignment Mode, the Drag Dot and Options Panel, pets, paladin
interop intact, and a unified codebase with Paladin as a first-class module.

---

## Design decisions

**Locked**
- **Sync interop:** compatible with stock PallyPower / PallyPowerTW on the shared
  paladin prefix; extended channel for new-class data.
- **Layout:** single vertical button strip (paladin self-bar), universal across
  classes.

**Still open**
- **Grid/pop-out placement:** confirm the existing class coverage + player
  pop-out becomes the hover-expansion behind `buff` buttons (proposed above).
- **Paladin internals:** wrap-and-align only, or eventually migrate
  `PallyPower.lua` logic into Core? (M0 assumes wrap-and-align.)
- **Symbol naming:** migrate internal `PallyPower_*` to `RallyPowerCP_*`, or keep
  for stability?
- **Role taxonomy:** keep MT / MA, or expand (Healer, Off-Tank, Kicker, etc.)?

---

## Risks & guardrails

- **Touching the paladin engine (M0)** is the highest-risk work — stage it, wrap
  don't rewrite, keep the working blessing/sync path intact.
- **Sync (M1)** is invisible until tested with a second client — budget
  two-account testing, and verify paladin interop against an unmodified
  PallyPower client; throttle carefully on the 1.12 message pipeline.
- **Debuff model (M2)** must be designed before the first debuff class, or it
  gets reinvented five times. Design once, reuse everywhere.
- **1.12 verification:** no standalone Lua available, so keep running the
  paren/brace/keyword-balance + definition-order check after every edit, and
  test in-client.

---

## Appendix — Spec coverage matrix

| Class | Buff buttons (friendly) | Self / duty buttons (Top Anchor) |
|-------|------------------------|-----------------------------------|
| Paladin | ✅ via legacy engine → **module in M0** | ❌ Auras / Seals / RF (M3) |
| Priest | ✅ Fort / Spirit / Shadow Prot | ⚠️ Tank Shield (M1) |
| Druid | ✅ Mark/Gift + Thorns | — none required |
| Mage | ✅ Arcane Int/Brilliance | ❌ Frostbolt / Scorch (M3) |
| Warrior | — none required | ⚠️ Battle Shout done; Sunder/TC/Demo (M3) |
| Shaman | — none required | ❌ Totems ×4 (M3, flagship) |
| Warlock | ⚠️ Blood Pact (minor) | ❌ Armor + Soulstone + Curses (M3) |
| Hunter | — none required | ❌ Stings ×3 (M3) |
| Rogue | — none required | ❌ Expose Armor (M3) |

✅ done · ⚠️ partial · ❌ not started · — not applicable

**Cross-cutting (all classes):** sync + shared timers (M1), role system (M1),
Free Assignment Mode (M1), Drag Dot + Options Panel (M2), pets row (M4).
