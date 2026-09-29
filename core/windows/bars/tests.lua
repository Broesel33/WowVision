local testRunner = WowVision.testing.testRunner
local lock = WowVision.actionBarLock

-- A console variable store standing in for the game's.
local function cvars(value, refuse)
    local store = { lockActionBars = value, writes = 0 }
    local function get(name)
        return store[name]
    end
    local function set(name, newValue)
        if refuse then
            error("refused")
        end
        store[name] = newValue
        store.writes = store.writes + 1
    end
    return store, get, set
end

testRunner:addSuite("ActionBarUnlock", {
    ["locked bars are unlocked on the first login"] = function(t)
        local state = { actionBarsUnlocked = false }
        local store, get, set = cvars("1")
        t:assertTrue(lock.unlockOnce(state, get, set))
        t:assertEqual(store.lockActionBars, "0")
        t:assertTrue(state.actionBarsUnlocked)
    end,

    ["bars already unlocked are left alone and marked done"] = function(t)
        local state = { actionBarsUnlocked = false }
        local store, get, set = cvars("0")
        t:assertFalse(lock.unlockOnce(state, get, set))
        t:assertEqual(store.writes, 0)
        t:assertTrue(state.actionBarsUnlocked)
    end,

    ["bars the player locked again stay locked"] = function(t)
        local state = { actionBarsUnlocked = true }
        local store, get, set = cvars("1")
        t:assertFalse(lock.unlockOnce(state, get, set))
        t:assertEqual(store.lockActionBars, "1")
        t:assertEqual(store.writes, 0)
    end,

    ["a refused write is tried again next login"] = function(t)
        local state = { actionBarsUnlocked = false }
        local store, get, set = cvars("1", true)
        t:assertFalse(lock.unlockOnce(state, get, set))
        t:assertEqual(store.lockActionBars, "1")
        t:assertFalse(state.actionBarsUnlocked)
    end,
})
