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

## [0.12.0] — 2026-07-09
**One visual family: every non-paladin class is now a strip.** Priest, Mage,
Druid and Warrior were rebuilt from scratch on the strip engine, so all nine
classes look and behave the same way; the bespoke grid bar is gone.

### Added (Assignment & Sync — step 1: the shared data model)
Foundation only; nothing consumes it yet (sync = step 2, panel = step 3), so
there is no user-visible change. Implements `docs/DESIGN_ASSIGNMENTS.md`.
- **`Core/RallyPowerCP_Assign.lua`** — a caster-major store
  (`RallyPowerCP_Assign`, new SavedVariablePerCharacter) covering the **totem**
  and **duty** domains, with **blessings delegated to the untouched PallyPower
  tables** (adapter accessors only; byte-compatible PLPWR interop preserved).
  Mutators/readers (`SetTotem`/`SetDuty`/`GetDutyCasters`/`GetTotemCoverage`/…),
  a `CanEdit` permission gate (self or lead/assist), roster pruning, a
  `Subscribe` change event, and an ephemeral **`RallyPowerCP.AssignStatus`**
  intent-vs-actually-up mirror (never saved). Stable append-only `wid`s and a
  per-caster `seq` are reserved for the future `RPCX` wire format.
- **Duty/totem catalogs** are declared by the class modules at load
  (`RallyPowerCP.Assign.RegisterDuty` / `RegisterTotems`): Priest/Mage/Druid
  raid buffs, Warrior/Rogue/Warlock/Mage/Hunter debuffs, Warlock/Priest/Druid
  utility, and the Shaman totem lists — nothing class-specific lives in the
  engine.

### Changed (Blessings tab round 3: spell tooltips actually resolve, aura skills row, wider left column)
- **Spell tooltips fixed for real**: the legacy ID tables hold SHORT names
  ("Wisdom", "Retribution", "the Crusader") which never match a spellbook
  entry, so the spell lookup always fell back to the summary tooltip. Cell
  tooltips now rebuild the full name with the locale's own patterns
  ("Blessing of …", "… Aura", "Seal of …") before the spellbook lookup — a
  paladin hovering an assigned blessing/aura/seal now gets the real spell
  text (totem chips and duty cards already used exact full names and light
  up for the class that knows them).
- **Second skills row: auras.** Under each paladin's blessing ranks, a row of
  their seven auras with rank+talent overlaid (from `AllPallysAuras`), since
  talents improve auras — the assigner can see who is best specced for the
  aura duty. Preview paladins: Protection +5 Devotion, Retribution +3
  Retribution Aura.
- **Roomier left column**: the name/skills column widened to 170px with a
  thin gold separator before the Aura column, rows deepened to 62px (6
  pooled rows) and the frame grew to 760×680; totem chips and duty cards
  widened to match.

### Changed (Blessings tab round 2: skills column, Aura/Seal moved left, tooltip fix)
- **Aura and Seal are now the FIRST two columns** of the grid (slots 1-2, as
  requested), followed by the ten buff classes.
- **Per-paladin skills strip**, imitating the classic frame's left column:
  under each paladin's name, an icon for every blessing they can cast with
  its **rank and talent points** ("6+5") overlaid, and the number of
  **Symbols of Kings** in their bags on the subtitle line ("34 sym", from the
  legacy `SYMCOUNT` broadcasts) — so the assigner can see at a glance who has
  the best rank/talents for each blessing. Preview paladins show max ranks
  with +5 on their spec's blessing. Blessing rows grew to 50px (7 pooled
  rows); the frame is 700×640.
- **Tooltip fix**: `GameTooltip:SetSpell` now passes the literal `"spell"`
  book type, and every tooltip handler is wrapped so an OnEnter error prints
  `RallyPowerCP error: … (tooltip)` to chat instead of silently killing the
  tooltip (the likely cause of tooltips not appearing at all).

### Added (Blessings tab: Aura + Seal columns, real spell tooltips)
- **Aura and Seal columns** on the Blessings tab, exactly like the classic
  PallyPower frame: two extra cells per paladin (gold-labelled, headed by the
  Devotion Aura / Righteousness icons) cycling through the legacy engine's own
  `PallyPower_PerformCycle(name, 10/11)` aura/seal paths — edits write
  `PallyPower_AuraAssignments`/`PallyPower_SealAssignments` and send the
  byte-identical `AASSIGN`/`SASSIGN` messages, so stock PallyPower users
  receive them unchanged. Preview paladins cycle all 7 auras / 6 seals
  locally. The frame widened to 700px for the twelve columns.
- **Real spell tooltips**: hovering a blessing/aura/seal cell, a totem chip or
  a duty card now shows the actual spell tooltip (name, rank, description)
  when the spell is in your spellbook, with the assignment context appended
  below — so the assigner can read what each spell does. Spells outside your
  spellbook keep the plain summary tooltip.

### Fixed (post-test polish round 2)
- **Preview-paladin blessings now survive `/reload`**: the fake paladins'
  assignments moved from a session-only table into the saved settings
  (`RallyPowerCP_Settings.testBless`); they are still wiped when test mode
  turns off, and the legacy tables / PLPWR wire still never see fake names.
- **Options frame grows for tall tabs**: the Shaman Buttons tab (four totem
  dropdowns + shared behaviour section) overflowed the fixed 480px frame,
  leaving the last dropdown on the border. Each tab now reports its content
  height and the frame gains bottom breathing room when needed.
- **Closer to the concept**: panel widened to 640×620 with concept-scale
  cells (45px blessing cells / 30px chips, 98px element chips, 292px duty
  cards), the tab row now sits flush on the content box with the active tab
  merging into it, and grid/typography spacing was retuned throughout.

### Changed (assignment panel rebuilt to the concept spec)
The panel now follows `docs/RallyPowerCP_assignment_concept.html` instead of
approximating it: a 566×612 gold-framed "Who Covers What" dialog with status
pills (Lead/Solo, clickable **Free Assign** toggle, PLPWR sync, TEST RAID),
concept-styled tabs (green dot = live, amber = local-until-sync), per-tab
header/description, class-coloured caster rows with spec subtitles, chip-style
cells (blessing icons, element-coloured totem chips, "+" empty cells), a
**coverage line** (red "No blessing: Priest, Shaman" / green all-covered), and
duty tabs rendered as two-column **cards** with icons and class-coloured
holder names plus an "N/M assigned" counter.
- **Test mode seats a full 40-man preview raid** of lore characters (Varian,
  Uther, Arthas, Thrall, Jaina, Sylvanas, …) covering every class **and spec**,
  so every tab is exercisable solo. Preview blessing edits stay in a
  session-only table (the legacy tables and the PLPWR wire never see fake
  names); preview totem/duty rows are swept by `PruneToRoster` when test mode
  turns off.
- **Classic bottom-button row** (same features as the PallyPower frame):
  **Refresh** (legacy rescan + REQ broadcast), **Clear** (current tab;
  blessings go through the byte-compatible legacy `CLEAR`), **Options** (opens
  the RallyPowerCP tabbed options), **Reset Position**, and **Presets**
  (paladins; the same presets dropdown as the classic frame).
- **Right-clicking the paladin buff bar now opens this panel** (left-click
  keeps the classic assignment frame; graft replaces
  `PallyPowerBuffBar_MouseUp` — `PallyPower.lua` untouched), and the classic
  frame's **Options button now opens the RallyPowerCP options panel**
  (`/rpc legacy` still reaches the old options frame).
- **Permission fixes**: `Assign.CanEdit` now treats solo players as their own
  leader and allows every edit in test mode, so totem/duty assignment works
  outside a group (previously a solo shaman couldn't cycle other rows at all);
  the panel repaint is wrapped in `pcall` and reports errors to chat instead
  of leaving a half-drawn grid. The panel position is saved per character.

### Added (Assignment & Sync — step 3: the assignment panel)
One frame for the whole raid's assignments (`Core/RallyPowerCP_AssignPanel.lua`),
opened by **right-clicking a strip's title area** or **`/rpc assign`** (works for
every class, Paladin included). Five tabs:
- **Blessings — live and PLPWR-byte-compatible.** Rows are the paladins known
  from `PLPWR` broadcasts; cells cycle through the legacy engine's OWN
  `PallyPower_PerformCycle`/`Backwards` (permission-gated by
  `PallyPower_CanControl`), so edits write the untouched PallyPower tables and
  send the same `ASSIGN` messages the `/pp` grid sends. A paladin can use this
  panel **instead of** the classic grid, and raid paladins on stock
  PallyPower/PallyPowerTW receive the assignments unchanged. Left-click next /
  right-click previous / wheel; shift sets all classes (legacy `MASSIGN`).
- **Totems** — shaman × element grid plus a "covered party" column, over the
  shared assignment model (click/wheel cycles the catalog; `-` = unassigned;
  `own` = their own subgroup).
- **Buffs / Debuffs / Utility** — the module-declared duty catalogs with a
  "who's responsible" cell per duty: lead/assist cycles through the class's
  candidates, everyone else claims/unclaims themselves.
- The non-blessing tabs are **local until the sync milestone**: your own row
  already drives your strip buttons (step 1b); rows set for others start
  broadcasting when `RPCX` sync lands.
- Pooled rows, ESC-closes, movable, remembers its last tab; 1s repaint plus
  instant repaint on any model change. In **test mode** you are always listed
  as a candidate, so every tab is exercisable solo.

### Added (Assignment & Sync — step 1b: strips are views of my own row)
The first live consumer of the data model (design §9). Solo behaviour is
unchanged; the model simply follows your picks — and when the sync milestone
lands, a leader's assignment will take over the same buttons automatically.
- **Effective selection = assignment first, local preference second, first
  known last.** The Shaman totem buttons, Hunter sting button and Warlock
  curse button now read your own row in `RallyPowerCP_Assign` before the
  `shamanSel`/`hunterSting`/`lockCurse` preferences (which remain the
  solo/offline fallback — no migration). An assignment naming a spell you
  don't know falls through gracefully.
- **Wheeling (or picking in the options dropdown) self-assigns**: it writes
  the local preference AND your own caster block in the shared model —
  PallyPower free-assign style, editing your own row. Stings and curses hold
  exactly one duty key at a time (picking one clears the others).
- **Warlock curse catalog completed**: `CURSE_WEAKNESS` / `RECKLESSNESS` /
  `TONGUES` / `AGONY` / `DOOM` registered with append-only wids 21–25, so
  every wheel option is representable as a duty.
- Out of scope by design: Rogue poisons (weapon buffs, not duties), the
  Expose/Battle Shout buttons (no cycle to assign), and the Priest/Mage/Druid
  per-class buff mapping (blessing-shaped, not a duty; the raid-buff duties
  cover "who maintains it" instead).
- **Solo test:** `/run RallyPowerCP.Assign.SetTotem(UnitName("player"),
  "Earth", "Tremor Totem")` — the Earth button switches to Tremor on the next
  tick; wheel it and `/run` `GetTotem` to see the assignment follow.

### Added (config options for the non-paladin classes)
The options panel gained the applicable PallyPower-style settings for every
non-paladin class, each wired to real behaviour:
- **Settings** — **Transparency** slider (strip-button backdrop opacity) and
  **Horizontal layout** (lay the strip left-to-right). Buff/grid scale is
  already covered by the existing **UI scale** slider (our classes have one
  frame, not the paladin's two).
- **Buttons → Behaviour** — **Smart buffs** (skip already-buffed players;
  off = allow re-casting), **Sound when a buff runs out** (gates the expiry
  ding), **UnitXP SP3 line-of-sight** (reuses the engine's
  `PallyPower_CheckTargetLoS` in our targeting; shared `PP_PerUser` setting),
  and a **Scan frequency (s)** slider (drives the roster-rescan interval).
- **Intentionally omitted:** HD Icons and Color Buff Bar — both are
  Paladin/PallyPower-art-specific (our buttons use live spell icons and their
  own status colours), so they'd be no-op toggles here.

### Changed
- **Priest / Mage / Druid → the class-buff strip** (`RallyPowerCP.BuildClassBuffs`):
  one 100×34 strip button per raid class, showing that class's assigned buff
  (buff icon + gold class-name label + grey buff sub-label), red with a
  need-count when members lack it, green/yellow with a timer when covered.
  Scroll a button to change that class's buff (Fortitude / Divine Spirit /
  Shadow Protection, Intellect, Mark / Thorns), left-click casts the group
  version, right-click tops off the next member, hover opens the same player
  pop-out the paladin bar uses. Priest's utility buttons (PW: Shield / Fear
  Ward) are appended to the strip with the same anatomy. The frame, drag,
  scale grip and saved position all come from the strip engine, so these read
  identically to Shaman / Hunter / Warlock / Rogue.
- **Warrior → a self-contained self-cast strip** (the Warlock-armor pattern):
  one Battle Shout button, green with a cast-derived timer while the shout is
  on you, red when it's missing; click casts (refreshing nearby party), test
  mode simulates. `btn_shout` options toggle.
- **The hand-rolled buff bar is retired.** `Core/RallyPowerCP_Core.lua` dropped
  `CreateBar` / `LayoutButtons` / the class-row + utility-row builders / the
  single-button click-cycle-tooltip helpers / `SavePosition` and the
  `ROW_`/`BAR_`/`UTIL_` geometry (~560 lines). The roster/coverage scan,
  timers, casting, pop-out, expiry ding, SmartBuff key binding and options
  hooks are unchanged and now feed the strip.

### Added
- **Strip engine**: buttons gain an optional `def.onEnter`/`def.onLeave` (the
  class-buff buttons use it to open the pop-out instead of a tooltip) and a
  `def.visible()` predicate (roster-presence gating; all class buttons show in
  test mode).
- **Test mode — all class buttons everywhere.** Priest/Mage/Druid show one
  button per class regardless of the real roster (scroll each to preview its
  buffs). **Paladin**: the legacy blessing bar is grafted to force all ten
  class buttons visible in test mode (wrapping the global `PallyPower_UpdateUI`;
  `PallyPower.lua` is untouched) so a paladin previews the full layout solo,
  the same way `/rpc test` shows every other class its full set.

### Notes / limitations
- Turtle-unverified: exercised statically only (`scripts/verify.py`). On-realm
  checklist — a grid class (Druid/Priest): `/rpc test` shows all nine class
  buttons, the sub-labels name the right buffs and the wheel cycles; a strip
  class (Shaman/Rogue): no regressions; a Paladin: the legacy bar fills with
  all class buttons in test mode and is otherwise untouched.
- The paladin test-mode buttons are a decorative preview (they keep the empty
  `classID`/`buffID` the engine set, so clicks don't cast); only the common
  vertical bar layout is repainted.

---

## [0.11.0] — 2026-07-09
**3.3.5 pop-out parity for the grid classes + the options panel absorbs the
classic PallyPower options** (right-click the minimap icon on any class).

### Changed
- **Grid pop-out unified to the PallyPowerPopupTemplate replica** (Priest,
  Mage, Druid, Warrior — previously 0.3-era 26px colour bars in a 160px
  panel): 100×34 rows with the Smooth skin + Blizzard Tooltip border, the
  official `C_GOOD`/`C_NEEDALL`/`C_SPECIAL` presets (0.5 alpha), 16×16 buff
  icon dimmed to 0.4 on players missing the buff, "R" range letter
  (green/red), "D" dead marker, and the main-tank icon — identical to the
  Paladin pop-out. Rows stack flush in a bare floating container anchored
  `TOPRIGHT → TOPLEFT (-4, 0)` of the class row.
- **Class rows are now 100×34 with a 2px gap** and the Smooth-skin backdrop,
  matching the paladin template; row status colours use the official presets
  (expiring stays yellow `1,1,0.5,0.5`).
- **Local MT/MA roles render on the tank icon** (white / cyan tint;
  CTRL+click still cycles MT → MA → none). The old role letter and the
  `RoleLabel`/`RoleColor` helpers are gone; "R" now means range, as in the
  reference.
- **Minimap right-click opens the RallyPowerCP options for every class**,
  Paladin included. The classic PallyPower frame stays reachable via
  **`/rpc legacy`** as an escape hatch.

### Added
- **Classic PallyPower options merged into the panel** without forking
  state: checkboxes drive the same XML widgets + handler functions the
  classic frame uses (its `uiDirty` refresh flag is file-local, so the
  engine's own handlers are the only sanctioned path — and the classic
  frame's widgets stay in sync); sliders write `PP_PerUser` and call
  `PallyPower_UpdateUI` / `PallyPowerGrid_Update`. `PallyPower.lua` is
  untouched.
  - Paladin **Settings**: lock frames · horizontal buff bar · hide Blizzard
    aura bar · buff-bar scale · grid scale · transparency · minimap
    button/skin · test mode.
  - Paladin **Buttons**: Aura / Seal / Righteous Fury buttons · smart
    buffs · normal-blessing preference · expiry sound · HD icons · color
    buff bar · UnitXP SP3 line-of-sight · scan frequency.
  - All classes: **Show minimap button** (the shared `minimapbuttonshow`).
- Buttons-tab audit fix: the utility-row toggle no longer requires the
  module to also declare grid buffs.

### Limitations
- Turtle-unverified: exercised statically only. On-realm test: hover a
  Priest/Druid class row (pop-out parity + CTRL+click roles), toggle strip
  buttons on a Shaman, and on a Paladin flip Aura/Seal/RF/scale from the
  panel and `/reload` to confirm persistence.
- 3.3.5-only options with no counterpart in this PallyPower fork (report
  channel, Show Pets, Salv in Combat, aura/seal tracker dropdowns, Wait for
  Players, buff-duration and layout dropdowns) are omitted — the fork's
  real `PP_PerUser` keys are authoritative. Background/border/status-colour
  pickers stay fixed at the 3.3.5 defaults (locked decision).

---

## [0.10.0] — 2026-07-08
**Options UI, Milestone A** — the tabbed options frame from
`docs/OPTIONS_UI_SPEC.md`: **Settings** and **Buttons** tabs live, **Raid**
tab stubbed until the Assignment & Sync milestone.

### Added
- **Tabbed options frame** (`Core/RallyPowerCP_Options.lua`), hand-built from
  1.12 building blocks (no Ace3): tooltip-skinned frame, hand-styled tabs,
  `OptionsCheckButtonTemplate` / `OptionsSliderTemplate` /
  `UIDropDownMenuTemplate` / `GameMenuButtonTemplate` widgets, ESC-close via
  `UISpecialFrames`. Open with **`/rpc options`** (any class) or
  **right-click the minimap icon** (non-Paladins; Paladins keep
  `PallyPower_Options`).
- **Settings tab** (all local, per character, applied live): show when
  solo / in party / in raid; show tooltips; test mode (same flag as
  `/rpc test`); UI scale slider 0.5–1.5 (default 1.0 — strips, class bar and
  pop-out; the Paladin engine keeps its own `/pp` scale); minimap icon skin
  dropdown; lock frame positions; Reset Frames button.
- **Buttons tab, generated per class** via the `M.optionsInfo` module
  descriptor contract (`check`/`select`/`slider`/`button`/`header`/`note`
  entries bound to `RallyPowerCP_Settings` keys, optional `get`/`set`/
  `onChange`). Strip classes (Shaman, Hunter, Warlock, Rogue) declare
  per-button enables (`btn_*`; strips re-flow and collapse) and dropdowns
  bound to the **same keys the mouse-wheel writes** (`shamanSel.*`,
  `hunterSting`, `lockCurse`, `roguePoison.*`) — dropdown and wheel are two
  views of one setting. Grid classes (Priest, Mage, Druid, Warrior) get
  auto-generated per-buff checks from `M.buffs` (`gridbuff_*`, honored in the
  buff-usable check) plus a utility-row toggle. Paladins see a note pointing
  at the authoritative legacy `/pp` options.
- **Raid tab** — deferred note; arrives with Assignment & Sync (Milestone B).

### Changed
- `/rpc test`, the options checkbox and the minimap flow all drive one shared
  `RallyPowerCP_SetTestMode`; `/rpc reset` shares its logic with the Reset
  Frames button.

### Limitations
- Turtle-unverified: built against 1.12 FrameXML templates that PallyPower's
  own XML already uses on this client, but the frame has not yet been
  exercised in-game — `/rpc options` on a strip class AND a grid class is the
  required on-realm test.
- The reference panel's background/border/status-color pickers are
  deliberately omitted (locked 3.3.5-parity decision).

---

## [0.9.0] — 2026-07-07
**Test mode** — preview and exercise the whole addon on an under-levelled
character. Toggle with **`/rpc test`** (any class).

### Added
- **`/rpc test`** toggles test mode (saved per character; strip headers show an
  orange **[TEST]** tag while it's on):
  - **Every option appears** in every cycle — grid buffs, totems, stings,
    curses, armor, poison types — even if not yet learned. Unlearned entries are
    marked with an orange `*`.
  - **Clicks simulate instead of cast:** timers start, buttons turn green, and
    chat prints `[test] would cast/drop/apply …` — but nothing is actually cast,
    so there are no failed-cast errors and no reagent use. Strip states run
    purely off the simulated timers (no target needed).
  - Turning it off returns everything to live casting and your real spellbook
    instantly.
- Exceptions that stay real (they read live data by nature): the **Soulstone**
  button (actual bag item + cooldown) and the **poison coating timers**
  (actual weapon enchants) — in test mode the poison *cycle* previews all
  types, but coating a weapon still requires the real item.

---

## [0.8.1] — 2026-07-07
**Strip dimensions now match the paladin template, Shaman moves onto the shared
engine, and lookups are cached.**

### Changed
- **All strip buttons are now the paladin-template size — 100×34 with a 26px
  icon and a 2px gap** (they were 138×30), with the buff-button text anatomy:
  label top-left, timer top-right, sub-label along the bottom. Applies to
  Shaman, Hunter, Warlock, and Rogue at once, since they share the engine.
- **`Class_Shaman.lua` refactored onto the shared strip engine**, deleting its
  bespoke duplicate strip code from 0.7.0. Behaviour is unchanged (wheel picks,
  click drops, right-click clears, cooldown-guarded cast-derived timers, saved
  selections) — your selected totems carry over; the strip's saved position
  resets once.

### Fixed
- **Performance:** spellbook lookups are cached (invalidated on
  `SPELLS_CHANGED`) and bag scans are cached (invalidated on `BAG_UPDATE`).
  Modules poll every 0.25s, so this removes constant full spellbook/bag rescans
  on the 1.12 client.

---

## [0.8.0] — 2026-07-05
**Three more classes — Hunter, Warlock, Rogue — on a new shared strip engine.**
Seven of nine classes now have a working module.

### Added
- **`Core\RallyPowerCP_Strip.lua`** — the reusable utility-strip engine extracted
  from the Shaman pattern: movable titled strip, skinned status buttons
  (icon / label / sub-label / timer, green–red–neutral), saved position per
  strip, tooltips, wheel plumbing, and shared helpers — spellbook lookup,
  bag search, "cast at target," and a **target-debuff tracker** that matches
  the debuff's icon against your own spellbook texture and **learns the real
  aura id under SuperWoW** (exact matching, no hard-coded ids or icons).
- **`Class_Hunter.lua`** — one **Sting** button: wheel picks Serpent / Scorpid /
  Viper (whichever you know), click applies it to your target; green with a
  cast-derived timer while your sting is up, red when the target lacks it.
- **`Class_Warlock.lua`** — three buttons:
  - **Armor** — Demon Armor/Skin (highest known), tracked on you, click to refresh.
  - **Soulstone** — the spec's glow button: green when a stone is in your bags and
    ready, red with a countdown while on cooldown, grey when you have none
    (clicking then *creates* one); click uses it on your friendly target or you.
  - **Curse** — wheel through every curse you know, click applies to the target,
    green while it's up.
- **`Class_Rogue.lua`** — three buttons:
  - **Expose Armor** duty — green/red on your target, click to apply.
  - **Main Hand / Off Hand poison** slots — wheel picks the poison type from
    what's actually in your bags (highest rank wins), click coats that weapon;
    shows the **real remaining time and charges** from `GetWeaponEnchantInfo`.

### Notes
- Sting/curse/expose timers are cast-derived per target (the client can't read
  debuff durations); presence detection is live and exact.
- Cross-player coordination (assigned duties, "who keeps what up") remains the
  sync milestone — these v1 modules are personal-accurate, per the design doc.
- Durations use vanilla defaults; any Turtle deltas are one-line edits.

---

## [0.7.0] — 2026-07-04
**First all-class module: Shaman totems** — and the reusable "cycle button"
pattern the other utility classes will inherit.

### Added
- **`Class_Shaman.lua`** — the Shaman gets its own compact strip of four element
  buttons (Earth / Fire / Water / Air) instead of the buff grid, since totems are
  party auras dropped at your feet, not buffs cast on players.
  - **Mouse-wheel** picks which totem to drop for that element (only totems you've
    learned); **left-click** drops it (self-cast, works in combat);
    **right-click** clears the tracked timer if you picked the totem back up.
  - Buttons show the totem's **real spellbook icon** (no icon guessing), green
    with a countdown while it's down, red when it isn't.
  - Your selected totem per element and the strip's position are **saved per
    character**. Toggle the strip from the minimap or `/rpc`.
  - Casting uses SuperWoW's `CastSpellByName` (falls back to a spellbook cast);
    timers are cast-derived, with a cooldown check so a totem on cooldown doesn't
    start a false timer.
- **Module hooks in the Core:** a class module can now provide `OnActivate` (build
  its own UI) and `Toggle` (own show/hide). The Core calls these for strip-based
  classes, so Shaman participates in the minimap/`/rpc` toggle like everyone else.

### Notes
- v1 tracks and drops **your own** totems. Cross-shaman coordination ("whose
  totem covers which party") uses SuperWoW's totem owner-suffix and arrives with
  the shared assignment/sync milestone.
- Totem durations use vanilla defaults; if Turtle differs (as blessings did),
  they're one edit each at the top of the module.

---

## [0.6.0] — 2026-07-03
**The 1.18.1-native pass — RallyPowerCP now uses SuperWoW where it removes a
1.12 limitation, with a graceful fallback when it's missing.** (Groundwork for
the all-class rollout: every class inherits this cleaner plumbing.)

### Added
- **SuperWoW detection** via `SUPERWOW_VERSION`. A one-time login notice tells
  players when it's missing (the addon then runs in 1.12 compatibility mode).
- **Spell-id buff detection.** SuperWoW makes `UnitBuff` also return each aura's
  spell id, so buffs are now matched by exact id instead of icon texture — no
  more "same icon" collisions. IDs are **learned at runtime** from the icon seed
  (captured the first time a buff is seen), so it needs no hard-coded ids and
  works on Turtle even where its ids differ from Vanilla.
- **Buff data gains an optional `ids = { ... }` field** for classes that want to
  pin exact aura ids; otherwise learning handles it.

### Changed
- **Casting now uses `CastSpellByName(spell, unit)`** under SuperWoW — a single
  call that targets the unit directly and can't disturb your current target.
  This replaces the `autoSelfCast`-CVar + `ClearTarget`/`SpellTargetUnit`/
  `TargetLastTarget` dance in both the Core caster and the pop-out row clicks.
  The old flow is kept as the no-SuperWoW fallback.
- Consolidated the three near-duplicate cast helpers into one primitive
  (`RawCastOnUnit`) used everywhere.

### Notes
- **VanillaFixes** remains a pure client-side performance/timing fix with no Lua
  API — a documented install requirement, nothing the addon calls.
- Detection/casting fall back to the exact 1.12 behaviour when SuperWoW is
  absent, so the addon still loads on a bare client.
- Not yet adopted (later steps): `UNIT_CASTEVENT` for cast-exact timers and
  shared timers (M1), and GUID-based identity for pets/totems (needed for the
  Shaman module).

---

## [0.5.1] — 2026-07-02
**The pop-out rows are now clickable for refreshes, with individual timers.**

### Added
- **Click a player in the pop-out to rebuff them**, official-flyout style:
  - **Left-click** casts the **Greater** blessing on that player (refreshing
    their class). Disabled in combat, per the project's combat rules.
  - **Right-click** casts the **Normal** single-target blessing — it honours
    that player's individual assignment if one is set, and **works in combat**
    (the one action permitted while fighting).
  - Casting goes through PallyPower's own spellbook tables and safety rails:
    auto-self-cast is suspended, your current target is preserved, the spell's
    cooldown is checked, and a 0.7s guard prevents double-click reagent burns.
    Out-of-range and dead targets get a feedback message instead of a wasted
    attempt.
- **Individual timers confirmed per player:** each row's countdown is that
  player's own (`m:ss`), ticked down by the engine, and a click-refresh
  restarts it — Normal casts reset that player's personal timer; Greater casts
  reset the class-wide one, exactly like the engine's own bookkeeping.

---

## [0.5.0] — 2026-07-01
**Phase 1 of the PallyPower 3.3.5 parity directive begins.** The pop-out is now
an exact replica of the WotLK player flyout.

### Changed
- **The player pop-out replicates `PallyPowerPopupTemplate`** from the official
  PallyPower Classic source (reference: `github.com/AznamirWoW/PallyPower`,
  `PallyPower_Wrath.xml`) — the WotLK-state design this project standardises on:
  - **100×34 buttons, stacked flush, floating bare** (no container panel).
  - **Skinned backdrop:** the official default "Smooth" statusbar texture (now
    shipped in `Skins\`) + Blizzard Tooltip border, coloured with the official
    defaults — green `0,0.7,0` Have · red `1,0,0` Need/Dead · blue `0,0,1`
    special/unknown — all at the official 0.5 alpha.
  - **Element-for-element layout:** 16×16 buff icon top-left (alpha 1 buffed /
    0.4 not), white personal timer beside it, player name bottom-right, green/red
    **"R"** range letter top-right, red **"D"** dead marker, and the main-tank
    icon for PallyPower-marked tanks.

### Notes
- 1.12 mappings: "Not Here" players get the blue preset + red R (a hidden
  player's buffs can't be read on this client); the official yellow
  "visible-but-far" R needs range data we don't track yet; the tank icon uses
  the official texture path, which may not exist in 1.12 art (harmlessly blank
  if so).
- Row clicks are display-only for now — porting the flyout's cast/assignment
  interactions is the next parity step, alongside the 84×80 class buttons and
  the main frame.

---

## [0.4.3] — 2026-07-01
**Pop-out reverted; design target changed to PallyPower 3.3.5.**

### Changed
- **Reverted the 0.4.2 pop-out** (the vanilla `PlayerButtonTemplate` rows and
  native assignment-click handlers). The pop-out is back to the 0.4.1
  colour-coded player bars (status-coloured bars with blessing icon, name, tank
  marker, and personal timer).
- **New project design target:** the pop-out — and, going forward, the whole
  Paladin experience — will be restyled to match **PallyPower 3.3.5** (the
  WotLK version in the project reference files) exactly, and that design will
  then be replicated for every other class. The 0.4.2 vanilla-template approach
  matched the wrong reference and is retired.
- The `Core\` / `Classes\` / `PallyPower\` folder structure from 0.4.2 is kept.

---

## [0.4.2] — 2026-06-30
**The pop-out becomes real PallyPower, and the addon gets an AutoRota-style
folder structure.**

### Changed
- **The player pop-out is now built from PallyPower's own `PlayerButtonTemplate`**
  — the exact rows the `/pp` grid uses: 13px-high flush-stacked rows, name on the
  left, the player's **individual assigned blessing** as a small icon on the
  right (just like the grid), and the main PallyPower frame's backdrop —
  following your PallyPower transparency setting.
- **Clicking a pop-out row runs PallyPower's real handlers** (not a copy):
  **Left-click** cycles that player's individual blessing (synced),
  **mouse-wheel** cycles it up/down, **right-click** clears it,
  **middle-click** toggles Main Tank, **CTRL+middle** toggles Healer — all with
  PallyPower's own sync messages and (as leader) raid-icon marking.
- **Name colours match PallyPower exactly**: Tank orange and Healer green
  override; otherwise the buff-tooltip status palette — Have (soft green), Need
  (soft red), Not Here (blue), Dead (bright red). A gold personal timer sits
  right of the name.
- **Restructured into an AutoRota-style folder layout**:
  - `Core\` — `RallyPowerCP_Core.lua` (engine) + `RallyPowerCP_Popout.lua`
  - `Classes\` — one module per class (unchanged)
  - `PallyPower\` — the untouched legacy engine (`PallyPower.lua/.xml`,
    `PallyPowerManaCost.lua`, `MinimapButton.lua/.xml`)
  - Root — `.toc`, `Bindings.xml` (must stay), `PallyPower-ResizeGrip.tga`
    (referenced by absolute path), docs, `Locale\`, `Icons\`, `HDIcons\`,
    `Sounds\`
  No code changes were needed for the move: the toc paths were updated, the
  legacy XML's relative `<Script>` references travel with their lua files, and
  every art path is absolute.

### Notes
- The pop-out rows use PlayerButton indices past `PALLYPOWER_MAXPERCLASS`, so
  the native grid's update loop never touches them, while the native click
  handlers parse them exactly like the grid's own rows. The PallyPower engine
  itself is still unmodified.
- Row clicks now do **assignment** (PallyPower semantics), not casting — casting
  stays on the buff button itself (left = class, right = single top-off), same
  as stock PallyPower.

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
