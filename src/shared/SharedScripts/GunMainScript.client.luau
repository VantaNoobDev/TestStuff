local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Player = game.Players.LocalPlayer
local Mouse = Player:GetMouse()
local Camera = workspace.CurrentCamera

if not script.Parent:IsA("Tool") then
	script.Enabled = false
	return
end

local Tool: Tool = script.Parent
local Remotes = ReplicatedStorage.Shared.Remotes
local HotkeySettings = require(ReplicatedStorage.Shared.SharedScripts.HotkeySettings)

-- Configuration
local IS_AUTO = script.Parent:GetAttribute("IsAuto") or false
local FIRE_RATE = script.Parent:GetAttribute("FireRate") or 1 -- Seconds between shots
local AbilityCount = script.Parent:GetAttribute("AbilityCount") or 0

-- State
local equipped = false
local firing = false
local lastShotTime = 0
local abilityActions = {}

-- Connections cleanup
local connections = {}

--[[
local function disconnect(name: string)
	if connections[name] then
		connections[name]:Disconnect()
		connections[name] = nil
	end
end
]]

local function disconnectAll()
	for name, conn in pairs(connections) do
		conn:Disconnect()
	end
	connections = {}
end

local function canShoot(): boolean
	if not equipped then
		return false
	end

	local now = tick()
	if now - lastShotTime < FIRE_RATE then
		return false
	end

	return true
end

local function shoot()
	if not canShoot() then
		return
	end

	lastShotTime = tick()

	-- Only send what server needs - it knows the player already
	Remotes.AttemptShoot:FireServer(Player, Mouse.Hit.Position, Mouse.Target, Tool.Name, Camera.CFrame)
end

local function onInputBegan(input: InputObject, processed: boolean)
	if processed then
		return
	end

	local isFireInput = input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
		or input.KeyCode == Enum.KeyCode.ButtonR2

	if not isFireInput then
		return
	end

	if IS_AUTO then
		firing = true
	else
		shoot()
	end
end

local function onInputEnded(input: InputObject, processed: boolean)
	local isFireInput = input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
		or input.KeyCode == Enum.KeyCode.ButtonR2

	if isFireInput and IS_AUTO then
		firing = false
	end
end

local function bindAbilities()
	for i = 1, AbilityCount do
		local hotkey: Enum.KeyCode = HotkeySettings[i]
		if not hotkey then
			continue
		end

		local actionName = `GunAbility_{Tool.Name}_{i}`

		local function abilityHandler(_: string, inputState: Enum.UserInputState)
			if inputState ~= Enum.UserInputState.End or not equipped then
				return
			end

			Remotes.AttemptShoot:FireServer(
				Player,
				Mouse.Hit.Position,
				Mouse.Target,
				Tool.Name,
				nil,
				true, -- isAbility
				hotkey,
				Tool:GetAttribute(tostring(hotkey))
			)
		end

		ContextActionService:BindAction(actionName, abilityHandler, false, hotkey)
		table.insert(abilityActions, actionName)
	end
end

local function unbindAbilities()
	for _, actionName in ipairs(abilityActions) do
		ContextActionService:UnbindAction(actionName)
	end
	table.clear(abilityActions)
end

Tool.Equipped:Connect(function()
	equipped = true
	Mouse.Icon = "rbxassetid://316279304"
	Player.CameraMode = Enum.CameraMode.LockFirstPerson

	Remotes.GunEquipped:Fire(Tool.Name)

	-- Bind input
	connections.inputBegan = UserInputService.InputBegan:Connect(onInputBegan)
	connections.inputEnded = UserInputService.InputEnded:Connect(onInputEnded)

	-- Auto-fire loop (only runs if IS_AUTO is true)
	if IS_AUTO then
		connections.autoFire = RunService.Heartbeat:Connect(function()
			if firing then
				shoot()
			end
		end)
	end

	bindAbilities()
end)

Tool.Unequipped:Connect(function()
	equipped = false
	firing = false

	Mouse.Icon = ""
	Player.CameraMode = Enum.CameraMode.Classic

	Remotes.GunUnequipped:Fire()

	disconnectAll()
	unbindAbilities()
end)
