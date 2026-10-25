local TooltipReader = WowVision.Class("TooltipReader")

function TooltipReader:initialize() end

function TooltipReader:getLine(frame, index)
    if not frame or index < 1 or index > frame:NumLines() then
        return nil, nil
    end
    local left = _G[frame:GetName() .. "TextLeft" .. index]
    local right = _G[frame:GetName() .. "TextRight" .. index]
    if not left and not right then
        return nil, nil
    end
    return left:GetText(), right:GetText()
end

-- Either side may be a secret string (hidden unit identities on Forever and
-- Retail): no comparison on it, but concatenation carries it through and
-- speech accepts the result.
function TooltipReader:formatLine(left, right)
    local hasText = WowVision.secrets.hasText
    local hasLeft, hasRight = hasText(left), hasText(right)
    if hasLeft and hasRight then
        return left .. " " .. right
    elseif hasLeft then
        return left
    elseif hasRight then
        return right
    end
    return ""
end

-- Joins lines with newlines by concatenation: table.concat refuses secret
-- strings.
function TooltipReader:joinLines(lines)
    return WowVision.secrets.join(lines, "\n")
end

function TooltipReader:getText(frame, lineNumber)
    if not frame then
        return ""
    end
    local lines = {}
    if lineNumber == nil then
        for l = 1, frame:NumLines() do
            local left, right = self:getLine(frame, l)
            tinsert(lines, self:formatLine(left, right))
        end
    else
        local left, right = self:getLine(frame, lineNumber)
        tinsert(lines, self:formatLine(left, right))
    end
    return self:joinLines(lines)
end

WowVision.TooltipReader = TooltipReader
