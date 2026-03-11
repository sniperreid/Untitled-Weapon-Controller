local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Player = Players.LocalPlayer
local PlayerGui = Player.PlayerGui
local Interface = PlayerGui:WaitForChild("Interface")

local Ui = script.CrosshairUi:Clone()
Ui.Parent = Interface

local Crosshair = {}

Crosshair.Enabled = false
Crosshair.Ui = Ui

Crosshair.Size = 0
Crosshair.DesiredSize = 0

Crosshair.SavedMouseIcon = UserInputService.MouseIcon

Crosshair.CardinalOffsets = {
	Left = function(x)
		return UDim2.fromOffset(-x - 1, 0)
	end,
	
	Right = function(x)
		return UDim2.fromOffset(x, 0)
	end,
	
	Down = function(y)
		return UDim2.fromOffset(0, y)
	end,
	
	Up = function(y)
		return UDim2.fromOffset(0, -y - 1)
	end,
}

function Crosshair:SetSize(Size)
	self.Size = Size
end

function Crosshair:Enable(state)
	self.Enabled = state
end

RunService:BindToRenderStep(
	"CrosshairUpdater",
	Enum.RenderPriority.Camera.Value + 4,
	function(dt)
		local Ui = Crosshair.Ui
		
		if not Ui then return end
		
		--Crosshair.Size = math.lerp(Crosshair.Size, Crosshair.DesiredSize, .075)
		
		local v = UserInputService:GetMouseLocation()
		
		Ui.Visible = Crosshair.Enabled-- and Crosshair.Size >= 3
		Ui.Position = UDim2.fromOffset(v.X, v.Y)

		if not Ui.Visible then return end
		
		Ui.Left.Position = Crosshair.CardinalOffsets.Left(Crosshair.Size)
		Ui.Right.Position = Crosshair.CardinalOffsets.Right(Crosshair.Size)
		Ui.Down.Position = Crosshair.CardinalOffsets.Down(Crosshair.Size)
		Ui.Up.Position = Crosshair.CardinalOffsets.Up(Crosshair.Size)
	end
)

return Crosshair
