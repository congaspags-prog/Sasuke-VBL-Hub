-- SASUKE VBL | Luau / Delta Executor
-- Hitbox auxiliar local + previsao aproximada de queda
-- Nenhuma chamada HTTP ou script externo.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local CoreGui = game:GetService("CoreGui")

local player = Players.LocalPlayer
local env = (type(getgenv) == "function" and getgenv()) or _G
if env.SasukeVBL and type(env.SasukeVBL.Close) == "function" then
    pcall(env.SasukeVBL.Close)
end

local PURPLE = Color3.fromRGB(150, 85, 240)
local DARK = Color3.fromRGB(21, 16, 34)
local PANEL = Color3.fromRGB(34, 26, 51)
local TEXT = Color3.fromRGB(240, 232, 255)
local MUTED = Color3.fromRGB(173, 157, 197)
local OFF = Color3.fromRGB(79, 71, 98)

local hitboxOn, predictOn, pathOn = false, true, true
local hitboxDiameter = 10 -- studs; 4 a 20
local running = true
local connections = {}
local trackedBall, trackedRoot, hitboxPart
local lastPosition, lastSampleTime

local function new(class, parent, props)
    local obj = Instance.new(class)
    for key, value in pairs(props or {}) do
        obj[key] = value
    end
    obj.Parent = parent
    return obj
end

local function rounded(obj, r)
    new("UICorner", obj, {CornerRadius = UDim.new(0, r or 10)})
end

local function bind(signal, fn)
    local conn = signal:Connect(fn)
    table.insert(connections, conn)
    return conn
end

-- A pasta e os indicadores existem somente neste cliente.
local fx = new("Folder", workspace, {Name = "SasukeVBL_LocalFX"})
local landing = new("Part", fx, {
    Name = "LandingMarker", Shape = Enum.PartType.Cylinder,
    Size = Vector3.new(0.15, 3.5, 3.5), Orientation = Vector3.new(0, 0, 90),
    Anchored = true, CanCollide = false, CanTouch = false, CanQuery = false,
    CastShadow = false, Material = Enum.Material.Neon,
    Color = PURPLE, Transparency = 1
})
local billboard = new("BillboardGui", landing, {
    Size = UDim2.fromOffset(135, 34), StudsOffset = Vector3.new(0, 2.5, 0),
    AlwaysOnTop = true, Enabled = false
})
local landingText = new("TextLabel", billboard, {
    Size = UDim2.fromScale(1, 1), BackgroundColor3 = DARK,
    BackgroundTransparency = 0.12, TextColor3 = TEXT,
    Font = Enum.Font.GothamBold, TextSize = 12, Text = "PREVISAO",
})
rounded(landingText, 8)

local dots = {}
for i = 1, 12 do
    dots[i] = new("Part", fx, {
        Name = "TrajectoryDot" .. i, Shape = Enum.PartType.Ball,
        Size = Vector3.new(0.37, 0.37, 0.37), Anchored = true,
        CanCollide = false, CanTouch = false, CanQuery = false,
        CastShadow = false, Material = Enum.Material.Neon,
        Color = PURPLE, Transparency = 1
    })
end

local function hidePrediction()
    landing.Transparency = 1
    billboard.Enabled = false
    for _, dot in ipairs(dots) do dot.Transparency = 1 end
end

local function removeHitbox()
    if hitboxPart then
        hitboxPart:Destroy()
        hitboxPart = nil
    end
end

local gui = new("ScreenGui", nil, {
    Name = "SasukeVBLMenu", ResetOnSpawn = false,
    IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling
})
local parented = pcall(function() gui.Parent = CoreGui end)
if not parented then gui.Parent = player:WaitForChild("PlayerGui") end

local main = new("Frame", gui, {
    Name = "Window", Size = UDim2.fromOffset(304, 300),
    Position = UDim2.new(0.5, -152, 0.40, -150),
    BackgroundColor3 = DARK, ClipsDescendants = true,
    BorderSizePixel = 0, Active = true
})
rounded(main, 13)
new("UIStroke", main, {Color = PURPLE, Thickness = 1.5, Transparency = 0.23})

local header = new("Frame", main, {
    Size = UDim2.new(1, 0, 0, 46), BackgroundColor3 = PANEL,
    BorderSizePixel = 0, Active = true
})
rounded(header, 13)
new("Frame", header, {
    Size = UDim2.new(1, 0, 0, 11), Position = UDim2.new(0, 0, 1, -11),
    BackgroundColor3 = PANEL, BorderSizePixel = 0
})
new("TextLabel", header, {
    Size = UDim2.fromOffset(38, 39), Position = UDim2.fromOffset(8, 4),
    BackgroundTransparency = 1, Text = "◎", Font = Enum.Font.GothamBold,
    TextSize = 30, TextColor3 = PURPLE
})
new("TextLabel", header, {
    Size = UDim2.fromOffset(183, 24), Position = UDim2.fromOffset(45, 3),
    BackgroundTransparency = 1, Text = "SASUKE  //  VBL",
    Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = TEXT,
    TextXAlignment = Enum.TextXAlignment.Left
})
new("TextLabel", header, {
    Size = UDim2.fromOffset(175, 15), Position = UDim2.fromOffset(45, 26),
    BackgroundTransparency = 1, Text = "RINNEGAN  •  DELTA",
    Font = Enum.Font.Gotham, TextSize = 10, TextColor3 = MUTED,
    TextXAlignment = Enum.TextXAlignment.Left
})

local function topButton(caption, x)
    local btn = new("TextButton", header, {
        Size = UDim2.fromOffset(24, 25), Position = UDim2.fromOffset(x, 10),
        BackgroundColor3 = OFF, Text = caption, TextColor3 = TEXT,
        Font = Enum.Font.GothamBold, TextSize = 16, AutoButtonColor = true
    })
    rounded(btn, 6)
    return btn
end
local minimizeBtn = topButton("−", 246)
local closeBtn = topButton("×", 273)

local content = new("Frame", main, {
    Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 1, -46),
    BackgroundTransparency = 1
})

local function switchRow(label, ypos, value)
    local row = new("Frame", content, {
        Size = UDim2.fromOffset(278, 39), Position = UDim2.fromOffset(13, ypos),
        BackgroundColor3 = PANEL, BorderSizePixel = 0
    })
    rounded(row, 9)
    new("TextLabel", row, {
        Size = UDim2.fromOffset(190, 38), Position = UDim2.fromOffset(10, 0),
        BackgroundTransparency = 1, Text = label, TextColor3 = TEXT,
        Font = Enum.Font.GothamMedium, TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left
    })
    local btn = new("TextButton", row, {
        Size = UDim2.fromOffset(64, 27), Position = UDim2.fromOffset(204, 6),
        BorderSizePixel = 0, Font = Enum.Font.GothamBold, TextSize = 11,
        TextColor3 = TEXT, AutoButtonColor = true
    })
    rounded(btn, 7)
    local function refresh(state)
        btn.Text = state and "ON" or "OFF"
        btn.BackgroundColor3 = state and PURPLE or OFF
    end
    refresh(value)
    return btn, refresh
end

local hitButton, setHit = switchRow("HITBOX DA BOLA", 10, hitboxOn)
local sizeRow = new("Frame", content, {
    Size = UDim2.fromOffset(278, 37), Position = UDim2.fromOffset(13, 55),
    BackgroundColor3 = PANEL, BorderSizePixel = 0
})
rounded(sizeRow, 9)
new("TextLabel", sizeRow, {
    Size = UDim2.fromOffset(126, 37), Position = UDim2.fromOffset(10, 0),
    BackgroundTransparency = 1, Text = "TAMANHO", TextColor3 = TEXT,
    TextSize = 12, Font = Enum.Font.GothamMedium,
    TextXAlignment = Enum.TextXAlignment.Left
})
local sizeText = new("TextLabel", sizeRow, {
    Position = UDim2.fromOffset(170, 0), Size = UDim2.fromOffset(53, 37),
    BackgroundTransparency = 1, Text = "10", TextColor3 = PURPLE,
    TextSize = 13, Font = Enum.Font.GothamBold
})
local function smallButton(symbol, x)
    local b = new("TextButton", sizeRow, {
        Position = UDim2.fromOffset(x, 6), Size = UDim2.fromOffset(28, 25),
        BackgroundColor3 = OFF, Text = symbol, TextColor3 = TEXT,
        Font = Enum.Font.GothamBold, TextSize = 16
    })
    rounded(b, 6)
    return b
end
local minusBtn = smallButton("−", 142)
local plusBtn = smallButton("+", 237)
local predictButton, setPredict = switchRow("PREVER QUEDA", 101, predictOn)
local pathButton, setPath = switchRow("MOSTRAR TRAJETORIA", 146, pathOn)
local status = new("TextLabel", content, {
    Size = UDim2.fromOffset(278, 26), Position = UDim2.fromOffset(13, 193),
    BackgroundColor3 = PANEL, Text = "PROCURANDO BOLA...",
    TextColor3 = MUTED, Font = Enum.Font.GothamMedium, TextSize = 11
})
rounded(status, 8)
new("TextLabel", content, {
    Position = UDim2.fromOffset(15, 220), Size = UDim2.fromOffset(275, 24),
    BackgroundTransparency = 1, Text = "Assistencia visual local  |  v1.0",
    TextColor3 = MUTED, TextSize = 10, Font = Enum.Font.Gotham,
    TextXAlignment = Enum.TextXAlignment.Center
})

local minimized = false
bind(minimizeBtn.MouseButton1Click, function()
    minimized = not minimized
    content.Visible = not minimized
    main.Size = UDim2.fromOffset(304, minimized and 46 or 300)
    minimizeBtn.Text = minimized and "+" or "−"
end)

-- Arrastar pelo topo: mouse e toque (mobile).
local dragging, dragOrigin, guiOrigin, activeInput = false, nil, nil, nil
bind(header.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragOrigin = input.Position
        guiOrigin = main.Position
        activeInput = input
    end
end)
bind(UserInputService.InputChanged, function(input)
    if dragging and dragOrigin and guiOrigin and
        (input == activeInput or
         (activeInput and activeInput.UserInputType == Enum.UserInputType.MouseButton1
          and input.UserInputType == Enum.UserInputType.MouseMovement)) then
        local delta = input.Position - dragOrigin
        main.Position = UDim2.new(guiOrigin.X.Scale, guiOrigin.X.Offset + delta.X,
            guiOrigin.Y.Scale, guiOrigin.Y.Offset + delta.Y)
    end
end)
bind(UserInputService.InputEnded, function(input)
    if input == activeInput or
       (activeInput and activeInput.UserInputType == Enum.UserInputType.MouseButton1
        and input.UserInputType == Enum.UserInputType.MouseButton1) then
        dragging, activeInput = false, nil
    end
end)

local function rootOf(instance)
    if not instance or not instance:IsDescendantOf(workspace) then return nil end
    if instance:IsA("BasePart") then return instance end
    if not instance:IsA("Model") then return nil end
    if instance.PrimaryPart then return instance.PrimaryPart end
    for _, child in ipairs(instance:GetDescendants()) do
        if child:IsA("BasePart") and child.Name ~= "SasukeHitboxProxy" then
            return child
        end
    end
end

local function findBall()
    local char = player.Character
    local playerRoot = char and char:FindFirstChild("HumanoidRootPart")
    local camera = workspace.CurrentCamera
    local origin = playerRoot and playerRoot.Position
        or (camera and camera.CFrame.Position) or Vector3.zero
    local bestBall, bestRoot, bestDistance = nil, nil, math.huge
    for _, candidate in ipairs(CollectionService:GetTagged("Ball")) do
        local root = rootOf(candidate)
        if root then
            local distance = (root.Position - origin).Magnitude
            if distance < bestDistance then
                bestBall, bestRoot, bestDistance = candidate, root, distance
            end
        end
    end
    return bestBall, bestRoot
end

local function ensureHitbox()
    if not hitboxOn or not trackedRoot or not trackedRoot.Parent then
        removeHitbox()
        return
    end
    if not hitboxPart then
        hitboxPart = new("Part", nil, {
            Name = "SasukeHitboxProxy", Shape = Enum.PartType.Ball,
            Anchored = true, CanCollide = false, CanTouch = false,
            CanQuery = true, CastShadow = false,
            Material = Enum.Material.ForceField,
            Color = PURPLE, Transparency = 0.82
        })
        hitboxPart.Parent = trackedBall:IsA("Model") and trackedBall or fx
    end
    hitboxPart.Size = Vector3.new(hitboxDiameter, hitboxDiameter, hitboxDiameter)
    hitboxPart.CFrame = trackedRoot.CFrame
end

-- Calcula a queda aproximada com base na velocidade atual e na gravidade.
-- Colisoes, habilidades especiais e alteracoes posteriores mudam o resultado.
local function prediction(position, velocity)
    if velocity.Magnitude > 400 then return nil end
    local exclusions = {fx, trackedBall}
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character then table.insert(exclusions, p.Character) end
    end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = exclusions
    params.IgnoreWater = true

    local floorHit = workspace:Raycast(position + Vector3.new(0, 2, 0),
        Vector3.new(0, -400, 0), params)
    if not floorHit then return nil end

    local g = workspace.Gravity
    if g <= 0 then return nil end
    local radius = trackedRoot and trackedRoot.Size.Y * 0.5 or 1
    local deltaH = math.max(0, position.Y - floorHit.Position.Y - radius)
    local duration = (velocity.Y + math.sqrt(velocity.Y * velocity.Y + 2 * g * deltaH)) / g
    if duration < 0.04 or duration > 4.5 then return nil end

    local acceleration = Vector3.new(0, -g, 0)
    local function point(t)
        return position + velocity * t + acceleration * (0.5 * t * t)
    end
    local last = position
    for i = 1, 40 do
        local t = duration * i / 40
        local nextPoint = point(t)
        local obstruction = workspace:Raycast(last, nextPoint - last, params)
        if obstruction then
            return obstruction.Position, t, point
        end
        last = nextPoint
    end
    return point(duration), duration, point
end

local function updatePrediction(position, velocity)
    if not predictOn then
        hidePrediction()
        return
    end
    local spot, timeToLand, pointAt = prediction(position, velocity)
    if not spot then
        hidePrediction()
        return
    end
    landing.Position = spot + Vector3.new(0, 0.12, 0)
    landing.Transparency = 0.26
    landingText.Text = ("CAI EM %.1fs"):format(timeToLand)
    billboard.Enabled = true

    for i, dot in ipairs(dots) do
        if pathOn then
            dot.Position = pointAt(timeToLand * i / (#dots + 1))
            dot.Transparency = 0.2
        else
            dot.Transparency = 1
        end
    end
end

bind(hitButton.MouseButton1Click, function()
    hitboxOn = not hitboxOn
    setHit(hitboxOn)
    if not hitboxOn then removeHitbox() else ensureHitbox() end
end)
bind(minusBtn.MouseButton1Click, function()
    hitboxDiameter = math.max(4, hitboxDiameter - 2)
    sizeText.Text = tostring(hitboxDiameter)
    if hitboxPart then ensureHitbox() end
end)
bind(plusBtn.MouseButton1Click, function()
    hitboxDiameter = math.min(20, hitboxDiameter + 2)
    sizeText.Text = tostring(hitboxDiameter)
    if hitboxPart then ensureHitbox() end
end)
bind(predictButton.MouseButton1Click, function()
    predictOn = not predictOn
    setPredict(predictOn)
    if not predictOn then hidePrediction() end
end)
bind(pathButton.MouseButton1Click, function()
    pathOn = not pathOn
    setPath(pathOn)
    if not pathOn then
        for _, dot in ipairs(dots) do dot.Transparency = 1 end
    end
end)

local accumulator = 0
bind(RunService.Heartbeat, function(dt)
    if not running then return end
    if hitboxPart and trackedRoot and trackedRoot.Parent then
        hitboxPart.CFrame = trackedRoot.CFrame
    end
    accumulator = accumulator + dt
    if accumulator < 0.11 then return end
    accumulator = 0

    local ball, root = findBall()
    if ball ~= trackedBall or root ~= trackedRoot then
        removeHitbox()
        hidePrediction()
        trackedBall, trackedRoot = ball, root
        lastPosition, lastSampleTime = nil, nil
    end
    if not root then
        status.Text = "PROCURANDO BOLA..."
        return
    end
    status.Text = "BOLA DETECTADA  |  HITBOX: " .. (hitboxOn and "ON" or "OFF")
    if hitboxOn then ensureHitbox() end

    local position = root.Position
    local now = os.clock()
    local velocity = root.AssemblyLinearVelocity
    if lastPosition and lastSampleTime then
        local deltaTime = now - lastSampleTime
        if deltaTime > 0.015 then
            local measured = (position - lastPosition) / deltaTime
            if velocity.Magnitude < 1.5 and measured.Magnitude > 1.5
                and measured.Magnitude < 400 then
                velocity = measured
            end
        end
    end
    lastPosition, lastSampleTime = position, now
    updatePrediction(position, velocity)
end)

local function close()
    if not running then return end
    running = false
    for _, conn in ipairs(connections) do pcall(function() conn:Disconnect() end) end
    removeHitbox()
    fx:Destroy()
    gui:Destroy()
    if env.SasukeVBL and env.SasukeVBL.Close == close then
        env.SasukeVBL = nil
    end
end

env.SasukeVBL = {Close = close}
bind(closeBtn.MouseButton1Click, close)