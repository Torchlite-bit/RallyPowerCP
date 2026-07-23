# Aegis: RallyPower

**All-class raid buff coordination for Turtle WoW 1.18.1** (1.12 client)

![Version](https://img.shields.io/badge/version-0.15.0-blue)
![Lua](https://img.shields.io/badge/Lua-5.0-red)
![WoW](https://img.shields.io/badge/WoW-1.12.1-purple)

A comprehensive buff management addon for Turtle WoW that extends PallyPower's Paladin-focused toolkit to all nine classes. Coordinate raid buffs, totems, debuffs, and interrupts across your entire group with shared assignment tracking, test-mode previews, and zero network traffic (unless you're coordinating).

**By Subtilizer (Torchlite) · Built on PallyPowerTW (ivanovlk) & original PallyPower**

---
## 📸 Screenshots

<!-- 
TEMPLATE INSTRUCTIONS: 
Replace the placeholder image links (e.g., 'path/to/your/image1.png') inside the parentheses with the actual URLs or relative file paths to your screenshots once you have them uploaded to your repository. 
-->


<img width="1539" height="688" alt="class buff" src="https://github.com/user-attachments/assets/921b44d4-564b-4a77-8323-59f40af7478e" />

<img width="1556" height="688" alt="raid roles" src="https://github.com/user-attachments/assets/51575c1f-b2f1-4f81-be10-b1c241e9ca0d" />




---

## ✨ Key Features

### 📊 Per-Class Buff Management
Every class gets a dedicated buff bar with its own tracking, UI, and controls:

| Class | Features |
|-------|----------|
| **Paladin** | The original PallyPower blessing/seal/aura grid + a **hover player pop-out** for each buff (see who has it, who needs it, click to refresh) |
| **Priest** | Power Word: Fortitude, Divine Spirit, Shadow Protection + Fear Ward utility |
| **Mage** | Arcane Intellect buff + Scorch debuff-tracking on targets |
| **Druid** | Mark of the Wild, Thorns |
| **Warrior** | Battle Shout (party-wide) + Sunder Armor tracking/application |
| **Shaman** | **All Totems** button (drops 4 totems in order via GCD), element toggles |
| **Hunter** | Sting selection and application on targets |
| **Warlock** | Armor (tracked), Soulstone (status tracked), Curse cycle |
| **Rogue** | Expose Armor tracking + Main/Off-hand poison selection |

### 🎯 Assignment Panel ("Who Covers What")
Coordinate assignments across the raid with real-time sync:

- **Blessings tab** — PallyPower's assignment grid with exact ranks/Symbol counts (byte-compatible with stock PallyPower)
- **Raid Buffs** — Caster × class matrix for Priest/Mage/Druid buffs
- **Totems** — Shaman totem assignments (auto-grouped, icon labels)
- **Debuffs** — Warrior Sunder, Mage Scorch duty tracking
- **Kick tab** — Interrupt tracker (who has kicks, whose are ready — your own exact, others best-effort)
- **Roles** — Mark Main Tank/Off-Tanks, set per-tank blessings, mark healers

Test mode seats a full 40-player preview raid so you can test on low-level characters.

### 📡 Shared Assignment Sync (RPCX Protocol)
- Broadcast your assignments + receive others' over a dedicated addon channel
- Leader-gated edits; Free Assignment mode lets members edit freely
- Automatic message chunking for large assignment blocks
- No impact on blessings — they stay on PLPWR (stock PallyPower compatible)

### 🧪 Test Mode
```macro
/rpc test
```

Preview every buff on a fake 40-man raid of lore characters, simulate casts with real timers, and test UI changes without affecting live assignments.

### 🔧 Minimap Icon
Left-click opens the right thing for your class. Right-click opens Options. Shift-click cycles skins (5 included: Blue, Gold, Ivory, White, Pearl).

---

## 🚀 Quick Start

### Installation
1. Download and extract to `Interface/AddOns/Aegis_RallyPower/`
   - Upgrading from pre-rebrand? Delete old `RallyPowerCP/` folder first (SavedVariables aren't carried over)
2. Launch WoW, log in
3. Left-click the minimap icon or use `/rpc` to toggle the buff bar

### Commands

| Command | What It Does |
|---------|-------------|
| `/rpc` (or `/aegis`) | Toggle the class buff bar |
| `/rpc options` | Open settings (or right-click minimap icon) |
| `/rpc assign` | Open the assignment panel (or right-click a strip title) |
| `/rpc test` | Test mode — preview buffs on all specs |
| `/rpc sync` | Force a full assignment resync |
| `/rpc castdbg` | Log raw cast events (SuperWoW only; for debugging) |
| `/rpc slots` | Dump tank-slot plan (for sync debugging) |
| `/pp` | PallyPower grid (Paladins only) |

**Key Binding:** Bind "Smart buff: next member missing any buff" to top off the group hands-free.

---

## 🛠️ Development Status

### ✅ Completed
- All nine class modules (bars, buttons, targeting)
- Shared assignment data model (blessings, totems, debuffs, utilities, interrupts)
- RPCX sync protocol (broadcast & receive, leader permissions, Free Assignment)
- Assignment panel with all five tabs
- Mage Scorch debuff-tracking button + debuff-button infrastructure
- Message chunking for large assignment blocks
- Interrupt tracking (Kick tab) with SuperWoW cast observation
- Test mode with 40-player preview raid
- Full Options UI with per-class toggles and settings

### ⏳ Next: Cast-Exact Shared Timers
Broadcast actual spell casts via SuperWoW `UNIT_CASTEVENT` so the raid sees what's *truly up* instead of best-effort timings. Currently blocked on in-game validation of cast observation on Turtle WoW.

**Run `/rpc castdbg` to help validate:** toggle on, trigger some interrupts, check chat for raw cast events. Results feed back to development.

### 🔮 Future Possibilities
- Per-caster Free Assignment (allowing members to edit specific rows)
- Mage/Warrior debuff-duty buttons (auto-tracking via UnitHasDebuffEntry)
- Raid buff grid view (if assignment panel grows)

---

## 📋 Requirements

### Client
* :crystal_ball: **SuperWoW** - Strongly Recommended
  Enables exact spell-ID-based buff detection and clean one-call casting. Without it, the addon falls back to icon-matching and target-juggling (less reliable, but works).
  ↳ [SuperWoW Release](https://github.com/balakethelock/SuperWoW/releases/tag/Release) | [Features Wiki](https://github.com/balakethelock/SuperWoW/wiki/Features) | [SuperAPI Addon](https://github.com/balakethelock/SuperAPI)

- 🔨 **VanillaFixes** — Recommended  
  Eliminates client stutter. Not required, but makes timers and UI smoother.
  ↳ [VanillaFixes Release](https://github.com/hannesmann/vanillafixes.git)

### Compatibility
- **Paladin sync works!** Aegis: RallyPower keeps PallyPower's `PLPWR` sync channel and message format, so Aegis Paladins coordinate blessings with stock PallyPower / PallyPowerTW users bidirectionally.
- **Other classes are local-only by default** — no network traffic. Turn on the assignment panel to enable `RPCX` sync with other Aegis users.

---

## 🐛 Known Limitations

- **1.12 client limitation:** Can't read another player's remaining buff time, so non-self timers count down from your casts (PallyPower's solution; we use the same approach)
- **Range detection:** Uses visibility checks, which are wider than buff range; out-of-range casts cancel cleanly
- **Cast observation:** Requires SuperWoW's `UNIT_CASTEVENT`; without it, other players' kick timers show "ready" (best-effort)

---

## 📚 References

- **CHANGELOG.md** — Version history, features per release, roadmap
- **docs/DESIGN_SYNC.md** — RPCX protocol specification (grammar, flows, permissions)
- **docs/DESIGN_ALLCLASSES.md** — Class module architecture and pattern
- **docs/OPTIONS_UI_SPEC.md** — Settings frame layout and options contract
- **CLAUDE.md** — Development brief (milestones, design decisions, verification workflow)

---

## 🙏 Credits

- **Aegis: RallyPower** by Subtilizer (Torchlite)
- **PallyPowerTW** by ivanovlk
- **Original PallyPower** by Hjorim, Sneakyfoot, Rake, Xerron, Azgaardian, Aznamir
- Spanish localization by Nuevemasnueve

---

## 📄 License

Inherits from PallyPower's original license terms. See in-game addon list for details.

---

**Questions? Bugs? Feature ideas?**  
Check the [CHANGELOG.md](CHANGELOG.md) for what's planned. File an issue or visit the Turtle WoW forums.
