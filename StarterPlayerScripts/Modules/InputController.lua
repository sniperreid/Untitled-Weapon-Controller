local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type Devices = "PC" | "Console" | "Mobile"
export type KeyCode = Enum.KeyCode | Enum.UserInputType
export type Remapped = {[Devices]: KeyCode?}

local Modules = ReplicatedStorage.Modules
local Util = Modules.Util
local Signal = require(Util.Signal)

local InputController = {}

InputController.RegisteredInputs = Signal.new "RegisteredInputs"

InputController.Remap = {
	
	{
		PC = Enum.UserInputType.MouseButton1,
		Console = Enum.KeyCode.ButtonR2
	},
	
	{
		PC = Enum.UserInputType.MouseButton2,
		Console = Enum.KeyCode.ButtonL2
	},
	
	{
		PC = Enum.KeyCode.LeftShift,
		Console = Enum.KeyCode.ButtonL3
	}
	
} :: {Remapped}

function InputController.GetRemappedKey(KeyCode: Enum.KeyCode | Enum.UserInputType, Device: Devices): KeyCode?
	local Remap = InputController.Remap
	
	for i, devices in Remap do
		for _Device, Key in devices do
			if Key == KeyCode and _Device ~= Device then
				return devices[Device]
			end
		end
	end
end

function InputController.GetCurrentDevice(): Devices
	if UserInputService.GamepadEnabled then
		return "Console"
	end
	
	if UserInputService.KeyboardEnabled and UserInputService.MouseEnabled then
		return "PC"
	end
	
	return "Mobile"
end

InputController.KeyRegisters = {}

function InputController.NewInputs(KeyCode: KeyCode, pressedState: boolean)
	return {
		Connect = function(self, Callback)
			table.insert(InputController.KeyRegisters, {
				onPressed = pressedState,
				KeyCode = KeyCode,
				Callback = Callback,
				Destroy = function(self)
					for i, v in InputController.KeyRegisters do
						if v == self then
							table.remove(InputController.KeyRegisters, i)
						end
					end
				end,
			})

			return InputController.KeyRegisters[#InputController.KeyRegisters]
		end,
	}
end

function InputController:RegisterKeyPressed(KeyCode: KeyCode)
	return InputController.NewInputs(KeyCode, true)
end

function InputController:RegisterKeyUnpressed(KeyCode: KeyCode)
	return InputController.NewInputs(KeyCode, false)
end

function InputController.FireInputs(inputObject: InputObject, pressedState: boolean)
	local kc = inputObject.KeyCode
	local uit = inputObject.UserInputType
	
	for i, Register in InputController.KeyRegisters do
		if Register.onPressed ~= pressedState then continue end
		
		local RemappedKeyCode = InputController.GetRemappedKey(Register.KeyCode, "PC") or InputController.GetRemappedKey(Register.KeyCode, "Console")
		
		if (RemappedKeyCode == kc or RemappedKeyCode == uit) or (Register.KeyCode == kc or Register.KeyCode == uit) then
			Register.Callback()
		end
	end
end

UserInputService.InputBegan:Connect(function(input)
	return InputController.FireInputs(input, true)
end)

UserInputService.InputEnded:Connect(function(input)
	return InputController.FireInputs(input, false)
end)

return InputController
