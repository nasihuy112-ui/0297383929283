local imgui    = require("mimgui")
local sampev   = require "samp.events"
local memory   = require("memory")
local SAMemory = require "SAMemory"
local json     = require("dkjson")
local ffi      = require("ffi")

SAMemory.require("CPed")
SAMemory.require("CPlayerData")
SAMemory.require("CCamera")

local gta = ffi.load("GTASA")
local cast = ffi.cast
local base = MONET_GTASA_BASE

ffi.cdef([[
    void _Z12AND_OpenLinkPKc(const char* link);
    typedef struct { float x, y, z; } Vec3;
    void _ZN4CPed15GetBonePositionER5RwV3djb(void* ped, void* out, int boneId, bool unknown);
]])

local function openLink(url) gta._Z12AND_OpenLinkPKc(url) end

local dpi = MONET_DPI_SCALE or 1
local MDS = dpi * 1.0
local camera = SAMemory.camera

local base_dir    = getWorkingDirectory() .. "/resource/crosshair/"
local single_dir  = base_dir .. "Uncropped image/"
local full_dir    = base_dir .. "siteM16/"
local config_path = getWorkingDirectory() .. "/config/crosshairchanger.json"

local textures, textureNames = {}, {}
local texture = nil
current_dir = single_dir

local window          = imgui.new.bool(false)
local selectedIndex   = imgui.new.int(0)
local recoilEnable    = imgui.new.bool(true)
local autoFix         = imgui.new.bool(false)
local disablePatch    = imgui.new.bool(false)
local showCrosshair   = imgui.new.bool(true)
local forceShow       = imgui.new.bool(false)
local redOnTarget     = imgui.new.bool(false)
local rgb_mode        = imgui.new.bool(false)
local mode_single     = imgui.new.bool(false)
local mode_full       = imgui.new.bool(false)
local siteM16         = imgui.new.bool(false)

local recoil_slider   = imgui.new.float(0.0)
local base_scale      = imgui.new.float(0.1)
local pos_x           = imgui.new.float(852.5)
local pos_y           = imgui.new.float(279.0)
local height_scale    = imgui.new.float[1](1.0)
local crosshair_color = imgui.new.float[4](1.0, 0.2, 0.8, 1.0)
local shadow_thickness = imgui.new.float[1](2.0)
local shadow_alpha    = imgui.new.float[1](0.6)
local rgb_speed       = imgui.new.float[1](3.0)
local rgb_intensity   = imgui.new.float[1](1.0)

local default_x, default_y = 852.5, 279.0

local shotCount, lastShotTime = 0, 0
local locked, attackLocked, notifyShown = false, false, false

local last_death_state = false
local death_grace_until = 0

local SNIPER_WEAPONS = { [33] = true, [34] = true }
local function isSniperWeapon(weapon) return SNIPER_WEAPONS[weapon] == true end

local function isPlayerDead()
    local ok, dead = pcall(function()
        return (not doesCharExist(PLAYER_PED)) or isCharDead(PLAYER_PED)
    end)
    if not ok then return false end
    return dead
end

local DATA = {
    raioFov = 16.0,
    daftarTulang = {
        0,1,2,3,4,5,6,7,8,
        21,22,23,24,25,26,
        31,32,33,34,35,36,
        41,42,43,44,
        51,52,53,54,
        201,301,302
    }
}

local vec3 = ffi.new("Vec3[1]")

local function getBonePos(ped, bone)
    local rawPtr = getCharPointer(ped)
    if not rawPtr or rawPtr == 0 then return nil end

    local ok, ptr = pcall(ffi.cast, "void*", rawPtr)
    if not ok or ptr == nil then return nil end

    local success = pcall(gta._ZN4CPed15GetBonePositionER5RwV3djb, ptr, vec3, bone, false)
    if not success then return nil end

    return vec3[0].x, vec3[0].y, vec3[0].z
end

local function isPlayerAiming()
    if not camera or not camera.aCams then return false end
    local cam = camera.aCams[0]
    if not cam then return false end
    local m = cam.nMode
    return m == 7 or m == 8 or m == 51 or m == 53
end

local isAiming = isPlayerAiming

local function isTargetInFov(mx, my, fov)
    if isPlayerDead() then return false end

    local ok, result = pcall(function()
        local px, py, pz = getCharCoordinates(PLAYER_PED)
        pz = pz + 0.7

        local bestDist = fov * fov

        for _, ped in ipairs(getAllChars()) do
            if ped ~= PLAYER_PED
            and doesCharExist(ped)
            and not isCharDead(ped)
            and isCharOnScreen(ped) then

                for _, bone in ipairs(DATA.daftarTulang) do
                    local x, y, z = getBonePos(ped, bone)

                    if x and y and z and isLineOfSightClear(px,py,pz,x,y,z,true,true,false,true,false) then
                        local sx, sy = convert3DCoordsToScreen(x, y, z)

                        if sx and sy then
                            local dx, dy = sx - mx, sy - my
                            if dx*dx + dy*dy < bestDist then return true end
                        end
                    end
                end
            end
        end

        return false
    end)

    if not ok then return false end
    return result
end

local rgb_hue = 0

local function rgbToHSV(h, s, v)
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p = v * (1 - s)
    local q = v * (1 - f * s)
    local t = v * (1 - (1 - f) * s)
    i = i % 6

    if i == 0 then return v, t, p
    elseif i == 1 then return q, v, p
    elseif i == 2 then return p, v, t
    elseif i == 3 then return p, q, v
    elseif i == 4 then return t, p, v
    else return v, p, q end
end

local function clampBright(r, g, b)
    local minB = 0.4
    r, g, b = math.max(r, minB), math.max(g, minB), math.max(b, minB)
    local maxV = math.max(r, g, b)
    if maxV > 1 then r, g, b = r / maxV, g / maxV, b / maxV end
    return r, g, b
end

local applySelectedTexture

local function loadTextures()
    textures, textureNames = {}, {}
    local dir = current_dir or single_dir
    if not dir then return end

    local p = io.popen('dir "'..dir..'" /b 2>nul || ls "'..dir..'" 2>/dev/null')
    if p then
        for file in p:lines() do
            if file:match("%.png$") then
                local full = dir .. file
                if doesFileExist(full) then
                    local tex = imgui.CreateTextureFromFile(full)
                    if tex then
                        table.insert(textures, tex)
                        table.insert(textureNames, file)
                    end
                end
            end
        end
        p:close()
    end

    if selectedIndex[0] > #textures - 1 then selectedIndex[0] = 0 end
    texture = textures[selectedIndex[0] + 1]
end

switchMode = function(isSingle)
    current_dir = isSingle and single_dir or full_dir
    loadTextures()
    applySelectedTexture()
end

applySelectedTexture = function()
    if textures and textures[selectedIndex[0] + 1] then
        texture = textures[selectedIndex[0] + 1]
    end
end

local function saveConfig()
    local data = {
        recoilEnable = recoilEnable[0],
        redOnTarget = redOnTarget[0],
        autoFix = autoFix[0],
        disablePatch = disablePatch[0],
        showCrosshair = showCrosshair[0],
        forceShow = forceShow[0],
        baseScale = base_scale[0],
        posX = pos_x[0],
        posY = pos_y[0],
        selectedIndex = selectedIndex[0],
        selectedTextureName = textureNames[selectedIndex[0] + 1] or "",
        siteM16 = siteM16[0],
        heightScale = height_scale[0],
        crosshairColor = {
            crosshair_color[0], crosshair_color[1],
            crosshair_color[2], crosshair_color[3]
        },
        shadowThickness = shadow_thickness[0],
        shadowAlpha = shadow_alpha[0],
        rgbMode = rgb_mode[0],
        rgbSpeed = rgb_speed[0],
        rgbIntensity = rgb_intensity[0],
    }

    local f = io.open(config_path, "w")
    if f then
        f:write(json.encode(data, { indent = true }))
        f:close()
        printStyledString("CONFIG SAVED", 2000, 6)
    end
end

local function loadConfig()
    if not doesFileExist(config_path) then return end
    local f = io.open(config_path, "r")
    if not f then return end

    local data = json.decode(f:read("*a"))
    f:close()
    if not data then return end

    recoilEnable[0]  = data.recoilEnable ~= false
    redOnTarget[0]   = data.redOnTarget ~= false
    autoFix[0]       = data.autoFix or false
    disablePatch[0]  = data.disablePatch or false
    showCrosshair[0] = data.showCrosshair ~= false
    forceShow[0]     = data.forceShow or false

    base_scale[0] = data.baseScale or 0.1
    pos_x[0] = data.posX or default_x
    pos_y[0] = data.posY or default_y

    selectedIndex[0] = data.selectedIndex or 0
    siteM16[0] = data.siteM16 or false
    height_scale[0] = data.heightScale or 1.0

    if data.crosshairColor then
        crosshair_color[0] = data.crosshairColor[1] or 1.0
        crosshair_color[1] = data.crosshairColor[2] or 0.2
        crosshair_color[2] = data.crosshairColor[3] or 0.8
        crosshair_color[3] = data.crosshairColor[4] or 1.0
    end

    shadow_thickness[0] = data.shadowThickness or 2.0
    shadow_alpha[0] = data.shadowAlpha or 0.6

    rgb_mode[0] = data.rgbMode or false
    rgb_speed[0] = data.rgbSpeed or 3.0
    rgb_intensity[0] = data.rgbIntensity or 1.0

    if siteM16[0] then
        mode_full[0], mode_single[0] = true, false
        switchMode(false)
    else
        mode_full[0], mode_single[0] = false, true
        switchMode(true)
    end

    if data.selectedTextureName and #textureNames > 0 then
        for i = 1, #textureNames do
            if textureNames[i] == data.selectedTextureName then
                selectedIndex[0] = i - 1
                break
            end
        end
    end

    if textures and #textures > 0 then
        selectedIndex[0] = math.max(0, math.min(selectedIndex[0], #textures - 1))
        applySelectedTexture()
    end
end

local function resetAutoFix()
    shotCount, lastShotTime = 0, 0
    locked, attackLocked, notifyShown = false, false, false
end

local function resetRecoil()
    shotCount = 0
end

local ds = base + 0x004371B0
local original, patched = {}, false

local function applyPatch()
    if patched or ds == 0 then return end
    for i = 0, 3 do original[i] = memory.getuint8(ds + i, true) or 0x00 end
    memory.setuint8(ds, 0x70, true)
    memory.setuint8(ds + 1, 0x47, true)
    memory.setuint8(ds + 2, 0x00, true)
    memory.setuint8(ds + 3, 0xBF, true)
    patched = true
end

local function restorePatch()
    if not patched then return end
    for i = 0, 3 do
        if original[i] then memory.setuint8(ds + i, original[i], true) end
    end
    patched = false
end

local function updateState()
    if disablePatch[0] then applyPatch() else restorePatch() end
end

local function applyAutoFix(data)
    if not autoFix[0] then return end
    if locked then return end
    if isPlayerDead() then return end
    if not data or not data.target then return end

    local now = os.clock()
    if now - lastShotTime < 0.12 then return end
    lastShotTime = now

    local sx, sy = convert3DCoordsToScreen(data.target.x, data.target.y, data.target.z)
    if not sx or not sy then return end

    shotCount = shotCount + 1
    printStyledString(shotCount .. "/2", 1000, 6)

    if shotCount >= 2 then
        pos_x[0], pos_y[0] = sx, sy
        printStyledString("2/2 done!", 1500, 6)
        locked, autoFix[0], attackLocked = true, false, false
        resetAutoFix()
    end
end

function sampev.onSendBulletSync(data)
    applyAutoFix(data)
end

-- per tick logic, runs every frame regardless of window visibility
imgui.OnFrame(function() return true end, function()
    updateState()

    local dead = isPlayerDead()

    if dead ~= last_death_state then
        last_death_state = dead
        if dead then
            death_grace_until = os.clock() + 1.0
        end
    end

    if dead then
        resetRecoil()
        attackLocked = false
        return
    end

    if os.clock() < death_grace_until then
        resetRecoil()
        attackLocked = false
        return
    end

    local aiming = false
    local aimOk = pcall(function() aiming = isAiming() end)
    if not aimOk then aiming = false end
    if not aiming then resetRecoil() end

    local rawPtr = getCharPointer(PLAYER_PED)
    if not rawPtr or rawPtr == 0 then
        attackLocked = false
        return
    end

    local ptrOk, p = pcall(ffi.cast, "CPed*", rawPtr)
    if not ptrOk or p == nil then
        attackLocked = false
        return
    end

    if p.pPlayerData == nil then
        attackLocked = false
        return
    end

    local d = p.pPlayerData

    if recoilEnable[0] then
        recoil_slider[0] = d.fAttackButtonCounter
    else
        d.fAttackButtonCounter = 0.0
        recoil_slider[0] = 0.0
    end

    if autoFix[0] then
        d.fAttackButtonCounter = 0.0
        attackLocked = true
    elseif attackLocked then
        d.fAttackButtonCounter = 1.0
        attackLocked = false
    end

    if not autoFix[0] then resetAutoFix() end
end)

imgui.OnFrame(function()
    local ok, result = pcall(function()
        if isPlayerDead() then return false end
        if os.clock() < death_grace_until then return false end

        local aiming = isAiming()
        local paused = isPauseMenuActive()
        local weapon = getCurrentCharWeapon(PLAYER_PED)
        local sniper = isSniperWeapon(weapon)

        return texture ~= nil
            and showCrosshair[0]
            and (aiming or forceShow[0])
            and not paused
            and not sniper
    end)
    if not ok then return false end
    return result
end, function()
    if isPlayerDead() then return end
    if os.clock() < death_grace_until then return end

    if rgb_mode[0] then
        rgb_hue = (rgb_hue + rgb_speed[0] * 0.003) % 1.0
    end

    local weaponOk, weapon = pcall(getCurrentCharWeapon, PLAYER_PED)
    if not weaponOk then return end

    local recoil = recoil_slider[0]
    local scale = base_scale[0]

    if recoilEnable[0] then
        if weapon == 31 then
            scale = base_scale[0] + (recoil * 0.02)
        else
            scale = base_scale[0] + (recoil * 0.04)
        end
    end

    local baseSize = 250
    if weapon == 25 then baseSize = 500
    elseif weapon == 33 then baseSize = 270
    elseif weapon == 26 then baseSize = 750 end

    local imgWidth = baseSize * scale
    local imgHeight = baseSize * scale * height_scale[0]
    local padding = 25 * MDS

    local x = pos_x[0] - (imgWidth / 2)
    local y = pos_y[0] - (imgHeight / 2)

    imgui.SetNextWindowPos(imgui.ImVec2(x - padding, y - padding), imgui.Cond.Always)
    imgui.SetNextWindowSize(imgui.ImVec2(imgWidth + padding * 2, imgHeight + padding * 2), imgui.Cond.Always)

    imgui.Begin("##crosshair", nil,
        imgui.WindowFlags.NoTitleBar +
        imgui.WindowFlags.NoResize +
        imgui.WindowFlags.NoMove +
        imgui.WindowFlags.NoBackground +
        imgui.WindowFlags.NoInputs
    )

    local shadow_col = imgui.ImVec4(0.1, 0.1, 0.1, shadow_alpha[0])
    local t = shadow_thickness[0]

    local offsets = {
        { t, 0 }, {-t, 0 }, { 0, t }, { 0, -t },
        { t, t }, { t, -t }, {-t, t }, {-t, -t },
        { t * 1.8, 0 }, {-t * 1.8, 0 }, { 0, t * 1.8 }, { 0, -t * 1.8 },
        { t * 1.4, t * 1.4 }, {-t * 1.4, t * 1.4 },
        { t * 1.4, -t * 1.4 }, {-t * 1.4, -t * 1.4 },
    }

    local halfW, halfH, gap = imgWidth / 2, imgHeight / 2, 0

    if mode_single[0] then
        for _, o in ipairs(offsets) do
            imgui.SetCursorPos(imgui.ImVec2(padding + o[1], padding + o[2]))
            imgui.Image(texture, imgui.ImVec2(imgWidth, imgHeight),
                imgui.ImVec2(0, 0), imgui.ImVec2(1, 1), shadow_col)
        end
    elseif mode_full[0] then
        for _, o in ipairs(offsets) do
            imgui.SetCursorPos(imgui.ImVec2(padding + o[1], padding + o[2]))
            imgui.Image(texture, imgui.ImVec2(halfW, halfH), imgui.ImVec2(0, 0), imgui.ImVec2(1, 1), shadow_col)

            imgui.SetCursorPos(imgui.ImVec2(padding + halfW + o[1], padding + o[2]))
            imgui.Image(texture, imgui.ImVec2(halfW, halfH), imgui.ImVec2(1, 0), imgui.ImVec2(0, 1), shadow_col)

            imgui.SetCursorPos(imgui.ImVec2(padding + o[1], padding + halfH + o[2]))
            imgui.Image(texture, imgui.ImVec2(halfW, halfH), imgui.ImVec2(0, 1), imgui.ImVec2(1, 0), shadow_col)

            imgui.SetCursorPos(imgui.ImVec2(padding + halfW + o[1], padding + halfH + o[2]))
            imgui.Image(texture, imgui.ImVec2(halfW, halfH), imgui.ImVec2(1, 1), imgui.ImVec2(0, 0), shadow_col)
        end
    end

    local centerX, centerY = x + imgWidth / 2, y + imgHeight / 2
    local isTarget = false
    if redOnTarget[0] and isPlayerAiming() then
        local ok, result = pcall(isTargetInFov, centerX, centerY, DATA.raioFov)
        if ok then isTarget = result end
    end

    local color
    if isTarget then
        color = imgui.ImVec4(1.0, 0.15, 0.15, 1.0)
    elseif rgb_mode[0] then
        local r, g, b = rgbToHSV(rgb_hue, 1.0, 1.0)
        r, g, b = clampBright(r, g, b)
        color = imgui.ImVec4(r * rgb_intensity[0], g * rgb_intensity[0], b * rgb_intensity[0], 1.0)
    else
        color = imgui.ImVec4(crosshair_color[0], crosshair_color[1], crosshair_color[2], 1.0)
    end

    if mode_single[0] then
        imgui.SetCursorPos(imgui.ImVec2(padding, padding))
        imgui.Image(texture, imgui.ImVec2(imgWidth, imgHeight), imgui.ImVec2(0, 0), imgui.ImVec2(1, 1), color)
    elseif mode_full[0] then
        imgui.SetCursorPos(imgui.ImVec2(padding - gap, padding - gap))
        imgui.Image(texture, imgui.ImVec2(halfW, halfH), imgui.ImVec2(0, 0), imgui.ImVec2(1, 1), color)

        imgui.SetCursorPos(imgui.ImVec2(padding + halfW + gap, padding - gap))
        imgui.Image(texture, imgui.ImVec2(halfW, halfH), imgui.ImVec2(1, 0), imgui.ImVec2(0, 1), color)

        imgui.SetCursorPos(imgui.ImVec2(padding - gap, padding + halfH + gap))
        imgui.Image(texture, imgui.ImVec2(halfW, halfH), imgui.ImVec2(0, 1), imgui.ImVec2(1, 0), color)

        imgui.SetCursorPos(imgui.ImVec2(padding + halfW + gap, padding + halfH + gap))
        imgui.Image(texture, imgui.ImVec2(halfW, halfH), imgui.ImVec2(1, 1), imgui.ImVec2(0, 0), color)
    end

    imgui.End()
end)

imgui.OnInitialize(function()
    local io = imgui.GetIO()
    io.IniFilename = nil

    loadConfig()

    if siteM16[0] then switchMode(false) else switchMode(true) end
    applySelectedTexture()
end)

imgui.OnFrame(function()
    return window[0]
end, function()
    imgui.SetNextWindowSize(imgui.ImVec2(0, 0), imgui.Cond.FirstUseEver)

    if imgui.Begin("Custom Crosshair", window, imgui.WindowFlags.AlwaysAutoResize) then
        imgui.BeginChild("##crosshair_child", imgui.ImVec2(90 * MDS, 265 * MDS), true)

        if #textureNames == 0 then
            imgui.TextDisabled("(empty)")
        else
            for i = 1, #textureNames do
                local name = textureNames[i]
                local sel = (selectedIndex[0] == i - 1)
                if imgui.Selectable(name, sel) then
                    selectedIndex[0] = i - 1
                    applySelectedTexture()
                end
            end
        end

        imgui.EndChild()
        imgui.SameLine()

        imgui.BeginChild("##settings_child", imgui.ImVec2(280 * MDS, 265 * MDS), true, imgui.WindowFlags.NoScrollWithMouse)

        imgui.Checkbox("Status", showCrosshair)
        imgui.Checkbox("Always Show Crosshair", forceShow)
        imgui.Checkbox("Recoil", recoilEnable)
        imgui.Checkbox("Red On Target", redOnTarget)

        if imgui.Checkbox("Fix Position With BulletSync", autoFix) then
            if autoFix[0] then printStyledString("Shoot to fix position!", 3000, 6) end
        end

        if imgui.Checkbox("siteM16", siteM16) then
            if siteM16[0] then
                mode_full[0], mode_single[0] = true, false
                switchMode(false)
            else
                mode_full[0], mode_single[0] = false, true
                switchMode(true)
            end
        end

        imgui.Checkbox("RGB Crosshair", rgb_mode)
        imgui.Checkbox("Hide Default Crosshair", disablePatch)

        imgui.ColorEdit4("Color", crosshair_color)
        imgui.Spacing()

        imgui.SetNextItemWidth(240 * MDS)
        imgui.SliderFloat("##shadow_alpha", shadow_alpha, 0.0, 1.0, "Shadow %.2f")

        imgui.SetNextItemWidth(240 * MDS)
        imgui.SliderFloat("##shadow_thickness", shadow_thickness, 0.1, 10.0, "Thickness %.2f")

        imgui.SetNextItemWidth(240 * MDS)
        imgui.SliderFloat("##BaseScalehi", height_scale, 0.1, 2.0, "H/W %.2f")

        imgui.SetNextItemWidth(240 * MDS)
        imgui.SliderFloat("##BaseScale", base_scale, 0.00, 0.5, "Scale %.2f")

        imgui.SetNextItemWidth(240 * MDS)
        imgui.SliderFloat("##PosX", pos_x, -1500, 1500, "PosX %.0f")

        imgui.SetNextItemWidth(240 * MDS)
        imgui.SliderFloat("##PosY", pos_y, -1500, 1500, "PosY %.0f")

        imgui.EndChild()

        if imgui.Button("Save") then saveConfig() end

        local url = "https://youtube.com/@deprauu"
        imgui.TextColored(imgui.ImVec4(1,1,1,1), url)
        if imgui.IsItemHovered() and imgui.IsMouseClicked(0) then openLink(url) end

        imgui.End()
    end
end)

function main()
    repeat wait(0) until isSampAvailable()
    sampRegisterChatCommand("ccs", function() window[0] = not window[0] end)
    wait(-1)
end
