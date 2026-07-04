script_name("snap turn")
script_author("Deprau")

local ffi = require("ffi")
local m = require("memory")
local mem = require("memory")
local SAMemory = require("SAMemory")
SAMemory.require("CCamera")
local cam = SAMemory.camera

local base = MONET_GTASA_BASE

local addrs = {
    base + 0x3FAFBC
}

local orig = {}
for i = 1, #addrs do
    orig[i] = mem.tostring(addrs[i], 4, true)
end

local patched = false

local function patchOn()
    if patched then return end
    for i = 1, #addrs do
        mem.copy(addrs[i], "\x00\x20\x70\x47", 4, true)
    end
    patched = true
end

local function patchOff()
    if not patched then return end
    for i = 1, #addrs do
        mem.copy(addrs[i], orig[i], 4, true)
    end
    patched = false
end

local wa = false
local at = 0

function main()
    while not isSampAvailable() do wait(0) end

    while true do
        wait(0)

        local md = cam.aCams[0].nMode

        local aim =
            md == 7 or
            md == 8 or
            md == 51 or
            md == 53

        local nw = os.clock()
        
        if aim then
            m.setfloat(getCharPointer(PLAYER_PED) + 0x564, 50.0, true)
            patchOn()
            wa = true
            at = 0
        else
            if wa then
                wa = false
                at = nw
            end

            if at > 0 and (nw - at) >= 0.3 then
                m.setfloat(getCharPointer(PLAYER_PED) + 0x564, 12.0, true)
                patchOff()
                at = 0
            end
        end
    end
end

function onScriptTerminate(script)
    if script == thisScript() then
        patchOff()
    end
end
