local module = WowVision.base.windows:createModule("channels")
local L = module.L
module:setLabel(L["Chat Channels"])

local graph = WowVision.graph
local nodes = graph.nodes
local ControlId = graph.ControlId
local kinds = graph.kinds

-- The chat channels window (ChannelFrame, Blizzard_Channels): opened by the
-- channel button on the chat frame, the Toggle Chat Tab key, or a shift
-- click on a channel name in chat. On the left the channel list, grouped
-- under headers (group, global, custom, communities); on the right the
-- members of the selected channel, owner and moderators marked; at the
-- bottom Add (a new custom channel) and Settings (voice chat).
--
-- Everything goes through the game: a left click on a channel selects it
-- and the member list follows; a left click on a header folds it; a right
-- click on a channel opens its menu (leave, join, password, invite), a right
-- click on a member opens the player menu. Both menus are the game's own,
-- read by the dropdown watcher. The voice chat parts (the headset button on
-- a channel, mute and deafen on members) are left out.

local function plainText(text)
    if text == nil then
        return nil
    end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return strtrim(text)
end

-- What a channel button IS, stable while the list rebuilds: the list
-- releases and reacquires its pooled buttons on every update, so a button
-- frame can hold another channel a moment later.
local function buttonKey(button)
    if button:IsHeader() then
        return "header:" .. tostring(button:GetCategory())
    end
    return "channel:" .. tostring(button:GetCategory()) .. ":" .. tostring(button:GetChannelName())
end

-- The button currently showing the channel or header with this key.
local function findButton(list, key)
    for _, button in ipairs(list.buttons or {}) do
        if button:IsShown() and buttonKey(button) == key then
            return button
        end
    end
    return nil
end

local function renderChannelList(builder, list)
    builder:beginStop("channelList")
    builder:pushContext("channelList", L["Channels"])
    for _, button in ipairs(list.buttons or {}) do
        if button:IsShown() then
            local key = buttonKey(button)
            local target = function()
                return findButton(list, key)
            end
            local announcements = {
                {
                    text = function()
                        local current = target()
                        return current ~= nil and plainText(current:GetText()) or nil
                    end,
                    kind = kinds.label,
                },
            }
            if button:IsHeader() then
                tinsert(announcements, {
                    text = function()
                        local current = target()
                        if current == nil or current:GetMemberCount() == 0 then
                            return nil
                        end
                        return current:IsCollapsed() and L["Collapsed"] or L["Expanded"]
                    end,
                    kind = kinds.value,
                    live = "focus",
                })
            else
                tinsert(announcements, {
                    text = function()
                        local current = target()
                        if current ~= nil and list:GetSelectedChannelButton() == current then
                            return L["selected"]
                        end
                        return nil
                    end,
                    kind = kinds.selected,
                    live = "focus",
                })
                -- A channel the player left reads greyed out and takes no clicks.
                tinsert(announcements, {
                    text = function()
                        local current = target()
                        if current ~= nil and not current:IsEnabled() then
                            return L["Disabled"]
                        end
                        return nil
                    end,
                    kind = kinds.enabled,
                })
            end
            local vtable = {
                controlType = graph.controlTypes.button,
                announcements = announcements,
                bindings = {
                    { binding = "leftClick", type = "Click", emulatedKey = "LeftButton", target = target },
                    { binding = "rightClick", type = "Click", emulatedKey = "RightButton", target = target },
                },
                contextActions = nodes.proxyContextActions(target),
            }
            nodes.attachScrollFrame(vtable, list, target)
            builder:addItem(ControlId.structural(key), vtable)
        end
    end
    builder:popContext()
end

-- The members of the selected channel, from the same sources the roster
-- fills its rows from: the chat channel roster, a community stream's
-- members, or a voice channel's members.
local function rosterMembers(channel)
    local members = {}
    if channel == nil then
        return members
    end
    if channel:ChannelIsCommunity() then
        if CommunitiesUtil ~= nil and C_Club.AreMembersReady(channel.clubId) then
            for _, info in ipairs(CommunitiesUtil.GetAndSortMemberInfo(channel.clubId, channel.streamId)) do
                tinsert(members, {
                    name = info.name,
                    owner = info.role == Enum.ClubRoleIdentifier.Owner or info.role == Enum.ClubRoleIdentifier.Leader,
                    moderator = info.role == Enum.ClubRoleIdentifier.Moderator,
                    offline = info.presence == Enum.ClubMemberPresence.Offline,
                })
            end
        end
    elseif channel:ChannelSupportsText() then
        local channelID = channel:GetChannelID()
        local count = select(5, GetChannelDisplayInfo(channelID)) or 0
        for index = 1, count do
            local name, owner, moderator, guid = C_ChatInfo.GetChannelRosterInfo(channelID, index)
            local offline = false
            if guid ~= nil then
                offline = C_PlayerInfo.IsConnected(PlayerLocation:CreateFromGUID(guid)) == false
            end
            members[index] = { name = name, owner = owner, moderator = moderator, offline = offline }
        end
    else
        local voiceChannel = channel:GetVoiceChannelID() ~= nil and C_VoiceChat.GetChannel(channel:GetVoiceChannelID())
            or nil
        for _, member in ipairs(voiceChannel ~= nil and voiceChannel.members or {}) do
            tinsert(members, { name = member.name })
        end
    end
    return members
end

local function memberLabel(member)
    if member == nil or member.name == nil then
        return RETRIEVING_DATA
    end
    local parts = { member.name }
    if member.owner then
        tinsert(parts, L["Owner"])
    elseif member.moderator then
        tinsert(parts, L["Moderator"])
    end
    if member.offline then
        tinsert(parts, L["Offline"])
    end
    return table.concat(parts, ", ")
end

local function renderMembers(builder, frame)
    local roster = frame.ChannelRoster
    if roster == nil or roster.ScrollBox == nil then
        return
    end
    local channel = frame.ChannelList:GetSelectedChannelButton()
    local members = rosterMembers(channel)
    local channelName = channel ~= nil and channel:GetChannelName() or nil
    builder:beginStop("members")
    nodes.scrollBoxList(builder, {
        scrollBox = roster.ScrollBox,
        key = "members",
        label = channelName ~= nil and nodes.joinLabel(L["Members"], channelName) or L["Members"],
        id = function(data, index)
            local member = members[index]
            return ControlId.structural("member:" .. tostring(member ~= nil and member.name or index))
        end,
        rowLabel = function(data, index)
            return memberLabel(members[index])
        end,
    })
end

local function render(builder, screen)
    local frame = ChannelFrame
    if frame == nil or not frame:IsShown() or frame.ChannelList == nil then
        return
    end
    builder:pushContext("channelFrame", CHAT_CHANNELS or L["Chat Channels"])
    renderChannelList(builder, frame.ChannelList)
    renderMembers(builder, frame)
    for _, button in ipairs({ frame.NewButton, frame.SettingsButton }) do
        builder:beginStop("button:" .. tostring(button:GetParentKey()))
        builder:addItem(ControlId.forObject(button), nodes.proxyButton({ target = button }))
    end
    builder:popContext()
end

module:registerWindow({
    type = "FrameWindow",
    name = "ChannelFrame",
    frameName = "ChannelFrame",
    graphScreen = { render = render },
})

-- The new channel box (Add): name and password, OK and Cancel. It opens on
-- the name box, which takes typing at once; Enter in either box creates the
-- channel, as the game's own boxes do.
local function renderCreatePopup(builder, screen)
    local popup = CreateChannelPopup
    if popup == nil or not popup:IsShown() then
        return
    end
    builder:pushContext("createChannel", CHANNEL_NEW_CHANNEL or L["Chat Channels"])
    for _, editBox in ipairs({ popup.Name, popup.Password }) do
        builder:beginStop("edit:" .. tostring(editBox:GetParentKey()))
        builder:addItem(
            ControlId.forObject(editBox),
            nodes.proxyEditBox({ editBox = editBox, label = editBox.Label ~= nil and editBox.Label:GetText() or nil })
        )
    end
    if popup.UseVoiceChat ~= nil and popup.UseVoiceChat:IsShown() then
        builder:beginStop("voiceChat")
        builder:addItem(
            ControlId.forObject(popup.UseVoiceChat),
            nodes.proxyCheckButton({ target = popup.UseVoiceChat, label = popup.UseVoiceChat.Text:GetText() })
        )
    end
    for _, button in ipairs({ popup.OKButton, popup.CancelButton }) do
        builder:beginStop("button:" .. tostring(button:GetParentKey()))
        builder:addItem(ControlId.forObject(button), nodes.proxyButton({ target = button }))
    end
    builder:popContext()
end

module:registerWindow({
    type = "FrameWindow",
    name = "CreateChannelPopup",
    frameName = "CreateChannelPopup",
    graphScreen = { render = renderCreatePopup },
})
