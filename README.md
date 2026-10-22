# Big Game Helper

A helper for Big Game Hunter. It keeps track of your hunting supplies, your hunts and kills,
and what you've learned during a hunt, so you don't have to count from your backpack or scroll
back through your chat box.

Everything it shows is information you can already see in the game: your backpack, the
creatures around you, the boss health bar and debuff bar, and the game messages in your chat
box.

## Supported hunts

- Anachronia Dinosaurs
- Havenhythe is planned

## Hunt tracking

A hunt starts when the boss health bar appears with the creature's name, and ends once the bar
has stayed away for 45 seconds (it's hidden during cutscenes). Each carcass ready to skin counts
as a kill, so double and triple encounters count every creature. The overlay shows the target's
HP and counts your kills this session.

## Dinosaurs

### What it shows

- Supplies: jungle logs, vines and plain wooden spears in your backpack, and whether you have
  enough for a full trap set: 4 logs and 3 vines, plus 3 spears (each spear you haven't made
  yet counts as 1 more log to fletch).
- Poisons: one row per frog colour (sky-blue, golden, phantasmal) with:
  - the damage you've seen that poison deal to the current dinosaur (30k, 15k or 7.5k)
  - how many spears tipped with that poison you're carrying
  - how many frogs of that colour are nearby
- Frog labels: a small tag over each poison frog showing the damage you've already seen
  its poison do. Frogs whose colour you haven't tested yet get no label.

### Poison damage

Each dinosaur reassigns its poisons when its herd goes into hiding, so damage is tracked per
dinosaur and never saved between logins. When a herd goes into hiding (its debuff appears, or
the game says so in chat), that dinosaur's learned damage is cleared.

The plugin only shows damage you've actually seen (or entered by hand). It doesn't guess the
colours you haven't tested. There are two ways to record it:

- Automatically: allow the plugin's optional `chat access` permission. When a poisoned
  spear hits, the game reports the damage in your chat box and the plugin records it.
- By hand: open `Set damage by hand` at the bottom of the overlay and pick the damage
  you saw for each colour.

## Settings

Open them from the settings icon in the Plugin Hub:

- Show the overlay only while hunting, always, or never. "Only while hunting" shows it from
  the first creature you see at the hunting grounds until you leave them.
- Turn frog labels on or off.

## The overlay

Drag the overlay's title bar to move it, and its edges or corners to resize it. It remembers
where you left it. Closing it hides it until your next hunt starts, or until you next arrive at
the hunting grounds. To bring it back sooner,
click the plugin's icon in the Plugins window, or `Show overlay` in its settings.

## Requirements

- [PrettyUI](https://prettyui.j3.gg/), installed automatically as a dependency.
