-- Tracks everything the overlay shows. All of it is information already visible to the player:
--   * backpack contents (logs, vines, spears, poisoned spears)
--   * poison frogs and dinosaurs around the player, while in an instance (the hunting grounds)
--   * poison damage, read from game messages in the chat box or entered by hand

local Data = require("src/data")

local Tracker = {
    counts = { logs = 0, vines = 0, spears = 0 },
    poisonedSpears = { 0, 0, 0 },
    -- Poison frogs nearby, keyed by NPC uid: { npc = NPCEntity, poison = index }.
    frogs = {},
    frogCounts = { 0, 0, 0 },
    -- The most recently seen dinosaur's name.
    dinosaur = nil,
    -- True from when a dinosaur is first seen in an instance until the player leaves it.
    atHuntingGround = false,
    -- Set once a hunt's boss health bar has named the target, so that other dinosaurs
    -- wandering into view don't change it. Only a new hunt changes the target after that.
    dinosaurLocked = false,
    -- Learned damage per dinosaur name: damageByDinosaur[name][poisonIndex] = damage.
    -- Poisons are reassigned when a species goes into hiding, so this is never saved to disk.
    damageByDinosaur = {},
    logicTick = 0,
    listeners = {},
    scanSignature = "",
}

local UNKNOWN_DINOSAUR = "?"

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

--- Registers a callback that runs whenever tracked data changes.
function Tracker.OnChange(callback)
    table.insert(Tracker.listeners, callback)
end

local function currentDamageTable()
    local key = Tracker.dinosaur or UNKNOWN_DINOSAUR
    local damage = Tracker.damageByDinosaur[key]
    if not damage then
        damage = {}
        Tracker.damageByDinosaur[key] = damage
    end
    return damage
end

--- Returns the damage the player has seen a poison deal to the current dinosaur, or nil if
--- they haven't seen it yet. Only damage actually seen (or entered by hand) is ever shown.
function Tracker.GetDamage(poisonIndex)
    return currentDamageTable()[poisonIndex]
end

--- Records a poison's damage against the current dinosaur. Pass nil to forget it.
function Tracker.SetDamage(poisonIndex, damage)
    local known = currentDamageTable()
    if damage then
        -- A damage tier can only belong to one colour, so drop any older, conflicting entry.
        for index, value in pairs(known) do
            if value == damage and index ~= poisonIndex then known[index] = nil end
        end
    end
    known[poisonIndex] = damage
    notify()
end

--- Forgets everything learned about the current dinosaur.
function Tracker.ResetCurrent()
    Tracker.damageByDinosaur[Tracker.dinosaur or UNKNOWN_DINOSAUR] = {}
    notify()
end

--- Forgets everything learned about one dinosaur, e.g. when its herd goes into hiding.
function Tracker.ForgetDinosaur(name)
    Tracker.damageByDinosaur[name] = nil
    notify()
end

--- Forgets all learned damage, e.g. after logging out (which ends the hunting session).
function Tracker.ClearAll()
    Tracker.damageByDinosaur = {}
    Tracker.atHuntingGround = false
    notify()
end

--- Re-counts hunting supplies in the backpack.
function Tracker.RefreshInventory()
    -- The docs say Find returns a single Inv with an isValid field (the stubs differ).
    local backpack = Inventory.Find(id.Inv.INV) --[[@as Inv?]]
    ---@diagnostic disable-next-line: undefined-field
    if not backpack or backpack.isValid == false then return end

    Tracker.counts.logs = backpack:GetTotal(Data.LOGS)
    Tracker.counts.vines = backpack:GetTotal(Data.VINES)
    Tracker.counts.spears = backpack:GetTotal(Data.SPEAR)
    for index, poison in ipairs(Data.POISONS) do
        Tracker.poisonedSpears[index] = backpack:GetTotal(poison.spear)
    end
    notify()
end

--- Finds the poison frogs and dinosaurs currently loaded around the player.
function Tracker.ScanNPCs(logicTick)
    Tracker.logicTick = logicTick
    if not Player.IsAvailable() or not World.IsAvailable() then return end

    local frogs, frogCounts = {}, { 0, 0, 0 }
    local signature = {}
    -- Hunting happens in the player's own instance, so frogs and dinosaurs are only looked
    -- for there. Every NPC loaded in an instance belongs to the player's own hunt.
    local inInstance = World.IsRegion()
    if not inInstance then Tracker.atHuntingGround = false end
    for _, npc in ipairs(inInstance and NPCList.All() or {}) do
        local poisonIndex = Data.POISON_BY_FROG_ID[npc.configID]
        if poisonIndex then
            frogs[npc.uid] = { npc = npc, poison = poisonIndex }
            frogCounts[poisonIndex] = frogCounts[poisonIndex] + 1
            table.insert(signature, npc.uid .. ":" .. poisonIndex)
        elseif Data.IS_DINOSAUR_ID[npc.configID] or Data.IS_DINOSAUR_ID[npc.parentConfigID] then
            Tracker.atHuntingGround = true
            local name = Data.FindDinosaurName(npc.displayName) or npc.displayName
            if not Tracker.dinosaurLocked then Tracker.SetDinosaur(name) end
        end
    end

    Tracker.frogs = frogs
    Tracker.frogCounts = frogCounts

    -- Only redraw when something actually changed.
    table.insert(signature, tostring(Tracker.atHuntingGround))
    table.insert(signature, Tracker.dinosaur or UNKNOWN_DINOSAUR)
    local joined = table.concat(signature, ",")
    if joined ~= Tracker.scanSignature then
        Tracker.scanSignature = joined
        notify()
    end
end

function Tracker.SetDinosaur(name)
    if not name or name == "" then return end
    -- Use the game's own spelling, so e.g. "Arcane Apoterrasaur" on the boss bar and
    -- "Arcane apoterrasaur" on the NPC share the same learned damage.
    name = Data.FindDinosaurName(name) or name
    if name == Tracker.dinosaur then return end
    -- Damage learned before any dinosaur was seen belongs to the first one we see.
    local unassigned = Tracker.damageByDinosaur[UNKNOWN_DINOSAUR]
    if unassigned and next(unassigned) and not Tracker.damageByDinosaur[name] then
        Tracker.damageByDinosaur[name] = unassigned
        Tracker.damageByDinosaur[UNKNOWN_DINOSAUR] = nil
    end
    Tracker.dinosaur = name
end

--- Looks for a poison colour and a damage tier in one game message.
--- Returns poisonIndex, damage when both are present, otherwise nil.
local function parseDamageMessage(text)
    local poisonIndex
    for index, poison in ipairs(Data.POISONS) do
        if text:find(poison.keyword, 1, true) then
            -- More than one colour in a single message is ambiguous; ignore it.
            if poisonIndex then return nil end
            poisonIndex = index
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
    -- (the herd went into hiding since), so everything else we knew is stale too.
    local expected = Tracker.GetDamage(poisonIndex)
    if expected and expected ~= damage then
        Tracker.damageByDinosaur[Tracker.dinosaur or UNKNOWN_DINOSAUR] = {}
    end
    Tracker.SetDamage(poisonIndex, damage)
end

return Tracker
