local testRunner = WowVision.testing.testRunner
local secrets = WowVision.secrets

-- A stand-in for the game's secrets: a table carrying the hidden value, and
-- an issecretvalue that recognises it. Installed for one test at a time.
local function secret(value)
    return { secretValue = value }
end

local function withSecrets(fn)
    return function(t)
        local saved = issecretvalue
        issecretvalue = function(value)
            return type(value) == "table" and value.secretValue ~= nil
        end
        local ok, err = pcall(fn, t)
        issecretvalue = saved
        if not ok then
            error(err, 0)
        end
    end
end

testRunner:addSuite("Secrets", {
    ["plain values compare as usual"] = function(t)
        t:assertEqual(secrets.changed("a", "a"), false)
        t:assertEqual(secrets.changed("a", "b"), true)
        t:assertEqual(secrets.changed(nil, "b"), true)
        t:assertEqual(secrets.changed(nil, nil), false)
    end,

    ["a secret on either side reads as a change"] = withSecrets(function(t)
        t:assertEqual(secrets.changed(secret("x"), "x"), true)
        t:assertEqual(secrets.changed("x", secret("x")), true)
        t:assertEqual(secrets.changed(secret("x"), secret("x")), true)
    end),

    ["hasText: nil and empty say nothing, secrets say something"] = withSecrets(function(t)
        t:assertEqual(secrets.hasText(nil), false)
        t:assertEqual(secrets.hasText(""), false)
        t:assertEqual(secrets.hasText("Hogger"), true)
        t:assertEqual(secrets.hasText(secret("")), true)
    end),

    ["join concatenates with the separator"] = function(t)
        t:assertEqual(secrets.join({}, ", "), "")
        t:assertEqual(secrets.join({ "Star" }, ", "), "Star")
        t:assertEqual(secrets.join({ "Star", "Hogger", "1 of 3" }, ", "), "Star, Hogger, 1 of 3")
    end,
})
