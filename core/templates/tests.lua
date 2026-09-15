local testRunner = WowVision.testing.testRunner
local templates = WowVision.templates

local locale = setmetatable({ Health = "Health", of = "of" }, {
    __index = function(_, key)
        return key
    end,
})

testRunner:addSuite("Templates", {
    ["fields and locale keys render"] = function(t)
        local nodes = templates.parse("[Health] {current} [of] {maximum}", locale)
        t:assertEqual(templates.renderNodes(nodes, { current = 80, maximum = 100 }), "Health 80 of 100")
    end,

    ["a slash between values is spaced out at parse time"] = function(t)
        local nodes, fields = templates.parse("{current}/{maximum} [Health]", locale)
        t:assertTrue(fields.current)
        t:assertTrue(fields.maximum)
        t:assertEqual(nodes[2].type, "literal")
        t:assertEqual(nodes[2].value, " / ")
        t:assertEqual(templates.renderNodes(nodes, { current = 80, maximum = 100 }), "80 / 100 Health")
    end,

    ["existing spacing around a slash does not double"] = function(t)
        local nodes = templates.parse("{a} / {b}", locale)
        t:assertEqual(templates.renderNodes(nodes, { a = 1, b = 2 }), "1 / 2")
    end,

    ["rendering never touches field values"] = function(t)
        -- A value carrying a slash stays as is: only literal text is
        -- rewritten, since values may be secret on retail.
        local nodes = templates.parse("{name}", locale)
        t:assertEqual(templates.renderNodes(nodes, { name = "a/b" }), "a/b")
    end,

    ["escapes and missing fields"] = function(t)
        local nodes = templates.parse("{{x}} {gone} [[y]]", locale)
        t:assertEqual(templates.renderNodes(nodes, {}), "{x}  [y]")
    end,
})
