local module = WowVision.base.windows:createModule("colorPicker")
local L = module.L
module:setLabel(L["Color Picker"])

local graph = WowVision.graph
local nodes = graph.nodes
local ControlId = graph.ControlId
local colors = WowVision.colors

-- The game's colour picker, opened by colour swatches in the settings
-- window and elsewhere. Its colour wheel and value bar are one mouse-only
-- widget (a ColorSelect), so the screen drives that widget through
-- synthetic controls instead: red, green and blue as numbers 0 to 255,
-- opacity as a percentage when the caller allows it, then retail's hex
-- box and the Okay and Cancel buttons. The current and original colours
-- read as spoken descriptions ("dark grayish blue, Slate Gray"), and each
-- channel repeats the description after its number so adjusting a
-- channel says what the colour has become.
--
-- Retail keeps the widget at Content.ColorPicker and its opacity on the
-- widget's alpha; classic pickers ARE the widget and keep opacity on the
-- OpacitySliderFrame slider beside the swatch. Setting a colour on the
-- widget fires its OnColorSelect, which updates the swatch, the hex box
-- and the caller's swatchFunc, exactly as a mouse drag would.

local function colorWidget(frame)
    local content = frame.Content
    if content ~= nil and content.ColorPicker ~= nil then
        return content.ColorPicker
    end
    return frame
end

local function currentRGB(frame)
    local widget = colorWidget(frame)
    if widget.GetColorRGB == nil then
        return 0, 0, 0
    end
    return widget:GetColorRGB()
end

local function setRGB(frame, r, g, b)
    local widget = colorWidget(frame)
    if widget.SetColorRGB ~= nil then
        widget:SetColorRGB(r, g, b)
    end
end

local function opacitySlider(frame)
    local slider = rawget(_G, "OpacitySliderFrame")
    if slider ~= nil and slider:IsShown() and slider:GetParent() == frame then
        return slider
    end
    return nil
end

local function hasOpacity(frame)
    return frame.hasOpacity and true or false
end

-- Opacity as 0..1 where 1 is opaque, matching the value the picker hands
-- to the caller's opacityFunc.
local function currentOpacity(frame)
    local slider = opacitySlider(frame)
    if slider ~= nil then
        return slider:GetValue()
    end
    local widget = colorWidget(frame)
    if widget.GetColorAlpha ~= nil then
        return widget:GetColorAlpha()
    end
    return frame.opacity or 1
end

local function setOpacity(frame, opacity)
    local slider = opacitySlider(frame)
    if slider ~= nil then
        slider:SetValue(opacity)
        return
    end
    local widget = colorWidget(frame)
    if widget.SetColorAlpha ~= nil then
        widget:SetColorAlpha(opacity)
    end
end

local function to255(value)
    return math.floor((value or 0) * 255 + 0.5)
end

local function clamp(value, low, high)
    if value < low then
        return low
    elseif value > high then
        return high
    end
    return value
end

local function describeCurrent(frame)
    return colors.text(currentRGB(frame))
end

local function describeOriginal(frame)
    local previous = frame.previousValues
    if previous ~= nil and previous.r ~= nil then
        return colors.text(previous.r, previous.g, previous.b)
    end
    return nil
end

local CHANNELS = {
    { key = "red", label = "Red", index = 1 },
    { key = "green", label = "Green", index = 2 },
    { key = "blue", label = "Blue", index = 3 },
}

local function channelNode(frame, channel)
    local function get()
        local rgb = { currentRGB(frame) }
        return to255(rgb[channel.index])
    end
    return nodes.number({
        label = L[channel.label],
        get = get,
        set = function(value)
            if type(value) ~= "number" then
                error("not a number")
            end
            local rgb = { currentRGB(frame) }
            rgb[channel.index] = clamp(math.floor(value + 0.5), 0, 255) / 255
            setRGB(frame, rgb[1], rgb[2], rgb[3])
        end,
        valueText = function()
            return tostring(get()) .. ", " .. describeCurrent(frame)
        end,
    })
end

local function opacityNode(frame)
    local function get()
        return math.floor(currentOpacity(frame) * 100 + 0.5)
    end
    return nodes.number({
        label = L["Opacity"],
        get = get,
        set = function(value)
            if type(value) ~= "number" then
                error("not a number")
            end
            setOpacity(frame, clamp(math.floor(value + 0.5), 0, 100) / 100)
        end,
        step = 5,
        largeStep = 25,
        valueText = function()
            return tostring(get()) .. " " .. L["Percent"]
        end,
    })
end

local function render(builder, screen)
    local frame = ColorPickerFrame
    if frame == nil or not frame:IsShown() then
        return
    end

    builder:beginStop("current")
    builder:addItem(
        ControlId.structural("current"),
        nodes.text({
            label = function()
                return L["Current Color"] .. ": " .. describeCurrent(frame)
            end,
            live = "focus",
        })
    )
    if describeOriginal(frame) ~= nil then
        builder:beginStop("original")
        builder:addItem(
            ControlId.structural("original"),
            nodes.text({
                label = function()
                    return L["Original Color"] .. ": " .. (describeOriginal(frame) or "")
                end,
            })
        )
    end

    for _, channel in ipairs(CHANNELS) do
        builder:beginStop(channel.key)
        builder:addItem(ControlId.structural(channel.key), channelNode(frame, channel))
    end
    if hasOpacity(frame) then
        builder:beginStop("opacity")
        builder:addItem(ControlId.structural("opacity"), opacityNode(frame))
    end

    local content = frame.Content
    local hexBox = content ~= nil and content.HexBox or nil
    if hexBox ~= nil and hexBox:IsShown() then
        builder:beginStop("hex")
        builder:addItem(ControlId.forObject(hexBox), nodes.proxyEditBox({ editBox = hexBox, label = L["Hex Color"] }))
    end

    local footer = frame.Footer
    local okay = footer ~= nil and footer.OkayButton or ColorPickerOkayButton
    local cancel = footer ~= nil and footer.CancelButton or ColorPickerCancelButton
    builder:beginStop("buttons")
    builder:pushContext("buttons", L["Color Picker"])
    builder:startRow()
    if okay ~= nil then
        builder:addItem(ControlId.forObject(okay), nodes.proxyButton({ target = okay }))
    end
    if cancel ~= nil then
        builder:addItem(ControlId.forObject(cancel), nodes.proxyButton({ target = cancel }))
    end
    builder:endRow()
    builder:popContext()
end

module:registerWindow({
    type = "FrameWindow",
    name = "ColorPickerFrame",
    frameName = "ColorPickerFrame",
    graphScreen = { render = render },
})
