# RallyPowerCP — Options UI Spec (Claude Code build target)

**Goal:** a tabbed options frame like PallyPower Classic's (Settings / Buttons /
Raid / Profiles), serving **every class** from one panel. Extracted from the
reference screenshots and `PallyPowerOptions.lua` in the reference repo
(`github.com/AznamirWoW/PallyPower` — clone it for exact strings/layout, but
note its options render through Ace3, which does NOT exist on 1.12: **the frame
must be hand-built** from the 1.12 building blocks below).

**Sequencing (decided):**
- **Milestone A (build now, no dependencies):** the frame + **Settings** tab +
  **Buttons** tab. All local config over `RallyPowerCP_Settings`.
- **Milestone B (with Assignment & Sync):** the **Raid** tab (MT/MA roles,
  Auto-Buff overrides, Free Assignment, Auto-Assign) — it edits *shared* state.
  In Milestone A it exists as a tab with a short "arrives with the sync
  milestone" label.
- **Profiles tab:** deferred entirely.

---

## Reference inventory (what the 3.3.5 panel contains)

### Settings tab
- **When to show:** Show Globally · Show in Party · Show when Solo · Show
  Tooltips · Blessings Report Channel (dropdown).
- **What to buff:** Smart Buffs · Show Pets · Salv in Combat.
- **Looks:** Buff Scale slider (0.4–1.5, default 0.9) · Buff/Player Button
  Layout dropdown ("Vertical Down | Left" …) · Background Textures dropdown
  (swatch, "Smooth") · Borders dropdown (swatch, "Blizzard Tooltip") · Reset
  Frames button.
- **Status colors:** Fully Buffed / Partially Buffed / None Buffed swatches.

### Buttons tab
- **Aura Button:** enable + "Aura Tracker" dropdown (which aura to track).
- **Seal Button:** enable · Righteous Fury enable · "Seal Tracker" dropdown.
- **Auto Buff Button:** enable · "Wait for Players" enable.
- **Class & Player Buttons:** Class Buttons · Player Buttons · Buff Duration.
- **Drag Handle:** enable.

### Raid tab (Milestone B)
- MT/MA explanation text.
- **Auto-Buff Main Tank:** enable + "Override [Greater dropdown] …with Normal
  [Normal dropdown]" (e.g. G.Salvation → Blessing of Light).
- **Auto-Buff Main Assist:** same pair (e.g. → Blessing of Might).
- (On the main grid, same milestone: Free assignment checkbox, Auto-Assign /
  Clear / Refresh / Blessings Report buttons.)

---

## RallyPowerCP mapping

### Milestone A — Settings tab (global, all classes)
| Control | Setting | Notes |
|---|---|---|
| Show when Solo / in Party / in Raid (3 checks) | `showSolo/showParty/showRaid` (default all on) | strips + class grid honor on roster change |
| Show Tooltips | `tooltips` (on) | strip/grid tooltip suppression |
| **Test Mode** | `testMode` | same flag as `/rpc test` — keep them in sync |
| Scale slider 0.5–1.5 | `uiScale` (0.9?) | `frame:SetScale()` on strips, grid bar, pop-out |
| Lock frames | `locked` | disables dragging on strips + grid bar |
| Minimap icon skin dropdown | existing skin setting | reuse `RallyPowerCP_ApplyMinimapSkin` values |
| Reset Frames button | clears all `stripPos_*` + `barPoint` | re-anchor defaults |

**Fixed for now (locked 3.3.5-parity decisions — show as disabled rows or omit):**
background texture (Smooth), border (Blizzard Tooltip), status colors
(official presets). Exposing them is a later, separate decision.

### Milestone A — Buttons tab (per-class, generated)
One tab whose contents are **generated from the active class module** — this is
the "for each class" requirement. Never nine hardcoded panels.

**Module contract (design-first — propose before coding):** each strip module
exposes an options descriptor; the tab renders it generically:

```lua
M.optionsInfo = {
  { type = "check",  key = "btn_earth",   label = "Earth totem button", default = true },
  { type = "select", key = "shamanSel.Earth", label = "Earth totem",
    values = function() return <known Earth totem names> end },
  ...
}
```

- `check` → UICheckButtonTemplate bound to `RallyPowerCP_Settings[key]`.
- `select` → UIDropDownMenu bound to the same saved keys the mouse-wheel
  already writes (`shamanSel.*`, `hunterSting`, `lockCurse`, `roguePoison.*`) —
  the dropdown and the wheel are two views of one setting.
- Per-button enable/disable: strips honor `btn_*` flags in `Finish()`/refresh
  (hidden buttons collapse the strip height).
- Grid classes (Priest/Mage/Druid/Warrior): generate per-buff enable checks
  from `M.buffs` (+ Priest utility row toggle). Paladin: this tab shows a note —
  its buttons are configured in the classic PallyPower options (`/pp` →
  Options), which already exist and stay authoritative for the legacy engine.

### Milestone B — Raid tab
MT/MA role editor + Auto-Buff MT/MA override pairs + Free Assignment — all
reading the shared assignment model from the sync milestone. Until then the tab
body is one sentence: *"Raid roles & auto-buff arrive with the Assignment &
Sync milestone."*

---

## 1.12 building blocks (no Ace3)

- Frame: `CreateFrame("Frame", ..., UIParent)` + the addon's `PP_BACKDROP`
  style (tooltip bg/border, tile 16 / edge 16 / inset 5); `SetMovable` + title
  drag; special-frames ESC-close via `tinsert(UISpecialFrames, name)`.
- Tabs: plain Buttons styled like the reference (or
  `OptionsFrameTabButtonTemplate` if present on 1.12 — verify; hand-styled is
  safe), one content child frame per tab, show/hide on click.
- Checkbox: `CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")`
  + `getglobal(name.."Text"):SetText(...)`.
- Slider: `"OptionsSliderTemplate"` (`getglobal(name.."Low"/"High"/"Text")`).
- Dropdown: `"UIDropDownMenuTemplate"` + `UIDropDownMenu_Initialize/SetSelectedValue/SetWidth`
  (all exist on 1.12; remember handlers use `this`/`arg1`).
- Section headers: `GameFontNormal` fontstrings + a thin divider texture.
- Entry points: `/rpc options` (add to the slash handler); minimap
  **right-click** for non-Paladins routes here (Paladins keep
  `PallyPower_Options()`); a small button on each strip title is optional.

## Definition of done (Milestone A)
- `/rpc options` opens the tabbed frame on any class; ESC closes it.
- Settings tab controls apply **live** (scale, show rules, lock, test mode) and
  persist per character.
- Buttons tab renders from the active module's descriptor; toggling a button
  hides it and re-flows the strip; every dropdown round-trips with the wheel.
- Raid tab shows the deferred note. `scripts/verify.py` passes; test on a strip
  class AND a grid class.
