local Framework = {}
local Events = {}
local Configuration = {
	FirstEventTime = 10,
}

local CurrentNumber: number = 1

for _, Module in pairs(script.Parent.Events:GetChildren()) do
	if Module:IsA("ModuleScript") and Module.Name ~= script.Name then
		Module.Name = tostring(CurrentNumber)
		CurrentNumber += 1
		Events[tonumber(Module.Name)] = require(Module)
	end
end

local function Retry()
	local Random = math.random(1, CurrentNumber - 1)
	local ChosenModule = Events[Random]
	return ChosenModule
end

function Framework:Start(): ()
	local IsFirstEvent: boolean = true
	while true do
		if IsFirstEvent then
			task.wait(Configuration.FirstEventTime)
			local ChosenModule = Retry()
			local EventConfiguration = ChosenModule.Configuration
			if EventConfiguration.PassiveEvent then
				EventConfiguration.Event()
			else
				EventConfiguration.Event()
				task.wait(EventConfiguration.Duration)
				EventConfiguration.EventEnded()
			end
			IsFirstEvent = false
		else
			local ChosenModule = Retry()
			local EventConfiguration = ChosenModule.Configuration
			if EventConfiguration.PassiveEvent then
				EventConfiguration.Event()
			else
				EventConfiguration.Event()
				task.wait(EventConfiguration.Duration)
				EventConfiguration.EventEnded()
			end
		end
	end
end

return Framework
