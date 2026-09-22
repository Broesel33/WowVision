local testRunner = WowVision.testing.testRunner
local chatLinks = WowVision.chatLinks

local CHANNEL = "|Hchannel:channel:2|h[2. Trade]|h"
local PLAYER = "|Hplayer:Xynayya-Thunderstrike:412:CHANNEL:2|h[|cffaad372Xynayya|r]|h"
local CLOTH = "|cffffffff|Hitem:2589::::::::70:::::|h[Linen Cloth]|h|r"
local SWORD = "|cff0070dd|Hitem:2244::::::::70:::::|h[Krol Blade]|h|r"

testRunner:addSuite("ChatLinks", {
    ["a line without links has no parts"] = function(t)
        local parts = chatLinks.parse("You are now rested.")
        t:assertEqual(#parts, 0)
        t:assertEqual(chatLinks.defaultIndex(parts), 0)
    end,

    ["a sender is a player part and the default"] = function(t)
        local parts = chatLinks.parse(PLAYER .. ": hello there")
        t:assertEqual(#parts, 1)
        t:assertEqual(parts[1].kind, "player")
        t:assertEqual(parts[1].display, "Xynayya")
        t:assertEqual(parts[1].link, "player:Xynayya-Thunderstrike:412:CHANNEL:2")
        t:assertEqual(chatLinks.playerName(parts[1]), "Xynayya-Thunderstrike")
        t:assertEqual(chatLinks.defaultIndex(parts), 1)
    end,

    ["parts keep line order and the first item is the default"] = function(t)
        local parts = chatLinks.parse(CHANNEL .. " " .. PLAYER .. ": WTS " .. CLOTH .. " and " .. SWORD)
        t:assertEqual(#parts, 4)
        t:assertEqual(parts[1].kind, "channel")
        t:assertEqual(parts[1].display, "2. Trade")
        t:assertEqual(parts[2].kind, "player")
        t:assertEqual(parts[3].kind, "link")
        t:assertEqual(parts[3].linkType, "item")
        t:assertEqual(parts[3].display, "Linen Cloth")
        t:assertEqual(parts[4].display, "Krol Blade")
        t:assertEqual(chatLinks.defaultIndex(parts), 3)
    end,

    ["an item part carries its color wrapper for relinking"] = function(t)
        local parts = chatLinks.parse("look: " .. SWORD .. " nice")
        t:assertEqual(parts[1].text, SWORD)
        t:assertEqual(parts[1].link, "item:2244::::::::70:::::")
    end,

    ["an uncolored link keeps bare markup"] = function(t)
        local parts = chatLinks.parse("|Hquest:171:10|h[A Warden of the Alliance]|h")
        t:assertEqual(parts[1].linkType, "quest")
        t:assertEqual(parts[1].text, "|Hquest:171:10|h[A Warden of the Alliance]|h")
        t:assertEqual(chatLinks.partLabel(parts[1]), "Quest A Warden of the Alliance")
    end,

    ["battle.net senders are player parts"] = function(t)
        local parts = chatLinks.parse("|HBNplayer:|Kq12|k:34:567:BN_WHISPER:|Kq12|k|h[|Kq12|k]|h whispers: hi")
        t:assertEqual(#parts, 1)
        t:assertEqual(parts[1].kind, "player")
        t:assertEqual(parts[1].linkType, "BNplayer")
    end,

    ["labels name the kind first"] = function(t)
        local parts = chatLinks.parse(CHANNEL .. " " .. PLAYER .. ": " .. CLOTH)
        t:assertEqual(chatLinks.partLabel(parts[1]), "Channel 2. Trade")
        t:assertEqual(chatLinks.partLabel(parts[2]), "Player Xynayya")
        t:assertEqual(chatLinks.partLabel(parts[3]), "Item Linen Cloth")
    end,

    ["plain text reads like the chat frame shows it"] = function(t)
        local line = CHANNEL .. " " .. PLAYER .. ": WTS " .. SWORD .. " https://example.org"
        t:assertEqual(chatLinks.plainText(line), "[2. Trade] [Xynayya]: WTS [Krol Blade] https://example.org")
    end,

    ["secret text is refused, never inspected"] = function(t)
        local secret = {}
        local previous = WowVision.isSecret
        WowVision.isSecret = function(value)
            return value == secret
        end
        local parts, reason = chatLinks.parse(secret)
        local plain = chatLinks.plainText(secret)
        WowVision.isSecret = previous
        t:assertNil(plain)
        t:assertNil(parts)
        t:assertEqual(reason, "secret")
    end,
})
