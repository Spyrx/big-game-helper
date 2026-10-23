-- Tracks everything the overlay shows. All of it is information already visible to the player:
--   * backpack contents (hunting supplies, and the poisoned items for each poison)
--   * the creatures being hunted and the poison carriers (frogs, moths, mushrooms) around the
--     player, while in an instance (the hunting grounds)
--   * poison damage, read from game messages in the chat box or entered by hand

local Data = require("src/data")

local Tracker = {
    -- The kind of hunt the current creature belongs to (see Data.HUNTS).
    hunt = Data.DINOSAURS,
    -- Backpack item counts by item ID, for every hunt's supplies and poisoned items.
    itemCounts = {},
    -- Poison carriers of the current hunt nearby, keyed by NPC uid or scenery position:
    -- { npc = NPCEntity, poison = index } for frogs and moths, or { loc = LocEntity, ... } for
    -- mushrooms.
    carriers = {},
    carrierCounts = { 0, 0, 0 },
    -- The most recently seen creature's name.
    creature = nil,
    -- True from when a creature is first seen in an instance until the player leaves it.
    atHuntingGround = false,
    -- Set once a hunt's boss health bar has named the target, so that other creatures
    -- wandering into view don't change it. Only a new hunt changes the target after that.
    creatureLocked = false,
    -- Learned damage per creature name: damageByCreature[name][poisonIndex] = damage.
    -- Poisons are reassigned from time to time, so this is never saved to disk.
    damageByCreature = {},
    logicTick = 0,
    listeners = {},
    scanSignature = "",
}

-- Our own messages, and notifications that name other players without a sender attached
-- (logins, friends, ignores). None of them are hunting messages, so they're never read.
local IGNORED_CHAT_TYPES = {
    [ChatType.PLUGIN] = true,
    [ChatType.LOGIN_LOGOUT] = true,
    [ChatType.FRIEND_CHAT_NOTIFICATION] = true,
    [ChatType.FRIEND_NOTIFICATION] = true,
    [ChatType.IGNORE_NOTIFICATION] = true,
}

local function notify()
    for _, callback in ipairs(Tracker.listeners) do callback() end
end

function Tracker.OnChange(callback)
    table.insert(Tracker.listeners, callback)
end

--- The key damage learned before any creature was seen is kept under, per hunt.
local function unknownKey(hunt)
    return hunt.key .. ":?"
end

local function currentDamageTable()
    local key = Tracker.creature or unknownKey(Tracker.hunt)
    local damage = Tracker.damageByCreature[key]
    if not damage then
        damage = {}
        Tracker.damageByCreature[key] = damage
    end
    return damage
end

--- Returns the damage the player has seen a poison deal to the current creature, or nil if
--- they haven't seen it yet. Only damage actually seen (or entered by hand) is ever shown.
function Tracker.GetDamage(poisonIndex)
    return currentDamageTable()[poisonIndex]
end

--- Records a poison's damage against the current creature. Pass nil to forget it.
function Tracker.SetDamage(poisonIndex, damage)
    local known = currentDamageTable()
    if damage then
        -- A damage tier can only belong to one poison, so drop any older, conflicting entry.
        for index, value in pairs(known) do
            if value == damage and index ~= poisonIndex then known[index] = nil end
        end
    end
    known[poisonIndex] = damage
    notify()
end

--- Forgets everything learned about the current creature.
function Tracker.ResetCurrent()
    Tracker.damageByCreature[Tracker.creature or unknownKey(Tracker.hunt)] = {}
    notify()
end

--- Forgets everything learned about one creature, e.g. when its herd goes into hiding or its
--- poisons change.
function Tracker.ForgetCreature(name)
    Tracker.damageByCreature[name] = nil
    notify()
end

--- Forgets all learned damage, e.g. after logging out (which ends the hunting session).
function Tracker.ClearAll()
    Tracker.damageByCreature = {}
    Tracker.atHuntingGround = false
    notify()
end

--- Number of an item in the backpack, as last counted.
function Tracker.Count(obj)
    return obj and Tracker.itemCounts[obj.id] or 0
end

function Tracker.RefreshInventory()
    -- The docs say Find returns a single Inv with an isValid field (the stubs differ).
    local backpack = Inventory.Find(id.Inv.INV) --[[@as Inv?]]
    ---@diagnostic disable-next-line: undefined-field
    if not backpack or backpack.isValid == false then return end

    local counts = {}
    for _, hunt in ipairs(Data.HUNTS) do
        for _, obj in ipairs(hunt.supplies) do counts[obj.id] = backpack:GetTotal(obj) end
        for _, poison in ipairs(hunt.poisons) do counts[poison.item.id] = backpack:GetTotal(poison.item) end
    end
    Tracker.itemCounts = counts
    notify()
end

--- Finds the poison carriers and hunted creatures currently loaded around the player.
--- Mushrooms are scenery, so they're looked up as well as NPCs.
function Tracker.Scan(logicTick)
    Tracker.logicTick = logicTick
    if not Player.IsAvailable() or not World.IsAvailable() then return end

    local found = {}
    -- Hunting happens in the player's own instance, so creatures and carriers are only looked
    -- for there. Every NPC loaded in an instance belongs to the player's own hunt.
    local inInstance = World.IsRegion()
    if not inInstance then Tracker.atHuntingGround = false end
    for _, npc in ipairs(inInstance and NPCList.All() or {}) do
        local carrier = Data.CARRIER_BY_ID[npc.configID]
        if carrier then
            table.insert(found, { key = npc.uid, npc = npc, hunt = carrier.hunt, poison = carrier.poison })
        elseif Data.HUNT_BY_CREATURE_ID[npc.configID] or Data.HUNT_BY_CREATURE_ID[npc.parentConfigID] then
            Tracker.atHuntingGround = true
            if not Tracker.creatureLocked then Tracker.SetCreature(npc.displayName) end
        end
    end

    -- Scenery carriers are only looked for in the current hunt, by their config.
    for index, poison in ipairs(inInstance and Tracker.hunt.poisons or {}) do
        for _, loc in ipairs(poison.carrierLocID and LocList.ByConfigID(poison.carrierLocID) or {}) do
            local coord = loc.coordGrid
            local key = string.format("loc %d,%d,%d", coord.x, coord.z, coord.level)
            table.insert(found, { key = key, loc = loc, hunt = Tracker.hunt, poison = index })
        end
    end

    -- Only the current hunt's carriers are shown.
    local carriers, carrierCounts = {}, {}
    local signature = {}
    for index = 1, #Tracker.hunt.poisons do carrierCounts[index] = 0 end
    for _, carrier in ipairs(found) do
        if carrier.hunt == Tracker.hunt then
            carriers[carrier.key] = { npc = carrier.npc, loc = carrier.loc, poison = carrier.poison }
            carrierCounts[carrier.poison] = carrierCounts[carrier.poison] + 1
            table.insert(signature, carrier.key .. ":" .. carrier.poison)
        end
    end
    Tracker.carriers = carriers
    Tracker.carrierCounts = carrierCounts

    -- Only redraw when something actually changed.
    table.insert(signature, tostring(Tracker.atHuntingGround))
    table.insert(signature, Tracker.creature or unknownKey(Tracker.hunt))
    local joined = table.concat(signature, ",")
    if joined ~= Tracker.scanSignature then
        Tracker.scanSignature = joined
        notify()
    end
end

--- Makes a creature the current target, switching to its kind of hunt.
function Tracker.SetCreature(text)
    if not text or text == "" then return end
    -- Use the game's own spelling, so e.g. "Arcane Apoterrasaur" on the boss bar and
    -- "Arcane apoterrasaur" on the NPC share the same learned damage.
    local name, hunt = Data.FindCreature(text)
    name = name or text
    hunt = hunt or Tracker.hunt
    if name == Tracker.creature then return end
    -- Damage learned before any creature was seen belongs to the first one we see.
    local unassigned = Tracker.damageByCreature[unknownKey(hunt)]
    if unassigned and next(unassigned) and not Tracker.damageByCreature[name] then
        Tracker.damageByCreature[name] = unassigned
        Tracker.damageByCreature[unknownKey(hunt)] = nil
    end
    Tracker.creature = name
    Tracker.hunt = hunt
end

--- Looks for one of the current hunt's poisons and a damage tier in one game message.
--- Returns poisonIndex, damage when both are present, otherwise nil.
local function parseDamageMessage(text)
    local poisonIndex
    for index, poison in ipairs(Tracker.hunt.poisons) do
        for _, keyword in ipairs(poison.keywords) do
            if text:find(keyword, 1, true) then
                -- More than one poison in a single message is ambiguous; ignore it.
                if poisonIndex and poisonIndex ~= index then return nil end
                poisonIndex = index
            end
        end
    end
    if not poisonIndex then return nil end

    for digits in text:gmatch("%d[%d,]*") do
        local value = tonumber((digits:gsub(",", "")))
        if Data.IS_DAMAGE_TIER[value] then return poisonIndex, value end
    end
    return nil
end

--- Handles Event.ChatMessage. Only receives messages if the player allowed chatAccess.
function Tracker.HandleChat(event)
    -- Only game messages: skip anything a player said, and messages about other players.
    if event.senderNameUnfiltered ~= "" or IGNORED_CHAT_TYPES[event.chatType] then return end

    -- Strip formatting tags such as <col=ff0000> before reading the text.
    local text = event.chatMessage:gsub("<[^>]*>", ""):lower()

    local poisonIndex, damage = parseDamageMessage(text)
    if not poisonIndex then return end

    -- A hit that disagrees with what we knew means the poisons were reassigned
    -- since, so everything else we knew is stale too.
    local expected = Tracker.GetDamage(poisonIndex)
    if expected and expected ~= damage then
        Tracker.damageByCreature[Tracker.creature or unknownKey(Tracker.hunt)] = {}
    end
    Tracker.SetDamage(poisonIndex, damage)
end

return Tracker
