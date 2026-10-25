# Controller

On WoW: Forever, WowVision can be played with a gamepad, next to the keyboard: both work at the same time, and every WowVision binding can have controller buttons besides its keys.

## Getting started

In the game options under **Gamepad**, turn on **Enable Gamepad** and **Enable Gamepad UI**. WowVision then answers the controller in its windows and in the world. Without the gamepad interface the controller buttons stay out of the way: the keybinding window shows them only while it is on.

The pad sends no Shift, Ctrl or Alt to the game, so WowVision reads the held buttons itself:

- **Left shoulder** held works like Alt
- **Left trigger** held works like Shift
- **Right trigger** held works like Ctrl
- **Both shoulders** held are the game's shortcut layer

## In WowVision windows

While a WowVision window is open, WowVision has the D-pad and the face buttons:

- **D-pad** — move between elements (the arrow keys)
- **A** — left click (Enter)
- **X** — right click (Backspace)
- **B** — close (Escape); where Escape belongs to the game, B runs the game's own Escape
- **Y** — read the tooltip (Space)
- **Left / right shoulder** — previous / next element (Shift+Tab / Tab)
- **Right trigger + left / right shoulder** — previous / next window
- **Right trigger + D-pad up / down** — first / last element
- **Left trigger + D-pad** — tooltip lines: up and down move between lines, left and right read the current line's left and right text
- **Menu button** — context menu
- **Left stick press** — drag
- **Left trigger + A** — shift click (chat links)
- **Right trigger + D-pad left / right** — the parts of a chat line

## In the world

- **Right stick press** — turn to the waypoint
- **Right stick press held + D-pad up / down** — previous / next buffer item
- **Right stick press held + D-pad left / right** — previous / next buffer
- **Right stick press held + left trigger + D-pad left / right** — previous / next buffer group

The right stick press and its combinations work in combat too.

## The shortcut layer

Hold both shoulders, out of combat, for the shortcuts whose game buttons only show something to sighted players:

- **D-pad up** — navigation window
- **D-pad down** — chat window
- **X** — scanner
- **A** — WowVision menu
- **Left stick press** — bars window, which also has the four gamepad action bars

## The gamepad main menu

The Start button opens the game's gamepad main menu, the wheel. WowVision shows it as a window of two rows of four: the upper row is the wheel's right half clockwise from the top, the lower row its left half. The **left stick** moves in the grid, **A** closes the wheel and runs the slice (as picking one does for everyone, so the window it opens has the focus), the shoulders turn the pages, and **B** or **Start** close it.

## In combat

When combat starts, the window buttons and the shortcut layer go back to the game, as the WowVision windows' keys do. The right stick press and its combinations stay.

## Changing the buttons

In the keybinding window (`/wv bind`), every binding lists its controller buttons while the gamepad interface is on. Activating one removes it. **Add Controller Button** waits for a button: hold the shoulders, triggers or the right stick press you want with it and press the button. A shoulder, a trigger or the right stick press pressed and let go on its own is taken by itself. Escape on the keyboard, ten seconds without a press, or combat starting cancels.

## Reporting a problem

While the gamepad interface is on, WowVision keeps a log of the controller presses and the speech around them, saved with your other WowVision data at logout or `/reload`. `/wv padlog` starts it afresh, just before you show a problem.
