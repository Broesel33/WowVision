local module = WowVision.base.windows:createModule("friends")
local L = module.L
module:setLabel(L["Friends"])

local graph = WowVision.graph
local nodes = graph.nodes
local ControlId = graph.ControlId
local kinds = graph.kinds

-- WoW: Forever's social window (FriendsFrame): the modern friends window in
-- a build of its own. Three tabs at the bottom -- Contacts, Raid, Quick
-- Join (the who list lives in the group finder, camelot/lfg.lua) -- and on
-- Contacts the friends list with its Battle.net bar. The ignore list, the
-- broadcast box, the raid info and Add Friend are windows of their own.
--
-- Everything goes through the game, as in classic/friends.lua: Enter on a
-- row is a left click (select), Backspace a right click (the game's player
-- menu); the buttons around the list act on the selection. A friend row's
-- own invite and summon buttons are in its context menu.

local function plainText(text)
    if text == nil then
        return nil
    end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|A.-|a", ""):gsub("|T.-|t", "")
    text = strtrim(text)
    if text == "" then
        return nil
    end
    return text
end

local function fontText(fontString)
    return function()
        return fontString ~= nil and plainText(fontString:GetText()) or nil
    end
end

local function selectedPart(isSelected)
    return {
        text = function()
            return isSelected() and L["selected"] or nil
        end,
        kind = kinds.selected,
        live = "focus",
    }
end

-- A button inside a scroll row, resolved through the row frame at click
-- time: rows are pooled, so the child belongs to whatever row shows the
-- element now.
local function rowChild(helpers, key)
    return function()
        local row = helpers.target()
        local child = row ~= nil and row[key] or nil
        if child ~= nil and child:IsShown() then
            return child
        end
        return nil
    end
end

local function clickBindings(target)
    return {
        { binding = "leftClick", type = "Click", emulatedKey = "LeftButton", target = target },
        { binding = "rightClick", type = "Click", emulatedKey = "RightButton", target = target },
    }
end

-- ---------------------------------------------------------------------------
-- Friends list
-- ---------------------------------------------------------------------------

-- What a row reads, from the same data the row fills itself from
-- (FriendsFrame_UpdateFriendButton): name, status, where they are, note.
local function wowFriendParts(id)
    local info = C_FriendList.GetFriendInfoByIndex(id)
    if info == nil then
        return { label = UNKNOWN }
    end
    local parts = {}
    if info.connected then
        parts.label = info.name .. ", " .. format(FRIENDS_LEVEL_TEMPLATE, info.level, info.className)
        if info.afk then
            parts.status = FRIENDS_LIST_AWAY
        elseif info.dnd then
            parts.status = FRIENDS_LIST_BUSY
        end
        parts.info = info.area
    else
        parts.label = info.name
        parts.status = FRIENDS_LIST_OFFLINE
    end
    if info.notes ~= nil and info.notes ~= "" then
        parts.note = L["Note"] .. " " .. info.notes
    end
    return parts
end

local function bnetFriendParts(id)
    local accountInfo = C_BattleNet.GetFriendAccountInfo(id)
    if accountInfo == nil then
        return { label = UNKNOWN }
    end
    local gameInfo = accountInfo.gameAccountInfo
    local parts = {}
    parts.label = plainText((FriendsFrame_GetBNetAccountNameAndStatus(accountInfo))) or UNKNOWN
    if gameInfo.isOnline then
        if accountInfo.isAFK or gameInfo.isGameAFK then
            parts.status = FRIENDS_LIST_AWAY
        elseif accountInfo.isDND or gameInfo.isGameBusy then
            parts.status = FRIENDS_LIST_BUSY
        end
        local sameGame = gameInfo.clientProgram == BNET_CLIENT_WOW and gameInfo.wowProjectID == WOW_PROJECT_ID
        if sameGame and gameInfo.areaName ~= nil and gameInfo.areaName ~= "" then
            parts.info = gameInfo.areaName
        else
            parts.info = gameInfo.richPresence
        end
    else
        parts.status = FriendsFrame_GetLastOnlineText(accountInfo)
    end
    if accountInfo.isFavorite then
        parts.favorite = L["Favorite"]
    end
    local notes = {}
    if accountInfo.note ~= nil and accountInfo.note ~= "" then
        tinsert(notes, L["Note"] .. " " .. accountInfo.note)
    end
    if accountInfo.customMessage ~= nil and accountInfo.customMessage ~= "" then
        tinsert(notes, accountInfo.customMessage)
    end
    if #notes > 0 then
        parts.note = table.concat(notes, ", ")
    end
    return parts
end

local function friendParts(data)
    if data.buttonType == FRIENDS_BUTTON_TYPE_WOW then
        return wowFriendParts(data.id)
    end
    return bnetFriendParts(data.id)
end

-- A stable id per person: focus follows the friend, not the list slot, when
-- someone logging on or off reorders the list.
local function friendId(data)
    if data.buttonType == FRIENDS_BUTTON_TYPE_WOW then
        local info = C_FriendList.GetFriendInfoByIndex(data.id)
        return ControlId.structural("friend:wow:" .. tostring(info ~= nil and info.name or data.id))
    end
    local accountInfo = C_BattleNet.GetFriendAccountInfo(data.id)
    return ControlId.structural("friend:bnet:" .. tostring(accountInfo ~= nil and accountInfo.battleTag or data.id))
end

local function emitFriend(builder, data, helpers)
    local function part(key, kind)
        return {
            text = function()
                return friendParts(data)[key]
            end,
            kind = kind,
        }
    end
    local invite = rowChild(helpers, "travelPassButton")
    local summon = rowChild(helpers, "summonButton")
    local rowActions = nodes.proxyContextActions(helpers.target)
    builder:addItem(friendId(data), {
        controlType = graph.controlTypes.button,
        announcements = {
            part("label", kinds.label),
            part("favorite", kinds.value),
            part("status", kinds.value),
            part("info", kinds.value),
            part("note", kinds.value),
            selectedPart(function()
                return FriendsFrame.selectedFriendType == data.buttonType and FriendsFrame.selectedFriend == data.id
            end),
        },
        bindings = clickBindings(helpers.target),
        -- The row's invite button (Battle.net friends) and summon button
        -- (Recruit a Friend) sit on its right edge.
        contextActions = function(add)
            local inviteButton = invite()
            if inviteButton ~= nil then
                add({
                    label = L["Invite"],
                    click = { emulatedKey = "LeftButton", target = invite },
                })
            end
            if summon() ~= nil then
                add({
                    label = L["Summon"],
                    click = { emulatedKey = "LeftButton", target = summon },
                })
            end
            rowActions(add)
        end,
        onFocus = helpers.onFocus,
        onFocusTick = helpers.onFocusTick,
        onUnfocus = helpers.onUnfocus,
        tooltipFrame = helpers.target,
    })
end

-- A friend request: the requester, then Accept and Decline (a menu:
-- decline, report, block) on the row's right, the row's own buttons.
local function emitInvite(builder, data, helpers)
    local inviteIndex = data.id
    local function inviteName()
        local inviteInfo = C_BattleNet.GetFriendInviteInfo(inviteIndex)
        return inviteInfo ~= nil and inviteInfo.accountName or nil
    end
    local key = "invite:" .. tostring(inviteName() or inviteIndex)
    local accept = rowChild(helpers, "AcceptButton")
    local decline = rowChild(helpers, "DeclineButton")
    builder:pushContext(key, L["Friend request"])
    builder:startRow()
    builder:addItem(ControlId.structural(key), {
        controlType = graph.controlTypes.text,
        announcements = { { text = inviteName, kind = kinds.label } },
        onFocus = helpers.onFocus,
        onFocusTick = helpers.onFocusTick,
        onUnfocus = helpers.onUnfocus,
    })
    builder:addItem(ControlId.structural(key .. ":accept"), {
        controlType = graph.controlTypes.button,
        announcements = { { text = ACCEPT, kind = kinds.label } },
        bindings = { { binding = "leftClick", type = "Click", emulatedKey = "LeftButton", target = accept } },
        onFocus = helpers.onFocus,
        onFocusTick = helpers.onFocusTick,
    })
    builder:addItem(ControlId.structural(key .. ":decline"), {
        controlType = graph.controlTypes.dropdown,
        announcements = { { text = DECLINE, kind = kinds.label } },
        onActivate = function()
            local button = decline()
            if button ~= nil then
                nodes.openDropdown(button)
            end
        end,
        onFocus = helpers.onFocus,
        onFocusTick = helpers.onFocusTick,
    })
    builder:endRow()
    builder:popContext()
end

local function emitFriendRow(builder, data, index, helpers)
    local buttonType = data.buttonType
    if buttonType == FRIENDS_BUTTON_TYPE_WOW or buttonType == FRIENDS_BUTTON_TYPE_BNET then
        emitFriend(builder, data, helpers)
    elseif buttonType == FRIENDS_BUTTON_TYPE_INVITE then
        emitInvite(builder, data, helpers)
    elseif buttonType == FRIENDS_BUTTON_TYPE_INVITE_HEADER then
        -- "Friend Requests (N)": a left click folds the requests.
        builder:addItem(ControlId.structural("friend:inviteHeader"), {
            controlType = graph.controlTypes.button,
            announcements = {
                {
                    text = function()
                        return format(FRIEND_REQUESTS, BNGetNumFriendInvites())
                    end,
                    kind = kinds.label,
                },
                {
                    text = function()
                        return GetCVarBool("friendInvitesCollapsed") and L["Collapsed"] or L["Expanded"]
                    end,
                    kind = kinds.value,
                    live = "focus",
                },
            },
            bindings = { { binding = "leftClick", type = "Click", emulatedKey = "LeftButton", target = helpers.target } },
            onFocus = helpers.onFocus,
            onFocusTick = helpers.onFocusTick,
            onUnfocus = helpers.onUnfocus,
        })
    end
    -- Dividers are lines between online and offline friends: nothing to read.
end

local function renderBattlenetBar(builder)
    local bar = FriendsFrameBattlenetFrame
    if bar == nil or not bar:IsShown() then
        return
    end
    builder:beginStop("battlenet")
    builder:pushContext("battlenet", L["Battle.net"])
    builder:startRow()
    if bar.Tag ~= nil and bar.Tag:IsShown() then
        builder:addItem(ControlId.structural("battlenet:tag"), nodes.text({ label = fontText(bar.Tag) }))
    elseif bar.UnavailableLabel ~= nil and bar.UnavailableLabel:IsShown() then
        builder:addItem(ControlId.structural("battlenet:unavailable"), nodes.text({ label = fontText(bar.UnavailableLabel) }))
    end
    local status = FriendsTabHeader.StatusDropdown
    if status ~= nil and status:IsShown() then
        local vtable = nodes.proxyDropdown({
            target = status,
            label = function()
                local bnStatus = FriendsTabHeader.bnStatus
                local current = FRIENDS_LIST_AVAILABLE
                if bnStatus == FRIENDS_TEXTURE_AFK then
                    current = FRIENDS_LIST_AWAY
                elseif bnStatus == FRIENDS_TEXTURE_DND then
                    current = FRIENDS_LIST_BUSY
                end
                return nodes.joinLabel(L["Status"], current)
            end,
        })
        if vtable ~= nil then
            builder:addItem(ControlId.forObject(status), vtable)
        end
    end
    -- The contacts menu: broadcast and the ignore list.
    if bar.ContactsMenuButton ~= nil and bar.ContactsMenuButton:IsShown() then
        local vtable = nodes.proxyDropdown({ target = bar.ContactsMenuButton, label = CONTACTS_MENU_NAME })
        if vtable ~= nil then
            builder:addItem(ControlId.forObject(bar.ContactsMenuButton), vtable)
        end
    end
    builder:endRow()
    builder:popContext()
end

local function renderFriendsList(builder)
    local frame = FriendsListFrame
    renderBattlenetBar(builder)

    builder:beginStop("list")
    nodes.scrollBoxList(builder, {
        scrollBox = frame.ScrollBox,
        key = "friends",
        label = FRIENDS_LIST,
        emit = emitFriendRow,
    })

    builder:beginStop("controls")
    builder:pushContext("controls", L["Controls"])
    builder:startRow()
    for _, button in ipairs({ FriendsFrameAddFriendButton, FriendsFrameSendMessageButton }) do
        local vtable = nodes.proxyButton({ target = button })
        if vtable ~= nil then
            builder:addItem(ControlId.forObject(button), vtable)
        end
    end
    builder:endRow()
    builder:popContext()
end

-- ---------------------------------------------------------------------------
-- Raid tab
-- ---------------------------------------------------------------------------

local function raidMemberLabel(index)
    local name, rank, _, level, class, _, zone, online, isDead, role = GetRaidRosterInfo(index)
    if name == nil then
        return UNKNOWN
    end
    local parts = { name }
    if level ~= nil and level > 0 then
        tinsert(parts, format(FRIENDS_LEVEL_TEMPLATE, level, class or ""))
    end
    if rank == 2 and RAID_LEADER ~= nil then
        tinsert(parts, RAID_LEADER)
    elseif rank == 1 and RAID_ASSISTANT ~= nil then
        tinsert(parts, RAID_ASSISTANT)
    end
    if role ~= nil and role ~= "NONE" and _G[role] ~= nil then
        tinsert(parts, _G[role])
    end
    if not online then
        tinsert(parts, FRIENDS_LIST_OFFLINE)
    elseif isDead then
        tinsert(parts, DEAD)
    end
    if zone ~= nil and zone ~= "" then
        tinsert(parts, zone)
    end
    return table.concat(parts, ", ")
end

-- The groups, one context each, members in raid order. A member's button
-- targets on a left click and opens the player menu on a right click.
-- Moving members between groups is drag and drop on screen and is left out.
local function renderRaidGroups(builder)
    local numMembers = GetNumGroupMembers()
    builder:beginStop("raidGroups")
    for group = 1, NUM_RAID_GROUPS or 8 do
        local members = {}
        for index = 1, numMembers do
            local _, _, subgroup = GetRaidRosterInfo(index)
            if subgroup == group then
                tinsert(members, index)
            end
        end
        if #members > 0 then
            builder:pushContext("raidGroup:" .. group, format(GROUP_NUMBER, group))
            for _, index in ipairs(members) do
                local button = _G["RaidGroupButton" .. index]
                if button ~= nil then
                    local captured = index
                    builder:addItem(ControlId.structural("raid:" .. tostring((GetRaidRosterInfo(index)))), {
                        controlType = graph.controlTypes.button,
                        announcements = {
                            {
                                text = function()
                                    return raidMemberLabel(captured)
                                end,
                                kind = kinds.label,
                            },
                        },
                        bindings = clickBindings(button),
                        contextActions = function(add)
                            add({ label = L["Left Click"], click = { emulatedKey = "LeftButton", target = button } })
                            add({ label = L["Right Click"], click = { emulatedKey = "RightButton", target = button } })
                        end,
                    })
                end
            end
            builder:popContext()
        end
    end
end

local function renderRaid(builder)
    if IsInRaid() and RaidGroup1 ~= nil then
        renderRaidGroups(builder)
    else
        builder:beginStop("raidDescription")
        builder:addItem(ControlId.structural("raid:description"), nodes.text({ label = RAID_DESCRIPTION }))
    end

    builder:beginStop("raidControls")
    builder:pushContext("raidControls", L["Controls"])
    builder:startRow()
    local allAssist = RaidFrameAllAssistCheckButton
    if allAssist ~= nil and allAssist:IsShown() then
        builder:addItem(
            ControlId.forObject(allAssist),
            nodes.proxyCheckButton({ target = allAssist, label = fontText(allAssist.text or allAssist.Text) })
        )
    end
    for _, button in ipairs({ RaidFrameConvertToRaidButton, RaidFrameRaidInfoButton }) do
        if button ~= nil then
            local vtable = nodes.proxyButton({ target = button })
            if vtable ~= nil then
                builder:addItem(ControlId.forObject(button), vtable)
            end
        end
    end
    builder:endRow()
    builder:popContext()
end

-- ---------------------------------------------------------------------------
-- Quick Join tab
-- ---------------------------------------------------------------------------

-- A group: the friends in it, then what it is queued for.
local function quickJoinLabel(entry)
    if type(entry) ~= "table" or entry.displayedMembers == nil then
        return UNKNOWN
    end
    local names = {}
    for _, member in ipairs(entry.displayedMembers) do
        local name = SocialQueueUtil_GetRelationshipInfo(member.guid, nil, member.clubId)
        tinsert(names, plainText(name) or UNKNOWN)
    end
    local parts = { table.concat(names, ", ") }
    for _, queue in ipairs(entry.displayedQueues or {}) do
        local queueName = SocialQueueUtil_GetQueueName(queue.queueData)
        if queueName ~= nil then
            tinsert(parts, plainText(queueName))
        end
    end
    if entry.CanJoin ~= nil and not entry:CanJoin() then
        tinsert(parts, L["Disabled"])
    end
    return table.concat(parts, ", ")
end

local function renderQuickJoin(builder)
    local frame = QuickJoinFrame
    builder:beginStop("quickJoin")
    nodes.scrollBoxList(builder, {
        scrollBox = frame.ScrollBox,
        key = "quickJoin",
        label = QUICK_JOIN,
        id = function(data, index)
            local guid = type(data) == "table" and data.GetGUID ~= nil and data:GetGUID() or index
            return ControlId.structural("quickJoin:" .. tostring(guid))
        end,
        row = function(data, index, helpers)
            return {
                controlType = graph.controlTypes.button,
                announcements = {
                    {
                        text = function()
                            return quickJoinLabel(data)
                        end,
                        kind = kinds.label,
                    },
                    selectedPart(function()
                        return type(data) == "table" and data.GetGUID ~= nil and frame:GetSelectedGroup() == data:GetGUID()
                    end),
                },
                bindings = clickBindings(helpers.target),
                contextActions = nodes.proxyContextActions(helpers.target),
                onFocus = helpers.onFocus,
                onFocusTick = helpers.onFocusTick,
                onUnfocus = helpers.onUnfocus,
                tooltipFrame = helpers.target,
            }
        end,
    })
    local join = frame.JoinQueueButton
    if join ~= nil then
        local vtable = nodes.proxyButton({ target = join })
        if vtable ~= nil then
            builder:beginStop("quickJoinButton")
            builder:addItem(ControlId.forObject(join), vtable)
        end
    end
end

-- ---------------------------------------------------------------------------
-- The window: the shown page, then the contacts sub-tabs, then the tabs.
-- ---------------------------------------------------------------------------

local function addTab(builder, tab, isSelected)
    if tab == nil or not tab:IsShown() then
        return
    end
    local vtable = nodes.proxyButton({ target = tab, label = fontText(tab.Text) })
    if vtable ~= nil then
        tinsert(vtable.announcements, selectedPart(isSelected))
        builder:addItem(ControlId.forObject(tab), vtable)
    end
end

-- Friends, Recent Allies, Recruit a Friend: read only when more than one
-- shows (the game hides the others on Forever).
local function renderSubTabs(builder)
    local header = FriendsTabHeader
    if header == nil or not header:IsShown() then
        return
    end
    local tabs = {}
    for _, tabID in ipairs({ header.friendsTabID, header.recentAlliesTabID, header.recruitAFriendTabID }) do
        local tab = tabID ~= nil and header:GetTabButton(tabID) or nil
        if tab ~= nil and tab:IsShown() then
            tinsert(tabs, { id = tabID, button = tab })
        end
    end
    if #tabs < 2 then
        return
    end
    builder:beginStop("subtabs")
    builder:pushContext("subtabs", L["Tabs"])
    builder:startRow()
    for _, entry in ipairs(tabs) do
        local captured = entry.id
        addTab(builder, entry.button, function()
            return header:GetTab() == captured
        end)
    end
    builder:endRow()
    builder:popContext()
end

local function renderTabs(builder)
    builder:beginStop("tabs")
    builder:pushContext("tabs", L["Tabs"])
    builder:startRow()
    for _, tab in ipairs({ FriendsFrameTab1, FriendsFrameTab3, FriendsFrameTab4 }) do
        local captured = tab
        addTab(builder, tab, function()
            return PanelTemplates_GetSelectedTab(FriendsFrame) == captured:GetID()
        end)
    end
    builder:endRow()
    builder:popContext()
end

local function render(builder, screen)
    local frame = FriendsFrame
    if frame == nil or not frame:IsShown() then
        return
    end
    builder:pushContext("friends", plainText(frame:GetTitleText():GetText()) or L["Friends"])

    if FriendsListFrame ~= nil and FriendsListFrame:IsShown() then
        renderFriendsList(builder)
    elseif RaidFrame ~= nil and RaidFrame:IsShown() then
        renderRaid(builder)
    elseif QuickJoinFrame ~= nil and QuickJoinFrame:IsShown() then
        renderQuickJoin(builder)
    else
        builder:beginStop("body")
        builder:addItem(ControlId.structural("unsupported"), nodes.text({ label = L["This tab is not supported yet"] }))
    end

    renderSubTabs(builder)
    renderTabs(builder)
    builder:popContext()
end

module:registerWindow({
    type = "FrameWindow",
    name = "friends",
    frameName = "FriendsFrame",
    conflictingAddons = { "Sku" },
    graphScreen = { render = render },
})

-- ---------------------------------------------------------------------------
-- The ignore list (from the contacts menu): ignored players and blocked
-- invites under their headers, Remove from Ignore for the selection.
-- ---------------------------------------------------------------------------

local function ignoreName(data)
    if data.squelchType == SQUELCH_TYPE_IGNORE then
        return C_FriendList.GetIgnoreName(data.index)
    end
    local _, blockName = BNGetBlockedInfo(data.index)
    return blockName
end

local function renderIgnoreList(builder, screen)
    local window = FriendsFrame ~= nil and FriendsFrame.IgnoreListWindow or nil
    if window == nil or not window:IsShown() then
        return
    end
    builder:pushContext("ignoreList", IGNORE_LIST)
    builder:beginStop("ignored")
    nodes.scrollBoxList(builder, {
        scrollBox = window.ScrollBox,
        key = "ignored",
        id = function(data, index)
            if data.header ~= nil then
                return ControlId.structural("ignore:header:" .. data.header)
            end
            return ControlId.structural("ignore:" .. tostring(data.squelchType) .. ":" .. tostring(ignoreName(data) or index))
        end,
        emit = function(b, data, index, helpers)
            if data.header ~= nil then
                local label = data.header == "FriendsFrameBlockedInviteHeaderTemplate" and BLOCKED_INVITES or IGNORED
                b:addItem(ControlId.structural("ignore:header:" .. data.header), nodes.text({ label = label }))
                return
            end
            b:addItem(helpers.id, {
                controlType = graph.controlTypes.button,
                announcements = {
                    {
                        text = function()
                            return ignoreName(data) or UNKNOWN
                        end,
                        kind = kinds.label,
                    },
                    selectedPart(function()
                        local squelchType, squelchIndex = IgnoreList_GetSelected()
                        return squelchType == data.squelchType and squelchIndex == data.index
                    end),
                },
                bindings = clickBindings(helpers.target),
                onFocus = helpers.onFocus,
                onFocusTick = helpers.onFocusTick,
                onUnfocus = helpers.onUnfocus,
            })
        end,
    })
    local unignore = window.UnignorePlayerButton
    local vtable = unignore ~= nil and nodes.proxyButton({ target = unignore }) or nil
    if vtable ~= nil then
        builder:beginStop("unignore")
        builder:addItem(ControlId.forObject(unignore), vtable)
    end
    builder:popContext()
end

-- A frame without a global name: looked up when polled, not at load.
module:registerWindow({
    type = "CustomWindow",
    name = "friendsIgnoreList",
    isOpen = function()
        local window = FriendsFrame ~= nil and FriendsFrame.IgnoreListWindow or nil
        return window ~= nil and window:IsVisible()
    end,
    conflictingAddons = { "Sku" },
    graphScreen = { render = renderIgnoreList },
})

-- The broadcast box (contacts menu): the message friends see under your
-- name, Update and Cancel.
local function renderBroadcast(builder, screen)
    local broadcast = FriendsFrameBattlenetFrame ~= nil and FriendsFrameBattlenetFrame.BroadcastFrame or nil
    if broadcast == nil or not broadcast:IsShown() then
        return
    end
    builder:pushContext("broadcast", BATTLENET_BROADCAST)
    builder:beginStop("broadcastText")
    builder:addItem(
        ControlId.forObject(broadcast.EditBox),
        nodes.proxyEditBox({ editBox = broadcast.EditBox, label = BATTLENET_BROADCAST })
    )
    for _, button in ipairs({ broadcast.UpdateButton, broadcast.CancelButton }) do
        local vtable = button ~= nil and nodes.proxyButton({ target = button }) or nil
        if vtable ~= nil then
            builder:beginStop("broadcast:" .. tostring(button:GetParentKey()))
            builder:addItem(ControlId.forObject(button), vtable)
        end
    end
    builder:popContext()
end

module:registerWindow({
    type = "CustomWindow",
    name = "friendsBroadcast",
    isOpen = function()
        local broadcast = FriendsFrameBattlenetFrame ~= nil and FriendsFrameBattlenetFrame.BroadcastFrame or nil
        return broadcast ~= nil and broadcast:IsVisible()
    end,
    conflictingAddons = { "Sku" },
    graphScreen = { render = renderBroadcast },
})

-- ---------------------------------------------------------------------------
-- Add Friend (AddFriendFrame): the name or BattleTag box, Send Request and
-- Cancel; the first time, an info page with Okay comes first.
-- ---------------------------------------------------------------------------

local function renderAddFriend(builder, screen)
    local frame = AddFriendFrame
    if frame == nil or not frame:IsShown() then
        return
    end
    builder:pushContext("addFriend", ADD_FRIEND)
    local entry = frame.EntryFrame
    local info = frame.InfoFrame
    if entry ~= nil and entry:IsShown() then
        builder:beginStop("name")
        builder:addItem(
            ControlId.forObject(entry.NameEditBox),
            nodes.proxyEditBox({ editBox = entry.NameEditBox, label = ENTER_CHARACTER_NAME_OR_BATTLETAG })
        )
        for _, text in ipairs({ entry.ErrorMessage, entry.RequestInfoText }) do
            if text ~= nil and text:IsShown() then
                builder:beginStop("text:" .. tostring(text:GetParentKey()))
                builder:addItem(ControlId.forObject(text), nodes.text({ label = fontText(text) }))
            end
        end
        for _, button in ipairs({ entry.AcceptButton, entry.CancelButton }) do
            local vtable = button ~= nil and nodes.proxyButton({ target = button }) or nil
            if vtable ~= nil then
                builder:beginStop("button:" .. tostring(button:GetParentKey()))
                builder:addItem(ControlId.forObject(button), vtable)
            end
        end
    elseif info ~= nil and info:IsShown() then
        builder:beginStop("info")
        local index = 0
        for _, region in ipairs({ info:GetRegions() }) do
            if region.GetText ~= nil and region:IsShown() and plainText(region:GetText()) ~= nil then
                index = index + 1
                builder:addItem(ControlId.structural("info:" .. index), nodes.text({ label = fontText(region) }))
            end
        end
        for _, child in ipairs({ info:GetChildren() }) do
            for _, region in ipairs({ child:GetRegions() }) do
                if region.GetText ~= nil and region:IsShown() and plainText(region:GetText()) ~= nil then
                    index = index + 1
                    builder:addItem(ControlId.structural("info:" .. index), nodes.text({ label = fontText(region) }))
                end
            end
        end
        local okay = info.OkayButton
        local vtable = okay ~= nil and nodes.proxyButton({ target = okay }) or nil
        if vtable ~= nil then
            builder:beginStop("okay")
            builder:addItem(ControlId.forObject(okay), vtable)
        end
    end
    builder:popContext()
end

module:registerWindow({
    type = "FrameWindow",
    name = "addFriend",
    frameName = "AddFriendFrame",
    conflictingAddons = { "Sku" },
    graphScreen = { render = renderAddFriend },
})

-- ---------------------------------------------------------------------------
-- Raid info (the raid tab's Raid Info button): saved instances and world
-- bosses with difficulty and time to reset; Extend and Close.
-- ---------------------------------------------------------------------------

local function savedLabel(data)
    local name, reset, difficulty, locked, extended
    if data.isInstance then
        local instanceName, _, instanceReset, _, instanceLocked, instanceExtended, _, _, _, difficultyName =
            GetSavedInstanceInfo(data.index)
        name, reset, difficulty, locked, extended =
            instanceName, instanceReset, difficultyName, instanceLocked, instanceExtended
    else
        local bossName, _, bossReset = GetSavedWorldBossInfo(data.index)
        name, reset, difficulty, locked, extended = bossName, bossReset, RAID_INFO_WORLD_BOSS, true, false
    end
    local parts = { name or UNKNOWN }
    if difficulty ~= nil and difficulty ~= "" then
        tinsert(parts, difficulty)
    end
    if locked or extended then
        tinsert(parts, SecondsToTime(reset or 0, true, nil, 3))
    else
        tinsert(parts, RAID_INSTANCE_EXPIRES_EXPIRED)
    end
    if extended then
        tinsert(parts, L["Extended"])
    end
    return table.concat(parts, ", ")
end

local function renderRaidInfo(builder, screen)
    local frame = RaidInfoFrame
    if frame == nil or not frame:IsShown() then
        return
    end
    builder:pushContext("raidInfo", RAID_INFO)
    builder:beginStop("saved")
    nodes.scrollBoxList(builder, {
        scrollBox = frame.ScrollBox,
        key = "saved",
        id = function(data, index)
            return ControlId.structural("saved:" .. tostring(data.isInstance) .. ":" .. tostring(data.index))
        end,
        row = function(data, index, helpers)
            return {
                controlType = graph.controlTypes.button,
                announcements = {
                    {
                        text = function()
                            return savedLabel(data)
                        end,
                        kind = kinds.label,
                    },
                    selectedPart(function()
                        return frame.selectedIndex == data.index and frame.selectedIsInstance == data.isInstance
                    end),
                },
                bindings = clickBindings(helpers.target),
                contextActions = nodes.proxyContextActions(helpers.target),
                onFocus = helpers.onFocus,
                onFocusTick = helpers.onFocusTick,
                onUnfocus = helpers.onUnfocus,
                tooltipFrame = helpers.target,
            }
        end,
    })
    for _, button in ipairs({ RaidInfoExtendButton, RaidInfoCancelButton }) do
        local vtable = button ~= nil and nodes.proxyButton({ target = button }) or nil
        if vtable ~= nil then
            builder:beginStop("raidInfo:" .. button:GetName())
            builder:addItem(ControlId.forObject(button), vtable)
        end
    end
    builder:popContext()
end

module:registerWindow({
    type = "FrameWindow",
    name = "raidInfo",
    frameName = "RaidInfoFrame",
    conflictingAddons = { "Sku" },
    graphScreen = { render = renderRaidInfo },
})
