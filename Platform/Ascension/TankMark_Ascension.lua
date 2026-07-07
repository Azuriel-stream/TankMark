-- Ascension (WotLK 3.3.5) platform overlay. [v0.32] (ADR 0003 / 0004)
--
-- Loaded ONLY by TankMark-wrath.toc (the 30300 package). The file ships to both
-- client folders, but the Vanilla TankMark.toc never references it, so it is inert
-- on Vanilla -- the package-per-target "gate via toc reference, not file exclusion"
-- rule (slice B's deferred file-list question, answered here). This is the home for
-- genuinely 3.3.5-specific code: the platform capability declarations, the UI-API
-- compat shims, and the ONE platform primitive slice C needs -- the identity read
-- (Platform.GUID -> native UnitGUID). The two-sweep engine itself is capability-gated
-- BEHAVIOR and lives in shared Core (Batch.lua / the mouseover dispatch), gated on
-- hasScanner -- per ADR 0003, only genuinely platform-specific code forks here.

if not TankMark then return end
if not TankMark.Platform then return end

local L = TankMark.Locals

-- Declare the platform capabilities (ADR 0004):
--   hasScanner=false      -- no passive nameplate scanner, so the batch is the sole
--                            marker and runs the two-sweep (not the in-combat skip).
--   requiresSuperWoW=false -- Ascension marks via the two-sweep live-token path, not
--                            SuperWoW, so CanAutomate's SuperWoW gate is lifted here
--                            (every OTHER gate -- active/permissions/zone-profile --
--                            still applies; and Ascension lacks SuperWoW anyway).
TankMark.Platform.Register({ name = "Ascension", caps = { hasScanner = false, requiresSuperWoW = false } })

-- Identity primitive override [v0.32] (slice C). SuperWoW's 2-return UnitExists (the
-- Core default) does not exist on stock 3.3.5; Ascension reads a unit's GUID via the
-- native UnitGUID. Driver_GetGUID delegates here, so the batch collector -- and the
-- flight recorder -- get a working GUID on Ascension. This is the sole documented
-- exception to ADR 0003's GUID-in rule expressed as a primitive: it READS a live
-- token. (Apply needs no override -- the default SetMark already accepts a token.)
TankMark.Platform.GUID = function(unit)
    return L._UnitGUID(unit)
end

-- === UIDropDownMenu compat: 1.12 -> 3.3.5 argument-order shims =================
-- The shared UI was written for Vanilla 1.12, where several UIDropDownMenu setters
-- take (value, frame). On 3.3.5 they were reordered to frame-first. Rather than
-- churn the shared UI (and risk the Vanilla build), wrap the Blizzard globals to
-- normalize by TYPE and forward in 3.3.5 order. Type-dispatch (frame is a table;
-- width/text is a number/string) makes the shim SAFE for BOTH our 1.12-order calls
-- AND native 3.3.5 callers (Blizzard, ElvUI, ...), so overriding the global is
-- collateral-free. Each shim is added only once its reorder is CONFIRMED in-game --
-- never speculatively, since a wrong global override would break other addons.

-- SetWidth: 1.12 (width, frame) -> 3.3.5 (frame, width [, padding]).  [CONFIRMED:
-- UIDropDownMenu.lua indexed arg #1 as the frame and got our numeric width.]
do
    local native = UIDropDownMenu_SetWidth
    if native then
        function UIDropDownMenu_SetWidth(a, b, c)
            if L._type(a) == "number" then a, b = b, a end   -- -> (frame, width)
            return native(a, b, c)
        end
    end
end

-- SetText: 1.12 (text, frame) -> 3.3.5 (frame, text).  [CONFIRMED: SetText called
-- frame:GetName() on our string "Durotar", so arg #1 is the frame.]
do
    local native = UIDropDownMenu_SetText
    if native then
        function UIDropDownMenu_SetText(a, b)
            if L._type(a) == "string" then a, b = b, a end   -- -> (frame, text)
            return native(a, b)
        end
    end
end
