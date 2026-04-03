--[[
	GunSystem.luau
	Created: [08/12/2025]
	Last Modified: [08/12/2025]
	
	FEATURES:
		- Automatic and semi-automatic fire modes
		- Customizable abilities with cooldowns
		- Headshot multiplier (2x damage)
		- Per-player ammo and reload tracking
	
	USAGE:
		local GunSystem = require(path.to.GunSystem)
		
		local MyGun = GunSystem.new({
			Name = "Rifle",
			FireRate = 10,
			FirePower = 25,
			FireSound = SoundInstance,
			Ammo = 30,
			Auto = true,
			ReloadTime = 2,
			MaxAmmo = 30,
			GunModel = ModelInstance,
			GunAbilities = {
				ShootFaster = function(self) -- ability code end,
			},
			AbilitiesCooldown = { ShootFaster = 5 }
		})
		
		MyGun:GiveWeapon(player)
		MyGun:Shoot(player, mousePos, target)
	
	NOTES:
		- Bullet/beam pools start at 20 each, adjust BULLET_POOL_SIZE/BEAM_POOL_SIZE if needed
		- Headshot detection checks for part named "Head"
		- Remember to call :Destroy() when removing gun system
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local TroveModule = require(ReplicatedStorage.ServerPackages.Trove)
local ObjectPool = require(ReplicatedStorage.ServerPackages.ObjectPool)
local AbilitiesHotkey = require(ReplicatedStorage.Shared.SharedScripts.HotkeySettings)

local GunSystem = {}
GunSystem.__index = GunSystem

export type NewGun = {
	Name: string,
	FireRate: number,
	FirePower: number,
	FireSound: Sound,
	Ammo: number,
	Auto: boolean,
	ReloadTime: number,
	MaxAmmo: number,
	GunModel: Model | Folder,
	GunAbilities: { [string]: (any) -> () }?,
	AbilitiesCooldown: { [string]: number }?,
}

-- Constants
local HEADSHOT_MULTIPLIER = 2
local BEAM_LIFETIME = 0.025
local BULLET_VISUAL_LIFETIME = 3
local BULLET_POOL_SIZE = 20
local BEAM_POOL_SIZE = 20

-- Helper function
local function GunRateToTime(FireRate: number): number
	return FireRate and (3 / FireRate) or 1
end

-- Object pool creation functions
local function CreateBulletPart(): Part
	local Part = Instance.new("Part")
	Part.Anchored = true
	Part.CanCollide = false
	Part.CanTouch = false
	Part.CanQuery = false
	Part.Transparency = 0.1
	Part.BrickColor = BrickColor.Yellow()
	Part.Size = Vector3.new(0.1, 0.1, 0.3)

	local SelectionBox = Instance.new("SelectionBox")
	SelectionBox.Color3 = Color3.fromRGB(0, 0, 0)
	SelectionBox.Transparency = 0
	SelectionBox.Adornee = Part
	SelectionBox.LineThickness = 0.005
	SelectionBox.Parent = Part

	local Attachment = Instance.new("Attachment")
	Attachment.Parent = Part

	return Part
end

local function CreateBeam(): Beam
	local Beam = Instance.new("Beam")
	Beam.Width0 = 0.1
	Beam.Width1 = 0.1
	Beam.Color = ColorSequence.new(Color3.new(1, 1, 1))
	return Beam
end

function GunSystem.new(Info: NewGun)
	local Gun = setmetatable({}, GunSystem)

	Gun._Name = Info.Name
	Gun.FireRate = Info.FireRate
	Gun.FirePower = Info.FirePower
	Gun._FireSound = Info.FireSound:Clone()
	Gun._Ammo = Info.Ammo
	Gun._Auto = Info.Auto
	Gun.ReloadTime = Info.ReloadTime
	Gun._MaxAmmo = Info.MaxAmmo
	Gun._GunModel = Info.GunModel:Clone()
	Gun._GunAbilities = Info.GunAbilities or {}
	Gun._AbilitiesCooldown = Info.AbilitiesCooldown or {}

	Gun._FinalAbilities = {}
	Gun._AbilitiesNames = {}
	Gun._AbilitiesOnCooldown = {}
	Gun._PeopleUsing = {}
	Gun._PlayerInfo = {}
	Gun._PlayerTroves = {}

	-- Initialize object pools
	Gun._BulletPool = ObjectPool.new(CreateBulletPart, BULLET_POOL_SIZE, function(Bullet: Part)
		Bullet.Parent = workspace
	end, function(Bullet: Part)
		Bullet.Parent = nil
		Bullet.CFrame = CFrame.new(0, 0, 0)
	end)

	Gun._BeamPool = ObjectPool.new(CreateBeam, BEAM_POOL_SIZE, function(beam: Beam)
		-- Beam is ready to use
	end, function(beam: Beam)
		beam.Parent = nil
		beam.Attachment0 = nil
		beam.Attachment1 = nil
	end)

	-- Setup abilities
	local Count = 1
	for AbilityName, Function in pairs(Gun._GunAbilities) do
		local HotkeyChosen = AbilitiesHotkey[Count]
		Gun._FinalAbilities[HotkeyChosen] = Function
		table.insert(Gun._AbilitiesNames, AbilityName)
		Gun._AbilitiesOnCooldown[AbilityName] = false
		Count += 1
	end

	Gun._CanShoot = true
	Gun._Reloading = false

	-- Setup raycast params
	Gun._Params = RaycastParams.new()
	Gun._Params.FilterType = Enum.RaycastFilterType.Exclude
	Gun._Params.FilterDescendantsInstances = {}

	return Gun
end

-- Extract tool creation to reduce duplication
local function CreateToolInstance(self, IsBackpack: boolean): Tool
	local NewTool = Instance.new("Tool")
	NewTool.Name = self._Name
	NewTool.CanBeDropped = false
	NewTool.RequiresHandle = true
	NewTool.Enabled = true

	-- Setting up for the script
	NewTool:SetAttribute("IsAuto", self._Auto)
	NewTool:SetAttribute("FireRate", GunRateToTime(self.FireRate))

	local NewHandle = self._GunModel:Clone()
	NewHandle.Parent = NewTool

	local NewSound = self._FireSound:Clone()
	NewSound.Parent = NewHandle

	-- Set ability attributes
	local Count = 1
	for _ in pairs(self._FinalAbilities) do
		NewTool:SetAttribute("AbilityCount", Count)
		Count += 1
	end

	Count = 1
	for _, AbilityName in pairs(self._AbilitiesNames) do
		NewTool:SetAttribute(tostring(AbilitiesHotkey[Count]), AbilityName)
		Count += 1
	end

	-- Add appropriate script
	if NewTool:FindFirstChildOfClass("LocalScript") then
		return NewTool
	end

	local ScriptPath = ReplicatedStorage.Shared.SharedScripts.GunMainScript

	local LocalScript = ScriptPath:Clone()
	LocalScript.Enabled = true
	LocalScript.Parent = NewTool

	return NewTool
end

function GunSystem:GiveWeapon(Player: Player): ()
	if not Player or not Player:IsA("Player") then
		warn("Invalid player passed to GiveWeapon")
		return
	end

	local Backpack = Player:FindFirstChild("Backpack")
	local StarterGear = Player:FindFirstChild("StarterGear")

	if not Backpack or not StarterGear then
		warn("Player missing Backpack or StarterGear")
		return
	end

	-- Create tools
	local BackpackTool = CreateToolInstance(self, true)
	BackpackTool.Parent = Backpack

	local StarterGearTool = CreateToolInstance(self, false)
	StarterGearTool.Parent = StarterGear

	-- Initialize player-specific data
	self._PeopleUsing[Player] = true
	self._PlayerTroves[Player] = TroveModule.new()

	self._PlayerInfo[Player] = self:_CreatePlayerInfo(Player)

	-- Cleanup on player leaving
	self._PlayerTroves[Player]:Add(Players.PlayerRemoving:Connect(function(LeavingPlayer)
		if LeavingPlayer == Player then
			self:_CleanupPlayer(Player)
		end
	end))
end

function GunSystem:_CreatePlayerInfo(Player: Player)
	local PlayerData = {
		_Name = self._Name,
		FireRate = self.FireRate,
		FirePower = self.FirePower,
		_Ammo = self._Ammo,
		_Auto = self._Auto,
		ReloadTime = self.ReloadTime,
		_MaxAmmo = self._MaxAmmo,
		_GunAbilities = self._GunAbilities,
		_FinalAbilities = self._FinalAbilities,
		_CanShoot = true,
		_Reloading = false,
		_GunModel = nil,
		_AbilitiesCooldown = table.clone(self._AbilitiesCooldown),
		_AbilitiesOnCooldown = table.clone(self._AbilitiesOnCooldown),
		_AbilitiesNames = table.clone(self._AbilitiesNames),
	}

	-- Reload function
	PlayerData._Reload = function()
		local Data = self._PlayerInfo[Player]
		if not Data or Data._Reloading then
			return
		end

		Data._CanShoot = false
		Data._Reloading = true

		ReplicatedStorage.Shared.Remotes.GunShot:FireClient(Player, "Reloading...", Data._Name)

		task.delay(Data.ReloadTime, function()
			if not self._PlayerInfo[Player] then
				return
			end

			Data._Ammo = Data._MaxAmmo
			Data._Reloading = false
			Data._CanShoot = true
			ReplicatedStorage.Shared.Remotes.GunShot:FireClient(Player, Data._Ammo, Data._Name)
		end)
	end

	-- Ability function
	PlayerData._Ability = function(HotkeyChosen: Enum.KeyCode, AbilityName: string)
		local Data = self._PlayerInfo[Player]
		if not Data then
			return
		end

		local AbilityChosen = Data._FinalAbilities[HotkeyChosen]
		if not AbilityChosen then
			return
		end

		if Data._AbilitiesOnCooldown[AbilityName] then
			warn("Ability on cooldown:", AbilityName)
			return
		end

		warn(`Ability: {AbilityName} has been used.`)
		AbilityChosen(Data)

		Data._AbilitiesOnCooldown[AbilityName] = true
		task.delay(Data._AbilitiesCooldown[AbilityName], function()
			if self._PlayerInfo[Player] then
				Data._AbilitiesOnCooldown[AbilityName] = false
			end
		end)
	end

	-- Setup raycast params
	self._Params = RaycastParams.new()
	self._Params.FilterType = Enum.RaycastFilterType.Exclude
	self._Params.FilterDescendantsInstances = {}

	-- Initialize object pools
	self._BulletPool = ObjectPool.new(CreateBulletPart, BULLET_POOL_SIZE, function(bullet: Part)
		bullet.Parent = workspace
		table.insert(self._Params.FilterDescendantsInstances, bullet)
	end, function(bullet: Part)
		bullet.Parent = nil
		bullet.CFrame = CFrame.new(0, -1000, 0)
		local index = table.find(self._Params.FilterDescendantsInstances, bullet)
		if index then
			table.remove(self._Params.FilterDescendantsInstances, index)
		end
	end)

	self._BeamPool = ObjectPool.new(CreateBeam, BEAM_POOL_SIZE, function(Beam: Beam)
		-- Beam is ready to use
	end, function(Beam: Beam)
		Beam.Parent = nil
		Beam.Attachment0 = nil
		Beam.Attachment1 = nil
	end)

	return PlayerData
end

function GunSystem:_CleanupPlayer(Player: Player)
	if self._PlayerTroves[Player] then
		self._PlayerTroves[Player]:Clean()
		self._PlayerTroves[Player] = nil
	end

	self._PeopleUsing[Player] = nil
	self._PlayerInfo[Player] = nil
end

function GunSystem:GetAmmo(Player: Player): number?
	local PlayerData = self._PlayerInfo[Player]
	return PlayerData and PlayerData._Ammo or nil
end

function GunSystem:Shoot(
	Player: Player,
	MousePosition: Vector3,
	Target: BasePart?,
	Camera: CFrame?,
	Ability: boolean?,
	HotkeyChosen: Enum.KeyCode?,
	AbilityName: string?
): ()
	local PlayerData = self._PlayerInfo[Player]
	if not PlayerData then
		return
	end

	local ShotSpeed = GunRateToTime(PlayerData.FireRate)

	-- Handle ability activation
	if Ability and HotkeyChosen and AbilityName then
		PlayerData._Ability(HotkeyChosen, AbilityName)
		return
	end

	-- Check if can shoot
	if not PlayerData._CanShoot or PlayerData._Ammo < 1 then
		if PlayerData._Ammo <= 0 and not PlayerData._Reloading then
			PlayerData._Reload()
		end
		return
	end

	-- Perform shoot
	PlayerData._CanShoot = false

	-- Get gun model safely
	local Character = Player.Character
	if not Character then
		return
	end

	local Tool = Character:FindFirstChildOfClass("Tool")
	if not Tool then
		return
	end

	PlayerData._GunModel = Tool:FindFirstChild("Handle")
	if not PlayerData._GunModel then
		return
	end

	-- Apply damage
	if Target and Target.Parent then
		local Humanoid = Target.Parent:FindFirstChildOfClass("Humanoid")
		local PlayerHumanoid = Character:FindFirstChildOfClass("Humanoid")

		if Humanoid and Humanoid ~= PlayerHumanoid then
			local Damage = Target.Name == "Head" and (PlayerData.FirePower * HEADSHOT_MULTIPLIER)
				or PlayerData.FirePower
			Humanoid:TakeDamage(Damage)
		end
	end

	-- Update ammo
	PlayerData._Ammo -= 1
	ReplicatedStorage.Shared.Remotes.GunShot:FireClient(Player, PlayerData._Ammo, PlayerData._Name)

	-- Play sound
	local Sound = PlayerData._GunModel:FindFirstChildOfClass("Sound")
	if Sound then
		Sound:Play()
	end

	-- Create bullet visual using object pool
	self:_CreateBulletVisual(PlayerData._GunModel, MousePosition)

	-- Reset shoot cooldown
	task.delay(ShotSpeed, function()
		if self._PlayerInfo[Player] then
			PlayerData._CanShoot = true
		end
	end)
end

function GunSystem:_CreateBulletVisual(GunModel: BasePart, Direction: Vector3)
	local Origin = GunModel.Position

	-- Get bullet from pool
	local Bullet = self._BulletPool:get()
	Bullet.CFrame = CFrame.lookAt(Origin, Direction)

	-- Get beam from pool
	local Beam = self._BeamPool:get()
	local BulletAttachment = Bullet:FindFirstChildOfClass("Attachment")

	-- Create temporary attachment for gun
	local GunAttachment = Instance.new("Attachment")
	GunAttachment.Parent = GunModel

	Beam.Attachment0 = BulletAttachment
	Beam.Attachment1 = GunAttachment
	Beam.Parent = GunModel

	-- Animate bullet
	local TweenInfo = TweenInfo.new(0.1, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
	local Tween = TweenService:Create(Bullet, TweenInfo, {
		CFrame = CFrame.lookAt(Direction, Direction + (Direction - Origin).Unit),
	})
	Tween:Play()

	-- Store references to prevent garbage collection issues
	local BeamRef = Beam
	local TweenRef = Tween
	local AttachmentRef = GunAttachment

	-- Return beam to pool after short duration
	task.delay(BEAM_LIFETIME, function()
		if BeamRef and BeamRef.Parent then
			BeamRef.Attachment0 = nil
			BeamRef.Attachment1 = nil
			self._BeamPool:free(BeamRef)
		end
		if AttachmentRef and AttachmentRef.Parent then
			AttachmentRef:Destroy()
		end
	end)

	-- Return bullet to pool after visual lifetime
	task.delay(BULLET_VISUAL_LIFETIME, function()
		if TweenRef then
			TweenRef:Cancel()
		end
		if Bullet and Bullet.Parent then
			-- Reset bullet properties before returning to pool
			Bullet.CFrame = CFrame.new(0, -1000, 0) -- Move far away
			Bullet.AssemblyLinearVelocity = Vector3.zero
			self._BulletPool:free(Bullet)
		end
	end)
end

function GunSystem:Destroy()
	-- Cleanup all players
	for Player, _ in pairs(self._PeopleUsing) do
		self:_CleanupPlayer(Player)
	end

	-- Clear object pools
	if self._BulletPool then
		self._BulletPool:clear()
	end
	if self._BeamPool then
		self._BeamPool:clear()
	end

	-- Clear references
	table.clear(self._PeopleUsing)
	table.clear(self._PlayerInfo)
	table.clear(self._PlayerTroves)
end

return GunSystem
