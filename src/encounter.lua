-- Follows each hunt using what the game shows on screen:
--   * a hunt starts when the boss health bar appears showing a big game creature's name. The
--     bar is hidden during cutscenes (e.g. when the scorpions fire) and returns if the creature
--     survives, so a hunt only ends once the bar has stayed away for a while.
--   * each carcass of the creature with a "Skin" option that appears during a hunt is a kill.
--     Double and triple dinosaur encounters leave one carcass per dinosaur. A Havenhythe
--     encounter is a single creature, so its hunt ends as soon as the kill is counted.
--   * a dinosaur herd has gone into hiding when a species' "in hiding" debuff appears on the
--     debuff bar with a fresh timer, or the game says so in the chat box. This only happens
--     right after the herd's final hunt. Older debuffs (from earlier herds, or reappearing after
--     a cutscene hid the bar) have less time left, so they're ignored.
--   * Havenhythe poisons change at the next encounter after the "Strongest poison" buff's timer
--     runs out (the buff stays, without a timer, and the game says so in the chat box). They
--     also don't survive hunting another Havenhythe creature in between, so damage is only
--     kept for the Havenhythe creature hunted last.

local Data = require("src/data")
local Tracker = require("src/tracker")
local UiRead = require("src/ui_read")

local Encounter = {
    -- True from when the boss bar first appears until the hunt is over.
    inHunt = false,
    -- True only while the boss bar is actually on screen (it's hidden during cutscenes).
    barVisible = false,
    -- Logic tick when the boss bar last disappeared, while waiting to see if it comes back.
    barGoneTick = nil,
    -- The creature from the current or most recent hunt.
    target = nil,
    -- The target's remaining HP, as last shown on the boss health bar.
    hp = nil,
    -- Carcasses already counted (or already lying around when the hunt started), by identity.
    seenCarcasses = {},
    -- Kills this session, by creature name. Reset when that herd hides.
    kills = {},
    -- Icons (one per species) of fresh "in hiding" debuffs already acted on, by sprite ID.
    handledHiding = {},
    -- False until the debuff bar has first been read. Debuffs already fresh at that point
    -- (e.g. when the plugin is reloaded) are noted without being acted on.
    debuffBarSeen = false,
    -- The poisoned item shown on the "Strongest poison" buff, and whether it last had a timer.
    strongestPoison = nil,
    strongestTimed = false,
    -- Creatures whose poisons change at their next encounter, by name.
    poisonsChangeNext = {},
    -- The Havenhythe creature hunted most recently.
    lastHavenhytheTarget = nil,
    listeners = {},
}

-- How long the boss bar must stay gone before the hunt is over. The scorpion cutscene runs
-- about 20 seconds, after which the bar returns if a dinosaur survived.
local HUNT_END_GRACE_TICKS = 45 * 50 -- 45 seconds at 50 logic ticks per second

-- A herd hides for an hour, so a hiding debuff with at least this many minutes left has only
-- just appeared.
local FRESH_HIDING_MINUTES = 55

-- How far from the player, in tiles, to look for carcasses. Carcasses fall at the trap the
-- player just set, so they're close by and on screen. Only used to count kills; carcass
-- positions are never shown.
local CARCASS_SEARCH_RANGE = 15

local function notify()
    for _, callback in ipairs(Encounter.listeners) do callback() end
end

--- Registers a callback that runs whenever a hunt starts or ends, a kill happens, or poisons change.
function Encounter.OnChange(callback)
    table.insert(Encounter.listeners, callback)
end

--- Returns the creature named on the boss health bar, or nil if no such bar is showing.
local function bossBarCreature()
    for _, componentID in ipairs(Data.BOSS_BAR_NAME_COMPONENTS) do
        local component = ui.Interfaces:GetComponent(componentID)
        if component and component.visibleGlobal then
            local text = UiRead.PlainText(component)
            local name = text and Data.FindCreature(text)
            if name then return name end
        end
    end
    return nil
end

--- Returns the HP shown on the boss health bar, or nil if it can't be read.
local function bossBarHP()
    local component = ui.Interfaces:GetComponent(Data.BOSS_BAR_HP_COMPONENT)
    local text = component and UiRead.PlainText(component)
    if not text then return nil end
    return tonumber((text:gsub("[^%d]", "")))
end

--- Reads a buff timer such as "59m" or "1h 2m" as minutes, or nil if it isn't one.
local function timerMinutes(text)
    local hours, minutes = text:match("(%d+)%s*h"), text:match("(%d+)%s*m")
    if not hours and not minutes then return nil end
    return (tonumber(hours) or 0) * 60 + (tonumber(minutes) or 0)
end

--- Reads a buff or debuff bar. Each slot showing an icon that identify() recognises adds
--- { [key] = minutes left } to the result, where identify(spriteID, objID) returns a key or
--- nil. Returns nil if the bar isn't on screen (e.g. during a cutscene). Minutes are false if
--- there's no timer, or it's unreadable.
local function readBar(slotPrefix, identify)
    local found, barVisible = {}, false
    for slot = 1, Data.BAR_SLOT_COUNT do
        local component = ui.Interfaces:GetComponent(id.Component[slotPrefix .. slot])
        -- Only slots on screen count, and all slots exist even when empty, so skip ones with
        -- nothing in them. Inside a slot the player can see, the icon's parts report as
        -- hidden even though they're drawn, so hidden children are read (never unhidden).
        if component and component.visibleGlobal then
            barVisible = true
            if UiRead.ChildCount(component) > 0 then
                -- A buff is an icon plus its timer text, e.g. "59m".
                local key, minutes
                UiRead.Walk(component, function(child)
                    key = key or identify(UiRead.Get(child, "spriteID"), UiRead.Get(child, "associatedObjectID"))
                    local text = UiRead.PlainText(child)
                    if text and not minutes then minutes = timerMinutes(text) end
                end, true)
                if key then found[key] = minutes or false end
            end
        end
    end
    if not barVisible then return nil end
    return found
end

--- True if an entity config has a "Skin" option (shown in-game as e.g. "Skin Bagrada rex").
local function hasSkinOption(entityConfig)
    local opNames = entityConfig and UiRead.Get(entityConfig, "opNames")
    if type(opNames) ~= "table" then return false end
    for _, opName in pairs(opNames) do
        if type(opName) == "string" and opName:lower():find("skin", 1, true) then return true end
    end
    return false
end

--- Returns an identity for each carcass of the named creature near the player. A carcass may
--- be an NPC (identified by its uid) or an object (identified by its tile).
local function nearbyCarcasses(name)
    local carcasses = {}
    local player = Player.GetEntity()
    local coordGrid = player and player.coordGrid
    if not coordGrid then return carcasses end

    local lowerName = name:lower()
    local function isCarcass(entity)
        return entity.isValid and entity.displayName:lower():find(lowerName, 1, true) ~= nil
            and hasSkinOption(entity.config)
    end
    for _, npc in ipairs(NPCList.ByDistance(coordGrid, CARCASS_SEARCH_RANGE) or {}) do
        if isCarcass(npc) then table.insert(carcasses, "npc:" .. npc.uid) end
    end
    for _, loc in ipairs(LocList.ByDistance(coordGrid, CARCASS_SEARCH_RANGE, true) or {}) do
        if isCarcass(loc) then table.insert(carcasses, "loc:" .. loc.coordGrid:ToPacked()) end
    end
    return carcasses
end

local function startHunt(creature)
    if Encounter.poisonsChangeNext[creature] then
        Encounter.poisonsChangeNext[creature] = nil
        Tracker.ForgetCreature(creature)
    end
    local _, hunt = Data.FindCreature(creature)
    if hunt and hunt.strongestPoisonBuff then
        -- Seen in-game: after a kebbit hunt, a chinchompa's earlier damage no longer applied.
        if Encounter.lastHavenhytheTarget and Encounter.lastHavenhytheTarget ~= creature then
            Tracker.ForgetCreature(creature)
        end
        Encounter.lastHavenhytheTarget = creature
    end
    Encounter.inHunt = true
    Encounter.target = creature
    Encounter.hp = nil
    Tracker.SetCreature(creature)
    Tracker.creatureLocked = true
    -- Carcasses from an earlier hunt that haven't been skinned yet aren't new kills.
    Encounter.seenCarcasses = {}
    for _, carcass in ipairs(nearbyCarcasses(creature)) do Encounter.seenCarcasses[carcass] = true end
end

--- The hunt is over. The target stays locked (see Tracker.creatureLocked) so the damage
--- learned on it stays on screen between hunts, until a hunt on another creature starts.
local function finishHunt()
    Encounter.inHunt = false
    Encounter.barGoneTick = nil
    Encounter.hp = nil
end

--- Counts carcasses that appeared since the hunt started. Returns true if any were new.
local function countNewKills()
    local found = false
    for _, carcass in ipairs(nearbyCarcasses(Encounter.target)) do
        if not Encounter.seenCarcasses[carcass] then
            Encounter.seenCarcasses[carcass] = true
            Encounter.kills[Encounter.target] = (Encounter.kills[Encounter.target] or 0) + 1
            found = true
        end
    end
    return found
end

--- The most recently hunted herd went into hiding: its poisons will be reassigned before it
--- can be hunted again, so forget what we learned about it.
local function herdWentIntoHiding()
    if not Encounter.target then return end
    -- Only dinosaur herds go into hiding.
    local _, hunt = Data.FindCreature(Encounter.target)
    if not hunt or not hunt.hidingSprites then return end
    if Encounter.inHunt then
        countNewKills()
        finishHunt()
    end
    Tracker.ForgetCreature(Encounter.target)
    Encounter.kills[Encounter.target] = nil
end

--- Acts once on each fresh dinosaur "in hiding" debuff. Returns true if anything changed.
local function checkHidingDebuffs()
    local debuffs = readBar("DEBUFF_BAR__BUFF_", function(spriteID)
        return Data.DINOSAURS.hidingSprites[spriteID] and spriteID or nil
    end)
    -- While the bar is hidden nothing changes.
    if not debuffs then return false end

    local changed = false
    for spriteID, minutes in pairs(debuffs) do
        local fresh = minutes and minutes >= FRESH_HIDING_MINUTES
        if not fresh then
            Encounter.handledHiding[spriteID] = nil
        elseif not Encounter.handledHiding[spriteID] then
            Encounter.handledHiding[spriteID] = true
            if Encounter.debuffBarSeen then
                herdWentIntoHiding()
                changed = true
            end
        end
    end
    for spriteID in pairs(Encounter.handledHiding) do
        if not debuffs[spriteID] then Encounter.handledHiding[spriteID] = nil end
    end
    Encounter.debuffBarSeen = true
    return changed
end

--- The poisons of the most recent creature change at its next encounter. buffHunt, if given,
--- is the hunt the "Strongest poison" buff belongs to; another hunt's creature isn't marked.
local function poisonsChangeNextEncounter(buffHunt)
    local creature = Encounter.target or Tracker.creature
    local _, hunt = Data.FindCreature(creature or "")
    if not hunt or not hunt.strongestPoisonBuff or (buffHunt and buffHunt ~= hunt) then return end
    Encounter.poisonsChangeNext[creature] = true
end

--- Watches the Havenhythe "Strongest poison" buff. It appears with a timer once the strongest
--- poison has been found, replacing any earlier one. When its timer runs out the buff stays,
--- without a timer, and the poisons change at the next encounter.
local function checkStrongestPoison()
    local buffs = readBar("BUFF_BAR__BUFF_", function(_, objID)
        if objID ~= nil and Data.STRONGEST_POISON_ICONS[objID] then return objID end
        return nil
    end)
    local shown, minutes = next(buffs or {})
    if not shown then return end
    -- readBar gives false for a buff without a timer.
    local timed = minutes ~= false
    local wasTimed = shown == Encounter.strongestPoison and Encounter.strongestTimed
    Encounter.strongestPoison, Encounter.strongestTimed = shown, timed
    -- Only the moment its timer runs out counts; the buff then stays like this for a while.
    if wasTimed and not timed then poisonsChangeNextEncounter(Data.STRONGEST_POISON_ICONS[shown]) end
end

--- Checks the boss bar, nearby carcasses and the buff and debuff bars. Called a couple of
--- times a second.
function Encounter.Update()
    local changed = false

    local creature = bossBarCreature()
    if creature then
        -- The bar names another creature, e.g. after going straight on to another hunt before
        -- the last one's bar had been gone long enough to end it.
        local otherCreature = Encounter.inHunt and creature ~= Encounter.target
        if otherCreature then finishHunt() end
        if not Encounter.barVisible or otherCreature then
            -- Either a new hunt, or the bar is back after a cutscene.
            Encounter.barVisible = true
            Encounter.barGoneTick = nil
            if not Encounter.inHunt then startHunt(creature) end
            changed = true
        end
        local hp = bossBarHP()
        if hp and hp ~= Encounter.hp then
            Encounter.hp = hp
            changed = true
        end
    elseif Encounter.barVisible then
        -- The bar just went away. Wait to see if it returns after a cutscene.
        Encounter.barVisible = false
        Encounter.barGoneTick = Tracker.logicTick
        changed = true
    end

    if Encounter.inHunt and countNewKills() then
        changed = true
        -- A one-creature encounter is over once its kill is counted, so if the same creature is
        -- hunted again before the grace period would have ended, that's still a new hunt.
        local _, hunt = Data.FindCreature(Encounter.target)
        if hunt and hunt.oneCreaturePerEncounter then finishHunt() end
    end
    if Encounter.inHunt then
        if not Encounter.barVisible and Tracker.logicTick - Encounter.barGoneTick >= HUNT_END_GRACE_TICKS then
            finishHunt()
            changed = true
        end
    end

    if checkHidingDebuffs() then changed = true end
    checkStrongestPoison()

    if changed then notify() end
end

--- Handles Event.ChatMessage. Only receives messages if the player allowed chatAccess.
function Encounter.HandleChat(event)
    if event.senderNameUnfiltered ~= "" or event.chatType == ChatType.PLUGIN then return end
    -- "It appears they have now gone into hiding. Come back later." follows the herd's last hunt.
    local text = event.chatMessage:gsub("<[^>]*>", ""):lower()
    if text:find("gone into hiding", 1, true) then
        herdWentIntoHiding()
        notify()
    -- "The strength of each poison will change in the next encounter with this creature."
    elseif text:find("poison will change in the next encounter", 1, true) then
        poisonsChangeNextEncounter()
    end
end

function Encounter.KillCount(name)
    return Encounter.kills[name] or 0
end

--- Forgets session state, e.g. after logging out.
function Encounter.Reset()
    Encounter.inHunt = false
    Encounter.barVisible = false
    Encounter.barGoneTick = nil
    Encounter.target = nil
    Encounter.hp = nil
    Encounter.seenCarcasses = {}
    Encounter.kills = {}
    Encounter.handledHiding = {}
    Encounter.debuffBarSeen = false
    Encounter.strongestPoison = nil
    Encounter.strongestTimed = false
    Encounter.poisonsChangeNext = {}
    Encounter.lastHavenhytheTarget = nil
    Tracker.creatureLocked = false
    notify()
end

return Encounter
