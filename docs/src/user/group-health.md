# Group Health Monitor

Available on WoW: Forever and Retail.

The group health monitor tells you which group member is losing health, and how badly, without reading out percentages. A hurt member is spoken as their number. The pitch tells how hurt they are: the lower their health, the higher the pitch. Healthy members stay silent.

The idea and the numbering come from Sku's health monitor.

## Numbers

- You are 1.
- Your party members are 2 to 5, in party order.
- In a raid, each member's number is their group times five, minus five, plus their place in the group. Group 1 is 1 to 5, group 2 is 6 to 10, up to 40.
- Raid numbers are only renumbered out of combat, so a number never changes during a fight.

## You need a real Windows voice

The monitor speaks with a game voice of its own, chosen in its settings. Pitch only works with a real Windows (SAPI) voice. A screen reader bridge voice, such as the NVDA SAPI bridge, speaks the numbers but ignores the pitch. The monitor does not need a screen reader at all.

Every voice shapes its sentences differently, so the pitch scale is tuned per voice. Microsoft Hedda and Microsoft Zira are measured; any other voice uses Hedda's scale and may sound less even.

## When something is said

The monitor speaks only when a member's health changes. It never reads health on a timer, unless you turn on the repeat.

With **Only When Health Changed Enough** (on by default) a member is spoken only when their health has moved by their role's **Minimum Change** since the last time they were spoken, up or down. Small changes add up: four small hits of 3 percent each make one announcement for a healer. A member whose health wobbles a little stays silent. This is the rule of Sku's health monitor, with Sku's values: tanks 5 percent, healers 10, damage dealers 20, no role 30.

Every role (tanks, healers, damage dealers, no role) has its own settings:

- **Speak Below**: above this health, the member is silent.
- **Minimum Change**: how far health must move since the last announcement (2 to 50 percent).
- **Urgent Below**: below this health, the member counts as urgent.
- **Delay** and **Pause**: a normal announcement comes this long after the change, and not again within the pause.
- **Urgent Delay** and **Urgent Pause**: the same for urgent announcements, normally much shorter.
- **Repeat Below** and **Repeat Every**: every member under the repeat threshold is spoken again at this interval. 0 turns the repeat off.

So a tank dropping under half health can be spoken at once and every half second, while a damage dealer at 60 percent is spoken a second later and at most every few seconds.

With **Only When Health Changed Enough** on, the delay is left out. The number goes out the moment the health changes, and the game itself decides whether it is heard: only when the health is a minimum change or more away from the last announcement. A silent check afterwards (about half a second) finds out where the health was, so the next number is measured from there. While a member's check is still running, a further change of that member goes out at once if no other check is waiting (it may then repeat the number before); otherwise it waits for the check, so in a busy fight a number can come up to about half a second later. The delays and pauses are not used in this mode: the minimum change keeps a member from speaking too often, as in Sku.

If something stops all speech (pressing Ctrl, a target change, a menu key) right as a number goes out, the number is spoken again, at most once every two seconds. A later stop does not repeat it: a silent check finds out where the health was instead. The snapshot and the repeat are never repeated: stopping them means stop.

A member who comes back to full health is announced as "number full", if **Announce Full Health** is on. A member who dies is announced once as "number dead".

## Other settings

- **Enabled**: the monitor is off until you turn it on. Off, it says nothing and its key does nothing.
- **Voice**, **Speech Rate**, **Speech Volume**: the monitor's own voice.
- **Time Between Numbers**: how far apart two announcements start (the snapshot, the repeat; with **Only When Health Changed Enough** the numbers of members hit at the same moment may start closer together).
- **Include Yourself**, **Watch Party**, **Watch Raid**.
- **Raid Groups**: which raid groups to watch, for example only the groups you heal.
- **Silent Out of Combat**.

## The snapshot key

**Speak Group Health** (default key: Alt+H) speaks every member once, in number order, at their current pitch; a member at full health as "number full" when **Announce Full Health** is on. Change the key with `/wv bind`.

## The log

`/wv ghlog on` records every announcement as it plays: the time, the number, the role, the lane (urgent, normal, repeat, snapshot), how long after the health change it came, and whether a pause held it back. `/wv ghlog off` stops it, `/wv ghlog show` opens the last 200 in a window, `/wv ghlog clear` empties it. The log also lists the announcements the game kept silent: the monitor cannot know which ones were audible. Its last line counts the health checks: samples, readings used, samples thrown away and why, purges, and numbers spoken again after a stop. With **Only When Health Changed Enough** on, each number that turned out to be a move is listed with the new reference, whether it was heard or silent (above **Speak Below**), and how soon after the health event it went out. The log is also kept in the saved variables at the next `/reload` (WowVisionDump).

## Limits

- The game keeps group health secret from addons. The monitor never knows anyone's health: it prepares the possible announcements and the game plays the one that matches. That is why incoming heals cannot be counted in.
- **Only When Health Changed Enough** learns how far health moved from how long silent speech plays, through the monitor's own voice. It is tuned to Microsoft voices (Hedda, Katja, Stefan and Zira were measured). Other voices, the NVDA SAPI bridge, and a frame rate below about 20 frames per second can make it fail. It does not work while the game is in the background (after Alt+Tab): the game then gives every utterance the same length. The output device does not matter (speakers and headsets measured the same). The game speaks one utterance after another, about 27 a second for all speech together, and every health event of a watched member costs three of them. Members hit at the same moment are checked together, up to three at a time, and when several wait the most urgent go first: members below their urgent threshold, then tanks, then healers, then the lowest health. In the simulation under steady damage: 5 watched members are followed almost fully (a number about 0.05 seconds after the change), 10 about 88 percent of the time, 20 about 60, 40 about half; under heavy area damage 10 members about a third. Numbers of members hit together may overlap. Watch only the raid groups you heal. When it reads nothing for half a minute, or almost nothing for a while, the monitor says "Group health readings failing" once; turn the setting off, and the monitor speaks on every health change again.
- In battlegrounds and arenas, the game does not let addons read group members at all. The monitor then says once that it is unavailable.
