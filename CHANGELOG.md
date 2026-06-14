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
- **Role assignment** (tank/healer tables) so utility buttons and a Tank-Shield
  box can target by role — e.g. PW: Shield / Fear Ward to tanks and healers.
- **Cross-caster sync**: two casters of the same class splitting buff duty and
  sharing timers over a dedicated addon-message channel (also the only way to get
  exact timers for buffs other players cast).
- **The full PallyPower grid + pop-outs**, drag-dot lock/unlock, and the
  right-click assignment matrix / options panel.
- **More classes**: Hunter (Trueshot Aura) and Shaman (totems) need an
  aura/range model rather than per-member casting.

---

## [0.2.3] — 2026-06-12
### Changed
- **The class row now matches PallyPower's buff-bar button exactly.** It was far
  too large; it's now the same 100×36 size with two 26×26 icons (your class icon
  on the left, the tracked buff on the right), the same Tooltip-textured backdrop
  coloured by status — red when someone needs it, yellow when it's expiring,
  green when everyone is covered — and the same `GameFontHighlightSmall` timer
  and count text. The values are taken straight from the Paladin frame so the
  look is identical.

---

## [0.2.2] — 2026-06-12
Hotfix: the class bar failed to appear for every non-Paladin class in 0.2.1.

### Fixed
- **The bar built nothing on non-Paladin classes.** The throttle's cooldown
  swirl used a Cooldown frame template that isn't reliable on the 1.12 client;
  creating it errored while building the bar, so the bar never appeared. Replaced
  it with a simple darkening overlay on the icon — same "you just cast, wait for
  the GCD" cue, no fragile frame template.
- **Combat detection** no longer calls `UnitAffectingCombat` (a later-expansion
  API); it now tracks combat with the vanilla `PLAYER_REGEN_DISABLED/ENABLED`
  events, so the right-click combat lockout works correctly on 1.12.
- The bar build is now wrapped so that, if anything unexpected errors on a custom
  client, the error is printed in chat instead of the bar silently failing.

---

## [0.2.1] — 2026-06-12
Reworked the class bar into a single scrollable row and adopted the spec's
main-button click model.

### Changed
- **One scrollable class row instead of one button per buff.** The bar now shows
  a single PallyPower-styled row — icon on the left, large countdown on the
  right, on a green (covered) / red (someone needs it) status bar. Scroll the
  mouse wheel to switch which buff it shows; the timer and the Have/Need/Not
  Here/Dead tooltip follow. Your selection is remembered.
- **New click model on the class row:**
  - **Left-click** casts the **group/raid version** (Prayer of…, Gift of the
    Wild, Arcane Brilliance), covering a whole subgroup at once; renew-capable.
  - **Right-click** is a **smart top-off**: it casts the single-target version on
    the one member who needs it most (missing first, otherwise the lowest time
    remaining). Disabled in combat, and it won't overwrite a buff with 4+ minutes
    left, to save reagents.
- The expiry **ding now fires for every tracked buff**, even one you aren't
  currently showing on the row, so nothing slips by while it's scrolled off.

### Added
- **Throttle guard.** After a cast the row shows a brief cooldown swirl and
  ignores clicks for the global-cooldown window, so a panicked double-click can't
  burn a second set of reagents.

### Notes
- Per-member timing still relies on your own casts — the 1.12 client can't read
  how long another player's buff has left — so the 4-minute no-overwrite guard
  and "lowest time remaining" only consider members you personally buffed; others
  showing the aura are treated as covered.

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
