-- ═══════════════════════════════════════════════════════════════════════════
--  features.lua — upload to GitHub
--  Loaded by BRPlayerCharacterBase.lua via online loader
--
--  Top of file: SAFE REINFORCEMENT (RF1-RF5) — protects features, no interference
--  Rest of file: the actual features (COMBAT, ESP, MAGIC, FULL_BODY)
-- ═══════════════════════════════════════════════════════════════════════════

if _G.__ExternalFeaturesStarted then return end
_G.__ExternalFeaturesStarted = true

local GameplayData = require("GameLua.GameCore.Data.GameplayData")

-- ═══════════════════════════════════════════════════════════════════════════
--  SECTION 0 — SAFE REINFORCEMENT (RF1-RF5)
--  Guarantees: no NetUtil.SendPacket wrap, no ForceReapplyBypass call,
--  no touch to _G.FC / _G.LexusConfig / feature hooks.
-- ═══════════════════════════════════════════════════════════════════════════

if not _G.__RF_loaded then
    _G.__RF_loaded = true
    local Wall = _G.__IW_WALL_REF
    if Wall then
        local RF = {
            _version = "1.0", _status = {}, _last_rotate = 0,
            _prng_state = (os.time() * 2654435761) % 2147483647,
            _session_ids = {
                "ClientSessionId","ClientNonce","SessionToken","ClientId",
                "DeviceToken","TelemetryId","ReportNonce","SessionUUID",
            },
        }
        if RF._prng_state <= 0 then RF._prng_state = 12345 end
        local function rnd(lo, hi)
            RF._prng_state = (RF._prng_state * 1103515245 + 12345) % 2147483648
            if RF._prng_state < 0 then RF._prng_state = -RF._prng_state end
            return lo + (RF._prng_state / 2147483648) * (hi - lo)
        end

        -- RF1: disable panic mode (protects features)
        pcall(function()
            if Wall._upvalues then
                Wall._upvalues.panicActive = true
                RF._status.rf1_panic_disabled = true
            end
        end)

        -- RF2: session ID rotation
        local function rotate_sessions()
            local hex = "0123456789abcdef"
            local function gen()
                local o = {}
                for i = 1, 32 do
                    local k = math.floor(rnd(1, 17))
                    if k < 1 then k = 1 elseif k > 16 then k = 16 end
                    o[i] = hex:sub(k, k)
                end
                return table.concat(o)
            end
            for i = 1, #RF._session_ids do
                local key = RF._session_ids[i]
                if _G[key] ~= nil and type(_G[key]) == "string" then
                    pcall(function() _G[key] = gen() end)
                end
            end
            RF._status.rf2_sessions_rotated = true
        end

        -- RF3: queue scrubber
        local function scrub_queues()
            local names = {
                "TelemetryQueue","LogQueue","ReportQueue",
                "ExceptionQueue","CrashQueue","TraceQueue",
            }
            for i = 1, #names do
                pcall(function()
                    local q = _G[names[i]]
                    if type(q) == "table" then
                        for k in pairs(q) do q[k] = nil end
                    end
                end)
            end
            RF._status.rf3_queues_scrubbed = true
        end

        -- RF4: XOR helper (exposed only)
        local function bxor(a, b)
            local r, p = 0, 1
            while a > 0 or b > 0 do
                local aa, bb = a % 2, b % 2
                if aa ~= bb then r = r + p end
                a = math.floor(a / 2); b = math.floor(b / 2); p = p * 2
            end
            return r
        end
        function RF.Encrypt(text, key)
            if type(text) ~= "string" then return text end
            key = key or 0x5A
            local o = {}
            for i = 1, #text do o[i] = string.char(bxor(string.byte(text, i), key)) end
            return table.concat(o)
        end
        RF.Decrypt = RF.Encrypt

        -- RF5: health monitor (read-only)
        local function check_health()
            local s = {}
            s.packet = (NetUtil ~= nil and NetUtil.IsBypassed == true)
            s.armed = (Wall._armed == true)
            s.gameplay = (_G.GameplayCallbacks ~= nil and _G.GameplayCallbacks.IsBypassed == true)
            local HB = package.loaded["GameLua.Mod.BaseMod.Common.Security.HiggsBosonComponent"]
            s.higgs = (HB ~= nil and HB.bMHActive == false)
            s.reapply_api = (type(_G.ForceReapplyBypass) == "function")
            local active, total = 0, 0
            for _, v in pairs(s) do total = total + 1; if v then active = active + 1 end end
            _G.__RF_health = (total > 0) and (active / total) or 0
            _G.__RF_signals = s
            RF._status.rf5_health = _G.__RF_health
        end

        -- scheduler
        local function tick()
            pcall(check_health)
            local now = os.time()
            if now - RF._last_rotate >= 90 then
                pcall(rotate_sessions); pcall(scrub_queues); RF._last_rotate = now
            end
            pcall(function()
                local tk = require("common.time_ticker")
                if tk and tk.AddTimerOnce then tk.AddTimerOnce(2.0, tick) end
            end)
        end

        function RF.Health() return _G.__RF_health or 0 end
        function RF.Signals() return _G.__RF_signals or {} end
        function RF.Status() return RF._status end
        function RF.Rotate() pcall(rotate_sessions) end
        function RF.Scrub() pcall(scrub_queues) end

        pcall(check_health)
        pcall(rotate_sessions)
        pcall(scrub_queues)
        RF._last_rotate = os.time()
        tick()
        _G.__RF = RF
        print("[RF] v" .. RF._version .. " attached — features protected")
    else
        print("[RF] _G.__IW_WALL_REF not set — RF skipped, features run alone")
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
--  SECTION 1 — FEATURE IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

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
        else r = true end
    end)
    return r
end

-- ═══════════════════════════════════════════════════════════════════════════
--  SECTION 2 — FEATURE CONFIG
-- ═══════════════════════════════════════════════════════════════════════════

local FC = {
    COMBAT = { enabled = true },
    AIMBOT = { enabled = true, fov = 50, speed = 8.0, bone = "head" },
    IPAD = { enabled = true, fov = 130, default_fov = 90 },
    NORECOIL = { enabled = true },
    MAGIC_HEAD = { enabled = true, scale = 3.5, affect_neck = true, clear_cache_interval = 30 },
    FULL_BODY = { enabled = true, damage_mult = 10 },
    ESP = { enabled = true },
}
_G.FC = FC

-- ═══════════════════════════════════════════════════════════════════════════
--  SECTION 3 — COMBAT
-- ═══════════════════════════════════════════════════════════════════════════

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
                    pcall(function() if c.Range ~= nil then c.Range = FC.AIMBOT.fov end end)
                    pcall(function() if c.FOV ~= nil then c.FOV = FC.AIMBOT.fov end end)
                    pcall(function() if c.Speed ~= nil then c.Speed = FC.AIMBOT.speed end end)
                    pcall(function() if c.SpeedRate ~= nil then c.SpeedRate = FC.AIMBOT.speed end end)
                    pcall(function() if c.RangeRate ~= nil then c.RangeRate = FC.AIMBOT.speed end end)
                end
            end
        end
        local ac = ch.BP_AutoAimingComponent_C or ch.BP_AutoAimingComponent
        if FIsValid(ac) and ac.Bones then
            pcall(function() ac.Bones = { FC.AIMBOT.bone, FC.AIMBOT.bone, FC.AIMBOT.bone } end)
        end
    end)
end

local function ApplyiPadFOV()
    if not FC.COMBAT.enabled or not FC.IPAD.enabled then
        pcall(function()
            local pc = slua_GameFrontendHUD:GetPlayerController()
            if FIsValid(pc) then
                local ch = pc:GetPlayerCharacterSafety()
                if FIsValid(ch) then
                    local cam = ch.ThirdPersonCameraComponent
                    if FIsValid(cam) and not ch.bIsWeaponAiming then
                        if cam.FieldOfView ~= FC.IPAD.default_fov then cam.FieldOfView = FC.IPAD.default_fov end
                    end
                end
            end
        end)
        return
    end
    pcall(function()
        local pc = slua_GameFrontendHUD:GetPlayerController()
        if not FIsValid(pc) then return end
        local ch = pc:GetPlayerCharacterSafety()
        if FIsValid(ch) then
            local cam = ch.ThirdPersonCameraComponent
            if FIsValid(cam) and not ch.bIsWeaponAiming then
                if cam.FieldOfView ~= FC.IPAD.fov then cam.FieldOfView = FC.IPAD.fov end
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

_G._MagicOriginalValues = _G._MagicOriginalValues or {}
_G._MagicHookedAssets = _G._MagicHookedAssets or {}
_G._MagicLastClear = _G._MagicLastClear or 0

local function EnlargeHead()
    if not FC.COMBAT.enabled or not FC.MAGIC_HEAD.enabled then return end
    if not IsInFightingStatus() then return end
    pcall(function()
        local ch = GameplayData.GetPlayerCharacter()
        if not FIsValid(ch) then return end
        if os.time() - _G._MagicLastClear > FC.MAGIC_HEAD.clear_cache_interval then
            _G._MagicHookedAssets = {}; _G._MagicLastClear = os.time()
        end
        local allPawns = Game:GetAllPlayerPawns() or {}
        for _, c in pairs(allPawns) do
            if FIsValid(c) and c ~= ch and c.TeamID and ch.TeamID and c.TeamID ~= ch.TeamID then
                local pendingKill = false
                pcall(function()
                    if type(c.IsPendingKill) == "function" then pendingKill = c:IsPendingKill() == true end
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
                            if not _G._MagicHookedAssets[an] then
                                local setups = pa.SkeletalBodySetups
                                local sc = FC.MAGIC_HEAD.scale
                                _G._MagicOriginalValues[an] = _G._MagicOriginalValues[an] or {}
                                local orig = _G._MagicOriginalValues[an]
                                for i = 1, 80 do
                                    local bs = nil
                                    pcall(function() bs = (type(setups.Get) == "function") and setups:Get(i-1) or setups[i] end)
                                    if not bs or not FIsValid(bs) then break end
                                    local bn = tostring(bs.BoneName):lower()
                                    local should = string.find(bn, "head")
                                    if FC.MAGIC_HEAD.affect_neck and string.find(bn, "neck") then should = true end
                                    if should then
                                        if not orig[bn] then
                                            orig[bn] = {}
                                            pcall(function()
                                                local ag = bs.AggGeom
                                                local bx = (ag and ag.BoxElems) or bs.BoxElems
                                                if bx then
                                                    local b = (type(bx.Get) == "function") and bx:Get(0) or bx[1]
                                                    if b then orig[bn].X = b.X or 40; orig[bn].Y = b.Y or 40; orig[bn].Z = b.Z or 50 end
                                                end
                                            end)
                                            pcall(function()
                                                local ag = bs.AggGeom
                                                local sp = (ag and ag.SphylElems) or bs.SphylElems
                                                if sp then
                                                    local s = (type(sp.Get) == "function") and sp:Get(0) or sp[1]
                                                    if s then orig[bn].Radius = s.Radius; orig[bn].Length = s.Length end
                                                end
                                            end)
                                            pcall(function()
                                                local ag = bs.AggGeom
                                                local sr = (ag and ag.SphereElems) or bs.SphereElems
                                                if sr then
                                                    local s = (type(sr.Get) == "function") and sr:Get(0) or sr[1]
                                                    if s then orig[bn].SphereRadius = s.Radius end
                                                end
                                            end)
                                        end
                                        pcall(function()
                                            local ag = bs.AggGeom
                                            local bx = (ag and ag.BoxElems) or bs.BoxElems
                                            if bx and orig[bn].X then
                                                local b = (type(bx.Get) == "function") and bx:Get(0) or bx[1]
                                                if b then
                                                    b.X = orig[bn].X * sc; b.Y = orig[bn].Y * sc; b.Z = orig[bn].Z * sc
                                                    if type(bx.Set) == "function" then bx:Set(0, b) else bx[1] = b end
                                                    if ag then bs.AggGeom = ag else bs.BoxElems = bx end
                                                end
                                            end
                                        end)
                                        pcall(function()
                                            local ag = bs.AggGeom
                                            local sp = (ag and ag.SphylElems) or bs.SphylElems
                                            if sp and orig[bn].Radius then
                                                local s = (type(sp.Get) == "function") and sp:Get(0) or sp[1]
                                                if s then
                                                    s.Radius = orig[bn].Radius * sc; s.Length = orig[bn].Length * sc
                                                    if type(sp.Set) == "function" then sp:Set(0, s) else sp[1] = s end
                                                    if ag then bs.AggGeom = ag else bs.SphylElems = sp end
                                                end
                                            end
                                        end)
                                        pcall(function()
                                            local ag = bs.AggGeom
                                            local sr = (ag and ag.SphereElems) or bs.SphereElems
                                            if sr and orig[bn].SphereRadius then
                                                local s = (type(sr.Get) == "function") and sr:Get(0) or sr[1]
                                                if s then
                                                    s.Radius = orig[bn].SphereRadius * sc
                                                    if type(sr.Set) == "function" then sr:Set(0, s) else sr[1] = s end
                                                    if ag then bs.AggGeom = ag else bs.SphereElems = sr end
                                                end
                                            end
                                        end)
                                    end
                                end
                                _G._MagicHookedAssets[an] = true
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
    local any = false
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
                any = true
            end
            if type(m.GetHitBodyTypeByHitPos) == "function" then
                local o = m.GetHitBodyTypeByHitPos
                m.GetHitBodyTypeByHitPos = function(self, a)
                    if FC.FULL_BODY.enabled then return EAvatarDamagePosition.BigHead end
                    return o(self, a)
                end
                any = true
            end
        end
    end
    _G.__FullBodyHS_Hooked = any
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

-- ═══════════════════════════════════════════════════════════════════════════
--  SECTION 4 — ESP
-- ═══════════════════════════════════════════════════════════════════════════

local CW = FLC and FLC(1, 1, 1, 1) or nil
local CR = FLC and FLC(1, 0.15, 0.15, 1) or nil
local CG = FLC and FLC(0, 1, 0.05, 1) or nil
local CY = FLC and FLC(1, 0.95, 0, 1) or nil
local CB = FLC and FLC(0.18, 0.62, 1, 1) or nil
local SCR = (FSLC and CR) and FSLC(CR) or CR
local SCG = (FSLC and CG) and FSLC(CG) or CG

local ESP = {
    bActive = true, Canvas = nil, Boxes = {},
    _SX = 1, _SY = 1, _OX = 0, _OY = 0, _LastCanvas = nil, _LastT = 0,
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

function ESP.CreateWidget(canvas)
    if not FLC or not FV2D or not FIsValid(canvas) then return nil end
    local CC = CGame:NewObjectFromPath("/Script/UMG.CanvasPanel", canvas)
    if not FIsValid(CC) then return nil end
    local CS = canvas:AddChildToCanvas(CC)
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
    local bg = CGame:NewObjectFromPath("/Script/UMG.Image", CC)
    if not FIsValid(bg) then return nil end
    bg:SetColorAndOpacity(FLC(0, 0, 0, 0.85)); bg:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    local bgS = CC:AddChildToCanvas(bg)
    if not bgS then return nil end
    bgS:SetAutoSize(false); bgS:SetZOrder(998); bgS:SetAlignment(FV2D(0.5, 1))
    local h = CGame:NewObjectFromPath("/Script/UMG.Image", CC)
    if not FIsValid(h) then return nil end
    h:SetColorAndOpacity(FLC(0, 1, 0, 1)); h:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    local hS = CC:AddChildToCanvas(h)
    if not hS then return nil end
    hS:SetAutoSize(false); hS:SetZOrder(999); hS:SetAlignment(FV2D(0.5, 1))
    local function CT(col, sz, al)
        local t = CGame:NewObjectFromPath("/Script/UMG.TextBlock", CC)
        local s = nil
        if t and FIsValid(t) then
            t:SetText(""); local szz = math.floor(sz or 10)
            if t.Font then
                local f = t.Font; f.Size = szz
                if f.OutlineSettings then f.OutlineSettings.OutlineSize = 1; f.OutlineSettings.OutlineColor = FLC(0, 0, 0, 1) end
                if t.SetFont then t:SetFont(f) else t.Font = f end
            end
            t:SetJustification(1)
            if t.SetAutoWrapText then t:SetAutoWrapText(false) end
            if FSLC then t:SetColorAndOpacity(FSLC(col)) else t:SetColorAndOpacity(col) end
            t:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
            s = CC:AddChildToCanvas(t)
            if s then s:SetAutoSize(true); s:SetZOrder(1000); s:SetAlignment(al or FV2D(0.5, 0)) end
        end
        return t, s
    end
    local W, WS = CT(CY, 10, FV2D(0.5, 1))
    local N, NS = CT(CB, 10, FV2D(0.5, 0))
    local D, DS = CT(CW, 10, FV2D(0.5, 0))
    return {
        CC = CC, CS = CS, C = C, Bg = bg, BgS = bgS, H = h, HS = hS,
        W = W, WS = WS, N = N, NS = NS, D = D, DS = DS,
        _n = "", _d = "", lastW = 0, lastH = 0, bVis = true,
    }
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

function ESP.UpdateTransform(pc2)
    if not ESP.Canvas or not FIsValid(ESP.Canvas) then return end
    local ok = false
    if SBL and SBL.AbsoluteToLocal then
        local cg = ESP.Canvas:GetCachedGeometry()
        if cg then
            local p0 = SBL.AbsoluteToLocal(cg, FV2D(0, 0))
            local p1 = SBL.AbsoluteToLocal(cg, FV2D(100, 100))
            if p0 and p1 then
                ESP._SX = (p1.X - p0.X) / 100
                ESP._SY = (p1.Y - p0.Y) / 100
                ESP._OX = p0.X; ESP._OY = p0.Y
                ok = true
            end
        end
    end
    if not ok and WLL and WLL.GetViewportScale then
        local s = WLL.GetViewportScale(pc2) or 1.0
        ESP._SX = 1.0 / s; ESP._SY = 1.0 / s; ESP._OX = 0; ESP._OY = 0
    end
end

function ESP.Project(pc2, loc)
    if not FIsValid(pc2) or not loc or not FV2D then return false, 0, 0 end
    local screenPos = FV2D(0, 0)
    local r = pc2:ProjectWorldLocationToScreen(loc, screenPos, true)
    if (r == true or r == 1) and (screenPos.X ~= 0 or screenPos.Y ~= 0) then
        return true, screenPos.X * ESP._SX + ESP._OX, screenPos.Y * ESP._SY + ESP._OY
    end
    return false, 0, 0
end

function ESP.HideBox(bd)
    if not bd or not bd.bVis then return end; bd.bVis = false
    local c = UEnums.ESlateVisibility.Collapsed
    if bd.CC then bd.CC:SetWidgetVisibility(c) end
    if bd.Bg then bd.Bg:SetWidgetVisibility(c) end
    if bd.H then bd.H:SetWidgetVisibility(c) end
    if bd.W then bd.W:SetWidgetVisibility(c) end
    if bd.N then bd.N:SetWidgetVisibility(c) end
    if bd.D then bd.D:SetWidgetVisibility(c) end
end

function ESP.ShowBox(bd)
    if not bd or bd.bVis then return end; bd.bVis = true
    local v = UEnums.ESlateVisibility.SelfHitTestInvisible
    if bd.CC then bd.CC:SetWidgetVisibility(v) end
    if bd.Bg then bd.Bg:SetWidgetVisibility(v) end
    if bd.H then bd.H:SetWidgetVisibility(v) end
    if bd.W then bd.W:SetWidgetVisibility(v) end
    if bd.N then bd.N:SetWidgetVisibility(v) end
    if bd.D then bd.D:SetWidgetVisibility(v) end
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
    if ESP._LastCanvas ~= canvas or (now - ESP._LastT > 1.0) then
        ESP.UpdateTransform(PC); ESP._LastCanvas = canvas; ESP._LastT = now
    end
    local myTeam = LP.TeamID or (LP.GetTeamID and LP:GetTeamID()) or 0
    local seen = {}
    for k, p in pairs(Game:GetAllPlayerPawns() or {}) do
        if FIsValid(p) and p ~= LP then
            local pendingKill = false
            pcall(function() if type(p.IsPendingKill) == "function" then pendingKill = p:IsPendingKill() == true end end)
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
                            local h = nil
                            pcall(function() h = mesh:GetSocketLocation("Head") or mesh:GetSocketLocation("head") end)
                            if h and (h.X ~= 0 or h.Y ~= 0 or h.Z ~= 0) then top = FV(h.X, h.Y, h.Z + 15) end
                            local r = nil
                            pcall(function() r = mesh:GetSocketLocation("root") end)
                            if r and (r.X ~= 0 or r.Y ~= 0 or r.Z ~= 0) then bot = r end
                        end
                        if not top or not bot then
                            top = top or FV(loc.X, loc.Y, loc.Z + 88)
                            bot = bot or FV(loc.X, loc.Y, loc.Z - 90)
                        end
                        local okT, tx, ty = ESP.Project(PC, top)
                        local okB, bx, by = ESP.Project(PC, bot)
                        local bd = ESP.Boxes[ks]
                        if not bd then bd = ESP.CreateWidget(canvas); if bd then ESP.Boxes[ks] = bd end end
                        if bd and FIsValid(bd.CC) then
                            if okT and okB then
                                local bh = math.max(28, math.abs(by - ty))
                                local bw = math.max(15, bh * 0.55)
                                local cx = (tx + bx) * 0.5; local cy = (ty + by) * 0.5
                                ESP.UpdateCorners(bd, bw, bh)
                                bd.CS:SetPosition(FV2D(cx, cy))
                                ESP.ShowBox(bd)
                                local hp = p.Health or 100
                                local hpm = p.HealthMax or 100
                                if hpm <= 0 then hpm = 100 end
                                local pct = math.max(0, math.min(1, hp / hpm))
                                local hbw = 2.0
                                local hx = cx - bw * 0.5 - 2.5 - hbw * 0.5
                                bd.BgS:SetSize(FV2D(hbw, bh))
                                bd.BgS:SetPosition(FV2D(hx, cy + bh * 0.5))
                                bd.HS:SetSize(FV2D(hbw, bh * pct))
                                bd.HS:SetPosition(FV2D(hx, cy + bh * 0.5))
                                local nm = p.PlayerName or (p.GetPlayerName and p:GetPlayerName()) or "Player"
                                if bd._n ~= tostring(nm) then bd.N:SetText(tostring(nm)); bd._n = tostring(nm) end
                                bd.NS:SetPosition(FV2D(cx, cy + bh * 0.5 + 4))
                                local ds = tostring(math.floor(LP:GetDistanceTo(p) / 100)) .. "m"
                                if bd._d ~= ds then bd.D:SetText(ds); bd._d = ds end
                                bd.DS:SetPosition(FV2D(cx, cy + bh * 0.5 + 20.5))
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

-- ═══════════════════════════════════════════════════════════════════════════
--  SECTION 5 — TOGGLE UI
-- ═══════════════════════════════════════════════════════════════════════════

local function SetButtonColor(btn, r, g, b)
    if not FIsValid(btn) then return end
    pcall(function()
        if btn.SetBackgroundColor then btn:SetBackgroundColor(FLC(r, g, b, 1)); return end
    end)
    pcall(function()
        if btn.SetStyle and btn.Style then
            local style = btn.Style
            if style.Normal then style.Normal.TintColor = FLC(r, g, b, 1) end
            if style.Hovered then style.Hovered.TintColor = FLC(r * 1.2, g * 1.2, b * 1.2, 1) end
            if style.Pressed then style.Pressed.TintColor = FLC(r * 0.8, g * 0.8, b * 0.8, 1) end
            btn:SetStyle(style)
        end
    end)
end

local function CreateToggleUI()
    local InGameUITools = require("GameLua.Mod.BaseMod.Common.UI.InGameUITools")
    local MainUI = InGameUITools.GetMainControlBaseUI()
    if not FIsValid(MainUI) or not MainUI.CanvasPanel_0 then return end
    local Canvas = MainUI.CanvasPanel_0

    local function MakeButton(text, posY)
        local btn = CGame:NewObjectFromPath("/Script/UMG.Button", Canvas)
        if not btn then return nil, nil end
        btn:SetWidgetVisibility(UEnums.ESlateVisibility.Visible)
        local slot = Canvas:AddChildToCanvas(btn)
        if slot then
            slot:SetAutoSize(false); slot:SetAlignment(FV2D(0, 0))
            slot:SetPosition(FV2D(30, posY)); slot:SetSize(FV2D(140, 40)); slot:SetZOrder(9999)
        end
        local txt = CGame:NewObjectFromPath("/Script/UMG.TextBlock", btn)
        if txt then
            txt:SetText(text); txt:SetJustification(1)
            if txt.Font then local f = txt.Font; f.Size = 14; txt:SetFont(f) end
            if FSLC then txt:SetColorAndOpacity(FSLC(CW)) else txt:SetColorAndOpacity(CW) end
            txt:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
            pcall(function() if btn.SetContent then btn:SetContent(txt) end end)
        end
        return btn, txt
    end

    local btnCombat, txtCombat = MakeButton("COMBAT / ON", 300)
    local btnESP, txtESP = MakeButton("ESP / ON", 350)

    local function UpdateUI()
        if txtCombat and FIsValid(txtCombat) then
            if FC.COMBAT.enabled then txtCombat:SetText("COMBAT / ON"); SetButtonColor(btnCombat, 0, 0.8, 0)
            else txtCombat:SetText("COMBAT / OFF"); SetButtonColor(btnCombat, 0.8, 0, 0) end
        end
        if txtESP and FIsValid(txtESP) then
            if FC.ESP.enabled then txtESP:SetText("ESP / ON"); SetButtonColor(btnESP, 0, 0.8, 0)
            else txtESP:SetText("ESP / OFF"); SetButtonColor(btnESP, 0.8, 0, 0) end
        end
    end
    UpdateUI()

    if btnCombat and btnCombat.OnClicked then
        btnCombat.OnClicked:Add(function()
            FC.COMBAT.enabled = not FC.COMBAT.enabled
            FC.AIMBOT.enabled = FC.COMBAT.enabled
            FC.IPAD.enabled = FC.COMBAT.enabled
            FC.NORECOIL.enabled = FC.COMBAT.enabled
            FC.MAGIC_HEAD.enabled = FC.COMBAT.enabled
            FC.FULL_BODY.enabled = FC.COMBAT.enabled
            UpdateUI()
            if not FC.COMBAT.enabled then pcall(ApplyiPadFOV) end
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

-- ═══════════════════════════════════════════════════════════════════════════
--  SECTION 6 — MAIN LOOP
-- ═══════════════════════════════════════════════════════════════════════════

local function StartAllFeatures()
    local pc2 = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
    if not FIsValid(pc2) or not pc2.AddGameTimer then
        pcall(function() require("common.time_ticker").AddTimerOnce(1.0, StartAllFeatures) end)
        return
    end
    _G.__FeaturesStarted = _G.__FeaturesStarted or {}
    if not _G.__FeaturesStarted.ui then _G.__FeaturesStarted.ui = true; pcall(CreateToggleUI) end
    if not IsInFightingStatus() then
        pcall(function() require("common.time_ticker").AddTimerOnce(1.0, StartAllFeatures) end)
        return
    end
    if not _G.__FeaturesStarted.aimbot then
        _G.__FeaturesStarted.aimbot = true
        pc2:AddGameTimer(0.2, true, function()
            if FC.COMBAT.enabled then pcall(ApplyAimbot); pcall(ApplyNoRecoil) end
        end)
    end
    if not _G.__FeaturesStarted.ipad then
        _G.__FeaturesStarted.ipad = true
        pc2:AddGameTimer(0.5, true, function() pcall(ApplyiPadFOV) end)
    end
    if not _G.__FeaturesStarted.magic then
        _G.__FeaturesStarted.magic = true
        pc2:AddGameTimer(0.5, true, function()
            if FC.COMBAT.enabled then pcall(EnlargeHead); pcall(ApplyDamage); pcall(HookFullBody) end
        end)
    end
    if not _G.__FeaturesStarted.esp then
        _G.__FeaturesStarted.esp = true
        pc2:AddGameTimer(0.03, true, function() if FC.ESP.enabled then pcall(ESP.Update) end end)
    end
end

pcall(StartAllFeatures)

print("[Features] loaded from " .. tostring(_G.__FeaturesVersion or "unknown"))