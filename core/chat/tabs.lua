-- Chat tabs: the game's own chat windows decide which messages each tab
-- receives (the chat settings, per tab); WowVision only decides how a tab
-- is spoken. The rules here are pure so the headless tests run them.
local chatTabs = {}
WowVision.chatTabs = chatTabs

-- Permanent chat windows (ChatFrame1..N). Temporary windows -- a whisper
-- popped out into its own tab, the pet battle log -- are numbered above.
chatTabs.MAX_WINDOWS = (
    Constants ~= nil
    and Constants.ChatFrameConstants ~= nil
    and Constants.ChatFrameConstants.MaxChatWindows
) or NUM_CHAT_WINDOWS or 10

-- The message store holding every line of the whisper tabs, across partners.
chatTabs.WHISPERS_KEY = "chat.whispers"

function chatTabs.storeKey(index)
    return "chat." .. index
end

-- A temporary tab the game opened for one conversation (whisperMode
-- "popout" or "popout_and_inline", or "Whisper in new tab" from a menu).
function chatTabs.isWhisperWindow(frame)
    return frame.isTemporary == true and (frame.chatType == "WHISPER" or frame.chatType == "BN_WHISPER")
end

-- "shown": speak while the tab is on screen (the selected docked tab, or an
-- undocked window); "always": speak whatever the tab receives.
function chatTabs.shouldSpeak(mode, shown)
    return mode == "always" or shown == true
end

-- One message reaches every tab that receives it, all in the same frame.
-- Its identity across tabs: the event's line ID (never secret), else the
-- text of a line the game added without an event (connection notices).
-- A secret text without a line ID has no identity: it is not deduplicated.
function chatTabs.lineKey(eventArgs, text)
    local lineID = type(eventArgs) == "table" and eventArgs[11] or nil
    if type(lineID) == "number" then
        return "line:" .. lineID
    end
    if type(text) == "string" and not WowVision.secrets.isSecret(text) then
        return "text:" .. text
    end
    return nil
end

-- The first tab to speak a message claims it; the others stay quiet. Claims
-- only live for one moment (every tab handles the event in the same frame).
function chatTabs.newClaims()
    local claims = { time = nil, keys = {} }
    function claims:claim(key, now)
        if now ~= self.time then
            self.time = now
            self.keys = {}
        end
        if self.keys[key] then
            return false
        end
        self.keys[key] = true
        return true
    end
    return claims
end
