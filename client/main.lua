-- ============================================
-- Retry Greenscreener - Client Main
-- Green Screen Screenshot Studio
-- Extracted from retry_inventory/client/admin.lua
-- ============================================

local previewProp = nil
local isItemProp = false
local propPitch = 0.0
local propRoll = 0.0
local freeRotateActive = false
local previewCam = nil
local savedModel = nil
local isScreenshotMode = false
local screenshotItemName = nil
local propRotation = 0.0
local isDraggingProp = false
local lastMouseX = 0

-- Green screen coordinates (must match the YMAP placement)
local GREEN_SCREEN_POS = vector3(-1289.02, -3409.83, 20.91)
local GREEN_SCREEN_ROT = vector3(0.0, 0.0, 330.0)
local GREEN_SCREEN_HIDDEN = vector3(-1224.22, -3349.63, 13.96)

-- Studio config (invisible drawables per component, loaded from server)
local studioConfig = nil

-- Saved player state before screenshot
local savedCoords = nil
local savedHeading = nil
local savedSkin = nil

-- Callback event to fire when screenshot completes (for inventory to reopen admin)
local callbackEvent = nil

-- ============================================
-- NUI Helper (self-contained)
-- ============================================

local function SendNUI(action, data)
    SendNuiMessage(json.encode({ action = action, data = data or {} }))
end

-- ============================================
-- Green Screen Screenshot System
-- ============================================

local clothingPed = nil
local isBatchMode = false
local batchData = nil
local freezeInterval = nil

-- Camera settings per component (same as greenscreener config.json)
local CLOTHING_CAM_SETTINGS = {
    [1]   = { fov = 30, rotation = vector3(0, 0, 120),  zPos = 0.65,  name = 'Masks' },
    [3]   = { fov = 55, rotation = vector3(0, 0, 155),  zPos = 0.3,   name = 'Torsos' },
    [4]   = { fov = 60, rotation = vector3(0, 0, 155),  zPos = -0.46, name = 'Legs' },
    [5]   = { fov = 40, rotation = vector3(0, 0, -25),  zPos = 0.3,   name = 'Bags' },
    [6]   = { fov = 40, rotation = vector3(0, 0, 120),  zPos = -0.85, name = 'Shoes' },
    [7]   = { fov = 45, rotation = vector3(0, 0, 155),  zPos = 0.3,   name = 'Accessories' },
    [8]   = { fov = 45, rotation = vector3(0, 0, 155),  zPos = 0.3,   name = 'Undershirts' },
    [9]   = { fov = 45, rotation = vector3(0, 0, 155),  zPos = 0.3,   name = 'Vests' },
    [11]  = { fov = 55, rotation = vector3(0, 0, 155),  zPos = 0.26,  name = 'Tops' },
    [100] = { fov = 30, rotation = vector3(0, 0, 120),  zPos = 0.75,  name = 'Hats' },
    [101] = { fov = 20, rotation = vector3(0, 0, 120),  zPos = 0.7,   name = 'Glasses' },
}

-- ============================================
-- Helpers
-- ============================================

--- Reset ped to invisible state
local function ResetPedComponents()
    local invDrawables = studioConfig and studioConfig.invisibleDrawables or {}

    SetPedDefaultComponentVariation(clothingPed)
    Wait(150)

    for compId = 0, 11 do
        local key = tostring(compId)
        if invDrawables[key] then
            SetPedComponentVariation(clothingPed, compId, invDrawables[key].drawable or -1, invDrawables[key].texture or 0, 0)
        else
            SetPedComponentVariation(clothingPed, compId, -1, 0, 0)
        end
    end

    SetPedHairColor(clothingPed, 45, 15)
    for p = 0, 7 do
        ClearPedProp(clothingPed, p)
    end
end

--- Load component with preload
local function LoadComponentVariation(component, drawable, texture)
    texture = texture or 0
    SetPedPreloadVariationData(clothingPed, component, drawable, texture)
    while not HasPedPreloadVariationDataFinished(clothingPed) do
        Wait(50)
    end
    SetPedComponentVariation(clothingPed, component, drawable, texture, 0)
end

--- Load prop with preload
local function LoadPropVariation(propId, drawable, texture)
    texture = texture or 0
    SetPedPreloadPropData(clothingPed, propId, drawable, texture)
    while not HasPedPreloadPropDataFinished(clothingPed) do
        Wait(50)
    end
    ClearPedProp(clothingPed, propId)
    SetPedPropIndex(clothingPed, propId, drawable, texture, true)
end

-- ============================================
-- Lights
-- ============================================

local studioLights = {}
local lightThreadActive = false

function DrawLights()
    for _, light in pairs(studioLights) do
        DrawLightWithRange(light.pos.x, light.pos.y, light.pos.z, light.r, light.g, light.b, 5.0, light.intensity)
    end
end

function StartLightThread()
    if lightThreadActive then return end
    lightThreadActive = true
    CreateThread(function()
        while lightThreadActive do
            local hasLights = false
            for _, light in pairs(studioLights) do
                DrawLightWithRange(light.pos.x, light.pos.y, light.pos.z, light.r, light.g, light.b, 5.0, light.intensity)
                hasLights = true
            end
            if not hasLights then
                Wait(50)
            else
                Wait(0)
            end
        end
    end)
end

function StopLightThread()
    lightThreadActive = false
end

function CleanupLights()
    lightThreadActive = false
    studioLights = {}
    SetWeatherTypeNowPersist('EXTRASUNNY')
    SetWeatherTypeNow('EXTRASUNNY')
    ClearOverrideWeather()
end

-- ============================================
-- Freeze interval (for clothing ped)
-- ============================================

local function StartFreezeInterval()
    if freezeInterval then return end
    freezeInterval = true
    CreateThread(function()
        while freezeInterval and clothingPed and DoesEntityExist(clothingPed) do
            ClearPedTasksImmediately(clothingPed)
            FreezeEntityPosition(clothingPed, true)
            DrawLights()
            Wait(0)
        end
    end)
end

local function StopFreezeInterval()
    freezeInterval = nil
end

-- ============================================
-- Scene Setup
-- ============================================

--- Setup scene: change model, position at green screen
local function SetupScene(gender)
    local ped = cache.ped
    savedCoords = GetEntityCoords(ped)
    savedHeading = GetEntityHeading(ped)
    savedModel = GetEntityModel(ped)

    -- Save skin via skinchanger before changing model
    savedSkin = nil
    if GetResourceState('skinchanger') == 'started' then
        TriggerEvent('skinchanger:getSkin', function(skin)
            savedSkin = skin
        end)
    end

    SetRainLevel(0.0)
    SetWeatherTypePersist('EXTRASUNNY')
    SetWeatherTypeNow('EXTRASUNNY')
    SetWeatherTypeNowPersist('EXTRASUNNY')
    NetworkOverrideClockTime(18, 0, 0)
    DisableIdleCamera(true)
    Wait(100)

    local modelHash = gender == 'female' and joaat('mp_f_freemode_01') or joaat('mp_m_freemode_01')
    if not HasModelLoaded(modelHash) then
        RequestModel(modelHash)
        local timeout = 50
        while not HasModelLoaded(modelHash) and timeout > 0 do
            Wait(100)
            timeout = timeout - 1
        end
        if not HasModelLoaded(modelHash) then return false end
    end

    SetPlayerModel(PlayerId(), modelHash)
    Wait(150)
    SetModelAsNoLongerNeeded(modelHash)
    Wait(150)

    clothingPed = PlayerPedId()

    SetEntityRotation(clothingPed, GREEN_SCREEN_ROT.x, GREEN_SCREEN_ROT.y, GREEN_SCREEN_ROT.z, 0, false)
    SetEntityCoordsNoOffset(clothingPed, GREEN_SCREEN_POS.x, GREEN_SCREEN_POS.y, GREEN_SCREEN_POS.z, false, false, false)
    FreezeEntityPosition(clothingPed, true)
    Wait(50)
    SetPlayerControl(PlayerId(), false)

    if not studioConfig then
        studioConfig = lib.callback.await('retry_greenscreener:getStudioConfig', false) or {}
    end

    StartFreezeInterval()
    return true
end

--- Setup camera for a component
local function SetupCamera(componentId)
    local camSettings = CLOTHING_CAM_SETTINGS[componentId] or { fov = 45, rotation = vector3(0, 0, 155), zPos = 0.3 }

    local pedCoords = GetEntityCoords(clothingPed)
    local fwdX, fwdY, fwdZ = table.unpack(GetEntityForwardVector(clothingPed))

    if previewCam then DestroyCam(previewCam, false) end

    local camPos = vector3(
        pedCoords.x + fwdX * 1.2,
        pedCoords.y + fwdY * 1.2,
        pedCoords.z + fwdZ + camSettings.zPos
    )

    previewCam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', camPos.x, camPos.y, camPos.z, 0, 0, 0, camSettings.fov, true, 0)
    PointCamAtCoord(previewCam, pedCoords.x, pedCoords.y, pedCoords.z + camSettings.zPos)
    SetCamActive(previewCam, true)
    RenderScriptCams(true, false, 0, true, false, 0)

    Wait(50)
    SetEntityRotation(clothingPed, camSettings.rotation.x, camSettings.rotation.y, camSettings.rotation.z, 2, false)

    previewProp = clothingPed
    propRotation = camSettings.rotation.z
    isItemProp = false
end

--- Restore player to original state
local function RestorePlayer()
    StopFreezeInterval()
    CleanupPreview()
    CleanupLights()

    if savedModel then
        if not HasModelLoaded(savedModel) then
            RequestModel(savedModel)
            local timeout = 50
            while not HasModelLoaded(savedModel) and timeout > 0 do Wait(100); timeout = timeout - 1 end
        end
        if HasModelLoaded(savedModel) then
            SetPlayerModel(PlayerId(), savedModel)
            Wait(150)
            SetModelAsNoLongerNeeded(savedModel)
        end
        savedModel = nil
    end

    Wait(200)
    local ped = PlayerPedId()
    if savedCoords then
        SetEntityCoordsNoOffset(ped, savedCoords.x, savedCoords.y, savedCoords.z, false, false, false)
        SetEntityHeading(ped, savedHeading or 0.0)
        FreezeEntityPosition(ped, false)
        SetPlayerControl(PlayerId(), true)
        DisableIdleCamera(false)
    end
    savedCoords = nil
    savedHeading = nil

    -- Restore skin (clothing/appearance) after model change
    if savedSkin and GetResourceState('skinchanger') == 'started' then
        TriggerEvent('skinchanger:loadSkin', savedSkin)
        savedSkin = nil
    end
end

--- Capture screenshot (waits for completion)
local function CaptureScreenshot(imageName)
    TriggerServerEvent('retry_greenscreener:captureScreenshot', imageName)
    Wait(2000)
end

-- ============================================
-- Cleanup
-- ============================================

function CleanupPreview()
    if previewProp and DoesEntityExist(previewProp) then
        DeleteEntity(previewProp)
        previewProp = nil
    end
    if clothingPed and clothingPed ~= previewProp and DoesEntityExist(clothingPed) then
        DeleteEntity(clothingPed)
    end
    clothingPed = nil
    if previewCam then
        RenderScriptCams(false, false, 0, true, false, 0)
        SetCamActive(previewCam, false)
        DestroyCam(previewCam, false)
        previewCam = nil
    end
    isScreenshotMode = false
end

-- ============================================
-- Re-apply invisibles (for batch captures)
-- ============================================

local function ReApplyInvisibles(excludeCompId)
    local invDrawables = studioConfig and studioConfig.invisibleDrawables or {}
    for compId = 0, 11 do
        if compId ~= excludeCompId then
            local key = tostring(compId)
            if invDrawables[key] then
                SetPedComponentVariation(clothingPed, compId, invDrawables[key].drawable or -1, invDrawables[key].texture or 0, 0)
            else
                SetPedComponentVariation(clothingPed, compId, -1, 0, 0)
            end
        end
    end
    for p = 0, 7 do
        if (p + 100) ~= excludeCompId then
            ClearPedProp(clothingPed, p)
        end
    end
end

-- ============================================
-- Batch Runners
-- ============================================

--- Run texture batch: same drawable, cycle textures
local function RunBatch(data)
    if not data then return end
    isBatchMode = true

    local savedRotation = propRotation
    local isProp = data.componentId >= 100
    local realCompId = isProp and (data.componentId - 100) or data.componentId

    for tex = 0, data.maxTextures - 1 do
        local imageName = ('clothing_%d_%d_%d'):format(data.componentId, data.drawableId, tex)

        ReApplyInvisibles(isProp and -1 or realCompId)
        Wait(100)

        if isProp then
            LoadPropVariation(realCompId, data.drawableId, tex)
        else
            LoadComponentVariation(realCompId, data.drawableId, tex)
        end
        SetEntityRotation(clothingPed, 0.0, 0.0, savedRotation, 2, false)
        Wait(800)

        CaptureScreenshot(imageName)
    end

    isBatchMode = false
    isScreenshotMode = false
    RestorePlayer()

    -- Notify caller (pass returnToShop so inventory can reopen the shop)
    if callbackEvent then
        TriggerEvent(callbackEvent, true, data.maxTextures .. ' screenshots taken', data.returnToShop)
        callbackEvent = nil
    end
end

--- Run full batch: all drawables, all textures
local function RunFullBatch(data)
    if not data then return end
    isBatchMode = true

    local savedRotation = propRotation
    local isProp = data.componentId >= 100
    local realCompId = isProp and (data.componentId - 100) or data.componentId
    local count = 0

    for drawable = 0, data.maxDrawables - 1 do
        ResetPedComponents()
        Wait(200)

        local maxTex = isProp
            and GetNumberOfPedPropTextureVariations(clothingPed, realCompId, drawable)
            or GetNumberOfPedTextureVariations(clothingPed, realCompId, drawable)
        if maxTex < 1 then maxTex = 1 end

        for tex = 0, maxTex - 1 do
            local imageName = ('clothing_%d_%d_%d'):format(data.componentId, drawable, tex)
            count = count + 1

            ReApplyInvisibles(isProp and -1 or realCompId)
            Wait(100)

            if isProp then
                LoadPropVariation(realCompId, drawable, tex)
            else
                LoadComponentVariation(realCompId, drawable, tex)
            end
            SetEntityRotation(clothingPed, 0.0, 0.0, savedRotation, 2, false)
            Wait(800)

            CaptureScreenshot(imageName)
        end
    end

    isBatchMode = false
    isScreenshotMode = false
    RestorePlayer()

    -- Notify caller
    if callbackEvent then
        TriggerEvent(callbackEvent, true, count .. ' screenshots taken')
        callbackEvent = nil
    end
end

-- ============================================
-- Screenshot Loop (mouse rotation + zoom + ENTER capture)
-- ============================================

local function ScreenshotLoop()
    CreateThread(function()
        while isScreenshotMode do
            Wait(0)

            if not previewProp or not DoesEntityExist(previewProp) then
                isScreenshotMode = false
                break
            end

            -- Keep ped frozen
            if clothingPed and DoesEntityExist(clothingPed) and not isItemProp then
                ClearPedTasksImmediately(clothingPed)
            end

            -- Re-apply rotation each frame
            if isItemProp then
                SetEntityRotation(previewProp, propPitch, propRoll, propRotation, 2, false)
            else
                SetEntityRotation(previewProp, 0.0, 0.0, propRotation, 2, false)
            end
            FreezeEntityPosition(previewProp, true)

            DrawLights()

            -- Disable interfering controls
            DisableControlAction(0, 25, true)   -- INPUT_AIM
            DisableControlAction(0, 1, true)    -- INPUT_LOOK_LR
            DisableControlAction(0, 2, true)    -- INPUT_LOOK_UD
            DisableControlAction(0, 106, true)  -- INPUT_VEH_MOUSE_CONTROL_OVERRIDE

            -- Free rotation mode: hold LEFT ALT
            local altHeld = IsDisabledControlPressed(0, 19)
            if isItemProp and altHeld then
                if not freeRotateActive then
                    freeRotateActive = true
                    SetNuiFocus(false, false)
                end
                local dx = GetDisabledControlNormal(0, 1) * 8.0
                local dy = GetDisabledControlNormal(0, 2) * 8.0
                local shiftHeld = IsDisabledControlPressed(0, 21)

                if shiftHeld then
                    propRoll = propRoll + dx * 30.0
                else
                    propRotation = propRotation + dx * 30.0
                    propPitch = propPitch + dy * 30.0
                end
            elseif freeRotateActive then
                freeRotateActive = false
                SetNuiFocus(true, true)
                SetNuiFocusKeepInput(true)
            end

            -- Rotation Z (yaw): A/D or Left/Right
            if IsDisabledControlPressed(0, 34) or IsDisabledControlPressed(0, 174) then
                propRotation = propRotation - 1.5
            end
            if IsDisabledControlPressed(0, 35) or IsDisabledControlPressed(0, 175) then
                propRotation = propRotation + 1.5
            end

            -- Rotation X/Y (pitch/roll): items only
            if isItemProp then
                if IsDisabledControlPressed(0, 32) then propPitch = propPitch + 1.5 end
                if IsDisabledControlPressed(0, 33) then propPitch = propPitch - 1.5 end
                if IsDisabledControlPressed(0, 44) then propRoll = propRoll - 1.5 end
                if IsDisabledControlPressed(0, 38) then propRoll = propRoll + 1.5 end
                -- R = reset rotation
                if IsDisabledControlJustPressed(0, 45) then
                    propRotation = GREEN_SCREEN_ROT.z
                    propPitch = 0.0
                    propRoll = 0.0
                end
            end

            -- ENTER = capture
            if IsControlJustPressed(0, 191) then
                DoCapture()
            end

            -- Block pause menu
            DisableControlAction(0, 200, true)
            DisableControlAction(0, 199, true)

            -- ESCAPE or BACKSPACE = cancel
            if IsDisabledControlJustPressed(0, 200) or IsDisabledControlJustPressed(0, 199) or IsControlJustPressed(0, 194) then
                CancelScreenshot()
                break
            end
        end
    end)
end

-- ============================================
-- Capture & Cancel
-- ============================================

function DoCapture()
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUI('screenshotStudioClose', {})

    Wait(300)

    if batchData then
        local data = batchData
        batchData = nil
        isScreenshotMode = false
        Wait(100)
        if data.fullBatch then
            RunFullBatch(data)
        else
            RunBatch(data)
        end
        return
    end

    -- Single mode
    TriggerServerEvent('retry_greenscreener:captureScreenshot', screenshotItemName)

    Wait(500)
    isScreenshotMode = false
end

function CancelScreenshot()
    isScreenshotMode = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUI('screenshotStudioClose', {})
    CleanupPreview()
    CleanupLights()

    if savedModel then
        if not HasModelLoaded(savedModel) then
            RequestModel(savedModel)
            local timeout = 50
            while not HasModelLoaded(savedModel) and timeout > 0 do Wait(100); timeout = timeout - 1 end
        end
        if HasModelLoaded(savedModel) then
            SetPlayerModel(PlayerId(), savedModel)
            Wait(150)
            SetModelAsNoLongerNeeded(savedModel)
        end
        savedModel = nil
    end

    Wait(100)

    if savedCoords then
        local ped = PlayerPedId()
        SetEntityCoordsNoOffset(ped, savedCoords.x, savedCoords.y, savedCoords.z, false, false, false)
        SetEntityHeading(ped, savedHeading or 0.0)
        FreezeEntityPosition(ped, false)
        SetPlayerControl(PlayerId(), true)
        DisableIdleCamera(false)
        savedCoords = nil
        savedHeading = nil
    end

    -- Restore skin after model change
    if savedSkin and GetResourceState('skinchanger') == 'started' then
        TriggerEvent('skinchanger:loadSkin', savedSkin)
        savedSkin = nil
    end

    Wait(200)

    -- Notify caller that screenshot was cancelled
    if callbackEvent then
        TriggerEvent(callbackEvent, false, 'cancelled')
        callbackEvent = nil
    end
end

-- ============================================
-- Server screenshot done handler
-- ============================================

RegisterNetEvent('retry_greenscreener:screenshotDone', function(success, imageName, imageUrl)
    if isBatchMode then return end

    CleanupPreview()
    CleanupLights()

    if savedModel then
        if not HasModelLoaded(savedModel) then
            RequestModel(savedModel)
            local timeout = 50
            while not HasModelLoaded(savedModel) and timeout > 0 do Wait(100); timeout = timeout - 1 end
        end
        if HasModelLoaded(savedModel) then
            SetPlayerModel(PlayerId(), savedModel)
            Wait(150)
            SetModelAsNoLongerNeeded(savedModel)
        end
        savedModel = nil
    end

    Wait(100)

    if savedCoords then
        local ped = PlayerPedId()
        SetEntityCoordsNoOffset(ped, savedCoords.x, savedCoords.y, savedCoords.z, false, false, false)
        SetEntityHeading(ped, savedHeading or 0.0)
        FreezeEntityPosition(ped, false)
        SetPlayerControl(PlayerId(), true)
        DisableIdleCamera(false)
        savedCoords = nil
        savedHeading = nil
    end

    -- Restore skin after model change
    if savedSkin and GetResourceState('skinchanger') == 'started' then
        TriggerEvent('skinchanger:loadSkin', savedSkin)
        savedSkin = nil
    end

    Wait(200)

    -- Notify caller
    if callbackEvent then
        TriggerEvent(callbackEvent, success, imageName)
        callbackEvent = nil
    end
end)

-- ============================================
-- NUI Callbacks - Studio Controls
-- ============================================

RegisterNUICallback('studioSetTime', function(data, cb)
    NetworkOverrideClockTime(data.hour or 12, data.minute or 0, 0)
    cb(1)
end)

RegisterNUICallback('studioSetWeather', function(data, cb)
    if data.weather and data.weather ~= '' then
        SetWeatherTypeNowPersist(data.weather)
        SetWeatherTypeNow(data.weather)
        SetWeatherTypePersist(data.weather)
        SetRainLevel(0.0)
    end
    cb(1)
end)

RegisterNUICallback('studioSetLights', function(data, cb)
    studioLights = {}

    if not previewProp or not DoesEntityExist(previewProp) then
        cb(1)
        return
    end

    local propCoords = GetEntityCoords(previewProp)
    local intensity = data.intensity or 5.0

    local r, g, b = 255, 255, 255
    if data.color and #data.color == 7 then
        r = tonumber(data.color:sub(2, 3), 16) or 255
        g = tonumber(data.color:sub(4, 5), 16) or 255
        b = tonumber(data.color:sub(6, 7), 16) or 255
    end

    local offsets = {
        front  = vector3(0.0, -1.5, 0.0),
        back   = vector3(0.0, 1.5, 0.0),
        left   = vector3(-1.5, 0.0, 0.0),
        right  = vector3(1.5, 0.0, 0.0),
        top    = vector3(0.0, 0.0, 1.5),
        bottom = vector3(0.0, 0.0, -0.5),
    }

    local hasAny = false
    for dir, enabled in pairs(data.lights or {}) do
        if enabled and offsets[dir] then
            local pos = propCoords + offsets[dir]
            studioLights[dir] = { pos = pos, r = r, g = g, b = b, intensity = intensity }
            hasAny = true
        end
    end

    if hasAny then
        StartLightThread()
    end

    cb(1)
end)

RegisterNUICallback('studioCapture', function(_, cb)
    if isScreenshotMode then
        DoCapture()
    end
    cb(1)
end)

RegisterNUICallback('studioCancel', function(_, cb)
    if isScreenshotMode then
        CancelScreenshot()
    end
    cb(1)
end)

-- ============================================
-- NUI Callbacks - Studio Config
-- ============================================

RegisterNUICallback('getStudioConfig', function(_, cb)
    local config = lib.callback.await('retry_greenscreener:getStudioConfig', false)
    studioConfig = config
    cb(config or {})
end)

RegisterNUICallback('saveStudioConfig', function(data, cb)
    local success = lib.callback.await('retry_greenscreener:saveStudioConfig', false, data)
    if success then studioConfig = data end
    cb({ success = success })
end)

RegisterNetEvent('retry_greenscreener:studioConfigUpdated', function(data)
    studioConfig = data
end)

-- ============================================
-- NUI Callback - Save Image
-- ============================================

RegisterNUICallback('saveImage', function(data, cb)
    local success = lib.callback.await('retry_greenscreener:saveImage', false, data)
    cb({ success = success })
end)

-- ============================================
-- Image cache sync
-- ============================================

-- Image events (imageUpdated, imageRemoved) are handled by retry_inventory directly

-- ============================================
-- Client Exports (called by retry_inventory admin panel)
-- ============================================

--- Start item screenshot (3D prop on green screen)
---@param model string Prop model name or weapon hash
---@param itemName string Item name for the screenshot filename
---@param cbEvent string|nil Client event to fire when done (success, imageName)
exports('StartItemScreenshot', function(model, itemName, cbEvent)
    if isScreenshotMode then return false end
    callbackEvent = cbEvent

    screenshotItemName = itemName or 'item'

    local modelHash = joaat(model)
    if IsWeaponValid(modelHash) then
        modelHash = GetWeapontypeModel(modelHash)
    end

    if not IsModelValid(modelHash) then return false end

    lib.requestModel(modelHash, 5000)
    if not HasModelLoaded(modelHash) then return false end

    local ped = cache.ped
    savedCoords = GetEntityCoords(ped)
    savedHeading = GetEntityHeading(ped)

    SetEntityCoordsNoOffset(ped, GREEN_SCREEN_HIDDEN.x, GREEN_SCREEN_HIDDEN.y, GREEN_SCREEN_HIDDEN.z, false, false, false)
    FreezeEntityPosition(ped, true)
    SetPlayerControl(PlayerId(), false)

    SetRainLevel(0.0)
    SetWeatherTypePersist('EXTRASUNNY')
    SetWeatherTypeNow('EXTRASUNNY')
    SetWeatherTypeNowPersist('EXTRASUNNY')
    NetworkOverrideClockTime(12, 0, 0)

    Wait(200)

    previewProp = CreateObjectNoOffset(modelHash, GREEN_SCREEN_POS.x, GREEN_SCREEN_POS.y, GREEN_SCREEN_POS.z, false, true, true)
    SetEntityRotation(previewProp, GREEN_SCREEN_ROT.x, GREEN_SCREEN_ROT.y, GREEN_SCREEN_ROT.z, 0, false)
    FreezeEntityPosition(previewProp, true)
    SetModelAsNoLongerNeeded(modelHash)

    Wait(100)

    local min, max = GetModelDimensions(modelHash)
    local modelSize = {
        x = max.x - min.x,
        y = max.y - min.y,
        z = max.z - min.z,
    }
    local fov = math.min(math.max(modelSize.x, modelSize.z) / 0.15 * 10, 60)
    fov = math.max(fov, 20)

    local propCoords = GetEntityCoords(previewProp)
    local fwd = GetEntityForwardVector(previewProp)
    local center = vector3(
        propCoords.x + (min.x + max.x) / 2,
        propCoords.y + (min.y + max.y) / 2,
        propCoords.z + (min.z + max.z) / 2
    )
    local camDist = 1.2 + math.max(modelSize.x, modelSize.z) / 2
    local camPos = vector3(
        center.x + fwd.x * camDist,
        center.y + fwd.y * camDist,
        center.z
    )

    previewCam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', camPos.x, camPos.y, camPos.z, 0, 0, 0, fov, true, 0)
    PointCamAtCoord(previewCam, center.x, center.y, center.z)
    SetCamActive(previewCam, true)
    RenderScriptCams(true, false, 0, true, false, 0)

    propRotation = GREEN_SCREEN_ROT.z
    propPitch = 0.0
    propRoll = 0.0
    isItemProp = true
    isScreenshotMode = true
    isDraggingProp = false

    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(true)
    SendNUI('screenshotStudioOpen', { itemName = screenshotItemName })

    ScreenshotLoop()
    return true
end)

--- Start single clothing screenshot
---@param componentId number Clothing component (1-11, 100+ for props)
---@param drawableId number Drawable index
---@param textureId number Texture index
---@param gender string 'male' or 'female'
---@param itemName string|nil Image name override
---@param cbEvent string|nil Client event to fire when done
exports('StartClothingScreenshot', function(componentId, drawableId, textureId, gender, itemName, cbEvent)
    if isScreenshotMode then return false end
    callbackEvent = cbEvent

    textureId = textureId or 0
    gender = gender or 'male'
    screenshotItemName = itemName or ('clothing_' .. componentId .. '_' .. drawableId .. '_' .. textureId)

    if not SetupScene(gender) then return false end

    ResetPedComponents()
    Wait(150)
    local isProp = componentId >= 100
    if isProp then
        LoadPropVariation(componentId - 100, drawableId, textureId)
    else
        LoadComponentVariation(componentId, drawableId, textureId)
    end
    Wait(500)

    SetupCamera(componentId)

    isScreenshotMode = true
    isDraggingProp = false

    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(true)
    SendNUI('screenshotStudioOpen', { itemName = screenshotItemName })

    ScreenshotLoop()
    return true
end)

--- Start batch clothing screenshot (all textures for 1 drawable)
---@param componentId number
---@param drawableId number
---@param gender string
---@param cbEvent string|nil Client event to fire when done
---@param returnToShop string|nil Shop ID to reopen after batch
exports('StartBatchClothingScreenshot', function(componentId, drawableId, gender, cbEvent, returnToShop)
    if isScreenshotMode then return false end
    callbackEvent = cbEvent
    gender = gender or 'male'

    screenshotItemName = ('clothing_%d_%d_0'):format(componentId, drawableId)

    if not SetupScene(gender) then return false end

    ResetPedComponents()
    Wait(150)
    local isProp = componentId >= 100
    local realCompId = isProp and (componentId - 100) or componentId
    if isProp then
        LoadPropVariation(realCompId, drawableId, 0)
    else
        LoadComponentVariation(realCompId, drawableId, 0)
    end
    Wait(500)

    local maxTextures = isProp
        and GetNumberOfPedPropTextureVariations(clothingPed, realCompId, drawableId)
        or GetNumberOfPedTextureVariations(clothingPed, realCompId, drawableId)
    if maxTextures < 1 then maxTextures = 1 end

    batchData = {
        componentId = componentId,
        drawableId = drawableId,
        gender = gender,
        maxTextures = maxTextures,
        returnToShop = returnToShop,
    }

    SetupCamera(componentId)
    isScreenshotMode = true
    isDraggingProp = false

    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(true)
    SendNUI('screenshotStudioOpen', { itemName = screenshotItemName, batch = true, totalTextures = maxTextures })

    ScreenshotLoop()
    return true
end)

--- Start full batch screenshot (all drawables + all textures for a component)
---@param componentId number
---@param gender string
---@param cbEvent string|nil Client event to fire when done
exports('StartFullBatchScreenshot', function(componentId, gender, cbEvent)
    if isScreenshotMode then return false end
    callbackEvent = cbEvent
    gender = gender or 'male'

    screenshotItemName = ('clothing_%d_0_0'):format(componentId)

    if not SetupScene(gender) then return false end

    ResetPedComponents()
    Wait(150)
    local isProp = componentId >= 100
    if isProp then
        LoadPropVariation(componentId - 100, 0, 0)
    else
        LoadComponentVariation(componentId, 0, 0)
    end
    Wait(500)

    local realCompId = isProp and (componentId - 100) or componentId
    local maxDrawables = isProp
        and GetNumberOfPedPropDrawableVariations(clothingPed, realCompId)
        or GetNumberOfPedDrawableVariations(clothingPed, realCompId)

    local totalScreenshots = 0
    for d = 0, maxDrawables - 1 do
        local maxTex = isProp
            and GetNumberOfPedPropTextureVariations(clothingPed, realCompId, d)
            or GetNumberOfPedTextureVariations(clothingPed, realCompId, d)
        if maxTex < 1 then maxTex = 1 end
        totalScreenshots = totalScreenshots + maxTex
    end

    batchData = {
        componentId = componentId,
        gender = gender,
        fullBatch = true,
        maxDrawables = maxDrawables,
        totalScreenshots = totalScreenshots,
    }

    SetupCamera(componentId)
    isScreenshotMode = true
    isDraggingProp = false

    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(true)
    SendNUI('screenshotStudioOpen', { itemName = screenshotItemName, batch = true, totalScreenshots = totalScreenshots })

    ScreenshotLoop()
    return true
end)

-- ============================================
-- Cleanup on resource stop
-- ============================================

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    CleanupPreview()
    CleanupLights()
    if savedCoords then
        local ped = cache.ped
        SetEntityCoordsNoOffset(ped, savedCoords.x, savedCoords.y, savedCoords.z, false, false, false)
        FreezeEntityPosition(ped, false)
        SetPlayerControl(PlayerId(), true)
    end
end)
