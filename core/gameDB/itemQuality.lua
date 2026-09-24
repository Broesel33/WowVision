local L = WowVision:getLocale()

-- Item quality as words. Labels name the quality by the colour the game
-- paints the item name in ("Fur Boots, White"); the tooltip reads the
-- game's own quality name ("Common") and the item level under the slot
-- line.
local items = {}

-- Colours per Enum.ItemQuality: 0 Poor, 1 Common, 2 Uncommon, 3 Rare,
-- 4 Epic, 5 Legendary, 6 Artifact, 7 Heirloom, 8 WoW Token.
local QUALITY_COLORS = {
    [0] = "Grey",
    [1] = "White",
    [2] = "Green",
    [3] = "Blue",
    [4] = "Purple",
    [5] = "Orange",
    [6] = "Light Gold",
    [7] = "Light Blue",
    [8] = "Light Blue",
}

local function getItemInfo(item)
    local getInfo = C_Item ~= nil and C_Item.GetItemInfo or GetItemInfo
    if getInfo == nil or item == nil then
        return nil
    end
    local ok, name, link, quality, itemLevel, _, _, _, _, equipLoc = pcall(getInfo, item)
    if not ok then
        return nil
    end
    return name, link, quality, itemLevel, equipLoc
end

local function usable(value)
    return value ~= nil and not WowVision.isSecret(value)
end

function items.getQualityColor(quality)
    if not usable(quality) then
        return nil
    end
    local key = QUALITY_COLORS[quality]
    return key ~= nil and L[key] or nil
end

function items.getQualityName(quality)
    if not usable(quality) then
        return nil
    end
    return _G["ITEM_QUALITY" .. tostring(quality) .. "_DESC"]
end

-- Quality of an item link, id, or name; nil until the item is cached.
function items.getQuality(item)
    local _, _, quality = getItemInfo(item)
    if usable(quality) then
        return quality
    end
    return nil
end

-- Whether names carry this quality's colour; the UI > Tooltip > Quality
-- module replaces this with its switches.
function items.shouldAnnounceColor(quality)
    return true
end

-- "name, colour", or the bare name when the quality is unknown or its
-- colour is switched off.
function items.formatName(name, quality)
    if name == nil then
        return nil
    end
    local color = items.shouldAnnounceColor(quality) and items.getQualityColor(quality) or nil
    if color == nil then
        return name
    end
    return name .. ", " .. color
end

-- Label for an item link: its name with the quality colour, or nil while
-- the item isn't cached.
function items.getLinkLabel(link)
    local name, _, quality = getItemInfo(link)
    if name == nil then
        return nil
    end
    return items.formatName(name, quality)
end

-- Equippable items only: the item level means nothing on reagents and
-- consumables. The detailed level accounts for upgrades and scaling; the
-- base level from GetItemInfo is the fallback where that API is missing.
local function getItemLevel(link, baseLevel, equipLoc)
    if equipLoc == nil or equipLoc == "" or equipLoc == "INVTYPE_NON_EQUIP_IGNORE" then
        return nil
    end
    local getDetailed = C_Item ~= nil and C_Item.GetDetailedItemLevelInfo or GetDetailedItemLevelInfo
    if getDetailed ~= nil then
        local ok, level = pcall(getDetailed, link)
        if ok and usable(level) and level > 0 then
            return level
        end
    end
    if usable(baseLevel) and baseLevel > 0 then
        return baseLevel
    end
    return nil
end

-- "Item Level %d" as a pattern matching the game's own item level line.
local itemLevelPattern
local function isItemLevelLine(text)
    if text == nil or ITEM_LEVEL == nil then
        return false
    end
    if itemLevelPattern == nil then
        local prefix = ITEM_LEVEL:match("^(.-)%%d") or ITEM_LEVEL
        itemLevelPattern = "^" .. prefix:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0") .. "%d"
    end
    return text:match(itemLevelPattern) ~= nil
end

-- Extra lines for an item tooltip: the quality name and the item level
-- go under the slot line (or under the name when the item has no slot).
-- lines is a list of { left, right }; it is changed in place. Any item
-- level line the game shows itself is dropped so it isn't read twice.
function items.augmentTooltipLines(lines, link)
    local _, _, quality, baseLevel, equipLoc = getItemInfo(link)
    local qualityName = items.getQualityName(quality)
    local itemLevel = getItemLevel(link, baseLevel, equipLoc)
    if qualityName == nil and itemLevel == nil then
        return
    end

    if itemLevel ~= nil then
        for i = #lines, 2, -1 do
            if isItemLevelLine(lines[i][1]) then
                table.remove(lines, i)
            end
        end
    end

    local position = math.min(2, #lines + 1)
    local slotText = equipLoc ~= nil and equipLoc ~= "" and _G[equipLoc] or nil
    if slotText ~= nil then
        for i = 2, #lines do
            if lines[i][1] == slotText then
                position = i + 1
                break
            end
        end
    end

    if itemLevel ~= nil and ITEM_LEVEL ~= nil then
        table.insert(lines, position, { format(ITEM_LEVEL, itemLevel), nil })
    end
    if qualityName ~= nil then
        table.insert(lines, position, { qualityName, nil })
    end
end

WowVision.items = items
