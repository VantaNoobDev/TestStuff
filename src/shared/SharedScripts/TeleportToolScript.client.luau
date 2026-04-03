local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Tool: Tool? = script.Parent
if not script.Parent:IsA("Tool") then
	script.Enabled = false
	return
end
local Player: Player = Players.LocalPlayer
local Mouse: Mouse = Player:GetMouse()
local Character: Model? = Player.Character
local RaycastParams = RaycastParams.new()
RaycastParams.FilterType = Enum.RaycastFilterType.Exclude
RaycastParams.CollisionGroup = "N/A"
RaycastParams.IgnoreWater = true
RaycastParams.RespectCanCollide = true

Tool.Activated:Connect(function(...)
	local Raycast =
		workspace:Raycast(Character:FindFirstChild("HumanoidRootPart").Position, Mouse.Hit.Position, RaycastParams)
	if Raycast then
		ReplicatedStorage.Shared.Remotes
			:WaitForChild("AttemptTeleport")
			:FireServer(Player, Mouse.Hit.Position, Raycast.Instance, Raycast.Distance)
	else
		ReplicatedStorage.Shared.Remotes:WaitForChild("AttemptTeleport"):FireServer(Player, Mouse.Hit.Position)
	end
end)
