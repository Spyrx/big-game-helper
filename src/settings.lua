-- User settings, saved in the PersistentDB, plus the Plugin Hub settings page.

local Settings = {
    values = {
        -- "auto" shows the overlay only while hunting; also "always" or "never".
        overlayMode = "auto",
        frogLabels = false,
    },
    view = nil,
    listeners = {},
    -- Opens the overlay. Set by main.lua, since the overlay module itself depends on Settings.
    showOverlay = nil,
}

function Settings.Load()
    local overlayMode = PersistentDB:GetString("overlayMode")
    if overlayMode then Settings.values.overlayMode = overlayMode end

    local frogLabels = PersistentDB:GetBool("frogLabels")
    if frogLabels ~= nil then Settings.values.frogLabels = frogLabels end
end

--- Registers a callback that runs whenever a setting changes.
function Settings.OnChange(callback)
    table.insert(Settings.listeners, callback)
end

function Settings.Set(key, value)
    Settings.values[key] = value
    PersistentDB:Set(key, value)
    for _, callback in ipairs(Settings.listeners) do callback() end
end

function Settings.HasChatAccess()
    return Plugin.HasPermission(PluginPermissions.chatAccess) == true
end

--- Builds the settings page, shown from the Plugin Hub's settings icon and the plugin's ribbon icon.
function Settings.BuildView(event)
    Settings.DestroyView()

    local parent = event.component
    local view = prettyui.SimpleView.new(parent, { width = parent.width, height = parent.height })
    Settings.view = view

    view:AddTitle("Big Game Helper")
    view:AddSimpleButton("Show overlay", function()
        if Settings.showOverlay then Settings.showOverlay() end
    end)
    view:AddText("Show the overlay automatically")
    view:AddRadioButton({
        { text = "Only while hunting", value = "auto" },
        { text = "Always", value = "always" },
        { text = "Never", value = "never" },
    }, {
        selectedValue = Settings.values.overlayMode,
        onChange = function(_, value) Settings.Set("overlayMode", value) end,
    })

    view:AddCheckboxButton({
        {
            text = "Label poison frogs with their damage",
            value = "frogLabels",
            selected = Settings.values.frogLabels,
        },
    }, {
        onChange = function(_, _, changedValue, selected) Settings.Set(changedValue, selected) end,
    })

    view:AddTitle("Chat access")
    if Settings.HasChatAccess() then
        view:AddText("Allowed. Poison damage is learned from your game messages.")
    else
        view:AddText("Not allowed. Allow chat access for this plugin in the Plugin Hub to learn poison damage "
            .. "from game messages, or set it by hand in the overlay.")
    end
end

function Settings.DestroyView()
    if Settings.view then
        Settings.view:Destroy()
        Settings.view = nil
    end
end

return Settings
