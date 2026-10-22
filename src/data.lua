-- Static game data for Anachronia Big Game Hunter.
-- IDs come from the client's own config tables (id.* / config.*), and display names
-- are read from the game so labels always match what the player sees in-game.

local Data = {}

-- Damage a poisoned spear deals to a dinosaur. Each session, one colour deals each value.
-- Source: https://runescape.wiki/w/Anachronia_Big_Game_Hunter/Strategies
Data.DAMAGE_TIERS = { 30000, 15000, 7500 }

Data.IS_DAMAGE_TIER = {}
for _, damage in ipairs(Data.DAMAGE_TIERS) do Data.IS_DAMAGE_TIER[damage] = true end

-- Materials for one full trap set: a pressure plate (1 log) and three scorpions
-- (1 log + 1 vine each), each armed with a spear. Spears are fletched from 1 log each, and
-- poisoned for free at the frogs.
Data.TRAP_SET_COST = { logs = 4, vines = 3, spears = 3 }
Data.LOGS_PER_SPEAR = 1

Data.LOGS = config.Obj.DINO_GAME_LOGS
Data.VINES = config.Obj.DINO_GAME_VINES
Data.SPEAR = config.Obj.DINO_GAME_SPEAR

-- Text colours used to tint each poison's labels, matched by keyword in its name.
local POISON_RGBA = {
    { keyword = "sky", rgba = 0x7FD3FFFF },
    { keyword = "gold", rgba = 0xFFD54AFF },
    -- The frog itself is pink, but the game shows phantasmal hitsplats and messages in red.
    { keyword = "phantasm", rgba = 0xFF4040FF },
}
local DEFAULT_RGBA = 0xE7D7B0FF

-- Poison N's spear and frog share a colour, e.g. DINO_GAME_SPEAR_POISON_1 is tipped
-- from DINO_GAME_FROG_POISON_1.
local POISON_CONFIGS = {
    { spear = config.Obj.DINO_GAME_SPEAR_POISON_1, frogID = id.NPC.DINO_GAME_FROG_POISON_1 },
    { spear = config.Obj.DINO_GAME_SPEAR_POISON_2, frogID = id.NPC.DINO_GAME_FROG_POISON_2 },
    { spear = config.Obj.DINO_GAME_SPEAR_POISON_3, frogID = id.NPC.DINO_GAME_FROG_POISON_3 },
}

--- Reads the colour word ("Sky-blue", "Golden", "Phantasmal") from the frog or spear's in-game name.
local function colourName(poison, index)
    local frog = config.NPC.FromID(poison.frogID)
    local name = frog and frog.name and frog.name:match("^(.-) poison frog$")
    if not name and poison.spear and poison.spear.name then
        name = poison.spear.name:match("%((.-) poison%)")
    end
    if not name or name == "" then return "Poison " .. index end
    return (name:gsub("^%l", string.upper))
end

Data.POISONS = {}
Data.POISON_BY_FROG_ID = {}
for index, poison in ipairs(POISON_CONFIGS) do
    local label = colourName(poison, index)
    local rgba = DEFAULT_RGBA
    for _, colour in ipairs(POISON_RGBA) do
        if label:lower():find(colour.keyword, 1, true) then rgba = colour.rgba end
    end
    Data.POISONS[index] = {
        label = label,
        -- Lower-case colour name used to spot this poison in game messages.
        keyword = label:lower(),
        rgba = rgba,
        spear = poison.spear,
    }
    Data.POISON_BY_FROG_ID[poison.frogID] = index
end

-- The nine huntable dinosaurs, by NPC ID and by lower-case display name.
--   DINO_GAME_CREATURE_1  26430  Arcane apoterrasaur
--   DINO_GAME_CREATURE_2  26431  Scimitops
--   DINO_GAME_CREATURE_3  26432  Bagrada rex
--   DINO_GAME_CREATURE_4  26433  Spicati apoterrasaur
--   DINO_GAME_CREATURE_5  26434  Asciatops
--   DINO_GAME_CREATURE_6  26435  Corbicula rex
--   DINO_GAME_CREATURE_7  26436  Oculi apoterrasaur
--   DINO_GAME_CREATURE_8  26437  Malletops
--   DINO_GAME_CREATURE_9  26438  Pavosaurus rex
Data.IS_DINOSAUR_ID = {}
Data.DINOSAUR_BY_NAME = {}
for creature = 1, 9 do
    local npcID = id.NPC["DINO_GAME_CREATURE_" .. creature]
    Data.IS_DINOSAUR_ID[npcID] = true
    local npc = config.NPC.FromID(npcID)
    if npc and npc.name then Data.DINOSAUR_BY_NAME[npc.name:lower()] = npc.name end
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

--- Returns the dinosaur named anywhere in a piece of text, or nil.
function Data.FindDinosaurName(text)
    local lower = text:lower()
    for lowerName, name in pairs(Data.DINOSAUR_BY_NAME) do
        if lower:find(lowerName, 1, true) then return name end
    end
    return nil
end

-- The debuff bar has 50 slots, DEBUFF_BAR__BUFF_1 to DEBUFF_BAR__BUFF_50.
Data.DEBUFF_SLOT_COUNT = 50

-- When a herd goes into hiding, a debuff with one of these icons appears, showing the time
-- left (e.g. "59m"). There's one icon per species, ICON_BUFF_DINO1 to ICON_BUFF_DINO9.
Data.IS_HIDING_SPRITE = {}
for creature = 1, 9 do
    local spriteID = id.Sprite["ICON_BUFF_DINO" .. creature]
    if spriteID then Data.IS_HIDING_SPRITE[spriteID] = true end
end

-- Possible future targets (Havenhythe big game). Names for 32780, 32781, 32784 and 32788
-- are from the RuneScape Wiki, not yet seen in-game.
--   Giant chinchompa              32778  BIG_GAME_HUNTER_HAVENHYTHE_CHINCHOMPA_1
--   Giant carnivorous chinchompa  32779  BIG_GAME_HUNTER_HAVENHYTHE_CHINCHOMPA_2
--   Giant volatile chinchompa     32780  BIG_GAME_HUNTER_HAVENHYTHE_CHINCHOMPA_3
--   Giant golden chinchompa       32781  BIG_GAME_HUNTER_HAVENHYTHE_CHINCHOMPA_4
--   Giant kebbit                  32782  BIG_GAME_HUNTER_HAVENHYTHE_KEBBIT_1
--   Giant spiked kebbit           32784  BIG_GAME_HUNTER_HAVENHYTHE_KEBBIT_2
--   Giant diseased kebbit         32786  BIG_GAME_HUNTER_HAVENHYTHE_KEBBIT_3
--   Giant dashing kebbit          32788  BIG_GAME_HUNTER_HAVENHYTHE_KEBBIT_4

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

--- Formats a damage values: 30000 -> "30k", 7500 -> "7.5k".
function Data.FormatDamage(damage)
    local thousands = damage / 1000
    if thousands == math.floor(thousands) then return string.format("%dk", thousands) end
    return string.format("%.1fk", thousands)
end

return Data
