# 🎨 RallyPowerCP — All-Class Design Concept

**Goal:** define, up front, what every class's bar looks like and how it behaves,
so the module interface is designed once and each class slots in without
retrofitting. The visual language is fixed by **PallyPower 3.3.5** (WotLK); every
class composes the *same* button widgets in a single vertical strip.

**Platform reminder:** Turtle WoW 1.18.1 (1.12 client) + **SuperWoW** +
**VanillaFixes**. Paladin is the fully-featured template; **every other class is
a deliberately simplified subset** of it.

---

## 1. The shared widget vocabulary (from PallyPower_Wrath.xml)

Every class UI is built from four widgets, all 100px wide, stacked in one column.
These already exist in the reference and we mirror their geometry exactly.

| Widget | Size | Anatomy | Interaction |
|---|---|---|---|
| **Grid buff button** (`PallyPowerButtonTemplate`) | 100×34 | 26×26 class icon + 26×26 buff icon, "need" count, two timers (group / individual) | wheel = cycle which buff for this class · L = cast group · R = single top-off · hover = **player pop-out** |
| **Auto / utility button** (`PallyPowerAutoButtonTemplate`) | 100×34 | one 26×26 icon, count, two timers | click = fire the utility · wheel = cycle option (where relevant) |
| **Player pop-out row** (`PallyPowerPopupTemplate`) | 100×34 | 16×16 buff icon, timer, name, **R** range, **D** dead, tank icon | L = greater on player · R = normal single (combat-legal) · wheel = cycle that player's assignment |
| **Toggle button** (Aura/RF style) | 100×34 | one icon, on/off tint | click = toggle/cycle a personal state |

Two roles these play, straight from the spec:

- **Grid buttons** = *targeted, per-class* buffs (the pop-out hangs off these).
- **Auto/toggle buttons** = *global / self / single-target* utility that doesn't
  target a friendly class (auras, totems, curses, shouts, stings, soulstone…).
  This is the spec's "Top Anchor," rendered as buttons at the top of the strip.

Plus the shared frame furniture: the **drag/lock dot**, the **skinned backdrop**
(Smooth + Blizzard Tooltip border, official status colors), and the options menu.

---

## 2. The module contract (what each `Class_<Name>.lua` declares)

One ordered list of buttons; the Core renders each by `kind`. Nothing class-
specific lives in the engine.

```lua
local M = RallyPowerCP:NewClass("SHAMAN")

M.bar = {
  { kind = "grid",   ... },  -- per-class buff w/ pop-out (blessing, Fortitude, Mark…)
  { kind = "cycle",  ... },  -- wheel through options on ONE target (curse, sting, totem slot)
  { kind = "toggle", ... },  -- personal on/off (aura, RF, armor, seal)
  { kind = "self",   ... },  -- one-press self/party cast (shout, totem drop)
  { kind = "special",... },  -- bespoke logic + glow states (soulstone)
}

-- Each entry carries: name(s), spell ids (learned if omitted), icon(s),
-- durations, and a cast rule. Detection/casting/timers are the engine's job.
```

`kind` set (final): **grid · cycle · toggle · self · special**. These five cover
every class below. Defining them once is what makes the simplified classes cheap.

---

## 3. Per-class concept

Legend: 🟩 grid (with pop-out) · 🟦 auto/utility · 🎛️ toggle · ⚙️ special

### ✨ Paladin — the full template *(done: pop-out + casting at 3.3.5 parity)*
```
🎛️ Aura        (cycle/toggle personal aura)
🎛️ Righteous Fury (on/off)
🎛️ Seal        (cycle personal seal)
🟩 Blessing     (per-class, greater/normal, full player pop-out)   ← the reference
```
Everything else is a **subset** of this.

### ⚡ Shaman — **first target; the hardest, now tractable via SuperWoW**
Totems are *party auras*, not friendly-class buffs, so Shaman is **all
auto-buttons, no grid**. Four element slots, each cycles which totem to drop.
```
🟦 Earth   (cycle: Stoneskin / Strength of Earth / Tremor / Earthbind)
🟦 Fire    (cycle: Searing / Magma / Fire Nova / Frost Resist)
🟦 Water   (cycle: Mana Spring / Healing Stream / Mana Tide / Poison/Disease Cleansing)
🟦 Air     (cycle: Windfury / Grace of Air / Grounding / Nature Resist / Sentry)
```
- Click = drop that totem; wheel = pick which totem in that element.
- **SuperWoW unlock:** the *owner suffix* (`UnitName("totemowner")`) +
  totem/pet awareness make "which shaman dropped what, and whose party" actually
  trackable — the thing that blocked this on plain 1.12.
- Simplification vs 3.3.5 ideal: start with **self-tracking + assignment display**
  (what I should be dropping), add cross-shaman sync later (M1). No per-friendly
  pop-out (totems aren't targeted), so no PallyPowerPopupTemplate here.

### ☀️ Priest — *simplified Paladin* **(grid already works)**
```
🟩 Fortitude / Divine Spirit / Shadow Protection  (grid, wheel-cycled, pop-out)
🟦 Tank Shield  (auto: PW:Shield the assigned tanks — needs the role system)
```
Nearly the Paladin pattern already; the Tank-Shield auto-button + roles is the
remaining piece.

### 🧙 Mage — *grid + one debuff button*
```
🟩 Arcane Intellect / Brilliance  (grid, pop-out)
🟦 Debuff  (cycle: Frostbolt slow / Scorch stacks — "who maintains it on the target")
```
The debuff button is the first instance of the **enemy-debuff duty** model
(track a debuff on your *target*, show covered/slipping). Shared with Warrior/
Rogue/Hunter/Warlock.

### 🌲 Druid — *simplest grid class* **(done)**
```
🟩 Mark of the Wild / Gift + Thorns  (grid, wheel Mark↔Gift↔Thorns, pop-out)
```
Already matches. No auto row needed. Good proof that the template collapses
cleanly for a light class.

### 💀 Warlock — *no grid; two bespoke buttons*
```
🎛️ Armor    (self: Demon/Fel Armor — personal toggle-cast)
⚙️ Soulstone (special: R-click assign target, L-click cast highest rank,
             glow green=ready / red=cooldown-or-active)
🟦 Curse    (cycle: Elements/Shadow/Doom/Agony/Tongues/Weakness/… on target)
```
The **special** kind exists mainly for the Soulstone's inventory/cooldown/active
glow logic. Curse reuses the debuff-duty model.

### 🏹 Hunter — *pure debuff-duty*
```
🟦 Sting  (cycle: Serpent / Viper / Scorpid — assigned sting on the target)
```
One button. The leanest utility class — a single instance of the debuff model.

### ⚔️ Warrior — *shout + debuff-duty* **(Battle Shout done)**
```
🟦 Battle Shout  (self: one press buffs nearby party — already implemented)
🟦 Debuff        (cycle: Sunder / Thunder Clap / Demo Shout — assigned duty)
```
Battle Shout is the existing `self` kind; the debuff button is the duty model.

### 🗡️ Rogue — *single debuff-duty*
```
🟦 Expose Armor  (assign which rogue maintains it, coordinated w/ Warrior Sunder)
```
One button, shares Warrior's armor-debuff logic.

---

## 4. What this tells us about build order & effort

Grouping by the **machinery** each class needs (not by class), because that's
what actually gets built:

1. **Grid + pop-out** — ✅ done (Paladin, Priest, Mage, Druid buff halves).
2. **`self` one-press cast** — ✅ done (Battle Shout); reused by Shaman totem drop.
3. **`cycle` (totem/curse/sting/debuff slot)** — the big new shared widget.
   Powers Shaman (×4), Mage, Warlock curse, Hunter, Warrior debuff, Rogue.
4. **Enemy-debuff duty model** — track a debuff on the *target*, show status,
   assign who maintains it. Shared by Mage/Warrior/Rogue/Hunter/Warlock. Design
   once (SuperWoW `UnitDebuff` id + `UNIT_CASTEVENT` make it clean).
5. **Totem ownership tracking** — Shaman-specific, via SuperWoW owner suffix.
6. **`toggle`** (auras/seals/RF/armor) — small, self-only.
7. **`special`** (Soulstone glow states) — Warlock-only, bespoke.
8. **Role system** — unlocks Priest Tank Shield + salvation-on-tank logic.

**Shaman first** exercises items 3 + 5 (cycle widget + totem ownership) — the
two highest-leverage new systems — so building it establishes the pattern the
debuff-duty classes then reuse.

---

## 5. Simplification policy (explicit)

Every non-Paladin class ships **"what I should be doing" tracking + one-touch
casting first**, and defers the raid-coordination layer (cross-caster sync,
who-does-what assignment broadcasting) to the M1 sync milestone. So v1 of each
class = a personal, accurate, PallyPower-styled helper; the shared-assignment
brain comes later, once, for all of them.

- Shaman v1: track/drop my own totems by element. (Sync: whose-totem-where.)
- Debuff classes v1: track the debuff on my target + one-touch (re)apply.
  (Sync: which player is assigned which debuff.)
- Priest Tank Shield: needs the role table (small) even in v1.

---

## 6. TL;DR

- **One strip, four widgets, five `kind`s** — every class is a composition of the
  same PallyPower-3.3.5 parts.
- **Paladin = full set; everyone else = a subset.** Druid is the smallest (one
  grid button); Hunter/Rogue are one auto-button each.
- **Shaman is the right first class**: it needs the `cycle` widget and
  SuperWoW totem-ownership, and those unlock the whole debuff-duty family.
- **Build by machinery, not by class**, and **ship personal-accurate first,
  sync later.**
