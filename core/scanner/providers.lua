local module = WowVision.base.scanner
local L = module.L

-- Scanner categories that need nothing but the game: the Player category
-- holds your corpse while you are a ghost (the map API reports it on the
-- current map) and the graveyards of the current map, so a corpse run has
-- somewhere to point.

local function mapPositionNode(key, label, mapId, position)
    if position == nil then
        return nil
    end
    local _, world = C_Map.GetWorldPosFromMapPos(mapId, position)
    if world == nil then
        return nil
    end
    local wx, wy = world:GetXY()
    return { key = key, label = label, x = wx, y = wy }
end

module:registerProvider({
    key = "player",
    label = L["Player"],
    order = 5,
    build = function()
        local out = {}
        local mapId = C_Map.GetBestMapForUnit("player")
        if mapId == nil then
            return out
        end
        if UnitIsGhost("player") or UnitIsDeadOrGhost("player") then
            local corpse = C_DeathInfo ~= nil and C_DeathInfo.GetCorpseMapPosition ~= nil
                    and C_DeathInfo.GetCorpseMapPosition(mapId)
                or nil
            local node = mapPositionNode("corpse", L["Corpse"], mapId, corpse)
            if node ~= nil then
                tinsert(out, node)
            end
        else
            tinsert(out, { key = "alive", label = L["Not dead"] })
        end
        local graveyards = C_DeathInfo ~= nil and C_DeathInfo.GetGraveyardsForMap ~= nil
                and C_DeathInfo.GetGraveyardsForMap(mapId)
            or nil
        if graveyards ~= nil and #graveyards > 0 then
            local children = {}
            for _, graveyard in ipairs(graveyards) do
                local node = mapPositionNode(
                    "graveyard:" .. tostring(graveyard.graveyardID or graveyard.areaPoiID),
                    graveyard.name or L["Graveyards"],
                    mapId,
                    graveyard.position
                )
                if node ~= nil then
                    tinsert(children, node)
                end
            end
            tinsert(out, { key = "graveyards", label = L["Graveyards"], children = children })
        end
        return out
    end,
})
