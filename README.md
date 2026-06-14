# RallyPowerCP

**All-class buff management for Turtle WoW 1.18.1 (1.12 client).**
By **Subtilizer (Torchlite)** · version **0.2.0** · see [CHANGELOG.md](CHANGELOG.md).

Built on **PallyPowerTW** (by ivanovlk) and the original **PallyPower** team.

RallyPowerCP keeps PallyPower's Paladin blessing/seal/aura grid exactly as it
was, and adds an auto-detecting buff tracker for every other buffing class. Log
in on a Paladin and you get the full PallyPower grid, unchanged. Log in on a
Priest, Mage, Druid, or Warrior and you instead get a matching bar that tracks
*your* class's group buffs across the party/raid.

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

- **One button per buff.** A red badge with a number = that many members are
  missing it; faded green = everyone in range is covered.
- **Left-click** buffs the next member who needs it. Once everyone is covered,
  clicks **renew** the next member, so you can top anyone off at any time.
  Targeting a friendly group member always (re)buffs that exact person.
- **Right-click** casts the group/greater version (Prayer of…, Arcane
  Brilliance, Gift of the Wild) on the missing member's subgroup.
- **Scroll the mouse wheel** over a button to switch which buff it tracks; the
  icon, count, timer, and tooltip all follow.
- **Countdown timer** beside each icon turns red and plays a **ding** at 60
  seconds left. Times are exact for buffs on you; for others they count down
  from your cast (the 1.12 client can't read other players' buff durations — the
  same limit PallyPower works around the same way).
- **Hover tooltip** lists everyone by status: **Have** / **Need** /
  **Not Here** (out of range) / **Dead**, just like the Paladin bar.
- **Utility row** (currently Priest): situational single-target casts. PW: Shield
  goes to your target, else the lowest-health member in range; Fear Ward goes to
  your target, else you.
- Only buffs you've actually learned appear, so the bar scales with level/spec.
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

## Credits

- RallyPowerCP by **Subtilizer (Torchlite)**.
- Based on **PallyPowerTW** by ivanovlk.
- Original PallyPower by Hjorim / Sneakyfoot / Rake / Xerron / Azgaardian /
  Aznamir. Spanish localization by Nuevemasnueve.
