-- Follows each hunt using what the game shows on screen:
--   * a hunt starts when the boss health bar appears showing a dinosaur's name. The bar is
--     hidden during cutscenes (e.g. when the scorpions fire) and returns if the dinosaur survives,
--     so a hunt only ends once the bar has stayed away for a while.
--   * each dinosaur carcass with a "Skin" option that appears during a hunt is a kill. Double and
--     triple encounters leave one carcass per dinosaur.
--   * a herd has gone into hiding when a species' "in hiding" debuff appears on the debuff bar
--     with a fresh timer, or the game says so in the chat box. This only happens right after the
--     herd's final hunt. Older debuffs (from earlier herds, or reappearing after a cutscene hid
--     the bar) have less time left, so they're ignored.

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
    -- The dinosaur from the current or most recent hunt.
    target = nil,
    -- The target's remaining HP, as last shown on the boss health bar.
    hp = nil,
    -- Carcasses already counted (or already lying around when the hunt started), by identity.
    seenCarcasses = {},
    -- Kills this session, by dinosaur name. Reset when that herd hides.
    kills = {},
    -- Icons (one per species) of fresh "in hiding" debuffs already acted on, by sprite ID.
    handledHiding = {},
    -- False until the debuff bar has first been read. Debuffs already fresh at that point
    -- (e.g. when the plugin is reloaded) are noted without being acted on.
    debuffBarSeen = false,
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

--- Registers a callback that runs whenever a hunt starts or ends, a kill happens, or a herd hides.
function Encounter.OnChange(callback)
    table.insert(Encounter.listeners, callback)
end

--- Returns the dinosaur named on the boss health bar, or nil if no such bar is showing.
local function bossBarDinosaur()
    for _, componentID in ipairs(Data.BOSS_BAR_NAME_COMPONENTS) do
        local component = ui.Interfaces:GetComponent(componentID)
        if component and component.visibleGlobal then
            local text = UiRead.PlainText(component)
            local name = text and Data.FindDinosaurName(text)
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

--- Reads a debuff timer such as "59m" or "1h 2m" as minutes, or nil if it isn't one.
local function timerMinutes(text)
    local hours, minutes = text:match("(%d+)%s*h"), text:match("(%d+)%s*m")
    if not hours and not minutes then return nil end
    return (tonumber(hours) or 0) * 60 + (tonumber(minutes) or 0)
end

--- Returns the "in hiding" debuffs on the debuff bar as { [spriteID] = minutes left }, or nil
--- if the debuff bar isn't on screen (e.g. during a cutscene). Minutes are nil if unreadable.
local function hidingDebuffs()
    local debuffs, barVisible = {}, false
    for slot = 1, Data.DEBUFF_SLOT_COUNT do
        local component = ui.Interfaces:GetComponent(id.Component["DEBUFF_BAR__BUFF_" .. slot])
        -- Only slots on screen count, and all slots exist even when empty, so skip ones with
        -- nothing in them. Inside a slot the player can see, the debuff icon's parts report
        -- as hidden even though they're drawn, so hidden children are read (never unhidden).
        if component and component.visibleGlobal then
            barVisible = true
            if UiRead.ChildCount(component) > 0 then
                -- A debuff is an icon plus its timer text, e.g. "59m".
                local hidingSprite, minutes
                UiRead.Walk(component, function(child)
                    local spriteID = UiRead.Get(child, "spriteID")
                    if Data.IS_HIDING_SPRITE[spriteID] then hidingSprite = spriteID end
                    local text = UiRead.PlainText(child)
                    if text and not minutes then minutes = timerMinutes(text) end
                end, true)
                if hidingSprite then debuffs[hidingSprite] = minutes end
            end
        end
    end
    if not barVisible then return nil end
    return debuffs
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

--- Returns an identity for each carcass of the named dinosaur near the player. A carcass may
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

local function startHunt(dinosaur)
    Encounter.inHunt = true
    Encounter.target = dinosaur
    Encounter.hp = nil
    Tracker.SetDinosaur(dinosaur)
    Tracker.dinosaurLocked = true
    -- Carcasses from an earlier hunt that haven't been skinned yet aren't new kills.
    Encounter.seenCarcasses = {}
    for _, carcass in ipairs(nearbyCarcasses(dinosaur)) do Encounter.seenCarcasses[carcass] = true end
end

--- The hunt is over. The target stays locked (see Tracker.dinosaurLocked) so the damage
--- learned on it stays on screen between hunts, until a hunt on another dinosaur starts.
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
    if Encounter.inHunt then
        countNewKills()
        finishHunt()
    end
    Tracker.ForgetDinosaur(Encounter.target)
    Encounter.kills[Encounter.target] = nil
end

--- Checks the boss bar, nearby carcasses and the debuff bar. Called a couple of times a second.
function Encounter.Update()
    local changed = false

    local dinosaur = bossBarDinosaur()
    if dinosaur then
        if not Encounter.barVisible then
            -- Either a new hunt, or the bar is back after a cutscene.
            Encounter.barVisible = true
            Encounter.barGoneTick = nil
            if not Encounter.inHunt then startHunt(dinosaur) end
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

    if Encounter.inHunt then
        if countNewKills() then changed = true end
        if not Encounter.barVisible and Tracker.logicTick - Encounter.barGoneTick >= HUNT_END_GRACE_TICKS then
            finishHunt()
            changed = true
        end
    end

    -- Act once on each fresh hiding debuff. While the bar is hidden nothing changes.
    local debuffs = hidingDebuffs()
    if debuffs then
        for spriteID, minutes in pairs(debuffs) do
            local fresh = minutes ~= nil and minutes >= FRESH_HIDING_MINUTES
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
    end

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
    end
end

--- Number of kills of a dinosaur this session.
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
    Tracker.dinosaurLocked = false
    notify()
end

return Encounter
