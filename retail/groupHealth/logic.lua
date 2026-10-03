-- The group health monitor's game-independent half: the curve points that
-- turn a member's health into a pitch or a volume gate, raid numbering,
-- lane timing and the spoken text. No WoW API in here, so the headless
-- suite covers it (retail/groupHealth/tests.lua).
--
-- Health is a SECRET value on Retail and WoW: Forever: addon code cannot
-- compare it, do arithmetic on it or keep it to compare later. What works
-- (measured on Forever 1.60.1, 2026-10-03, with a probe):
-- - UnitHealthPercent(unit, true, curve) runs the real health (0 to 1)
--   through a curve WE build and hands back the result, itself secret.
-- - A secret survives concatenation, so the result can be the number in a
--   SAPI <pitch absmiddle="..."> or <volume level="..."> tag, and
--   C_VoiceChat.SpeakText honours both tags with a real SAPI voice. The
--   NVDA bridge voice speaks the text but ignores pitch.
-- - A step curve yields the value of the last point at or below the input:
--   points (0, 100), (0.5, 0) give 100 below half health, 0 from half up.
-- - A word at volume 0 is silent but takes as long as if it were spoken.
-- - PlaySoundFile refuses a secret path, so recorded files are no way out.
--
-- So the addon never decides whether someone is hurt. Every health event
-- prepares the possible announcements, each behind a volume gate, and the
-- engine plays the one whose health range matches.

local GroupHealth = {}
WowVision.groupHealth = GroupHealth

GroupHealth.ROLES = { "TANK", "HEALER", "DAMAGER", "NONE" }
GroupHealth.MAX_RAID_GROUPS = 8

-- Sku's monitor uses 15 pitch steps, the highest pitch at the lowest
-- health. The SAPI pitch range is -10 to 10.
GroupHealth.PITCH_STEPS = 15
GroupHealth.PITCH_HIGH = 10
GroupHealth.PITCH_LOW = -10

local function round(value)
    return math.floor(value + 0.5)
end

-- Step k covers health k/steps up to (k+1)/steps; full health falls into
-- the last step. Step 0 (the lowest health) gets the highest pitch.
function GroupHealth.pitchPoints(steps)
    steps = steps or GroupHealth.PITCH_STEPS
    local points = {}
    local span = GroupHealth.PITCH_HIGH - GroupHealth.PITCH_LOW
    for k = 0, steps - 1 do
        local pitch = GroupHealth.PITCH_HIGH - (steps > 1 and k * span / (steps - 1) or 0)
        tinsert(points, { k / steps, round(pitch) })
    end
    return points
end

local SILENT = { { 0, 0 } }

-- Volume 100 below `high`, 0 at or above it. Thresholds are fractions of
-- full health (0 to 1).
function GroupHealth.belowPoints(high)
    if high == nil or high <= 0 then
        return SILENT
    end
    return { { 0, 100 }, { high, 0 } }
end

-- Volume 100 from `low` up to (not including) `high`.
function GroupHealth.bandPoints(low, high)
    if high == nil or high <= 0 or (low ~= nil and low >= high) then
        return SILENT
    end
    if low == nil or low <= 0 then
        return GroupHealth.belowPoints(high)
    end
    return { { 0, 0 }, { low, 100 }, { high, 0 } }
end

-- Volume 100 at exactly full health.
function GroupHealth.fullPoints()
    return { { 0, 0 }, { 1, 100 } }
end

-- A cache key for a point list, so equal gates share one curve object.
function GroupHealth.pointsKey(points)
    local parts = {}
    for _, point in ipairs(points) do
        tinsert(parts, point[1] .. ":" .. point[2])
    end
    return table.concat(parts, ",")
end

-- Raid numbers as Sku gives them: (group - 1) * 5 + place in the group, the
-- place counted in raid index order. `roster` maps a raid index (1 to 40)
-- to its group number; holes are allowed. Returns raid index -> number.
function GroupHealth.raidNumbers(roster, maxIndex)
    local numbers = {}
    local counts = {}
    for index = 1, maxIndex or 40 do
        local group = roster[index]
        if group ~= nil then
            counts[group] = (counts[group] or 0) + 1
            numbers[index] = (group - 1) * 5 + counts[group]
        end
    end
    return numbers
end

-- When a lane may speak next: not before `delay` after the event that woke
-- it, and not within `pause` of its last announcement.
function GroupHealth.nextFire(now, lastFire, delay, pause)
    local at = now + (delay or 0)
    if lastFire ~= nil and pause ~= nil and lastFire + pause > at then
        at = lastFire + pause
    end
    return at
end

-- One spoken part: the words at a volume and a pitch, either of which may
-- be a secret curve result. Plain concatenation only, which secrets allow.
function GroupHealth.segment(volume, pitch, words)
    return '<volume level="' .. volume .. '"><pitch absmiddle="' .. pitch .. '">' .. words .. "</pitch></volume>"
end

-- The engine caches the audio of every text it speaks and replays it when
-- the same text comes again, keyed AFTER stripping the markup: a "3" at one
-- pitch and a "3" at another are one key, and the replay keeps the old
-- pitch and volume. Every utterance therefore gets a padding no other
-- utterance of the session has: utterance number n written in base 8, each
-- digit a run of 1 to 8 no-break spaces, the runs led by plain spaces.
-- Inaudible (Sku measured U+00A0 on the client), and unlike the shared
-- cache-buster's 512 variants per text it never repeats: a tank's number
-- would reach 512 within one long fight.
local NBSP = "\194\160"

function GroupHealth.uniquePad(n)
    local parts = {}
    repeat
        local digit = n % 8
        tinsert(parts, " " .. string.rep(NBSP, digit + 1))
        n = math.floor(n / 8)
    until n == 0
    return table.concat(parts)
end

-- Settings store thresholds in percent; curves take fractions.
function GroupHealth.fraction(percent)
    if percent == nil then
        return nil
    end
    if percent < 0 then
        percent = 0
    elseif percent > 100 then
        percent = 100
    end
    return percent / 100
end
