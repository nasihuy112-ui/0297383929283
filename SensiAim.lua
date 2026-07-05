script_author("Deprau")

require("widgets")

_G.ImFontGlyphRangesBuilder = function()
    return {
        AddText = function() end,
        BuildRanges = function() return {} end
    }
end

local imgui = require "mimgui"
local ffi = require("ffi")
local SAMemory = require "SAMemory"
local gta = ffi.load("GTASA")
SAMemory.require("CCamera")
local inicfg = require "inicfg"
local camera = SAMemory.camera
local imgui = require 'mimgui'
local new = imgui.new
local sampev = require 'lib.samp.events'
local faicons = require('fAwesome6')

local cfg_name = "SensitivityAimMobile"
local cfg = inicfg.load({
    main = {
        enable = true,
        sens = 9.0,
        smooth_speed = 12.0
    }
}, cfg_name)
inicfg.save(cfg, cfg_name)

ffi.cdef [[
typedef struct RwV3d{float x,y,z;}RwV3d;
void _ZN4CPed15GetBonePositionER5RwV3djb(void* thiz,RwV3d* posn,uint32_t bone,bool calledFromCam);
]]

local socket = require 'socket.http'
local ltn12  = require 'ltn12'
local lfs    = require 'lfs'

local BASE_DIR = getWorkingDirectory() .. '/lib/deprau'
local FONT_DIR = BASE_DIR .. '/font'

local FONT_URLS = {
    {
        url  = 'https://st.1001fonts.net/download/font/poppis.demo.otf',
        path = FONT_DIR .. '/poppis.demo.otf',
        size = 26
    },
    {
        url  = 'https://st.1001fonts.net/download/font/baflion-sans.black.otf',
        path = FONT_DIR .. '/baflion-sans.black.otf',
        size = 26
    }
}

local fontPoppis  = nil
local fontFreshid = nil

local function mkdirs(path)
    local cur = ""
    for part in path:gmatch("[^/]+") do
        cur = cur .. "/" .. part
        if not lfs.attributes(cur) then
            pcall(lfs.mkdir, cur)
        end
    end
end

local function safeDownload(url, path)
    if doesFileExist(path) then return true end
    mkdirs(path:match("(.+)/[^/]+$"))

    local f = io.open(path, "wb")
    if not f then return false end

    local _, code = socket.request{
        url  = url,
        sink = ltn12.sink.file(f),
        headers = {
            ["User-Agent"] = "Mozilla/5.0"
        }
    }

    return code == 200
end

local function safeAddFont(io, path, size, config, ranges)
    if not doesFileExist(path) then return nil end
    local ok, font = pcall(function()
        return io.Fonts:AddFontFromFileTTF(path, size, config, ranges)
    end)
    return ok and font or nil
end

imgui.OnInitialize(function()
    local io = imgui.GetIO()
    io.IniFilename = nil

    mkdirs(getWorkingDirectory() .. '/lib')
    mkdirs(BASE_DIR)
    mkdirs(FONT_DIR)

    for _, f in ipairs(FONT_URLS) do
        pcall(safeDownload, f.url, f.path)
    end

    local fonts = io.Fonts
    local glyph = fonts:GetGlyphRangesDefault()

    fontPoppis  = safeAddFont(io, FONT_URLS[1].path, FONT_URLS[1].size, nil, glyph)
    fontFreshid = safeAddFont(io, FONT_URLS[2].path, FONT_URLS[2].size, nil, glyph)

    if fontPoppis then
        local fa_cfg = imgui.ImFontConfig()
        fa_cfg.MergeMode = true
        fa_cfg.PixelSnapH = true

        local iconRanges = new.ImWchar[3](
            faicons.min_range,
            faicons.max_range,
            0
        )

        fonts:AddFontFromMemoryCompressedBase85TTF(
            faicons.get_font_data_base85('solid'),
            FONT_URLS[1].size,
            fa_cfg,
            iconRanges
        )
    end

    fonts:Build()
end)


local pcCamEnabled = true

local targetPhi, targetTheta = 0.0, 0.0
local currentPhi, currentTheta = 0.0, 0.0
local velocityPhi, velocityTheta = 0.0, 0.0

local pcCamCheckbox = imgui.new.bool(cfg.main.enable)
local sensValue = imgui.new.float(cfg.main.sens)
local smoothSpeedValue = imgui.new.float(cfg.main.smooth_speed)

local sensitivity = sensValue[0] / 10000.0
local smoothSpeed = smoothSpeedValue[0]

local smoothSpeed = 12.0
local velocityDecay = 0.28
local maxTheta = math.rad(89)
local initialized = false
local lastTick = os.clock()

local ui_meta = {
    __index = function(self, v)
        if v == "switch" then
            return function()
                if self.process and self.process:status() ~= "dead" then return false end
                self.timer = os.clock()
                self.state = not self.state
                self.process = lua_thread.create(function()
                    while true do wait(0)
                        local t = math.min((os.clock() - self.timer) / self.duration, 1.0)
                        self.alpha = self.state and t or 1.0 - t
                        if t >= 1.0 then break end
                    end
                end)
                return true
            end
        end
        if v == "alpha" then
            return self.state and 1.0 or 0.0
        end
    end
}

local menu = { state = false, duration = 0.3 }
setmetatable(menu, ui_meta)

local function clampTheta(theta)
    if theta > maxTheta then return maxTheta end
    if theta < -maxTheta then return -maxTheta end
    return theta
end

local function smoothDamp(current, target, speed, dt)
    if dt <= 0 or dt > 0.1 then dt = 0.016 end
    return current + (target - current) * (1 - math.exp(-speed * dt))
end

local function getDT()
    local now = os.clock()
    local dt = now - lastTick
    lastTick = now
    if dt <= 0 or dt > 0.1 then dt = 0.016 end
    return dt
end

local function getCameraAngles()
    return camera.aCams[0].fHorizontalAngle, camera.aCams[0].fVerticalAngle
end

local function setCameraAngles(phi, theta)
    camera.aCams[0].fHorizontalAngle = phi
    camera.aCams[0].fVerticalAngle = theta
end

local function updateCameraSensitivity()
    if not pcCamEnabled then initialized=false return end
    if not doesCharExist(PLAYER_PED) then initialized=false return end
    if isCharInAnyCar(PLAYER_PED) then initialized=false return end
    local weapon = getCurrentCharWeapon(PLAYER_PED)
    if weapon==0 then initialized=false return end
    local camMode = camera.aCams[0].nMode
    local aiming = camMode==7 or camMode==8 or camMode==51 or camMode==53
    if not aiming then initialized=false velocityPhi=0 velocityTheta=0 return end

    local pressed, x, y = isWidgetPressedEx(0xAF,0)
    x = tonumber(x) or 0
    y = tonumber(y) or 0
    if pressed and (x~=0 or y~=0) then
        if not initialized then
            currentPhi, currentTheta = getCameraAngles()
            targetPhi, targetTheta = currentPhi, currentTheta
            initialized=true
        end
        velocityPhi = velocityPhi - x*sensitivity
        velocityTheta = velocityTheta - y*sensitivity
    end

    if initialized and isCharOnFoot(PLAYER_PED) then
        targetPhi   = targetPhi + velocityPhi
        targetTheta = clampTheta(targetTheta + velocityTheta)
        velocityPhi = velocityPhi * velocityDecay
        velocityTheta = velocityTheta * velocityDecay
        local dt = getDT()
        currentPhi   = smoothDamp(currentPhi, targetPhi, smoothSpeed, dt)
        currentTheta = smoothDamp(currentTheta, targetTheta, smoothSpeed, dt)
        setCameraAngles(currentPhi, currentTheta)
    end
end

function main()
    while not isSampAvailable() do wait(0) end
    sampRegisterChatCommand("sens", function()
        pcCamEnabled = not pcCamEnabled
        pcCamCheckbox[0] = pcCamEnabled
        initialized=false
    end)

    sampRegisterChatCommand("sensm", menu.switch)

    while true do
        wait(0)
        pcCamEnabled = pcCamCheckbox[0]
        updateCameraSensitivity()
    end
end
if not menu.windowPos then
    local sw, sh = getScreenResolution()
    menu.windowPos = imgui.ImVec2(sw / 2, sh / 2)
end

imgui.OnFrame(
    function() return menu.alpha > 0 end,
    function()
        darkgreentheme()

        imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, menu.alpha)

        imgui.SetNextWindowPos(
            menu.windowPos,
            imgui.Cond.FirstUseEver,
            imgui.ImVec2(0.5, 0.5)
        )

        local style = imgui.GetStyle()
        style.Colors[imgui.Col.Border]   = imgui.ImVec4(0, 0, 0, 1)
        style.WindowBorderSize = 2.0

        imgui.Begin(
            "Menu",
            nil,
            imgui.WindowFlags.AlwaysAutoResize + imgui.WindowFlags.NoTitleBar
        )

if fontFreshid then imgui.PushFont(fontFreshid) end
imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.00, 0.00, 0.00, 1.00))
imgui.Text("Aim Sensibility")
imgui.PopStyleColor()

if fontFreshid then imgui.PopFont() end

local btnYOffset = -12

imgui.SameLine(270)
imgui.SetCursorPosY(imgui.GetCursorPosY() - 12)

if fontFreshid then imgui.PushFont(fontFreshid) end

imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.0, 0.0, 0.0, 1.0))

if imgui.Button(faicons.ANGLES_DOWN, imgui.ImVec2(28, 30)) then
    cfg.main.enable = pcCamCheckbox[0]
    cfg.main.sens = sensValue[0]
    cfg.main.smooth_speed = smoothSpeedValue[0]
    inicfg.save(cfg, cfg_name)

    if isSampAvailable() then
        sampAddChatMessage(
            "{00FF00}@Deprau>>{FFFFFF} Setting berhasil disimpan!",
            -1
        )
    end
end

imgui.PopStyleColor()

if fontFreshid then imgui.PopFont() end

imgui.Spacing()        

if fontPoppis then imgui.PushFont(fontPoppis) end

imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.0, 0.0, 0.0, 1.0))

imgui.PushStyleColor(imgui.Col.FrameBg, imgui.ImVec4(0.90, 0.80, 0.10, 1.0))
imgui.PushStyleColor(imgui.Col.FrameBgHovered, imgui.ImVec4(0.95, 0.85, 0.15, 1.0))
imgui.PushStyleColor(imgui.Col.FrameBgActive, imgui.ImVec4(0.85, 0.75, 0.10, 1.0))

imgui.PushStyleColor(imgui.Col.SliderGrab, imgui.ImVec4(0.0, 0.0, 0.0, 1.0))
imgui.PushStyleColor(imgui.Col.SliderGrabActive, imgui.ImVec4(0.0, 0.0, 0.0, 1.0))

imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(0.0, 0.0, 0.0, 1.0))
imgui.PushStyleVarFloat(imgui.StyleVar.FrameBorderSize, 1.0)

imgui.PushItemWidth(310)
if imgui.SliderFloat(
    "##Sensi",
    sensValue,
    1.0,
    50.0,
    "Sensitivity %.1f"
) then
    sensitivity = sensValue[0] / 10000.0
end
imgui.PopItemWidth()

imgui.PushItemWidth(310)
if imgui.SliderFloat(
    "##Smooth",
    smoothSpeedValue,
    10.0,
    200.0,
    "Smooth %.1f"
) then
    smoothSpeed = smoothSpeedValue[0]
end
imgui.PopItemWidth()

imgui.PopStyleVar()
imgui.PopStyleColor(6)

if fontPoppis then imgui.PopFont() end
        local dl = imgui.GetWindowDrawList()
        local wp = imgui.GetWindowPos()
        local ws = imgui.GetWindowSize()

        local radius   = 14
        local paddingX = 8
        local paddingY = 6

        local center = imgui.ImVec2(
            wp.x + ws.x - radius - paddingX,
            wp.y + radius + paddingY
        )

        local hovered = imgui.IsMouseHoveringRect(
            imgui.ImVec2(center.x - radius, center.y - radius),
            imgui.ImVec2(center.x + radius, center.y + radius)
        )

   local col = hovered
            and imgui.ImVec4(0, 0, 0, 1.0)
            or  imgui.ImVec4(0, 0, 0, 1.0)
        dl:AddCircleFilled(
            center,
            radius,
            imgui.GetColorU32Vec4(col),
            32
        )

        if hovered and imgui.IsMouseClicked(0) then
            menu.switch() -- 🔥 sama persis kaya pas buka GUI
        end
        imgui.End()
        imgui.PopStyleVar()
    end
)


function darkgreentheme()
imgui.SwitchContext()
local style  = imgui.GetStyle()
local colors = style.Colors
local clr    = imgui.Col
local ImVec4 = imgui.ImVec4
local ImVec2 = imgui.ImVec2

style.WindowPadding = ImVec2(15, 15)  
style.WindowRounding = 20.0  
style.FramePadding = ImVec2(6, 6)  
style.ItemSpacing = ImVec2(12, 8)  
style.ItemInnerSpacing = ImVec2(8, 6)  
style.IndentSpacing = 25.0  
style.ScrollbarSize = 16.0  
style.ScrollbarRounding = 10.0  
style.GrabMinSize = 14.0  
style.GrabRounding = 8.0  
style.ChildRounding = 12.0  
style.FrameRounding = 10.0  
style.WindowTitleAlign = ImVec2(0.5, 0.5)

colors[clr.Text] = ImVec4(1.00, 1.00, 1.00, 1.00)
colors[clr.TextDisabled] = ImVec4(0.70, 0.70, 0.70, 1.00)
colors[clr.WindowBg] = ImVec4(1.00, 1.00, 0.00, 1.00)
colors[clr.ChildBg] = ImVec4(0.06, 0.10, 0.09, 1.00)
colors[clr.PopupBg] = ImVec4(0.03, 0.05, 0.04, 0.98)
colors[clr.Border] = ImVec4(1.00, 1.00, 1.00, 0.45)
colors[clr.BorderShadow] = ImVec4(0.00, 0.00, 0.00, 0.00)

colors[clr.FrameBg]         = ImVec4(0.22, 0.22, 0.22, 1.00) -- normal
colors[clr.FrameBgHovered] = ImVec4(0.30, 0.30, 0.30, 1.00) -- hover
colors[clr.FrameBgActive]  = ImVec4(0.38, 0.38, 0.38, 1.00) -- aktif
colors[clr.TitleBg] = ImVec4(0.28, 0.28, 0.28, 1.00)
colors[clr.TitleBgCollapsed] = ImVec4(0.28, 0.28, 0.28, 1.00)
colors[clr.TitleBgActive] = ImVec4(0.38, 0.38, 0.38, 1.00)
colors[clr.MenuBarBg] = ImVec4(0.06, 0.10, 0.09, 1.00)
colors[clr.ScrollbarBg] = ImVec4(0.02, 0.04, 0.03, 0.50)
colors[clr.ScrollbarGrab] = ImVec4(1.00, 1.00, 1.00, 0.80)
colors[clr.ScrollbarGrabHovered] = ImVec4(1.00, 1.00, 1.00, 1.00)
colors[clr.ScrollbarGrabActive] = ImVec4(1.00, 1.00, 1.00, 1.00)

colors[clr.CheckMark] = ImVec4(1.00, 1.00, 1.00, 1.00)
colors[clr.SliderGrab] = ImVec4(1.00, 1.00, 1.00, 1.00)
colors[clr.SliderGrabActive] = ImVec4(1.00, 1.00, 1.00, 1.00)

colors[clr.Button]        = ImVec4(0.00, 0.00, 0.00, 0.00)
colors[clr.ButtonHovered] = ImVec4(0.00, 0.00, 0.00, 0.00)
colors[clr.ButtonActive]  = ImVec4(0.00, 0.00, 0.00, 0.00)
colors[clr.Header] = ImVec4(0.50, 0.50, 0.50, 0.50)
colors[clr.HeaderHovered] = ImVec4(1.00, 1.00, 1.00, 0.85)
colors[clr.HeaderActive] = ImVec4(1.00, 1.00, 1.00, 1.00)

colors[clr.ResizeGrip] = ImVec4(1.00, 1.00, 1.00, 0.35)
colors[clr.ResizeGripHovered] = ImVec4(1.00, 1.00, 1.00, 0.75)
colors[clr.ResizeGripActive] = ImVec4(1.00, 1.00, 1.00, 1.00)

colors[clr.PlotLines] = ImVec4(1.00, 1.00, 1.00, 1.00)
colors[clr.PlotLinesHovered] = ImVec4(1.00, 1.00, 1.00, 1.00)
colors[clr.PlotHistogram] = ImVec4(1.00, 1.00, 1.00, 1.00)
colors[clr.PlotHistogramHovered] = ImVec4(1.00, 1.00, 1.00, 1.00)

colors[clr.TextSelectedBg] = ImVec4(1.00, 1.00, 1.00, 0.50)
colors[clr.ModalWindowDimBg] = ImVec4(0.30, 0.30, 0.30, 0.80)
end
