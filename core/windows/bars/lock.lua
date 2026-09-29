-- The one-time action bar unlock, kept free of frames so it runs in the
-- headless tests. See the bars module for why and when it runs.
local lock = {}

-- state.actionBarsUnlocked records that this character was handled.
-- Returns true when the bars were locked and are now unlocked.
function lock.unlockOnce(state, getCVar, setCVar)
    if state.actionBarsUnlocked then
        return false
    end
    if getCVar == nil or setCVar == nil then
        return false
    end
    local okRead, locked = pcall(getCVar, "lockActionBars")
    if not okRead then
        return false
    end
    local changed = false
    if locked == "1" or locked == true or locked == 1 then
        if not pcall(setCVar, "lockActionBars", "0") then
            -- Refused (combat, a restricted client): try again next login.
            return false
        end
        changed = true
    end
    state.actionBarsUnlocked = true
    return changed
end

WowVision.actionBarLock = lock
