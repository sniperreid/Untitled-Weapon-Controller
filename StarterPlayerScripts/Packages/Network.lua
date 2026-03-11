--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Communications = ReplicatedStorage.Communications

local NetBank = require(Communications.NetBank)

export type Infastructure = {
	Jobs: {[NetBank.ClientJobs]: (...any) -> any},
	
	FireServer: (self: Infastructure, Job: NetBank.ServerJobs, ...any) -> (),
	InvokeServer: (self: Infastructure, Job: NetBank.ServerJobs, ...any) -> any,
	
	Call: (self: Infastructure, Job: NetBank.ClientJobs, ...any) -> (),
	Bind: (self: Infastructure, Job: NetBank.ClientJobs, Callback: (...any) -> any) -> ()
}

local Network = {} :: Infastructure

Network.Jobs = {}

local GotNetworkError = "Attempt to bind job %s failed, because it already exists." :: any
local FailedToRetrieveNetwork = "Attempt to call job %s failed, please Bind this network event." :: any

function Network:FireServer(Job, ...)
	local JobFolder = Communications:WaitForChild(Job) :: Instance | nil
	local RemoteEvent = JobFolder and JobFolder:FindFirstChild("RemoteEvent") :: RemoteEvent | nil
	
	if not RemoteEvent then return end
	
	RemoteEvent:FireServer(...)
end

function Network:InvokeServer(Job, ...)
	local JobFolder = Communications:WaitForChild(Job) :: Instance | nil
	
	if not JobFolder then return end
	
	local RemoteFunction = JobFolder and JobFolder:FindFirstChild("RemoteFunction") :: RemoteFunction | nil

	if not RemoteFunction then return end

	return RemoteFunction:InvokeServer(...)
end

function Network:Call(Job: NetBank.ClientJobs, ...)
	if not self.Jobs[Job] then return end
	--assert(self.Jobs[Job], FailedToRetrieveNetwork:format(Job))
	
	return self.Jobs[Job](...)
end

function Network:Bind(Job: NetBank.ClientJobs, Callback)
	assert(not self.Jobs[Job], GotNetworkError:format(Job))
	
	self.Jobs[Job] = Callback
end

Communications.FireToClient.OnClientEvent:Connect(function(...)
	Network:Call(...)
end)

Communications.InvokeToClient.OnClientInvoke = function(...)
	return Network:Call(...)
end

return Network
