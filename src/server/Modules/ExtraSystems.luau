local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local ExtraSystems = {}

ExtraSystems._TeleportTool = Instance.new("Tool")
ExtraSystems._TeleportTool.Name = "TeleportTool"
ExtraSystems._TeleportTool.RequiresHandle = false
ExtraSystems._PlayersUsing = {}

Players.PlayerAdded:Connect(function(Player: Player)
	local NewTool: Tool = ExtraSystems._TeleportTool:Clone()
	NewTool.Parent = Player:WaitForChild("Backpack")

	local NewGear: Tool = ExtraSystems._TeleportTool:Clone()
	NewGear.Parent = Player:WaitForChild("StarterGear")
	ExtraSystems._PlayersUsing[Player] = true

	local ToolScript = Shared.SharedScripts.TeleportToolScript:Clone()
	ToolScript.Parent = NewTool
	ToolScript.Enabled = true

	local GearScript = Shared.SharedScripts.TeleportToolScript:Clone()
	GearScript.Parent = NewGear
	GearScript.Enabled = true
end)

Shared.Remotes
	:WaitForChild("AttemptTeleport").OnServerEvent
	:Connect(function(Player: Player, PlayerSent: Player, MousePosition: Vector3, Instance: Instance?, Distance: number)
		if not Instance and not Distance then
			if ExtraSystems._PlayersUsing[PlayerSent] then
				PlayerSent.Character:MoveTo(MousePosition)
			end
		else
			if ExtraSystems._PlayersUsing[PlayerSent] and Distance < 1000 then
				PlayerSent.Character:MoveTo(MousePosition)
			end
		end
	end)

return ExtraSystems
