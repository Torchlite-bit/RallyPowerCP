# Aegis: RallyPower

**All-class buff management for Turtle WoW 1.18.1 (1.12 client).**
By **Subtilizer (Torchlite)** · version **0.14.0** · see [CHANGELOG.md](CHANGELOG.md).

Built on **PallyPowerTW** (by ivanovlk) and the original **PallyPower** team.

**Aegis: RallyPower** (formerly RallyPowerCP) keeps PallyPower's Paladin blessing/seal/aura bar and grid, and
adds the hover **player pop-out** to it: hover a blessing button on the buff bar
and a colour-coded list of that class's players (Have / Need / Not Here / Dead,
with names and timers) expands to its left. It also adds an auto-detecting buff
tracker for the other buffing classes — log in on a Priest, Mage, Druid, or
Warrior and you get a matching bar that tracks *your* class's group buffs across
the party/raid.

---

## What you get per class

| Class | What the bar does |
|-------|-------------------|
| **Paladin** | The original PallyPower blessing bar/grid, with a hover **player pop-out** on each buff-bar class button, replicating **PallyPower 3.3.5's player flyout**: skinned status-coloured buttons (green Have / red Need / blue Not Here), buff icon with dimming, personal timer, name, "R" range letter, "D" dead marker, and tank icon. **Click a player to refresh:** left = Greater blessing (out of combat), right = Normal single-target (honours individual assignments; works in combat). |
| **Priest** | Power Word: Fortitude, Divine Spirit, Shadow Protection — plus a utility row: Fear Ward. |
| **Mage** | Arcane Intellect. |
| **Druid** | Mark of the Wild, Thorns. |
| **Warrior** | Battle Shout (self-cast; one click refreshes nearby party) and a Sunder Armor button that tracks/applies it on your target. |
| **Shaman** | A totem strip: an **All Totems** button (one click drops your four selected totems in order, pacing the casts through the global cooldown and skipping totems on cooldown; right-click clears every timer) followed by the four element buttons (Earth / Fire / Water / Air — scroll to pick a totem, click to drop it; shows its icon, green-with-timer when down). Toggle from the minimap or `/rpc`. |
| **Hunter** | A Sting button: scroll to pick Serpent / Scorpid / Viper, click to apply to your target; green while your sting is up. |
| **Warlock** | Armor (self, tracked), Soulstone (green = ready in bags, red = cooldown, grey = none — click creates/uses it), and a Curse cycle for your target. |
| **Rogue** | Expose Armor duty on your target, plus Main-hand / Off-hand poison slots — scroll picks the poison from your bags, click coats the weapon, with real remaining time and charges. |

Still to come: the Priest tank-shield button, Mage/Warrior debuff-duty buttons,
and the raid-wide assignment/sync layer that coordinates all of it.

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
  local — not yet shared with other Aegis: RallyPower users or used by smart
  targeting; that's coming in the role/sync update.)*
- **Countdown timers** turn the row yellow and play a **ding** at 60 seconds
  left — for every tracked buff, even one scrolled off the rows. Times are exact
  for buffs on you; for others they count down from your cast (the 1.12 client
  can't read other players' buff durations — the same limit PallyPower works
  around the same way).
- **Utility row** (currently Priest): situational single-target casts. Fear Ward
  goes to your assigned tank/healer if set (Roles tab + Options → Raid), else
  your target, else you.
- Only buffs you've learned appear, so the bar scales with level/spec.
- **Drag** to move; position is saved per character.

## Commands & key binding

| Command | Description |
|---------|-------------|
| `/pp`, `/pallypower`, `/rp`, `/rallypower` | Paladin grid / buff bar (PallyPower) |
| `/rpc` (alias `/aegis`) | Toggle the all-class buff bar (non-Paladins); all subcommands work on either |
| `/rpc test` | **Test mode** — show every option (unlearned marked `*`) and simulate casts with real timers, for previewing on low-level characters |
| `/rpc options` | **Options frame** (any class; or **right-click** the minimap icon) — Settings tab (show rules, tooltips, test mode, UI scale, minimap skin/button, lock/reset frames) and a per-class Buttons tab; Paladins get the merged classic PallyPower settings |
| `/rpc assign` | **Assignment panel** ("Who Covers What"; any class; or **right-click** a strip's title / the paladin buff bar) — Blessings tab drives the classic PallyPower assignments **with Aura and Seal columns first**, each paladin's **blessing/aura ranks+talents and Symbol of Kings count** under their name (byte-compatible with stock PallyPower users); the **Raid Buffs tab is a caster × class grid** (priests/mages/druids — their strips follow their rows); plus Totems (auto group, totem icons) / Debuffs over the shared assignment model; a **Kick tab** that tracks who has an interrupt and whose kick is off cooldown (your own exact, others best-effort); and a **Roles tab** with Main-Tank + off-tank dropdowns, healer marking, and per-tank blessings. Scale grip bottom-right; real spell tooltips for spells in your spellbook. In test mode it seats a full 40-man preview raid of lore characters for solo testing |
| `/rpc sync` | Force a full assignment re-sync — request everyone's totem/duty/raid-buff assignments and re-broadcast yours over the `RPCX` channel (blessings still sync separately over PLPWR) |
| `/rpc legacy` | The classic PallyPower options frame (escape hatch in case something wasn't migrated) |
| `/rpc reset` | Reset the class bar's position |
| `/rpc icon` | Cycle the minimap icon skin (any class; or **shift-click** the icon) |
| `/rpc icon <name>` | Set a skin directly: `blue`, `ivory`, `white`, `gold`, `pearl` |

Bind **"Smart buff: next member missing any buff"** under Aegis: RallyPower in the
Key Bindings menu to top off the group hands-free — each press buffs the next
member missing anything.

## Minimap icon

Shown for every class (toggle it in Options). **Left-click** opens the right
thing for your class — the Paladin grid on a Paladin, the class bar on everyone
else. **Right-click** opens Options. **Shift-click** cycles the icon skin. Five
skins ship (Blue & Gold default, Ivory, White, Gold, Pearl).

## Installation

1. Put the `Aegis_RallyPower` folder in `Interface/AddOns/` (the folder name
   must be `Aegis_RallyPower`, matching `Aegis_RallyPower.toc`). Upgrading from
   the pre-rebrand build? Delete the old `RallyPowerCP` folder first — saved
   settings are not carried over.
2. That's it — all art, sounds, and textures are bundled, and every path is
   verified against a real file.

### Client requirements (Turtle WoW 1.18.1 / 1.12 client)

- **SuperWoW** — strongly recommended. Aegis: RallyPower uses it for exact,
  spell-id-based buff detection and clean one-call targeted casting. Without it
  the addon still works, falling back to icon-based detection and the classic
  target-juggling cast (you'll get a one-time notice at login).
- **VanillaFixes** — recommended. A client-side fix that eliminates stutter and
  animation lag. It has no in-game effect the addon relies on, but it makes the
  whole client (and the bar's timers) run smoother.

## Architecture (for tinkering)

Aegis: RallyPower follows an AutoRota-style layout — a class-independent core, one
module per class, and the legacy engine quarantined in its own folder:

```
Aegis_RallyPower\
  Aegis_RallyPower.toc
  Bindings.xml                  (key bindings — must stay at the root)
  PallyPower-ResizeGrip.tga     (referenced by absolute path — stays at root)
  Core\
    Aegis_Core.lua       (the class-independent engine)
    Aegis_Popout.lua     (the PallyPower buff-bar player pop-out)
  Classes\
    Class_Priest.lua  Class_Mage.lua  Class_Druid.lua  Class_Warrior.lua
  PallyPower\                   (the original PallyPower engine, untouched)
    PallyPower.lua  PallyPower.xml  PallyPowerManaCost.lua
    MinimapButton.lua  MinimapButton.xml
  Locale\   Icons\   HDIcons\   Sounds\
```

- **`Core\Aegis_Core.lua`** — the engine: roster scanning, buff
  detection, casting, the bar UI, timers, tooltips, scrolling, minimap skins,
  and slash commands. It knows nothing about specific classes.
- **`Classes\Class_<Name>.lua`** — one module per class. Each registers with
  `AegisRP:NewClass("TOKEN")` and supplies only its data.
- **`Core\Aegis_Popout.lua`** — attaches the player pop-out to the
  PallyPower buff bar. Reads PallyPower's own per-button data without modifying
  the engine.
- **`PallyPower\`** — the original engine, deliberately left intact.

### Adding a class or buff

Copy an existing `Classes\Class_<Name>.lua`, change the token and data, and list
the file in `Aegis_RallyPower.toc`. Buff entry fields:

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

- **Paladin sync works.** Aegis: RallyPower keeps PallyPower's sync channel (prefix
  `PLPWR`) and message format, so an Aegis: RallyPower Paladin coordinates blessings
  with players running original PallyPower / PallyPowerTW in both directions.
- **The class bar is local-only** — it sends nothing over the network, so it
  can't conflict with anyone, but it also doesn't coordinate between two casters
  of the same class yet (that's the cross-caster sync on the roadmap).

## Known limitations

- On the 1.12 client there is no way to read how much time is left on another
  player's buff, so non-self timers count down from your own casts.
- "In range" uses the game's visibility check, which is a wider radius than buff
  range; an out-of-range cast cancels cleanly and the next click moves on.

## Credits

- Aegis: RallyPower by **Subtilizer (Torchlite)**.
- Based on **PallyPowerTW** by ivanovlk.
- Original PallyPower by Hjorim / Sneakyfoot / Rake / Xerron / Azgaardian /
  Aznamir. Spanish localization by Nuevemasnueve.
