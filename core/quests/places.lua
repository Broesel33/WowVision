local quests = WowVision.quests

-- Place naming shared by every quest data source: given a map position,
-- the nearest map landmark with its distance and the explored-overlay
-- area name there. Zone and subzone words are the caller's (a source that
-- knows the area ids passes them; one that only knows the map passes the
-- map name). Everything here is plain game API.
local places = {}
quests.places = places

-- The map's points of interest (towns, camps, landmarks -- shown whether
-- or not the player has explored them) as world positions, cached per
-- map. The game offers no subzone-at-coordinate lookup (the exploration
-- API reports overlay art, not subzones), so the nearest landmark stands
-- in for one.
local landmarksByMap = {}
function places.landmarks(mapId)
    local list = landmarksByMap[mapId]
    if list ~= nil then
        return list
    end
    list = {}
    landmarksByMap[mapId] = list
    if C_AreaPoiInfo == nil or C_AreaPoiInfo.GetAreaPOIForMap == nil then
        return list
    end
    local ok, ids = pcall(C_AreaPoiInfo.GetAreaPOIForMap, mapId)
    if not ok or ids == nil then
        return list
    end
    for _, poiId in ipairs(ids) do
        local infoOk, info = pcall(C_AreaPoiInfo.GetAreaPOIInfo, mapId, poiId)
        if infoOk and info ~= nil and info.name ~= nil and info.name ~= "" and info.position ~= nil then
            local _, position = C_Map.GetWorldPosFromMapPos(mapId, info.position)
            if position ~= nil then
                local wx, wy = position:GetXY()
                tinsert(list, { name = info.name, wx = wx, wy = wy })
            end
        end
    end
    return list
end

-- The explored-overlay area names at a map position (x, y in percent):
-- the exploration art's areas, right in open country, unreliable where
-- overlays crowd (and absent until uncovered). Returned as a set of names.
function places.overlayAreas(mapId, x, y)
    local names = {}
    if C_MapExplorationInfo == nil or C_MapExplorationInfo.GetExploredAreaIDsAtPosition == nil then
        return names
    end
    local ok, ids = pcall(C_MapExplorationInfo.GetExploredAreaIDsAtPosition, mapId, CreateVector2D(x / 100, y / 100))
    if ok and ids ~= nil then
        for _, id in ipairs(ids) do
            local name = C_Map.GetAreaInfo(id)
            if name ~= nil and name ~= "" then
                names[name] = true
            end
        end
    end
    return names
end

-- Names for a position (x, y in percent of mapId): the zone as given
-- (falling back to the map's name), the nearest landmark with its
-- distance in yards, an overlay area name when one is known there, and
-- the subzone as given.
function places.placeName(mapId, x, y, zone, subzone)
    if zone == nil and mapId ~= nil and C_Map.GetMapInfo ~= nil then
        local info = C_Map.GetMapInfo(mapId)
        zone = info ~= nil and info.name or nil
    end
    if mapId == nil or x == nil or y == nil then
        return zone, nil, nil, nil, subzone
    end
    local _, position = C_Map.GetWorldPosFromMapPos(mapId, CreateVector2D(x / 100, y / 100))
    if position == nil then
        return zone, nil, nil, nil, subzone
    end
    local wx, wy = position:GetXY()
    local bestName, bestDistance = nil, nil
    for _, landmark in ipairs(places.landmarks(mapId)) do
        local dx, dy = landmark.wx - wx, landmark.wy - wy
        local distance = math.sqrt(dx * dx + dy * dy)
        if bestDistance == nil or distance < bestDistance then
            bestName, bestDistance = landmark.name, distance
        end
    end
    local area = nil
    for name in pairs(places.overlayAreas(mapId, x, y)) do
        if name ~= zone and (area == nil or name == bestName) then
            area = name
        end
    end
    return zone, bestName, bestDistance, area, subzone
end
