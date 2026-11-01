-- ============================================================
-- EXTERNAL FEATURES FILE (1.lua)
-- Upload this to GitHub.
-- ============================================================

if _G.__ExternalFeaturesStarted then return end
_G.__ExternalFeaturesStarted = true

local GameplayData = require("GameLua.GameCore.Data.GameplayData")

-- ============================================================
-- Imports & Helpers
-- ============================================================
local EAvatarDamagePosition = nil
pcall(function() EAvatarDamagePosition = import("EAvatarDamagePosition") end)

local SBL, WLL, FV2D, FV, FLC, FSLC
pcall(function()
    SBL = import("SlateBlueprintLibrary")
    WLL = import("WidgetLayoutLibrary")
    FV2D = import("Vector2D")
    FV = import("Vector")
    FLC = import("LinearColor")
    FSLC = import("SlateColor")
end)

local function FIsValid(o)
    if not o then return false end
    if slua and slua.isValid then return slua.isValid(o) end
    return true
end

local function IsInFightingStatus()
    local r = false
    pcall(function()
        if GameStatus and GameStatus.IsInFightingStatus then
            r = GameStatus.IsInFightingStatus() == true
        else
            r = true
        end
    end)
    return r
end

-- ============================================================
-- Feature Config
-- ============================================================
local FC = {
    COMBAT = { enabled = true },
    AIMBOT = { enabled = true, fov = 50, speed = 8.0, bone = "head" },
    IPAD = { enabled = true, fov = 130, default_fov = 90 }, -- 90 هو المنظور الطبيعي
    NORECOIL = { enabled = true },
    MAGIC_HEAD = { enabled = true, scale = 3.5, affect_neck = true, clear_cache_interval = 30 },
    FULL_BODY = { enabled = true, damage_mult = 10 },
    ESP = { enabled = true },
}

-- ============================================================
-- COMBAT FUNCTIONS
-- ============================================================
local function ApplyAimbot()
    if not FC.COMBAT.enabled or not FC.AIMBOT.enabled then return end
    pcall(function()
        local pc = slua_GameFrontendHUD:GetPlayerController()
        if not FIsValid(pc) then return end
        local ch = pc:GetPlayerCharacterSafety()
        if not FIsValid(ch) then return end
        local wm = ch.WeaponManagerComponent
        if not FIsValid(wm) then return end
        local w = wm.CurrentWeaponReplicated
        if not FIsValid(w) then return end
        local e = w.ShootWeaponEntityComp
        if FIsValid(e) and e.AutoAimingConfig then
            for _, r in ipairs({"OuterRange", "InnerRange"}) do
                local c = e.AutoAimingConfig[r]
                if c then
                    c.Range = FC.AIMBOT.fov
                    c.FOV = FC.AIMBOT.fov
                    c.Speed = FC.AIMBOT.speed
                    c.SpeedRate = FC.AIMBOT.speed
                    c.RangeRate = FC.AIMBOT.speed
                end
            end
        end
        local ac = ch.BP_AutoAimingComponent_C or ch.BP_AutoAimingComponent
        if FIsValid(ac) and ac.Bones then
            ac.Bones = { FC.AIMBOT.bone, FC.AIMBOT.bone, FC.AIMBOT.bone }
        end
    end)
end

local function ApplyiPadFOV()
    -- إصلاح زر الكومبات: لو مقفول يرجع المنظور الطبيعي
    if not FC.COMBAT.enabled or not FC.IPAD.enabled then
        pcall(function()
            local pc = slua_GameFrontendHUD:GetPlayerController()
            if FIsValid(pc) then
                local ch = pc:GetPlayerCharacterSafety()
                if FIsValid(ch) then
                    local cam = ch.ThirdPersonCameraComponent
                    if FIsValid(cam) and not ch.bIsWeaponAiming then
                        if cam.FieldOfView ~= FC.IPAD.default_fov then
                            cam.FieldOfView = FC.IPAD.default_fov
                        end
                    end
                end
            end
        end)
        return
    end
    
    -- لو مفتوح يطبق الآيباد
    pcall(function()
        local pc = slua_GameFrontendHUD:GetPlayerController()
        if not FIsValid(pc) then return end
        local ch = pc:GetPlayerCharacterSafety()
        if FIsValid(ch) then
            local cam = ch.ThirdPersonCameraComponent
            if FIsValid(cam) and not ch.bIsWeaponAiming then
                if cam.FieldOfView ~= FC.IPAD.fov then
                    cam.FieldOfView = FC.IPAD.fov
                end
            end
        end
    end)
    pcall(function()
        local sc = require("client.logic.setting.setting_config")
        if sc then
            if sc.TpViewValue then sc.TpViewValue.max = FC.IPAD.fov end
            if sc.FpViewValue then sc.FpViewValue.max = FC.IPAD.fov end
        end
    end)
end

local function ModRecoil(w)
    if not FIsValid(w) then return end
    local e = w.ShootWeaponEntityComp
    if FIsValid(e) then
        e.RecoilKick = 0; e.RecoilKickADS = 0
        e.GameDeviationFactor = 0; e.GameDeviationAccuracy = 0
        if e.DeviationInfo then
            e.DeviationInfo.DeviationMax = 0
            e.DeviationInfo.DeviationBase = 0
        end
    end
end

local function ApplyNoRecoil()
    if not FC.COMBAT.enabled or not FC.NORECOIL.enabled then return end
    pcall(function()
        local pc = slua_GameFrontendHUD:GetPlayerController()
        if not FIsValid(pc) then return end
        local ch = pc:GetPlayerCharacterSafety()
        if not FIsValid(ch) then return end
        local wm = ch.WeaponManagerComponent
        if not FIsValid(wm) then return end
        ModRecoil(wm.CurrentWeaponReplicated)
        local all = wm:GetAllInventoryWeaponList(false)
        if FIsValid(all) then
            for i = 0, all:Num() - 1 do ModRecoil(all:Get(i)) end
        end
    end)
end

local function EnlargeHead()
    if not FC.COMBAT.enabled or not FC.MAGIC_HEAD.enabled then return end
    if not IsInFightingStatus() then return end
    pcall(function()
        local ch = GameplayData.GetPlayerCharacter()
        if not FIsValid(ch) then return end
        _G._MagicHC = _G._MagicHC or {}
        _G._MagicHL = _G._MagicHL or 0
        if os.time() - _G._MagicHL > FC.MAGIC_HEAD.clear_cache_interval then
            _G._MagicHC = {}; _G._MagicHL = os.time()
        end
        local allPawns = Game:GetAllPlayerPawns() or {}
        for _, c in pairs(allPawns) do
            if FIsValid(c) and c ~= ch and c.TeamID and ch.TeamID and c.TeamID ~= ch.TeamID then
                local pendingKill = false
                pcall(function()
                    if type(c.IsPendingKill) == "function" then
                        pendingKill = c:IsPendingKill() == true
                    end
                end)
                if not pendingKill then
                    local mesh = c.Mesh
                    if FIsValid(mesh) then
                        local pa = nil
                        pcall(function() pa = mesh.PhysicsAssetOverride end)
                        if not FIsValid(pa) then
                            pcall(function()
                                if FIsValid(mesh.SkeletalMesh) then pa = mesh.SkeletalMesh.PhysicsAsset end
                            end)
                        end
                        if FIsValid(pa) and pa.SkeletalBodySetups then
                            local an = tostring(pa)
                            pcall(function() if type(pa.GetName) == "function" then an = pa:GetName() end end)
                            if not _G._MagicHC[an] then
                                local setups = pa.SkeletalBodySetups
                                local sc = FC.MAGIC_HEAD.scale
                                for i = 1, 80 do
                                    local bs = nil
                                    pcall(function() bs = (type(setups.Get) == "function") and setups:Get(i - 1) or setups[i] end)
                                    if not bs or not FIsValid(bs) then break end
                                    local bn = tostring(bs.BoneName):lower()
                                    local should = string.find(bn, "head")
                                    if FC.MAGIC_HEAD.affect_neck and string.find(bn, "neck") then should = true end
                                    if should then
                                        local ag = bs.AggGeom
                                        pcall(function()
                                            local bx = (ag and ag.BoxElems) or bs.BoxElems
                                            if bx then
                                                local b = (type(bx.Get) == "function") and bx:Get(0) or bx[1]
                                                if b then
                                                    b.X = (b.X or 40) * sc; b.Y = (b.Y or 40) * sc; b.Z = (b.Z or 50) * sc
                                                    if type(bx.Set) == "function" then bx:Set(0, b) else bx[1] = b end
                                                    if ag then bs.AggGeom = ag else bs.BoxElems = bx end
                                                end
                                            end
                                        end)
                                        pcall(function()
                                            local sp = (ag and ag.SphylElems) or bs.SphylElems
                                            if sp then
                                                local s = (type(sp.Get) == "function") and sp:Get(0) or sp[1]
                                                if s then
                                                    if s.Radius then s.Radius = s.Radius * sc end
                                                    if s.Length then s.Length = s.Length * sc end
                                                    if type(sp.Set) == "function" then sp:Set(0, s) else sp[1] = s end
                                                    if ag then bs.AggGeom = ag else bs.SphylElems = sp end
                                                end
                                            end
                                        end)
                                        pcall(function()
                                            local sr = (ag and ag.SphereElems) or bs.SphereElems
                                            if sr then
                                                local s = (type(sr.Get) == "function") and sr:Get(0) or sr[1]
                                                if s and s.Radius then
                                                    s.Radius = s.Radius * sc
                                                    if type(sr.Set) == "function" then sr:Set(0, s) else sr[1] = s end
                                                    if ag then bs.AggGeom = ag else bs.SphereElems = sr end
                                                end
                                            end
                                        end)
                                    end
                                end
                                _G._MagicHC[an] = true
                                pcall(function() if mesh.RecreatePhysicsState then mesh:RecreatePhysicsState() end end)
                            end
                        end
                    end
                end
            end
        end
    end)
end

local function HookFullBody()
    if not FC.COMBAT.enabled or not FC.FULL_BODY.enabled then return end
    if _G.__FullBodyHS_Hooked then return end
    if not EAvatarDamagePosition or not EAvatarDamagePosition.BigHead then return end
    for _, p in ipairs({
        "GameLua.Mod.BaseMod.Common.Weapon.ShootWeaponEntity",
        "GameLua.Mod.BaseMod.Client.Weapon.ShootWeaponEntity",
        "GameLua.Logic.Weapon.ShootWeaponEntity",
        "client.slua.logic.weapon.ShootWeaponEntity",
        "GameLua.Logic.Weapon.ShootWeaponEntityLogic"
    }) do
        local m = package.loaded[p]
        if not m then pcall(function() m = require(p) end) end
        if m then
            if type(m.GetHitBodyType) == "function" then
                local o = m.GetHitBodyType
                m.GetHitBodyType = function(self, a, b)
                    if FC.FULL_BODY.enabled then return EAvatarDamagePosition.BigHead end
                    return o(self, a, b)
                end
            end
            if type(m.GetHitBodyTypeByHitPos) == "function" then
                local o = m.GetHitBodyTypeByHitPos
                m.GetHitBodyTypeByHitPos = function(self, a)
                    if FC.FULL_BODY.enabled then return EAvatarDamagePosition.BigHead end
                    return o(self, a)
                end
            end
            _G.__FullBodyHS_Hooked = true
        end
    end
end

local function ModDamage(w)
    if not FIsValid(w) then return end
    local s = w.ShootWeaponEntityComp
    if not FIsValid(s) then return end
    local m = FC.FULL_BODY.damage_mult
    pcall(function() if s.SetHeadDamageMultiplier then s:SetHeadDamageMultiplier(m) end end)
    pcall(function() if s.HeadDamageMultiplier then s.HeadDamageMultiplier = m end end)
end

local function ApplyDamage()
    if not FC.COMBAT.enabled or not FC.FULL_BODY.enabled then return end
    pcall(function()
        local ch = GameplayData.GetPlayerCharacter()
        if not FIsValid(ch) then return end
        local wm = ch.WeaponManagerComponent
        if not FIsValid(wm) then return end
        ModDamage(wm.CurrentWeaponReplicated)
        local all = wm:GetAllInventoryWeaponList(false)
        if FIsValid(all) then
            for i = 0, all:Num() - 1 do ModDamage(all:Get(i)) end
        end
    end)
end

-- ============================================================
-- ESP LOGIC (Simplified for External File)
-- ============================================================
local TPV = FV2D and FV2D(0, 0) or nil
local CW = FLC and FLC(1, 1, 1, 1) or nil
local CR = FLC and FLC(1, 0.15, 0.15, 1) or nil
local CG = FLC and FLC(0, 1, 0.05, 1) or nil
local CY = FLC and FLC(1, 0.95, 0, 1) or nil
local CB = FLC and FLC(0.18, 0.62, 1, 1) or nil
local SCR = (FSLC and CR) and FSLC(CR) or CR
local SCG = (FSLC and CG) and FSLC(CG) or CG

local ESP = {
    bActive = true, Canvas = nil, Boxes = {}, Lines = {},
    _SX = 1, _SY = 1, _OX = 0, _OY = 0, _LastCanvas = nil, _LastT = 0, _VisCache = {}
}

function ESP.GetCanvas()
    if ESP.Canvas and FIsValid(ESP.Canvas) then return ESP.Canvas end
    local T = package.loaded["GameLua.Mod.BaseMod.Common.UI.InGameUITools"]
    if not T then pcall(function() T = require("GameLua.Mod.BaseMod.Common.UI.InGameUITools") end) end
    if not T then return nil end
    local M = T.GetMainControlBaseUI and T.GetMainControlBaseUI()
    if not FIsValid(M) then return nil end
    local C = nil
    if M.CanvasPanel_0 and FIsValid(M.CanvasPanel_0) then C = M.CanvasPanel_0
    elseif M.CanvasPanel_42 and FIsValid(M.CanvasPanel_42) then C = M.CanvasPanel_42 end
    if C then ESP.Canvas = C end
    return C
end

function ESP.CreateWidget(pc)
    if not FLC or not FV2D then return nil end
    local CC = CGame:NewObjectFromPath("/Script/UMG.CanvasPanel", pc)
    if not FIsValid(CC) then return nil end
    local CS = pc:AddChildToCanvas(CC)
    if not CS then return nil end
    CS:SetAutoSize(false); CS:SetZOrder(995); CS:SetAlignment(FV2D(0.5, 0.5))
    local wc = FLC(1, 1, 1, 1)
    local function BL()
        local b = CGame:NewObjectFromPath("/Script/UMG.Border", CC)
        if b and FIsValid(b) then
            b:SetBrushColor(wc); b:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
            local s = CC:AddChildToCanvas(b)
            if s then s:SetAutoSize(false) end
            return { widget = b, slot = s }
        end
        return nil
    end
    local C = { TL_H = BL(), TL_V = BL(), TR_H = BL(), TR_V = BL(), BL_H = BL(), BL_V = BL(), BR_H = BL(), BR_V = BL() }
    local bg = CGame:NewObjectFromPath("/Script/UMG.Image", pc)
    if not FIsValid(bg) then return nil end
    bg:SetColorAndOpacity(FLC(0, 0, 0, 0.85)); bg:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    local bgS = pc:AddChildToCanvas(bg)
    if not bgS then return nil end
    bgS:SetAutoSize(false); bgS:SetZOrder(998); bgS:SetAlignment(FV2D(0.5, 1))
    local h = CGame:NewObjectFromPath("/Script/UMG.Image", pc)
    if not FIsValid(h) then return nil end
    h:SetColorAndOpacity(FLC(0, 1, 0, 1)); h:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    local hS = pc:AddChildToCanvas(h)
    if not hS then return nil end
    hS:SetAutoSize(false); hS:SetZOrder(999); hS:SetAlignment(FV2D(0.5, 1))
    local function CT(col, sz, al)
        local t = CGame:NewObjectFromPath("/Script/UMG.TextBlock", pc)
        local s = nil
        if t and FIsValid(t) then
            t:SetText(""); local szz = math.floor(sz or 10)
            if t.Font then
                local f = t.Font; f.Size = szz
                if f.OutlineSettings then f.OutlineSettings.OutlineSize = 1; f.OutlineSettings.OutlineColor = FLC(0, 0, 0, 1) end
                if t.SetFont then t:SetFont(f) else t.Font = f end
            end
            if t.SetFontSize then t:SetFontSize(szz) end
            t:SetJustification(1); if t.SetAutoWrapText then t:SetAutoWrapText(false) end
            if FSLC then t:SetColorAndOpacity(FSLC(col)) else t:SetColorAndOpacity(col) end
            t:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
            s = pc:AddChildToCanvas(t)
            if s then s:SetAutoSize(true); s:SetZOrder(1000); s:SetAlignment(al or FV2D(0.5, 0)) end
        end
        return t, s
    end
    local W, WS = CT(CY, 10, FV2D(0.5, 1)); local N, NS = CT(CB, 10, FV2D(0.5, 0))
    local D, DS = CT(CW, 10, FV2D(0.5, 0)); local S, SS = CT(CG, 10, FV2D(0.5, 0))
    return { CC = CC, CS = CS, C = C, Bg = bg, BgS = bgS, H = h, HS = hS, W = W, WS = WS, N = N, NS = NS, D = D, DS = DS, S = S, SS = SS, _w = "", _n = "", _d = "", _s = "", lastW = 0, lastH = 0, bVis = true }
end

function ESP.UpdateCorners(bd, w, h)
    if bd.lastW and bd.lastH and math.abs(w - bd.lastW) < 1.5 and math.abs(h - bd.lastH) < 1.5 then return end
    bd.lastW = w; bd.lastH = h
    local t = 1.0; local cl = math.max(7, math.min(w, h) * 0.28)
    local C = bd.C; bd.CS:SetSize(FV2D(w, h))
    if C.TL_H then C.TL_H.slot:SetPosition(FV2D(0, 0)); C.TL_H.slot:SetSize(FV2D(cl, t)) end
    if C.TL_V then C.TL_V.slot:SetPosition(FV2D(0, 0)); C.TL_V.slot:SetSize(FV2D(t, cl)) end
    if C.TR_H then C.TR_H.slot:SetPosition(FV2D(w - cl, 0)); C.TR_H.slot:SetSize(FV2D(cl, t)) end
    if C.TR_V then C.TR_V.slot:SetPosition(FV2D(w - t, 0)); C.TR_V.slot:SetSize(FV2D(t, cl)) end
    if C.BL_H then C.BL_H.slot:SetPosition(FV2D(0, h - t)); C.BL_H.slot:SetSize(FV2D(cl, t)) end
    if C.BL_V then C.BL_V.slot:SetPosition(FV2D(0, h - cl)); C.BL_V.slot:SetSize(FV2D(t, cl)) end
    if C.BR_H then C.BR_H.slot:SetPosition(FV2D(w - cl, h - t)); C.BR_H.slot:SetSize(FV2D(cl, t)) end
    if C.BR_V then C.BR_V.slot:SetPosition(FV2D(w - t, h - cl)); C.BR_V.slot:SetSize(FV2D(t, cl)) end
end

function ESP.UpdateTransform(pc)
    if not ESP.Canvas or not FIsValid(ESP.Canvas) then return end
    local ok = false
    if SBL and SBL.AbsoluteToLocal then
        local cg = ESP.Canvas:GetCachedGeometry()
        if cg then
            local p0 = SBL.AbsoluteToLocal(cg, FV2D(0, 0)); local p1 = SBL.AbsoluteToLocal(cg, FV2D(100, 100))
            if p0 and p1 then ESP._SX = (p1.X - p0.X)/100; ESP._SY = (p1.Y - p0.Y)/100; ESP._OX = p0.X; ESP._OY = p0.Y; ok = true end
        end
    end
    if not ok and WLL and WLL.GetViewportScale then local s = WLL.GetViewportScale(pc) or 1.0; ESP._SX = 1.0/s; ESP._SY = 1.0/s; ESP._OX = 0; ESP._OY = 0 end
end

function ESP.Project(pc, loc)
    if not FIsValid(pc) or not loc or not TPV then return false, 0, 0 end
    local r = pc:ProjectWorldLocationToScreen(loc, TPV, true)
    if (r == true or r == 1) and (TPV.X ~= 0 or TPV.Y ~= 0) then return true, TPV.X * ESP._SX + ESP._OX, TPV.Y * ESP._SY + ESP._OY end
    return false, 0, 0
end

function ESP.HideBox(bd)
    if not bd or not bd.bVis then return end; bd.bVis = false
    local c = UEnums.ESlateVisibility.Collapsed
    if bd.CC then bd.CC:SetWidgetVisibility(c) end; if bd.Bg then bd.Bg:SetWidgetVisibility(c) end
    if bd.H then bd.H:SetWidgetVisibility(c) end; if bd.W then bd.W:SetWidgetVisibility(c) end
    if bd.N then bd.N:SetWidgetVisibility(c) end; if bd.D then bd.D:SetWidgetVisibility(c) end; if bd.S then bd.S:SetWidgetVisibility(c) end
end

function ESP.ShowBox(bd)
    if not bd or bd.bVis then return end; bd.bVis = true
    local v = UEnums.ESlateVisibility.SelfHitTestInvisible
    if bd.CC then bd.CC:SetWidgetVisibility(v) end; if bd.Bg then bd.Bg:SetWidgetVisibility(v) end
    if bd.H then bd.H:SetWidgetVisibility(v) end; if bd.W then bd.W:SetWidgetVisibility(v) end
    if bd.N then bd.N:SetWidgetVisibility(v) end; if bd.D then bd.D:SetWidgetVisibility(v) end; if bd.S then bd.S:SetWidgetVisibility(v) end
end

function ESP.Update()
    if not FC.ESP.enabled or not ESP.bActive or not IsInFightingStatus() then return end
    local canvas = ESP.GetCanvas()
    if not canvas then return end
    local LP = GameplayData.GetPlayerCharacter()
    if not FIsValid(LP) then return end
    local PC = GameplayData.GetPlayerController()
    if not FIsValid(PC) then return end
    
    local now = os.clock()
    if ESP._LastCanvas ~= canvas or (now - ESP._LastT > 1.0) then ESP.UpdateTransform(PC); ESP._LastCanvas = canvas; ESP._LastT = now end
    
    local myTeam = LP.TeamID or (LP.GetTeamID and LP:GetTeamID()) or 0
    local seen = {}
    for k, p in pairs(Game:GetAllPlayerPawns() or {}) do
        if FIsValid(p) and p ~= LP then
            local pendingKill = false; pcall(function() if type(p.IsPendingKill) == "function" then pendingKill = p:IsPendingKill() == true end end)
            if not pendingKill then
                local pt = p.TeamID or (p.GetTeamID and p:GetTeamID()) or -1
                local alive = (p.Health and p.Health > 0) or (p.IsAlive and p:IsAlive())
                if alive and pt ~= myTeam then
                    local ks = tostring(k); seen[ks] = true
                    local loc = p:K2_GetActorLocation()
                    if loc then
                        local top, bot = nil, nil
                        local mesh = p.Mesh
                        if mesh and mesh.GetSocketLocation then
                            local h = nil; pcall(function() h = mesh:GetSocketLocation("Head") or mesh:GetSocketLocation("head") end)
                            if h and (h.X ~= 0 or h.Y ~= 0 or h.Z ~= 0) then top = FV(h.X, h.Y, h.Z + 15) end
                            local r = nil; pcall(function() r = mesh:GetSocketLocation("root") end)
                            if r and (r.X ~= 0 or r.Y ~= 0 or r.Z ~= 0) then bot = r end
                        end
                        if not top or not bot then
                            local tO = 88; local bO = -90
                            top = top or FV(loc.X, loc.Y, loc.Z + tO)
                            bot = bot or FV(loc.X, loc.Y, loc.Z + bO)
                        end
                        local okT, tx, ty = ESP.Project(PC, top)
                        local okB, bx, by = ESP.Project(PC, bot)
                        local bd = ESP.Boxes[ks]
                        if not bd then bd = ESP.CreateWidget(canvas); if bd then ESP.Boxes[ks] = bd end end
                        if bd and FIsValid(bd.CC) then
                            if okT and okB then
                                local bh = math.max(28, math.abs(by - ty)); local bw = math.max(15, bh * 0.55)
                                local cx = (tx + bx) * 0.5; local cy = (ty + by) * 0.5
                                ESP.UpdateCorners(bd, bw, bh); bd.CS:SetPosition(FV2D(cx, cy)); ESP.ShowBox(bd)
                                local hp = p.Health or 100; local hpm = p.HealthMax or 100
                                if hpm <= 0 then hpm = 100 end; local pct = math.max(0, math.min(1, hp / hpm))
                                local hbw = 2.0; local hx = cx - bw * 0.5 - 2.5 - hbw * 0.5
                                bd.BgS:SetSize(FV2D(hbw, bh)); bd.BgS:SetPosition(FV2D(hx, cy + bh*0.5))
                                bd.HS:SetSize(FV2D(hbw, bh * pct)); bd.HS:SetPosition(FV2D(hx, cy + bh*0.5))
                                local nm = p.PlayerName or (p.GetPlayerName and p:GetPlayerName()) or "Player"
                                if bd._n ~= tostring(nm) then bd.N:SetText(tostring(nm)); bd._n = tostring(nm) end
                                bd.NS:SetPosition(FV2D(cx, cy + bh*0.5 + 4))
                                local ds = tostring(math.floor(LP:GetDistanceTo(p)/100)) .. "m"
                                if bd._d ~= ds then bd.D:SetText(ds); bd._d = ds end
                                bd.DS:SetPosition(FV2D(cx, cy + bh*0.5 + 20.5))
                            else
                                ESP.HideBox(bd)
                            end
                        end
                    end
                end
            end
        end
    end
    for k, bd in pairs(ESP.Boxes) do if not seen[k] then ESP.HideBox(bd) end end
end

function ESP.HideAll() for k, bd in pairs(ESP.Boxes) do ESP.HideBox(bd) end end

-- ============================================================
-- TOGGLE UI
-- ============================================================
local function CreateToggleUI()
    local InGameUITools = require("GameLua.Mod.BaseMod.Common.UI.InGameUITools")
    local MainUI = InGameUITools.GetMainControlBaseUI()
    if not FIsValid(MainUI) or not MainUI.CanvasPanel_0 then return end
    local Canvas = MainUI.CanvasPanel_0

    local function MakeButton(text, posY)
        local btn = CGame:NewObjectFromPath("/Script/UMG.Button", Canvas)
        if not btn then return nil, nil end
        btn:SetWidgetVisibility(UEnums.ESlateVisibility.Visible) -- Fix touch
        
        local slot = Canvas:AddChildToCanvas(btn)
        if slot then
            slot:SetAutoSize(false); slot:SetAlignment(FV2D(0, 0))
            slot:SetPosition(FV2D(30, posY)); slot:SetSize(FV2D(140, 40)); slot:SetZOrder(9999)
        end
        local txt = CGame:NewObjectFromPath("/Script/UMG.TextBlock", btn)
        if txt then
            txt:SetText(text); txt:SetJustification(1)
            if txt.Font then local f = txt.Font; f.Size = 14; txt:SetFont(f) end
            if FSLC then txt:SetColorAndOpacity(FSLC(CW)) end
            txt:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) -- Fix touch
            pcall(function() if btn.SetContent then btn:SetContent(txt) end end)
        end
        return btn, txt
    end

    local btnCombat, txtCombat = MakeButton("COMBAT / ON", 300)
    local btnESP, txtESP = MakeButton("ESP / ON", 350)

    local function UpdateUI()
        if txtCombat and FIsValid(txtCombat) then
            if FC.COMBAT.enabled then txtCombat:SetText("COMBAT / ON"); if btnCombat then btnCombat:SetBackgroundColor(FLC(0, 0.8, 0, 1)) end
            else txtCombat:SetText("COMBAT / OFF"); if btnCombat then btnCombat:SetBackgroundColor(FLC(0.8, 0, 0, 1)) end end
        end
        if txtESP and FIsValid(txtESP) then
            if FC.ESP.enabled then txtESP:SetText("ESP / ON"); if btnESP then btnESP:SetBackgroundColor(FLC(0, 0.8, 0, 1)) end
            else txtESP:SetText("ESP / OFF"); if btnESP then btnESP:SetBackgroundColor(FLC(0.8, 0, 0, 1)) end end
        end
    end
    UpdateUI()

    if btnCombat and btnCombat.OnClicked then
        btnCombat.OnClicked:Add(function()
            FC.COMBAT.enabled = not FC.COMBAT.enabled
            FC.AIMBOT.enabled = FC.COMBAT.enabled; FC.IPAD.enabled = FC.COMBAT.enabled
            FC.NORECOIL.enabled = FC.COMBAT.enabled; FC.MAGIC_HEAD.enabled = FC.COMBAT.enabled; FC.FULL_BODY.enabled = FC.COMBAT.enabled
            UpdateUI()
            if not FC.COMBAT.enabled then pcall(ApplyiPadFOV) end -- Fix reset FOV instantly
        end)
    end
    if btnESP and btnESP.OnClicked then
        btnESP.OnClicked:Add(function()
            FC.ESP.enabled = not FC.ESP.enabled
            ESP.bActive = FC.ESP.enabled
            if not ESP.bActive then ESP.HideAll() end
            UpdateUI()
        end)
    end
end

-- ============================================================
-- MAIN LOOP STARTER
-- ============================================================
local function StartAllFeatures()
    local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
    if not FIsValid(pc) or not pc.AddGameTimer then
        pcall(function() require("common.time_ticker").AddTimerOnce(1.0, StartAllFeatures) end)
        return
    end

    pc.__FeaturesStarted = pc.__FeaturesStarted or {}
    if not pc.__FeaturesStarted.ui then pc.__FeaturesStarted.ui = true; pcall(CreateToggleUI) end
    if not IsInFightingStatus() then pcall(function() require("common.time_ticker").AddTimerOnce(1.0, StartAllFeatures) end); return end

    if not pc.__FeaturesStarted.aimbot then
        pc.__FeaturesStarted.aimbot = true
        pc:AddGameTimer(0.2, true, function() if FC.COMBAT.enabled then pcall(ApplyAimbot); pcall(ApplyNoRecoil) end end)
    end
    if not pc.__FeaturesStarted.ipad then
        pc.__FeaturesStarted.ipad = true
        pc:AddGameTimer(0.5, true, function() pcall(ApplyiPadFOV) end)
    end
    if not pc.__FeaturesStarted.magic then
        pc.__FeaturesStarted.magic = true
        pc:AddGameTimer(0.5, true, function() if FC.COMBAT.enabled then pcall(EnlargeHead); pcall(ApplyDamage); pcall(HookFullBody) end end)
    end
    if not pc.__FeaturesStarted.esp then
        pc.__FeaturesStarted.esp = true
        pc:AddGameTimer(0.03, true, function() if FC.ESP.enabled then pcall(ESP.Update) end end)
    end
end

pcall(StartAllFeatures)