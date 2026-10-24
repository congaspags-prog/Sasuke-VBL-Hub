-- SASUKE VBL | Luau / Delta Executor
-- Hitbox auxiliar local + previsao aproximada de queda
-- Nenhuma chamada HTTP ou script externo.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")

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

-- Configuracoes carregadas automaticamente antes de desenhar a interface.
local settingsPath = "SasukeVBL_Config.json"
local canSave = type(writefile) == "function" and type(readfile) == "function"
local hitboxOn, predictOn, pathOn, fluidMode = false, true, true, false
local autoDefenseOn, autoDiveOn = false, true
local hitboxDiameter = 10 -- studs; 4 a 20
local minimized = false
local running = true
local connections = {}
local trackedBall, trackedRoot, hitboxPart
local lastPosition, lastSampleTime
local autoSaveLabel
local lastDefenseTick, lastDefenseBall, lastDefenseSpot = -100, nil, nil
local lastDefenseAction = ""

local function loadSettings()
    if not canSave then return end
    local ok, data = pcall(function()
        return HttpService:JSONDecode(readfile(settingsPath))
    end)
    if not ok or type(data) ~= "table" then return end
    if type(data.hitbox) == "boolean" then hitboxOn = data.hitbox end
    if type(data.prediction) == "boolean" then predictOn = data.prediction end
    if type(data.line) == "boolean" then pathOn = data.line end
    if type(data.fluid) == "boolean" then fluidMode = data.fluid end
    if type(data.autoDefense) == "boolean" then autoDefenseOn = data.autoDefense end
    if type(data.autoDive) == "boolean" then autoDiveOn = data.autoDive end
    if type(data.minimized) == "boolean" then minimized = data.minimized end
    if type(data.size) == "number" and data.size == data.size then
        hitboxDiameter = math.clamp(math.floor(data.size), 4, 20)
    end
end
loadSettings()

local function saveSettings()
    if not canSave then
        if autoSaveLabel then autoSaveLabel.Text = "CONFIG: SEM ARQUIVOS" end
        return
    end
    local ok = pcall(function()
        local content = HttpService:JSONEncode({
            hitbox = hitboxOn,
            prediction = predictOn,
            line = pathOn,
            fluid = fluidMode,
            autoDefense = autoDefenseOn,
            autoDive = autoDiveOn,
            minimized = minimized,
            size = hitboxDiameter
        })
        writefile(settingsPath, content)
    end)
    if autoSaveLabel then
        autoSaveLabel.Text = ok and "CONFIG: SALVA AUTOMATICAMENTE" or "CONFIG: ERRO AO SALVAR"
    end
end

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

-- Uma linha continua, sem particulas pontilhadas.
local landingLine = new("Part", fx, {
    Name = "LandingLine", Size = Vector3.new(0.13, 0.13, 1),
    Anchored = true, CanCollide = false, CanTouch = false,
    CanQuery = false, CastShadow = false, Material = Enum.Material.Neon,
    Color = PURPLE, Transparency = 1
})

local function hidePrediction()
    landing.Transparency = 1
    landingLine.Transparency = 1
    billboard.Enabled = false
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
    Name = "Window", Size = UDim2.fromOffset(304, minimized and 46 or 454),
    Position = UDim2.new(0.5, -152, 0.40, -178),
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
    BackgroundTransparency = 1, Text = "RINNEGAN  •  V2.1",
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
    BackgroundTransparency = 1, Text = tostring(hitboxDiameter), TextColor3 = PURPLE,
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
local pathButton, setPath = switchRow("LINHA ATE A QUEDA", 146, pathOn)
local fluidButton, setFluid = switchRow("MODO FLUIDEZ", 191, fluidMode)
local defenseButton, setDefense = switchRow("AUTO SALVAR BOLA", 236, autoDefenseOn)
local diveButton, setDive = switchRow("AUTO MERGULHO", 281, autoDiveOn)
local status = new("TextLabel", content, {
    Size = UDim2.fromOffset(278, 26), Position = UDim2.fromOffset(13, 328),
    BackgroundColor3 = PANEL, Text = "PROCURANDO BOLA...",
    TextColor3 = MUTED, Font = Enum.Font.GothamMedium, TextSize = 11
})
rounded(status, 8)
autoSaveLabel = new("TextLabel", content, {
    Position = UDim2.fromOffset(13, 360), Size = UDim2.fromOffset(278, 18),
    BackgroundTransparency = 1, Text = "CONFIG: VERIFICANDO...",
    TextColor3 = PURPLE, TextSize = 10, Font = Enum.Font.GothamMedium,
    TextXAlignment = Enum.TextXAlignment.Center
})
new("TextLabel", content, {
    Position = UDim2.fromOffset(13, 381), Size = UDim2.fromOffset(278, 14),
    BackgroundTransparency = 1, Text = "Sasuke • v2.1 • defesa automatica experimental",
    TextColor3 = MUTED, TextSize = 9, Font = Enum.Font.Gotham,
    TextXAlignment = Enum.TextXAlignment.Center
})

content.Visible = not minimized
minimizeBtn.Text = minimized and "+" or "−"
saveSettings()
bind(minimizeBtn.MouseButton1Click, function()
    minimized = not minimized
    content.Visible = not minimized
    main.Size = UDim2.fromOffset(304, minimized and 46 or 454)
    minimizeBtn.Text = minimized and "+" or "−"
    saveSettings()
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

-- Projeta a gravidade em trechos e encontra a primeira superficie atingida.
-- Evita dar como local de queda uma parede ou obstaculo vertical.
-- Habilidades, lag, vento e novas batidas podem mudar a trajetoria real.
local function prediction(position, velocity)
    if velocity.Magnitude > 400 or velocity.Magnitude < 1.5 then return nil end
    local g = workspace.Gravity
    if g <= 0 then return nil end

    local exclusions = {fx, trackedBall}
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character then table.insert(exclusions, p.Character) end
    end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = exclusions
    params.IgnoreWater = true
    params.RespectCanCollide = true

    local radius = trackedRoot and trackedRoot.Size.Y * 0.5 or 1
    local start = position - Vector3.new(0, radius * 0.75, 0)
    local acceleration = Vector3.new(0, -g, 0)
    local function point(t)
        return position + velocity * t + acceleration * (0.5 * t * t)
            - Vector3.new(0, radius * 0.75, 0)
    end
    local horizon = 4.5
    local steps = fluidMode and 25 or 48
    local previous = start
    for i = 1, steps do
        local nextTime = horizon * i / steps
        local nextPoint = point(nextTime)
        local segment = nextPoint - previous
        if segment.Magnitude > 0.001 then
            local hit = workspace:Raycast(previous, segment, params)
            if hit then
                if hit.Normal.Y < 0.55 then return nil end
                local fraction = math.clamp(hit.Distance / segment.Magnitude, 0, 1)
                local exactTime = horizon * (i - 1 + fraction) / steps
                if exactTime < 0.04 then return nil end
                return hit.Position, exactTime
            end
        end
        previous = nextPoint
    end
    return nil
end

-- Linha unica: retorna a previsao tambem para a defesa automatica.
local function updatePrediction(position, velocity)
    if not predictOn and not autoDefenseOn then
        hidePrediction()
        return nil
    end
    local spot, timeToLand = prediction(position, velocity)
    if not spot then
        hidePrediction()
        return nil
    end
    if not predictOn then
        hidePrediction()
        return spot, timeToLand
    end

    landing.Position = spot + Vector3.new(0, 0.12, 0)
    landing.Transparency = fluidMode and 0.42 or 0.26
    landingText.Text = ("QUEDA EM %.1fs"):format(timeToLand)
    billboard.Enabled = true

    local target = spot + Vector3.new(0, 0.2, 0)
    local delta = target - position
    local distance = delta.Magnitude
    if pathOn and distance > 0.2 then
        landingLine.Size = Vector3.new(0.15, 0.15, distance)
        landingLine.CFrame = CFrame.lookAt(position + delta * 0.5, target)
        landingLine.Transparency = fluidMode and 0.35 or 0.17
    else
        landingLine.Transparency = 1
    end
    return spot, timeToLand
end

-- Defesa experimental: envia somente controles normais do jogo.
-- Bump = clique esquerdo, Dive = Ctrl. Nao altera hitbox do servidor.
-- Alguns executores mobile nao oferecem simulacao de entrada;
-- nesse caso, a funcao informa que o comando nao foi suportado.
local inputOK, virtualInput = pcall(function()
    return game:GetService("VirtualInputManager")
end)
if not inputOK then virtualInput = nil end

local function tapReceive()
    if type(mouse1click) == "function" then
        return pcall(mouse1click)
    end
    if type(mouse1press) == "function" and type(mouse1release) == "function" then
        local ok = pcall(mouse1press)
        if ok then
            task.delay(0.055, function() pcall(mouse1release) end)
        end
        return ok
    end
    if virtualInput then
        local cam = workspace.CurrentCamera
        local size = cam and cam.ViewportSize or Vector2.new(720, 1280)
        local x, y = math.floor(size.X * 0.5), math.floor(size.Y * 0.5)
        local ok = pcall(function()
            virtualInput:SendMouseButtonEvent(x, y, 0, true, game, 0)
        end)
        if ok then
            task.delay(0.06, function()
                pcall(function()
                    virtualInput:SendMouseButtonEvent(x, y, 0, false, game, 0)
                end)
            end)
        end
        return ok
    end
    return false
end

local function tapDive()
    if type(keypress) == "function" and type(keyrelease) == "function" then
        local ok = pcall(function() keypress(0x11) end) -- 0x11: Control
        if ok then
            task.delay(0.085, function()
                pcall(function() keyrelease(0x11) end)
            end)
        end
        return ok
    end
    if virtualInput then
        local ok = pcall(function()
            virtualInput:SendKeyEvent(true, Enum.KeyCode.LeftControl, false, game)
        end)
        if ok then
            task.delay(0.085, function()
                pcall(function()
                    virtualInput:SendKeyEvent(false, Enum.KeyCode.LeftControl, false, game)
                end)
            end)
        end
        return ok
    end
    return false
end

local function tryAutoDefense(spot, landingTime, velocity)
    if not autoDefenseOn or not spot or not landingTime then return end
    if velocity.Y >= -0.75 then return end -- somente bola descendo
    if landingTime > 0.9 or landingTime < 0.06 then return end
    if UserInputService:GetFocusedTextBox() then return end

    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    if not hrp or not humanoid or humanoid.Health <= 0
       or humanoid.FloorMaterial == Enum.Material.Air then return end

    local offset = spot - hrp.Position
    local horizontal = Vector3.new(offset.X, 0, offset.Z).Magnitude
    if horizontal > 15.5 then return end
    if (trackedRoot.Position - hrp.Position).Magnitude > 30 then return end

    local action
    if horizontal <= 7.5 and landingTime <= 0.47 then
        action = "RECEPCAO"
    elseif autoDiveOn and horizontal > 7.5 and landingTime <= 0.85
        and landingTime >= 0.15 then
        action = "MERGULHO"
    else
        return
    end

    local now = os.clock()
    if now - lastDefenseTick < (action == "MERGULHO" and 1.45 or 0.95) then return end
    if lastDefenseBall == trackedBall and lastDefenseSpot
        and (lastDefenseSpot - spot).Magnitude < 3.5
        and now - lastDefenseTick < 1.75 then return end

    lastDefenseTick = now
    lastDefenseBall = trackedBall
    lastDefenseSpot = spot
    local didTrigger
    if action == "MERGULHO" then
        didTrigger = tapDive()
    else
        didTrigger = tapReceive()
    end
    lastDefenseAction = didTrigger and (action .. " ENVIADA") or "COMANDO NAO SUPORTADO"
end

bind(hitButton.MouseButton1Click, function()
    hitboxOn = not hitboxOn
    setHit(hitboxOn)
    if not hitboxOn then removeHitbox() else ensureHitbox() end
    saveSettings()
end)
bind(minusBtn.MouseButton1Click, function()
    hitboxDiameter = math.max(4, hitboxDiameter - 2)
    sizeText.Text = tostring(hitboxDiameter)
    if hitboxPart then ensureHitbox() end
    saveSettings()
end)
bind(plusBtn.MouseButton1Click, function()
    hitboxDiameter = math.min(20, hitboxDiameter + 2)
    sizeText.Text = tostring(hitboxDiameter)
    if hitboxPart then ensureHitbox() end
    saveSettings()
end)
bind(predictButton.MouseButton1Click, function()
    predictOn = not predictOn
    setPredict(predictOn)
    if not predictOn then hidePrediction() end
    saveSettings()
end)
bind(pathButton.MouseButton1Click, function()
    pathOn = not pathOn
    setPath(pathOn)
    if not pathOn then landingLine.Transparency = 1 end
    saveSettings()
end)
bind(fluidButton.MouseButton1Click, function()
    fluidMode = not fluidMode
    setFluid(fluidMode)
    saveSettings()
end)
bind(defenseButton.MouseButton1Click, function()
    autoDefenseOn = not autoDefenseOn
    setDefense(autoDefenseOn)
    lastDefenseTick = -100
    lastDefenseSpot = nil
    lastDefenseAction = ""
    saveSettings()
end)
bind(diveButton.MouseButton1Click, function()
    autoDiveOn = not autoDiveOn
    setDive(autoDiveOn)
    saveSettings()
end)

-- Atualizacao separada: procurar a bola custa mais que seguir uma ja encontrada.
-- O modo fluidez reduz raycasts/frequencia sem desativar a linha de queda.
local accumulator = 0
local ballSearchClock = 99
bind(RunService.Heartbeat, function(dt)
    if not running then return end
    if hitboxPart and trackedRoot and trackedRoot.Parent then
        hitboxPart.CFrame = trackedRoot.CFrame
    end

    ballSearchClock = ballSearchClock + dt
    local searchInterval = fluidMode and 0.80 or 0.40
    if ballSearchClock >= searchInterval then
        ballSearchClock = 0
        local ball, root = findBall()
        if ball ~= trackedBall or root ~= trackedRoot then
            removeHitbox()
            hidePrediction()
            trackedBall, trackedRoot = ball, root
            lastPosition, lastSampleTime = nil, nil
        end
    end

    accumulator = accumulator + dt
    local updateInterval = fluidMode and 0.21 or 0.095
    if accumulator < updateInterval then return end
    accumulator = 0

    local root = trackedRoot
    if not root or not root.Parent then
        hidePrediction()
        removeHitbox()
        status.Text = "PROCURANDO BOLA..."
        return
    end
    status.Text = autoDefenseOn and
        ("DEFESA AUTO: " .. (lastDefenseAction ~= "" and lastDefenseAction or "MONITORANDO"))
        or ("BOLA DETECTADA  |  HITBOX: " .. (hitboxOn and "ON" or "OFF"))
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
    local spot, landingTime = updatePrediction(position, velocity)
    if autoDefenseOn then tryAutoDefense(spot, landingTime, velocity) end
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