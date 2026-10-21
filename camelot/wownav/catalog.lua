-- The WowNav targets of a continent for WowVision's destination list (F10, /beacon to): the logical catalogues (NPCs,
-- mobs, objects; compact format 2, expanded by WowNav's TargetCatalog.ExpandCatalog) and the dyn catalogues (dungeon
-- entrances, portals, docks, tram stops, elevators, zone crossings) of every zone on the player's map, as WowNav's
-- own list has them (his concept 7a: one catalogue per continent). Each row says its categories and its zone, and the
-- search looks at the names in both languages, the categories and the zone (his 54414e7, from the user's own use).
--
-- Memory: the full rows are only built while a zone is read; the list keeps one slim row per target, and the zone's
-- catalogue goes back to packed text. The list is built in the background, one zone per step, when the player's map
-- changes, so F10 does not wait for it.

local text = WowVision.wownavText
local L = WowVision:getLocale()

local catalog = {}
WowVision.wownavCatalog = catalog

local LOGICAL_FORMAT = 2

-- the localised name of a zone (WowNav's LocalizedZoneName: the client's name of the zone's own map)
local zoneNames = {}
local function zoneName(N, zoneId)
    local cached = zoneNames[zoneId]
    if cached ~= nil then
        return cached or nil
    end
    local name
    if C_Map ~= nil and C_Map.GetMapInfo ~= nil then
        local ok, info = pcall(C_Map.GetMapInfo, zoneId)
        if ok and type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
            name = info.name
        end
    end
    local entry = N.index[zoneId]
    name = name or (entry and entry.name)
    zoneNames[zoneId] = name or false
    return name
end

local function lower(s)
    return WowVision.utils ~= nil and WowVision.utils.foldCase ~= nil and WowVision.utils.foldCase(s) or s:lower()
end

-- One slim row: what the list shows and searches, and what a route request needs (catalog.contract).
local function row(target, zoneId, zone, german, layer)
    local name = text.targetName(target, german)
    local categories = text.categories(target)
    local detail = categories and (categories .. ", " .. (zone or "")) or zone
    local search = { name, target.nameEn or "", target.nameDe or "", categories or "", zone or "" }
    for _, alias in ipairs(target.searchAliases or {}) do
        search[#search + 1] = alias
    end
    return {
        id = "wownav:" .. zoneId .. ":" .. target.id, n = name, detail = detail,
        search = lower(table.concat(search, " ")),
        x = target.x, y = target.y, z = target.z, levels = target.levels,
        tid = target.id, kind = target.kind, nameEn = target.nameEn, zoneId = zoneId, layer = layer,
        surface = target.surface,
    }
end

-- The rows of one zone (both layers), or nil, reason.
function catalog.zoneRows(N, C, zoneId, german)
    local zone = zoneName(N, zoneId)
    local out = {}
    local logical = N.LogicalTargets(zoneId)
    if type(logical) == "table" then
        if logical.format ~= LOGICAL_FORMAT then
            N.DropTargets(zoneId)
            return nil, "logical catalogue format " .. tostring(logical.format)
        end
        local rows, why = C.ExpandCatalog(logical)
        if not rows then
            N.DropTargets(zoneId)
            return nil, why
        end
        for _, target in ipairs(rows) do
            out[#out + 1] = row(target, zoneId, zone, german, "logical")
        end
        logical.expanded = nil
    end
    local dyn = N.DynTargets(zoneId)
    if type(dyn) == "table" and type(dyn.targets) == "table" then
        for _, target in ipairs(dyn.targets) do
            if type(target) == "table" and type(target.x) == "number" and type(target.y) == "number" then
                out[#out + 1] = row(target, zoneId, zone, german, "dyn")
            end
        end
    end
    N.DropTargets(zoneId)
    return out
end

-- The zones of the index on a native map.
function catalog.zonesOnMap(N, map)
    local zones = {}
    for id, entry in pairs(N.index) do
        if (entry.nativeMapId or entry.mapId) == map then
            zones[#zones + 1] = id
        end
    end
    table.sort(zones)
    return zones
end

-- The list of the player's map: built in steps (catalog.step), kept until the map changes.
local current = nil      -- { map, zones, next, rows, done, german }

function catalog.start(N, map)
    if current ~= nil and current.map == map then
        return
    end
    current = { map = map, zones = catalog.zonesOnMap(N, map), next = 1, rows = {}, done = false, german = text.german() }
    current.done = #current.zones == 0
end

-- Reads the next zone. True while there is more to read.
function catalog.step(N, C)
    local c = current
    if c == nil or c.done then
        return false
    end
    local zoneId = c.zones[c.next]
    c.next = c.next + 1
    local rows = catalog.zoneRows(N, C, zoneId, c.german)
    for _, r in ipairs(rows or {}) do
        c.rows[#c.rows + 1] = r
    end
    if c.next > #c.zones then
        c.done = true
    end
    return not c.done
end

-- The rows of the player's map, finished first if the background build has not got there yet.
function catalog.rows(N, C, map)
    catalog.start(N, map)
    while catalog.step(N, C) do
    end
    return current.rows
end

function catalog.covers(N, map)
    return #catalog.zonesOnMap(N, map) > 0
end

function catalog.clear()
    current = nil
end

-- The automatic waypoints near a position (his NODE_SELECTION_RADIUS list): the network's own waypoints of the zones
-- there, nearest first, at most limit, as rows that route straight to the waypoint (nodeId). Real waypoints only
-- (no points on links), like his NodesWithin.
catalog.NODE_SELECTION_RADIUS = 60.0

function catalog.autoPoints(N, x, y, radius, limit)
    radius = radius or catalog.NODE_SELECTION_RADIUS
    local found = {}
    for _, zoneId in ipairs(N.ZonesForPoint(x, y)) do
        if N.LoadZone(zoneId) then
            for _, id in ipairs(N.NodesWithin(zoneId, x, y, radius)) do
                local nx, ny, nz = N.Position(id)
                local dx, dy = nx - x, ny - y
                found[#found + 1] = { id = id, x = nx, y = ny, z = nz, distance = math.sqrt(dx * dx + dy * dy) }
            end
        end
    end
    table.sort(found, function(a, b)
        return a.distance < b.distance
    end)
    local rows = {}
    for i = 1, math.min(#found, limit or #found) do
        local p = found[i]
        local name = text.autoName(N.Bits(p.id), p.z)
        rows[i] = {
            id = "wownav:node:" .. p.id, n = name, search = lower(name .. " " .. L["automatic"]),
            x = p.x, y = p.y, z = p.z, nodeId = p.id, distance = p.distance,
        }
    end
    return rows
end

-- The target contract of a row for the resolver (TargetCatalog.Validate).
function catalog.contract(r, map)
    return {
        id = r.tid, kind = r.kind, nameEn = r.nameEn or r.n, nativeMapId = map, coordinateSpace = "world",
        x = r.x, y = r.y, z = r.z, zStatus = r.z == nil and "unknown" or "known", levels = r.levels,
        surface = r.surface,
    }
end
