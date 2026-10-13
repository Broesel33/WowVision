-- Health readback for the group health monitor: which band of health a
-- member is in, learned from how long silent utterances play. A sighted
-- healer sees how far a bar moved at one look; the monitor uses this only
-- to decide WHEN to speak (the member's health moved far enough since the
-- last announcement, Sku's rule). WHAT it speaks still comes from the
-- secret health through the curves, so a misread costs one extra or one
-- missing announcement, never a wrong number. Only official API: curves of
-- ours, C_VoiceChat speech at volume 0, its playback events and
-- debugprofilestop().
--
-- How (measured on WoW: Forever 1.60.1, 2026-10-13, with a developer probe):
-- UnitHealthPercent(unit, true, curve) turns the health into a silence
-- length, 'a<silence msec="..."/>' is spoken at volume 0 and rate 10, and the
-- time from PLAYBACK_STARTED to PLAYBACK_FINISHED gives the length back:
-- - 74 clean samples over five runs lie on one line, played = 190 ms +
--   0.3314 * silence (rate 10 shortens the silence too); on the lengths used
--   here every sample was within 0.27 of a level. Fixed values, no
--   calibration; two more machines' headsets and speakers timed the same.
--   Offline (SAPI to a file, 2026-10-13) Hedda, Katja, Stefan and Zira all
--   shorten silence to exactly a third at rate 10, their "a" within 16 ms
--   of Hedda's; the simulation keeps reading up to about 20 ms off.
-- - msec="0" plays longer than 100 ms of silence, so level 0 is 100 ms.
-- - Events land on frames (about 17 ms at 60 fps), so a level is 300 ms of
--   silence, about 100 ms played.
-- - With the game in the background (alt-tab), every utterance plays 461
--   to 463 ms whatever its length, and starts about 71 ms after the call
--   (three probe runs, 2026-10-13; back in front the timing is right again
--   at once). 462 ms lies 0.40 from level 2, inside MAX_OFF_LEVEL: two
--   digits both in BACKGROUND_MS are thrown away. Laptop speakers and two
--   headsets timed the same in front.
-- - Volume 0 plays in real time; a secret works inside <silence msec>; ten
--   silent utterances side by side keep their timing.
-- - Other speech beside ours does no harm. A stop of all speech
--   (C_VoiceChat.StopSpeakingText, which takes no arguments: nobody can stop
--   only their own speech) cuts every utterance short, and so may speech
--   that interrupts: such samples are thrown away.
--
-- A sample is TWO utterances called in the same frame (so both read the
-- same health), each a digit as a level of silence. What the digits mean
-- is the sample's PLAN: the health split into bands, each band a value,
-- the value written in the plan's base. The events carry only an utterance
-- id; ids count up in call order, so the lower id is the first digit
-- (checked in game).
-- - change plan (the monitor): bands around the member's reference, the
--   health at their last announcement. The middle band is "moved less than
--   the threshold", its edges exactly reference -/+ threshold, widened to
--   the pitch levels within the minimum pitch steps (the game evaluates
--   the curve, so the edge is exact); seven bands on each side,
--   the nearest a quarter threshold wide, the farther wider, the last open;
--   full health is a band of its own. Base 4, the likeliest answers on the
--   shortest silences: "moved less" plays about 0.22 seconds, the nearest
--   moves about 0.32, the farthest about 0.52.
-- - zoom plan: a band of health (whole percent) in equal parts, plus one
--   band below and one above when there is room, base 4. Finds the
--   reference at the start (zooming into 0 to 100) and after a jump past
--   the outer bands (zooming into the open band read): one zoom splits 100
--   percent into about 6 percent parts, a second into parts below half a
--   percent. It never announces by itself. The default of a readback
--   without plans of its own: zooming into 0 to 100.
--
-- Every engine call of ours goes through one slot line (SLOT_MS apart, or
-- longer for a slot with more utterances: the engine prepares one after
-- another, so a slot is as long as its utterances need and we never pile
-- up a queue in front of other speech), so the starts of different slots
-- never share a window. Requests wait in a queue; when the line is free up
-- to BATCH_MAX members go out in one slot, the most urgent first (the
-- caller's priority): what they carry first, then each member's two
-- digits, all one run of ids. A start beyond what the slot expects, a
-- missing one, or one right after the run that is not the next slot's own
-- makes the slot ambiguous and its samples are thrown away.
--
-- A stop of all speech purges what it cut: every sample out is dropped and
-- its member read again at once, and an announcement of ours cut by the
-- stop is handed back to be spoken again. A member whose samples keep
-- failing for long purges everything, and everyone is read again. The
-- caller hears that the readback fails only when it stays bad: half a
-- minute without any reading, or fewer than one in five of the last 40
-- samples usable.
--
-- No WoW API in here: the caller hands in an environment (clock, timer,
-- speak, the health through a curve), so tools/groupHealthSim.lua runs it
-- against a simulated engine.

local GroupHealth = WowVision.groupHealth

local R = {
    RATE = 10,
    SILENCE_OFFSET = 100,
    LEVEL_SILENCE = 300,
    BASE_MS = 223,
    LEVEL_MS = 99.4,
    -- The window for a slot of two utterances; each more adds ENGINE_MS.
    START_WINDOW_MS = 100,
    -- The engine prepares utterances one after another, about this long
    -- each (flood probe, 2026-10-13: 20, 40, 80 silent utterances in one
    -- frame all played their length, started about 36 ms apart).
    ENGINE_MS = 37,
    -- After a slot's window: a start with the id right after the run in
    -- this time, not the next slot's own, means the run is one longer than
    -- ours (speech called just before ours took the engine, and our last
    -- start fell past the window).
    GRACE_MS = 80,
    -- The engine never starts an utterance sooner after its call.
    FIRST_START_MS = 30,
    -- Members read together in one slot at most (their utterances one run).
    -- Simulated with the engine as measured (three fights each): 3 per slot
    -- follows 88 percent of changes with 10 members under steady damage, 62
    -- with 20, 50 with 40 (one per slot: 57, 24, 11); 4 per slot no more,
    -- but other speech waits longer behind a slot and numbers overlap more.
    BATCH_MAX = 3,
    CUT_WINDOW_MS = 110,
    SLOT_MS = 120,
    GAP_SECONDS = 0.12,
    -- The longest sample (0.52 s digits, a late start) is under a second;
    -- a stopped utterance never reports its end (TextToSpeechFrame.lua),
    -- so this is how long a sample cut without our hook holds its member.
    TIMEOUT_SECONDS = 1.2,
    -- Clean samples land within 0.27 of a whole level; one further off was cut.
    MAX_OFF_LEVEL = 0.42,
    -- What every utterance plays with the game in the background.
    BACKGROUND_MS = { 455, 470 },
    -- An own utterance called this recently may be cut before it started.
    OWN_START_MS = 500,
    -- Own utterances that never reported their end are forgotten after this.
    OWN_FORGET_MS = 10000,
    -- Two quick retries, then one a second: a change must not get lost.
    QUICK_RETRIES = 2,
    RETRY_LATER_SECONDS = 1,
    -- A member whose samples have failed this long: purge and read everyone.
    STUCK_MS = 3000,
    -- No reading at all for this long, over at least FAIL_SAMPLES failed
    -- samples: the caller is told once.
    FAIL_MS = 30000,
    FAIL_SAMPLES = 20,
    -- Or of the last FAIL_WINDOW samples fewer than FAIL_RATIO usable: a
    -- voice that does not fit the fixed values still reads now and then,
    -- wrongly (simulation: 5 to 13 percent usable; heavy speech spam or 15
    -- fps still 28 percent). Said again only after it recovered to RECOVER.
    FAIL_WINDOW = 40,
    FAIL_RATIO = 0.2,
    RECOVER_RATIO = 0.5,
}
GroupHealth.readbackConstants = R

-- Plans --------------------------------------------------------------------------

local EPS = 1e-9

-- A plan from its points ({ lower edge as a fraction, value }, rising): the
-- band of each value and the two digit curves.
local function newPlan(kind, base, points, extra)
    local plan = { kind = kind, base = base, points = points, intervals = {} }
    local digits = { {}, {} }
    for i, point in ipairs(points) do
        local nextPoint = points[i + 1]
        plan.intervals[point[2]] = { point[1], nextPoint ~= nil and nextPoint[1] or 1 }
        local high, low = math.floor(point[2] / base), point[2] % base
        tinsert(digits[1], { point[1], R.SILENCE_OFFSET + high * R.LEVEL_SILENCE })
        tinsert(digits[2], { point[1], R.SILENCE_OFFSET + low * R.LEVEL_SILENCE })
    end
    plan.digitPoints = digits
    for key, value in pairs(extra or {}) do
        plan[key] = value
    end
    return plan
end

-- A plan of the caller's own (kind, base, points as newPlan takes them).
GroupHealth.readbackPlan = newPlan

-- Plans are kept for reuse (and with them the game's curve objects, see
-- module.lua). A simulated two hours of raid fighting made about 300 change
-- plans and 1200 zoom plans, the zoom plans still growing; past
-- PLANS_MAX a cache starts afresh (samples out keep their plan).
local PLANS_MAX = 512

local function newCache()
    return { plans = {}, count = 0 }
end

local function cached(cache, key)
    return cache.plans[key]
end

local function keep(cache, key, plan)
    if cache.count >= PLANS_MAX then
        cache.plans, cache.count = {}, 0
    end
    cache.plans[key] = plan
    cache.count = cache.count + 1
    return plan
end

local changePlans = newCache()

-- The band from `lo` to `hi` percent in equal parts (16 less one for each
-- band outside it: below `lo` when lo > 0, above `hi` when hi < 100; at
-- 100 the top part includes full health). Edges round outward to whole
-- percent, so the plans (and the game's curve objects) stay few.
local zoomPlans = newCache()

function GroupHealth.zoomPlan(lo, hi)
    lo, hi = math.max(0, math.floor(lo + EPS)), math.min(100, math.ceil(hi - EPS))
    if hi <= lo then
        hi = math.min(100, lo + 1)
        lo = hi - 1
    end
    local key = lo .. ":" .. hi
    local plan = cached(zoomPlans, key)
    if plan ~= nil then
        return plan
    end
    local parts = 16 - (lo > 0 and 1 or 0) - (hi < 100 and 1 or 0)
    local points = {}
    if lo > 0 then
        tinsert(points, { 0, #points })
    end
    for k = 0, parts - 1 do
        tinsert(points, { (lo + k * (hi - lo) / parts) / 100, #points })
    end
    if hi < 100 then
        tinsert(points, { hi / 100, #points })
    end
    -- band: what the plan's inner parts cover; at 100 it takes in full
    -- health (the top part is closed), hence just past 1.
    plan = newPlan("zoom", 4, points, { band = { lo / 100, hi < 100 and hi / 100 or 1.01 } })
    return keep(zoomPlans, key, plan)
end

-- The first zoom of a member without a reference.
function GroupHealth.locatePlan()
    return GroupHealth.zoomPlan(0, 100)
end

-- The plan of a member's next sample; `pitchQuiet` (optional) widens the
-- quiet band by the role's minimum pitch steps (GroupHealth.pitchQuiet).
function GroupHealth.planFor(member, threshold, pitchQuiet)
    if member.reference == nil then
        return GroupHealth.locatePlan()
    end
    -- Zooming covers the band and its widening (LOCATE_WIDEN), so a
    -- reading in the zoom's outer bands lies wholly past both. The pitch
    -- steps are left out here: widening the zoom by them made the
    -- reference coarser and slow changes late (simulation, 2026-10-13).
    if member.locate and member.locateBand ~= nil then
        local widen = threshold * GroupHealth.LOCATE_WIDEN
        return GroupHealth.zoomPlan(member.locateBand[1] * 100 - widen, member.locateBand[2] * 100 + widen)
    end
    return GroupHealth.changePlan(member.reference, threshold, pitchQuiet)
end

-- Values by how long their longer digit plays, shortest first: base 4
-- gives 0; then 1, 4, 5; then 2, 6, 8, 9, 10; then the rest.
local function valuesByLength(base)
    local list = {}
    for value = 0, base * base - 1 do
        tinsert(list, value)
    end
    local function longer(value)
        return math.max(math.floor(value / base), value % base)
    end
    table.sort(list, function(x, y)
        if longer(x) ~= longer(y) then
            return longer(x) < longer(y)
        end
        return x < y
    end)
    return list
end

local CHANGE_BASE = 4
-- Bands on each side of the middle; the outermost is open.
local CHANGE_SIDE = 7
-- Their widths in quarter thresholds, nearest first (the seventh is open):
-- precise near the threshold, where slow changes cross it, and reaching
-- 5.25 thresholds out (a tank's 5 percent: 26 percent), so a big hit
-- seldom needs a zoom. Measured in the simulation against equal widths:
-- slow changes announced after 1.00 to 1.08 minimum changes instead of
-- 1.08 to 1.15, hits as fast.
local CHANGE_WIDTHS = { 1, 1, 1, 2, 4, 8 }
local BY_LENGTH = valuesByLength(CHANGE_BASE)

-- Which answers get the shortest silences (lowest rank first; full health
-- is always last). Likeliest first: "moved less", then the nearest moves.
-- (By urgency, the biggest drops first, was right while the number waited
-- for the sample; now the number goes out with it, and the sample's speed
-- only decides when the member's next number may go. Over eight simulated
-- fights both orders came out within 0.05 s of each other.)
GroupHealth.changeRank = {
    middle = 0,
    below = function(k)
        return 2 * k - 1
    end,
    above = function(k)
        return 2 * k
    end,
}

-- The bands around `reference` (whole percent) for a threshold in percent.
-- The middle band, "moved less", is reference -/+ threshold, widened to
-- `pitchQuiet` when given (Sku's two rules, both must pass to announce).
-- Seven bands on each side of it (CHANGE_WIDTHS), the outer ones open;
-- bands outside 0 to 1 drop out. Below a full reference, full health is a
-- band of its own, so a heal to full sets the reference to exactly 100.
-- The answers get their silences by GroupHealth.changeRank.
function GroupHealth.changePlan(reference, threshold, pitchQuiet)
    local r, a = reference / 100, threshold / 100
    local low, high = r - a, r + a
    if pitchQuiet ~= nil then
        low, high = math.min(low, pitchQuiet[1]), math.max(high, pitchQuiet[2])
    end
    local key = reference .. ":" .. threshold .. ":" .. low .. ":" .. high
    local plan = cached(changePlans, key)
    if plan ~= nil then
        return plan
    end
    local w = a / 4
    -- Rising: { lower edge, rank } (GroupHealth.changeRank; full health last).
    -- far[k]: how far band k's outer edge lies past the threshold, in w.
    local far = {}
    local reach = 0
    for k = 1, CHANGE_SIDE - 1 do
        reach = reach + CHANGE_WIDTHS[k]
        far[k] = reach
    end
    local bands = {}
    for k = CHANGE_SIDE, 1, -1 do
        tinsert(bands, { k == CHANGE_SIDE and -math.huge or low - far[k] * w, GroupHealth.changeRank.below(k) })
    end
    tinsert(bands, { low, GroupHealth.changeRank.middle })
    for k = 1, CHANGE_SIDE do
        tinsert(bands, { high + (k == 1 and 0 or far[k - 1]) * w, GroupHealth.changeRank.above(k) })
    end
    local kept = { { 0, bands[1][2] } }
    for i = 2, #bands do
        local x = bands[i][1]
        if x <= 0 then
            kept[#kept] = { 0, bands[i][2] }
        elseif x <= 1 then
            tinsert(kept, { x, bands[i][2] })
        end
    end
    if reference < 100 and kept[#kept][1] < 1 then
        tinsert(kept, { 1, 2 * CHANGE_SIDE + 1 })
    end
    -- Values by rank: the lowest ranks the shortest silences.
    local ranks = {}
    for _, point in ipairs(kept) do
        tinsert(ranks, point[2])
    end
    table.sort(ranks)
    local valueOf = {}
    for i, rank in ipairs(ranks) do
        valueOf[rank] = BY_LENGTH[i]
    end
    local points = {}
    for _, point in ipairs(kept) do
        tinsert(points, { point[1], valueOf[point[2]] })
    end
    -- quiet: the middle band itself, "moved less": exactly what the caller's
    -- volume gate keeps silent.
    plan = newPlan("change", CHANGE_BASE, points, { reference = reference, threshold = threshold, quiet = { low, high } })
    return keep(changePlans, key, plan)
end

-- Decoding -----------------------------------------------------------------------

-- A level as a fraction: played time back through the fixed line.
function GroupHealth.readbackRaw(playedMs)
    return (playedMs - R.BASE_MS) / R.LEVEL_MS
end

-- The plan's value from the two played times; nil and the reason when they
-- make none.
function GroupHealth.readbackValue(plan, firstMs, secondMs)
    local rawHigh, rawLow = GroupHealth.readbackRaw(firstMs), GroupHealth.readbackRaw(secondMs)
    local bg = R.BACKGROUND_MS
    if firstMs >= bg[1] and firstMs <= bg[2] and secondMs >= bg[1] and secondMs <= bg[2] then
        return nil, "game in the background", rawHigh, rawLow
    end
    local high, low = math.floor(rawHigh + 0.5), math.floor(rawLow + 0.5)
    if math.abs(rawHigh - high) > R.MAX_OFF_LEVEL or math.abs(rawLow - low) > R.MAX_OFF_LEVEL then
        return nil, "between levels", rawHigh, rawLow
    end
    if high < 0 or low < 0 or high >= plan.base or low >= plan.base then
        return nil, "out of range", rawHigh, rawLow
    end
    local value = high * plan.base + low
    if plan.intervals[value] == nil then
        return nil, "out of range", rawHigh, rawLow
    end
    return value, nil, rawHigh, rawLow
end

-- The rule ------------------------------------------------------------------------

-- What a reading means for a member: true when the number it carried was
-- heard, moving member.reference (whole percent) to the middle of the band
-- read. Speak first, check afterwards: every move comes with a health
-- event, and every event sends a number, so only a sample that carried one
-- can tell a move. A plain sample (no number) only sets the reference or
-- narrows it down.
-- - No reference yet: it sets the reference.
-- - Carried: heard exactly when the band lies outside the quiet band the
--   number went out behind (quietFor), whatever readings came in between.
-- - A band wider than a quarter threshold (the wider outer bands, a first
--   zoom) leaves the member to be located in it, and the caller asks for a
--   plain zoom sample at once. A zoom reading inside the band, or a narrow
--   plain one, settles the reference quietly or zooms further. A plain
--   reading that sees a move leaves everything be: the move's own event
--   sends its number (moving the reference here would gate that number
--   around the new health, silent).
local function apart(lo, hi, band)
    return hi <= band[1] + EPS or lo >= band[2] - EPS
end

function GroupHealth.judge(member, reading, threshold)
    local plan = reading.plan
    local band = plan.intervals[reading.value]
    local lo, hi = band[1], band[2]
    local a = threshold / 100
    local function settle(heard)
        member.reference = math.floor((lo + hi) * 50 + 0.5)
        member.locate = hi - lo > a / 4 + EPS
        member.locateBand = member.locate and band or nil
        return heard
    end
    if member.reference == nil then
        return settle(false)
    end
    if reading.carried then
        if apart(lo, hi, GroupHealth.quietFor(plan)) then
            return settle(true)
        end
        if plan.kind == "zoom" and member.locate then
            return settle(false)
        end
        return false
    end
    if member.locate and plan.kind == "zoom" and member.locateBand ~= nil then
        local widen = a * GroupHealth.LOCATE_WIDEN
        local locateBand = member.locateBand
        if not apart(lo, hi, { locateBand[1] - widen, locateBand[2] + widen }) then
            return settle(false)
        end
    end
    return false
end

-- The band a number carried by a sample of this plan stays silent in: the
-- change plan's middle band, or a zoom plan's whole inner band (planFor
-- builds it over the band being located in, widened by LOCATE_WIDEN). From
-- the plan alone, so the gate and judge always agree.
function GroupHealth.quietFor(plan)
    return plan.quiet or plan.band
end

-- How far past the band being located in a move must go to count, in
-- thresholds. The last announcement lies somewhere in the band; a full
-- threshold would be Sku's rule exactly but swallows real moves while
-- zooming in, none lets small moves through as repeats. Eight simulated
-- fights each: none, 23 percent of heard numbers repeats, 179 of 192
-- changes followed; half, 8 to 11 percent, 166; full, 10 percent, 158.
GroupHealth.LOCATE_WIDEN = 0.5

-- One slot line for every readback in the addon: two lines calling in the
-- same frame put both starts into each other's windows (seen in game: two
-- readbacks woken by the same health event lost 63 of 68 samples).
-- The line also records every start once, centrally: which slot's window it
-- fell into and as which start of that slot. Only as many starts as the slot
-- expects can be its own (two for a sample, one for the caller's speech);
-- any later one is foreign, whichever readback owns the slot.
function GroupHealth.newReadbackLine()
    return { nextSlotMs = 0, slots = {}, starts = {}, byId = {} }
end
GroupHealth.readbackLine = GroupHealth.newReadbackLine()

local Readback = WowVision.Class("GroupHealthReadback")
GroupHealth.Readback = Readback

-- env: now() in ms; after(seconds, fn); speak(text) speaks at volume 0 and
-- R.RATE; through(unit, points, digit) the unit's health through a step
-- curve of those points (may be secret, nil when the game refuses the
-- unit); nextCount() a counter that never repeats, not even after a /reload;
-- onReading(unit, reading) with { value, plan, calledMs, rawHigh, rawLow,
-- playedHigh, playedLow, carried (the sample carried speech of the
-- caller's, see request), recheck }. Optional: plan(unit) the plan of the
-- unit's next sample (default locatePlan); priority(unit) who goes first
-- when several wait (lower first); rerequest(unit)
-- when the readback wants the unit read again (a retry, a stop, a health
-- event while two samples were out; default a plain request);
-- onDiscard(unit, why, sample); onPurge(why) after a purge, to read
-- everyone again; onOwnCut(tag) for an own utterance cut by a stop;
-- onFailing() once when the readback fails for long; onError(err) for an
-- error in the caller's carry (the sample goes on); line, a slot line of
-- its own (the simulation; the addon's readbacks all share
-- GroupHealth.readbackLine).
function Readback:initialize(env)
    self.env = env
    self.line = env.line or GroupHealth.readbackLine
    self.units = {}
    self.queue = {}
    self.queueSeq = 0
    self.inflight = {}
    self.own = {}
    self.generation = 0
    self.lastReadingMs = env.now()
    self.lastPurgeMs = -math.huge
    self.failedSamples = 0
    self.recent = {}
    -- Counts for the log and the simulation's report.
    self.stats = { samples = 0, readings = 0, discarded = {}, maxInflight = 0, purges = {}, ownCut = 0 }
end

-- Runs fn(slot) (engine calls) in the next free slot of the shared line;
-- `expect` is how many starts the calls make.
-- How long the starts of a slot of `count` utterances may take: the first
-- 34 to 56 ms after the call, each further one about ENGINE_MS later.
function GroupHealth.readbackWindow(count)
    return R.START_WINDOW_MS + math.max(0, count - 2) * R.ENGINE_MS
end

function Readback:inSlot(expect, fn)
    local line = self.line
    local now = self.env.now()
    local at = math.max(now, line.nextSlotMs)
    local window = GroupHealth.readbackWindow(expect)
    line.nextSlotMs = at + math.max(R.SLOT_MS, window + R.SLOT_MS - R.START_WINDOW_MS)
    local function run()
        local slot = { t = self.env.now(), starts = 0, expect = expect, window = window }
        tinsert(line.slots, slot)
        while #line.slots > 32 do
            tremove(line.slots, 1)
        end
        fn(slot)
    end
    if at <= now then
        run()
    else
        self.env.after((at - now) / 1000, run)
    end
end

-- Speech of the caller's own (the monitor's announcements): in a slot, so
-- its start never falls into a sample's window, and is known as ours. The
-- tag comes back through onOwnCut when a stop cuts it.
function Readback:speakOwn(fn, tag)
    self:inSlot(1, function(slot)
        local now = self.env.now()
        for i = #self.own, 1, -1 do
            if now - self.own[i].calledMs > R.OWN_FORGET_MS then
                tremove(self.own, i)
            end
        end
        local own = { tag = tag, calledMs = now, owner = self }
        slot.own = own
        tinsert(self.own, own)
        fn()
    end)
end

-- Samples of one unit out at once. A new health event while one is out
-- starts another at once; with MAX_PER_UNIT out, it asks for one more
-- afterwards. A reading older than one already used is dropped.
local MAX_PER_UNIT = 2
-- Up to R.BATCH_MAX members are read together in one slot: their
-- utterances one run (the engine prepares one after another, so a slot's
-- fixed wait, the first start's 34 to 56 ms and the window's end, is shared
-- by all of them).

-- Read the unit soon; false when two samples are out already (it asks
-- again through rerequest when one is back). The request waits in a queue
-- until the line is free; then up to BATCH_MAX members go out together,
-- the most urgent first (env.priority). opts (optional): plan, the plan to
-- use instead of env.plan's; recheck, a silent sample judged like a carried
-- one (it stands in for one that was lost); carry(plan), called in the same
-- frame as the digits and before them, speaks the caller's own utterances
-- (which then read the same health as the sample) and returns how many.
function Readback:request(unit, opts)
    local state = self.units[unit]
    if state == nil then
        state = { out = 0, usedMs = -math.huge }
        self.units[unit] = state
    end
    if state.out >= MAX_PER_UNIT then
        state.again = true
        return false
    end
    state.out = state.out + 1
    self.queueSeq = self.queueSeq + 1
    tinsert(self.queue, { unit = unit, opts = opts, seq = self.queueSeq, generation = self.generation })
    self:schedule()
    return true
end

-- The next batch goes out when the line is free.
function Readback:schedule()
    if self.scheduled or #self.queue == 0 then
        return
    end
    local now = self.env.now()
    local at = self.line.nextSlotMs
    if at <= now then
        self:runBatch()
        return
    end
    self.scheduled = true
    self.env.after((at - now) / 1000, function()
        self.scheduled = false
        self:runBatch()
    end)
end

function Readback:runBatch()
    local now = self.env.now()
    -- Another readback, or own speech, took the line meanwhile.
    if self.line.nextSlotMs > now then
        self:schedule()
        return
    end
    local env = self.env
    local queue = {}
    for _, request in ipairs(self.queue) do
        -- Asked for before a purge: that member is read afresh already.
        if request.generation == self.generation then
            request.priority = env.priority ~= nil and env.priority(request.unit) or 0
            tinsert(queue, request)
        end
    end
    table.sort(queue, function(a, b)
        if a.priority ~= b.priority then
            return a.priority < b.priority
        end
        return a.seq < b.seq
    end)
    local batch, rest, taken = {}, {}, {}
    for _, request in ipairs(queue) do
        if #batch < R.BATCH_MAX and not taken[request.unit] then
            taken[request.unit] = true
            tinsert(batch, request)
        else
            tinsert(rest, request)
        end
    end
    self.queue = rest
    if #batch > 0 then
        self:sampleBatch(batch)
    end
    self:schedule()
end

-- No slot reserved ahead and nobody waiting: a sample asked for now is
-- called at once.
function Readback:lineFree()
    return self.line.nextSlotMs <= self.env.now() and #self.queue == 0
end

-- The readback asks for the unit again: the caller decides how.
function Readback:rerequest(unit)
    if self.env.rerequest ~= nil then
        self.env.rerequest(unit)
    else
        self:request(unit)
    end
end

-- One slot for the batch, all in this frame, so every utterance reads the
-- health of the same moment: first what the callers carry (most urgent
-- member first: a spoken number is heard soonest), then each member's two
-- digits. Their ids are one run counting up by one per call.
function Readback:sampleBatch(batch)
    local env, line = self.env, self.line
    local now = env.now()
    local slot = { t = now, starts = 0, expect = 0, window = R.START_WINDOW_MS, samples = {}, list = {}, finishes = {}, failed = {}, owner = self, carried = 0 }
    local ready = {}
    for _, request in ipairs(batch) do
        local opts = request.opts
        local plan = (opts ~= nil and opts.plan) or (env.plan ~= nil and env.plan(request.unit)) or GroupHealth.locatePlan()
        local m = { unit = request.unit, plan = plan, calledMs = now, owner = self, slot = slot, opts = opts }
        self.stats.samples = self.stats.samples + 1
        local silences = {}
        for digit = 1, 2 do
            local ok, silence = pcall(env.through, request.unit, plan.digitPoints[digit], digit)
            if not ok or silence == nil then
                silences = nil
                break
            end
            silences[digit] = silence
        end
        if silences == nil then
            m.error = "no health"
            self:finish(m)
        else
            m.silences = silences
            -- A re-check: silent, but judged like the lost sample it stands
            -- in for (opts.plan is that sample's plan, so the same quiet band).
            if opts ~= nil and opts.recheck then
                m.carried = true
                m.recheck = true
            end
            tinsert(ready, m)
        end
    end
    if #ready == 0 then
        return
    end
    tinsert(line.slots, slot)
    while #line.slots > 32 do
        tremove(line.slots, 1)
    end
    for _, m in ipairs(ready) do
        local opts = m.opts
        if opts ~= nil and opts.carry ~= nil then
            m.carried = true
            local ok, count = pcall(opts.carry, m.plan)
            if ok and type(count) == "number" then
                slot.carried = slot.carried + count
            elseif not ok and env.onError ~= nil then
                env.onError(count)
            end
        end
    end
    for index, m in ipairs(ready) do
        m.digitIndex = index - 1
        tinsert(slot.samples, m)
        tinsert(self.inflight, m)
        for digit = 1, 2 do
            local ok, err = pcall(env.speak, 'a<silence msec="' .. m.silences[digit] .. '"/>' .. GroupHealth.readbackPad(env.nextCount()))
            if not ok then
                -- A missing call breaks the run: the slot's samples are lost.
                slot.broken = true
                m.error = "speak: " .. tostring(err)
            end
        end
    end
    self.stats.maxInflight = math.max(self.stats.maxInflight, #self.inflight)
    slot.expect = slot.carried + 2 * #ready
    slot.window = GroupHealth.readbackWindow(slot.expect)
    line.nextSlotMs = now + math.max(R.SLOT_MS, slot.window + R.SLOT_MS - R.START_WINDOW_MS)
    -- The run is known once the window and the grace after it are over.
    env.after((slot.window + R.GRACE_MS) / 1000 + 0.001, function()
        self:checkSlot(slot)
    end)
    env.after(R.TIMEOUT_SECONDS + slot.window / 1000, function()
        for _, m in ipairs(slot.samples) do
            if not m.done then
                m.error = m.error or "timeout"
                self:finish(m)
            end
        end
    end)
end

-- Every readback hears every start; the line records it once.
function Readback:startEntry(id)
    local line = self.line
    local entry = line.byId[id]
    if entry ~= nil then
        return entry
    end
    local now = self.env.now()
    entry = { t = now, id = id }
    for i = #line.slots, 1, -1 do
        local slot = line.slots[i]
        if now >= slot.t and now <= slot.t + (slot.window or R.START_WINDOW_MS) then
            slot.starts = slot.starts + 1
            entry.slot = slot
            entry.order = slot.starts
            break
        end
    end
    line.byId[id] = entry
    tinsert(line.starts, entry)
    while #line.starts > 64 do
        line.byId[tremove(line.starts, 1).id] = nil
    end
    return entry
end

function Readback:onStarted(id)
    local entry = self:startEntry(id)
    local slot = entry.slot
    if slot == nil then
        return
    end
    local own = slot.own
    if own ~= nil and own.owner == self and entry.order == 1 then
        own.id = id
        return
    end
    if slot.owner ~= self or slot.samples == nil then
        return
    end
    -- Up to the starts the slot expects are ours; one more makes the whole
    -- slot ambiguous.
    if entry.order <= slot.expect then
        tinsert(slot.list, entry)
    else
        slot.ambiguous = true
    end
end

-- The slot's run once its window and grace are over: exactly as many
-- starts as it made calls, their ids consecutive, and no start with the id
-- right after them. nil before; nil and true (broken) for
-- anything else (a start missing, or a foreign one: the engine was busy,
-- or speech called just before ours started in our window).
function Readback:slotRun(slot)
    if slot.run ~= nil then
        return slot.run
    end
    if self.env.now() < slot.t + slot.window + R.GRACE_MS then
        return nil
    end
    if slot.broken or slot.ambiguous or #slot.list ~= slot.expect or #slot.list < 2 then
        return nil, true
    end
    local sorted = {}
    for _, entry in ipairs(slot.list) do
        tinsert(sorted, entry)
    end
    table.sort(sorted, function(x, y)
        return x.id < y.id
    end)
    if sorted[#sorted].id - sorted[1].id ~= #sorted - 1 then
        return nil, true
    end
    -- The id right after the run started by the end of the grace, and not
    -- as the next slot's own (between the windows, or sooner after that
    -- slot's call than the engine can): the run may be shifted by one
    -- (someone else's utterance at its start, our last one late).
    local after = self.line.byId[sorted[#sorted].id + 1]
    if after ~= nil and after.t <= slot.t + slot.window + R.GRACE_MS then
        local nextSlot = after.slot
        if nextSlot == nil or (nextSlot ~= slot and after.t < nextSlot.t + R.FIRST_START_MS) then
            return nil, true
        end
    end
    slot.run = sorted
    return sorted
end

-- A sample's two digits: in the run after what was carried, two per
-- member in call order.
function Readback:digits(m)
    local run, broken = self:slotRun(m.slot)
    if run == nil then
        return nil, nil, broken
    end
    local at = m.slot.carried + 2 * m.digitIndex
    return run[at + 1], run[at + 2]
end

-- Ends the slot's samples whose digits have both finished (or failed), or
-- all of them when the run is broken.
function Readback:checkSlot(slot)
    for _, m in ipairs(slot.samples) do
        if not m.done then
            local first, second, broken = self:digits(m)
            if broken then
                m.error = m.error or "ambiguous"
                self:finish(m)
            elseif first ~= nil then
                if slot.failed[first.id] or slot.failed[second.id] then
                    m.error = "failed"
                    self:finish(m)
                elseif m.error ~= nil or (slot.finishes[first.id] ~= nil and slot.finishes[second.id] ~= nil) then
                    self:finish(m)
                end
            end
        end
    end
end

-- Did anything foreign start right after `finishMs`? Ours are only the
-- expected starts of a slot that stayed unambiguous, or of a slot of the
-- caller's own speech: an interrupting start can fall into a later slot.
function Readback:interrupted(m, finishMs)
    for _, entry in ipairs(self.line.starts) do
        if entry.t > finishMs and entry.t <= finishMs + R.CUT_WINDOW_MS then
            local slot = entry.slot
            local ours = slot ~= nil and entry.order <= slot.expect and not slot.ambiguous
            if not ours then
                return true
            end
        end
    end
    return false
end

function Readback:onFinished(id, failed)
    for i, own in ipairs(self.own) do
        if own.id == id then
            tremove(self.own, i)
            return
        end
    end
    local entry = self.line.byId[id]
    local slot = entry ~= nil and entry.slot or nil
    if slot == nil or slot.owner ~= self or slot.samples == nil then
        return
    end
    if failed then
        slot.failed[id] = true
    elseif slot.finishes[id] == nil then
        slot.finishes[id] = self.env.now()
    end
    self:checkSlot(slot)
end

-- Drop everything and start afresh; the caller reads everyone again.
function Readback:purge(why)
    self.generation = self.generation + 1
    self.queue = {}
    for _, m in ipairs(self.inflight) do
        m.done = true
    end
    self.inflight = {}
    self.units = {}
    self.lastPurgeMs = self.env.now()
    self.stats.purges[why] = (self.stats.purges[why] or 0) + 1
    if self.env.onPurge ~= nil then
        self.env.onPurge(why)
    end
end

-- Someone stopped all speech: every sample out is cut, and so is our own
-- speech that was playing or about to start (a stopped utterance reports
-- no end). The cut samples are dropped and their members read again at
-- once; samples still waiting for their slot were not called yet, so they
-- keep their turn. Then the cut speech is handed back.
function Readback:onStop()
    local now = self.env.now()
    local cut = {}
    for _, own in ipairs(self.own) do
        if own.id ~= nil or now - own.calledMs < R.OWN_START_MS then
            tinsert(cut, own.tag)
        end
    end
    self.own = {}
    local rewake, seen = {}, {}
    local cutSamples = self.inflight
    self.inflight = {}
    for _, m in ipairs(cutSamples) do
        m.done = true
        self.stats.discarded.stop = (self.stats.discarded.stop or 0) + 1
        local state = self.units[m.unit]
        if state ~= nil then
            state.out = math.max(0, state.out - 1)
        end
        if self.env.onDiscard ~= nil then
            self.env.onDiscard(m.unit, "stop", m)
        end
        if not seen[m.unit] then
            seen[m.unit] = true
            tinsert(rewake, m.unit)
        end
    end
    self.stats.purges.stop = (self.stats.purges.stop or 0) + 1
    for _, unit in ipairs(rewake) do
        self:rerequest(unit)
    end
    for _, tag in ipairs(cut) do
        self.stats.ownCut = self.stats.ownCut + 1
        if self.env.onOwnCut ~= nil then
            self.env.onOwnCut(tag)
        end
    end
end

-- The last samples' outcomes (true: used); tells the caller once when too
-- few were usable.
function Readback:outcome(used)
    local recent = self.recent
    tinsert(recent, used)
    while #recent > R.FAIL_WINDOW do
        tremove(recent, 1)
    end
    if #recent < R.FAIL_WINDOW then
        return
    end
    local count = 0
    for _, ok in ipairs(recent) do
        if ok then
            count = count + 1
        end
    end
    local ratio = count / #recent
    if ratio >= R.RECOVER_RATIO then
        self.failingSaid = false
    elseif ratio < R.FAIL_RATIO then
        self:failing()
    end
end

function Readback:failing()
    if self.failingSaid then
        return
    end
    self.failingSaid = true
    if self.env.onFailing ~= nil then
        self.env.onFailing()
    end
end

-- A sample lost to a disturbance is taken again; a refused unit ("no
-- health") is not.
local RETRY = { stop = true, ambiguous = true, interrupt = true, timeout = true, failed = true, ["between levels"] = true, ["out of range"] = true, ["game in the background"] = true }

-- Whether the readback takes a sample lost this way again.
function GroupHealth.readbackRetries(why)
    return RETRY[why] == true
end

-- Returns true when it purged.
function Readback:discard(m, why)
    local stats = self.stats
    local env = self.env
    stats.discarded[why] = (stats.discarded[why] or 0) + 1
    if env.onDiscard ~= nil then
        env.onDiscard(m.unit, why, m)
    end
    if not RETRY[why] then
        return false
    end
    local now = env.now()
    self.failedSamples = self.failedSamples + 1
    self:outcome(false)
    if now - self.lastReadingMs > R.FAIL_MS and self.failedSamples >= R.FAIL_SAMPLES then
        self:failing()
    end
    local state = self.units[m.unit]
    if state == nil then
        return false
    end
    state.failingSinceMs = state.failingSinceMs or m.calledMs
    if now - state.failingSinceMs > R.STUCK_MS and now - self.lastPurgeMs > R.STUCK_MS then
        self:purge("stuck")
        return true
    end
    -- No retry while a newer sample of the unit is still out (out counts this one).
    if state.out <= 1 then
        state.retries = (state.retries or 0) + 1
        if state.retries <= R.QUICK_RETRIES then
            state.again = true
        else
            state.later = true
        end
    end
    return false
end

-- The digits by id: the lower id was called first.
function Readback:decode(m)
    local first, second = self:digits(m)
    if first == nil then
        return nil, "ambiguous"
    end
    local finishes = m.slot.finishes
    for _, start in ipairs({ first, second }) do
        if self:interrupted(m, finishes[start.id]) then
            return nil, "interrupt"
        end
    end
    local playedHigh = finishes[first.id] - first.t
    local playedLow = finishes[second.id] - second.t
    local value, why, rawHigh, rawLow = GroupHealth.readbackValue(m.plan, playedHigh, playedLow)
    if value == nil then
        return nil, why
    end
    return {
        value = value,
        plan = m.plan,
        carried = m.carried,
        recheck = m.recheck,
        calledMs = m.calledMs,
        rawHigh = rawHigh,
        rawLow = rawLow,
        playedHigh = playedHigh,
        playedLow = playedLow,
    }
end

function Readback:finish(m)
    if m.done then
        return
    end
    m.done = true
    for i, other in ipairs(self.inflight) do
        if other == m then
            tremove(self.inflight, i)
            break
        end
    end
    local env = self.env
    local generation = self.generation
    -- The gap lets the start of speech that cut ours short arrive.
    env.after(R.GAP_SECONDS, function()
        -- A purge since: the sample's member is read afresh already.
        if generation ~= self.generation then
            return
        end
        local state = self.units[m.unit]
        if m.error ~= nil then
            if self:discard(m, m.error) then
                return
            end
        else
            local reading, why = self:decode(m)
            if reading == nil then
                if self:discard(m, why) then
                    return
                end
            elseif state ~= nil and m.calledMs < state.usedMs then
                self:discard(m, "older than the last reading")
            else
                self.stats.readings = self.stats.readings + 1
                self.lastReadingMs = env.now()
                self.failedSamples = 0
                self:outcome(true)
                if state ~= nil then
                    state.retries = 0
                    state.usedMs = m.calledMs
                    state.failingSinceMs = nil
                end
                env.onReading(m.unit, reading)
            end
        end
        if state ~= nil then
            state.out = math.max(0, state.out - 1)
            if state.again then
                state.again = false
                state.later = false
                self:rerequest(m.unit)
            elseif state.later then
                state.later = false
                env.after(R.RETRY_LATER_SECONDS, function()
                    if self.units[m.unit] == state then
                        self:rerequest(m.unit)
                    end
                end)
            end
        end
    end)
end
