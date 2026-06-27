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

## [0.4.1] — 2026-06-27
**Paladin pop-out, done right.** 0.4.0 added a *second* bar for Paladins; that was
the wrong call. This replaces it: the **original PallyPower buff bar** now gets
the hover player pop-out directly, and the duplicate bar is gone.

### Changed
- **Reverted the separate Paladin class bar** from 0.4.0. Paladins use the
  original PallyPower bar/grid again — no second bar on screen.
- **Hovering a blessing button** on the PallyPower buff bar now opens the
  colour-coded **player pop-out** to its left (green Have / red Need / blue Not
  Here / dark-red Dead), each bar showing the blessing icon, the player's name, a
  tank marker (MT), and that player's personal timer. This replaces the old text
  tooltip on those buttons.

### Added
- **`RallyPowerCP_Popout.lua`** — a self-contained pop-out that reads PallyPower's
  own per-button data (`need` / `have` / `range` / `dead` lists + `LastCastPlayer`
  timers) and tank flags. It does **not** modify the PallyPower engine — it wraps
  the existing buff-button hover handler — so the classic bar behaves exactly as
  before, just with the visual pop-out instead of the text tooltip.

### Removed
- `Classes/Class_Paladin.lua` (the 0.4.0 module) — no longer needed.

---

## [0.4.0] — 2026-06-26
**M0 begins — Paladin becomes a class-bar class.** First step of the Foundation
milestone from the roadmap: bring Paladin into the same system as everyone else.

### Added
- **`Class_Paladin.lua`** — Paladins now get the class rows + hover player
  pop-out, exactly like Priest/Mage/Druid. All six blessings are included with
  their normal (single-target) and greater (group) versions and Turtle durations
  (10 min / 30 min).
- **Per-class blessing assignment is built in** via the existing mouse-wheel:
  scroll a class row to set that class's blessing (e.g. Might on the Warrior row,
  Wisdom on the Mage row). Left-click casts the Greater (group) blessing on the
  class; right-click tops off the one member who needs the normal blessing. In
  the pop-out, left-click a player = Greater, right-click = normal single target.

### Changed
- Paladins are no longer walled off from the bar. The minimap **left-click** and
  **/rpc** now toggle the new bar for Paladins; the Smart Buff key works too.

### Notes
- **The original PallyPower blessing grid still runs**, independently and
  unchanged — open it with **/pp**. You'll have both UIs available; hide whichever
  you don't want. (Retiring or merging the legacy grid is later M0 work.)
- This bar is **local-only** for now — it tracks the blessings *you* cast.
  Cross-paladin sync (and interop with stock PallyPower) lands in M1.
- Auras / Seals / Righteous Fury (the paladin top-anchor controls) are M3; the
  classic self-bar still provides them today.
- Blessing **reagents aren't pre-checked** (same as the other group buffs) — a
  cast without reagents fails with the normal game error.

---

## [0.3.2] — 2026-06-15
Pop-out refinements to match PallyPower's player-list behaviour.

### Changed
- **The pop-out now expands to the *left*** of the class rows (was the right),
  matching PallyPower's layout.
- **Replaced the plain text tooltip with a stack of colour-coded player bars.**
  Each bar shows the buff icon, the player's name, a status colour (green Have /
  red Need / blue Not Here / dark-red Dead) and that player's personal timer —
  instead of the old dark text panel.
- **Mouse-wheel is now per-class.** Scrolling a class row cycles *that class's*
  buff only (e.g. the Druid row toggles Mark of the Wild -> Gift of the Wild ->
  Thorns), so each class can display and cast a different buff at the same time.

### Added
- **Role markers on the player bars.** Each bar shows a role slot (an "R" when
  unassigned); **CTRL+click** a player cycles their role — Main Tank (gold) ->
  Main Assist (cyan) -> none. Roles are saved per character.
  - *Local only for now:* roles aren't yet shared with other RallyPowerCP users
    and aren't yet wired into smart targeting (e.g. directing Priest shields to
    tanks). Those come with the upcoming role/sync milestone.

---

## [0.3.1] — 2026-06-12
The interactive pop-out (Option A, stage 2 of 2). Option A is now complete.

### Added
- **Hover pop-out side panel.** Hovering a class row opens a panel to its right
  listing every player in that class, each colour-coded by status — green
  (Have), red (Need), blue (Not Here), bright red (Dead) — with that player's
  personal countdown timer. It stays open while the cursor is over the row or
  the panel, and updates live.
- **Click an individual player** in the pop-out:
  - **Left-click** casts the group version covering that player's subgroup. It's
    skipped if they already have the buff (no wasted reagents) and is disabled in
    combat.
  - **Right-click** casts the single-target version on just that player — the
    "top off the one who missed it" action — and works in combat.

### Notes
- Deferred to later milestones (they need the assignment/role systems): the
  mouse-wheel-per-player custom assignment and CTRL+click tank/assist roles.
- Per-player timers are exact only for buffs you cast yourself; a player buffed
  by someone else shows as covered with no countdown (1.12 client limitation).

---

## [0.3.0] — 2026-06-12
The class-grouped grid (Option A, stage 1 of 2). The bar is now organized like
PallyPower's: one row per class in your group.

### Added
- **Class-grouped grid.** Instead of one row, the bar now shows **one row per
  class present** in your party/raid (in PallyPower's class order), each styled
  like the Paladin buff-bar button — your class icon, the buff icon, status
  colour, count, and the earliest timer for that class.
- **Per-class click actions**, scoped to just that class's members:
  - **Left-click** casts the group/raid version on that class (cycling through
    its members, renew-capable).
  - **Right-click** is a smart top-off on the one member of that class who needs
    it most (missing first, else lowest time left). Combat-locked, 4-min floor.
  - **Scroll** changes the globally-selected buff shown on every row.
  - **Hover** shows that class's members broken into Have / Need / Not Here /
    Dead.

### Fixed
- Completed the data layer the grid needs: the roster scan now buckets members
  by class and computes per-class coverage and timers (previously the grid had
  no data feeding it, so no rows appeared). Rows rebuild automatically when the
  set of classes in your group changes.

### Notes
- Stage 2 (next) is the interactive pop-out: a side panel off each class row
  listing every individual player with status + timer, click-to-buff individuals.
- The grid is players-only for now; pets aren't bucketed into a row yet.

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
