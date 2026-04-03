--[[
	MovementClient.luau
	Client-side script for handling movement input
	
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

-- Get remote event
local remotesFolder = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes")
local performMovementRemote = remotesFolder:WaitForChild("PerformMovement")

-- Hotkey configuration (should match server)
local HOTKEYS = {
	Dash = Enum.KeyCode.Q,
	Slide = Enum.KeyCode.C,
}

-- Cooldown tracking (client-side prediction)
local cooldowns = {
	Dash = 0,
	Slide = 0,
}

local COOLDOWN_DURATIONS = {
	Dash = 1.5,
	Slide = 2.0,
}

-- Check if movement is on cooldown
local function isOnCooldown(movementType: string): boolean
	return os.clock() < cooldowns[movementType]
end

-- Start cooldown timer
local function startCooldown(movementType: string)
	cooldowns[movementType] = os.clock() + COOLDOWN_DURATIONS[movementType]
end

-- Handle input
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	-- Check for dash
	if input.KeyCode == HOTKEYS.Dash then
		if not isOnCooldown("Dash") then
			startCooldown("Dash")
			performMovementRemote:FireServer("Dash")
		else
			-- Optional: Show cooldown feedback to player
			print("Dash is on cooldown!")
		end
	end

	-- Check for slide
	if input.KeyCode == HOTKEYS.Slide then
		if not isOnCooldown("Slide") then
			startCooldown("Slide")
			performMovementRemote:FireServer("Slide")
		else
			-- Optional: Show cooldown feedback to player
			print("Slide is on cooldown!")
		end
	end
end)

print("[MovementClient] Movement controls loaded")
print("Press Q to Dash")
print("Press C to Slide")
