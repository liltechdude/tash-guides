# TashGuides 0.10.0

A leveling-guide addon for WoW Forever. All quest data comes from **QuestieDB**, which must be installed separately and enabled in the add-on menu along with this.
---

<img width="1330" height="903" alt="TashGuidesForeverScreenshot" src="https://github.com/user-attachments/assets/a229434a-49a5-4aac-9596-1a89a613e8d0" />


## Contents

- [Features at a glance](#features-at-a-glance)
- [Requirements](#requirements)
- [Installation](#installation)
- [Getting started](#getting-started)
- [Guide window](#guide-window)
- [Guides: campaign, zone, class, profession and Smart](#guides-campaign-zone-class-profession-and-smart)
- [Waypoint arrow](#waypoint-arrow)
- [Quest tracker](#quest-tracker)
- [Map and minimap pins](#map-and-minimap-pins)
- [Tooltips](#tooltips)
- [Auto-accept and auto turn-in](#auto-accept-and-auto-turn-in)
- [Slash commands](#slash-commands)
- [Options reference](#options-reference)
- [Minimap button](#minimap-button)
- [Saved data and per-character progress](#saved-data-and-per-character-progress)
- [Troubleshooting and FAQ](#troubleshooting-and-faq)
- [For guide authors and developers](#for-guide-authors-and-developers)
- [Credits](#credits)

---

## Features at a glance

| Piece | What it does |
|---|---|
| **Guide window** | The current step's goals (accept, complete, turn in, go to, talk to...) with checkmarks and objective progress. Moves to the next step when every goal is done. Shows a few upcoming steps and a progress bar. `<` / `>` browse earlier and later steps without moving the guide; click the step bar to return to the current one. |
| **Steps panel** | The note icon in the guide window header (or `/tg steps`). Every step of the guide: earlier steps (done), the current one and what is coming up, with per-step goal counts. Click a step to view it, right-click to move the guide there. For the Smart Guide it lists every task lined up plus your recent quest activity. |
| **Smart Guide** | Works in any zone without hand-written data. Builds steps from your turn-ins, objectives and nearby quest givers. **Linear** routing (default) plans a fixed route and walks you through it step by step like a written guide; **Nearest** routing re-sorts by distance as you move. Used when no campaign guide fits your character. |
| **Leveling campaign** | A hand-written route from level 1 to 60 for every race: 70 guides, one per zone visit, each handing you on to the next. Every race starts in its own starting area and joins its faction's shared route through the mid levels, ending in Silithus. Quests for other races and classes are hidden automatically. |
| **Zone guides** | A step-by-step guide for every zone from level 1 to 60 (around 40 of them), generated from QuestieDB for your faction, race and class: every quest of the zone, chains in order, quests grouped by giver and objective area. Use them alongside the campaign to clear a zone completely, or wherever you want a guide for the zone you are in. |
| **Profession guides** | One guide per profession with quests (*Alchemy quests*, *Cooking quests*, ...), ordered by the skill each one needs. Professions you have learned are marked. |
| **Class & race chains** | Your class quests (trainer letters, class quest lines) and racial quests are found in QuestieDB at login and offered as their own guides, *Warrior quests*, *Human quests* and so on, in level order with prerequisites first. The main guides (zone guides and the Smart Guide) include them too unless you opt out: class crest in the guide header, the checkbox in the guide picker, the option *Include class & race quests*, or `/tg chains`. The Smart Guide offers every class/racial quest you can take wherever its giver is, ranked ahead of ordinary quests at a similar distance. |
| **Waypoint arrow** | Points to the current goal, colored green to red by heading, with distance in yards and ETA. Shows a check when you arrive at a spot, and an **objective-area** display (colored ring, objective icon, *IN OBJECTIVE AREA* and your progress) once you are among the mobs or nodes a quest needs. Right-click it to clear a manual waypoint. Targets on other maps (a trainer in a city, a turn-in two zones over) still get a direction and distance. When the current step has nothing to point at (an item-started quest, a note) the arrow points at the next step that does, marked *Next: ...*. For objectives with many spawns it favors spawns ahead of you over ones behind (tunable in options: *Prefer spawns ahead of you*) and moves on from spawns you just cleared. |
| **Quest tracker** | Same look as the guide window. Quests the current guide step works on are grouped first (*Guide step*, with an accent edge), then *This zone* by distance, then *Elsewhere*. Objectives are colored by progress with a progress bar per quest; class/racial quests are tagged. Click: waypoint. Shift: link. Ctrl: quest log. Right-click: hide. |
| **Map pins** | `!` quests to pick up (blue: repeatable, grey: low level), `?` turn-ins, and colored dots for objectives (red kill, yellow loot, blue object, purple explore). On both the world map and the minimap. Click a pin to set a waypoint. |
| **Tooltips** | Hover a mob or object to see which of your quests need it and your progress. Hover a quest giver to see what they offer or are waiting for. |
| **Automation** (off by default) | Optional auto-accept and auto turn-in. Hold Shift to bypass. Reward choices are never made for you. |

You can use any of these on their own: each piece can be turned off in the options, and the pins, tooltips and tracker keep working without the guide window or the arrow. The guide window, arrow and tracker can also be moved, scaled and locked in place.

---

## Requirements

- The **World of Warcraft Forever** client (the `_forever_` game folder).
- **QuestieDB**, installed and enabled. This is the Forever build of the database addon that Questie uses, and it must support QuestieDB contract version 4. TashGuides lists it as a dependency, so the game will not load TashGuides without it.

If QuestieDB is missing or too old, TashGuides prints a message in chat on login saying it could not start and why.

---

## Installation

1. Download this repository (the green **Code** button, then **Download ZIP**) and unzip it.
2. Copy the **`TashGuides`** folder (the one containing `TashGuides.toc`, not the whole repository) into:

   ```
   World of Warcraft/_forever_/Interface/AddOns/
   ```

3. Make sure **QuestieDB** is in the same `AddOns` folder.
4. Start the game, or type `/reload` if it is already running. Check that TashGuides and QuestieDB are both enabled on the character-select AddOns screen.

On login you should see a chat line like `TashGuides: v0.10.0 ready - Northshire Valley. Type /tg help for commands.`

To update, replace the `TashGuides` folder with the new one. Your settings and progress are kept (see [Saved data](#saved-data-and-per-character-progress)).

---

## Getting started

When you log in, TashGuides picks a guide for you:

- If a campaign guide for the zone you are standing in suits your faction and race and you are within its level range (or one level below it), it loads that guide. Your race's starting area wins over the zone's later guide, and a guide you have not finished wins over one you have.
- Otherwise, if there is a generated zone guide for the zone you are standing in and your level fits it, it loads that one. (Zone guides are built a moment after login, so another guide may show briefly first.)
- Otherwise it loads the campaign guide that fits your level best, or the **Smart Guide** if none does.

Once you choose a guide yourself, TashGuides never swaps it for another.

From there:

1. Follow the **guide window**. The top goal is what to do now.
2. Follow the **arrow**. It points to that goal and counts down the yards.
3. Do the goals. The window ticks them off and moves on by itself.

Handy first commands:

```
/tg                      toggle the guide window
/tg guides               choose a guide
/tg next | prev | skip   move through steps (Shift-click the > button also skips)
/tg steps                past and upcoming steps
/tg class | race         open your class / racial quest chain
/tg zone                 the generated guide for the zone you are in
/tg prof alchemy         a profession quest guide
/tg chains               include or hide class & race quests in the main guides
/tg arrow | tracker      toggle the arrow / quest tracker
/tg way 45.2 61.8 note   waypoint on your current map
/tg clear                clear the waypoint
/tg options              settings (also: right-click the minimap button)
/tg reset                restart the current guide
/tg status               database and guide status
```

Every window can be dragged by holding the left mouse button. Positions are remembered. Lock a window in the options to stop it from being moved by accident.

---

## Guide window

The guide window is the main view. It has a title bar, a step bar, the goals for the current step, and (for written guides) a progress bar along the bottom.

### Title bar buttons

| Button | What it does |
|---|---|
| Book icon | Open the guide picker. |
| Gear icon | Open the options window. |
| Minus | Minimize the window down to its title bar (click again to restore). |
| Stop icon | Hide the window. Use `/tg` or the minimap button to bring it back. |

### Step bar

For written guides (the campaign, zone, class and profession guides) the step bar shows `Step 4/23` and the step's title, with arrow buttons on either side:

- **Left arrow**: look back at the previous step without losing your place. The label shows `(viewing)` in red while you are looking at an earlier step. Press the right arrow to walk back forward to where you actually are.
- **Right arrow**: go forward. Use it to confirm a step that only contains notes, or to move ahead manually. **Shift-click** skips the current step. When you have finished a guide, the right arrow loads the next guide.

For the Smart Guide the step bar has a **Linear / Nearest** button that switches routing (see [Smart Guide](#smart-guide)). In linear routing the label reads `Route  12 stops left` and the right arrow **skips** the current step to the end of the route; **Shift-click** plans the route again from where you stand. In nearest routing the arrows are hidden.

### Goals

Each goal has an icon and a checkmark when done. Goals are written like:

- **Accept** *Quest Name (level)* from *NPC*
- **Complete** *Quest Name (level)*, with each objective listed underneath and colored from red to green as you make progress
- **Turn in** *Quest Name (level)* to *NPC*
- **Go to** a coordinate
- **Talk to** an NPC
- **Reach level** N
- **Hearth to** a place, **Fly to** a place
- Plain notes with extra advice

Quest names are colored by difficulty relative to your level, and repeatable quests are tinted blue.

If you cannot pick a quest up yet, the goal says why in red, for example `(requires level 4)` or `(finish the earlier quests first)`. Goals marked `(optional)` do not hold up the step.

Goals that do not apply to your character, such as another class's training quest, are hidden automatically. A step with nothing left to do for you is skipped.

### Mouse actions on a goal

| Action | Result |
|---|---|
| Hover | Tooltip with the quest's level, required level, objective text, and who starts and ends it. |
| Left-click | Point the arrow at that goal's location. |
| Right-click | Mark a manual goal (go to, talk to, hearth, fly) done or not done. Quest goals follow your quest log and cannot be ticked by hand. |

### How goals complete

| Goal | Counts as done when |
|---|---|
| Accept | The quest is in your log, or you already turned it in. |
| Complete | All objectives are finished, or the quest is ready to turn in. |
| Turn in | The quest has been handed in. |
| Go to | You arrive within the arrow's arrival distance. |
| Talk to | You open that NPC's gossip, quest or merchant window. |
| Reach level | Your character reaches that level. |
| Hearth to | You cast your Hearthstone or Astral Recall. |
| Fly to | You board a flight path. |

When every goal in a step is done, the guide moves on and plays a short sound. You can turn **Advance steps automatically** off in the options if you would rather press the right arrow yourself.

### Upcoming steps and progress bar

Below the current step, the window shows the first goal of the next few steps, dimmed. Show anywhere from 0 to 5 with the **Upcoming steps shown** option (default 2). For written guides a progress bar at the bottom shows steps done, total steps and a percentage.

---

## Guides: campaign, zone, class, profession and Smart

### The leveling campaign

The campaign is a set of hand-written guides, one per zone visit, that take every race from level 1 to 60. Each one is a fixed route: which quests to take, in what order, where to go and how to get there, with tips along the way. Quest names, NPC names and locations are filled in from QuestieDB. When you finish a guide, the right arrow loads the next one.

**Starting out (1-12).** Every race has its own start:

| Race | Route |
|---|---|
| Human | Northshire Valley, Elwynn Forest, Westfall, then Redridge Mountains |
| Dwarf, Gnome | Coldridge Valley, Dun Morogh, Loch Modan, then Redridge Mountains |
| Night Elf | Shadowglen, Teldrassil, Darkshore, Ashenvale, then Duskwood |
| Orc, Troll | Valley of Trials, Durotar, then The Barrens |
| Tauren | Camp Narache, Mulgore, then The Barrens |
| Undead | Deathknell, Tirisfal Glades, Silverpine Forest, then The Barrens |

**The shared route.**

| Levels | Alliance | Horde |
|---|---|---|
| 15-30 | Redridge Mountains, Duskwood, Wetlands | The Barrens (part 1), Stonetalon Mountains, The Barrens (part 2), Ashenvale, Thousand Needles |
| 25-40 | Hillsbrad Foothills, Alterac Mountains, Arathi Highlands, Stranglethorn Vale (part 1), Thousand Needles, Desolace | Hillsbrad Foothills, Alterac Mountains, Arathi Highlands, Stranglethorn Vale (part 1), Desolace |
| 35-45 | Dustwallow Marsh, Badlands, Swamp of Sorrows, Stranglethorn Vale (part 2) | the same |
| 40-50 | Tanaris, Feralas, The Hinterlands, Searing Gorge | the same |
| 45-55 | Blasted Lands, Azshara, Un'Goro Crater, Felwood | the same |
| 50-60 | Burning Steppes, Western Plaguelands, Eastern Plaguelands, Winterspring, Silithus | the same |

The guides of the same zone differ by faction: each uses its own faction's hubs, flight paths and quests.

**What is in them.** The quests of each zone that suit the route: normal quests, your race's quests, and the quests added for Forever. Left out: dungeon and raid quests, elite group quests, repeatable, holiday and profession quests, and class quests apart from the trainer letters in the starting areas (your class quests have their own guide, see [Class & race chains](#features-at-a-glance)). Some zones offer few quests to one faction once those are left out, so a few guides are short. Quests that start from a random drop are optional: if the item drops, the guide picks up the quest and its follow-ups, and if it never does, those steps are skipped. A few steps say *Reach level N* where the next quests need it.

**Pace.** The guides are written for a player who kills what is in the way, not one who grinds. Counting the kills on the way as roughly as much experience as the quests, the campaign reaches level 60 in the Eastern Plaguelands. If you skip quests you may need a dungeon or a generated zone guide to catch up; the guide picker shows each guide's level range.

The picker only lists guides that suit your character's faction and race.

> Improvements to the campaign are welcome. See [For guide authors](#for-guide-authors-and-developers).

### Zone guides

Zone guides cover every zone with enough quests, from level 1 to 60. Where the campaign picks a route through a zone, a zone guide lists all of its quests for you. They are not typed in: TashGuides reads QuestieDB at login and builds each one for the character that is logged in, so a Tauren Warrior and a Gnome Mage get different guides for the same zone. Open them from the picker (they are grouped by level range), with `/tg zone` for the zone you are standing in, or let the guide pick one for you at login (see [Getting started](#getting-started)).

**What goes in.** Quests your character can take: your faction, race and class, level 60 or lower, started by someone who stands somewhere on the map, filed under the zone the giver is in. A quest from another class's trainer is left out even if the database forgot its class flag (a `<Hunter Trainer>` is a hunter's quest). **What stays out:** repeatable and holiday quests, profession quests (they have their own guides), quests that start from an item or inside an instance, and quests whose every objective is inside an instance. Breadcrumb quests whose target is in the same zone are skipped, and of two exclusive quests only the first is listed.

**How the route is worked out.** TashGuides plays the zone in its head. Quests whose earlier quests in the zone are done become available; a level counter rises as quests are handed in, so a level 20 quest does not appear while the level 12 ones are still open; and the quest log never holds more than ten quests at a time. Each move goes to the cheapest next thing: handing in costs 0.6 of the walking distance, picking up 0.85 (plus half the walk from the giver to the objectives, so a quest whose mobs are far away waits), objectives 1.0. Then everything doable from that spot joins the same step: hand-ins and pick-ups at one NPC, objectives within about 140 yards of each other. A step starts with hand-ins, then pick-ups, then objectives.

**Class and racial quests** get steps of their own, tagged `[class]` or `[race]`, so the *Include class & race quests* opt-out hides exactly those steps and leaves the rest of the route alone.

**It adapts to you.** A step for a quest that can no longer be taken (you did its exclusive twin, it expired, you are too high a level) disappears. If you skip a pick-up, the objective and hand-in steps for that quest stop waiting on it. If a quest says `requires level 14`, that is your cue to do other quests; use **Shift-click `>`** to skip a step you cannot do yet.

The route depends only on the database and your faction, race and class, never on your progress, so your place in a zone guide survives relogs and is kept per character. If you update QuestieDB, a guide can be a few steps different, which only shifts the numbers.

At the end of a zone guide the right arrow offers the next one: a zone a step up in level, preferably on the same continent and nearby.

### Profession guides

Each profession that has quests (Alchemy, Blacksmithing, Cooking, Enchanting, Engineering, First Aid, Fishing, Herbalism, Leatherworking, Mining, Skinning, Tailoring, and Jewelcrafting, Inscription or Riding where your client has them) gets a guide, in the picker under *Profession quests* and with `/tg prof alchemy` (any start of the name works). Quests are ordered by the skill they need, earliest first, and earlier quests in a chain come before later ones. Each step names the skill, the level and where the quest starts. Professions you have learned are marked `learned` in the picker. Class and racial quest chains are listed with them as separate guides.

Profession quests are not part of the Smart Guide or the zone guides; the map pins for them follow the *Profession quests* pin option.

### Smart Guide

The Smart Guide works anywhere, for any race, class and level. It looks at your quest log and your surroundings and finds:

- **Turn-ins**: quests you have finished, at the nearest hand-in NPC.
- **Objectives**: remaining objectives for quests you are on.
- **Pick-ups**: quests you are eligible for on your current map, from nearby quest givers, as long as the quest's level is no more than three above your own.

How those tasks are ordered depends on the **routing**, switched with the **Linear / Nearest** button on the step bar, the option *Linear Smart route*, or `/tg route linear` / `/tg route nearest`.

**Linear (default)** works like a written guide. The first time, it plans a route nearest-next from where you stand. After that the order is fixed: the current step stays the current step until every goal in it is done, however far you wander or whichever other quest's mobs you pass. New tasks are slotted into the route where they add the least walking, never ahead of the step you are on: a quest you just picked up, or an objective that has turned into a hand-in. Stops are remembered by place, so the route does not reshuffle as the arrow picks different spawns. The route is saved per character and survives a reload.

- The right arrow (or `/tg route skip`) skips the current step to the end of the route.
- Right-click a stop in the Steps panel (`/tg steps`) to do it next.
- Shift-click the right arrow (or `/tg route reset`) to plan the whole route again from where you are now, for example after a hearth or a flight.

**Nearest** re-sorts every few seconds by distance, with turn-ins and pick-ups weighted slightly in your favor so you hand in and grab quests when you pass by. The leading task is sticky: another task has to be clearly closer (about a third) before it takes over, so the guide does not flip between two quests at a similar distance.

In both modes, tasks within about 30 yards of each other (for example one NPC who takes and gives several quests) share a step, and a step lists turn-ins first, then objectives, then pick-ups. In linear routing only stops next to each other in the route are merged, so the order holds. Steps are labeled with their distance (`Route 3 - 140 yd away` in linear routing). If there is nothing to do it tells you to explore toward a town or pick a zone guide.

The Smart Guide only suggests quests you can actually accept right now. It applies the same eligibility rules as the map pins (see [Which quests get a `!`](#which-quests-get-a-)).

### Choosing and restarting guides

Open the picker with the book icon, `/tg guides`, or the **Choose guide...** button in the options. Click a guide to load it. The active one is marked with `>`. The picker also has a **Restart current guide** button.

The picker is a scrolling list in sections: the Smart Guide, the campaign by level range (1-10, 10-20, and so on), generated zone guides by level range, class and race quests, and profession quests. The guide you are on is marked with `>` and the list opens scrolled to it; hover a guide to see its level range and your place in it.

Your place in every guide is saved separately for each character, so you can swap guides and come back where you left off.

---

## Waypoint arrow

The arrow points toward your current target and shows what it is.

- **Direction and color**: the arrow rotates relative to the way your character is facing. It is green when you are heading the right way, passes through yellow, and turns red when you are facing away from the target.
- **Distance and ETA**: distance in yards (or `1.2k yd` when far), plus an estimated travel time based on your current speed.
- **Arrival**: when you reach a spot (a quest giver, a hand-in, a go-to point), the arrow becomes a green check and says `Arrived`.
- **Objective area**: when the target is a quest objective and you are within the objective area (50 yards of the nearest spawn you still need, set with *Objective area size*), the arrow is replaced by:
  - a pulsing ring in the objective's map-pin color (red kill, yellow loot, blue object, purple explore) around a matching icon;
  - the quest name and **IN OBJECTIVE AREA**;
  - your progress on that objective (`Kobold Vermin slain: 3/10`), plus how far the nearest spawn is.

  It switches back to the arrow when you walk out of the area. An objective waypoint you set from the tracker or a map pin stays until the quest is ready to hand in, instead of clearing when you reach the first spawn.
- **Other zones**: if the target is on another map, the arrow shows the target's direction when the two maps can be lined up, and otherwise says `Travel to` followed by the zone name.
- **Instances**: inside an instance there is no usable position, so the arrow says so rather than pointing the wrong way.
- **Dungeon objectives**: objectives that are inside a dungeon point to the dungeon entrance on the outdoor map, and the arrow labels it `... entrance`.
- **Hover**: shows the target's name, zone and coordinates.

### What the arrow follows

There is one active waypoint at a time. Where it comes from, in priority order:

1. A waypoint you set yourself: `/tg way`, a click on the tracker, a click on a map pin, or a click on a guide goal.
2. The guide's current goal.

A waypoint you set wins over the guide. When you reach it, or clear it, the guide's target comes back by itself. Right-click the arrow to clear a waypoint you set.

### Smart target choice for objectives with many spawns

Kill and collect objectives often have many possible spawn points. Instead of always pointing at the closest one, the arrow picks the best one:

- **Prefers spawns ahead of you.** A spawn straight ahead costs its true distance. A spawn directly behind you counts as farther by up to the **Prefer spawns ahead of you** setting (default 2.5, meaning up to 3.5x). A much closer spawn behind you can still win. Set it to 0 for plain nearest-spawn behavior.
- **Moves on from spawns you cleared.** If you stood within about 15 yards of a spawn, it is treated as done (killed or looted) for the next three minutes, so the arrow does not drag you back to it.
- **Does not flicker.** The current target is kept unless another spawn is clearly better, so turning the camera or circling a mob does not make the arrow jump around.

Targets refresh every second as you move.

---

## Quest tracker

The quest tracker is a compact list of everything in your quest log, with the count (`Quests 14/25`) in its header. Click the plus or minus button in its corner to collapse or expand it.

- Quests that have a target on your **current map** are listed first, **nearest first**. Quests elsewhere follow.
- Each quest shows its level, a `(complete)` or `(failed)` tag, and the distance on the right.
- Objectives are listed underneath, colored from red to green as you progress. Finished quests say `Turn in to <NPC>`.
- Hover a quest for its objective text and who to turn it in to.

### Mouse actions on a quest

| Action | Result |
|---|---|
| Click | Point the arrow at the quest. For unfinished quests it targets the best objective spawn; for finished ones it targets the turn-in NPC. |
| Shift-click | Paste a link to the quest into your chat box. |
| Ctrl-click | Open the quest in your quest log. |
| Right-click | Hide the quest from the tracker. A `N hidden` line is shown at the bottom. |

To bring hidden quests back, press **Show hidden tracker quests** in the options.

### Tracker options

You can set how many quests to show (3-25, default 12), the scale, and whether the tracker is locked. **Hide Blizzard's quest tracker** removes the default tracker so you do not have two. That change is applied out of combat.

---

## Map and minimap pins

TashGuides draws quest markers on the world map and on the minimap. The two can be turned on or off independently, and so can each kind of pin.

| Pin | Meaning |
|---|---|
| Gold `!` | A quest you can pick up. |
| Blue `!` | A repeatable quest. |
| Small grey `!` | A low-level quest that gives little experience (hidden by default). |
| Gold `?` | A finished quest, ready to turn in. |
| Red dot | Kill objective. |
| Yellow dot | Loot or collect objective. For items this shows where the item drops, or the vendor that sells it if nothing drops it. |
| Blue dot | Interact with an object. |
| Purple dot | Explore or event objective. |
| Blue target ring | Your active waypoint. |

Hover a pin to see which quest or quests it belongs to. Pins at the same spot merge into one pin with several lines. Click a pin to set a waypoint on it.

Only objectives you have not finished yet are drawn, so the dots disappear as you complete them. On the minimap, pins respect a rotating minimap, and your waypoint is pinned to the edge of the minimap when it is out of range so you can see which way to go.

### Which quests get a `!`

To keep the map useful, a `!` only appears for quests you can actually accept **right now**. A quest is left out if:

- you have already done it (repeatable quests excepted), or it is already in your log
- you are below its required level, or above its maximum level
- it is not for your race or class
- its prerequisite quests are not done yet
- you have taken or finished a mutually exclusive quest
- it has expired, or it is a breadcrumb quest you no longer need
- it is a sub-quest that belongs to another quest
- its quest giver is hostile to your faction

Quests that need a profession skill are hidden by default. Turn them on with **Profession quests**.

The list of available quests updates automatically when you level up, finish a quest or learn a profession. Right after login it is built gradually in the background, then refreshed again a few seconds later once the game has finished sending your completed quests, so pins can take a moment to fill in.

### Pin options

World map, Minimap, Quests to pick up, Objectives, Turn-ins, Low-level quests, Repeatable quests, Profession quests, and separate size sliders for the world map and minimap pins.

---

## Tooltips

With **Quest info on tooltips** on (the default), hovering things in the world adds your quest information.

**Mobs and objects you need**: shows the quest name (colored by difficulty) and the objective with its current progress, such as `Kobold Vermin slain: 3/10`.

**Quest givers**:
- `! Quest Name (level)` for each quest they can give you right now
- `? Turn in: Quest Name` for quests you have finished that they accept
- `? Quest Name (not finished)` for quests of theirs that you are still working on

---

## Auto-accept and auto turn-in

Both are **off by default**. Turn them on in the options under **Quests**.

| Option | What it does |
|---|---|
| **Auto-accept quests** | Accepts a quest as soon as an NPC offers it. In gossip and quest-list windows it picks up available quests one at a time, skipping low-level (grey) ones. |
| **Auto turn-in quests** | Hands in finished quests. In gossip and quest-list windows it selects your finished quests first. |

Rules:

- **Hold Shift** while talking to an NPC to skip automation and handle things yourself.
- When a quest offers **a choice of rewards**, the window stays open for you. TashGuides never chooses a reward for you. Quests with no choice, or only one reward, are turned in directly.
- Auto turn-in runs before auto-accept in the same window, so you hand in first and then pick up.

---

## Slash commands

The commands are `/tg` and `/tashguides` (they are the same).

| Command | What it does |
|---|---|
| `/tg` | Show or hide the guide window. |
| `/tg show` / `/tg hide` | Show or hide the guide window explicitly. |
| `/tg guides` | Open the guide picker. |
| `/tg smart` | Switch to the Smart Guide. |
| `/tg zone` | Open the generated guide for the zone you are standing in. |
| `/tg prof <name>` | Open a profession quest guide, e.g. `/tg prof alchemy`. With no name it lists the professions that have one. |
| `/tg class` / `/tg race` | Open your class / racial quest chain guide. |
| `/tg chains` | Include or hide class and racial quests in the main guides. |
| `/tg steps` | Show or hide the Steps panel. |
| `/tg next` | Next step (confirms a notes-only step, or moves ahead manually). |
| `/tg prev` | Look back at the previous step. |
| `/tg skip` | Skip the current step. |
| `/tg route linear` / `/tg route nearest` | Smart Guide routing: a fixed route step by step, or nearest task first. |
| `/tg route skip` | Smart Guide (linear): move the current step to the end of the route. |
| `/tg route reset` | Smart Guide (linear): plan the route again from where you stand. |
| `/tg arrow` | Show or hide the waypoint arrow. |
| `/tg tracker` | Show or hide the quest tracker. |
| `/tg way 45.2 61.8 [note]` | Set a waypoint at those coordinates (0-100) on the map you are standing on. The note is an optional label. |
| `/tg clear` | Clear the waypoint you set. |
| `/tg options` | Open the options window. |
| `/tg reset` | Restart the current guide from step 1. |
| `/tg status` | Print the version, the QuestieDB connection, how many quests are currently available to you, your place in the current guide, and how many zone and profession guides were generated. |
| `/tg help` | List the commands in chat. (Any unknown command does the same.) |

---

## Options reference

Open the options with `/tg options`, the gear icon on the guide window, the minimap button's right-click, or the game's AddOns settings list (it has a **TashGuides** entry with a button that opens the window). Press Esc to close it.

| Section | Setting | Default | Notes |
|---|---|---|---|
| **Guide window** | Show guide window | On | |
| | Lock position | Off | |
| | Advance steps automatically | On | When off, use the right arrow or `/tg next`. |
| | Linear Smart route | On | Smart Guide routing. On: a fixed route followed step by step. Off: nearest task first, re-sorted as you move. |
| | Sounds | On | Controls every TashGuides sound: step advance, quest ready, waypoint reached. |
| | Upcoming steps shown | 2 | 0 to 5. |
| | Scale | 1.00 | 0.60 to 1.60. |
| | Opacity | 0.92 | 0.20 to 1.00. |
| **Arrow** | Show waypoint arrow | On | |
| | Lock position | Off | |
| | Scale | 1.00 | 0.50 to 2.00. |
| | Arrival distance (yd) | 8 | 3 to 30. How close counts as "arrived". |
| | Objective area size (yd) | 50 | 20 to 150. How close to the nearest needed spawn shows *IN OBJECTIVE AREA* instead of the arrow. |
| | Prefer spawns ahead of you | 2.5 | 0 to 5. 0 = always nearest. |
| **Quest tracker** | Show quest tracker | On | |
| | Lock position | Off | |
| | Hide Blizzard's quest tracker | Off | |
| | Quests shown | 12 | 3 to 25. |
| | Scale | 1.00 | 0.60 to 1.60. |
| **Map pins** | World map | On | |
| | Minimap | On | |
| | Quests to pick up (!) | On | |
| | Objectives (dots) | On | |
| | Turn-ins (?) | On | |
| | Low-level quests | Off | Grey quests that give little experience. |
| | Repeatable quests | On | |
| | Profession quests | Off | |
| | World map pin size | 1.00 | 0.50 to 2.00. |
| | Minimap pin size | 1.00 | 0.50 to 2.00. |
| **Quests** | Quest info on tooltips | On | |
| | Auto-accept quests | Off | Hold Shift to skip. |
| | Auto turn-in quests | Off | Hold Shift to skip. Reward choices wait for you. |
| | Minimap button | On | |
| | Show hidden tracker quests (button) | | Un-hides quests you right-clicked away in the tracker. |
| | Choose guide... (button) | | Opens the guide picker. |

---

## Minimap button

A small button sits on the edge of your minimap.

| Action | Result |
|---|---|
| Click | Show or hide the guide window. |
| Shift-click | Show or hide the quest tracker. |
| Right-click | Open the options. |
| Drag | Move the button around the minimap. |

TashGuides also registers with the game's addon compartment menu: click it to toggle the guide window, right-click it to open the options. If you would rather not have the minimap button, untick **Minimap button** in the options.

---

## Saved data and per-character progress

- **Settings** (everything in the options, plus window positions) are shared across all your characters and stored in `TashGuidesDB`.
- **Progress** is stored per character in `TashGuidesCharDB`: the active guide, your step in each guide, skipped steps, goals you ticked by hand, quests hidden from the tracker, and quests you have handed in.

Both live in your `WTF` folder as `TashGuides.lua` files under `SavedVariables`. Deleting them (with the game closed) resets TashGuides to a clean state.

---

## Troubleshooting and FAQ

**"could not start - QuestieDB is not loaded".**
Install QuestieDB into the same `AddOns` folder, enable it, and `/reload`. If the message names a contract version problem, update QuestieDB.

**Nothing shows up after login.**
Type `/tg status`. If it says TashGuides is not ready, the message tells you why. The guide window might simply be hidden: try `/tg` or click the minimap button.

**The map has no `!` pins yet.**
The list of available quests is built gradually after login and refreshed a few seconds later. Give it a moment. If a particular quest is missing, it is probably not available to you yet (level, prerequisites, race or class). See [Which quests get a `!`](#which-quests-get-a-).

**A grey, repeatable or profession quest has no pin.**
Those kinds are controlled by separate options: **Low-level quests**, **Repeatable quests** and **Profession quests**.

**There is no arrow.**
It is hidden inside instances, and when there is no current target. Check **Show waypoint arrow** in the options. If the target is in another zone, the arrow says `Travel to <zone>`.

**The arrow keeps pointing at a mob behind me.**
Raise **Prefer spawns ahead of you** in the options. Set it to 0 if you would rather have the plain nearest spawn.

**The guide asks me to accept a quest the NPC does not offer.**
QuestieDB occasionally lacks a requirement the game enforces, most often a class: a quest from another class's trainer with no class flag in the data. TashGuides handles both ends of this. A quest whose only givers are trainers of one class (`<Hunter Trainer>`, `<Mage Trainer>`, ...) counts as that class's quest, even when the data has no class flag, unless it continues an ordinary quest chain (a trainer handing out one step of a story everyone does). And when you open an NPC's quest window, any quest the data says they should have for you but the window does not list is hidden from the guide, pins and Smart Guide, with a chat line saying so. It gets another look each time you level up, in case a level or another requirement was the reason. Grey low-level quests are never judged this way, because the client can hide those itself.

**The guide says a quest "is not in your quest log yet".**
You have not picked that quest up. Do the earlier goal in the step first.

**I am in a zone the campaign does not visit, or ahead of or behind it.**
Open the picker and choose the campaign guide for your level, or use the generated [zone guide](#zone-guides) for where you are (`/tg zone`). Zone guides appear a moment after login; if the picker shows no zones, `/tg status` says how many were built. The Smart Guide works anywhere.

**A campaign step waits on a quest I cannot do.**
Shift-click `>` to skip the step. If a quest the guide counts on is not offered to you, TashGuides notices when you open the NPC's quest window and stops waiting on it (see the next answer).

**A zone guide is missing a quest I know about, or has an odd step.**
Zone guides are built from QuestieDB's data, so they can only be as good as it is. A quest is left out if it is not for your faction, race or class, repeatable, a holiday quest, or starts from an item or inside an instance. Holiday quests are recognised by their quest category (`HOLIDAY_SORT` in `TashGuides/zones.lua`); if one slips into a guide, add its category number there. Shift-click `>` skips any step.

**A zone guide step waits on a quest I skipped.**
It should not: once you pass a pick-up without taking it, that quest's objective and hand-in steps stop waiting. If a step still sticks, Shift-click `>` and tell us the quest.

**I got stuck on a step.**
Press **Shift + right arrow** (or `/tg skip`) to skip it. Right-click a go-to, talk, hearth or fly goal to tick it by hand. `/tg reset` restarts the guide.

**Does TashGuides work in combat?**
Yes. It handles values the game restricts during combat and will not spam errors. The Blizzard tracker is only shown or hidden outside combat.

**Something is wrong with a quest location or objective.**
Locations come from QuestieDB. If the database is wrong, the fix belongs there, but please also open an issue here so it can be tracked.

---

## For guide authors and developers

### Writing a guide

A guide is a Lua file in `TashGuides/guides/` that calls `TashGuides.RegisterGuide`, listed in `TashGuides.toc`. The campaign lives in `guides/alliance/` and `guides/horde/`. A short example:

```lua
TashGuides.RegisterGuide({
    id = "A_WESTFALL", title = "Westfall", subtitle = "Levels 11-17",
    faction = "Alliance",            -- races = { "Dwarf", "Gnome" } for a starting area
    minLevel = 11, maxLevel = 17,
    area = 40,                       -- AreaID of the zone: the default map for goto goals
    areas = { 1519 },                -- other AreaIDs where the guide picks up or hands in
    next = "A_REDRIDGE",             -- the guide the right arrow offers at the end
    steps = {
        { title = "Sentinel Hill",
            { "turnin", 109 }, { "accept", 12 }, { "accept", 102 },
            note = "Gryan Stoutmantle and Captain Danuvin in the tower (56, 47)." },
        { { "talk", 523, "for the flight path" } },
        { title = "Defias on the farms", { "complete", 12 },
            note = "Trappers and Smugglers walk the fields north of the hill (44, 34)." },
    },
})
```

Goals: `{"accept", q}`, `{"complete", q}`, `{"turnin", q}`, `{"goto", x, y, "text", area = AreaID}`, `{"talk", npcId, "text"}`, `{"level", n}`, `{"hearth", "Place"}`, `{"fly", "Place"}` and `{"note", "text"}`. Any goal can be `optional = true`: it never holds a step up, and a step made only of optional goals is skipped unless you are on that chain (the quest is in your log, or an earlier quest you did has unlocked it). Step keys: `title`, `note`, `race`, `class`, and `chain = "class"` for class quests (hidden by the *Include class & race quests* opt-out). Quests another race or class cannot do are hidden automatically. Write hand-ins first in a step, then pick-ups, then objectives. The full reference is at the top of `TashGuides/guide.lua`.

### Tools

Everything runs offline against the installed QuestieDB with [LuaJIT](https://luajit.org) (`QDB=/path/to/QuestieDB` overrides the location):

| Command | What it does |
|---|---|
| `luajit tests/zdump.lua Alliance 40` | Every quest the faction can pick up in a zone (AreaID), with givers, hand-ins and coordinates, prerequisites, exclusive quests and where the objectives are. Add a level range: `... 40 10 20`. |
| `luajit tests/qlookup.lua q 783 7` | Quests in detail; `npc 823` for an NPC. |
| `luajit tests/check_guides.lua` | Validates every hand-written guide, then walks each race's campaign from its starting guide through every `next`: quests exist and suit the faction, givers stand on the guide's maps, quests are accepted before they are completed or turned in, prerequisites come first, exclusive quests and breadcrumbs are respected, child quests are taken while their parent is in the log, and the quest log never holds more than 20. `ONLY=A_WESTFALL,H_BARRENS` limits it to those guides (id prefixes) and also checks each of them on its own, so a guide can be tested before its neighbours exist. |
| `luajit tests/pace.lua` | Estimated level on arriving at and leaving each campaign guide, per race (`RACE=Tauren` for one). |
| `luajit tests/addon_sim.lua` | Loads the whole addon under a mocked client and runs the engine checks, including playing every race's campaign from level 1 to the end. `FACTION=Horde` for the Horde races. |

---

## Credits

- Quest, NPC, object and item data: **QuestieDB** and the many contributors to the Questie database.
- TashGuides is an independent project and is not affiliated with or endorsed by Blizzard Entertainment, or the Questie project.
- Bug reports and guide contributions are welcome: open an issue or pull request on the [GitHub repository](https://github.com/liltechdude/tash-guides).
