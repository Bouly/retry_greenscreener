-- ============================================
-- Retry Greenscreener - Server Main
-- Admin checks, studio config, image save
-- ============================================

local resName = GetCurrentResourceName()

-- ============================================
-- Permission check
-- ============================================

local function IsAdmin(source)
    return IsPlayerAceAllowed(source, 'command.itemcreator') or IsPlayerAceAllowed(source, 'group.admin')
end

-- Admin check callback for screenshot.js
AddEventHandler('retry_greenscreener:internal:checkAdmin', function(source, cb)
    cb(IsAdmin(source))
end)

-- ============================================
-- Studio Config (invisible drawables per component)
-- ============================================

lib.callback.register('retry_greenscreener:getStudioConfig', function(source)
    if not IsAdmin(source) then return nil end
    return GsJSON.Load('studio_config.json')
end)

lib.callback.register('retry_greenscreener:saveStudioConfig', function(source, data)
    if not IsAdmin(source) then return false end
    GsJSON.Save('studio_config.json', data)
    TriggerClientEvent('retry_greenscreener:studioConfigUpdated', -1, data)
    return true
end)

-- ============================================
-- Image save callback (local PNG save to inventory resource)
-- Called from admin panel NUI after screenshot preview
-- ============================================

lib.callback.register('retry_greenscreener:saveImage', function(source, data)
    if not IsAdmin(source) then return false end
    if not data or not data.name or not data.base64 then return false end

    local safeName = data.name:lower():gsub('[^a-z0-9_%-]', '_')
    local base64Data = data.base64:gsub('^data:image/png;base64,', '')

    -- Save to the inventory resource's web/images/
    local invResName = 'retry_inventory'
    local filePath = 'web/images/' .. safeName .. '.png'
    SaveResourceFile(invResName, filePath, base64Data, -1)

    print(('[retry_greenscreener] Admin saved image: %s.png'):format(safeName))
    return true
end)
