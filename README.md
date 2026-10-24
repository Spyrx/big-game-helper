# Big Game Helper

A helper for Big Game Hunter. It keeps track of your hunting supplies, your hunts and kills, and what you've learned during a hunt, so you don't have to count from your backpack or scroll back through your chat box.

Everything it shows is information you can already see in the game: your backpack, the creatures and mushrooms around you, the boss health bar, your buff and debuff bars, and the game messages in your chat box.

## Supported hunts

- Anachronia Dinosaurs
- Havenhythe Giant chinchompas
- Havenhythe Giant kebbits

## Hunt tracking

A hunt starts when the boss health bar appears with the creature's name. It ends when the herd goes into hiding, or once the bar has stayed away for 45 seconds (it's hidden during cutscenes). Havenhythe encounters are one creature each, so they end as soon as the kill is counted. Each carcass ready to skin counts as a kill, so double and triple encounters count every creature. The overlay shows the target's HP and your kills on that creature. A dinosaur's kill count resets when its herd goes into hiding, while chinchompa and kebbit kills keep counting for the session.

## Dinosaurs

### What it shows

- Supplies: jungle logs, vines and plain wooden spears in your backpack, and whether you have enough for a full trap set: 4 logs and 3 vines, plus 3 spears (each spear you haven't made yet counts as 1 more log to fletch).
- Poisons: one row per frog colour (sky-blue, golden, phantasmal) with:
  - the damage you've seen that poison deal to the current dinosaur (30k, 15k or 7.5k)
  - how many spears tipped with that poison you're carrying
  - how many frogs of that colour are nearby
- Frog labels: a small tag over each poison frog showing the damage you've already seen its poison do. Frogs whose colour you haven't tested yet get no label.

### Poison damage

Each dinosaur reassigns its poisons when its herd goes into hiding, so damage is tracked per dinosaur and never saved between logins. When a herd goes into hiding (its debuff appears, or the game says so in chat), that dinosaur's learned damage is cleared.

The plugin only shows damage you've actually seen (or entered by hand). It doesn't guess the colours you haven't tested. There are two ways to record it:

- Automatically: allow the plugin's optional `chat access` permission. When a poisoned spear hits, the game reports the damage in your chat box and the plugin records it.
- By hand: open `Set damage by hand` at the bottom of the overlay and pick the damage you saw for each colour.

## Giant chinchompas

### What it shows

- Supplies: giant logs and rope in your backpack, and whether you have enough for a full trap set: 5 logs and 7 rope (three log traps and the giant box trap).
- Poisons: one row per moth (verdite, lazurite, purpurite) with:
  - the damage you've seen that moth's poison deal to the current chinchompa (30k, 15k or 7.5k)
  - how many of those moths you're carrying
  - how many of those moths are flying nearby
- Moth labels: a small tag over each poison moth showing the damage you've already seen its poison do, like the frog labels.

### Poison damage

Damage is recorded the same two ways as for dinosaurs. The game's damage messages name the poison rather than the moth (nightshade for purpurite, blue-death for lazurite, luminious for verdite), and the plugin matches them up.

Chinchompas don't go into hiding. Once you've found the strongest poison, the game shows a "Strongest poison" buff with a timer. When the timer runs out, the poisons change at your next encounter with that chinchompa, so its learned damage is cleared when that encounter starts.

The poisons also don't carry over if you hunt another chinchompa or a kebbit in between, so learned damage is only kept for the last creature you hunted at Havenhythe.

## Giant kebbits

### What it shows

- Supplies: giant logs, rocks and plain grenwall spikes in your backpack, and whether you have enough for a full trap set: 4 logs, 1 rock and 3 spikes (three spike traps and the giant deadfall trap). Plain and poisoned spikes both count, since poisoning them is free.
- Poisons: one row per mushroom (luminious, blue-deathcap, nightshade) with:
  - the damage you've seen that poison deal to the current kebbit (30k, 15k or 7.5k)
  - how many spikes tipped with that poison you're carrying
- Mushroom labels: a small tag over each poison mushroom showing the damage you've already seen its poison do.

### Poison damage

Damage is recorded the same two ways as for dinosaurs, from the same damage messages as the chinchompas use. The poisons also change the same way: once the "Strongest poison" buff's timer runs out, that kebbit's learned damage is cleared when your next encounter with it starts, and it isn't kept if you hunt another kebbit or a chinchompa in between.

## Settings

Open them from the settings icon in the Plugin Hub:

- Show the overlay only while hunting, always, or never. "Only while hunting" shows it from the first creature you see at the hunting grounds until you leave them.
- Turn frog, moth and mushroom labels on or off.

## The overlay

Drag the overlay's title bar to move it, and its edges or corners to resize it. It remembers where you left it. Closing it hides it until your next hunt starts, or until you next arrive at the hunting grounds. To bring it back sooner, click the plugin's icon in the Plugins window, or `Show overlay` in its settings.

## Requirements

- [PrettyUI](https://prettyui.j3.gg/), installed automatically as a dependency.
