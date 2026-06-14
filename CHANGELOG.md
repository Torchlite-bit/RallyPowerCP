# Changelog — RallyPowerCP

All notable changes to RallyPowerCP are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com) and the project uses semantic
versioning (MAJOR.MINOR.PATCH).

RallyPowerCP is a fork of **PallyPowerTW** (by ivanovlk), itself based on the
original **PallyPower** team. It targets Turtle WoW 1.18.1 on the 1.12 client.
Author: **Subtilizer (Torchlite)**.

---

## [Unreleased]
### Planned / under consideration
- **Role assignment** (tank/healer tables) so utility buttons can target by
  role — e.g. PW: Shield / Fear Ward to tanks and healers specifically.
- **Cross-caster sync**: two casters of the same class splitting buff duty and
  sharing timers over a dedicated addon-message channel.
- **Reagent awareness**: grey out a group-buff right-click when out of reagents.
- **Combat mode**: reduced scanning and/or a muted expiry ding while in combat.
- **More classes**: Hunter (Trueshot Aura) and Shaman (totems) need an
  aura/range model rather than per-member casting; Warlock utility (soulstones)
  is a different feature again.

---

## [0.2.0] — 2026-06-12
Modular rebuild. The all-class bar is now a clean engine plus one file per class.

### Changed
- **Restructured into an AutoRota-style architecture.** The monolithic
  `RallyPowerCP_Classes.lua` is split into a class-independent engine
  (`RallyPowerCP_Core.lua`) and one module per class under `Classes\`
  (`Class_Priest.lua`, `Class_Mage.lua`, `Class_Druid.lua`,
  `Class_Warrior.lua`). Each module registers via `RallyPowerCP:NewClass(token)`
  and supplies only its data. Behaviour for existing classes is unchanged.
  Adding a class is now "copy a file, list it in the `.toc`."

### Added
- **Warrior support** — Battle Shout, tracked as a new **self-cast** buff type:
  one click refreshes party members in range (no per-member targeting), while
  coverage and the countdown timer work normally. The `selfcast` flag is
  reusable for other shout/aura buffs.
- **Scroll-to-switch-buff.** Roll the mouse wheel over any buff button to cycle
  it through your class's buffs; the icon, need count, timer, and the
  Have/Need/Not Here/Dead tooltip all follow. (PallyPower's scroll-to-assign,
  brought to the class bar.)

### Changed
- **Clicks can renew already-buffed members.** Clicks still prioritize members
  who are *missing* the buff, but once everyone in range is covered, further
  clicks renew the next member in the cycle instead of doing nothing — so you
  can top anyone off at any time. Targeting a friendly group member always
  (re)buffs that member. The Smart Buff key still stops once everyone is covered.

---

## [0.1.2] — 2026-06-12
### Added
- **PallyPower-style buff tooltips for every class.** Hovering a buff button
  lists group members by status — **Have** (green), **Need** (red),
  **Not Here** (blue, out of range), **Dead** (bright red) — using the same
  labels, colors, and categorization as the Paladin buff bar.
- **Priest utility row** (top of the bar, like the Paladin seal buttons):
  **Power Word: Shield** (your friendly target, else the lowest-health living
  member in range) and **Fear Ward** (your target, else yourself). Icons are
  read live from your spellbook; only learned spells appear.

### Fixed
- Clicking a buff now **cycles** through party/raid members instead of sticking
  on you — a per-buff round-robin cursor advances each click (and handles
  clicking faster than the buff visibly applies).
- A click when everyone is already covered no longer wastefully re-casts on you.

---

## [0.1.1] — 2026-06-12
### Added
- Class-bar casts announce in green like the Paladin module
  ("Casting <buff> on <Class> (<Name>)"), respecting your feedback setting.

### Fixed
- Removed the cosmetic `DoEmote("STAND")` that threw "You can't do that while
  moving!" on both the Paladin blessings and the class bar. Casting auto-stands
  you anyway.
- A buff click no longer hits your current target when it's an NPC, a stranger,
  or anyone outside your party/raid.

---

## [0.1.0 → 0.1.1 groundwork]
Smart casting, countdown timers, the expiry ding, the Smart Buff key binding,
and the five minimap icon skins all landed during early development and were
first stamped at 0.1.1. See git history for the blow-by-blow.

---

## [0.0.1] — 2026-06-12
Initial release, by **Subtilizer (Torchlite)**.

### Added
- New `RallyPowerCP.toc` identity (title, author, version, per-character saved
  variables) and the first all-class buff tracker for Priest, Mage, and Druid.
- Coverage scanning by buff icon texture; a movable, PallyPower-styled bar.

### Changed
- Rebranded PallyPowerTW → RallyPowerCP throughout (identity, paths, titles,
  slash commands, key-binding header, credits), keeping internal `PallyPower_*`
  Lua names to avoid destabilizing the proven Paladin engine. Minimap left-click
  routes by class (Paladin grid vs class bar).

### Fixed
- Turtle blessing durations now apply on every realm (10-min / 30-min), not just
  a hard-coded realm list.
- Suppressed the false "new version available" message triggered by other
  PallyPower users on the shared `PLPWR` sync channel.

### Compatibility
- Paladin blessing sync with original PallyPower / PallyPowerTW users is
  unchanged (shared `PLPWR` prefix and message format). The all-class bar is
  local-only and sends nothing over the network.
