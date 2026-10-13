-- The group health monitor's log (/wv ghlog): what the monitor did, for
-- tests in game. Off by default and quiet while on (in chat it was too much
-- in a fight); /wv ghlog show opens the last lines. The log and the
-- readback's counts also go into WowVisionDump, saved at the next /reload.
-- Health itself is secret and never logged: only what the monitor did and
-- when.
--
-- The monitor reports through module:trace(member, what, detail):
-- - event: a health event, detail the unit token it came with;
-- - wait: a check held back, detail why;
-- - sent: a number went out with a check;
-- - moved: a check found the number was a move (detail: a re-check);
-- - lost: a check was lost (detail: why, re-check);
-- - respeak: something cut by a stop goes out again;
-- - play: a queue entry plays (detail: the entry).

local module = WowVision.base.groupHealth

local LOG_MAX = 400
module.log = {}

-- Per member: when the health event came that the next number answers, and
-- why it waited. Weak keys: members dropped by a roster update go away.
local pending = setmetatable({}, { __mode = "k" })

local function chat(text)
    for line in tostring(text):gmatch("[^\n]+") do
        print("WowVision group health: " .. line)
    end
end

-- The clock time, and the game's own time to the hundredth (the clock's
-- seconds and the game time's fractions do not line up).
local function logTime()
    return date("%H:%M:%S") .. string.format(" (%.2f)", GetTime())
end

-- The log and the readback's counts into WowVisionDump.
function module:keepLog()
    WowVisionDump = WowVisionDump or {}
    WowVisionDump.groupHealthLog = {
        lines = self.log,
        readback = self.checks ~= nil and self.checks.readback.stats or nil,
        respoken = self.respoken,
        stopSources = self.stopSources,
        stopStacks = self.stopStacks,
    }
end

local function append(parts)
    tinsert(module.log, table.concat(parts, ", "))
    while #module.log > LOG_MAX do
        tremove(module.log, 1)
    end
    module:keepLog()
end

local function memberParts(member)
    return { logTime(), "number " .. tostring(member.number), string.lower(member.role) }
end

local trace = {}

-- Only events under another token than the member's own: in a raid the
-- same person may come as raidN and as partyN or player (one check each).
function trace.event(member, unit)
    local state = pending[member] or {}
    pending[member] = state
    state.eventAt = state.eventAt or GetTime()
    if unit ~= member.unit then
        local parts = memberParts(member)
        tinsert(parts, "health event as " .. tostring(unit) .. " (" .. member.unit .. ")")
        append(parts)
    end
end

function trace.wait(member, why)
    local state = pending[member] or {}
    pending[member] = state
    state.waited = state.waited or why
end

function trace.sent(member)
    local state = pending[member] or {}
    pending[member] = {
        sentAfter = state.eventAt ~= nil and GetTime() - state.eventAt or nil,
        waitedFor = state.waited,
    }
end

function trace.moved(member, recheck)
    local parts = memberParts(member)
    tinsert(parts, "moved, reference now " .. tostring(member.reference))
    -- Heard below "Speak Below", or at full health ("<number> full").
    local heard = member.reference < module:roleSetting(member.role, "startThreshold")
        or (member.reference >= 100 and module.settings.announceFull)
    local what = heard and "heard" or "silent (above Speak Below)"
    if recheck then
        -- The number went out with the lost check, earlier.
        what = what .. " with a lost check, found by a re-check"
    end
    tinsert(parts, what)
    local state = pending[member]
    if state ~= nil and state.sentAfter ~= nil then
        tinsert(parts, string.format("sent %.2f s after the health event", state.sentAfter))
        if state.sentAfter > 0.05 and state.waitedFor ~= nil then
            tinsert(parts, "waited: " .. state.waitedFor)
        end
    end
    append(parts)
end

function trace.lost(member, detail)
    local parts = memberParts(member)
    tinsert(parts, (detail.recheck and "re-check lost: " or "check lost: ") .. detail.why)
    append(parts)
end

function trace.respeak(member)
    module.respoken = (module.respoken or 0) + 1
    local parts = memberParts(member)
    tinsert(parts, "said again after a stop of all speech cut it")
    append(parts)
end

function trace.play(member, entry)
    local parts = memberParts(member)
    tinsert(parts, entry.lane)
    local queued = GetTime() - entry.queuedAt
    if queued > 0.05 then
        tinsert(parts, string.format("waited %.1f s in the queue", queued))
    end
    append(parts)
end

function module:trace(member, what, detail)
    if self.logging and trace[what] ~= nil then
        trace[what](member, detail)
    end
end

-- Where a stack line points: an addon file (Blizzard's own included) with
-- its line, or a code string (a key binding's body, a /run), else nil
-- (game code without Lua, "[C]").
local function stackPlace(line)
    local file, lineNumber = line:match("AddOns[/\\]([^%]%[\"\n:]-%.%a+)[%]\"]*:(%d+)")
    if file ~= nil then
        return file .. ":" .. lineNumber
    end
    local code = line:match('%[string "([^"\n]*)"%]')
    if code ~= nil then
        return 'code "' .. code:sub(1, 60) .. '"'
    end
    return nil
end

-- Who stopped all speech, while the log is on: the first place in the call
-- stack past the hooks and the speech module (only the messenger), with
-- whether Ctrl was held (Blizzard's Ctrl stop, the "Stop Text to Speech"
-- binding). Counted per source; each source's first stack is kept whole,
-- and every stop gets a log line, to set beside lost checks.
hooksecurefunc(C_VoiceChat, "StopSpeakingText", function()
    if not module.logging then
        return
    end
    local stack = debugstack(2, 20, 0) or ""
    local source = nil
    for line in stack:gmatch("[^\n]+") do
        local place = stackPlace(line)
        if place ~= nil and not place:find("groupHealth", 1, true) and not place:find("retail/speech.lua", 1, true) then
            source = place
            break
        end
    end
    if source == nil then
        source = "the game (no Lua on the stack)"
    end
    if IsControlKeyDown() then
        source = source .. ", Ctrl held"
    end
    module.stopSources = module.stopSources or {}
    module.stopSources[source] = (module.stopSources[source] or 0) + 1
    module.stopStacks = module.stopStacks or {}
    if module.stopStacks[source] == nil then
        module.stopStacks[source] = stack:sub(1, 1500)
    end
    append({ logTime(), "stop of all speech by " .. source })
end)

local function counts(list)
    local parts = {}
    for why, n in pairs(list) do
        tinsert(parts, why .. " " .. n)
    end
    table.sort(parts)
    return #parts > 0 and table.concat(parts, ", ") or "none"
end

local function show()
    local lines = {}
    for _, line in ipairs(module.log) do
        tinsert(lines, line)
    end
    -- The readback's counts, so its health shows next to the plays.
    if module.checks ~= nil then
        local stats = module.checks.readback.stats
        tinsert(lines, string.format(
            "Readback: %d samples, %d readings used, thrown away: %s; most at once %d; purges: %s; own speech cut %d, said again %d",
            stats.samples, stats.readings, counts(stats.discarded), stats.maxInflight, counts(stats.purges), stats.ownCut, module.respoken or 0
        ))
    end
    if #lines == 0 then
        return false
    end
    chat(lines[#lines])
    WowVision.testing.showResults(table.concat(lines, "\n"))
    return true
end

module:registerCommand({
    name = "ghlog",
    description = "Group health monitor log: 'on' records what the monitor does, 'off' stops, 'show' lists the last lines, 'clear' empties it",
    func = function(args)
        local word = (args or ""):lower():match("^%s*(%S+)")
        local text
        if word == "on" then
            module.logging = true
            text = "Group health log on"
        elseif word == "off" then
            module.logging = false
            text = "Group health log off"
        elseif word == "clear" then
            module.log = {}
            module:keepLog()
            text = "Group health log cleared"
        elseif show() then
            return
        else
            text = "Group health log is empty"
        end
        chat(text)
        WowVision:speak(text)
    end,
})
