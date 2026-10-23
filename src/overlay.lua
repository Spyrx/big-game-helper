-- The on-screen overlay: a PrettyUI window over the game area.
-- Drag its title bar to move it and its edges to resize it; position and size are remembered.
-- Closing it hides it until the next hunt starts or the player next arrives at the hunting
-- grounds, or until the player asks for it again (the plugin's ribbon icon, or "Show overlay"
-- in its settings).

local Data = require("src/data")
local Encounter = require("src/encounter")
local Settings = require("src/settings")
local Tracker = require("src/tracker")

-- Default and minimum width. The window's inner width is width - 16 border - 28 padding
-- (316 at 360). The poison rows need that much for a two-digit "spears, frogs" (or
-- "moths, nearby") count to clear the damage column, and the "Set damage by hand" rows fill it.
local MIN_WIDTH = 360
local MAX_WIDTH = 520
local DEFAULT_HEIGHT = 380
local MIN_HEIGHT = 160

local Overlay = {
    ---@type table? The PrettyUI window, while shown.
    window = nil,
    ---@type table? Components inside the window that get updated, while shown.
    widgets = nil,
    -- The hunt the window was built for. It's rebuilt when the player switches hunts.
    builtFor = nil,
    -- Set when the player closes the window; cleared when the next hunt starts.
    dismissed = false,
    -- Set when the player asks to see the window; it then stays open until closed.
    forced = false,
    wasInHunt = false,
    wasAtHuntingGround = false,
    x = PersistentDB:GetInt("overlayX") or 16,
    y = PersistentDB:GetInt("overlayY") or 160,
    width = PersistentDB:GetInt("overlayWidth") or MIN_WIDTH,
    height = PersistentDB:GetInt("overlayHeight") or DEFAULT_HEIGHT,
}

-- Opacity of the window's background, so the game shows through.
local BACKGROUND_ALPHA = 0.7

local TEXT_RGBA = 0xE7D7B0FF
local MUTED_RGBA = 0xA89A80FF
local GOOD_RGBA = 0x6FD36FFF
local WARN_RGBA = 0xFFA040FF

-- Text next to a 40px item slot is nudged down to sit on its centre line.
local SLOT_TEXT_OFFSET = 8

-- Poison rows: the poison name column is as wide as the longest name, then the damage, then
-- the carried and nearby counts right-aligned to the edge of the content.
local POISON_DAMAGE_WIDTH = 40
local POISON_DETAIL_WIDTH = 150
-- PrettyUI's default content padding, so right-aligned text ends where full-width rows
-- (like the "Set damage by hand" header) do.
local CONTENT_PADDING = 14

-- Layout of the "Set damage by hand" rows (label + 4 buttons = 314 wide).
-- The label column fits "Blue-deathcap", and the section's content isn't indented so the row fits.
local MANUAL_ROW_HEIGHT = 30
local MANUAL_LABEL_WIDTH = 110
local MANUAL_BUTTON_WIDTH = 48
local MANUAL_BUTTON_GAP = 4

--- Width of the longest poison name in the overlay's font, plus a little room.
local function poisonNameWidth(hunt)
    local widest = 0
    for _, poison in ipairs(hunt.poisons) do
        local succeeded, width = pcall(function()
            return config.Font.MUSEO_SANS_15PT_REGULAR:GetStringWidth(poison.label, false)
        end)
        widest = math.max(widest, succeeded and width or #poison.label * 8)
    end
    return widest + 6
end

--- Adds an item icon followed by a count to the current row.
local function addCountedItem(window, obj, inline)
    window:AddItemSlot(obj, { inline = inline, tooltip = obj.name })
    return window:AddText({ text = "0", inline = true, width = 56, offsetY = SLOT_TEXT_OFFSET })
end

--- Adds the "Set damage by hand" section, for when chat access is off or a message was missed.
local function addManualControls(window, hunt)
    -- The window keeps the size the player chose and scrolls if the section doesn't fit.
    local section = window:AddCollapseButton("Set damage by hand", {
        expanded = false,
        indent = 0,
    })
    for index, poison in ipairs(hunt.poisons) do
        local y = (index - 1) * MANUAL_ROW_HEIGHT
        section:AddText({
            text = poison.label,
            colour = poison.rgba,
            x = 0,
            y = y,
            width = MANUAL_LABEL_WIDTH,
            widthAnchor = 0,
            height = MANUAL_ROW_HEIGHT - MANUAL_BUTTON_GAP,
        })

        -- The section sizes all its text buttons to match the widest, so "Clear" is a short "X"
        -- (with a tooltip) to keep every button narrow enough for the row to fit.
        local buttons = {}
        for _, damage in ipairs(Data.DAMAGE_TIERS) do
            table.insert(buttons, { text = Data.FormatDamage(damage), damage = damage })
        end
        table.insert(buttons, { text = "X", damage = nil, tooltip = "Clear" })

        -- Buttons are anchored to the right edge, lining up with the section's header as the
        -- window is resized.
        for column, button in ipairs(buttons) do
            local fromRight = #buttons - column + 1
            section:AddSimpleButton(button.text, function()
                Tracker.SetDamage(index, button.damage)
            end, {
                x = -fromRight * MANUAL_BUTTON_WIDTH - (fromRight - 1) * MANUAL_BUTTON_GAP,
                xAnchor = 1,
                y = y,
                width = MANUAL_BUTTON_WIDTH,
                tooltip = button.tooltip,
            })
        end
    end
end

local function savePlacement()
    local root = Overlay.window and Overlay.window.root
    if not root then return end
    Overlay.x, Overlay.y = root.x, root.y
    Overlay.width, Overlay.height = root.width, root.height
    PersistentDB:SetInt("overlayX", Overlay.x)
    PersistentDB:SetInt("overlayY", Overlay.y)
    PersistentDB:SetInt("overlayWidth", Overlay.width)
    PersistentDB:SetInt("overlayHeight", Overlay.height)
end

local function build(hunt)
    local gameArea = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__GAME_AREA)
    if not gameArea then return end

    local window = prettyui.Window.new(gameArea, {
        title = "Big Game Hunter",
        x = Overlay.x,
        y = Overlay.y,
        width = math.max(MIN_WIDTH, math.min(MAX_WIDTH, Overlay.width)),
        height = math.max(MIN_HEIGHT, Overlay.height),
        resizable = true,
        minWidth = MIN_WIDTH,
        maxWidth = MAX_WIDTH,
        minHeight = MIN_HEIGHT,
        destroyOnClose = true,
        onClose = function()
            savePlacement()
            Overlay.window = nil
            Overlay.widgets = nil
            Overlay.dismissed = true
            Overlay.forced = false
        end,
    })
    -- Swap the window's opaque background for PrettyUI's translucent HUD panel background.
    window.background.spriteID = prettyui.Sprites.HUD_WINDOW.content
    window.background.alpha = BACKGROUND_ALPHA

    local widgets = {}
    widgets.target = window:AddText({ text = "", colour = MUTED_RGBA })

    -- Supplies in the backpack, in one row.
    widgets.supplies = {}
    for index, obj in ipairs(hunt.supplies) do
        widgets.supplies[index] = addCountedItem(window, obj, index > 1)
    end
    if hunt.TrapSetStatus then widgets.trapSet = window:AddText({ text = "" }) end

    -- One row per poison: the poisoned item's icon, poison name, damage, carried and nearby.
    widgets.poisons = {}
    local nameWidth = poisonNameWidth(hunt)
    for _, poison in ipairs(hunt.poisons) do
        window:AddItemSlot(poison.item, { tooltip = poison.item.name })
        table.insert(widgets.poisons, {
            name = window:AddText({
                text = poison.label,
                colour = poison.rgba,
                inline = true,
                width = nameWidth,
                offsetY = SLOT_TEXT_OFFSET,
            }),
            damage = window:AddText({
                text = "?",
                inline = true,
                width = POISON_DAMAGE_WIDTH,
                offsetY = SLOT_TEXT_OFFSET,
            }),
            detail = window:AddText({
                text = "",
                inline = true,
                x = -(CONTENT_PADDING + POISON_DETAIL_WIDTH),
                xAnchor = 1,
                width = POISON_DETAIL_WIDTH,
                alignHorizontal = ui.AlignMode.BOTTOMRIGHT,
                maxLines = 1,
                offsetY = SLOT_TEXT_OFFSET,
            }),
        })
    end
    widgets.hint = window:AddText({ text = "", colour = MUTED_RGBA, height = 44 })

    addManualControls(window, hunt)

    Overlay.window = window
    Overlay.widgets = widgets
    Overlay.builtFor = hunt
end

local function shouldShow()
    -- A closed window stays closed until the next hunt starts, or the player next arrives at
    -- the hunting grounds.
    if Encounter.inHunt and not Overlay.wasInHunt then Overlay.dismissed = false end
    if Tracker.atHuntingGround and not Overlay.wasAtHuntingGround then Overlay.dismissed = false end
    Overlay.wasInHunt = Encounter.inHunt
    Overlay.wasAtHuntingGround = Tracker.atHuntingGround
    if Overlay.forced then return true end
    if Overlay.dismissed then return false end

    local mode = Settings.values.overlayMode
    if mode == "never" then return false end
    if mode == "always" then return true end
    -- "Only while hunting": from the first creature seen in the hunting instance until leaving it.
    return Encounter.inHunt or Tracker.atHuntingGround
end

--- Describes the current target, e.g. "Scimitops: 45,000 HP" or "Scimitops: 2 kills this session".
local function targetLabel()
    local creature = Tracker.creature
    if not creature then return "Target: no " .. Tracker.hunt.creatureWord .. " seen yet" end
    if Encounter.barVisible and Encounter.hp then
        return creature .. ": " .. Data.FormatNumber(Encounter.hp) .. " HP"
    end
    local kills = Encounter.KillCount(creature)
    if kills == 0 then return "Target: " .. creature end
    return creature .. ": " .. Data.Plural(kills, "kill") .. " this session"
end

--- Returns the damage label and its colour for one poison against the current creature.
--- Every seen value is shown the same way; the overlay records damage, it doesn't recommend.
local function damageLabel(poisonIndex)
    local damage = Tracker.GetDamage(poisonIndex)
    if not damage then return "?", MUTED_RGBA end
    return Data.FormatDamage(damage), TEXT_RGBA
end

local function hintLabel(hunt)
    if not Settings.HasChatAccess() then
        return "Chat access is off, so set damage by hand below."
    end
    for index = 1, #hunt.poisons do
        if Tracker.GetDamage(index) then return "" end
    end
    return "Damage fills in from your game messages as " .. hunt.hitDescription .. "."
end

function Overlay.Render()
    local hunt = Tracker.hunt
    local show = shouldShow()
    if Overlay.window and (not show or Overlay.builtFor ~= hunt) then Overlay.Destroy() end
    if show and not Overlay.window then build(hunt) end
    if not Overlay.window then return end

    local widgets = Overlay.widgets --[[@as table]]
    widgets.target.content = targetLabel()

    for index, obj in ipairs(hunt.supplies) do
        widgets.supplies[index].content = tostring(Tracker.Count(obj))
    end

    if widgets.trapSet then
        local trapSetText, enough = hunt.TrapSetStatus(Tracker.Count)
        widgets.trapSet.content = trapSetText
        widgets.trapSet.rgba = enough and GOOD_RGBA or WARN_RGBA
    end

    for index, row in ipairs(widgets.poisons) do
        local text, rgba = damageLabel(index)
        row.damage.content = text
        row.damage.rgba = rgba
        row.detail.content = hunt.Detail(Tracker.Count(hunt.poisons[index].item), Tracker.carrierCounts[index] or 0)
    end

    widgets.hint.content = hintLabel(hunt)
end

--- Opens the overlay on request, whatever the "Show the overlay" setting, until it's closed.
function Overlay.Show()
    Overlay.forced = true
    Overlay.dismissed = false
    Overlay.Render()
end

function Overlay.Destroy()
    if not Overlay.window then return end
    savePlacement()
    Overlay.window:Destroy()
    Overlay.window = nil
    Overlay.widgets = nil
    Overlay.builtFor = nil
end

return Overlay
