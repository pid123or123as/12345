print('mega ai')
local ManualFinish = {}

function ManualFinish.Init(UI, Core, notify)
    local State = {
        ManualFinishEnabled = false
    }

    local ManualFinishConfig = {
        DistanceLimit = 35, -- Ограничение расстояния в 30 метров
        CheckInterval = 0.75 -- Проверка каждые 0.75 секунды
    }

    local lastCheck = 0
    local activePlayers = {}
    local playerFriendCache = {} -- Кэш для проверки друзей
    local attachedPrompts = {} -- Хранит привязанные ProximityPrompt

    local function processPlayer(player)
        if player == Core.PlayerData.LocalPlayer then return end
        activePlayers[player] = true
    end

    for _, player in ipairs(Core.Services.Players:GetPlayers()) do
        processPlayer(player)
    end

    Core.Services.Players.PlayerAdded:Connect(function(player)
        processPlayer(player)
    end)

    Core.Services.Players.PlayerRemoving:Connect(function(player)
        activePlayers[player] = nil
        playerFriendCache[player] = nil
        -- Возвращаем Prompt в исходное место, если он был перемещён
        if attachedPrompts[player] then
            local prompt = attachedPrompts[player]
            if prompt and prompt.Parent then
                prompt.Parent = player.Character and player.Character:FindFirstChild("HumanoidRootPart") or nil
            end
            attachedPrompts[player] = nil
        end
    end)

    Core.Services.RunService.RenderStepped:Connect(function(deltaTime)
        if not State.ManualFinishEnabled then
            -- Возвращаем все Prompt в исходное место, если функция отключена
            for player, prompt in pairs(attachedPrompts) do
                if prompt and prompt.Parent then
                    prompt.Parent = player.Character and player.Character:FindFirstChild("HumanoidRootPart") or nil
                end
                attachedPrompts[player] = nil
            end
            return
        end

        lastCheck = lastCheck + deltaTime
        if lastCheck < ManualFinishConfig.CheckInterval then return end
        lastCheck = 0

        local localChar = Core.PlayerData.LocalPlayer.Character
        local localRoot = localChar and localChar:FindFirstChild("HumanoidRootPart")
        if not (localChar and localRoot) then return end

        local localPos = localRoot.Position
        local distanceLimitSqr = ManualFinishConfig.DistanceLimit * ManualFinishConfig.DistanceLimit

        for player in pairs(activePlayers) do
            -- Проверка на друга
            local isFriend = playerFriendCache[player]
            if isFriend == nil then
                isFriend = Core.Services.FriendsList and Core.Services.FriendsList[player.Name:lower()] or false
                playerFriendCache[player] = isFriend
            end
            if isFriend then continue end

            -- Поиск персонажа в Workspace
            local character = Core.Services.Workspace:FindFirstChild(player.Name)
            if not character then continue end

            local humanoid = character:FindFirstChildOfClass("Humanoid")
            local rootPart = character:FindFirstChild("HumanoidRootPart")
            local finishPrompt = rootPart and rootPart:FindFirstChild("FinishPrompt")

            if not (humanoid and rootPart and finishPrompt and finishPrompt:IsA("ProximityPrompt")) then
                continue
            end

            if humanoid.Health <= 0 then continue end
            if not finishPrompt.Enabled then continue end

            local targetPos = rootPart.Position
            local distanceSqr = (localPos - targetPos).Magnitude ^ 2

            if distanceSqr <= distanceLimitSqr then
                -- Если игрок в радиусе, перемещаем Prompt к локальному игроку
                if not attachedPrompts[player] then
                    finishPrompt.Parent = localRoot
                    attachedPrompts[player] = finishPrompt
                end
            else
                -- Если игрок вышел из радиуса, возвращаем Prompt обратно
                if attachedPrompts[player] then
                    finishPrompt.Parent = rootPart
                    attachedPrompts[player] = nil
                end
            end
        end
    end)

    -- Создание новой секции в табе Auto
    if UI.Tabs and UI.Tabs.Auto then
        local ManualFinishSection = UI.Tabs.Auto:Section({ Name = "ManualFinish", Side = "Left" })
        if ManualFinishSection then
            ManualFinishSection:Header({ Name = "BringFinishPrompt" })
            ManualFinishSection:Toggle({
                Name = "Enabled",
                Default = State.ManualFinishEnabled,
                Callback = function(value)
                    State.ManualFinishEnabled = value
                end
            }, "ManualFinish")
        end
    end
end

return ManualFinish
