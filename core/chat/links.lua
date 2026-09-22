-- Chat line parts: the clickable pieces of one chat message -- the channel
-- name, the sender, and every item, quest, or spell link -- in the order a
-- sighted player sees them. Parsing is pure and headless-tested; the click
-- helpers below go through the game's own SetItemRef, the same function a
-- real mouse click on the chat frame reaches.

local chatLinks = {}
WowVision.chatLinks = chatLinks

local PLAYER_TYPES = {
    player = true,
    playerCommunity = true,
    playerGM = true,
    BNplayer = true,
    BNplayerCommunity = true,
}

-- Spoken kind per link type; anything unlisted reads as a plain "Link".
local TYPE_LABELS = {
    item = "Item",
    quest = "Quest",
    spell = "Spell",
    enchant = "Spell",
    talent = "Talent",
    achievement = "Achievement",
    trade = "Profession",
    currency = "Currency",
}

local function stripMarkup(text)
    return (
        text:gsub("|c%x%x%x%x%x%x%x%x", "")
            :gsub("|cn[^:]+:", "")
            :gsub("|r", "")
            :gsub("|T.-|t", "")
            :gsub("|A.-|a", "")
    )
end

-- Display text as speech: no color codes, textures, or link brackets.
local function cleanDisplay(display)
    return (stripMarkup(display):gsub("^%s*%[", ""):gsub("%]%s*$", ""))
end

-- The line as a sighted player reads it, for copying: links collapse to
-- their display text, colors and textures drop out.
function chatLinks.plainText(message)
    if WowVision.isSecret ~= nil and WowVision.isSecret(message) then
        return nil, "secret"
    end
    if type(message) ~= "string" then
        return ""
    end
    return stripMarkup((message:gsub("|H.-|h(.-)|h", "%1")))
end

-- message -> list of parts, or nil plus a reason ("secret") when the text
-- cannot be inspected. Retail and Forever hand addons SECRET chat text while
-- chat messaging lockdown is in effect (encounters, restricted maps): any
-- string operation on it throws, so it is checked before anything else.
-- part: { kind = "player"|"channel"|"link", linkType, link, text, display }
--   link    the bare link data ("item:2589:0:..."), SetItemRef's first argument
--   text    the full link markup including its color wrapper, the second
function chatLinks.parse(message)
    if WowVision.isSecret ~= nil and WowVision.isSecret(message) then
        return nil, "secret"
    end
    local parts = {}
    if type(message) ~= "string" then
        return parts
    end
    local init = 1
    while true do
        local first, last, link, display = string.find(message, "|H(.-)|h(.-)|h", init)
        if first == nil then
            break
        end
        local text = string.sub(message, first, last)
        -- Quality colors wrap the link from outside; shift-click relinking
        -- needs them back on.
        local before = string.sub(message, 1, first - 1)
        local color = string.match(before, "(|c%x%x%x%x%x%x%x%x)$") or string.match(before, "(|cn[^:]+:)$")
        if color ~= nil and string.sub(message, last + 1, last + 2) == "|r" then
            text = color .. text .. "|r"
        end
        local linkType = string.match(link, "^([^:]+)") or link
        local kind = "link"
        if PLAYER_TYPES[linkType] then
            kind = "player"
        elseif linkType == "channel" then
            kind = "channel"
        end
        local spoken = cleanDisplay(display)
        if spoken ~= "" then
            tinsert(parts, {
                kind = kind,
                linkType = linkType,
                link = link,
                text = text,
                display = spoken,
            })
        end
        init = last + 1
    end
    return parts
end

-- Where the part cursor starts on a fresh line: the first item-like link, so
-- the tooltip keys read it with no extra step; else the sender; else the
-- first part.
function chatLinks.defaultIndex(parts)
    if parts == nil or #parts == 0 then
        return 0
    end
    for index, part in ipairs(parts) do
        if part.kind == "link" then
            return index
        end
    end
    for index, part in ipairs(parts) do
        if part.kind == "player" then
            return index
        end
    end
    return 1
end

function chatLinks.partLabel(part)
    local L = WowVision:getLocale()
    local kindLabel
    if part.kind == "player" then
        kindLabel = L["Player"]
    elseif part.kind == "channel" then
        kindLabel = L["Channel"]
    else
        kindLabel = L[TYPE_LABELS[part.linkType] or "Link"]
    end
    return kindLabel .. " " .. part.display
end

-- The name a player link carries (first option; realm included when the
-- game put one there).
function chatLinks.playerName(part)
    return (string.match(part.link, "^[^:]+:([^:]+)"))
end

------------------------------------------------------------
-- Clicks (game client only)
------------------------------------------------------------

-- A true left or right click on the part.
function chatLinks.click(part, button, chatFrame)
    SetItemRef(part.link, part.text, button, chatFrame or SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME)
end

local function openChat(text, chatFrame)
    if ChatFrameUtil ~= nil and ChatFrameUtil.OpenChat ~= nil then
        ChatFrameUtil.OpenChat(text, chatFrame)
    elseif ChatFrame_OpenChat ~= nil then
        ChatFrame_OpenChat(text, chatFrame)
    end
end

local function insertLink(text)
    if ChatFrameUtil ~= nil and ChatFrameUtil.InsertLink ~= nil then
        return ChatFrameUtil.InsertLink(text)
    elseif ChatEdit_InsertLink ~= nil then
        return ChatEdit_InsertLink(text)
    end
    return false
end

-- The shift-click, by result rather than by held key so the binding stays
-- rebindable: a player name goes into the open chat box, or becomes a /who
-- with none open (as the game does); a link goes into the chat box, which is
-- opened for it when none is -- a keyboard user cannot have the chat box and
-- this window focused at once.
function chatLinks.shiftClick(part, chatFrame)
    if part.kind == "channel" then
        return false
    end
    if part.kind == "player" then
        if part.linkType == "BNplayer" or part.linkType == "BNplayerCommunity" then
            return false -- the game disables this too: the link carries an account id
        end
        local name = chatLinks.playerName(part)
        if name == nil then
            return false
        end
        if not insertLink(name) then
            C_FriendList.SendWho((WHO_TAG_EXACT or "") .. name, Enum.SocialWhoOrigin and Enum.SocialWhoOrigin.Item)
        end
        return true
    end
    if not insertLink(part.text) then
        openChat(part.text, chatFrame)
    end
    return true
end
