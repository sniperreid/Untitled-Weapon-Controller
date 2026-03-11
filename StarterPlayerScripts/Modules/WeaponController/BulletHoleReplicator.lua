local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Modules = ReplicatedStorage.Modules
local Util = Modules.Util
local WorldToGui = require(Util.WorldToGui)

local LIFETIME = 25
local SIZE = .6

local BulletHoles = {}

function BulletHoles:GetNormal(part, pos)
	local shape
	if part:IsA("Part") then shape = part.Shape.Value
	elseif part:IsA("WedgePart") then shape = 3
	elseif part:IsA("CornerWedgePart") then shape = 4
	else shape = 5
	end
	if shape == 0 then
		return (pos-part.Position).unit, "curve", pos
	elseif shape == 1 or shape == 3 then
		local r = part.CFrame:pointToObjectSpace(pos)/part.Size
		local rot = part.CFrame-part.Position
		if r.x > 0.4999 then return rot*Vector3.new(1,0,0), "right", pos
		elseif r.x < -0.4999 then return rot*Vector3.new(-1,0,0), "left", pos
		elseif r.y > 0.4999 then return rot*Vector3.new(0,1,0), "top", pos
		elseif r.y < -0.4999 then return rot*Vector3.new(0,-1,0), "bottom", pos
		elseif r.z > 0.4999 then return rot*Vector3.new(0,0,1), "back", pos
		elseif r.z < -0.4999 then return rot*Vector3.new(0,0,-1), "front", pos
		end
		return rot*Vector3.new(0,part.Size.Z,-part.Size.Y).unit, "ramp", pos
	elseif shape == 2 then
		return (pos-part.Position).unit, "curve", pos
	elseif shape == 4 then
		local r = part.CFrame:pointToObjectSpace(pos)/part.Size
		local rot = part.CFrame-part.Position
		if r.x > 0.4999 then return rot*Vector3.new(1,0,0), "right", pos
		elseif r.y < -0.4999 then return rot*Vector3.new(0,-1,0), "bottom", pos
		elseif r.z < -0.4999 then return rot*Vector3.new(0,0,-1), "front", pos
		elseif r.unit:Dot(Vector3.new(1,0,1).unit) > 0 then return rot*Vector3.new(0,part.Size.Z,part.Size.Y).unit, "lslope", pos
		end
		return rot*Vector3.new(-part.Size.Y,part.Size.X,0).unit, "rslope", pos
	else
		return Vector3.new(0,1,0), "unknown", pos
	end
end

BulletHoles.InitialInfo = TweenInfo.new(.1, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
BulletHoles.DebrisInfo = TweenInfo.new(4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)

function BulletHoles:CreateBulletHole(part, pos, weight)
	WorldToGui.SetImageSurfaceGui(part, pos, "rbxassetid://2859765692", LIFETIME)
	
	if true then return end
	
	local hole = Instance.new("Part")
	hole.Parent = workspace.Terrain
	hole.Material = Enum.Material.SmoothPlastic
	hole.Transparency = 1
	hole.Anchored = true
	hole.CanCollide = false
	hole.Size = Vector3.new(SIZE,0,SIZE) * (weight / 20)
	hole.CFrame = CFrame.new(pos, pos + self:GetNormal(part, pos)) * CFrame.Angles(-math.pi/2, 0, 0)

	local holedecal = Instance.new("Decal")
	holedecal.Parent = hole
	holedecal.Texture = "rbxassetid://2859765692"
	holedecal.Face = "Top"
	holedecal.Color3 = Color3.fromRGB(150, 150, 150)
	holedecal.Transparency = .7
	
	Debris:AddItem(hole, LIFETIME + 1)
	
	TweenService:Create(
		holedecal,
		BulletHoles.InitialInfo,
		{
			Transparency = .1,
			Color3 = Color3.fromRGB(255, 255, 255)
		}
	):Play()
	
	task.delay(LIFETIME - 3, function()
		TweenService:Create(
			holedecal,
			BulletHoles.DebrisInfo,
			{
				Transparency = 1
			}
		):Play()
	end)
end

return BulletHoles
