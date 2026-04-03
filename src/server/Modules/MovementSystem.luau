--[[
	MovementSystem.luau
	Created: [07/12/2025]
	Last Modified: [08/12/2025]
	
	FEATURES:
		- Dash with animation and velocity boost
		- Per-player cooldown management
		- Customizable hotkeys
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local TroveModule = require(ReplicatedStorage.ServerPackages.Trove)

-- Try to get ObjectPool if it exists
local ObjectPool
local hasObjectPool = pcall(function()
	ObjectPool = require(ReplicatedStorage.ServerPackages.ObjectPool)
end)

local MovementSystem = {}
MovementSystem.__index = MovementSystem

-- Constants
local DASH_ANIMATION_ID = "rbxassetid://113300913723343"
local DASH_VELOCITY = 250
local DASH_DURATION = 0.1
local DASH_COOLDOWN = 1

local SLIDE_COOLDOWN = 0
local SLIDE_VELOCITY = 40
local SLIDE_DURATION = 1

-- Movement configurations
local MOVEMENT_CONFIGS = {
	Dash = {
		Cooldown = DASH_COOLDOWN,
		RequiresUndo = false,
	},
	Slide = {
		Cooldown = SLIDE_COOLDOWN,
		RequiresUndo = false,
	},
}

export type NewPlayerMovement = {
	Player: Player,
	Hotkeys: { [string]: Enum.KeyCode }?,
	MovementOptions: {
		Dash: boolean?,
		Slide: boolean?,
	},
}

-- Create BodyVelocity pool if ObjectPool is available
local BodyVelocityPool
local BodyGyroPool
if hasObjectPool then
	BodyVelocityPool = ObjectPool.new(
		function()
			local bv = Instance.new("BodyVelocity")
			bv.MaxForce = Vector3.new(math.huge, 0, math.huge)
			return bv
		end,
		10, -- Pool size
		function(bv: BodyVelocity)
			-- On get - already configured in creation
		end,
		function(bv: BodyVelocity)
			-- On free
			bv.Parent = nil
			bv.Velocity = Vector3.zero
		end
	)

	BodyGyroPool = ObjectPool.new(
		function()
			local bg = Instance.new("BodyGyro")
			bg.MaxTorque = Vector3.new(0, math.huge, 0)
			bg.P = 10000
			return bg
		end,
		10, -- Pool size
		function(bg: BodyGyro)
			-- On get - already configured in creation
		end,
		function(bg: BodyGyro)
			-- On free
			bg.Parent = nil
			bg.CFrame = CFrame.new()
		end
	)
end

function MovementSystem.new(Info: NewPlayerMovement)
	local self = setmetatable({}, MovementSystem)

	self.Player = Info.Player
	self.Hotkeys = Info.Hotkeys or {
		Dash = Enum.KeyCode.Q,
		Slide = Enum.KeyCode.C,
	}
	self.MovementOptions = Info.MovementOptions

	-- Initialize player data
	if not MovementSystem._PlayerInfo then
		MovementSystem._PlayerInfo = {}
	end

	MovementSystem._PlayerInfo[Info.Player] = {
		Hotkeys = self.Hotkeys,
		MovementOptions = self.MovementOptions,
		MovementCooldowns = {},
		MovementsOnCooldown = {},
		AnimationTracks = {},
		Character = nil,
		Humanoid = nil,
		RootPart = nil,
		Trove = TroveModule.new(), -- Per-player Trove for cleanup
	}

	-- Setup cooldowns from config
	for MovementName, Config in pairs(MOVEMENT_CONFIGS) do
		MovementSystem._PlayerInfo[Info.Player].MovementCooldowns[MovementName] = Config.Cooldown
		MovementSystem._PlayerInfo[Info.Player].MovementsOnCooldown[MovementName] = false
	end

	-- Cache character references
	self:_UpdateCharacterReferences(Info.Player)

	-- Handle character respawns
	local CharacterConnection = Info.Player.CharacterAdded:Connect(function()
		task.wait(0.1) -- Small delay for character to load
		self:_UpdateCharacterReferences(Info.Player)
	end)

	-- Add connection to trove
	local PlayerData = MovementSystem._PlayerInfo[Info.Player]
	if PlayerData then
		PlayerData.Trove:Add(CharacterConnection)
	end

	-- Cleanup on player leave
	Players.PlayerRemoving:Connect(function(LeavingPlayer)
		if LeavingPlayer == Info.Player then
			self:_Cleanup(Info.Player)
		end
	end)

	return self
end

local function SetCharacterMassless(Character: Model, massless: boolean)
	for _, part in pairs(Character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Massless = massless
		end
	end
end

function MovementSystem:_UpdateCharacterReferences(Player: Player)
	local PlayerData = MovementSystem._PlayerInfo[Player]
	if not PlayerData then
		return
	end

	local Character = Player.Character
	if not Character then
		return
	end

	PlayerData.Character = Character
	PlayerData.Humanoid = Character:FindFirstChildOfClass("Humanoid")
	PlayerData.RootPart = Character:FindFirstChild("HumanoidRootPart")

	-- Pre-load dash animation
	if PlayerData.Humanoid and not PlayerData.AnimationTracks.Dash then
		local DashAnim = Instance.new("Animation")
		DashAnim.AnimationId = DASH_ANIMATION_ID
		PlayerData.AnimationTracks.Dash = PlayerData.Humanoid:LoadAnimation(DashAnim)

		-- Add animation to trove for cleanup
		PlayerData.Trove:Add(PlayerData.AnimationTracks.Dash)
		PlayerData.Trove:Add(DashAnim)
	end
end

function MovementSystem:_Cleanup(Player: Player)
	local PlayerData = MovementSystem._PlayerInfo[Player]
	if not PlayerData then
		return
	end

	-- Clean up everything with Trove (animations, connections, etc.)
	if PlayerData.Trove then
		PlayerData.Trove:Clean()
	end

	-- Clear player data
	MovementSystem._PlayerInfo[Player] = nil
end

function MovementSystem:GetMovementInfo(Player: Player)
	local PlayerData = MovementSystem._PlayerInfo[Player]
	if not PlayerData then
		return nil
	end

	return {
		Hotkeys = PlayerData.Hotkeys,
		MovementOptions = PlayerData.MovementOptions,
		Cooldowns = PlayerData.MovementCooldowns,
	}
end

function MovementSystem:_PerformDash(Player: Player)
	local PlayerData = MovementSystem._PlayerInfo[Player]
	if not PlayerData then
		return
	end

	-- Check references
	if not PlayerData.Humanoid or not PlayerData.RootPart then
		self:_UpdateCharacterReferences(Player)
		if not PlayerData.Humanoid or not PlayerData.RootPart then
			warn("Failed to get character references for dash")
			return
		end
	end

	-- Check cooldown
	if PlayerData.MovementsOnCooldown.Dash then
		return
	end

	-- Start cooldown
	PlayerData.MovementsOnCooldown.Dash = true

	-- Disable ragdoll states
	PlayerData.Humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	PlayerData.Humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)

	-- Make character massless and set custom physical properties
	SetCharacterMassless(PlayerData.Character, true)

	-- Store original CustomPhysicalProperties
	local originalProps = PlayerData.RootPart.CustomPhysicalProperties
	PlayerData.RootPart.CustomPhysicalProperties = PhysicalProperties.new(
		0.7, -- Density
		0, -- Friction (set to 0 to slide better)
		0, -- Elasticity (set to 0 to not bounce)
		1, -- FrictionWeight
		1 -- ElasticityWeight
	)

	-- Lock rotation
	local BodyGyro
	if hasObjectPool and BodyGyroPool then
		BodyGyro = BodyGyroPool:get()
	else
		BodyGyro = Instance.new("BodyGyro")
		BodyGyro.MaxTorque = Vector3.new(0, math.huge, 0)
		BodyGyro.P = 10000
	end
	BodyGyro.CFrame = PlayerData.RootPart.CFrame
	BodyGyro.Parent = PlayerData.RootPart

	-- Get dash direction
	local LookVector = PlayerData.RootPart.CFrame.LookVector
	local DashVelocity = LookVector * DASH_VELOCITY

	-- Apply velocity using AssemblyLinearVelocity instead of BodyVelocity
	PlayerData.RootPart.AssemblyLinearVelocity = DashVelocity

	local DashTrack = PlayerData.AnimationTracks.Dash
	if DashTrack then
		DashTrack:Play()
	end

	-- Create a temporary trove for this dash instance
	local DashTrove = TroveModule.new()

	-- Track last position to detect collision
	local lastPosition = PlayerData.RootPart.Position
	local stuckFrames = 0

	-- Create velocity management connection
	local velocityConnection = game:GetService("RunService").Heartbeat:Connect(function()
		if not PlayerData.RootPart then
			return
		end

		-- Check if we've moved since last frame
		local currentPosition = PlayerData.RootPart.Position
		local distanceMoved = (currentPosition - lastPosition).Magnitude

		if distanceMoved < 0.1 then
			stuckFrames = stuckFrames + 1
			-- If stuck for 2+ frames, we hit something - stop everything
			if stuckFrames >= 2 then
				PlayerData.RootPart.AssemblyLinearVelocity = Vector3.zero
				PlayerData.RootPart.AssemblyAngularVelocity = Vector3.zero
				DashTrove:Clean()
			end
		else
			stuckFrames = 0
			-- Keep applying the dash velocity
			PlayerData.RootPart.AssemblyLinearVelocity = DashVelocity
			PlayerData.RootPart.AssemblyAngularVelocity = Vector3.zero
		end

		lastPosition = currentPosition
	end)
	DashTrove:Add(velocityConnection)

	-- Remove velocity after duration
	task.delay(DASH_DURATION, function()
		-- Clean up the trove
		DashTrove:Clean()

		-- Stop all velocity
		if PlayerData.RootPart then
			PlayerData.RootPart.AssemblyLinearVelocity = Vector3.zero
			PlayerData.RootPart.AssemblyAngularVelocity = Vector3.zero
		end

		-- Remove rotation lock
		if BodyGyro and BodyGyro.Parent then
			if hasObjectPool and BodyGyroPool then
				BodyGyroPool:free(BodyGyro)
			else
				BodyGyro:Destroy()
			end
		end

		-- Restore properties
		if PlayerData.Character and PlayerData.Humanoid and PlayerData.RootPart then
			SetCharacterMassless(PlayerData.Character, false)
			PlayerData.RootPart.CustomPhysicalProperties = originalProps
			PlayerData.Humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
			PlayerData.Humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true)
		end
	end)

	-- Reset cooldown
	task.delay(PlayerData.MovementCooldowns.Dash or DASH_COOLDOWN, function()
		if MovementSystem._PlayerInfo[Player] then
			PlayerData.MovementsOnCooldown.Dash = false
		end
	end)
end

function MovementSystem:_PerformSlide(Player: Player)
	local PlayerData = MovementSystem._PlayerInfo[Player]
	if not PlayerData then
		return
	end

	-- Check references
	if not PlayerData.Humanoid or not PlayerData.RootPart then
		self:_UpdateCharacterReferences(Player)
		if not PlayerData.Humanoid or not PlayerData.RootPart then
			warn("Failed to get character references for slide")
			return
		end
	end

	-- Check cooldown
	if PlayerData.MovementsOnCooldown.Slide then
		return
	end

	-- Start cooldown
	PlayerData.MovementsOnCooldown.Slide = true

	-- Disable ragdoll states
	PlayerData.Humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	PlayerData.Humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)

	-- Make character massless and set custom physical properties
	SetCharacterMassless(PlayerData.Character, true)

	-- Store original CustomPhysicalProperties
	local originalProps = PlayerData.RootPart.CustomPhysicalProperties
	PlayerData.RootPart.CustomPhysicalProperties = PhysicalProperties.new(
		0.7, -- Density
		0, -- Friction
		0, -- Elasticity
		1, -- FrictionWeight
		1 -- ElasticityWeight
	)

	-- Lock rotation
	local BodyGyro
	if hasObjectPool and BodyGyroPool then
		BodyGyro = BodyGyroPool:get()
	else
		BodyGyro = Instance.new("BodyGyro")
		BodyGyro.MaxTorque = Vector3.new(0, math.huge, 0)
		BodyGyro.P = 10000
	end
	BodyGyro.CFrame = PlayerData.RootPart.CFrame
	BodyGyro.Parent = PlayerData.RootPart

	-- Get slide direction
	local LookVector = PlayerData.RootPart.CFrame.LookVector
	local SlideVelocity = LookVector * SLIDE_VELOCITY

	-- Apply velocity using AssemblyLinearVelocity
	PlayerData.RootPart.AssemblyLinearVelocity = SlideVelocity

	-- Create a temporary trove for this slide instance
	local SlideTrove = TroveModule.new()

	-- Track last position to detect collision
	local lastPosition = PlayerData.RootPart.Position
	local stuckFrames = 0

	-- Create velocity management connection
	local velocityConnection = game:GetService("RunService").Heartbeat:Connect(function()
		if not PlayerData.RootPart then
			return
		end

		-- Check if we've moved since last frame
		local currentPosition = PlayerData.RootPart.Position
		local distanceMoved = (currentPosition - lastPosition).Magnitude

		if distanceMoved < 0.1 then
			stuckFrames = stuckFrames + 1
			-- If stuck for 2+ frames, we hit something - stop everything
			if stuckFrames >= 2 then
				PlayerData.RootPart.AssemblyLinearVelocity = Vector3.zero
				PlayerData.RootPart.AssemblyAngularVelocity = Vector3.zero
				SlideTrove:Clean()
			end
		else
			stuckFrames = 0
			-- Keep applying the slide velocity
			PlayerData.RootPart.AssemblyLinearVelocity = SlideVelocity
			PlayerData.RootPart.AssemblyAngularVelocity = Vector3.zero
		end

		lastPosition = currentPosition
	end)
	SlideTrove:Add(velocityConnection)

	-- Play animation
	local SlideTrack = PlayerData.AnimationTracks.Slide
	if SlideTrack then
		SlideTrack:Play()
	end

	-- Remove velocity and gyro after duration
	task.delay(SLIDE_DURATION, function()
		-- Clean up the trove
		SlideTrove:Clean()

		-- Stop all velocity
		if PlayerData.RootPart then
			PlayerData.RootPart.AssemblyLinearVelocity = Vector3.zero
			PlayerData.RootPart.AssemblyAngularVelocity = Vector3.zero
		end

		-- Remove rotation lock
		if BodyGyro and BodyGyro.Parent then
			if hasObjectPool and BodyGyroPool then
				BodyGyroPool:free(BodyGyro)
			else
				BodyGyro:Destroy()
			end
		end

		-- Restore properties
		if PlayerData.Character and PlayerData.Humanoid and PlayerData.RootPart then
			SetCharacterMassless(PlayerData.Character, false)
			PlayerData.RootPart.CustomPhysicalProperties = originalProps
			PlayerData.Humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
			PlayerData.Humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true)
		end
	end)

	-- Reset cooldown
	task.delay(PlayerData.MovementCooldowns.Slide or SLIDE_COOLDOWN, function()
		if MovementSystem._PlayerInfo[Player] then
			PlayerData.MovementsOnCooldown.Slide = false
		end
	end)
end

function MovementSystem:Movement(AttemptMovementOption: string, Player: Player, Camera: CFrame?)
	-- Validate player
	if not Player or not MovementSystem._PlayerInfo[Player] then
		warn("Invalid player for movement")
		return
	end

	-- Movement function map
	local MovementFunctions = {
		Dash = function()
			self:_PerformDash(Player)
		end,
		DashUndo = function() end, -- Dash doesn't need undo

		Slide = function()
			self:_PerformSlide(Player)
		end,

		SlideUndo = function() end, -- Slide doesn't need undo
	}

	local MovementFunction = MovementFunctions[AttemptMovementOption]
	if MovementFunction then
		MovementFunction()
	else
		warn(`Unknown movement option: {AttemptMovementOption}`)
	end
end

-- Cleanup all players on shutdown
function MovementSystem:Destroy()
	for Player, _ in pairs(MovementSystem._PlayerInfo or {}) do
		self:_Cleanup(Player)
	end

	if hasObjectPool and BodyVelocityPool then
		BodyVelocityPool:clear()
	end
end

return MovementSystem
