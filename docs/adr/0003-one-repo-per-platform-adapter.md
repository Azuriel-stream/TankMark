# One repo, shared pure Core plus a per-platform adapter, packaged per target

**Status:** accepted (WotLK/Ascension port, grilled 2026-07-07)

## Context & decision

TankMark targets Vanilla 1.12 with SuperWoW. We want it to also run on a **WotLK 3.3.5 client
(Project Ascension)** — best-effort, for casual 5-mans, with a deliberately reduced envelope (see
[ADR 0004](0004-ascension-pre-pull-marking-model.md)). The two clients differ at *parse time*: Vanilla
is Lua 5.0, Ascension is Lua 5.1.

The seam work already shipped (Ledger / Assignment / Processor-`DecideMark` / Governor / ProfileStore
/ ZoneView / `DecidePull`) is **pure and Lua-5.0-clean**, so the decision logic ports *mechanically*,
and **GUID is the core's identity currency** on both clients. That makes the shared-core surface large
and the platform surface small.

**Decision:** **one repo, one branch.** A **shared pure Core** plus a thin **per-platform adapter**
(`TankMark.Platform` — capability flags plus the few platform-bound primitives: apply-a-mark,
read-a-mark, identity, event source, transport, and the `L` Locals API cache). A **tiny build step**
assembles Core + the chosen `Platform/` directory + the correct `.toc`, renaming it to `TankMark.toc`,
and drops the result into each client's own AddOns folder. The build step extends the existing
`.claude/sync-to-network.sh`.

## Considered options

- **A second repository (rejected).** A behavioral fix in shared Core would have to be ported or
  copied twice; the two copies drift; the off-client `tests/` harness would need duplicating. All cost,
  no isolation benefit that the adapter doesn't already give.
- **A long-lived platform branch (rejected).** A permanent merge tax with the same duplication problem
  deferred rather than solved; the two builds drift with every Core change.
- **Runtime client-detection in a single package (rejected).** Impossible at the boundary that
  matters. Lua 5.0 vs 5.1 is a **parse-time** fork — `#t` is a *syntax error* on 1.12, so a
  Wrath-flavored file cannot even load on Vanilla — and both old clients **ignore `.toc` flavor
  suffixes** (a 2019+ feature), so each reads the single `TankMark.toc`. Detection cannot rescue a file
  that will not parse.
- **One repo + per-platform adapter + package-per-target (accepted).** A behavioral change in shared
  Core is **one edit** inheriting to both builds and validated by the shared off-client harness; only
  genuinely platform-bound files fork; the build step is small and reuses the sync script.

## Consequences

- **A build step enters a project whose stated identity is "no build step."** Bounded: it is
  *assemble-and-copy*, not a compile — the source stays interpreted, no bundler, no transpile. The
  CLAUDE.md "no build step" claim is narrowed to "no *compile* step."
- **The platform fork surface is small and named:** the adapter primitives + the Locals cache. The
  guiding rule is **keep every platform fn GUID-in** where a GUID is a valid handle (Vanilla), and let
  the platform resolve GUID→addressable-token internally. The **one exception** is Ascension's apply
  edge, where no such resolution exists (a GUID is not a token) — there the adapter takes the live
  token directly. See [ADR 0004](0004-ascension-pre-pull-marking-model.md).
- **The Vanilla "no non-SuperWoW path" invariant is preserved:** the Vanilla adapter still reports
  `canAutomate = false` without SuperWoW, exactly as today.
- **The off-client `tests/` harness covers both builds** because the decision layer is shared and pure
  — a Lua 5.1 harness already exists.
- **Two `.toc`s ship** (`## Interface: 11200` and `30300`); the build renames the right one per target;
  the two clients never share an AddOns folder.
- **Vanilla is untouched.** Every platform difference is a capability flag read in shared Core or a file
  that only exists in the Vanilla `Platform/` dir, so the Vanilla build is behavior-identical to today.
</content>
