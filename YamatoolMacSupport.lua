----------------------------------------------------------------
-- BRM5 ULTIMATE v26.0
-- Fixed: ModeLbl/AmmoLbl nil race (GUI created before tasks)
-- Fixed: RenderStepped zero raycasts (cache read-only on render)
-- Fixed: VisScoreCache refresh moved to background tasks only
-- Optimized: locked target refreshed at 30Hz, all targets at 5Hz
----------------------------------------------------------------
local Rayfield    = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

-- Window created immediately so Rayfield loads before any RunService loops
local Window = Rayfield:CreateWindow({
    Name="BRM5 ULTIMATE v36.0", LoadingTitle="BRM5 Combat Suite",
    LoadingSubtitle="v28.0 — Prediction overhauled: bullet speed, gravity, accel, dir change, convergence gate",
    ConfigurationSaving={Enabled=false},
})
local UIS         = game:GetService("UserInputService")
local RunService  = game:GetService("RunService")
local Players     = game:GetService("Players")
local VIM         = game:GetService("VirtualInputManager")
local CoreGui     = game:GetService("CoreGui")
local Camera      = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer


----------------------------------------------------------------
-- MAC / CROSS-EXECUTOR COMPATIBILITY
-- Wraps mouse functions so script works on Mac executors
-- (Synapse X, Script-Ware M, Hydrogen, etc.)
----------------------------------------------------------------
local function MoveRel(dx, dy)
    if mousemoverel then
        mousemoverel(dx, dy)
    elseif Mouse and Mouse.move then
        Mouse:move(dx, dy)
    end
end

local function Click()
    if mouse1click then
        Click()
    elseif Mouse and Mouse.click then
        pcall(function() Mouse:click() end)
    else
        pcall(function()
            VIM:SendMouseButtonEvent(0, 0, 0, true,  game, 1)
            VIM:SendMouseButtonEvent(0, 0, 0, false, game, 1)
        end)
    end
end

local function Press()
    if mouse1press then
        Press()
    elseif Mouse and Mouse.down then
        pcall(function() Mouse:down() end)
    else
        pcall(function() VIM:SendMouseButtonEvent(0, 0, 0, true, game, 1) end)
    end
end

local function Release()
    if mouse1release then
        Release()
    elseif Mouse and Mouse.up then
        pcall(function() Mouse:up() end)
    else
        pcall(function() VIM:SendMouseButtonEvent(0, 0, 0, false, game, 1) end)
    end
end

----------------------------------------------------------------
-- CLEANUP
----------------------------------------------------------------
for _, v in ipairs(workspace:GetDescendants()) do
    if v.Name == "ESPHighlight" then pcall(v.Destroy, v) end
end
do local old = CoreGui:FindFirstChild("BRM5_HUD")  if old then old:Destroy() end end
do local old = CoreGui:FindFirstChild("BRM5_FOV")  if old then old:Destroy() end end
do local old = CoreGui:FindFirstChild("BRM5_INFO") if old then old:Destroy() end end

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local Cfg = {
    MasterEnabled   = false,
    Esp             = true,
    Autoshoot       = false,
    NoRecoil        = true,
    HoldToAim       = true,
    AutoReload      = true,
    CrosshairTarget = true,
    Sensitivity     = 0.3,
    Smoothing       = 1.0,
    FovRadius       = 300,
    FovVisible      = true,
    HideHUD         = false,  -- hides mode/ammo bar without removing function
    StickyLock      = false,  -- never auto-switch target; only re-acquire when RMB re-pressed
    VisibleColor    = Color3.fromRGB(0, 255, 0),
    HiddenColor     = Color3.fromRGB(255, 0, 0),
    FovColor        = Color3.fromRGB(255, 255, 255),
    EspFill         = 0.6,
    EspOutline      = 0.6,
    SniperMode      = false,  -- removes range cap, tightens screen threshold
    MaxRange        = 120,    -- studs, ignored in sniper mode
    BulletSpeed     = 900,    -- studs/s: AR=900, Sniper=1500, SMG=700, Pistol=500
}

local Keys = {
    Master    = Enum.KeyCode.Z,
    Esp       = Enum.KeyCode.U,
    Autoshoot = Enum.KeyCode.P,
    NoRecoil  = Enum.KeyCode.I,
}

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------
local TargetList    = {}
local LockedTarget  = nil
local EspState      = {}
local PredState     = {}
local VisScoreCache = {}
local RMBHeld        = false
local IsFiring       = false
local LastShotFired  = 0
local IsReloading    = false
local ReloadCooldown = false
local CurrentMode    = "auto"
local AmmoLabel      = nil
local RayParams      = nil
local LastChar       = nil
local BindingKey     = nil

local FMODE = { auto=0.09, semi=0.22, burst=0.10 }

----------------------------------------------------------------
-- FIX: GUI CREATED FIRST — before any task.spawn or function
-- that references ModeLbl or AmmoLbl.
-- Previously these were created ~100 lines after their first use.
----------------------------------------------------------------
local FovGui = Instance.new("ScreenGui")
FovGui.Name="BRM5_FOV"; FovGui.ResetOnSpawn=false; FovGui.Parent=CoreGui

local FovCircle = Instance.new("Frame", FovGui)
FovCircle.BackgroundTransparency=1; FovCircle.BorderSizePixel=0; FovCircle.ZIndex=10
Instance.new("UICorner", FovCircle).CornerRadius = UDim.new(1,0)
local FovStroke = Instance.new("UIStroke", FovCircle)
FovStroke.Thickness=1.5; FovStroke.ApplyStrokeMode=Enum.ApplyStrokeMode.Border

local InfoGui = Instance.new("ScreenGui")
InfoGui.Name="BRM5_INFO"; InfoGui.ResetOnSpawn=false; InfoGui.Parent=CoreGui
local InfoFrame = Instance.new("Frame", InfoGui)
InfoFrame.Size=UDim2.new(0,160,0,44); InfoFrame.Position=UDim2.new(0,16,1,-60)
InfoFrame.BackgroundColor3=Color3.fromRGB(10,10,10); InfoFrame.BackgroundTransparency=0.4
InfoFrame.BorderSizePixel=0
Instance.new("UICorner", InfoFrame).CornerRadius=UDim.new(0,6)
local _is=Instance.new("UIStroke", InfoFrame)
_is.Color=Color3.fromRGB(70,70,70); _is.Thickness=1

local function MakeInfoLbl(text, y)
    local l = Instance.new("TextLabel", InfoFrame)
    l.Size=UDim2.new(1,-10,0,18); l.Position=UDim2.new(0,8,0,y)
    l.BackgroundTransparency=1; l.TextColor3=Color3.fromRGB(0,255,100)
    l.Text=text; l.TextSize=13; l.Font=Enum.Font.GothamBold
    l.TextXAlignment=Enum.TextXAlignment.Left
    return l
end

-- FIX: ModeLbl and AmmoLbl exist NOW, before any function references them
local ModeLbl = MakeInfoLbl("🔫 MODE: ---",  4)
local AmmoLbl = MakeInfoLbl("📦 AMMO: ---", 24)

----------------------------------------------------------------
-- RAYCAST PARAMS
----------------------------------------------------------------
local function BuildRayParams()
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    local ex = { Camera }
    local char = LocalPlayer.Character
    if char then
        table.insert(ex, char)
        local tool = char:FindFirstChildOfClass("Tool")
        if tool then table.insert(ex, tool) end
    end
    local wm = workspace:FindFirstChild("WorldModel")
    if wm then table.insert(ex, wm) end
    rp.FilterDescendantsInstances = ex
    return rp
end

local function GetRP()
    local char = LocalPlayer.Character
    if char ~= LastChar or not RayParams then
        LastChar = char; RayParams = BuildRayParams()
    end
    return RayParams
end

local function RayOrigin()
    return Camera.CFrame.Position + Camera.CFrame.LookVector * 0.5
end

----------------------------------------------------------------
-- MULTI-PART VISIBILITY SCORING
-- FIX: ComputeVisScore now ONLY called from background tasks.
-- RenderStepped reads ReadVisCache() — pure table lookup, zero raycasts.
----------------------------------------------------------------
local VIS_PARTS = {
    { name="Head",             weight=3 },
    { name="UpperTorso",       weight=3 },
    { name="Torso",            weight=3 },
    { name="RightUpperArm",    weight=1 },
    { name="LeftUpperArm",     weight=1 },
    { name="LowerTorso",       weight=2 },
    { name="HumanoidRootPart", weight=2 },
    { name="Root",             weight=2 },
    { name="RightUpperLeg",    weight=1 },
    { name="LeftUpperLeg",     weight=1 },
}
local MAX_VIS_WEIGHT = (function()
    local t = 0; for _, p in ipairs(VIS_PARTS) do t = t + p.weight end; return t
end)()

-- Always computes fresh — only called from background tasks
local function ComputeVisScore(model)
    local o  = RayOrigin()
    local rp = GetRP()
    local totalW = 0; local visW = 0
    local bestPart = nil; local bestW = 0

    for _, entry in ipairs(VIS_PARTS) do
        local part = model:FindFirstChild(entry.name)
        if part and part:IsA("BasePart") then
            totalW = totalW + entry.weight
            local ray = workspace:Raycast(o, part.Position - o, rp)
            local vis = not ray or (ray.Instance and ray.Instance:IsDescendantOf(model))
            if vis then
                visW = visW + entry.weight
                if entry.weight > bestW then bestPart = part; bestW = entry.weight end
            end
        end
    end

    local score = totalW > 0 and (visW / totalW) or 0
    VisScoreCache[model] = { score=score, bestPart=bestPart, t=tick() }
    return score, bestPart
end

-- FIX: Pure cache read — NO raycasts. Called from RenderStepped.
local function ReadVisCache(model)
    local c = VisScoreCache[model]
    if c then return c.score, c.bestPart end
    return 0, nil
end

----------------------------------------------------------------
-- BACKGROUND VIS REFRESH TASKS
-- Task A (30Hz): refreshes ONLY the locked target — high priority
-- Task B (5Hz):  refreshes ALL targets for ESP colors
-- RenderStepped never calls ComputeVisScore — reads cache only.
----------------------------------------------------------------
task.spawn(function()
    while true do
        task.wait(0.033)  -- 30Hz
        local t = LockedTarget
        if t and t.Parent then
            ComputeVisScore(t)
        end
    end
end)

task.spawn(function()
    while true do
        task.wait(0.2)   -- 5Hz — ESP color updates
        for _, e in ipairs(TargetList) do
            if e and e.Parent then
                ComputeVisScore(e)
            end
            task.wait()  -- yield between enemies to spread cost over frames
        end
    end
end)

----------------------------------------------------------------
-- TARGET VALIDITY
----------------------------------------------------------------
local function IsDead(model)
    if not model or not model.Parent then return true end
    local h = model:FindFirstChildOfClass("Humanoid")
    if not h or h.Health <= 0 then return true end
    return not (model:FindFirstChild("Root") or model:FindFirstChild("HumanoidRootPart"))
end

local function IsPlayerChar(model)
    for _, p in ipairs(Players:GetPlayers()) do
        if model == p.Character then return true end
    end
    return false
end

local function IsValid(model)
    if not model or not model.Parent then return false end
    if IsDead(model) or IsPlayerChar(model) then return false end
    return (model:FindFirstChild("Torso") or model:FindFirstChild("UpperTorso")
         or model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Root")) ~= nil
end

local function InFront(pos)
    local d = pos - Camera.CFrame.Position
    return d.Magnitude < 0.001 or d.Unit:Dot(Camera.CFrame.LookVector) > -0.3
end

-- FIX: reads cache only, no raycasts
local function BestAimPart(model)
    local _, best = ReadVisCache(model)
    if best then return best, true end
    for _, entry in ipairs(VIS_PARTS) do
        local p = model:FindFirstChild(entry.name)
        if p and p:IsA("BasePart") then return p, false end
    end
    return nil, false
end

----------------------------------------------------------------
-- TARGET SCORING (reads cache — no raycasts)
----------------------------------------------------------------
local function ScoreTarget(model, screenDist, worldDist)
    local visScore = ReadVisCache(model)
    local distScore   = math.clamp(1 - (worldDist / 200), 0, 1)
    local screenScore = math.clamp(1 - (screenDist / Cfg.FovRadius), 0, 1)
    return (visScore * 0.55) + (distScore * 0.25) + (screenScore * 0.20)
end

----------------------------------------------------------------
-- PREDICTION (v28 — fixed all 5 issues)
--
-- FIX 1: Bullet speed uses Cfg.BulletSpeed (was hardcoded 900)
-- FIX 2: Acceleration now INCREASES lead (was dampening it — backwards)
-- FIX 3: Gravity compensation added for Y axis (9.81 * travel^2 * 0.5)
-- FIX 4: Direction change rate factored in via angular velocity of vel
-- FIX 5: Lead only applied when aim is already converging on target
--        (checks crosshair is within FovRadius so we don't lead a
--         target we haven't caught up to yet)
----------------------------------------------------------------
local function Predict(model, part)
    local root = model:FindFirstChild("HumanoidRootPart")
             or model:FindFirstChild("Root") or part
    if not root then return Vector3.zero end

    local vel = root.AssemblyLinearVelocity
    -- Only predict if target is actually moving meaningfully
    if vel.Magnitude < 0.5 then return Vector3.zero end

    local now  = tick()
    local prev = PredState[model]
    local dt   = prev and math.clamp(now - prev.t, 0.001, 0.05) or 0.016

    -- FIX 4: Track direction change rate (how fast velocity vector rotates)
    -- If target is circle-strafing, their vel direction changes fast
    -- We extrapolate the direction change to aim ahead of the arc
    local accel      = Vector3.zero
    local dirChange  = Vector3.zero
    if prev then
        accel = (vel - prev.vel) / dt
        -- Angular rate of velocity direction change
        local prevDir = prev.vel.Magnitude > 0.1 and prev.vel.Unit or vel.Unit
        local curDir  = vel.Magnitude > 0.1 and vel.Unit or prevDir
        dirChange = (curDir - prevDir) / dt  -- how fast direction is rotating
    end

    PredState[model] = { vel=vel, t=now }

    local dist   = (Camera.CFrame.Position - part.Position).Magnitude
    -- FIX 1: Use configurable bullet speed
    local travel = dist / Cfg.BulletSpeed

    -- FIX 5: Only apply full prediction if aim is already near the target.
    -- If crosshair is far from target, we haven't caught up yet — applying
    -- lead now would make us chase the wrong point. Scale lead by proximity.
    local sPos, onScreen = Camera:WorldToViewportPoint(part.Position)
    local mouse = game:GetService("UserInputService"):GetMouseLocation()
    local sDist = onScreen and (Vector2.new(sPos.X,sPos.Y)-mouse).Magnitude or 999
    -- Lead factor: 0 when far from target, 1 when crosshair is on target
    local leadFactor = math.clamp(1 - (sDist / (Cfg.FovRadius * 0.5)), 0, 1)

    -- FIX 2: Acceleration ADDS to lead (was subtracting — backwards)
    -- Higher acceleration = more lead needed, not less
    local accelLead = accel * (travel * travel) * 0.5

    -- FIX 4: Direction change adds a lateral offset to aim ahead of the arc
    local dirLead = dirChange * vel.Magnitude * (travel * travel) * 0.3

    -- Base linear lead
    local linearLead = vel * travel

    -- FIX 3: Gravity compensation — bullets drop over time
    -- Gravity in Roblox = 196.2 studs/s^2 (default workspace gravity)
    -- We lift the aim point up by how much the bullet will drop
    local gravity     = workspace.Gravity  -- use actual workspace gravity
    local gravityDrop = Vector3.new(0, 0.5 * gravity * travel * travel, 0)

    -- Combine all corrections, scaled by how close we are to the target
    return (linearLead + accelLead + dirLead + gravityDrop) * leadFactor
end

----------------------------------------------------------------
-- FIRE RATE
----------------------------------------------------------------
local function FireInterval(dist)
    local b = FMODE[CurrentMode] or 0.09
    if CurrentMode == "auto" then
        if dist < 15  then return b * 0.7
        elseif dist < 30  then return b
        elseif dist < 50  then return b * 1.6
        elseif dist < 80  then return b * 2.5
        else                   return b * 4.0 end
    elseif CurrentMode == "burst" then
        return dist < 40 and b or b * 1.8
    end
    return b
end

----------------------------------------------------------------
-- AUTO RELOAD
----------------------------------------------------------------
local AMMO_PATH = {"HUDInterface","Frame","9","4","3","1","3"}
local function FindAmmoLabel()
    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui"); if not pg then return nil end
    local n = pg
    for _, s in ipairs(AMMO_PATH) do n = n:FindFirstChild(s); if not n then return nil end end
    return (n:IsA("TextLabel") or n:IsA("TextBox")) and tonumber(n.Text) and n or nil
end

local function PressR()
    pcall(function() VIM:SendKeyEvent(true,  Enum.KeyCode.R, false, game) end)
    task.wait(0.1)
    pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.R, false, game) end)
end

local function TriggerReload()
    if ReloadCooldown or IsReloading then return end
    IsReloading = true; ReloadCooldown = true
    task.spawn(function()
        task.wait(0.05); PressR()
        local w = 0
        repeat
            task.wait(0.1); w = w + 0.1
            local v = AmmoLabel and AmmoLabel.Parent and tonumber(AmmoLabel.Text) or 0
            if v and v > 0 then break end
            if math.abs(w - 1.5) < 0.05 then PressR() end
        until w >= 6
        task.wait(0.3); ReloadCooldown = false; IsReloading = false
    end)
end

-- FIX: AmmoLbl already exists when this task.spawn runs
task.spawn(function()
    while true do
        if not AmmoLabel or not AmmoLabel.Parent then
            AmmoLabel = FindAmmoLabel()
            if AmmoLabel then
                AmmoLabel:GetPropertyChangedSignal("Text"):Connect(function()
                    local v = tonumber(AmmoLabel.Text)
                    if not v then return end
                    AmmoLbl.Text = v == 0 and "📦 EMPTY!" or "📦 AMMO: "..v
                    AmmoLbl.TextColor3 = v == 0
                        and Color3.fromRGB(255,80,80)
                        or  Color3.fromRGB(0,255,100)
                    if v == 0 and Cfg.AutoReload then TriggerReload() end
                end)
            end
        end
        task.wait(1)
    end
end)

----------------------------------------------------------------
-- FIRE MODE DETECTION
-- FIX: ModeLbl already exists when ApplyMode is first called
----------------------------------------------------------------
local FMODE_PATH = {"HUDInterface","Frame","9","4","3","1","2"}
local FModeNodes = nil

local function ReadMode()
    if not FModeNodes then return "auto" end
    local lit = 0
    for _, n in ipairs(FModeNodes) do
        local t = 1
        pcall(function() t = n:IsA("ImageLabel") and n.ImageTransparency or n.BackgroundTransparency end)
        if t < 0.5 then lit = lit + 1 end
    end
    return lit >= 3 and "burst" or lit == 2 and "auto" or "semi"
end

local function ApplyMode(mode)
    CurrentMode = mode
    local col = mode=="auto"  and Color3.fromRGB(255,200,0)
             or mode=="burst" and Color3.fromRGB(180,100,255)
             or                   Color3.fromRGB(100,200,255)
    -- FIX: ModeLbl guaranteed to exist here (created before this function)
    ModeLbl.Text = "🔫 "..mode:upper(); ModeLbl.TextColor3 = col
end

local function ResolveFireMode()
    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui"); if not pg then return end
    local n = pg
    for _, s in ipairs(FMODE_PATH) do n = n:FindFirstChild(s); if not n then return end end
    local nodes = {}
    for i = 1, 3 do
        local c = n:FindFirstChild(tostring(i)) or n:GetChildren()[i]; if not c then return end
        nodes[i] = c
        local prop = c:IsA("ImageLabel") and "ImageTransparency" or "BackgroundTransparency"
        pcall(function()
            c:GetPropertyChangedSignal(prop):Connect(function() ApplyMode(ReadMode()) end)
        end)
    end
    FModeNodes = nodes; ApplyMode(ReadMode())
end

task.spawn(function()
    while true do
        if not FModeNodes then
            ResolveFireMode()
        else
            for _, n in ipairs(FModeNodes) do
                if not n.Parent then FModeNodes = nil; break end
            end
        end
        task.wait(3)
    end
end)

----------------------------------------------------------------
-- PARTICLE DISABLER
----------------------------------------------------------------
local function KillFx(v)
    local c = v.ClassName
    if c=="ParticleEmitter" or c=="Smoke" or c=="Fire"
    or c=="Sparkles" or c=="Trail" or c=="Beam" then
        pcall(function()
            v.Enabled = false
            if c == "ParticleEmitter" then v:Clear() end
            v:Destroy()
        end)
    end
end

task.spawn(function()
    local all = workspace:GetDescendants()
    for i = 1, #all, 100 do
        for j = i, math.min(i+99, #all) do KillFx(all[j]) end
        RunService.Heartbeat:Wait()
    end
end)

local pending = {}; local flushing = false
workspace.DescendantAdded:Connect(function(v)
    local c = v.ClassName
    if c=="ParticleEmitter" or c=="Smoke" or c=="Fire"
    or c=="Sparkles" or c=="Trail" or c=="Beam" then
        pending[#pending+1] = v
        if not flushing then
            flushing = true
            task.delay(0.05, function()
                local b = pending; pending = {}; flushing = false
                for _, p in ipairs(b) do KillFx(p) end
            end)
        end
    end
end)

----------------------------------------------------------------
-- ESP — 10Hz loop, reads VisScoreCache (no extra raycasts)
----------------------------------------------------------------
local function MakeESP(model)
    if model:FindFirstChild("ESPHighlight") then return end
    local h = Instance.new("Highlight")
    h.Name="ESPHighlight"; h.FillTransparency=Cfg.EspFill
    h.OutlineTransparency=Cfg.EspOutline; h.Adornee=model
    h.Enabled=false; h.Parent=model
    EspState[model] = { vis=false, pend=0, pendTgt=false }
end

local function TryAdd(v)
    if v.Name ~= "Male" or not v:IsA("Model") or IsPlayerChar(v) then return end
    task.delay(0.2, function()
        if not v.Parent or IsPlayerChar(v) then return end
        if v:FindFirstChild("Head") or v:FindFirstChild("UpperTorso") then
            MakeESP(v)
            if not table.find(TargetList, v) then table.insert(TargetList, v) end
        end
    end)
end

task.spawn(function()
    local all = workspace:GetDescendants()
    for i = 1, #all, 100 do
        for j = i, math.min(i+99, #all) do
            if all[j].Name == "Male" then TryAdd(all[j]) end
        end
        RunService.Heartbeat:Wait()
    end
end)

workspace.DescendantAdded:Connect(function(d) if d.Name=="Male" then TryAdd(d) end end)
workspace.DescendantRemoving:Connect(function(d)
    if d.Name ~= "Male" then return end
    local i = table.find(TargetList, d); if i then table.remove(TargetList, i) end
    EspState[d]=nil; PredState[d]=nil; VisScoreCache[d]=nil
    if LockedTarget == d then LockedTarget = nil end
end)

-- Combined 10Hz loop: prune + ESP colors (reads cache — no raycasts)
task.spawn(function()
    while true do
        for i = #TargetList, 1, -1 do
            local t = TargetList[i]
            if not t or not t.Parent or IsDead(t) or IsPlayerChar(t) then
                local h = t and t:FindFirstChild("ESPHighlight")
                if h then pcall(h.Destroy, h) end
                EspState[t]=nil; PredState[t]=nil; VisScoreCache[t]=nil
                table.remove(TargetList, i)
                if LockedTarget == t then LockedTarget = nil end
            end
        end

        for _, e in ipairs(TargetList) do
            local h = e:FindFirstChild("ESPHighlight"); if not h then continue end
            if not Cfg.Esp then
                if h.Enabled then h.Enabled = false end
                continue
            end
            h.Enabled = true

            -- FIX: ReadVisCache — pure table read, no raycasts
            local score = ReadVisCache(e)
            local visible = score > 0.2

            local st = EspState[e]
            if not st then
                st = { vis=false, pend=0, pendTgt=false }; EspState[e] = st
            end

            if visible ~= st.pendTgt then
                st.pendTgt = visible; st.pend = 1
            else
                st.pend = st.pend + 1
            end
            if st.pend >= 3 and visible ~= st.vis then
                st.vis = visible; st.pend = 0
            end

            local col = st.vis and Cfg.VisibleColor or Cfg.HiddenColor
            if h.FillColor ~= col then h.FillColor = col; h.OutlineColor = col end
            if h.FillTransparency    ~= Cfg.EspFill    then h.FillTransparency    = Cfg.EspFill    end
            if h.OutlineTransparency ~= Cfg.EspOutline then h.OutlineTransparency = Cfg.EspOutline end
        end

        task.wait(0.1)
    end
end)

----------------------------------------------------------------
-- INPUT
----------------------------------------------------------------
LocalPlayer.CharacterAdded:Connect(function()
    RayParams=nil; LastChar=nil; PredState={}; VisScoreCache={}; LockedTarget=nil
end)

local function GetKeyName(kc) return kc and kc.Name or "NONE" end

UIS.InputBegan:Connect(function(input, gp)
    if BindingKey then
        local kc = input.KeyCode
        if kc ~= Enum.KeyCode.Unknown then
            Keys[BindingKey] = kc
            print("[BIND] "..BindingKey.." → "..GetKeyName(kc))
            BindingKey = nil
        end
        return
    end

    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        if Cfg.NoRecoil then
            IsFiring=true
            local cf = Camera.CFrame
            local p, y = cf:ToEulerAnglesYXZ()
            NoRecoilPitch = p; NoRecoilYaw = y
        end
    end
    if input.UserInputType == Enum.UserInputType.MouseButton2 then RMBHeld=true end
    if gp then return end

    local k = input.KeyCode
    if     k == Keys.Master    then
        Cfg.MasterEnabled = not Cfg.MasterEnabled
        Cfg.NoRecoil      = Cfg.MasterEnabled
        if not Cfg.MasterEnabled then LockedTarget=nil; IsFiring=false end
        print("MASTER:", Cfg.MasterEnabled and "ON" or "OFF")
    elseif k == Keys.Esp       then Cfg.Esp = not Cfg.Esp; print("ESP:", Cfg.Esp and "ON" or "OFF")
    elseif k == Keys.Autoshoot then Cfg.Autoshoot = not Cfg.Autoshoot; print("AUTOSHOOT:", Cfg.Autoshoot and "ON" or "OFF")
    elseif k == Keys.NoRecoil  then
        Cfg.NoRecoil = not Cfg.NoRecoil
        if not Cfg.NoRecoil then IsFiring=false end
        print("NORECOIL:", Cfg.NoRecoil and "ON" or "OFF")
    elseif k == Enum.KeyCode.Zero then
        print("=== BRM5 DEBUG ===")
        print("Mode:", CurrentMode, "| Targets:", #TargetList, "| Locked:", LockedTarget and LockedTarget.Name or "none")
        print("Ammo:", AmmoLabel and AmmoLabel.Text or "?", "| Reloading:", IsReloading)
        if LockedTarget then
            local s, p = ReadVisCache(LockedTarget)
            print("Locked vis score:", string.format("%.2f", s), "best part:", p and p.Name or "none")
        end
        print("==================")
    end
end)

UIS.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then IsFiring=false; NoRecoilYaw=nil; NoRecoilPitch=nil end
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        RMBHeld = false
        if Cfg.HoldToAim then LockedTarget = nil end
    end
end)

----------------------------------------------------------------
-- NO RECOIL — stores yaw+pitch at shot start, re-locks every frame
-- Separating yaw/pitch avoids gimbal lock near vertical aim
----------------------------------------------------------------
local NoRecoilYaw   = nil
local NoRecoilPitch = nil

RunService.RenderStepped:Connect(function()
    if not Cfg.NoRecoil or not IsFiring then return end
    if not UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then return end
    if not NoRecoilYaw then return end
    local pos = Camera.CFrame.Position
    Camera.CFrame = CFrame.new(pos)
        * CFrame.fromEulerAnglesYXZ(NoRecoilPitch, NoRecoilYaw, 0)
end)

----------------------------------------------------------------
-- MAIN AIMBOT LOOP — RenderStepped, ZERO raycasts
-- All visibility data read from VisScoreCache (written by bg tasks)
----------------------------------------------------------------
RunService.RenderStepped:Connect(function(dt)
    -- FOV circle
    local mc = UIS:GetMouseLocation()
    local fd = Cfg.FovRadius * 2
    FovCircle.Size     = UDim2.new(0,fd,0,fd)
    FovCircle.Position = UDim2.new(0,mc.X-Cfg.FovRadius,0,mc.Y-Cfg.FovRadius)
    FovCircle.Visible  = Cfg.FovVisible and Cfg.MasterEnabled and not Cfg.CrosshairTarget
    FovStroke.Color    = Cfg.FovColor

    local active = Cfg.MasterEnabled and (not Cfg.HoldToAim or RMBHeld)
    if not active then
        if Cfg.HoldToAim and not RMBHeld then LockedTarget = nil end
        return
    end

    if LockedTarget and not IsValid(LockedTarget) then LockedTarget = nil end

    local mouse = UIS:GetMouseLocation()

    if not LockedTarget or not Cfg.StickyLock then
        local bestT, bestScore = nil, -1
        for _, e in ipairs(TargetList) do
            if not IsValid(e) then continue end
            local ref = e:FindFirstChild("HumanoidRootPart") or e:FindFirstChild("UpperTorso")
                     or e:FindFirstChild("Torso") or e:FindFirstChild("Root")
            if not ref or not InFront(ref.Position) then continue end
            local wd = (Camera.CFrame.Position - ref.Position).Magnitude
            local sp, onScreen = Camera:WorldToViewportPoint(ref.Position)
            local sd = onScreen and (Vector2.new(sp.X,sp.Y)-mouse).Magnitude or Cfg.FovRadius
            if wd > 8 and (not onScreen or sd >= Cfg.FovRadius) then continue end

            local score
            if Cfg.CrosshairTarget then
                score = 1 - (sd / Cfg.FovRadius)
            else
                -- FIX: ScoreTarget reads cache — no raycasts
                score = ScoreTarget(e, sd, wd)
            end

            if score > bestScore then bestScore=score; bestT=e end
        end
        LockedTarget = bestT
    end

    if not LockedTarget then return end

    -- FIX: BestAimPart reads cache — no raycasts
    local targetPart, isVis = BestAimPart(LockedTarget)
    if not targetPart then LockedTarget=nil; return end

    local dist  = (Camera.CFrame.Position - targetPart.Position).Magnitude
    local aimPt = targetPart.Position + Predict(LockedTarget, targetPart)
    local sPos, onScreen = Camera:WorldToViewportPoint(aimPt)
    if not onScreen and dist > 15 then return end

    if onScreen then
        local sDist = (Vector2.new(sPos.X,sPos.Y)-mouse).Magnitude
        if sDist > Cfg.FovRadius + 20 then return end
        if sDist > 0.5 then
            local t = math.min(1, (Cfg.Sensitivity / Cfg.Smoothing) * (dt * 60))
            MoveRel((sPos.X-mouse.X)*t, (sPos.Y-mouse.Y)*t)
        end
    end

    if not Cfg.Autoshoot or IsReloading then return end

    local visScore = ReadVisCache(LockedTarget)

    -- Range gate: sniper mode = no cap, otherwise use MaxRange
    local maxRange = Cfg.SniperMode and 9999 or Cfg.MaxRange
    if dist > maxRange then return end

    -- Visibility gate: sniper mode is more lenient (0.1) since targets
    -- at long range may have fewer cached visible parts due to 5Hz refresh.
    -- Normal mode keeps 0.2 threshold.
    local visThreshold = Cfg.SniperMode and 0.1 or 0.2
    if visScore < visThreshold then return end

    -- Screen proximity gate: how close crosshair must be to fire.
    -- Sniper mode: tight (15px) — at range 1px = big miss, must be precise.
    -- Normal mode: loose (80px) — aim assist handles the rest.
    -- Only gate when onScreen (already computed above in aim block).
    local shootThreshold = Cfg.SniperMode and 15 or 80
    if onScreen then
        local sDist = (Vector2.new(sPos.X, sPos.Y) - mouse).Magnitude
        if sDist > shootThreshold then return end
    end

    local now = tick(); local iv = FireInterval(dist)

    if CurrentMode == "burst" then
        if (now-LastShotFired) >= iv then
            LastShotFired = now
            for i=0,2 do
                task.delay(i*0.065, function()
                    if Cfg.Autoshoot and Cfg.MasterEnabled then Click() end
                end)
            end
        end
    elseif CurrentMode == "semi" then
        -- Semi/sniper: press+release so bolt-action registers each shot
        if (now-LastShotFired) >= iv then
            LastShotFired = now
            Press()
            task.delay(0.06, function() Release() end)
        end
    else
        -- Auto
        if (now-LastShotFired) >= iv then
            LastShotFired=now; Click()
        end
    end
end)

----------------------------------------------------------------
-- RAYFIELD TABS (Window created at top of script)
----------------------------------------------------------------
local CombatTab  = Window:CreateTab("⚔ Combat",   4483362458)
local VisualsTab = Window:CreateTab("👁 Visuals",  4483362458)
local BindsTab   = Window:CreateTab("⌨ Keybinds", 4483362458)
local InfoTab    = Window:CreateTab("ℹ Info",      4483362458)

CombatTab:CreateToggle({ Name="⚡ Master ["..GetKeyName(Keys.Master).."]", CurrentValue=false,
    Callback=function(v)
        Cfg.MasterEnabled=v; Cfg.NoRecoil=v
        if not v then LockedTarget=nil; IsFiring=false end
    end})
CombatTab:CreateDivider()
CombatTab:CreateToggle({ Name="No Recoil ["..GetKeyName(Keys.NoRecoil).."]", CurrentValue=true,
    Callback=function(v) Cfg.NoRecoil=v; if not v then IsFiring=false end end})
CombatTab:CreateToggle({ Name="Hold RMB to Aim", CurrentValue=true,
    Callback=function(v) Cfg.HoldToAim=v end})
CombatTab:CreateToggle({ Name="Crosshair Target", CurrentValue=true,
    Callback=function(v) Cfg.CrosshairTarget=v; if v then LockedTarget=nil end end})
CombatTab:CreateToggle({ Name="Autoshoot ["..GetKeyName(Keys.Autoshoot).."]", CurrentValue=false,
    Callback=function(v) Cfg.Autoshoot=v end})
CombatTab:CreateToggle({ Name="Sticky Lock (keep target until RMB released)", CurrentValue=false,
    Callback=function(v) Cfg.StickyLock=v end})
CombatTab:CreateToggle({ Name="Auto Reload", CurrentValue=true,
    Callback=function(v) Cfg.AutoReload=v end})
CombatTab:CreateDivider()
CombatTab:CreateToggle({ Name="🔭 Sniper Mode (no range cap, tighter threshold)", CurrentValue=false,
    Callback=function(v) Cfg.SniperMode=v end})
CombatTab:CreateSlider({ Name="Max Range (studs, ignored in Sniper Mode)", Range={50,500}, Increment=10, CurrentValue=120,
    Callback=function(v) Cfg.MaxRange=v end})
CombatTab:CreateSlider({ Name="Bullet Speed (AR=900 Sniper=1500 SMG=700)", Range={300,2000}, Increment=50, CurrentValue=900,
    Callback=function(v) Cfg.BulletSpeed=v end})
CombatTab:CreateDivider()
CombatTab:CreateSlider({ Name="Sensitivity", Range={0.1,2},  Increment=0.05, CurrentValue=0.3, Callback=function(v) Cfg.Sensitivity=v end})
CombatTab:CreateSlider({ Name="Smoothing",   Range={1,5},    Increment=0.1,  CurrentValue=1.0, Callback=function(v) Cfg.Smoothing=v   end})
CombatTab:CreateSlider({ Name="FOV Radius",  Range={50,600}, Increment=10,   CurrentValue=300, Callback=function(v) Cfg.FovRadius=v   end})

VisualsTab:CreateToggle({ Name="ESP ["..GetKeyName(Keys.Esp).."]", CurrentValue=true,
    Callback=function(v) Cfg.Esp=v end})
VisualsTab:CreateToggle({ Name="Show FOV Circle", CurrentValue=true,
    Callback=function(v) Cfg.FovVisible=v end})
VisualsTab:CreateToggle({ Name="Hide Mode/Ammo Bar", CurrentValue=false,
    Callback=function(v) Cfg.HideHUD=v; InfoFrame.Visible=not v end})
VisualsTab:CreateSlider({ Name="ESP Fill Transparency",    Range={0,1}, Increment=0.05, CurrentValue=0.6, Callback=function(v) Cfg.EspFill=v    end})
VisualsTab:CreateSlider({ Name="ESP Outline Transparency", Range={0,1}, Increment=0.05, CurrentValue=0.6, Callback=function(v) Cfg.EspOutline=v end})
VisualsTab:CreateColorPicker({ Name="Visible Enemy", Color=Cfg.VisibleColor, Callback=function(v) Cfg.VisibleColor=v end})
VisualsTab:CreateColorPicker({ Name="Hidden Enemy",  Color=Cfg.HiddenColor,  Callback=function(v) Cfg.HiddenColor=v  end})
VisualsTab:CreateColorPicker({ Name="FOV Color",     Color=Cfg.FovColor,     Callback=function(v) Cfg.FovColor=v end})

BindsTab:CreateParagraph({ Title="How to rebind",
    Content="Click a Rebind button then press any key.\nTakes effect immediately."})
BindsTab:CreateDivider()
local function MakeBindRow(tab, action, label)
    tab:CreateButton({ Name="Rebind "..label.."  →  ["..GetKeyName(Keys[action]).."]",
        Callback=function()
            BindingKey = action
            print("Press a key to bind: "..action)
        end})
end
MakeBindRow(BindsTab, "Master",    "Master Toggle")
MakeBindRow(BindsTab, "Esp",       "ESP Toggle")
MakeBindRow(BindsTab, "Autoshoot", "Autoshoot Toggle")
MakeBindRow(BindsTab, "NoRecoil",  "No Recoil Toggle")

InfoTab:CreateParagraph({ Title="Keybinds",
    Content="O → Master\nU → ESP\nP → Autoshoot\nI → No Recoil\nRMB → Aim (Hold RMB mode)\n0 → Debug dump"})
InfoTab:CreateParagraph({ Title="Target Scoring",
    Content="Visibility 55% + Distance 25% + Crosshair proximity 20%\nTargets behind cover score low and are skipped\nAutoshoot requires >20% body exposed"})
InfoTab:CreateParagraph({ Title="v26.0 Changes",
    Content="Mode + ammo labels fixed (nil race condition)\nZero raycasts on render thread\nLocked target refreshed at 30Hz bg task\nAll targets refreshed at 5Hz bg task\nVIS_CACHE_TTL raised to 0.2s"})
InfoTab:CreateButton({ Name="Debug Dump (or press 0)", Callback=function()
    print("=== BRM5 DEBUG ===")
    print("Mode:", CurrentMode, "| Targets:", #TargetList, "| Locked:", LockedTarget and LockedTarget.Name or "none")
    if LockedTarget then
        local s,p = ReadVisCache(LockedTarget)
        print("Vis score:", string.format("%.2f",s), "| Best part:", p and p.Name or "none")
    end
    print("==================")
end})

print("BRM5 v36.0 | Mac compatible | Z=Master U=ESP P=Autoshoot I=NoRecoil 0=Debug")
