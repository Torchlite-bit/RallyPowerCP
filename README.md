# RallyPowerCP

**All-class buff management for Turtle WoW 1.18.1 (1.12 client).**
By **Subtilizer (Torchlite)** — version **0.0.1**.

Built on PallyPowerTW (by ivanovlk) and the original PallyPower team.

RallyPowerCP keeps PallyPower's Paladin blessing/aura/seal grid exactly as it
was, and adds an auto-detecting buff tracker for every other buffing class. Log
in on a Paladin and you get the full PallyPower grid. Log in on a Priest, Mage,
or Druid and you instead get a matching bar that tracks *your* class's group
buffs across the party/raid.

---

## What's different from PallyPowerTW

1. **Renamed** to RallyPowerCP (new `.toc`, paths, load check, slash aliases,
   credits, key-binding header). Internal Lua function/variable names are kept
   as `PallyPower_*` on purpose — they're invisible in-game and renaming 3,700+
   lines would risk breaking the proven Paladin engine.
2. **Turtle blessing timers forced on.** Regular blessings = **10 min**, Greater
   Blessings = **30 min**, on every realm. (PallyPowerTW only applied these on a
   hard-coded list of realm names, so off-list realms wrongly showed 5 min.)
   Toggle in `PallyPower.lua` via `FORCE_TURTLE_DURATIONS`.
3. **All-class buff bar** (`RallyPowerCP_Classes.lua`). Auto-detects your class:
   - **Paladin** → dormant; the original grid owns the UI (unchanged).
   - **Priest** → Power Word: Fortitude, Divine Spirit, Shadow Protection.
   - **Mage** → Arcane Intellect.
   - **Druid** → Mark of the Wild, Thorns.
   - **Others** → no tracked group buffs yet (easy to add — see below).

## The class bar

- One button per group buff you can cast. **Red + number** = that many group
  members are still missing it. **Faded/green** = everyone is covered.
- **Left-click** a button → buffs the **next group member missing it** (your
  current target gets priority if they're missing it; if everyone's covered it
  refreshes you). No more accidental self-casts.
- **Right-click** → casts the group/greater version (Prayer of…, Arcane
  Brilliance, Gift of the Wild) on the missing member's subgroup.
- **Countdown timer** beside each icon shows the soonest expiry among the buffs
  you've cast — exact to the second for buffs on yourself; for others it counts
  down from your cast (the 1.12 client doesn't expose other players' buff
  durations, the same limitation PallyPower works around the same way). Turns
  red and plays the **ding** (same sound as the Paladin bar) at 60 seconds left.
- **Drag** the bar to move it; position is saved. Only buffs you've actually
  learned appear.
- Buff durations are listed per spell in `RallyPowerCP_ClassBuffs`
  (`dur`/`gdur`, in seconds) — easy to edit if Turtle tunes a duration.

## Showing up automatically + the minimap icon

- **Solo / leveling:** the bar appears on its own at login and after zoning,
  just like PallyPower's solo buff bar — *as soon as you know at least one
  trackable buff*. Before you've trained any (a fresh low-level character), it
  stays hidden because there's nothing to show, then pops up once you learn one.
  While solo it tracks the buffs on **you**, so it doubles as a self-buff
  reminder.
- **Minimap icon:** shown for every class (toggle it in Options). 
  **Left-click** toggles the right thing for your class — the Paladin assignment
  grid on a Paladin, your class buff bar on everyone else. **Right-click** opens
  Options. Hover shows the credits/version.

## Slash commands

| Command | Description |
|---------|-------------|
| `/pp`, `/pallypower`, `/rp`, `/rallypower` | Paladin grid / buff bar (PallyPower) |
| `/rpc` | Toggle the all-class buff bar (non-Paladins) |
| `/rpc reset` | Reset the class bar's position |
| `/rpc icon` | Cycle the minimap icon skin (any class; also **shift-click** the icon) |
| `/rpc icon <name>` | Set a skin directly: `blue`, `ivory`, `white`, `gold`, `pearl` |

## Installation

1. Place this folder in `Interface/AddOns/` and make sure it is named exactly
   **`RallyPowerCP`** (the folder name must match `RallyPowerCP.toc`).
2. That's it — all art (`Icons/`, `HDIcons/`), the expiry sound (`Sounds/`),
   and the `PallyPower-ResizeGrip` texture are bundled and every path in the
   code has been verified against a real file. The new class bar uses
   Blizzard's built-in spell icons and needs no extra art.

## Adding more classes/buffs

Edit `RallyPowerCP_ClassBuffs` in `RallyPowerCP_Classes.lua`. Each entry:

```lua
{ name  = "Power Word: Fortitude",          -- exact single-target spell name
  group = "Prayer of Fortitude",            -- optional group/greater version
  icons = { "Spell_Holy_WordFortitude" },   -- applied-aura icon basename(s)
  pet   = true },                           -- optional: also track on pets
```

Buffs are detected by **icon texture**, which is the only reliable way to read
another player's buffs on the 1.12 client.

## Compatibility with other PallyPower users

- **Paladin blessing sync works.** RallyPowerCP keeps PallyPower's sync channel
  (addon-message prefix `PLPWR`) and message format unchanged, so a RallyPowerCP
  Paladin and players running the original PallyPower / PallyPowerTW in the same
  party/raid see and coordinate each other's blessing, aura, and seal
  assignments normally, in both directions.
- **The all-class bar is local-only.** The Priest/Mage/Druid buff tracker sends
  and receives nothing over the network — it just watches buffs on your screen
  and reminds you. It does not coordinate between, say, two Priests the way the
  Paladin grid coordinates multiple Paladins. It also can't conflict with anyone
  else's addons.
- **No false "new version" pop-ups.** Because the sync channel is shared, other
  PallyPower users broadcast their own (higher) version numbers. That would
  normally trigger a misleading "new version of RallyPowerCP available" message,
  so it's suppressed in this fork.

## Known limitations (v0.0.1)

- Warrior/Hunter/Shaman/Warlock/Rogue have no tracked group buffs yet (shouts,
  auras, and totems work differently and are planned for a later build).
- The bar tracks coverage and lets you rebuff; it does not auto-assign buffs the
  way the Paladin grid coordinates blessings between multiple Paladins.

## Credits

- RallyPowerCP by **Subtilizer (Torchlite)**.
- Based on **PallyPowerTW** by ivanovlk.
- Original PallyPower by Hjorim / Sneakyfoot / Rake / Xerron / Azgaardian /
  Aznamir. Spanish localization by Nuevemasnueve.
