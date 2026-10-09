-- UE4SS hot reload may reuse Lua's module cache.
package.loaded['translations'] = nil
local replacements = require('translations')
package.loaded['source-text'] = nil
local sourceText = require('source-text')
package.loaded['target-labels'] = nil
local targetLabels = require('target-labels')
local restoreTargetLabels = {}
for original, translated in pairs(targetLabels) do
    if not restoreTargetLabels[translated] then restoreTargetLabels[translated] = original end
end
local targetChanges = 0
local enableExperimentalTargetPolling = false -- Native updates overwrite it; user observed flicker.
local replacementCount = 0
for _ in pairs(replacements) do replacementCount = replacementCount + 1 end
print('[AC8Chinese] loaded translation keys=' .. replacementCount .. '\n')
local changes = 0
local errors = 0
local diagnosticPass = 0
local function str(value)
    if type(value) == 'string' then return value end
    return value:ToString()
end
local eventHits = 0
local eventGuard = false
local textBlockClass = StaticFindObject('/Script/Live.LiveLocalizeTextBlock')
local function translateAtAssignment(context)
    if eventGuard then return end
    local ok, err = pcall(function()
        local widget = context:get()
        if not widget:IsValid() or not widget:IsA(textBlockClass) or widget.bIsSubtitleTextBlock then return end
        local key = str(widget.TextID)
        local value, sources = replacements[key], sourceText[key]
        if not value or not sources then return end
        local current = widget:GetText():ToString()
        if current ~= sources[1] and current ~= sources[2] then return end
        eventGuard = true
        widget:SetText(FText(value))
        eventGuard = false
        eventHits = eventHits + 1
        if eventHits <= 12 then print('[AC8Chinese] assignment hit=' .. eventHits .. ' key=' .. key .. '\n') end
    end)
    eventGuard = false
    if not ok and errors < 3 then errors = errors + 1; print('[AC8Chinese] assignment error: ' .. tostring(err) .. '\n') end
end
for _, path in ipairs({'/Script/Live.LiveLocalizeTextBlock:SetLocalizeText', '/Script/UMG.TextBlock:SetText'}) do
    local ok, err = pcall(function() RegisterHook(path, function() end, translateAtAssignment) end)
    if not ok then print('[AC8Chinese] assignment hook unavailable: ' .. tostring(err) .. '\n') end
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
                local current = widget:GetText():ToString()
                local sources = sourceText[key]
                if current ~= value and sources and (current == sources[1] or current == sources[2]) then
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
        for _, actor in ipairs(FindAllOf('LiveTargetContainerActor') or {}) do
            local ok, err = pcall(function()
                if not actor:IsValid() then return end
                -- Excludes GamerTagText and callsigns: only generic unit/status labels.
                for _, field in ipairs({'AllianceText', 'ObjectTypeText', 'NextTargetText'}) do
                    local component = actor[field]
                    if component and component:IsValid() then
                        local original = component.Text:ToString()
                        local value = enableExperimentalTargetPolling and targetLabels[original] or restoreTargetLabels[original]
                        if value then
                            component:K2_SetText(FText(value))
                            targetChanges = targetChanges + 1
                            if targetChanges <= 8 then
                                print('[AC8Chinese] target changed ' .. original .. ' -> ' .. value .. ' font=' .. component.Font:GetFullName() .. '\n')
                            end
                        end
                    end
                end
            end)
            if not ok and errors < 3 then errors = errors + 1; print('[AC8Chinese] target error: ' .. tostring(err) .. '\n') end
        end
    end)
    return false
end)
-- Bounded, read-only schema diagnostics for combat labels; no player data logged.
LoopAsync(10000, function()
    diagnosticPass = diagnosticPass + 1
    ExecuteInGameThread(function()
        if diagnosticPass == 1 then
            for _, name in ipairs({'LiveGameObject', 'LiveSetGameObjectDisplayName', 'TargetContainerParams'}) do
                pcall(function()
                    local path = '/Script/Live.' .. name
                    local class = StaticFindObject(path)
                    if class and class:IsValid() then
                        class:ForEachProperty(function(p)
                            print('[AC8Chinese] source schema ' .. p:GetFullName() .. '\n')
                        end)
                    end
                end)
            end
            local actors = FindAllOf('LiveTargetContainerActor') or {}
            for i, actor in ipairs(actors) do
                if i > 3 then break end
                pcall(function()
                    for _, field in ipairs({'AllianceText', 'ObjectTypeText', 'ObjectCallsignText', 'NextTargetText'}) do
                        local component = actor[field]
                        if component and component:IsValid() then
                            print('[AC8Chinese] target component ' .. field .. ' ' .. component:GetFullName() .. '\n')
                            local font = component.Font
                            if font and font:IsValid() then
                                print('[AC8Chinese] font cache=' .. tostring(font.FontCacheType) .. ' glyphs=' .. tostring(font.NumCharacters) .. '\n')
                            end
                            component:GetClass():ForEachProperty(function(p)
                                print('[AC8Chinese] target property ' .. p:GetFullName() .. '\n')
                            end)
                        end
                    end
                end)
            end
        end
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
