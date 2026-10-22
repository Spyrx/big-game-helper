-- Small labels above each poison frog showing how much damage its poison deals
-- to the current dinosaur. Frogs whose damage isn't known yet get no label.

local Data = require("src/data")
local Settings = require("src/settings")
local Tracker = require("src/tracker")

local FrogLabels = {
    -- Keyed by NPC uid: { tooltip = AnchoredTooltip, text = String }.
    labels = {},
}

-- Frogs are small, so draw the label lower than PrettyUI's default NPC height.
local LABEL_HEIGHT_ABOVE_GROUND = 300

function FrogLabels.Render()
    -- Work out which frogs should have a label, and what it should say.
    local wanted = {}
    if Settings.values.frogLabels then
        for uid, frog in pairs(Tracker.frogs) do
            local damage = Tracker.GetDamage(frog.poison)
            if damage and frog.npc.isValid then
                wanted[uid] = {
                    npc = frog.npc,
                    text = Data.FormatDamage(damage),
                    rgba = Data.POISONS[frog.poison].rgba,
                }
            end
        end
    end

    -- Remove labels that are no longer wanted or out of date. A label also destroys
    -- itself when its frog despawns, which leaves its root nil.
    for uid, label in pairs(FrogLabels.labels) do
        local want = wanted[uid]
        if not want or label.tooltip.root == nil or label.text ~= want.text then
            label.tooltip:Destroy()
            FrogLabels.labels[uid] = nil
        end
    end

    for uid, want in pairs(wanted) do
        if not FrogLabels.labels[uid] then
            local tooltip = prettyui.AnchoredTooltip.forNPC(want.npc, {
                text = want.text,
                colour = want.rgba,
                heightAboveGround = LABEL_HEIGHT_ABOVE_GROUND,
            })
            if tooltip then FrogLabels.labels[uid] = { tooltip = tooltip, text = want.text } end
        end
    end
end

function FrogLabels.Destroy()
    for _, label in pairs(FrogLabels.labels) do label.tooltip:Destroy() end
    FrogLabels.labels = {}
end

return FrogLabels
