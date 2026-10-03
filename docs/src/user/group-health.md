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

## When something is said

The monitor speaks only when a member's health changes. It never reads health on a timer, unless you turn on the repeat.

Every role (tanks, healers, damage dealers, no role) has its own settings:

- **Speak Below**: above this health, the member is silent.
- **Urgent Below**: below this health, the member counts as urgent.
- **Delay** and **Pause**: a normal announcement comes this long after the change, and not again within the pause.
- **Urgent Delay** and **Urgent Pause**: the same for urgent announcements, normally much shorter.
- **Repeat Below** and **Repeat Every**: every member under the repeat threshold is spoken again at this interval. 0 turns the repeat off.

So a tank dropping under half health can be spoken at once and every half second, while a damage dealer at 60 percent is spoken a second later and at most every few seconds.

A member who comes back to full health is announced as "number full", if **Announce Full Health** is on. A member who dies is announced once as "number dead".

## Other settings

- **Enabled**: the monitor is off until you turn it on. Off, it says nothing and its key does nothing.
- **Voice**, **Speech Rate**, **Speech Volume**: the monitor's own voice.
- **Time Between Numbers**: how far apart two announcements start.
- **Include Yourself**, **Watch Party**, **Watch Raid**.
- **Raid Groups**: which raid groups to watch, for example only the groups you heal.
- **Silent Out of Combat**.

## The snapshot key

**Speak Group Health** (default key: Alt+H) speaks every member once, in number order, at their current pitch. Change the key with `/wv bind`.

## The log

`/wv ghlog on` prints every announcement to chat as it plays: the time, the number, the role, the lane (urgent, normal, repeat, snapshot), how long after the health change it came, and whether a pause held it back. `/wv ghlog off` stops it, `/wv ghlog show` lists the last 200, `/wv ghlog clear` empties it. The log also lists the announcements the game kept silent: the monitor cannot know which ones were audible.

## Limits

- The game keeps group health secret from addons. The monitor never knows anyone's health: it prepares the possible announcements and the game plays the one that matches. That is why it cannot announce "only when health moved by 10 percent", and why incoming heals cannot be counted in.
- In battlegrounds and arenas, the game does not let addons read group members at all. The monitor then says once that it is unavailable.
