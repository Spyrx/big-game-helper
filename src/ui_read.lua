-- Read-only helpers for looking at the game's own interface components.
-- Nothing here changes the game's UI; it only reads what's already on screen.

local UiRead = {}

-- How deep to look inside a component's children.
local MAX_DEPTH = 6

--- Reads a property that may not exist on every component type, returning nil instead of erroring.
function UiRead.Get(component, field)
    local succeeded, value = pcall(function() return component[field] end)
    if succeeded then return value end
    return nil
end

--- Reads a text component's content with formatting tags such as <col=ff0000> removed.
function UiRead.PlainText(component)
    local content = UiRead.Get(component, "content")
    if type(content) ~= "string" then return nil end
    return (content:gsub("<[^>]*>", ""))
end

--- Calls visit(component, depth, visible) for a component and each of its visible descendants,
--- or all descendants when includeHidden is true.
--- Stops early if visit returns true, and then returns true itself.
function UiRead.Walk(component, visit, includeHidden, depth, visible)
    depth = depth or 0
    if visit(component, depth, visible ~= false) == true then return true end
    if depth >= MAX_DEPTH then return false end

    local stopped = false
    local function visitChild(child, childVisible)
        if (childVisible or includeHidden) and UiRead.Walk(child, visit, includeHidden, depth + 1, childVisible) then
            stopped = true
            return true
        end
        return false
    end
    -- Only collection-type components (layers, panels, ...) have children.
    pcall(function() component:IterateStaticComponents(visitChild) end)
    if not stopped then pcall(function() component:IterateDynamicComponents(visitChild) end) end
    return stopped
end

--- Returns the number of direct children (visible or not) of a component.
function UiRead.ChildCount(component)
    local count = 0
    local function countChild() count = count + 1 end
    pcall(function() component:IterateStaticComponents(countChild) end)
    pcall(function() component:IterateDynamicComponents(countChild) end)
    return count
end

return UiRead
