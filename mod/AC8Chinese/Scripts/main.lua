local replacements = require('translations')
local changes = 0
local errors = 0
local diagnosticPass = 0
local function str(value)
    if type(value) == 'string' then return value end
    return value:ToString()
end
-- Native UI calls bypass reflected wrappers. TextID was verified at runtime.
LoopAsync(500, function()
    ExecuteInGameThread(function()
        local widgets = FindAllOf('LiveLocalizeTextBlock') or {}
        for _, widget in ipairs(widgets) do
            local ok, err = pcall(function()
                if not widget:IsValid() then return end
                local key = str(widget.TextID)
                local value = replacements[key]
                if not value or widget.bIsSubtitleTextBlock then return end
                if widget:GetText():ToString() ~= value then
                    widget:SetText(FText(value))
                    changes = changes + 1
                    if changes <= 20 or changes % 100 == 0 then
                        print(string.format('[AC8Chinese] widget changed=%d key=%s text=%s\n', changes, key, value))
                    end
                end
            end)
            if not ok then
                errors = errors + 1
                if errors <= 3 then print('[AC8Chinese] widget error: ' .. tostring(err) .. '\n') end
            end
        end
    end)
    return false
end)
-- Bounded, read-only schema diagnostics for combat labels; no player data logged.
LoopAsync(10000, function()
    diagnosticPass = diagnosticPass + 1
    ExecuteInGameThread(function()
        for _, name in ipairs({'LiveTargetContainerActor', 'LiveTargetContainerManager', 'LiveMiniMapWidget', 'LiveNUITextBlock'}) do
            local ok, err = pcall(function()
                local class = StaticFindObject('/Script/Live.' .. name)
                if diagnosticPass == 1 and class and class:IsValid() then
                    class:ForEachProperty(function(property)
                        print('[AC8Chinese] schema ' .. property:GetFullName() .. '\n')
                    end)
                end
                print('[AC8Chinese] instances ' .. name .. '=' .. #(FindAllOf(name) or {}) .. '\n')
            end)
            if not ok then print('[AC8Chinese] diagnostic: ' .. tostring(err) .. '\n') end
        end
    end)
    return diagnosticPass >= 6
end)
print('[AC8Chinese] exact TextID widget translation active; rendering validation pending\n')
