-- The group health monitor's checks: Sku's rule (speak a member when their
-- health moved the role's minimum change and minimum pitch steps since
-- their last announcement) on health the addon cannot read. No WoW API in here: the caller hands in
-- an environment, so tools/groupHealthSim.lua runs the real checks against
-- a simulated engine.
--
-- Speak first, check afterwards. The member's reference (the health of
-- their last announcement) is a plain number once known, so the rule is a
-- volume gate: a health event speaks the number at once, silent inside
-- reference -/+ minimum change (widened to the pitch levels within the
-- minimum pitch steps), and the game decides whether it is heard.
-- A silent readback sample (readback.lua) called in the same frame reads
-- the same health and tells afterwards whether the number was a move; then
-- the reference moves to it.
--
-- Per member: out (checks the readback still has), again (a health event
-- came while two were out: check once more when one is back), lost (the
-- plan of a check whose sample was lost: its number may have been heard,
-- so the next check is a silent re-check with that plan), rechecking.

local GroupHealth = WowVision.groupHealth

-- A number cut by a stop of all speech this soon after it went out was not
-- heard to its end: the next check speaks it again (gated afresh, so a
-- member who healed back in the meantime stays silent). At most once in
-- RESPEAK_EVERY_MS per member: someone pressing Ctrl again and again must
-- not turn one move into a burst of repeats.
local RESPEAK_MS = 400
local RESPEAK_EVERY_MS = 2000

-- Who is read first when several wait for the slot line (lower first): a
-- member below their urgent threshold, then tanks, then healers, then the
-- lower health; a member without a reference last.
function GroupHealth.readPriority(member, urgentPercent)
    if member == nil or member.reference == nil then
        return 1000
    end
    local score = member.reference
    if urgentPercent ~= nil and member.reference < urgentPercent then
        score = score - 200
    end
    if member.role == "TANK" then
        score = score - 30
    elseif member.role == "HEALER" then
        score = score - 15
    end
    return score
end

local Checks = WowVision.Class("GroupHealthChecks")
GroupHealth.Checks = Checks

-- env:
-- - members() the watched members by unit; memberFor(unit) a member by
--   any unit token naming them (nil when not watched);
-- - threshold(member) the role's minimum change, whole percent;
--   pitchQuiet(member) (optional) the band of health that sounds less than
--   the role's minimum pitch steps from the member's reference;
--   urgent(member) the role's urgent threshold, percent;
-- - carry(member, quiet) speaks the member's number straight to the engine,
--   silent inside `quiet` ({ low, high } health), and returns how many
--   utterances it made;
-- - for the readback (readback.lua): now, after, speak, through,
--   nextCount, onOwnCut, onFailing, onError and optionally line;
-- - trace(member, what, detail) (optional): diagnostics, see log.lua.
function Checks:initialize(env)
    self.env = env
    self.readback = GroupHealth.Readback:new({
        line = env.line,
        now = env.now,
        after = env.after,
        speak = env.speak,
        through = env.through,
        nextCount = env.nextCount,
        onOwnCut = env.onOwnCut,
        onFailing = env.onFailing,
        onError = env.onError,
        plan = function(unit)
            local member = env.memberFor(unit)
            if member == nil then
                return GroupHealth.locatePlan()
            end
            return GroupHealth.planFor(member, env.threshold(member), env.pitchQuiet ~= nil and env.pitchQuiet(member) or nil)
        end,
        priority = function(unit)
            local member = env.memberFor(unit)
            return GroupHealth.readPriority(member, member ~= nil and env.urgent(member) or nil)
        end,
        rerequest = function(unit)
            self:check(unit)
        end,
        onReading = function(unit, reading)
            self:onReading(unit, reading)
        end,
        onDiscard = function(unit, why, sample)
            self:onDiscard(unit, why, sample)
        end,
        onPurge = function()
            self:onPurge()
        end,
    })
end

function Checks:trace(member, what, detail)
    if self.env.trace ~= nil then
        self.env.trace(member, what, detail)
    end
end

-- One silent sample for every member whose reference is not known yet, or
-- still being narrowed down: someone who joined, or everyone after a purge.
function Checks:readNew()
    for _, member in pairs(self.env.members()) do
        if not member.dead and (member.reference == nil or member.locate) and (member.out or 0) == 0 then
            self.readback:request(member.unit)
        end
    end
end

-- A check of the member goes out: `opts` as readback:request takes them.
function Checks:send(member, opts)
    member.out = (member.out or 0) + 1
    if opts.recheck then
        member.rechecking = true
    end
    if self.readback:request(member.unit, opts) then
        return true
    end
    -- Two samples of the member out already: the readback asks again
    -- (rerequest) when one is back.
    member.out = member.out - 1
    if opts.recheck then
        member.rechecking = false
    end
    return false
end

-- A health event, or the readback asking for the member again. A member
-- without a reference gets a plain silent sample (the first reading sets
-- it). Otherwise the number goes out now, carried by a sample. While the
-- member's last check is still out, a second one may go out beside it
-- when the slot line is free (nobody else waiting): gated by the same
-- reference it may repeat the first, but a member taking hit after hit is
-- heard at once. Else it waits for the check and goes out with the health
-- of that moment.
function Checks:check(unit)
    local member = self.env.memberFor(unit)
    if member == nil or member.dead then
        return
    end
    if member.reference == nil then
        self.readback:request(member.unit)
        return
    end
    local out = member.out or 0
    if member.lost ~= nil then
        if out >= 2 then
            member.again = true
            self:trace(member, "wait", "two checks out")
            return
        end
        local plan = member.lost
        member.lost = nil
        if not self:send(member, { plan = plan, recheck = true }) then
            member.lost = plan
        end
        return
    end
    if out >= 2 or (out == 1 and (member.rechecking or not self.readback:lineFree())) then
        member.again = true
        self:trace(member, "wait", (out >= 2 and "two checks out")
            or (member.rechecking and "a re-check was out")
            or "its last check was out and the line busy")
        return
    end
    self:send(member, {
        carry = function(plan)
            if self.env.memberFor(member.unit) ~= member or member.dead then
                return 0
            end
            self:trace(member, "sent")
            return self.env.carry(member, GroupHealth.quietFor(plan))
        end,
    })
end

-- A check is back (read or lost).
local function checkBack(member, recheck)
    member.out = math.max(0, (member.out or 1) - 1)
    if recheck then
        member.rechecking = false
    end
end

-- Returns true when the reading found a carried number was a move.
function Checks:onReading(unit, reading)
    local member = self.env.memberFor(unit)
    if member == nil or member.dead then
        return false
    end
    local moved = GroupHealth.judge(member, reading, self.env.threshold(member))
    if reading.carried then
        checkBack(member, reading.recheck)
        if moved then
            self:trace(member, "moved", reading.recheck)
        end
    end
    if (member.out or 0) == 0 then
        -- Not located yet: zoom in now, not at the next event.
        if member.locate then
            self.readback:request(member.unit)
        end
        if member.again then
            member.again = false
            self:check(member.unit)
        end
    end
    return moved
end

-- A sample that carried a number was lost: whether the number was heard is
-- not known. The next check is a silent re-check with the same plan, which
-- moves the reference if it was. Only a number a stop cut right after it
-- went out goes out again (RESPEAK_MS). The readback asks for the member
-- again by itself after a disturbance (readbackRetries, a stop).
function Checks:onDiscard(unit, why, sample)
    if not sample.carried then
        return
    end
    local member = self.env.memberFor(unit)
    if member == nil then
        return
    end
    checkBack(member, sample.recheck)
    self:trace(member, "lost", { why = why, recheck = sample.recheck })
    local now = self.readback.env.now()
    if not sample.recheck and why == "stop" and now - sample.calledMs < RESPEAK_MS
        and now - (member.lastRespeakMs or -math.huge) > RESPEAK_EVERY_MS then
        member.lastRespeakMs = now
        self:trace(member, "respeak")
    else
        member.lost = sample.plan
    end
    if not GroupHealth.readbackRetries(why) and why ~= "stop" and member.again then
        member.again = false
        self:check(member.unit)
    end
end

-- The readback dropped everything (a member stuck failing): every check is
-- gone, and who is not located yet is read again.
function Checks:onPurge()
    for _, member in pairs(self.env.members()) do
        member.out = 0
        member.again = false
        member.lost = nil
        member.rechecking = false
    end
    self:readNew()
end
