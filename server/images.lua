-- ============================================
-- Fivemanage upload handler
-- Uploads processed screenshots to Fivemanage,
-- then registers the URL in retry_inventory via export.
-- No local image storage — retry_inventory owns images.json.
-- ============================================

local resName = GetCurrentResourceName()
local resourcePath = GetResourcePath(resName)

-- Local JSON I/O (only for studio_config.json)
local function LoadJSON(filename)
    local raw = LoadResourceFile(resName, 'data/' .. filename)
    if not raw or raw == '' then return {} end
    return json.decode(raw) or {}
end

local function SaveJSON(filename, data)
    local existing = LoadResourceFile(resName, 'data/' .. filename)
    if existing and existing ~= '' then
        local bakPath = resourcePath .. '/data/' .. filename .. '.bak'
        local bakFile = io.open(bakPath, 'w')
        if bakFile then
            bakFile:write(existing)
            bakFile:close()
        end
    end

    local path = resourcePath .. '/data/' .. filename
    local file = io.open(path, 'w')
    if not file then
        print('[retry_greenscreener] ERROR: Cannot write to ' .. path)
        return false
    end
    file:write(json.encode(data, { indent = true }))
    file:close()
    return true
end

-- Expose for server/main.lua (studio config)
GsJSON = {}
GsJSON.Load = LoadJSON
GsJSON.Save = SaveJSON

-- ============================================
-- Fivemanage upload via PerformHttpRequest
-- ============================================

AddEventHandler('retry_greenscreener:internal:uploadImage', function(payload)
    if type(payload) ~= 'table' then return end
    local name = payload.name
    local base64 = payload.base64
    local src = payload.src
    if not name or not base64 then return end

    local apiKey = GetConvar('retry_greenscreener_fivemanage_key', '')
    if apiKey == '' then
        print('[retry_greenscreener] Fivemanage upload skipped: retry_greenscreener_fivemanage_key convar not set')
        if src then TriggerClientEvent('retry_greenscreener:screenshotDone', src, false, name, nil) end
        return
    end

    local endpoint = GetConvar('retry_greenscreener_fivemanage_endpoint', 'https://api.fivemanage.com/api/v3/file')

    local uploadUrl = endpoint
    if not uploadUrl:find('/base64') then
        uploadUrl = uploadUrl .. '/base64'
    end

    local body = json.encode({
        base64 = 'data:image/png;base64,' .. base64,
        filename = name .. '.png',
        metadata = json.encode({ name = name }),
    })

    print(('[retry_greenscreener] Uploading %s to Fivemanage (%d KB)...'):format(name, math.floor(#body / 1024)))

    PerformHttpRequest(uploadUrl, function(status, responseText, headers)
        if status < 200 or status >= 300 then
            print(('[retry_greenscreener] Fivemanage upload failed: HTTP %d: %s'):format(status, (responseText or ''):sub(1, 200)))
            if src then TriggerClientEvent('retry_greenscreener:screenshotDone', src, false, name, nil) end
            return
        end

        local ok, data = pcall(json.decode, responseText)
        if not ok or type(data) ~= 'table' then
            print(('[retry_greenscreener] Fivemanage bad response: %s'):format((responseText or ''):sub(1, 200)))
            if src then TriggerClientEvent('retry_greenscreener:screenshotDone', src, false, name, nil) end
            return
        end

        local url = (data.data and data.data.url) or data.url or data.Url or data.link
        if not url then
            print(('[retry_greenscreener] Fivemanage no URL in response: %s'):format((responseText or ''):sub(1, 200)))
            if src then TriggerClientEvent('retry_greenscreener:screenshotDone', src, false, name, nil) end
            return
        end

        -- Add cache-buster
        local cleanUrl = url:gsub('%?t=%d+$', '')
        local bustUrl = cleanUrl .. '?t=' .. os.time()

        print(('[retry_greenscreener] Uploaded: %s -> %s'):format(name, url))

        -- Register URL in retry_inventory (which owns images.json)
        local setOk = pcall(exports.retry_inventory.SetImage, exports.retry_inventory, name:lower(), bustUrl)
        if not setOk then
            print('[retry_greenscreener] Warning: could not register image in retry_inventory')
        end

        if src then TriggerClientEvent('retry_greenscreener:screenshotDone', src, true, name, bustUrl) end
    end, 'POST', body, {
        ['Content-Type'] = 'application/json',
        ['Authorization'] = apiKey,
    })
end)
