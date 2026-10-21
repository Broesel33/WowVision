-- The texts of the WowNav engine in WowVision's languages: WowVisionNavigationText (the resolver's reasons) and the
-- spoken names of targets, built the way WowNav's Localization.lua builds them (data ReadMe section 8): a dyn target
-- has a name key and a place that the client names in its own language (C_Map.GetAreaInfo / GetRealZoneText, the
-- English nameParam as the fallback), plus a suffix when two targets of a zone would sound alike. Categories come as
-- English keys from the data and are named here.

local L = WowVision:getLocale()

local text = {}
WowVision.wownavText = text

-- the resolver's reasons (TargetResolver.lua); keys without an entry read back as the key
local REASONS = {
    res_stale = L["The target position is outdated"],
    res_no_native_map = L["The target is on another map"],
    res_other_map = L["The target is on another map"],
    res_band_invalid = L["There is no such floor"],
    res_ambiguous = L["The target lies over several floors"],
    res_z_conflict = L["The target's height fits no floor of the network"],
    res_level_unknown = L["The target lies over several floors"],
    res_no_point = L["No network point near the target"],
    res_no_path = L["No network path to the target"],
    res_no_route_from_start = L["No network path from here to the target"],
}

function WowVisionNavigationText(key, ...)
    local template = REASONS[key]
    if template == nil then
        return tostring(key)
    end
    if select("#", ...) > 0 then
        return string.format(template, ...)
    end
    return template
end

function text.german()
    return GetLocale ~= nil and GetLocale() == "deDE"
end

-- dyn name templates (nameKey) and suffixes (nameSuffix.key)
local DYN = {
    dungeon_entrance = L["Dungeon entrance: %s"],
    portal = L["Portal to %s"],
    dock_ship = L["Ship dock to %s"],
    dock_zeppelin = L["Zeppelin dock to %s"],
    tram_entrance = L["Deeprun Tram entrance"],
    tram_dock = L["Tram dock toward %s"],
    elevator = L["Elevator: %s"],
    zone_transition = L["Crossing to %s"],
}
local SUFFIX = {
    lower = L[" (lower)"],
    upper = L[" (upper)"],
    z = L[" (height %d)"],
    number = L[" (%d)"],
}

local function placeName(target)
    if type(target.nameAreaId) == "number" and C_Map ~= nil and C_Map.GetAreaInfo ~= nil then
        local ok, name = pcall(C_Map.GetAreaInfo, target.nameAreaId)
        if ok and type(name) == "string" and name ~= "" then
            return name
        end
    end
    if type(target.nameMapId) == "number" and GetRealZoneText ~= nil then
        local ok, name = pcall(GetRealZoneText, target.nameMapId)
        if ok and type(name) == "string" and name ~= "" then
            return name
        end
    end
    if type(target.nameParam) == "string" and target.nameParam ~= "" then
        return target.nameParam
    end
    return nil
end

local function nameSuffix(target)
    local suffix = target.nameSuffix
    if type(suffix) ~= "table" or type(suffix.key) ~= "string" then
        return ""
    end
    local template = SUFFIX[suffix.key]
    if template == nil then
        return ""
    end
    if template:find("%d", 1, true) then
        if type(suffix.value) ~= "number" then
            return ""
        end
        return string.format(template, suffix.value)
    end
    return template
end

-- The spoken name of a target (WowNav's WowVisionNavigationTargetName).
function text.targetName(target, german)
    if type(target) ~= "table" then
        return ""
    end
    local key = target.nameKey
    local template = type(key) == "string" and DYN[key] or nil
    if template ~= nil then
        if not template:find("%s", 1, true) then
            return template .. nameSuffix(target)
        end
        return string.format(template, placeName(target) or L["unknown destination"]) .. nameSuffix(target)
    end
    if german == nil then
        german = text.german()
    end
    local english, deutsch = target.nameEn, target.nameDe
    if german and type(deutsch) == "string" and deutsch ~= "" then
        return deutsch .. nameSuffix(target)
    end
    if type(english) == "string" and english ~= "" then
        return english .. nameSuffix(target)
    end
    if type(deutsch) == "string" and deutsch ~= "" then
        return deutsch .. nameSuffix(target)
    end
    return tostring(target.id or "")
end

-- category keys of the data (ReadMe section 7)
local CATEGORY = {
    quest_giver = L["quest giver"], trainer = L["trainer"], vendor = L["vendor"],
    flight_master = L["flight master"], innkeeper = L["innkeeper"], banker = L["banker"],
    stable_master = L["stable master"], auctioneer = L["auctioneer"], spirit_healer = L["spirit healer"],
    spirit_guide = L["spirit guide"], npc_or_mob = L["NPC or mob"], chest = L["chest"],
    herb_or_ore = L["herb or ore"], object = L["object"], quest_item = L["quest item"],
    interaction_object = L["interaction object"], mailbox = L["mailbox"], anvil = L["anvil"], forge = L["forge"],
    door = L["door"], book = L["book"], chair = L["chair"], sign = L["sign"], fishing_spot = L["fishing spot"],
    zone_transition = L["zone transition"], transit = L["transit"], boat = L["ship"], tram = L["tram"],
    dungeon = L["dungeon"], portal = L["portal"], zeppelin = L["zeppelin"], lift = L["elevator"],
}

-- The spoken categories of a target, "trainer, vendor"; nil when it has none worth saying.
function text.categories(target)
    local list = target.category
    if type(list) == "string" then
        list = { list }
    end
    if type(list) ~= "table" then
        return nil
    end
    local out = {}
    for _, key in ipairs(list) do
        local name = CATEGORY[key]
        if name == nil and type(key) == "string" then
            local number = key:match("^object_type_(%d+)$")
            name = number and string.format(L["object type %s"], number) or nil
        end
        if name ~= nil then
            out[#out + 1] = name
        end
    end
    if #out == 0 then
        return nil
    end
    return table.concat(out, ", ")
end
