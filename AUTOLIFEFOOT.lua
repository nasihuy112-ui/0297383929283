local ffi = require("ffi")
local memory = require("memory")
local imgui = require("mimgui")
local gta = ffi.load("GTASA")
local samem = require("SAMemory")
local inicfg = require("inicfg")
local sampev = require("samp.events")

samem.require("CPed")
samem.require("CPlayerData")

ffi.cdef[[void _Z12AND_OpenLinkPKc(const char* link);]]

function openLink(url)
    gta._Z12AND_OpenLinkPKc(url)
end

local player_ped = samem.cast("CPed **", samem.player_ped)
local window = imgui.new.bool(false)

local cfg = inicfg.load({
    Setting = {
        EnableMain        = true,
        UseBulletSync     = false,
        UseGiveDamage     = false,
        SprintSpeed       = 1.0,
        ResetDuration     = 2000,
        EnableWeaponReset = true,
        RestoreDelay      = 500
    }
}, "autolifefoot")

local EnableMain        = imgui.new.bool(cfg.Setting.EnableMain)
local UseBulletSync     = imgui.new.bool(cfg.Setting.UseBulletSync)
local UseGiveDamage     = imgui.new.bool(cfg.Setting.UseGiveDamage)
local SprintSpeed       = imgui.new.float(cfg.Setting.SprintSpeed)
local ResetDuration     = imgui.new.int(cfg.Setting.ResetDuration)
local EnableWeaponReset = imgui.new.bool(cfg.Setting.EnableWeaponReset)
local RestoreDelay      = imgui.new.int(cfg.Setting.RestoreDelay)

local function saveset()
    cfg.Setting.EnableMain        = EnableMain[0]
    cfg.Setting.UseBulletSync     = UseBulletSync[0]
    cfg.Setting.UseGiveDamage     = UseGiveDamage[0]
    cfg.Setting.SprintSpeed       = SprintSpeed[0]
    cfg.Setting.ResetDuration     = ResetDuration[0]
    cfg.Setting.EnableWeaponReset = EnableWeaponReset[0]
    cfg.Setting.RestoreDelay      = RestoreDelay[0]

    inicfg.save(cfg, "autolifefoot")
    sampAddChatMessage("Config disimpan!", -1)
end

local function getPed()
    if not player_ped then return nil end
    local ped = player_ped[0]
    if ped == nil or ped == samem.nullptr then return nil end
    return ped
end

local function getPlayerData()
    local ped = getPed()
    if not ped then return nil end
    return ped.pPlayerData
end

local function nowMs()
    return os.clock() * 1000
end

local resetUntil = 0
local lastWeapon = nil
local restoreAt  = 0
local restoring  = false

local function triggerReset()
    local now = nowMs()
    resetUntil = now + ResetDuration[0]
    if not EnableWeaponReset[0] then return end

    local curWeapon = getCurrentCharWeapon(PLAYER_PED)
    if curWeapon ~= 0 then lastWeapon = curWeapon end

    setCurrentCharWeapon(PLAYER_PED, 0)
    restoreAt = now + RestoreDelay[0]
    restoring = true
end

function sampev.onSendGiveDamage(playerId, damage, weapon, bodypart)
    if not EnableMain[0] or not UseGiveDamage[0] then return end
    if damage > 0 and weapon ~= 0 then
        triggerReset()
    end
end

function sampev.onSendBulletSync(data)
    if not EnableMain[0] or not UseBulletSync[0] then return end
    triggerReset()
end

lua_thread.create(function()
    while true do
        local now = nowMs()
        local sprintActive = EnableMain[0] and resetUntil > now
        local restoreActive = EnableWeaponReset[0] and restoring

        if sprintActive then
            local ped = getPed()
            if ped then
                local pdata = getPlayerData()
                if pdata then
                    pdata.fSprintEnergy = 5.0
                    pdata.bPlayerSprintDisabled = false
                end
                ped.nPedFlags.bResetWalkAnims = 1
            end
        end

        if restoreActive and restoreAt > 0 and now >= restoreAt then
            setCurrentCharWeapon(PLAYER_PED, (lastWeapon and lastWeapon ~= 0) and lastWeapon or 24)
            restoreAt = 0
            restoring = false
        end

        if sprintActive or restoreActive then
            wait(0)
        else
            wait(50)
        end
    end
end)

function main()
    while not isSampAvailable() do wait(0) end
    sampRegisterChatCommand("alm", function() window[0] = not window[0] end)
    wait(-1)
end

local REF_WIDTH  = 1280.0
local REF_HEIGHT = 720.0

local function getDPI()
    local io = imgui.GetIO()
    local sx = io.DisplaySize.x / REF_WIDTH
    local sy = io.DisplaySize.y / REF_HEIGHT
    return math.min(sx, sy)
end

local DPI = getDPI()

imgui.OnFrame(
    function()
        return window[0]
    end,
    function()
        imgui.SetNextWindowSize(imgui.ImVec2(199 * DPI, 0), imgui.Cond.FirstUseEver)

        if imgui.Begin("Deprau - Auto Lifefoot", window,
            imgui.WindowFlags.NoCollapse + imgui.WindowFlags.AlwaysAutoResize + imgui.WindowFlags.NoScrollbar) then

            imgui.Checkbox("Enable", EnableMain)
            imgui.SameLine()
            if imgui.Button("Save", imgui.ImVec2(imgui.GetContentRegionAvail().x, 30 * DPI)) then
                saveset()
            end

            if EnableMain[0] then
                if imgui.Checkbox("BulletSync", UseBulletSync) then
                    if UseBulletSync[0] then UseGiveDamage[0] = false end
                end

                if imgui.Checkbox("GiveDamage", UseGiveDamage) then
                    if UseGiveDamage[0] then UseBulletSync[0] = false end
                end

                imgui.PushItemWidth(250 * DPI)
                imgui.SliderInt("##ResetDuration", ResetDuration, 0, 10000, "Reset - %d")
                if EnableWeaponReset[0] then
                    imgui.SliderInt("##RestoreDelay", RestoreDelay, 0, 10000, "Switch - %d")
                end
                imgui.PopItemWidth()
            end
        end

        imgui.End()
    end
)
