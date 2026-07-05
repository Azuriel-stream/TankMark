-- The Mark Ledger: the single owner of mark-ownership state.
--
-- Owns four indices over "which mob holds which raid mark":
--   MarkMemory[icon]     = guid   (authoritative owner of the icon)
--   activeGUIDs[guid]    = icon   (reverse lookup: the icon a guid holds)
--   usedIcons[icon]      = true   (icon is in use)
--   activeMobNames[icon] = name   (display label for the HUD)
--
-- MarkMemory, activeGUIDs and activeMobNames are written ONLY here. usedIcons has
-- exactly two named writers: this Ledger (ownership -- a live mob wears the mark)
-- and TankMark.Reservation.Reserve (reservation -- a human manually claims a slot
-- for a player via /tmark assign or the HUD, pairing usedIcons with
-- sessionAssignments). That reservation concern is deliberately kept out of the
-- Ledger and lives in its own seam beside it.
--
-- The Ledger is the SOLE writer of these tables; existing code still reads them
-- directly (read-migration is a later pass). It is pure: no WoW API, no UI. The
-- live mark-unit busy check, HUD refresh, sessionAssignments, and mob-priority
-- resolution stay in callers. The interface is the test surface.

if not TankMark then return end

local L = TankMark.Locals

-- Backing indices stay public on TankMark so existing direct reads keep working.
TankMark.MarkMemory     = TankMark.MarkMemory     or {}
TankMark.usedIcons      = TankMark.usedIcons      or {}
TankMark.activeGUIDs    = TankMark.activeGUIDs    or {}
TankMark.activeMobNames = TankMark.activeMobNames or {}

TankMark.Ledger = {}
local Ledger = TankMark.Ledger

-- Record that `guid` (named `name`) holds `icon`, updating every index. If a
-- different guid previously held the icon, that prior owner's reverse lookup is
-- cleared so it is re-processed as unmarked next cycle (mark-theft handling).
function Ledger.Assign(icon, guid, name)
    if not icon or not guid then return end

    local prevOwner = TankMark.MarkMemory[icon]
    if prevOwner and prevOwner ~= guid and TankMark.activeGUIDs[prevOwner] == icon then
        TankMark.activeGUIDs[prevOwner] = nil
    end

    TankMark.MarkMemory[icon]     = guid
    TankMark.activeGUIDs[guid]    = icon
    TankMark.usedIcons[icon]      = true
    TankMark.activeMobNames[icon] = name
end

-- Re-affirm that `icon` is owned by `guid` without disturbing the HUD label or
-- other indices. The scanner calls this for marks whose holder is still visible,
-- rebuilding MarkMemory after a combat-end flush. The reverse index is already
-- set (the caller read `icon` from activeGUIDs[guid]).
function Ledger.Reaffirm(icon, guid)
    if icon and guid then
        TankMark.MarkMemory[icon] = guid
    end
end

-- Release `icon`'s ownership. When `owner` is given and a *different* guid now
-- holds the icon, the icon-level state is preserved -- a reassignment was
-- committed earlier in the same event tick and must not be clobbered (the
-- v0.26 duplicate-event guard). The released guid's reverse lookup is always
-- dropped; when `owner` is nil the icon is cleared and any reverse entry
-- pointing at it is swept. Returns true if the icon state was cleared.
function Ledger.Release(icon, owner)
    if not icon then return false end

    local memGUID = TankMark.MarkMemory[icon]
    local pending = owner and memGUID and (memGUID ~= owner)

    if not pending then
        TankMark.MarkMemory[icon]     = nil
        TankMark.usedIcons[icon]      = nil
        TankMark.activeMobNames[icon] = nil
    end

    if owner then
        if TankMark.activeGUIDs[owner] == icon then
            TankMark.activeGUIDs[owner] = nil
        end
    else
        for g, i in L._pairs(TankMark.activeGUIDs) do
            if i == icon then TankMark.activeGUIDs[g] = nil end
        end
    end

    return not pending
end

-- Drop `guid`'s hold entirely. Clears its reverse lookup, and if it still owns
-- an icon in MarkMemory, clears that icon's state too. Used when a recorded mob
-- turns out to be unmarked in-game (stale record / external mark removal).
function Ledger.Evict(guid)
    if not guid then return end

    local icon = TankMark.activeGUIDs[guid]
    TankMark.activeGUIDs[guid] = nil

    if icon and TankMark.MarkMemory[icon] == guid then
        TankMark.MarkMemory[icon]     = nil
        TankMark.usedIcons[icon]      = nil
        TankMark.activeMobNames[icon] = nil
    end
end

-- ===== Read accessors =====================================================
-- New code reads ownership through these (existing direct reads migrate to them).

-- Raw MarkMemory entry, no fallback. This is the skull duplicate-event guard's
-- predicate ("a reassignment was committed this tick"); do NOT swap it for
-- OwnerOf, whose fallback scan would also match a pre-existing holder.
function Ledger.MemoryOwner(icon)
    if not icon then return nil end
    return TankMark.MarkMemory[icon]
end

-- The guid holding `icon`. Prefers MarkMemory; falls back to the reverse index
-- for the combat-end window where FlushMemory wiped MarkMemory but activeGUIDs
-- still holds the mark until the scanner re-affirms it.
function Ledger.OwnerOf(icon)
    if not icon then return nil end
    local g = TankMark.MarkMemory[icon]
    if g then return g end
    for guid, i in L._pairs(TankMark.activeGUIDs) do
        if i == icon then return guid end
    end
    return nil
end

-- The icon `guid` currently holds (reverse lookup).
function Ledger.IconOf(guid)
    if not guid then return nil end
    return TankMark.activeGUIDs[guid]
end

-- The recorded mob name for `icon` (HUD label).
function Ledger.NameFor(icon)
    if not icon then return nil end
    return TankMark.activeMobNames[icon]
end

-- Whether `icon` is flagged in use (ownership or reservation).
function Ledger.IsUsed(icon)
    if not icon then return false end
    return TankMark.usedIcons[icon] and true or false
end

-- The icon currently labelled with `name` (reverse name lookup, used on death).
function Ledger.IconForName(name)
    if not name then return nil end
    for icon, n in L._pairs(TankMark.activeMobNames) do
        if n == name then return icon end
    end
    return nil
end

-- Combat-end flush. PLAYER_REGEN_ENABLED also fires when the addon-holder DIES
-- (death drops you out of combat), so this must NOT wipe the marks: it clears
-- only MarkMemory (the live-owner map) and keeps usedIcons / activeGUIDs /
-- activeMobNames, so the HUD and icon reservations survive your death. OwnerOf's
-- activeGUIDs fallback answers ownership while MarkMemory is empty (you are dead,
-- so the scanner cannot re-affirm). Deliberately PARTIAL -- do not "reconcile" it
-- into a full clear, and do not remove the OwnerOf fallback.
function Ledger.FlushMemory()
    for k in L._pairs(TankMark.MarkMemory) do TankMark.MarkMemory[k] = nil end
end

-- Wipe every index (session reset). Clears in place so table identities stay
-- stable for any code holding a reference.
function Ledger.Clear()
    for k in L._pairs(TankMark.MarkMemory)     do TankMark.MarkMemory[k]     = nil end
    for k in L._pairs(TankMark.usedIcons)      do TankMark.usedIcons[k]      = nil end
    for k in L._pairs(TankMark.activeGUIDs)    do TankMark.activeGUIDs[k]    = nil end
    for k in L._pairs(TankMark.activeMobNames) do TankMark.activeMobNames[k] = nil end
end
