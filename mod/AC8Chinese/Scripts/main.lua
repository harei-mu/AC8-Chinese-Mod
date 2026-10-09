-- Offline prototype. Native C++ call sites may bypass reflected UFunction hooks.
-- Never use global text replacement: only audited localization keys are changed.
local replacements = require('translations')
local hits = 0
local errors = 0
local function as_string(value)
    if type(value) == 'string' then return value end
    return value:ToString()
end
local function translated(context, key_param)
    local manager = context:get()
    local culture = as_string(manager:GetCulture())
    if culture ~= 'zh-Hans' and culture ~= 'zh-CN' then return nil end
    local key = as_string(key_param:get())
    local result = replacements[key]
    if result then
        hits = hits + 1
        if hits <= 12 or hits % 100 == 0 then
            print(string.format('[AC8Chinese] hit=%d key=%s\n', hits, key))
        end
    end
    return result
end
local function install(name, text_return)
    local ok, err = pcall(function()
        RegisterHook('/Script/Live.LiveLocalizationManager:' .. name,
            function() end,
            function(context, key_param)
                local success, value = pcall(translated, context, key_param)
                if not success then
                    errors = errors + 1
                    if errors <= 3 then print('[AC8Chinese] callback error: ' .. tostring(value) .. '\n') end
                    return nil
                end
                if value == nil then return nil end
                if text_return then return FText(value) end
                return value
            end)
    end)
    print('[AC8Chinese] hook ' .. name .. ': ' .. (ok and 'registered' or tostring(err)) .. '\n')
end
install('LocalizeString', false)
install('LocalizeText', true)
print('[AC8Chinese] prototype ready; in-game coverage and font rendering require verification\n')
