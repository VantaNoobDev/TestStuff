local Event = {}

type Configuration = {
	Name: string,
	Duration: number,
	PassiveEvent: boolean,
	Event: () -> () | RBXScriptConnection | RBXScriptSignal,
	EventEnded: () -> () | RBXScriptConnection | RBXScriptSignal,
}

Event.Configuration = {
	Name = "Test",
	Duration = 20,
	PassiveEvent = false,
	Event = function()
		workspace.Baseplate.BrickColor = BrickColor.Random()
	end,
	EventEnded = function()
		workspace.Baseplate.BrickColor = BrickColor.Gray()
	end,
} :: Configuration

return Event
