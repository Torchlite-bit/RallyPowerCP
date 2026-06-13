# Changelog — RallyPowerCP

All notable changes to RallyPowerCP are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com); versions follow
semantic versioning (MAJOR.MINOR.PATCH).

RallyPowerCP is a fork of **PallyPowerTW** (by ivanovlk), itself based on the
original **PallyPower** (Hjorim / Sneakyfoot / Rake / Xerron / Azgaardian /
Aznamir). Targets Turtle WoW 1.18.1 on the 1.12 client.

## [Unreleased]
### Fixed
- Clicking a buff now properly **cycles** through party/raid members in range
  instead of getting stuck on you. Added a per-buff round-robin cursor so each
  click continues from the member after the last one buffed (wrapping around),
  which also handles clicking faster than the buff visibly applies.
- When everyone in range (including you) already has the buff, a click no longer
  wastefully re-casts on yourself — it reports that the group is covered and
  does nothing.

### Planned / under consideration
- Cross-caster sync: multiple casters of the same class coordinating buff
  duty and sharing timers (own addon-message protocol).
- Reagent awareness: grey out group-buff right-click when out of reagents.
- Combat mode: reduced scanning and/or muted expiry ding while in combat.
- Shaman / Warrior / Hunter support (totems, shouts, and auras need a
  different tracking model than maintained buffs).

## [0.1.1] - 2026-06-12
### Added
- Class bar now announces casts in green, mirroring the Paladin module
  ("Casting <buff> on <Class> (<Name>)"), via PallyPower's own feedback
  function — so it respects your chat-vs-screen feedback setting and the
  `[RallyPowerCP]` prefix.

### Fixed
- Paladin blessing casts no longer throw "You can't do that while moving!" —
  removed the same cosmetic `DoEmote("STAND")` (both occurrences) that caused
  it on the class bar. Casting auto-stands you anyway.
- Class-bar casts no longer throw "You can't do that while moving!" — removed a
  stray `DoEmote("STAND")` from the cast flow (it was cosmetic, and emotes are
  blocked while moving). Casting while moving now works silently.
- Clicking a buff button no longer buffs your current target when that target
  is an NPC, a stranger, or anyone outside your party/raid. The "prefer my
  target" shortcut now only applies to an actual group member who is missing
  the buff; otherwise the cast goes to the next needy group member and your
  original target is restored.

## [0.0.1] - 2026-06-12
Initial release, by **Subtilizer (Torchlite)**.

### Added
- **`RallyPowerCP.toc`** defining the new addon identity: title, author,
  version, per-character saved variables (matching upstream behaviour, plus
  `RallyPowerCP_Settings`), and load order with localizations in `Locale\`.
- **All-class buff module** (`RallyPowerCP_Classes.lua`):
  - Auto-detects the logged-in class. Paladins get the original PallyPower
    grid untouched; Priest, Mage, and Druid get a PallyPower-styled tracker
    bar for their class's group buffs (Fortitude/Spirit/Shadow Protection;
    Arcane Intellect; Mark of the Wild/Thorns).
  - Coverage scanning by buff icon texture (the only reliable way to read
    other players' buffs on the 1.12 client). Red count = members missing
    the buff; faded green = covered. Pets tracked where it matters.
  - **Smart casting**: left-click buffs the next group member missing that
    buff (current target gets priority if they need it; refreshes self when
    everyone is covered). Right-click casts the group version (Prayer /
    Brilliance / Gift) on the missing member's subgroup. Uses PallyPower's
    exact 1.12 cast flow: temporarily disable `autoSelfCast`, clear target to
    force the targeting cursor, `SpellTargetUnit`, then restore target and
    CVar.
  - **Countdown timers** beside each icon: exact (API) times for buffs on
    yourself; cast-recorded times for buffs you put on others. Red text and
    an audible **ding** (the Paladin bar's sound) at 60 seconds remaining,
    with a chat warning naming the buff.
  - **Smart Buff key binding**: one key buffs the next member missing any
    tracked buff — repeat to top off the whole group hands-free.
  - Bar is movable (position saved per character), shows only learned buffs,
    auto-shows at login/zone-in, and toggles via `/rpc` or the minimap icon.
- **Minimap icon skin system**: five bundled skins (Blue & Gold default,
  Ivory, White, Gold, Pearl — all with pressed states) as game-format TGAs.
  Cycle with `/rpc icon` or **shift-click** the minimap icon; set directly
  with `/rpc icon <name>`. Choice saved per character.
- **Slash commands**: `/rp` and `/rallypower` aliases for the Paladin module;
  `/rpc` (toggle class bar), `/rpc reset` (reset bar position),
  `/rpc icon [name]` (icon skins).
- README and this changelog.

### Changed
- **Rebranded** PallyPowerTW → RallyPowerCP throughout: addon identity and
  load check, all hard-coded texture/sound paths, options title, chat message
  prefix, key-binding header, minimap tooltip credits, grid title
  ("RallyPowerCP") and buff-bar title ("Rally Buffs"). Internal `PallyPower_*`
  Lua names intentionally kept to avoid destabilizing the proven Paladin
  engine.
- **Minimap left-click now routes by class**: Paladin assignment grid for
  Paladins, the class buff bar for everyone else. Right-click still opens
  Options.
- **Scan engine efficiency**: each unit's buff list is read once per scan
  (single-pass collection) instead of once per tracked buff; full roster
  scans run only when a `UNIT_AURA`/roster event reports a change (5-second
  safety-net fallback), while the per-second countdown tick is pure
  arithmetic with zero API calls.
- Click targeting skips out-of-range members (`UnitIsVisible`) so casts
  don't whiff on someone across the zone.

### Fixed
- **Turtle blessing durations now apply on every realm** (10-minute regular /
  30-minute Greater). Upstream only enabled them on four hard-coded realm
  names, silently falling back to 5-minute vanilla timers elsewhere
  (`FORCE_TURTLE_DURATIONS` switch, on by default).
- Suppressed the misleading "new version of RallyPowerCP available" chat
  message triggered by PallyPower/PallyPowerTW users broadcasting their own
  higher version numbers on the shared `PLPWR` sync channel.
- Corrected the Spanish localization filename case in the load order
  (`esEs` → `esES`), which mattered on case-sensitive setups.
- Class-bar clicks no longer auto-self-cast or hit your current target by
  accident (root cause of the original "buffs me instead of the party"
  behaviour).

### Compatibility
- Paladin blessing sync with players running original PallyPower /
  PallyPowerTW is unchanged in both directions (shared `PLPWR` prefix and
  message format). The all-class bar is local-only and sends nothing over
  the network.
