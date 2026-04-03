--[[
	Server Main Script
	Created: [05/12/2025]
	Last Modified: [08/12/2025]
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- Folders
local Models = ServerStorage.Models
local Sounds = ServerStorage.Sounds
local Shared = ReplicatedStorage.Shared
local RemotesFolder = Shared.Remotes

-- Systems
local GunSystem = require(script.Modules.GunSystem)
local MovementSystem = require(script.Modules.MovementSystem)
task.spawn(function()
	require(script.Modules.ExtraSystems)
end)

-- Constants
local CHARACTER_LOAD_DELAY = 1
local DEFAULT_WALK_SPEED = 16

local ANIMATION_IDS = {
	Idle = "rbxassetid://119487229730482",
	Walk = "rbxassetid://98890454362994",
	Run = "rbxassetid://131547780245919",
	Jump = "rbxassetid://79528716593701",
	Fall = "rbxassetid://131572427032406",
}

-- Remote Events Setup
local Remotes = {}

local function CreateRemotes()
	local RemoteDefinitions = {
		AttemptShoot = "RemoteEvent",
		GunShot = "RemoteEvent",
		GunEquipped = "BindableEvent",
		GunUnequipped = "BindableEvent",
		GetAmmo = "RemoteFunction",
		AttemptMovement = "RemoteEvent",
		AttemptTeleport = "RemoteEvent",
	}

	for Name, InstanceType in pairs(RemoteDefinitions) do
		local Remote = Instance.new(InstanceType)
		Remote.Name = Name
		Remote.Parent = RemotesFolder
		Remotes[Name] = Remote
	end
end

CreateRemotes()

-- Gun Configurations
local Guns = {}

local function InitializeGuns()
	Guns.Pistol = GunSystem.new({
		Name = "Pistol",
		FireRate = 3,
		FirePower = 10,
		FireSound = Sounds.Pistol:FindFirstChildOfClass("Sound"),
		Ammo = 16,
		Auto = false,
		ReloadTime = 3,
		MaxAmmo = 16,
		GunModel = Models.Pistol.Handle,
		GunAbilities = {
			ShootFast = function(self)
				local OriginalRate = self.FireRate
				self._ChangeStats("FireRate", OriginalRate * 10)
				task.delay(5, function()
					self._ChangeStats("FireRate", OriginalRate)
				end)
			end,
			PowerShot = function(self)
				local OriginalPower = self.FirePower
				self._ChangeStats("FirePower", OriginalPower * 3)
				task.delay(5, function()
					self._ChangeStats("FirePower", OriginalPower)
				end)
			end,
			Reload = function(self)
				self._Reload()
			end,
		},
		AbilitiesCooldown = {
			ShootFast = 3,
			PowerShot = 3,
		},
	})

	Guns.AutoRifle = GunSystem.new({
		Name = "AutoRifle",
		FireRate = 10,
		FirePower = 10,
		FireSound = Sounds.AutoRifle:FindFirstChildOfClass("Sound"),
		Ammo = 30,
		Auto = true,
		ReloadTime = 3,
		MaxAmmo = 30,
		GunModel = Models.AutoRifle.Handle,
		GunAbilities = {
			ShootFast = function(self)
				local OriginalRate = self.FireRate
				self._ChangeStats("FireRate", OriginalRate * 2)
				task.delay(5, function()
					self._ChangeStats("FireRate", OriginalRate)
				end)
			end,
			PowerShot = function(self)
				local OriginalPower = self.FirePower
				self._ChangeStats("FirePower", OriginalPower * 3)
				task.delay(5, function()
					self._ChangeStats("FirePower", OriginalPower)
				end)
			end,
			Reload = function(self)
				self._Reload()
			end,
		},
		AbilitiesCooldown = {
			ShootFast = 3,
			PowerShot = 3,
		},
	})
end

InitializeGuns()

-- Helper Functions
local function SetupCharacterAnimations(Character: Model)
	local Animate = Character:FindFirstChild("Animate")
	if not Animate then
		return
	end

	-- Set Idle Animations
	local Idle = Animate:FindFirstChild("idle")
	if Idle then
		local IdleAnim1 = Idle:FindFirstChild("Animation1")
		local IdleAnim2 = Idle:FindFirstChild("Animation2")
		if IdleAnim1 then
			IdleAnim1.AnimationId = ANIMATION_IDS.Idle
		end
		if IdleAnim2 then
			IdleAnim2.AnimationId = ANIMATION_IDS.Idle
		end
	end

	-- Set Walk Animation
	local Walk = Animate:FindFirstChild("walk")
	if Walk then
		local WalkAnim = Walk:FindFirstChild("WalkAnim")
		if WalkAnim then
			WalkAnim.AnimationId = ANIMATION_IDS.Walk
		end
	end

	-- Set Run Animation
	local Run = Animate:FindFirstChild("run")
	if Run then
		local RunAnim = Run:FindFirstChild("RunAnim")
		if RunAnim then
			RunAnim.AnimationId = ANIMATION_IDS.Run
		end
	end

	-- Set Jump Animation
	local Jump = Animate:FindFirstChild("jump")
	if Jump then
		local JumpAnim = Jump:FindFirstChild("JumpAnim")
		if JumpAnim then
			JumpAnim.AnimationId = ANIMATION_IDS.Jump
		end
	end

	-- Set Fall Animation
	local Fall = Animate:FindFirstChild("fall")
	if Fall then
		local FallAnim = Fall:FindFirstChild("FallAnim")
		if FallAnim then
			FallAnim.AnimationId = ANIMATION_IDS.Fall
		end
	end
end

local function SetupCharacter(Character: Model)
	-- Setup humanoid
	local Humanoid = Character:WaitForChild("Humanoid", 5)
	if Humanoid then
		Humanoid.WalkSpeed = DEFAULT_WALK_SPEED
	end

	-- Setup animations
	SetupCharacterAnimations(Character)
end

local function GivePlayerWeapons(Player: Player)
	if not Player or not Player.Parent then
		return
	end

	-- Give weapons
	for _, Gun in pairs(Guns) do
		Gun:GiveWeapon(Player)
	end

	-- Initialize movement system
	MovementSystem.new({
		Player = Player,
		Hotkeys = {},
		MovementOptions = {
			Dash = true,
			Slide = true,
		},
	})
end

local function ValidatePlayerGun(Player: Player, GunName: string): boolean
	if not Player or not GunName then
		return false
	end

	local Backpack = Player:FindFirstChild("Backpack")
	local Character = Player.Character

	if Backpack and Backpack:FindFirstChild(GunName) then
		return true
	end

	if Character and Character:FindFirstChild(GunName) then
		return true
	end

	return false
end

-- Player Setup
local function OnPlayerAdded(Player: Player)
	Player:LoadCharacterAsync()

	-- Handle character spawning
	Player.CharacterAdded:Connect(function(Character)
		SetupCharacter(Character)
	end)

	-- Give weapons after short delay
	task.delay(CHARACTER_LOAD_DELAY, function()
		GivePlayerWeapons(Player)
	end)
end

-- Cleanup on player leaving
local function OnPlayerRemoving(Player: Player)
	MovementSystem:_Cleanup(Player)
end

Players.PlayerAdded:Connect(OnPlayerAdded)
Players.PlayerRemoving:Connect(OnPlayerRemoving)

-- Handle existing players (for testing)
for _, Player in ipairs(Players:GetPlayers()) do
	task.spawn(OnPlayerAdded, Player)
end

-- Remote Event Handlers
Remotes.AttemptShoot.OnServerEvent:Connect(
	function(
		Player: Player,
		OtherPlayer: Player,
		MousePosition: Vector3,
		Target: BasePart?,
		GunName: string?,
		Camera: CFrame?,
		Ability: boolean?,
		HotkeyChosen: Enum.KeyCode?,
		AbilityName: string?
	)
		-- Validate inputs
		if not Player or not OtherPlayer or not GunName then
			warn("Invalid shoot parameters")
			return
		end

		local Gun = Guns[GunName]
		if not Gun then
			warn(`Gun not found: {GunName}`)
			return
		end

		-- Validate player has gun equipped
		if not ValidatePlayerGun(Player, GunName) then
			warn(`Player {Player.Name} doesn't have {GunName} equipped`)
			return
		end

		-- Execute shoot
		Gun:Shoot(OtherPlayer, MousePosition, Target, Camera, Ability, HotkeyChosen, AbilityName)
	end
)

Remotes.AttemptMovement.OnServerEvent:Connect(
	function(Player: Player, OtherPlayer: Player, MovementOption: string, Undo: boolean?, Camera: CFrame?)
		-- Validate inputs
		if not Player or not OtherPlayer or not MovementOption then
			warn("Invalid movement parameters")
			return
		end

		-- Execute movement
		if Undo then
			MovementSystem:Movement(`{MovementOption}Undo`, OtherPlayer, Camera)
		else
			MovementSystem:Movement(MovementOption, OtherPlayer, Camera)
		end
	end
)

Remotes.GetAmmo.OnServerInvoke = function(Player: Player, GunName: string?): number?
	-- Validate inputs
	if not Player or not GunName then
		return nil
	end

	local Gun = Guns[GunName]
	if not Gun then
		return nil
	end

	-- Validate player has gun
	if not ValidatePlayerGun(Player, GunName) then
		return nil
	end

	return Gun:GetAmmo(Player)
end

-- Cleanup (removed periodic cleanup - GunSystem handles it internally now)
game:BindToClose(function()
	-- Cleanup all gun systems
	for _, Gun in pairs(Guns) do
		if Gun.Destroy then
			Gun:Destroy()
		end
	end
end)
