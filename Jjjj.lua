script_author("Deprau")

local ffi = require 'ffi'

ffi.cdef[[
    float fPlayerAimScale;
]]

local gta = ffi.load('GTASA')

local original = gta.fPlayerAimScale
gta.fPlayerAimScale = 0.0

function main()
    while true do
        wait(-1)
    end
end

function onScriptTerminate(script)
    if script == thisScript() then
        gta.fPlayerAimScale = original
    end
end
