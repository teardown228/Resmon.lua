--ResorceMonitor.lua 
--By Kirgiz0_0

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- cfg
local CHECK_INTERVAL = 0.2              -- Interval
local OBJECTS_PER_SEC_THRESHOLD = 1000    -- Objpersec threshold
local FULLSCREEN_ZINDEX_THRESHOLD = 10  -- Zindex lmao
local FULLSCREEN_SIZE_EPS = 0.02        -- Vframe
local LOUD_VOLUME_THRESHOLD = 0.6       -- Sound.Volume >= & IsPlaying & Looping -> Sus
local LOG_MAX = 200                     -- лимиты по логу
-- internal state
local createdCount = 0
local lastCheckTime = tick()
local additionsThisInterval = 0
local logEntries = {} -- time.os и прочий мусор

local function pushLog(kind, desc)
	local entry = { time = os.time(), kind = kind, desc = desc }
	table.insert(logEntries, 1, entry)
	if #logEntries > LOG_MAX then
		table.remove(logEntries)
	end
	-- вывод в консось
	warn(string.format("[ActivityObserver] %s: %s", kind, desc))
end

-- Крутая утилита (пузище моровинда непостежимо)
local function isFullscreenGui(gui)
	-- проверяем основные признаки: Size примерно (1,1) и высокий ZIndex или Active=true
	if not gui or not gui:IsA("GuiObject") then return false end
	local size = gui.Size
	-- сравнение масштабных компонентов
	local sx = math.abs((size.X.Scale or 0) - 1)
	local sy = math.abs((size.Y.Scale or 0) - 1)
	if sx <= FULLSCREEN_SIZE_EPS and sy <= FULLSCREEN_SIZE_EPS then
		if (gui.ZIndex and gui.ZIndex >= FULLSCREEN_ZINDEX_THRESHOLD) or gui.Active == true then
			return true
		end
	end
	return false
end

local function inspectInstance(inst)
	-- вызывается при добавлении нового объекта, только чтение
	if not inst then return end
	local t = inst.ClassName or inst:GetClassName()

	-- GUI
	if inst:IsA("GuiObject") then
		if isFullscreenGui(inst) then
			pushLog("FullscreenGUI", ("Found fullscreen GUI: %s (%s)"):format(inst:GetFullName(), t))
		end
		-- чекаем большой текстлейбл слэш гуи
		if inst:IsA("TextLabel") or inst:IsA("TextBox") then
			local txt = inst.Text
			if txt and #txt > 5000 then
				pushLog("LargeText", ("Huge text label: %s length=%d"):format(inst:GetFullName(), #txt))
			end
		end
	end

	-- VideoFrame
	if inst:IsA("VideoFrame") then
		if isFullscreenGui(inst) then
			pushLog("VideoFrameFull", ("Fullscreen VideoFrame: %s"):format(inst:GetFullName()))
		else
			pushLog("VideoFrame", ("VideoFrame: %s size=%s"):format(inst:GetFullName(), tostring(inst.Size)))
		end
	end

	-- Sound
	if inst:IsA("Sound") then
		local playing = inst.IsPlaying
		local looped = inst.Looped
		local vol = inst.Volume or 0
		local name = inst.Name
		if playing and looped and vol >= LOUD_VOLUME_THRESHOLD then
			pushLog("LoudLoopSound", ("Sound playing (loop): %s volume=%.2f path=%s"):format(name, vol, inst:GetFullName()))
		end
	end

	-- Particle/heavy objects
	if inst:IsA("ParticleEmitter") then
		pushLog("Particle", ("ParticleEmitter added: %s"):format(inst:GetFullName()))
	end
	if inst:IsA("Part") or inst:IsA("MeshPart") then
		-- Детектим если скриптопидор спавнит много новых партов
		-- нууу еще после then пусто потому что я тупой и у меня нет мозгов я придурок
	end
end

-- вызов DescendantAdded для PlayerGui и Workspace
local function setupObservers()
	local function onAdded(inst)
		additionsThisInterval = additionsThisInterval + 1
		inspectInstance(inst)
	end

	PlayerGui.DescendantAdded:Connect(onAdded)
	workspace.DescendantAdded:Connect(onAdded)
	-- если нужно можно также слушать ReplicatedStorage / ServerStorage (только чтение)
	-- но это потенциально бесполезно, поэтому оставлено выключенно по умолчанию
end

-- HUD для оповещений (говно тип)
local function createHUD()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ActivityObserverHUD"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = PlayerGui

	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0, 1)
	frame.Position = UDim2.new(0.01, 0, 0.98, 0)
	frame.Size = UDim2.new(0, 320, 0, 120)
	frame.BackgroundTransparency = 0.3
	frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	frame.BorderSizePixel = 0
	frame.Parent = screenGui

	local title = Instance.new("TextLabel", frame)
	title.Size = UDim2.new(1, -10, 0, 24)
	title.Position = UDim2.new(0, 5, 0, 5)
	title.Text = "Watcher"
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.new(1,1,1)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.SourceSansSemibold
	title.TextSize = 18

	local status = Instance.new("TextLabel", frame)
	status.Name = "Status"
	status.Size = UDim2.new(1, -10, 0, 60)
	status.Position = UDim2.new(0, 5, 0, 30)
	status.Text = "Idle"
	status.TextWrapped = true
	status.TextColor3 = Color3.new(1,0.8,0)
	status.BackgroundTransparency = 1
	status.Font = Enum.Font.SourceSans
	status.TextSize = 14
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.TextYAlignment = Enum.TextYAlignment.Top

local btnMute = Instance.new("TextButton", frame)
btnMute.Size = UDim2.new(0, 150, 0, 24)
btnMute.Position = UDim2.new(0, 5, 1, -29)
btnMute.Text = "Mute (system)"
btnMute.Font = Enum.Font.SourceSans
btnMute.TextSize = 14

local soundService = game:GetService("SoundService")
local starterGui = game:GetService("StarterGui")

local muted = false -- флаг состояния звука

btnMute.MouseButton1Click:Connect(function()
	muted = not muted

	if muted then
		soundService.Volume = 0
		btnMute.Text = "Unmute (system)"
		starterGui:SetCore("SendNotification", {
			Title = "ActivityObserver",
			Text = "Звук выключен",
			Duration = 4
		})
	else
		soundService.Volume = 1
		btnMute.Text = "Mute (system)"
		starterGui:SetCore("SendNotification", {
			Title = "ActivityObserver",
			Text = "Звук включен",
			Duration = 4
		})
	end
end)


	local btnLog = Instance.new("TextButton", frame)
	btnLog.Size = UDim2.new(0, 150, 0, 24)
	btnLog.Position = UDim2.new(0, 165, 1, -29)
	btnLog.Text = "Open Log"
	btnLog.Font = Enum.Font.SourceSans
	btnLog.TextSize = 14

	btnLog.MouseButton1Click:Connect(function()
		local lines = {}
		for i = 1, math.min(#logEntries, 50) do
			local e = logEntries[i]
			table.insert(lines, os.date("%Y-%m-%d %H:%M:%S", e.time) .. " [" .. e.kind .. "] " .. e.desc)
		end
		local msg = table.concat(lines, "\n")
		-- выводим в консоль и уведомление
		print("[ActivityObserver] Last log:\n" .. msg)
		StarterGui:SetCore("SendNotification", {
			Title = "ActivityObserver";
			Text = "Лог выведен в Output (F9). См. последние записи.";
			Duration = 5;
		})
	end)

	return screenGui, status
end

-- Основной цикл: проверяем вспышки создания объектов (спред)
local function startMonitor()
	setupObservers()
	local hud, statusLabel = createHUD()

	RunService.Heartbeat:Connect(function(dt)
		-- раз в 0.2 (ссылаясь на чек интервал) секунд проверим интенсивность добавлений
		local now = tick()
		if now - lastCheckTime >= CHECK_INTERVAL then
			local rate = additionsThisInterval / math.max(1, now - lastCheckTime)
			if rate >= OBJECTS_PER_SEC_THRESHOLD then
				pushLog("Spike", ("High creation rate: %.1f objects/sec"):format(rate))
				statusLabel.Text = ("!!! Suspicious activity: %.1f objects/sec\nPress 'Open Log' to view. Record video and submit to Trust & Safety."):format(rate)
				StarterGui:SetCore("SendNotification", {
					Title = "Warning: abnormal activity";
					Text = ("Создано %.0f объектов/за %.2fс — Аномальная нагрузка."):format(additionsThisInterval, now - lastCheckTime);
					Duration = 6;
				})
			else
				-- обновляем статус
				if additionsThisInterval > 0 then
					statusLabel.Text = ("Activity: %.1f obj/sec (recent)"):format(rate)
				else
					statusLabel.Text = "Idle"
				end
			end

			-- сброс счётчиков
			lastCheckTime = now
			additionsThisInterval = 0
		end
	end)
end

-- Запуск
pushLog("Info", "ActivityObserver started")
startMonitor()
