-- Static game data for Big Game Hunter, with one definition per kind of hunt.
-- IDs come from the client's own config tables (id.* / config.*), and display names
-- are read from the game so labels always match what the player sees in-game.

local Data = {}

-- Damage a poison deals to a big game creature. Each of a creature's three poisons deals a
-- different one of these, until its poisons are reassigned.
-- Sources: https://runescape.wiki/w/Anachronia_Big_Game_Hunter/Strategies
--          https://runescape.wiki/w/Havenhythe_Big_Game_Hunter/Strategies
Data.DAMAGE_TIERS = { 30000, 15000, 7500 }

Data.IS_DAMAGE_TIER = {}
for _, damage in ipairs(Data.DAMAGE_TIERS) do Data.IS_DAMAGE_TIER[damage] = true end

--- "1 spear", "3 spears". plural is only needed when it isn't word .. "s", e.g. "rope".
function Data.Plural(count, word, plural)
    return count .. " " .. (count == 1 and word or plural or word .. "s")
end

local DEFAULT_RGBA = 0xE7D7B0FF

--- Describes what's missing for one full trap set, if anything, and whether there's enough.
--- needs lists { word, plural, have, need } for each material (see Data.Plural).
local function trapSetStatus(needs)
    local short = {}
    for _, material in ipairs(needs) do
        local missing = material.need - material.have
        if missing > 0 then table.insert(short, Data.Plural(missing, material.word, material.plural)) end
    end
    if #short == 0 then return "Enough for a full trap set", true end
    return "Short for a trap set: " .. table.concat(short, ", "), false
end

local function countPoisoned(hunt, count)
    local total = 0
    for _, poison in ipairs(hunt.poisons) do total = total + count(poison.item) end
    return total
end

--- Builds a hunt's poisons from { item, carrierID, carrierLocID, label, keywords, rgba } entries.
--- item is the backpack item the poison is used from, and carrierID the NPC it comes from
--- (or carrierLocID the scenery, e.g. a mushroom).
local function definePoisons(entries)
    local poisons = {}
    for index, entry in ipairs(entries) do
        local label = entry.label or ("Poison " .. index)
        poisons[index] = {
            label = label,
            -- Lower-case words used to spot this poison in game messages.
            keywords = entry.keywords or { label:lower() },
            rgba = entry.rgba or DEFAULT_RGBA,
            item = entry.item,
            carrierID = entry.carrierID,
            carrierLocID = entry.carrierLocID,
        }
    end
    return poisons
end

--- Reads a name from an NPC's or scenery's in-game name with a pattern, e.g. "Golden" from
--- "Golden poison frog". configs is config.NPC or config.Loc.
local function nameFromConfig(configs, configID, pattern)
    local entity = configID and configs.FromID(configID)
    local name = entity and entity.name and entity.name:match(pattern)
    if not name or name == "" then return nil end
    return (name:gsub("^%l", string.upper))
end

--------------------------------------------------------------------------------------------
-- Dinosaurs (Anachronia)

-- Text colours used to tint each poison's labels, matched by keyword in its name.
local FROG_RGBA = {
    { keyword = "sky", rgba = 0x7FD3FFFF },
    { keyword = "gold", rgba = 0xFFD54AFF },
    -- The frog itself is pink, but the game shows phantasmal hitsplats and messages in red.
    { keyword = "phantasm", rgba = 0xFF4040FF },
}

-- Materials for one full dinosaur trap set: a pressure plate (1 log) and three scorpions
-- (1 log + 1 vine each), each armed with a spear. Spears are fletched from 1 log each, and
-- poisoned for free at the frogs.
local DINO_TRAP_SET_COST = { logs = 4, vines = 3, spears = 3 }
local LOGS_PER_SPEAR = 1

local DINO_LOGS = config.Obj.DINO_GAME_LOGS
local DINO_VINES = config.Obj.DINO_GAME_VINES
local DINO_SPEAR = config.Obj.DINO_GAME_SPEAR

-- Poison N's spear and frog share a colour, e.g. DINO_GAME_SPEAR_POISON_1 is tipped
-- from DINO_GAME_FROG_POISON_1.
local dinoPoisons = {}
for index = 1, 3 do
    local spear = config.Obj["DINO_GAME_SPEAR_POISON_" .. index]
    local frogID = id.NPC["DINO_GAME_FROG_POISON_" .. index]
    -- The colour word ("Sky-blue", "Golden", "Phantasmal") from the frog or spear's in-game name.
    local label = nameFromConfig(config.NPC, frogID, "^(.-) poison frog$")
    if not label and spear and spear.name then
        label = spear.name:match("%((.-) poison%)")
        label = label and label ~= "" and (label:gsub("^%l", string.upper)) or nil
    end
    local rgba
    for _, colour in ipairs(FROG_RGBA) do
        if label and label:lower():find(colour.keyword, 1, true) then rgba = colour.rgba end
    end
    dinoPoisons[index] = { item = spear, carrierID = frogID, label = label, rgba = rgba }
end

Data.DINOSAURS = {
    key = "dinosaurs",
    creatureWord = "dinosaur",
    hitDescription = "poisoned spears hit",
    supplies = { DINO_LOGS, DINO_VINES, DINO_SPEAR },
    poisons = definePoisons(dinoPoisons),
    -- The nine huntable dinosaurs:
    --   DINO_GAME_CREATURE_1  26430  Arcane apoterrasaur
    --   DINO_GAME_CREATURE_2  26431  Scimitops
    --   DINO_GAME_CREATURE_3  26432  Bagrada rex
    --   DINO_GAME_CREATURE_4  26433  Spicati apoterrasaur
    --   DINO_GAME_CREATURE_5  26434  Asciatops
    --   DINO_GAME_CREATURE_6  26435  Corbicula rex
    --   DINO_GAME_CREATURE_7  26436  Oculi apoterrasaur
    --   DINO_GAME_CREATURE_8  26437  Malletops
    --   DINO_GAME_CREATURE_9  26438  Pavosaurus rex
    creatureIDs = {},
    -- When a herd goes into hiding, a debuff with one of these icons appears, showing the time
    -- left (e.g. "59m"). There's one icon per species, ICON_BUFF_DINO1 to ICON_BUFF_DINO9.
    hidingSprites = {},
}
for creature = 1, 9 do
    table.insert(Data.DINOSAURS.creatureIDs, id.NPC["DINO_GAME_CREATURE_" .. creature])
    local spriteID = id.Sprite["ICON_BUFF_DINO" .. creature]
    if spriteID then Data.DINOSAURS.hidingSprites[spriteID] = true end
end

--- e.g. "2 spears, 3 frogs" for one poison's row.
function Data.DINOSAURS.Detail(carried, nearby)
    return Data.Plural(carried, "spear") .. ", " .. Data.Plural(nearby, "frog")
end

--- Describes what's missing for one full trap set, if anything, and whether there's enough.
--- Spears not yet made are counted as the logs needed to fletch them.
function Data.DINOSAURS.TrapSetStatus(count)
    local spears = count(DINO_SPEAR) + countPoisoned(Data.DINOSAURS, count)
    local spearsToMake = math.max(0, DINO_TRAP_SET_COST.spears - spears)
    return trapSetStatus({
        { word = "log", have = count(DINO_LOGS), need = DINO_TRAP_SET_COST.logs + spearsToMake * LOGS_PER_SPEAR },
        { word = "vine", have = count(DINO_VINES), need = DINO_TRAP_SET_COST.vines },
    })
end

--------------------------------------------------------------------------------------------
-- Havenhythe, shared by the chinchompas and kebbits

-- Havenhythe's three poisons, shared by the chinchompas' moths and the kebbits' mushrooms. The
-- damage messages name the poison, e.g. "Nightshade poison damage dealt: 30,000".
-- "Luminious" is the game's own spelling; "lumin" also matches if it's ever corrected.
local HAVENHYTHE_POISONS = {
    { colour = "GREEN", keywords = { "lumin" }, rgba = 0x7CDB6AFF },
    { colour = "BLUE", keywords = { "blue-death" }, rgba = 0x6AA8FFFF },
    { colour = "PURPLE", keywords = { "nightshade" }, rgba = 0xC890FFFF },
}

local HAVENHYTHE_LOGS = config.Obj.BIG_GAME_HUNTER_HAVENHYTHE_LOGS
local HAVENHYTHE_ROPE = config.Obj.BIG_GAME_HUNTER_HAVENHYTHE_ROPE
local HAVENHYTHE_STONE = config.Obj.BIG_GAME_HUNTER_HAVENHYTHE_STONE
local GRENWALL_SPIKES = config.Obj.GREN_SPIKE

--------------------------------------------------------------------------------------------
-- Giant chinchompas (Havenhythe)

-- Moth N (Verdite, Lazurite, Purpurite) comes from hollow tree moth NPC N and carries
-- Havenhythe poison N, e.g. BIG_GAME_HUNTER_HAVENHYTHE_MOTH_1 is carried as MOTH_GREEN.
local chinchompaPoisons = {}
for index, poison in ipairs(HAVENHYTHE_POISONS) do
    local npcID = id.NPC["BIG_GAME_HUNTER_HAVENHYTHE_MOTH_" .. index]
    chinchompaPoisons[index] = {
        item = config.Obj["BIG_GAME_HUNTER_HAVENHYTHE_MOTH_" .. poison.colour],
        carrierID = npcID,
        -- The moth's name ("Verdite"), as on the "Strongest poison" buff.
        label = nameFromConfig(config.NPC, npcID, "^(.-) moth$"),
        keywords = poison.keywords,
        rgba = poison.rgba,
    }
end

-- Materials for one full chinchompa trap set: three log traps (1 giant log + 2 rope each) and
-- the giant box trap (2 giant logs + 1 rope).
-- Source: https://runescape.wiki/w/Havenhythe_Big_Game_Hunter/Strategies
local CHINCHOMPA_TRAP_SET_COST = { logs = 5, rope = 7 }

Data.CHINCHOMPAS = {
    key = "chinchompas",
    creatureWord = "chinchompa",
    hitDescription = "your traps hit",
    supplies = { HAVENHYTHE_LOGS, HAVENHYTHE_ROPE },
    poisons = definePoisons(chinchompaPoisons),
    --   Giant chinchompa              32778  BIG_GAME_HUNTER_HAVENHYTHE_CHINCHOMPA_1
    --   Giant carnivorous chinchompa  32779  BIG_GAME_HUNTER_HAVENHYTHE_CHINCHOMPA_2
    --   Giant volatile chinchompa     32780  BIG_GAME_HUNTER_HAVENHYTHE_CHINCHOMPA_3
    --   Giant golden chinchompa       32781  BIG_GAME_HUNTER_HAVENHYTHE_CHINCHOMPA_4
    creatureIDs = {},
    -- Once the strongest poison has been found, a buff, e.g. "Strongest poison - Purpurite moth",
    -- appears, showing that moth's icon and the time until the poisons change.
    strongestPoisonBuff = true,
    -- Each encounter is a single chinchompa, and it can be hunted again straight away.
    oneCreaturePerEncounter = true,
}
for creature = 1, 4 do
    table.insert(Data.CHINCHOMPAS.creatureIDs, id.NPC["BIG_GAME_HUNTER_HAVENHYTHE_CHINCHOMPA_" .. creature])
end

--- e.g. "2 moths, 3 nearby" for one poison's row.
function Data.CHINCHOMPAS.Detail(carried, nearby)
    return Data.Plural(carried, "moth") .. ", " .. nearby .. " nearby"
end

--- Describes what's missing for one full trap set, if anything, and whether there's enough.
function Data.CHINCHOMPAS.TrapSetStatus(count)
    return trapSetStatus({
        { word = "log", have = count(HAVENHYTHE_LOGS), need = CHINCHOMPA_TRAP_SET_COST.logs },
        { word = "rope", plural = "rope", have = count(HAVENHYTHE_ROPE), need = CHINCHOMPA_TRAP_SET_COST.rope },
    })
end

--------------------------------------------------------------------------------------------
-- Giant kebbits (Havenhythe)

-- Materials for one full kebbit trap set: three spike traps (1 giant log + 1 poisoned spike
-- each) and the giant deadfall trap (1 giant log + 1 rock). Spikes are poisoned for free at the
-- mushrooms.
-- Source: https://runescape.wiki/w/Havenhythe_Big_Game_Hunter/Strategies
local KEBBIT_TRAP_SET_COST = { logs = 4, rocks = 1, spikes = 3 }

-- Grenwall spikes are poisoned at the mushroom of each colour, e.g. MUSHROOM_GREEN
-- ("Luminious mushroom") makes KEBBIT_SPIKES_GREEN. There's one mushroom of each colour.
local kebbitPoisons = {}
for index, poison in ipairs(HAVENHYTHE_POISONS) do
    local mushroomID = id.Loc["BIG_GAME_HUNTER_HAVENHYTHE_MUSHROOM_" .. poison.colour]
    kebbitPoisons[index] = {
        item = config.Obj["BIG_GAME_HUNTER_HAVENHYTHE_KEBBIT_SPIKES_" .. poison.colour],
        carrierLocID = mushroomID,
        -- The mushroom's name ("Blue-deathcap").
        label = nameFromConfig(config.Loc, mushroomID, "^(.-) mushroom$"),
        keywords = poison.keywords,
        rgba = poison.rgba,
    }
end

Data.KEBBITS = {
    key = "kebbits",
    creatureWord = "kebbit",
    hitDescription = "your traps hit",
    supplies = { HAVENHYTHE_LOGS, HAVENHYTHE_STONE, GRENWALL_SPIKES },
    poisons = definePoisons(kebbitPoisons),
    --   Giant kebbit                  32782  BIG_GAME_HUNTER_HAVENHYTHE_KEBBIT_1
    --   Giant spiked kebbit           32784  BIG_GAME_HUNTER_HAVENHYTHE_KEBBIT_2
    --   Giant diseased kebbit         32786  BIG_GAME_HUNTER_HAVENHYTHE_KEBBIT_3
    --   Giant dashing kebbit          32788  BIG_GAME_HUNTER_HAVENHYTHE_KEBBIT_4
    -- Each has a "Kebbit watcher" (KEBBIT_1_OUTER and so on) nearby, which isn't hunted.
    creatureIDs = {},
    -- Like the chinchompas' buff, showing the strongest poison's spikes, e.g.
    -- KEBBIT_SPIKES_GREEN.
    strongestPoisonBuff = true,
    -- Each encounter is a single kebbit, and it can be hunted again straight away.
    oneCreaturePerEncounter = true,
}
for creature = 1, 4 do
    table.insert(Data.KEBBITS.creatureIDs, id.NPC["BIG_GAME_HUNTER_HAVENHYTHE_KEBBIT_" .. creature])
end

--- e.g. "2 spikes" for one poison's row. There's only ever one mushroom of each colour, so
--- it isn't counted.
function Data.KEBBITS.Detail(carried)
    return Data.Plural(carried, "spike")
end

--- Describes what's missing for one full trap set, if anything, and whether there's enough.
--- Plain spikes count too, since they're poisoned for free.
function Data.KEBBITS.TrapSetStatus(count)
    return trapSetStatus({
        { word = "log", have = count(HAVENHYTHE_LOGS), need = KEBBIT_TRAP_SET_COST.logs },
        { word = "rock", have = count(HAVENHYTHE_STONE), need = KEBBIT_TRAP_SET_COST.rocks },
        { word = "spike", have = count(GRENWALL_SPIKES) + countPoisoned(Data.KEBBITS, count),
          need = KEBBIT_TRAP_SET_COST.spikes },
    })
end

--------------------------------------------------------------------------------------------
-- Lookups across every hunt

Data.HUNTS = { Data.DINOSAURS, Data.CHINCHOMPAS, Data.KEBBITS }

-- Hunt by creature NPC ID, and { hunt, poison index } by the NPC a poison comes from.
Data.HUNT_BY_CREATURE_ID = {}
Data.CARRIER_BY_ID = {}
-- Hunt by the item ID whose icon its "Strongest poison" buff shows, e.g. a moth for chinchompas.
Data.STRONGEST_POISON_ICONS = {}
-- { name, hunt } by lower-case creature name, e.g. "giant chinchompa".
local CREATURE_BY_NAME = {}
for _, hunt in ipairs(Data.HUNTS) do
    for _, npcID in ipairs(hunt.creatureIDs) do
        Data.HUNT_BY_CREATURE_ID[npcID] = hunt
        local npc = config.NPC.FromID(npcID)
        if npc and npc.name then CREATURE_BY_NAME[npc.name:lower()] = { name = npc.name, hunt = hunt } end
    end
    for index, poison in ipairs(hunt.poisons) do
        if poison.carrierID then Data.CARRIER_BY_ID[poison.carrierID] = { hunt = hunt, poison = index } end
        if hunt.strongestPoisonBuff and poison.item then Data.STRONGEST_POISON_ICONS[poison.item.id] = hunt end
    end
end

--- Returns the creature named anywhere in a piece of text and its hunt, or nil. The longest
--- name wins, in case one creature's name is part of another's.
function Data.FindCreature(text)
    local lower = text:lower()
    local found
    for lowerName, creature in pairs(CREATURE_BY_NAME) do
        if lower:find(lowerName, 1, true) and (not found or #lowerName > #found.name) then found = creature end
    end
    if not found then return nil end
    return found.name, found.hunt
end

-- Interfaces that open when a hunt starts: the boss health bar (an activity progress bar,
-- with an extension panel) and an activity-specific buff bar.
Data.HUNT_INTERFACES = {
    id.Interface.ACTIVITY_PROGRESS_BAR,
    id.Interface.ACTIVITY_PROGRESS_BAR_EXTENSION,
    id.Interface.ACTIVITY_BUFF_BAR,
}

-- Boss health bar text showing the hunted creature's name, e.g. "Arcane Apoterrasaur".
Data.BOSS_BAR_NAME_COMPONENTS = {
    id.Component.ACTIVITY_PROGRESS_BAR__ACTIVITY_NAME_TEXT,
}
-- Boss health bar tooltip text showing the creature's remaining HP, e.g. "90,000".
Data.BOSS_BAR_HP_COMPONENT = id.Component.ACTIVITY_PROGRESS_BAR__TOOLTIP_PROGRESS_AMOUNT

-- The buff and debuff bars have 50 slots each, e.g. DEBUFF_BAR__BUFF_1 to DEBUFF_BAR__BUFF_50.
Data.BAR_SLOT_COUNT = 50

--- Formats a whole number with thousands separators: 90000 -> "90,000".
function Data.FormatNumber(value)
    local text = tostring(math.floor(value))
    local formatted
    repeat
        formatted = text
        text = text:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
    until text == formatted
    return formatted
end

--- Formats a damage value: 30000 -> "30k", 15000 -> "15k", 7500 -> "7.5k".
function Data.FormatDamage(damage)
    local thousands = damage / 1000
    if thousands == math.floor(thousands) then return string.format("%dk", thousands) end
    return string.format("%.1fk", thousands)
end

return Data
