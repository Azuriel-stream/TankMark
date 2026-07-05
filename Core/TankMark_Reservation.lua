-- The Reservation seam: the single writer of manual mark-slot reservations.
--
-- A "reservation" is a human manually claiming a mark slot for a player (via
-- /tmark assign or the HUD) ahead of -- or independent of -- any mob wearing it.
-- It is distinct from OWNERSHIP (a live mob physically wears the mark, recorded
-- by the Ledger) and from ASSIGNMENT (the Team Profile projected onto the
-- session, i.e. sessionAssignments). Reservation is the one operation that
-- touches both worlds at once: it flags the icon occupied (usedIcons) so the
-- auto-marker won't hand that icon to another mob, AND binds the responsible
-- player (sessionAssignments).
--
-- This is the seam the Ledger deliberately disclaims -- its header notes usedIcons
-- "is also set true by the assignment/reservation paths ... [which] stays in those
-- callers." That scattered write now lives here, so usedIcons has exactly two
-- named writers: the Ledger (ownership) and this module (reservation). Pure: no
-- WoW API, no UI (callers keep their own HUD refresh / print).

if not TankMark then return end

local L = TankMark.Locals

TankMark.Reservation = {}
local Reservation = TankMark.Reservation

-- [v0.31] Reserve `icon` for `player`: occupy the slot and bind the player in one
-- write. Both indices must already exist (created at load by Session.lua).
function Reservation.Reserve(icon, player)
    if not icon or not player then return end
    TankMark.usedIcons[icon]         = true
    TankMark.sessionAssignments[icon] = player
end
