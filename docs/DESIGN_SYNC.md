# 📡 RallyPowerCP — Sync Protocol (RPCX)

Milestone step 2 of *Assignment & Sync*. Broadcasts the totem / duty /
raid-buff assignments the model already stores (step 1) to the raid, receives
and stores others', and gates edits by permission. **Blessings are untouched:
they keep riding the legacy `PLPWR` channel** (`SELF`/`ASSIGN`/`AASSIGN`/…) —
RPCX carries only what PallyPower never knew about.

Lua 5.0, 1.12 client. Mirrors PallyPower's own sync patterns (a dedicated
addon-message prefix, ignore-your-own-echo, `REQ` → reply, `CheckRaidLeader`
as the permission gate) so it reads as a clean sibling to PLPWR.

---

## 1. Channel

- Prefix **`RPCX`**. Separate `CHAT_MSG_ADDON` registration; PLPWR is never
  read or written here.
- Sent to `RAID` when in a raid, else `PARTY`, via `SendAddonMessage` — the
  exact call shape PallyPower uses. Solo (no group) sends nothing.
- A client **ignores messages whose sender is itself** (`arg4 == me`), which
  is how the engine suppresses its own echo — no `seq` needed for that.

## 2. Message grammar

Space-delimited head, `;`-delimited payload sections. Player names can't
contain spaces or `;` (client rule), so both split cleanly.

```
<v> REQ
<v> BLK <caster> <seq> <payload>
<v> CLR <caster>
```

- `<v>` — schema version (`1`). A client ignores a message whose `<v>` it
  doesn't understand (forward-compat; today only `1` exists).
- `REQ` — "send me your plan." Sent on entering world and on roster change.
- `BLK` — asserts `<caster>`'s whole block (authoritative *replace*, not
  merge). `<seq>` is the caster block's monotonic counter (carried for future
  ordering; v1 correctness is arrival-order LWW + permission, §4).
- `CLR` — drop `<caster>`'s block entirely (the panel's Clear on your own row).

### Payload sections (each `<tag><data>`, joined by `;`, empty ones omitted)

| Tag | Domain | Data | Example |
|---|---|---|---|
| `c` | class token | English token | `cSHAMAN` |
| `t` | totems | totem `wid`s (each wid implies its element) | `t3,17` |
| `d` | duties | `wid` or `wid=target` (name / `@ROLE`) | `d11,3=Seraphine,19=@MT` |
| `b` | raid-buff grid | `classID.buffIndex` pairs | `b0.1,1.1,2.3` |

- **Totem wids** are globally unique across elements (Class_Shaman assigns
  them 1..N in element order), so a bare wid reverse-maps to exactly one
  `(element, spell name)`. Names never cross the wire (Turtle-rename safe).
- **Duty wids** are the catalog's stable `wid`s (§7 of the model design).
  `target` is a player name (Soulstone/Innervate) or a `@ROLE` token; absent
  target = the untargeted `true` claim.
- **Raid-buff grid** (`cbuff` domain): `buffIndex` indexes the *caster's
  class* buff catalog (`RallyPowerCP.classes[token].buffs`), which every
  same-version client shares. Append-only, like wids.
- **Unknown wids / indices are skipped, not errored** — a client on an older
  catalog silently ignores entries it can't map, keeping the rest.

Example full block (a shaman): `1 BLK Stormtide 4 cSHAMAN;t3,17`
A warlock: `1 BLK Soulbrand 2 cWARLOCK;d11,17=Seraphine`

## 3. Flows

- **On entering world / roster change**: send `REQ`, then re-broadcast every
  block I'm authoritative for (see §4) so joiners and I reconcile both ways.
- **On local edit** (model `Notify` fires for a caster I just changed):
  mark that caster dirty; a **0.5 s debounced flush** serializes and sends one
  `BLK` per dirty caster. Debounce batches a burst of cell clicks into one
  message and collapses no-op repaints.
- **On `REQ` received**: reply by broadcasting every block I'm authoritative
  for (my own always; others' only if I'm lead/assist). Redundant leader +
  self assertions resolve by §4; the cost is a handful of tiny messages.
- **On `BLK` received** (sender ≠ me): permission-check (§4); if allowed,
  **replace** `casters[caster]` with the decoded block and fire a UI notify.
  Applying a remote block never re-broadcasts (an `applyingRemote` guard on
  the dirty hook), so there's no echo loop.
- **On `CLR` received**: permission-check, then `casters[caster] = nil`.
- **Roster prune** already exists (`A.PruneToRoster`); the sync frame calls it
  on roster change so leavers drop out, exactly like PallyPower.

## 4. Permissions & conflicts (PallyPower-faithful)

Acceptance of a `BLK`/`CLR` for `caster` from `sender`:

```
sender == caster                      -- you own your own row (self-assign)
  or PallyPower_CheckRaidLeader(sender)  -- lead/assist may push anyone's plan
```

This is the same rule PallyPower applies to `ASSIGN`, reused verbatim (the
model's `CanEdit` gates *local* writes with the identical test). A leader can
therefore push a plan to a member's client; a member can only assert
themselves. **Conflict resolution is arrival-order last-writer-wins**, exactly
as PallyPower resolves two people editing the same blessing — human-paced
edits make races practically impossible, and a leader who wants to override
just clicks (their message arrives last). `seq` is carried for a future
hardening but v1 does not depend on it.

Free Assignment for non-paladins (letting a member edit another member's row)
is **out of scope for v1**: PallyPower's `freeassign` flag rides paladin
`SELF` on PLPWR and only populates `AllPallys` (paladins). v1 gates on
lead/assist; a per-caster free-assign signal on RPCX is a fast-follow.

## 5. Not in v1 (fast-follows)

- **Cast-exact shared timers** — filling other casters' `RallyPowerCP.
  AssignStatus` from broadcast cast times / SuperWoW `UNIT_CASTEVENT` (model
  §8). v1 syncs *intent*; "actually up" for remote casters comes next.
- **Message chunking** — a single caster block is well under the ~255-char
  addon-message limit for any realistic plan; a length guard warns if that
  ever trips, and chunking lands only if needed.
- **REQ-reply jitter** — v1 replies immediately (raids ≤40, tiny messages);
  add a random stagger only if a thundering-herd shows up on a real pull.
- **Non-paladin Free Assignment** (§4).

## 6. Files

New `Core\RallyPowerCP_Sync.lua`, loaded after `RallyPowerCP_Assign.lua` and
the class modules (it reverse-maps their catalogs) and before the panel. The
panel and strips already read the model, so remote assignments appear in them
with no extra wiring — the sync layer only feeds the store and fires the same
`Notify` the panel already subscribes to.
