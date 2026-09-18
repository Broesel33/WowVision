local testRunner = WowVision.testing.testRunner
local colors = WowVision.colors

local function describe(r, g, b)
    return colors.describe(r / 255, g / 255, b / 255)
end

local function nearest(r, g, b)
    return colors.nearestName(r / 255, g / 255, b / 255)
end

testRunner:addSuite("Colors", {
    ["neutrals read as white, gray, and black"] = function(t)
        t:assertEqual(describe(255, 255, 255), "white")
        t:assertEqual(describe(200, 200, 200), "light gray")
        t:assertEqual(describe(128, 128, 128), "gray")
        t:assertEqual(describe(64, 64, 64), "dark gray")
        t:assertEqual(describe(0, 0, 0), "black")
    end,

    ["pure hues are vivid"] = function(t)
        t:assertEqual(describe(255, 0, 0), "vivid red")
        t:assertEqual(describe(0, 0, 255), "vivid blue")
        t:assertEqual(describe(255, 255, 0), "vivid yellow")
        t:assertEqual(describe(0, 255, 255), "vivid bluish green")
    end,

    ["dark saturated blue is deep, not dark"] = function(t)
        local text = describe(0, 0, 128)
        t:assertTrue(text == "very deep blue" or text == "deep blue", text)
    end,

    ["muted colours pick up the grayish modifier"] = function(t)
        t:assertEqual(describe(112, 128, 144), "grayish blue")
    end,

    ["light reds are pinks and dark oranges are browns"] = function(t)
        t:assertTrue(describe(255, 192, 203):find("pink", 1, true) ~= nil, describe(255, 192, 203))
        t:assertTrue(describe(139, 69, 19):find("brown", 1, true) ~= nil, describe(139, 69, 19))
        t:assertTrue(describe(128, 128, 0):find("olive", 1, true) ~= nil, describe(128, 128, 0))
    end,

    ["a near black tint is blackish"] = function(t)
        t:assertEqual(describe(30, 0, 0), "blackish red")
    end,

    ["nearest name matches exact table entries"] = function(t)
        t:assertEqual(nearest(0, 0, 128), "Navy Blue")
        t:assertEqual(nearest(255, 255, 255), "White")
    end,

    ["nearest name picks the closest entry for colours off the table"] = function(t)
        t:assertEqual(nearest(112, 128, 144), "Slate Gray")
    end,

    ["text joins the description and the name"] = function(t)
        t:assertEqual(colors.text255(0, 0, 128):find("blue, Navy Blue", 1, true) ~= nil, true)
    end,

    ["text drops a name that repeats the description"] = function(t)
        t:assertEqual(colors.text255(0, 0, 0), "black")
        t:assertEqual(colors.text255(255, 255, 255), "white")
    end,
})
