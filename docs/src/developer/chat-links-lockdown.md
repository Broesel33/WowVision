# Chat Links Under Chat Messaging Lockdown

Status: design note for an experiment. Nothing here is built or verified in game yet.

## The problem

Chat line parts (`core/chat/links.lua`, `core/chat/ui.lua`) find the clickable pieces of a message by parsing its text, then act through `SetItemRef`, the function a real mouse click reaches. That works wherever addon code may read chat text.

Retail 12 and WoW: Forever flag chat text and sender names `SecretInChatMessagingLockdown`. The API documentation describes it as: secret values "when encounter, challenge mode, or PvP match addon restrictions are in effect, and when the player is on a communication-restricted map such as a dungeon or raid". A secret string can be held and passed on, but any string operation on it throws. `C_ChatInfo.InChatMessagingLockdown()` reports the state.

What still works there:

- Speaking the line. `C_VoiceChat.SpeakText` is `SecretArguments = "AllowedWhenTainted"`, so the full text, link names included, is spoken.
- Loot, money, currency, achievement, and experience messages. `CHAT_MSG_LOOT` and friends carry no secret flag, so their links parse and click as usual.

What does not: finding or acting on links in player-typed messages (say, party, raid, guild, whisper, channels). `chatLinks.parse` returns `nil, "secret"` and the UI says "Links unavailable here".

A sighted player is unaffected: the chat frame is Blizzard code, and a mouse click on a link runs the whole chain untainted.

## Why the direct routes are closed

- Parsing the text: forbidden, it is a string operation on a secret.
- Handing the secret line to a tooltip unparsed: `C_TooltipInfo.GetHyperlink` is `SecretArguments = "AllowedWhenUntainted"` (Blizzard code only). The `SetHyperlink` widget method is undocumented, which almost certainly means the same default. It also expects a bare link, not a whole chat line. Worth one in-game attempt, not a plan.
- Our own frames: a secure click on an addon frame still runs addon handlers, which are tainted. The secure templates offer a fixed action list (spell, item use, macro, click, target); none resolves a link.
- A key press as a click on the chat frame: the override-binding click needs a Button, and a ScrollingMessageFrame is not one. Link hit-testing is done by the engine from the mouse position, never from the click call.
- The bindable mouse commands (`CAMERAORSELECTORMOVE`, `TURNORACTION`) act on the 3D world only, never on UI frames.

Of the roughly 120 APIs that accept secret arguments from addon code, the useful ones here are `SpeakText`, `SetText` on font strings and tooltips, and a few string helpers. None turns a link into item data.

## The experiment: bring the link to the pointer

The only trusted path is a real pointer click inside Blizzard's chat frame. Addons cannot move the pointer, but they can move the chat frame, and they can notice hover without reading anything:

1. The chat frame fires `OnHyperlinkEnter` (also published as the `ChatFrame.OnHyperlinkEnter` EventRegistry event) when the pointer is over a link. The link argument is secret, but the fact that the event fired is not.
2. Scroll the chat frame so the wanted message is its bottom line. Scrolling is by message offset and needs no text access.
3. Read `GetCursorPosition()`. Reposition the chat frame so that bottom line passes under the stationary pointer, stepping horizontally along the line.
4. Count hover events: first link, second link, and so on. Stop on the one the user asked for (by ordinal, since kinds cannot be read; in party chat the sender is normally first and a linked item next).
5. Say "link ready". The user performs ONE real click at the pointer position with their assistive technology:
   - NVDA: NVDA+Numpad Divide (desktop layout) or NVDA+[ (laptop) for a left click; NVDA+Numpad Multiply or NVDA+] for a right click.
   - JAWS and Windows Mouse Keys offer equivalents.
   These are operating-system clicks; the game cannot tell them from a physical mouse. One key press, one click, made by the user: no automation.
6. Blizzard's untainted code handles the click: an item opens `ItemRefTooltip`, a player opens the whisper or the context menu.
7. Read `ItemRefTooltip` line by line into speech (passing lines unread if they come back secret), then restore the chat frame's position and scroll offset.

## Unknowns to settle in game

- Does `OnHyperlinkEnter` fire when the frame moves under a still pointer, or only on pointer motion? Everything depends on this.
- How wide is the lockdown in practice: the whole instance, or only encounters and challenge mode runs?
- Do stored secret strings become readable once lockdown ends, so links "come back" on old lines? If not, the message store should keep nothing it cannot use.
- Can `ItemRefTooltip` text be read, or at least spoken, during lockdown?
- The pointer must be inside the game window; the chat frame must be mouse-enabled, shown, and not faded; wrapped lines put links on other rows.
- Does `GameTooltip:SetHyperlink(secretLine)` do anything at all (the five percent test)?

A `/wv` diagnostic should answer the first four in one dungeon run on Forever: report `InChatMessagingLockdown()`, whether the newest stored line is secret, whether an older one still is, and log hover events while the chat frame is nudged.

## The real fix

Blizzard already exempted speech for screen-reader addons. The matching request: let `C_TooltipInfo.GetHyperlink` (or tooltip `SetHyperlink`) accept secret link text from tainted code, or give chat links a keyboard-reachable activation. An item tooltip reveals nothing about an encounter.
