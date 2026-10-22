-- Big Game Helper
-- A helper overlay for Big Game Hunter (currently the Anachronia dinosaurs). Everything it
-- shows is information the player can already see: their backpack, NPCs on screen, and game
-- messages in the chat box.

local Settings = require("src/settings")
local Tracker = require("src/tracker")
local Encounter = require("src/encounter")
local Overlay = require("src/overlay")
local FrogLabels = require("src/frog_labels")

-- The client runs 50 logic ticks per second, so this checks for frogs, dinosaurs, the boss
-- health bar and debuffs twice a second.
local SCAN_INTERVAL_TICKS = 25

local function refreshViews()
    Overlay.Render()
    FrogLabels.Render()
end

Settings.Load()
Settings.showOverlay = Overlay.Show
Tracker.OnChange(refreshViews)
Encounter.OnChange(refreshViews)
Settings.OnChange(refreshViews)
Tracker.RefreshInventory()
refreshViews()

local function onInventoryChanged(event)
    if event.inv.id == id.Inv.INV then Tracker.RefreshInventory() end
end

Event.InventoryAdded.Subscribe("bgh_inventory_added", onInventoryChanged)
Event.InventoryUpdated.Subscribe("bgh_inventory_updated", onInventoryChanged)

Event.Logic.Subscribe("bgh_scan", function(event)
    if event.logicTick % SCAN_INTERVAL_TICKS == 0 then
        Tracker.ScanNPCs(event.logicTick)
        Encounter.Update()
    end
end)

-- Only delivered if the player has allowed the optional chatAccess permission.
Event.ChatMessage.Subscribe("bgh_chat", function(event)
    Tracker.HandleChat(event)
    Encounter.HandleChat(event)
end)

Event.OptionalPermissionChanged.Subscribe("bgh_permission", refreshViews)

Event.GameStateChanged.Subscribe("bgh_game_state", function(event)
    -- Logging out ends the hunting session, so poison assignments no longer apply.
    if event.newState == GameState.LOGINSCREEN or event.newState == GameState.LOBBY then
        Tracker.ClearAll()
        Encounter.Reset()
    end
end)

Event.SettingsLayerReady.Subscribe("bgh_settings", Settings.BuildView)

-- Clicking the plugin's ribbon icon (in the Plugins window) reopens the overlay, and shows
-- the same settings page in the Plugins window.
Event.ContentLayerReady.Subscribe("bgh_content", function(event)
    Overlay.Show()
    Settings.BuildView(event)
end)

function PluginShutdown()
    Event.InventoryAdded.Unsubscribe("bgh_inventory_added")
    Event.InventoryUpdated.Unsubscribe("bgh_inventory_updated")
    Event.Logic.Unsubscribe("bgh_scan")
    Event.ChatMessage.Unsubscribe("bgh_chat")
    Event.OptionalPermissionChanged.Unsubscribe("bgh_permission")
    Event.GameStateChanged.Unsubscribe("bgh_game_state")
    Event.SettingsLayerReady.Unsubscribe("bgh_settings")
    Event.ContentLayerReady.Unsubscribe("bgh_content")

    Overlay.Destroy()
    FrogLabels.Destroy()
    Settings.DestroyView()
end
