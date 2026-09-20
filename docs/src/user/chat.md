# Chat

WowVision gives you access to your chat history and announces incoming messages automatically.

## Incoming Messages

By default, WowVision speaks new chat messages as they arrive and plays a notification sound. You can configure or disable these alerts from the WowVision menu (`/wv`).

## The Chat Window

Press **Shift+F3** to open the chat window. The window has two sections: your message history and your chat tabs.
Use **Up** and **Down** to scroll through messages in the current tab. Each message is announced with its text and timestamp. **Home** and **End** jump to the oldest or most recent message.

Your chat tabs are listed horizontally — use the arrow keys to switch between them. Each tab corresponds to one of your WoW chat frames, so whatever tab setup you have in-game carries over.

## Clicking Parts of a Message

A sighted player can click pieces of a chat line: the sender's name, the channel name, and any linked item, quest, or spell. WowVision gives you the same clicks.

Within a message, **Ctrl+Left** and **Ctrl+Right** move between its clickable parts, in the order they appear in the line. Each is announced, for example "Player Xynayya" or "Item Linen Cloth". When you arrive on a message, the first linked item is selected if there is one; otherwise the sender is.

On the selected part:

- **Enter** is a left click. On a player it starts a whisper, on a channel it starts a message to that channel, and on an item, quest, or spell it reads the tooltip.
- **Backspace** is a right click. On a player or channel this opens the game's own menu (whisper, invite, add friend, ignore, and so on), which WowVision reads like any other dropdown.
- **Shift+Enter** is a shift click. On a link it puts the link into your chat box, opening it if needed. On a player it puts the name into an open chat box, or runs a who query if none is open.
- **Space** and the **Shift+Arrow** tooltip keys read the tooltip of a selected link line by line.

**Shift+F10** opens the context menu, which lists these clicks and adds **Copy Line**: WowVision says "Copy now" and the message sits selected as plain text in an edit box, where Ctrl+C copies it and Escape closes the box. Use this for web addresses or anything else you want outside the game.

On Retail and WoW: Forever, the game hides chat text from addons during boss encounters and in some instances. Messages are still spoken, but their parts cannot be clicked there, and WowVision says "Links unavailable here". Loot messages are not affected.

## Sending Messages

WowVision reads chat but doesn't replace WoW's chat input. To send a message, use WoW's normal chat system — press Enter (when no WowVision window is open), type your message, and send it as usual.

A sound plays when the game's chat box opens for typing and another when it closes, so you always know whether your keys go to the chat box or to the game. Both sounds can be changed or turned off in the Chat module's settings ("Chat Box Opened" and "Chat Box Closed").
