
local imgui = require('mimgui')
local ffi   = require('ffi')
local hk    = require('monethook')
local gt    = ffi.load('GTASA')
local mm    = require('SAMemory')
local cs    = ffi.cast

mm.require('RenderWare')

pcall(function()
    ffi.cdef[[
    typedef struct {
        RwV3D   pos;
        RwV3D   normal;
        RwColor color;
        float   u, v;
    } RwIm3DVertex;

    typedef struct { float x, y, z; } CVec;

    int   _Z16RwRenderStateSet13RwRenderStatePv(int state, void* value);
    bool  _Z15RwIm3DTransformP18RxObjSpace3DVertexjP11RwMatrixTagj(RwIm3DVertex* verts, uint32_t numVerts, RwMatrix* mat, uint32_t flags);
    void  _Z28RwIm3DRenderIndexedPrimitive15RwPrimitiveTypePti(int primType, uint16_t* indices, int numIndices);
    void  _Z9RwIm3DEndv();
    void  _ZN13CBulletTraces8AddTraceEP7CVectorS1_fjh(CVec* start, CVec* end, float size, uint32_t lifetime, uint8_t opacity);
    void  _ZN13CBulletTraces8AddTraceEP7CVectorS1_iP7CEntity(CVec* start, CVec* end, int weaponType, void* pEntity);
    void  _Z22FireOneInstantHitRoundP7CVectorS0_i(CVec* start, CVec* end, int weaponType);
    int   _Z16RwTextureDestroyP9RwTexture(void* tex);
    void  _ZN13CBulletTraces6RenderEv();
    ]]
end)

local T1 = 1
local T2 = 7
local T3 = 8
local T4 = 10
local T5 = 11
local T6 = 12
local T7 = 20
local PT = 3

local RES_DIR = getWorkingDirectory()..'/resource/BulletTracers/'
local CP      = getWorkingDirectory()..'/config/BulletTracers.cfg'

local function scanTextures()
    local list = {}
    local i = 1
    local ok, handle = pcall(io.popen, 'ls "'..RES_DIR..'"')
    if ok and handle then
        for fname in handle:lines() do
            if fname:match('%.png$') or fname:match('%.PNG$') then
                list[i] = fname
                i = i + 1
            end
        end
    end
    return list
end

local function lC()
    local f = io.open(CP, 'r')
    if not f then return nil end
    local d = {}
    for ln in f:lines() do
        local k, v = ln:match('^([^=]+)=(.+)$')
        if k and v then
            local n = tonumber(v)
            d[k] = n ~= nil and n or v
        end
    end
    f:close()
    return d
end

local function sC(c)
    local f = io.open(CP, 'w')
    if not f then return end
    f:write(string.format('en=%d\n',   c.en[0] and 1 or 0))
    f:write(string.format('tw=%.4f\n', c.tw[0]))
    f:write(string.format('ft=%.4f\n', c.ft[0]))
    f:write(string.format('cr=%.4f\n', c.co[0]))
    f:write(string.format('cg=%.4f\n', c.co[1]))
    f:write(string.format('cb=%.4f\n', c.co[2]))
    f:write(string.format('ca=%.4f\n', c.co[3]))
    f:write(string.format('tx=%s\n',   c.tx))
    f:close()
end

local sv = lC()
local function gv(k, d) return sv and sv[k] or d end

local c = {
    en = imgui.new.bool(gv('en', 1) == 1),
    sm = imgui.new.bool(false),
    tw = imgui.new.float(gv('tw', 0.08)),
    ft = imgui.new.float(gv('ft', 0.15)),
    co = imgui.new.float[4](
        gv('cr', 1.0),
        gv('cg', 1.0),
        gv('cb', 0.9),
        gv('ca', 1.0)
    ),
    tx = gv('tx', ''),
}

local SG = 1
local VP = 20
local IP = 12
local VT = SG * VP
local IT = SG * IP
local HC = 500

local tr   = {}
local ir   = false

local px, py, pz
local rr   = nil
local tl   = false
local rw   = nil

local texList    = {}
local texIdx     = 1
local previewTex = nil
local previewRw  = nil

local vt = ffi.new('RwIm3DVertex[?]', HC * VT)
local id = ffi.new('uint16_t[?]',     HC * IT)

local mt = ffi.new('RwMatrix')
mt.right.x=1; mt.right.y=0; mt.right.z=0
mt.up.x=0;    mt.up.y=1;    mt.up.z=0
mt.at.x=0;    mt.at.y=0;    mt.at.z=1
mt.pos.x=0;   mt.pos.y=0;   mt.pos.z=0

local function nw() return os.clock() end

local function fileExists(path)
    local f = io.open(path, 'rb')
    if f then f:close(); return true end
    return false
end

local function RS(st, vl)
    pcall(function()
        gt._Z16RwRenderStateSet13RwRenderStatePv(st, cs('void*', vl))
    end)
end

local function iF(v)
    return v == v and v ~= math.huge and v ~= -math.huge
end

local function gP(dx, dy)
    local cx, cy = dy, -dx
    local cl = math.sqrt(cx*cx + cy*cy)
    if cl > 0.001 then return cx/cl, cy/cl, 0 end
    return 1, 0, 0
end

local function sV(v, x, y, z, u, vv, r, g, b, a)
    v.pos.x=x; v.pos.y=y; v.pos.z=z
    v.normal.x=0; v.normal.y=1; v.normal.z=0
    v.color.r=r; v.color.g=g; v.color.b=b; v.color.a=a
    v.u=u; v.v=vv
end

local function fadeAlpha(pg)
    local inv = 1 - pg
    return inv * inv * inv
end

local function loadRwTex(path)
    local ok, tx = pcall(renderLoadTextureFromFile, path)
    if not ok or not tx then return nil, nil end
    local rwPtr  = cs('RwTexture*', tx)
    local raster = cs('void*', cs('uintptr_t', rwPtr.raster))
    return rwPtr, raster
end

local function applyTexture(fname)
    local path = RES_DIR .. fname
    if not fileExists(path) then
        print('[BulletTracers] Texture "'..fname..'" tidak ditemukan!')
        pcall(sampAddChatMessage, '{FF3B3B}[BulletTracers] Texture "'..fname..'" hilang!', -1)
        tl = false
        return
    end

    if previewRw ~= nil then
        pcall(function() gt._Z16RwTextureDestroyP9RwTexture(previewRw) end)
        previewRw  = nil
        previewTex = nil
    end
    if rw ~= nil then
        pcall(function() gt._Z16RwTextureDestroyP9RwTexture(rw) end)
        rw = nil
        rr = nil
    end
    tl = false

    local rwPtr, raster = loadRwTex(path)
    if not rwPtr then
        print('[BulletTracers] gagal load texture: ' .. path)
        return
    end

    rw         = rwPtr
    rr         = raster
    previewRw  = rwPtr
    previewTex = raster
    tl         = true
    c.tx       = fname
    sC(c)
end

local CB = {}
local hooks = {}

function CB.Init()
    tr = {}
    ir = false
end

function CB.Shutdown()
    sC(c)
    tl = false
    rr = nil
    if rw ~= nil then
        pcall(function() gt._Z16RwTextureDestroyP9RwTexture(rw) end)
        rw        = nil
        previewRw = nil
        previewTex = nil
    end
    for i = 1, #hooks do
        local h = hooks[i]
        pcall(function()
            if h and h.remove then h:remove() end
        end)
    end
    hooks = {}
end

function CB.Update()
    local t0 = nw()
    local lf = c.ft[0]
    local i  = 1
    while i <= #tr do
        local t = tr[i]
        if not t or (t0 - t.st) >= lf then
            tr[i] = tr[#tr]
            tr[#tr] = nil
        else
            i = i + 1
        end
    end
end

function CB.AddTrace(sx, sy, sz, ex, ey, ez)
    if not iF(sx) or not iF(sy) or not iF(sz) then return end
    if not iF(ex) or not iF(ey) or not iF(ez) then return end
    tr[#tr + 1] = {
        sx=sx, sy=sy, sz=sz,
        ex=ex, ey=ey, ez=ez,
        st=nw(),
    }
end

local function bB(cx, cy, cz)
    local t0 = nw()
    local lf = c.ft[0]
    local vc = 0
    local ic = 0
    local bv = 0
    local cl = c.co

    for i = 1, #tr do
        if vc + VT > HC * VT then break end
        if ic + IT > HC * IT then break end

        local t = tr[i]
        if t then
            local ag = t0 - t.st
            local pg = math.max(0, math.min(1, ag / lf))
            local fR = fadeAlpha(pg)
            local fA = math.max(0, math.min(255, math.floor(255 * fR * cl[3])))

            local r = math.floor(cl[0] * 255)
            local g = math.floor(cl[1] * 255)
            local b = math.floor(cl[2] * 255)

            local dx = t.ex - t.sx
            local dy = t.ey - t.sy
            local dz = t.ez - t.sz
            local ln = math.sqrt(dx*dx + dy*dy + dz*dz)

            if ln >= 0.001 and iF(ln) then
                dx=dx/ln; dy=dy/ln; dz=dz/ln

                local hw = c.tw[0]
                local pX, pY, pZ = t.sx, t.sy, t.sz

                for sg = 1, SG do
                    local t1  = sg / SG
                    local t0n = (sg - 1) / SG

                    local qx, qy, qz
                    if sg == SG then
                        qx, qy, qz = t.ex, t.ey, t.ez
                    else
                        qx = t.sx + dx*ln*t1
                        qy = t.sy + dy*ln*t1
                        qz = t.sz + dz*ln*t1
                    end

                    local sd = qx - pX
                    local se = qy - pY
                    local sf = qz - pZ
                    local sl = math.sqrt(sd*sd + se*se + sf*sf)

                    if sl >= 0.0005 and iF(sl) then
                        sd=sd/sl; se=se/sl; sf=sf/sl

                        local tX = cx - pX
                        local tY = cy - pY
                        local tZ = cz - pZ
                        local tL = math.sqrt(tX*tX + tY*tY + tZ*tZ)
                        local aw, ab, ac

                        if tL > 0.001 and iF(tL) then
                            tX=tX/tL; tY=tY/tL; tZ=tZ/tL
                            aw = se*tZ - sf*tY
                            ab = sf*tX - sd*tZ
                            ac = sd*tY - se*tX
                            local aL = math.sqrt(aw*aw + ab*ab + ac*ac)
                            if aL < 0.001 or not iF(aL) then
                                aw, ab, ac = gP(sd, se)
                            else
                                aw=aw/aL; ab=ab/aL; ac=ac/aL
                            end
                        else
                            aw, ab, ac = gP(sd, se)
                        end

                        local bw = se*ac - sf*ab
                        local bb = sf*aw - sd*ac
                        local bc = sd*ab - se*aw
                        local bL = math.sqrt(bw*bw + bb*bb + bc*bc)
                        if bL > 0.001 and iF(bL) then
                            bw=bw/bL; bb=bb/bL; bc=bc/bL
                        else
                            bw, bb, bc = 0, 0, 1
                        end

                        local a1=aw*hw; local a2=ab*hw; local a3=ac*hw
                        local b1=bw*hw; local b2=bb*hw; local b3=bc*hw

                        if iF(a1) and iF(a2) and iF(a3) and iF(b1) and iF(b2) and iF(b3) then
                            sV(vt[bv+0], pX+a1,pY+a2,pZ+a3, 0,t0n, r,g,b,fA)
                            sV(vt[bv+1], pX-a1,pY-a2,pZ-a3, 1,t0n, r,g,b,fA)
                            sV(vt[bv+2], qx+a1,qy+a2,qz+a3, 0,t1,  r,g,b,fA)
                            sV(vt[bv+3], qx-a1,qy-a2,qz-a3, 1,t1,  r,g,b,fA)

                            local ii=ic
                            id[ii+0]=bv+0; id[ii+1]=bv+1; id[ii+2]=bv+2
                            id[ii+3]=bv+1; id[ii+4]=bv+3; id[ii+5]=bv+2

                            bv=bv+4; vc=vc+4; ic=ic+6

                            sV(vt[bv+0], pX+b1,pY+b2,pZ+b3, 0,t0n, r,g,b,fA)
                            sV(vt[bv+1], pX-b1,pY-b2,pZ-b3, 1,t0n, r,g,b,fA)
                            sV(vt[bv+2], qx+b1,qy+b2,qz+b3, 0,t1,  r,g,b,fA)
                            sV(vt[bv+3], qx-b1,qy-b2,qz-b3, 1,t1,  r,g,b,fA)

                            local ii2=ic
                            id[ii2+0]=bv+0; id[ii2+1]=bv+1; id[ii2+2]=bv+2
                            id[ii2+3]=bv+1; id[ii2+4]=bv+3; id[ii2+5]=bv+2

                            bv=bv+4; vc=vc+4; ic=ic+6
                        end
                    end

                    pX, pY, pZ = qx, qy, qz
                end
            end
        end
    end

    return vc, ic
end

function CB.Render()
    if ir then return end
    if not tl then return end
    if not rr then return end
    if #tr == 0 then return end
    if px == nil or py == nil or pz == nil then return end

    local cx, cy, cz
    local ok = pcall(function() cx=px[0]; cy=py[0]; cz=pz[0] end)
    if not ok then return end
    if not iF(cx) or not iF(cy) or not iF(cz) then return end

    ir = true

    pcall(function()
        RS(T3, 0)
        RS(T2, 4)
        RS(T6, 1)
        RS(T4, 5)
        RS(T5, 6)
        RS(T7, 1)
        RS(13,3); RS(14,3); RS(15,3)

        local vc, ic = bB(cx, cy, cz)
        if vc > 0 then
            local ok2 = gt._Z15RwIm3DTransformP18RxObjSpace3DVertexjP11RwMatrixTagj(vt, vc, mt, 1)
            if ok2 then
                RS(T1, rr)
                gt._Z28RwIm3DRenderIndexedPrimitive15RwPrimitiveTypePti(PT, id, ic)
                gt._Z9RwIm3DEndv()
            end
        end

        RS(T7, 3)
        RS(T2, 4)
        RS(T3, 1)
        RS(T6, 0)
        RS(13,1); RS(14,1); RS(15,1)
    end)

    ir = false
end

local lt = 0
local SI = 2.0

local BASE_W, BASE_H = 1280, 720

local function getDPIScale()
    local ok, sw, sh = pcall(getScreenResolution)
    if not ok or not sw or not sh or sw <= 0 or sh <= 0 then
        return 1.0
    end
    local scale = math.min(sw / BASE_W, sh / BASE_H)
    if scale < 0.6 then scale = 0.6 end
    if scale > 2.0 then scale = 2.0 end
    return scale
end

local DPI = getDPIScale()

function darkgreentheme()
    imgui.SwitchContext()
    local style = imgui.GetStyle()
    local ImVec2 = imgui.ImVec2

    style.WindowRounding    = 18.0
    style.ItemSpacing       = ImVec2(12, 8)
    style.ItemInnerSpacing  = ImVec2(8, 6)
    style.IndentSpacing     = 25.0
    style.ScrollbarSize     = 25.0
    style.ScrollbarRounding = 10.0
    style.GrabMinSize       = 20.0
    style.GrabRounding      = 20.0
    style.ChildRounding     = 12.0
    style.FrameRounding     = 10.0
    style.WindowTitleAlign  = ImVec2(0.5, 0.5)
end

imgui.OnFrame(
    function() return c.sm[0] end,
    function()
        darkgreentheme()
        imgui.SetNextWindowSize(imgui.ImVec2(0, 0))
        imgui.Begin('Deprau - BulletTracers', c.sm, imgui.WindowFlags.AlwaysAutoResize + imgui.WindowFlags.NoCollapse)

        local ch = false
        imgui.PushItemWidth(180 * DPI)
        if imgui.SliderFloat('Scale', c.tw, 0.02, 0.2, '%.3f') then ch = true end
        imgui.PopItemWidth()

        imgui.PushItemWidth(180 * DPI)
        if imgui.SliderFloat('Fade Duration', c.ft, 0.10, 3.0, '%.2f') then ch = true end
        imgui.PopItemWidth()

        imgui.PushItemWidth(180 * DPI)
        if imgui.ColorEdit4('Color',   c.co, imgui.ColorEditFlags.AlphaBar) then ch = true end
        imgui.PopItemWidth()

        imgui.Spacing()
        if imgui.CollapsingHeader('Change Texture') then
            if #texList == 0 then
                imgui.TextDisabled('No PNG found in /resource/BulletTracers/')
            else
                for i = 1, #texList do
                    local selected = (i == texIdx)
                    if imgui.Selectable(texList[i], selected) then
                        if not selected then
                            texIdx = i
                            applyTexture(texList[i])
                        end
                    end
                end
                if previewTex ~= nil then
                    imgui.Image(previewTex, imgui.ImVec2(128, 120),
                        imgui.ImVec2(0,0), imgui.ImVec2(1,1),
                        imgui.ImVec4(1,1,1,1),
                        imgui.ImVec4(0.4,0.4,0.4,1))
                end
            end
        end

        if ch then
            local nt = os.clock()
            if nt - lt >= SI then
                sC(c)
                lt = nt
            end
        end

        imgui.End()
    end
)
addEventHandler('onScriptTerminate', function(scr)
    if scr == script.this then
        CB.Shutdown()
    end
end)

function main()
    if not isSampLoaded() or not isSampfuncsLoaded() then return end
    while not isSampAvailable() do wait(100) end

    sampRegisterChatCommand('bullt', function()
        c.sm[0] = not c.sm[0]
    end)

    local bs = MONET_GTASA_BASE
    local cb = bs + 0xC4B968
    px = cs("float*", cb + 0x4B0)
    py = cs("float*", cb + 0x4B4)
    pz = cs("float*", cb + 0x4B8)

    CB.Init()

    texList = scanTextures()

    local startTex = c.tx ~= '' and c.tx or (texList[1] or '')
    if startTex ~= '' and fileExists(RES_DIR .. startTex) then
        for i = 1, #texList do
            if texList[i] == startTex then texIdx = i; break end
        end
        applyTexture(startTex)
    elseif texList[1] then
        print('[BulletTracers] "'..startTex..'" hilang, pakai fallback: '..texList[1])
        applyTexture(texList[1])
    else
        print('[BulletTracers] ERROR: tidak ada PNG di ' .. RES_DIR)
        return
    end

    local lastCheck = 0

    local h1
    h1 = hk.new(
        "void(*)(CVec*, CVec*, float, uint32_t, uint8_t)",
        function(pS, pE, sz, lf, op)
            pcall(function() h1(pS, pE, sz, lf, op) end)
            if not c.en[0] then return end
            if pS == nil or pE == nil then return end
            pcall(function() CB.AddTrace(pS.x, pS.y, pS.z, pE.x, pE.y, pE.z) end)
        end,
        cs("uintptr_t", cs("void*", gt._ZN13CBulletTraces8AddTraceEP7CVectorS1_fjh))
    )
    hooks[#hooks + 1] = h1

    local h2
    h2 = hk.new(
        "void(*)(CVec*, CVec*, int, void*)",
        function(pS, pE, wp, pe)
            pcall(function() h2(pS, pE, wp, pe) end)
            if not c.en[0] then return end
            if pS == nil or pE == nil then return end
            pcall(function() CB.AddTrace(pS.x, pS.y, pS.z, pE.x, pE.y, pE.z) end)
        end,
        cs("uintptr_t", cs("void*", gt._ZN13CBulletTraces8AddTraceEP7CVectorS1_iP7CEntity))
    )
    hooks[#hooks + 1] = h2

    local h3
    h3 = hk.new(
        "void(*)(CVec*, CVec*, int)",
        function(pS, pE, wp)
            pcall(function() h3(pS, pE, wp) end)
            if not c.en[0] then return end
            if pS == nil or pE == nil then return end
            pcall(function() CB.AddTrace(pS.x, pS.y, pS.z, pE.x, pE.y, pE.z) end)
        end,
        cs("uintptr_t", cs("void*", gt._Z22FireOneInstantHitRoundP7CVectorS0_i))
    )
    hooks[#hooks + 1] = h3

    local h4
    h4 = hk.new(
        "void(*)()",
        function()
            if c.en[0] then
                local now2 = os.clock()
                if tl and (now2 - lastCheck) >= 5.0 then
                    lastCheck = now2
                    if not fileExists(RES_DIR .. c.tx) then
                        tl = false
                        print('[BulletTracers] Texture "'..c.tx..'" hilang, tracer dinonaktifkan!')
                        pcall(sampAddChatMessage, '{FF3B3B}[BulletTracers] Texture hilang, tracer off!', -1)
                    end
                end
                pcall(function() CB.Update() end)
                pcall(CB.Render)
            end
            pcall(function() h4() end)
        end,
        cs("uintptr_t", cs("void*", gt._ZN13CBulletTraces6RenderEv))
    )
    hooks[#hooks + 1] = h4

    wait(-1)
end