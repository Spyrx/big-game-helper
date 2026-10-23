-- Small labels above each poison carrier (frogs, moths, mushrooms) showing how much damage its
-- poison deals to the current creature. Carriers whose damage isn't known yet get no label.

local Data = require("src/data")
local Settings = require("src/settings")
local Tracker = require("src/tracker")

local PoisonLabels = {
    -- Keyed like Tracker.carriers: { tooltip = AnchoredTooltip, text = String }.
    labels = {},
}

-- Frogs and moths are small, so their labels sit lower than PrettyUI's default NPC height.
local LABEL_HEIGHT_ABOVE_GROUND = 300

function PoisonLabels.Render()
    -- Work out which carriers should have a label, and what it should say.
    local wanted = {}
    if Settings.values.frogLabels then
        for key, carrier in pairs(Tracker.carriers) do
            local damage = Tracker.GetDamage(carrier.poison)
            if damage and (carrier.npc or carrier.loc).isValid then
                wanted[key] = {
                    npc = carrier.npc,
                    loc = carrier.loc,
                    text = Data.FormatDamage(damage),
                    rgba = Tracker.hunt.poisons[carrier.poison].rgba,
                }
            end
        end
    end

    -- Remove labels that are no longer wanted or out of date. An NPC's label also destroys
    -- itself when the NPC despawns, which leaves its root nil.
    for key, label in pairs(PoisonLabels.labels) do
        local want = wanted[key]
        if not want or label.tooltip.root == nil or label.text ~= want.text then
            label.tooltip:Destroy()
            PoisonLabels.labels[key] = nil
        end
    end

    for key, want in pairs(wanted) do
        if not PoisonLabels.labels[key] then
            local tooltip
            if want.npc then
                tooltip = prettyui.AnchoredTooltip.forNPC(want.npc, {
                    text = want.text,
                    colour = want.rgba,
                    heightAboveGround = LABEL_HEIGHT_ABOVE_GROUND,
                })
            else
                -- Scenery labels use PrettyUI's default height above the tile.
                tooltip = prettyui.AnchoredTooltip.forLoc(want.loc.coordGrid, {
                    text = want.text,
                    colour = want.rgba,
                })
            end
            if tooltip then PoisonLabels.labels[key] = { tooltip = tooltip, text = want.text } end
        end
    end
end

function PoisonLabels.Destroy()
    for _, label in pairs(PoisonLabels.labels) do label.tooltip:Destroy() end
    PoisonLabels.labels = {}
end

return PoisonLabels
