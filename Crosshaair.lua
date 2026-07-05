script_author('Deprau')
local imgui   = require("mimgui")
local sampev  = require "samp.events"
local memory  = require("memory")
local SAMemory = require "SAMemory"
local json    = require("dkjson")
local faicons = require('fAwesome6')
SAMemory.require("CPed")
SAMemory.require("CPlayerData")
SAMemory.require("CCamera")
local ffi   = require("ffi")
local gta = ffi.load("GTASA")

ffi.cdef[[
    void _Z12AND_OpenLinkPKc(const char* link);
]]

function openLink(url) gta._Z12AND_OpenLinkPKc(url) end

local dpi = MONET_DPI_SCALE or 1
local MDS = dpi * 1.0
local player_ped = SAMemory.cast("CPed **", SAMemory.player_ped)
local camera = SAMemory.camera

local base_dir = getWorkingDirectory() .. "/resource/crosshair/"
local single_dir = base_dir .. "Uncropped image/"
local full_dir   = base_dir .. "siteM16/"
local config_path = getWorkingDirectory() .. "/config/crosshairchanger.json"

local textures, textureNames = {}, {}
local texture = nil

local window = imgui.new.bool(false)

local selectedIndex = imgui.new.int(0)
local recoilEnable = imgui.new.bool(true)
local autoFix = imgui.new.bool(false)
local disablePatch = imgui.new.bool(false)
local showCrosshair = imgui.new.bool(true)
local forceShow = imgui.new.bool(false)

local recoil_slider = imgui.new.float(0.0)
local base_scale = imgui.new.float(0.1)

local pos_x = imgui.new.float(852.5)
local pos_y = imgui.new.float(279.0)
current_dir = single_dir

local shotCount = 0
local lastShotTime = 0
local locked = false
local attackLocked = false
local notifyShown = false

local height_scale = imgui.new.float[1](1.0)
local crosshair_color = imgui.new.float[4](1.0, 0.2, 0.8, 1.0)
local shadow_thickness = imgui.new.float[1](2.0)
local shadow_alpha = imgui.new.float[1](0.6)

local rgb_mode = imgui.new.bool(false)
local rgb_speed = imgui.new.float[1](3.0)
local rgb_intensity = imgui.new.float[1](1.0)
local mode_single = imgui.new.bool(false)
local mode_full   = imgui.new.bool(false)
local siteM16 = imgui.new.bool(false)
local redOnTarget = imgui.new.bool(false)
local selectedTextureName = nil

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

        shotCount = shotCount,
        lastShotTime = lastShotTime,
        locked = locked,
        attackLocked = attackLocked,
        notifyShown = notifyShown,

        heightScale = height_scale[0],

        crosshairColor = {
            crosshair_color[0],
            crosshair_color[1],
            crosshair_color[2],
            crosshair_color[3]
        },

        shadowThickness = shadow_thickness[0],
        shadowAlpha = shadow_alpha[0],

        rgbMode = rgb_mode[0],
        rgbSpeed = rgb_speed[0],
        rgbIntensity = rgb_intensity[0],

        currentDir = (current_dir == single_dir) and "single" or "full"
    }

    local f = io.open(config_path, "w")
    if f then
        f:write(json.encode(data, { indent = true }))
        f:close()
        printStyledString("CONFIG SAVED", 2000, 6)
    end
end

local function applySelectedTexture()
    if textures and textures[selectedIndex[0] + 1] then
        texture = textures[selectedIndex[0] + 1]
    end
end

local function loadConfig()
    if not doesFileExist(config_path) then return end

    local f = io.open(config_path, "r")
    if not f then return end

    local data = json.decode(f:read("*a"))
    f:close()
    if not data then return end

    recoilEnable[0] = data.recoilEnable ~= false
    redOnTarget[0] = data.redOnTarget ~= false
    autoFix[0] = data.autoFix or false
    disablePatch[0] = data.disablePatch or false
    showCrosshair[0] = data.showCrosshair ~= false
    forceShow[0] = data.forceShow or false

    base_scale[0] = data.baseScale or 0.1
    pos_x[0] = data.posX or default_x
    pos_y[0] = data.posY or default_y

    selectedIndex[0] = data.selectedIndex or 0
    recoil_slider[0] = data.recoilSlider or 0.0

    siteM16[0] = data.siteM16 or false

    shotCount = data.shotCount or 0
    lastShotTime = data.lastShotTime or 0
    locked = data.locked or false
    attackLocked = data.attackLocked or false
    notifyShown = data.notifyShown or false

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

    -- MODE SWITCH
    if siteM16[0] then
        mode_full[0] = true
        mode_single[0] = false
        switchMode(false)
    else
        mode_full[0] = false
        mode_single[0] = true
        switchMode(true)
    end

    -- APPLY TEXTURE BY NAME (PRIORITY FIRST)
    if data.selectedTextureName and #textureNames > 0 then
        for i = 1, #textureNames do
            if textureNames[i] == data.selectedTextureName then
                selectedIndex[0] = i - 1
                break
            end
        end
    end

    -- SAFE APPLY (fallback index)
    if textures and #textures > 0 then
        selectedIndex[0] = math.min(selectedIndex[0], #textures - 1)
        if textures and #textures > 0 then
    selectedIndex[0] = math.min(selectedIndex[0], #textures - 1)
end
if selectedIndex[0] and textures[selectedIndex[0] + 1] then
    texture = textures[selectedIndex[0] + 1]
end
-- FIX: pastikan texture list sudah ada
if textures and #textures > 0 then
    if data.selectedTextureName then
        for i = 1, #textureNames do
            if textureNames[i] == data.selectedTextureName then
                selectedIndex[0] = i - 1
                break
            end
        end
    end

    selectedIndex[0] = math.max(0, math.min(selectedIndex[0], #textures - 1))
    applySelectedTexture()
end
-- APPLY TEXTURE AFTER LOAD (IMPORTANT FIX)
if data.selectedTextureName and #textureNames > 0 then
    for i = 1, #textureNames do
        if textureNames[i] == data.selectedTextureName then
            selectedIndex[0] = i - 1
            break
        end
    end
end

-- SAFETY CLAMP
if #textures > 0 then
    if selectedIndex[0] < 0 then selectedIndex[0] = 0 end
    if selectedIndex[0] > #textures - 1 then
        selectedIndex[0] = 0
    end

    texture = textures[selectedIndex[0] + 1]
end
    end
end

local default_x, default_y = 852.5, 279.0

local shotCount = 0
local lastShotTime = 0
local locked = false
local attackLocked = false
local notifyShown = false

local function resetAutoFix()
    shotCount = 0
    lastShotTime = 0
    locked = false
    attackLocked = false
    notifyShown = false
end

local ds = MONET_GTASA_BASE + 0x004371B0
local original, patched = {}, false

local function isAiming()
    if not camera or not camera.aCams then return false end
    local m = camera.aCams[0].nMode
    return m == 7 or m == 8 or m == 51 or m == 53
end


local function resetRecoil()
    shotCount, isLocked = 0, false
end

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

    if selectedIndex[0] > #textures - 1 then
    selectedIndex[0] = 0
end

texture = textures[selectedIndex[0] + 1]
end

local applySelectedTexture -- forward declaration

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

local function applyPatch()
    if patched or ds == 0 then return end
    for i = 0, 3 do
        original[i] = memory.getuint8(ds + i, true) or 0x00
    end
    memory.setuint8(ds, 0x70, true)
    memory.setuint8(ds + 1, 0x47, true)
    memory.setuint8(ds + 2, 0x00, true)
    memory.setuint8(ds + 3, 0xBF, true)
    patched = true
end

local function restorePatch()
    if not patched then return end
    for i = 0, 3 do
        if original[i] then
            memory.setuint8(ds + i, original[i], true)
        end
    end
    patched = false
end

local function updateState()
    if disablePatch[0] then applyPatch() else restorePatch() end
end

local function applyAutoFix(data)
    if not autoFix[0] then return end
    if locked then return end
    if not data or not data.target then return end

    local now = os.clock()
    if now - lastShotTime < 0.12 then return end
    lastShotTime = now

    local sx, sy = convert3DCoordsToScreen(
        data.target.x,
        data.target.y,
        data.target.z
    )

    if not sx or not sy then return end

    shotCount = shotCount + 1

    -- notif 0/2, 1/2, 2/2
    printStyledString(shotCount .. "/2", 1000, 6)

    if shotCount >= 2 then
        pos_x[0] = sx
        pos_y[0] = sy

        printStyledString("2/2 done!", 1500, 6)

        locked = true
        autoFix[0] = false
        attackLocked = false

        resetAutoFix()
    end
end

function sampev.onSendBulletSync(data)
    applyAutoFix(data)
end

local introStart = 0
local introActive = true

function main()
    repeat wait(0) until isSampAvailable()
introStart = os.clock()
    introActive = true
    window[0] = true
    sampRegisterChatCommand("ccs", function()

    window[0] = not window[0]
end)

    

    while true do
        wait(0)

        if introActive then
            if os.clock() - introStart >= 0.0 then
                window[0] = false
                introActive = false
            else
                window[0] = true
            end
        end
    updateState()
    
    local aiming = isAiming()
    if not aiming then resetRecoil() end

    local p = player_ped and player_ped[0]
    if p and p.pPlayerData then
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
        else
            if attackLocked then
                d.fAttackButtonCounter = 1.0
                attackLocked = false
            end
        end
    end

    if not autoFix[0] then
        resetAutoFix()
    end
end
end

DATA = {
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

ffi.cdef[[
typedef struct { float x, y, z; } Vec3;
void _ZN4CPed15GetBonePositionER5RwV3djb(void* ped, void* out, int boneId, bool unknown);
]]

local vec3 = ffi.new("Vec3[1]")

local function getBonePos(ped, bone)
    local ptr = ffi.cast("void*", getCharPointer(ped))
    gta._ZN4CPed15GetBonePositionER5RwV3djb(ptr, vec3, bone, false)
    return vec3[0].x, vec3[0].y, vec3[0].z
end

local function isPlayerAiming()
    local camMode = camera.aCams[0].nMode
    return camMode == 7 or camMode == 8 or camMode == 51 or camMode == 53
end

local function isTargetInFov(mx, my, fov)
    local px, py, pz = getCharCoordinates(PLAYER_PED)
    pz = pz + 0.7

    local bestDist = fov * fov

    for _, ped in ipairs(getAllChars()) do
        if ped ~= PLAYER_PED
        and doesCharExist(ped)
        and not isCharDead(ped)
        and isCharOnScreen(ped) then

            for _, bone in ipairs(DATA.daftarTulang) do
                local x,y,z = getBonePos(ped, bone)

                if isLineOfSightClear(px,py,pz,x,y,z,true,true,false,true,false) then
                    local sx,sy = convert3DCoordsToScreen(x,y,z)

                    if sx and sy then
                        local dx = sx - mx
                        local dy = sy - my
                        local dist = dx*dx + dy*dy

                        if dist < bestDist then
                            return true
                        end
                    end
                end
            end

        end
    end

    return false
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

    r = math.max(r, minB)
    g = math.max(g, minB)
    b = math.max(b, minB)

    local maxV = math.max(r, g, b)
    if maxV > 1 then
        r = r / maxV
        g = g / maxV
        b = b / maxV
    end

    return r, g, b
end

imgui.OnFrame(function()
    local aiming = isAiming()
    local paused = isPauseMenuActive()
    local notSpawned = not doesCharExist(PLAYER_PED) or isCharDead(PLAYER_PED)

    return texture ~= nil
        and showCrosshair[0]
        and (aiming or forceShow[0])
        and not paused
        and not notSpawned
end, function()

    if rgb_mode[0] then
        rgb_hue = (rgb_hue + rgb_speed[0] * 0.003) % 1.0
    end

    local recoil = recoil_slider[0]
    local weapon = getCurrentCharWeapon(PLAYER_PED)
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
        { t, 0 }, {-t, 0 },
        { 0, t }, { 0, -t },
        { t, t }, { t, -t },
        {-t, t }, {-t, -t },
        { t * 1.8, 0 }, {-t * 1.8, 0 },
        { 0, t * 1.8 }, { 0, -t * 1.8 },
        { t * 1.4, t * 1.4 }, {-t * 1.4, t * 1.4 },
        { t * 1.4, -t * 1.4 }, {-t * 1.4, -t * 1.4 },
    }

    local halfW = imgWidth / 2
    local halfH = imgHeight / 2
    local gap = 0

    -- SHADOW
    if mode_single[0] then
        for _, o in ipairs(offsets) do
            imgui.SetCursorPos(imgui.ImVec2(padding + o[1], padding + o[2]))
            imgui.Image(texture, imgui.ImVec2(imgWidth, imgHeight),
                imgui.ImVec2(0, 0), imgui.ImVec2(1, 1), shadow_col)
        end
    elseif mode_full[0] then
        for _, o in ipairs(offsets) do
            -- kiri atas
            imgui.SetCursorPos(imgui.ImVec2(padding + o[1], padding + o[2]))
            imgui.Image(texture, imgui.ImVec2(halfW, halfH),
                imgui.ImVec2(0, 0), imgui.ImVec2(1, 1), shadow_col)

            -- kanan atas
            imgui.SetCursorPos(imgui.ImVec2(padding + halfW + o[1], padding + o[2]))
            imgui.Image(texture, imgui.ImVec2(halfW, halfH),
                imgui.ImVec2(1, 0), imgui.ImVec2(0, 1), shadow_col)

            -- kiri bawah
            imgui.SetCursorPos(imgui.ImVec2(padding + o[1], padding + halfH + o[2]))
            imgui.Image(texture, imgui.ImVec2(halfW, halfH),
                imgui.ImVec2(0, 1), imgui.ImVec2(1, 0), shadow_col)

            -- kanan bawah
            imgui.SetCursorPos(imgui.ImVec2(padding + halfW + o[1], padding + halfH + o[2]))
            imgui.Image(texture, imgui.ImVec2(halfW, halfH),
                imgui.ImVec2(1, 1), imgui.ImVec2(0, 0), shadow_col)
        end
    end

    local centerX = x + imgWidth / 2
    local centerY = y + imgHeight / 2

    local isTarget = false
    if redOnTarget[0] and isPlayerAiming() then
        isTarget = isTargetInFov(centerX, centerY, DATA.raioFov)
    end

    local color

    if isTarget then
        color = imgui.ImVec4(1.0, 0.15, 0.15, 1.0)
    else
        if rgb_mode[0] then
            local r, g, b = rgbToHSV(rgb_hue, 1.0, 1.0)
            r, g, b = clampBright(r, g, b)

            color = imgui.ImVec4(
                r * rgb_intensity[0],
                g * rgb_intensity[0],
                b * rgb_intensity[0],
                1.0
            )
        else
            color = imgui.ImVec4(
                crosshair_color[0],
                crosshair_color[1],
                crosshair_color[2],
                1.0
            )
        end
    end

    -- RENDER
    if mode_single[0] then
        imgui.SetCursorPos(imgui.ImVec2(padding, padding))
        imgui.Image(texture, imgui.ImVec2(imgWidth, imgHeight),
            imgui.ImVec2(0, 0), imgui.ImVec2(1, 1), color)

    elseif mode_full[0] then
        -- kiri atas
        imgui.SetCursorPos(imgui.ImVec2(padding - gap, padding - gap))
        imgui.Image(texture, imgui.ImVec2(halfW, halfH),
            imgui.ImVec2(0, 0), imgui.ImVec2(1, 1), color)

        -- kanan atas
        imgui.SetCursorPos(imgui.ImVec2(padding + halfW + gap, padding - gap))
        imgui.Image(texture, imgui.ImVec2(halfW, halfH),
            imgui.ImVec2(1, 0), imgui.ImVec2(0, 1), color)

        -- kiri bawah
        imgui.SetCursorPos(imgui.ImVec2(padding - gap, padding + halfH + gap))
        imgui.Image(texture, imgui.ImVec2(halfW, halfH),
            imgui.ImVec2(0, 1), imgui.ImVec2(1, 0), color)

        -- kanan bawah
        imgui.SetCursorPos(imgui.ImVec2(padding + halfW + gap, padding + halfH + gap))
        imgui.Image(texture, imgui.ImVec2(halfW, halfH),
            imgui.ImVec2(1, 1), imgui.ImVec2(0, 0), color)
    end

    imgui.End()
end)
function darkgreentheme()
    imgui.SwitchContext()
    local style = imgui.GetStyle()
    local colors = style.Colors
    local ImVec2 = imgui.ImVec2

    style.WindowRounding = 18.0
    style.ItemSpacing = ImVec2(12, 8)
    style.ItemInnerSpacing = ImVec2(8, 6)
    style.IndentSpacing = 25.0
    style.ScrollbarSize = 30.0
    style.ScrollbarRounding = 10.0
    style.GrabMinSize = 20.0
    style.GrabRounding = 20.0
    style.ChildRounding = 12.0
    style.FrameRounding = 10.0
    style.WindowTitleAlign = ImVec2(0.5, 0.5)
end

local dpi = MONET_DPI_SCALE or 1
local MDS = dpi * 1.0

local http = require("socket.http")
local ltn12 = require("ltn12")

local FONT_URL  = "https://github.com/konkeymong123-crypto/Pngjpg/raw/refs/heads/main/baflion-sans.black.otf"
local FONT_PATH = getWorkingDirectory() .. "/lib/deprau/baflion-sans.black.otf"

local function downloadFont()
    if doesFileExist(FONT_PATH) then return end

    local dir = FONT_PATH:match("(.+)/[^/]+$")
    if dir and not doesDirectoryExist(dir) then
        createDirectory(dir)
    end

    local file = io.open(FONT_PATH, "wb")
    if not file then return end

    http.request{
        url = FONT_URL,
        sink = ltn12.sink.file(file)
    }
end

downloadFont()

local fontTitle, fontTitleSmall, fontAwesome = nil, nil, nil

imgui.OnInitialize(function()
    local io = imgui.GetIO()
    io.IniFilename = nil

    local config = imgui.ImFontConfig()
    config.MergeMode = true
    config.PixelSnapH = true

    if doesFileExist(FONT_PATH) then
        fontTitle      = io.Fonts:AddFontFromFileTTF(FONT_PATH, 18 * dpi)
        fontTitleSmall = io.Fonts:AddFontFromFileTTF(FONT_PATH, 11 * dpi)
    end

    local iconRanges = imgui.new.ImWchar[3](faicons.min_range, faicons.max_range, 0)
    fontAwesome = io.Fonts:AddFontFromMemoryCompressedBase85TTF(
        faicons.get_font_data_base85('solid'),
        20,
        config,
        iconRanges
    )

    io.Fonts:Build()
    io.FontGlobalScale = MDS

    darkgreentheme()
    loadConfig()

    if siteM16[0] then
        switchMode(false)
    else
        switchMode(true)
    end

    applySelectedTexture()
end)

function imgui.BeginCustomTitle(title, titleSizeY, var, flags)
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, imgui.ImVec2(5,5))
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize, 0)

    local opened = imgui.Begin(title, var, imgui.WindowFlags.NoTitleBar + (flags or 0))
    if opened then
        local style = imgui.GetStyle()
        local p = imgui.GetWindowPos()
        local size = imgui.GetWindowSize()
        local dl = imgui.GetWindowDrawList()

        dl:AddRectFilled(p, imgui.ImVec2(p.x + size.x, p.y + titleSizeY),
            imgui.GetColorU32Vec4(style.Colors[imgui.Col.TitleBgActive]), style.WindowRounding, 3)

        local titleOffsetY = 2

        if fontTitle then imgui.PushFont(fontTitle) end
        local textSize = imgui.CalcTextSize(title)

        local textPos = imgui.ImVec2(
            p.x + 9,
            p.y + titleSizeY/2 - textSize.y/2 + titleOffsetY
        )

        local strokeColor = imgui.ImVec4(0,0,0,1)
        local mainColor = imgui.ImVec4(1,1,1,1)

        local offsets = {
            imgui.ImVec2(-1,-1),
            imgui.ImVec2(-1,1),
            imgui.ImVec2(1,-1),
            imgui.ImVec2(1,1)
        }

        for _, offset in ipairs(offsets) do
            dl:AddText(
                imgui.ImVec2(textPos.x + offset.x, textPos.y + offset.y),
                imgui.GetColorU32Vec4(strokeColor),
                title
            )
        end
        dl:AddText(textPos, imgui.GetColorU32Vec4(mainColor), title)
        if fontTitle then imgui.PopFont() end

        local radius = titleSizeY * 0.38
        local padding = 6
        local yOffset = 2

        local closeCenter = imgui.ImVec2(
            p.x + size.x - radius - padding,
            p.y + titleSizeY / 2 - yOffset
        )

        local closeHovered = imgui.IsMouseHoveringRect(
            imgui.ImVec2(closeCenter.x - radius, closeCenter.y - radius),
            imgui.ImVec2(closeCenter.x + radius, closeCenter.y + radius)
        )

        if closeHovered and imgui.IsMouseClicked(0) then window[0] = false end
        
        dl:AddCircleFilled(
            closeCenter,
            radius,
            imgui.GetColorU32Vec4(
                closeHovered and imgui.ImVec4(1,1,1,1) or imgui.ImVec4(0.9,0.9,0.9,1)
            ),
            32
        )

        -- outline hitam tipis
        dl:AddCircle(
            closeCenter,
            radius,
            imgui.GetColorU32Vec4(imgui.ImVec4(0,0,0,1)),
            32,
            2
        )

        local saveOffset = imgui.ImVec2(-radius*2 - padding, 0)
        local saveCenter = imgui.ImVec2(closeCenter.x + saveOffset.x, closeCenter.y + saveOffset.y)

        local saveHovered = imgui.IsMouseHoveringRect(
            imgui.ImVec2(saveCenter.x - radius, saveCenter.y - radius),
            imgui.ImVec2(saveCenter.x + radius, saveCenter.y + radius)
        )

        if saveHovered and imgui.IsMouseClicked(0) then saveConfig() end

        if fontAwesome then imgui.PushFont(fontAwesome) end
        local iconText = faicons('FLOPPY_DISK')
        local iconSize = imgui.CalcTextSize(iconText)

        local iconPos = imgui.ImVec2(
            saveCenter.x - iconSize.x/2,
            saveCenter.y - iconSize.y/2 + 5
        )

        local iconStrokeOffsets = {
            imgui.ImVec2(-1,-1),
            imgui.ImVec2(-1,1),
            imgui.ImVec2(1,-1),
            imgui.ImVec2(1,1)
        }

        for _, offset in ipairs(iconStrokeOffsets) do
            dl:AddText(
                imgui.ImVec2(iconPos.x + offset.x, iconPos.y + offset.y),
                imgui.GetColorU32Vec4(imgui.ImVec4(0,0,0,1)),
                iconText
            )
        end
        dl:AddText(iconPos, imgui.GetColorU32Vec4(imgui.ImVec4(1,1,1,1)), iconText)
        if fontAwesome then imgui.PopFont() end
        imgui.SetCursorPosY(titleSizeY + 5)
    end
    return opened
end


imgui.OnFrame(function()
    return window[0]
end, function()

    local childW = 90 * MDS
    local childH = 265 * MDS


    local winW = childW + 306 * MDS
    local winH = childH  + 60 * MDS
    imgui.SetNextWindowSize(imgui.ImVec2(winW, winH), imgui.Cond.Always)
    if imgui.BeginCustomTitle(
        "Custom Crosshair",
        28 * MDS,
        window,
        imgui.WindowFlags.NoCollapse +
        imgui.WindowFlags.NoResize +
        imgui.WindowFlags.NoScrollbar
    ) then
        imgui.BeginChild("##crosshair_child", imgui.ImVec2(childW, childH), true)

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

        imgui.BeginChild(
    "##settings_child",
    imgui.ImVec2(0, childH),
    true,
    imgui.WindowFlags.NoScrollWithMouse
)

imgui.Checkbox("Status", showCrosshair)
imgui.Checkbox("Always Show Crosshair", forceShow)
imgui.Checkbox("Recoil", recoilEnable)
imgui.Checkbox("Red On Target", redOnTarget)

if imgui.Checkbox("Fix Position With BulletSync", autoFix) then
    if autoFix[0] then
        printStyledString("Shoot to fix position!", 3000, 6)
    end
end

if imgui.Checkbox("siteM16", siteM16) then
    if siteM16[0] then
        mode_full[0] = true
        mode_single[0] = false
        switchMode(false)
    else
        mode_full[0] = false
        mode_single[0] = true
        switchMode(true)
    end
end

imgui.Checkbox("RGB Crosshair", rgb_mode)
imgui.Checkbox("Hide Default Crosshair", disablePatch)
        local function row(label, ref)
    imgui.ColorEdit4("##" .. label, ref, imgui.ColorEditFlags.NoInputs)
    imgui.SameLine()

    local y = imgui.GetCursorPosY()
    imgui.SetCursorPosY(y + 5)

    if fontTitleSmall then imgui.PushFont(fontTitleSmall) end
    imgui.Text(label)
    if fontTitleSmall then imgui.PopFont() end
end

row("Crosshair Color", crosshair_color)
imgui.Spacing()

imgui.SetNextItemWidth(330)
imgui.SliderFloat("##shadow_alpha", shadow_alpha, 0.0, 1.0, "Shadow %.2f")

imgui.SetNextItemWidth(330)
imgui.SliderFloat("##shadow_thickness", shadow_thickness, 0.1, 10.0, "Thickness %.2f")

imgui.SetNextItemWidth(330)
imgui.SliderFloat("##BaseScalehi", height_scale, 0.1, 2.0, "H/W %.2f")

imgui.SetNextItemWidth(330)
imgui.SliderFloat("##BaseScale", base_scale, 0.00, 0.5, "Scale %.2f")

imgui.SetNextItemWidth(330)
imgui.SliderFloat("##PosX", pos_x, -1500, 1500, "PosX %.0f")

imgui.SetNextItemWidth(330)
imgui.SliderFloat("##PosY", pos_y, -1500, 1500, "PosY %.0f")
        imgui.EndChild()
        local url = "https://youtube.com/@deprauu"

local windowWidth = imgui.GetWindowSize().x
local textWidth = imgui.CalcTextSize(url).x
local offsetX = 5

imgui.SetCursorPosX((windowWidth - textWidth) / 2 + offsetX)

imgui.SetWindowFontScale(1.0)
imgui.TextColored(imgui.ImVec4(1,1,1,1), url)

if imgui.IsItemHovered() and imgui.IsMouseClicked(0) then
    os.execute('start ' .. url)
end

imgui.SetWindowFontScale(1.0)

            if imgui.IsItemClicked() then
                openLink(url)
            end
        imgui.End()
    end
end)

local originalCheckbox = imgui.Checkbox

function imgui.Checkbox(str_id, bool)
    local style = imgui.GetStyle()
    local oldSpacingY = style.ItemSpacing.y

    style.ItemSpacing.y = 3

    local label = str_id
    local result = originalCheckbox("##"..label, bool)
    imgui.SameLine()

    local y = imgui.GetCursorPosY()
    imgui.SetCursorPosY(y + 5)

    if fontTitleSmall then imgui.PushFont(fontTitleSmall) end
    imgui.Text(label)
    if fontTitleSmall then imgui.PopFont() end

    style.ItemSpacing.y = oldSpacingY

    return result
end

