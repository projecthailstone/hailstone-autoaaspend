# Auto AA for Hailstone

Auto AA spends your alternate advancement points for you, on the abilities you pick, in the order you pick. It is
a Lua script for the [Hailstone](https://github.com/projecthailstone) EverQuest client. It adds a small **Auto AA**
window and puts its own controls into the Modern UI's AA window.

Each purchase goes through the game's own check, the same one the AA window's Train button uses. Auto AA only
decides which ability to buy next; the game still checks your points, level, class, expansions and prerequisites.

## Picking abilities in the AA window

While Auto AA runs, every row of the AA window has a round toggle at its right:

- **Empty ring** (a gold plus when you point at it): the ability is not queued. Click to add it to the end of the
  queue.
- **Gold disc with a number**: the ability is queued, and the number is its place in the queue. Click to take it
  out.

Queued rows have a gold outline. The next ability to be bought pulses and says **NEXT**; a switched-off entry says
**OFF**; one that has reached the highest rank you set says **DONE**.

When you select an ability, its details panel gets an **Auto Buy** box. It has a switch to queue the ability, the
highest rank to buy (**Up to rank**: *All*, or a number), its place in the queue and **Move to top**.

A strip under the window's header shows whether Auto AA is running and what it buys next, with **Start / Pause**
and a button that opens the Auto AA window.

## The Auto AA window

It opens when the script starts. You can also open it with `/autoaaspend` or the EQ menu's **Plugins > Auto AA**.

- **The top card**: your unspent points (and how many you keep in reserve), **Start / Pause**, **Spend now** (buy
  what can be bought now, then stop), what it is doing, and the next purchase with its rank and cost.
- **Queue**: the abilities in order. Each row shows its place, its name, why it is waiting, its rank pips, *up to*
  (the highest rank to buy), an on / off switch and a remove button. Drag a row to move it, or right-click it for
  Move to the top / bottom, Switch off and Remove. The search box at the bottom adds any ability offered to you, and
  **AA window** opens the AA window.
- **Settings**: see below.
- **Log**: what it bought and when, newest first.

The reasons a queued ability is waiting:

| Says | Meaning |
|---|---|
| Ready | It is bought at the next chance. |
| *n* more pt | You need *n* more points (your reserve counts against you). |
| Level *n* | The next rank needs level *n*. |
| Needs *X* *r* | It needs rank *r* of another ability first. |
| Done at rank *n* | It has reached the highest rank you set. |
| Maxed | You own every rank. |
| Not offered to you | No class of yours can have it, or the server does not offer it. |
| Can't be bought yet | The game says no for another reason (an expansion, a server rule). |
| Off | Switched off: kept in the queue but skipped. |

## Settings

- **Order**:
  - **Skip ahead** (the default) buys the first queued ability that can be bought now and passes over those that
    must wait.
  - **Wait for the top** saves points for the first ability that is not finished and buys nothing else until it
    has been bought.
- **Keep in reserve**: points Auto AA never spends, so you can buy something yourself.
- **Buy missing prerequisites first**: when a queued ability needs another one, that one is bought first if it can
  be (up to three steps back).
- **Buy during fights too**: off by default. While it is off, Auto AA only buys when auto attack is off and nothing
  is on your extended target list.
- **Start again after logging in**: if Auto AA was running when the character left, it starts again on the next
  login. Otherwise it waits for you to press Start.
- **When the queue has nothing to buy**: buy the cheapest abilities on the tabs you tick (General, Archetype, Class,
  Special), optionally only ranks up to a set cost. A queued ability keeps to its own entry: its highest rank, or
  off.
- **Clear the queue**.

## How it buys

It buys one rank at a time, at most about one a second. After each purchase it waits until the server confirms it
(your points or the ability's rank change) before buying the next. If the server does not answer within a few
seconds, it leaves that ability alone for a minute and moves on. It never buys an ability that can only be granted,
and never buys past the highest rank you set.

The game's own Train button asks you to confirm each purchase unless you turned that off. Auto AA does not ask: it
buys as `/alternateadv buy` does. Starting it is the confirmation.

## Commands

```
/autoaaspend               show or hide the window
/autoaaspend on | off      start or pause (also: toggle)
/autoaaspend now           buy what can be bought now, then stop
/autoaaspend add <name>    queue an ability by its full name
/autoaaspend remove <name>
/autoaaspend status
```

## Where the settings are

The settings are kept per server and character in `scripts/config/autoaaspend/` under Hailstone's folder. Nothing
is written to the game folder.

## For server owners

Auto AA is an ordinary player script, so your `hailstone.cfg` decides whether it runs at all (`[scripts] player =
on` and the capabilities in `player_caps`). It needs `read`, `actions`, `commands` and `ui`. To turn it off on your
server:

```ini
[autoaaspend]
enabled = off
```

## Needs

A Hailstone client with `hailstone.alt_abilities`, `hailstone.train_aa` and the Modern UI's `lib/aa.lua`: 0.4.0-alpha or
later. With an older Modern UI, the AA window stays as it was and the Auto AA window still works. The Gamepad UI
shows only the commands for now.

## Development

`lua5.4 tests/run.lua` runs the tests. They cover the settings, the choice of what to buy, and the windows drawn
over stand-ins for the client. `tools/release.sh <version>` packs and signs a release (see the script's head).
