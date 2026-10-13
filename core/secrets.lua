-- Helpers for values the game hands addons as SECRETS (Retail from Midnight
-- on, and WoW: Forever, which runs the same engine). Comparing, measuring or
-- string-processing a secret throws; truthiness and concatenation work, and
-- the speech API accepts secret strings. Pure Lua so the headless tests run
-- it; clients without secrets (classic) see every guard collapse to a plain
-- check.
local secrets = {}
WowVision.secrets = secrets

function secrets.isSecret(value)
    return issecretvalue ~= nil and issecretvalue(value) == true
end

-- Whether a value changed between two reads. A secret on either side cannot
-- be compared, and the events that deliver secrets already mean "changed",
-- so it reads as a change. Callers that poll must use another change signal
-- (the event) while the value is secret, or they would fire every tick.
function secrets.changed(old, new)
    if secrets.isSecret(old) or secrets.isSecret(new) then
        return true
    end
    return old ~= new
end

-- Whether a string has anything to say: nil and "" do not; a secret string
-- is taken to (its length cannot be read, and speech accepts it as is).
function secrets.hasText(text)
    if not text then
        return false
    end
    if secrets.isSecret(text) then
        return true
    end
    return text ~= ""
end

-- table.concat refuses secret strings; concatenation carries them through.
-- Joins a list of strings with a separator the same way.
function secrets.join(list, separator)
    local text = ""
    for index, item in ipairs(list) do
        if index == 1 then
            text = item
        else
            text = text .. separator .. item
        end
    end
    return text
end
