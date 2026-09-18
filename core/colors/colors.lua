local L = WowVision:getLocale()

-- Colour naming for speech. Two layers:
--
-- 1. describe(r, g, b): a systematic name in the ISCC-NBS style, built from
--    a hue word and lightness/chroma modifiers ("dark grayish blue", "vivid
--    orange", "light brown"). Computed from CIELAB, so it never fails and
--    it localises with a few dozen words instead of a name list.
-- 2. nearestName(r, g, b): the closest entry in the Name That Color list
--    (core/colors/names.lua, 1,566 names), matched in CIELAB so "closest"
--    agrees with the eye rather than with RGB distance.
--
-- text(r, g, b) joins the two: "Dark grayish blue, Slate". Inputs are 0..1
-- floats like every WoW colour API; describe255/text255 take 0..255.

local colors = WowVision.colors or {}
WowVision.colors = colors

-- ---- colour space ----

local function channelToLinear(c)
    if c <= 0.04045 then
        return c / 12.92
    end
    return ((c + 0.055) / 1.055) ^ 2.4
end

local function labF(t)
    if t > 0.008856 then
        return t ^ (1 / 3)
    end
    return 7.787 * t + 16 / 116
end

-- sRGB (0..1) to CIELAB under D65.
function colors.rgbToLab(r, g, b)
    local rl, gl, bl = channelToLinear(r), channelToLinear(g), channelToLinear(b)
    local x = (rl * 0.4124564 + gl * 0.3575761 + bl * 0.1804375) / 0.95047
    local y = rl * 0.2126729 + gl * 0.7151522 + bl * 0.0721750
    local z = (rl * 0.0193339 + gl * 0.1191920 + bl * 0.9503041) / 1.08883
    local fx, fy, fz = labF(x), labF(y), labF(z)
    return 116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)
end

-- HSV hue (degrees) and saturation from sRGB.
function colors.rgbToHsv(r, g, b)
    local max = math.max(r, g, b)
    local min = math.min(r, g, b)
    local delta = max - min
    local hue = 0
    if delta > 0 then
        if max == r then
            hue = 60 * (((g - b) / delta) % 6)
        elseif max == g then
            hue = 60 * ((b - r) / delta + 2)
        else
            hue = 60 * ((r - g) / delta + 4)
        end
    end
    local saturation = max > 0 and delta / max or 0
    return hue, saturation, max
end

local function hsvToRgb(hue, saturation, value)
    local c = value * saturation
    local x = c * (1 - math.abs((hue / 60) % 2 - 1))
    local m = value - c
    local r, g, b
    if hue < 60 then
        r, g, b = c, x, 0
    elseif hue < 120 then
        r, g, b = x, c, 0
    elseif hue < 180 then
        r, g, b = 0, c, x
    elseif hue < 240 then
        r, g, b = 0, x, c
    elseif hue < 300 then
        r, g, b = x, 0, c
    else
        r, g, b = c, 0, x
    end
    return r + m, g + m, b + m
end

-- ---- systematic description ----

-- Hue families by HSV hue, in degrees. Each band names the hue word used
-- for ordinary lightness and the family word that replaces it when the
-- colour falls into the pink, brown or olive regions.
local HUES = {
    { limit = 10, name = "red", light = "pink" },
    { limit = 22, name = "reddish orange", dark = "reddish brown", darkBelow = 70, light = "pink" },
    { limit = 40, name = "orange", dark = "brown", darkBelow = 75 },
    { limit = 52, name = "orange yellow", dark = "yellowish brown", darkBelow = 75 },
    { limit = 66, name = "yellow", dark = "olive", darkBelow = 60 },
    { limit = 80, name = "greenish yellow", dark = "olive", darkBelow = 60 },
    { limit = 100, name = "yellow green", dark = "olive green", darkBelow = 55 },
    { limit = 130, name = "yellowish green" },
    { limit = 160, name = "green" },
    { limit = 185, name = "bluish green" },
    { limit = 205, name = "greenish blue" },
    { limit = 255, name = "blue" },
    { limit = 275, name = "purplish blue" },
    { limit = 290, name = "violet" },
    { limit = 320, name = "purple" },
    { limit = 332, name = "reddish purple", light = "purplish pink" },
    { limit = 345, name = "purplish red", light = "pink" },
    { limit = 360, name = "red", light = "pink" },
}

local function hueBand(hue)
    for _, band in ipairs(HUES) do
        if hue < band.limit then
            return band
        end
    end
    return HUES[#HUES]
end

-- Largest CIELAB chroma this hue reaches in sRGB, so chroma tiers are
-- relative to what the hue can do: pure cyan is far less chromatic in Lab
-- than pure blue, yet both should read as vivid.
local maxChromaCache = {}
local function maxChromaFor(hue)
    local key = math.floor(hue)
    local cached = maxChromaCache[key]
    if cached ~= nil then
        return cached
    end
    local best = 0
    for value = 0.5, 1.0, 0.125 do
        local r, g, b = hsvToRgb(key, 1, value)
        local _, a, bb = colors.rgbToLab(r, g, b)
        local chroma = math.sqrt(a * a + bb * bb)
        if chroma > best then
            best = chroma
        end
    end
    maxChromaCache[key] = best
    return best
end

-- Lightness tiers (Lab L, roughly ten times Munsell value): 1 very light,
-- 2 light, 3 medium, 4 dark, 5 very dark. `shift` moves the boundaries for
-- families that are inherently dark (brown, olive) or light (pink).
local function lightnessTier(lightness, shift)
    lightness = lightness + (shift or 0)
    if lightness >= 85 then
        return 1
    elseif lightness >= 65 then
        return 2
    elseif lightness >= 45 then
        return 3
    elseif lightness >= 25 then
        return 4
    end
    return 5
end

local NEUTRALS = { "white", "light gray", "gray", "dark gray", "black" }

-- Modifier grids per chroma tier, indexed by lightness tier.
local LOW_CHROMA = { "very pale", "pale", "grayish", "dark grayish", "blackish" }
local MODERATE_CHROMA = { "very light", "light", "moderate", "dark", "very dark" }
local HIGH_CHROMA = { "brilliant", "brilliant", "strong", "deep", "very deep" }

local function joinWords(modifier, hue)
    if modifier == nil or modifier == "" then
        return L[hue]
    end
    return string.format(L["%s %s"], L[modifier], L[hue])
end

-- Systematic name for an sRGB colour (0..1 channels).
function colors.describe(r, g, b)
    local lightness, a, bb = colors.rgbToLab(r, g, b)
    local chroma = math.sqrt(a * a + bb * bb)
    if chroma < 6 then
        return L[NEUTRALS[lightnessTier(lightness)]]
    end

    local hue = colors.rgbToHsv(r, g, b)
    local band = hueBand(hue)
    local relative = chroma / maxChromaFor(hue)

    -- Family overrides: the light reds are pinks, the darker oranges are
    -- browns, the dark yellows are olives. Vivid colours keep their hue.
    local name = band.name
    local shift = 0
    if relative < 0.85 then
        if band.light ~= nil and lightness >= 60 then
            name = band.light
            shift = -20
        elseif band.dark ~= nil and lightness < band.darkBelow then
            name = band.dark
            shift = 20
        end
    end
    local darkFamily = name == band.dark

    local tier = lightnessTier(lightness, shift)
    if darkFamily and tier < 2 then
        -- Light brown is as light as brown gets.
        tier = 2
    end
    local modifier
    if relative >= 0.85 and chroma >= 40 then
        modifier = "vivid"
    elseif relative >= 0.55 and chroma >= 30 then
        modifier = HIGH_CHROMA[tier]
        -- Browns and olives are never brilliant: ISCC calls the bright
        -- ones strong.
        if darkFamily and modifier == "brilliant" then
            modifier = "strong"
        end
    elseif relative >= 0.25 or chroma >= 22 then
        modifier = MODERATE_CHROMA[tier]
        if modifier == "moderate" then
            modifier = nil
        end
    else
        modifier = LOW_CHROMA[tier]
    end
    return joinWords(modifier, name)
end

-- ---- nearest named colour ----

local labNames = nil
local function buildLabNames()
    labNames = {}
    for index, entry in ipairs(colors.names or {}) do
        local packed = entry[1]
        local r = math.floor(packed / 65536) % 256
        local g = math.floor(packed / 256) % 256
        local b = packed % 256
        local l, a, bb = colors.rgbToLab(r / 255, g / 255, b / 255)
        labNames[index] = { l, a, bb, entry[2] }
    end
end

local nearestCache = {}
local nearestCacheSize = 0

-- Closest Name That Color entry for an sRGB colour (0..1 channels).
function colors.nearestName(r, g, b)
    local key = math.floor(r * 255 + 0.5) * 65536 + math.floor(g * 255 + 0.5) * 256 + math.floor(b * 255 + 0.5)
    local cached = nearestCache[key]
    if cached ~= nil then
        return cached
    end
    if labNames == nil then
        buildLabNames()
    end
    local l, a, bb = colors.rgbToLab(r, g, b)
    local bestName, bestDistance = nil, math.huge
    for _, entry in ipairs(labNames) do
        local dl, da, db = entry[1] - l, entry[2] - a, entry[3] - bb
        local distance = dl * dl + da * da + db * db
        if distance < bestDistance then
            bestDistance = distance
            bestName = entry[4]
        end
    end
    if nearestCacheSize >= 512 then
        nearestCache = {}
        nearestCacheSize = 0
    end
    nearestCache[key] = bestName
    nearestCacheSize = nearestCacheSize + 1
    return bestName
end

-- Speech text: the systematic description, then the nearest name when it
-- adds something.
function colors.text(r, g, b)
    local description = colors.describe(r, g, b)
    local name = colors.nearestName(r, g, b)
    if name == nil or name:lower() == description:lower() then
        return description
    end
    return description .. ", " .. name
end

function colors.text255(r, g, b)
    return colors.text(r / 255, g / 255, b / 255)
end

function colors.describe255(r, g, b)
    return colors.describe(r / 255, g / 255, b / 255)
end
