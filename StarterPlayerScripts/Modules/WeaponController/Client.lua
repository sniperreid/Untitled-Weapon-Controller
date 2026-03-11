local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Viewmodels = ReplicatedStorage.Viewmodels

local WeaponController = script.Parent

local CrosshairController = require(WeaponController.CrosshairController)
local FastCast = require(WeaponController.FastCastRedux)
local BulletHoleReplicator = require(WeaponController.BulletHoleReplicator)

local WeaponsFolder = Instance.new("Folder")
WeaponsFolder.Name = "[Client] - Weapons"
WeaponsFolder.Parent = workspace.Terrain

local BulletsFolder = Instance.new("Folder", workspace.Terrain)
BulletsFolder.Name = "[CLIENT] - BulletsFolder"

local BulletTemplate = Instance.new("Part")
BulletTemplate.Anchored = true
BulletTemplate.CanCollide = false
BulletTemplate.Transparency = 1
BulletTemplate.Shape = Enum.PartType.Ball
BulletTemplate.Color = Color3.fromRGB(0, 255, 0)
BulletTemplate.Size = Vector3.new(.05,.05,.05)
BulletTemplate.Material = Enum.Material.Neon

for i, v in script.BulletTrail:GetChildren() do
	v:Clone().Parent = BulletTemplate
end

BulletTemplate.Trail.Attachment0 = BulletTemplate.Attachment0
BulletTemplate.Trail.Attachment1 = BulletTemplate.Attachment1

local MouseRaycastParameters = RaycastParams.new()
MouseRaycastParameters.FilterType = Enum.RaycastFilterType.Include
MouseRaycastParameters.FilterDescendantsInstances = {}

local Modules = WeaponController.Parent
local InputController = require(Modules.InputController)

local Packages = Modules.Parent.Packages
local Network = require(Packages.Network)

local RBXCleanUp = require(ReplicatedStorage.Modules.Util.RBXCleanUp)

local ActiveWeapons = {}

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local ClientAnimations = {}

for i, Viewmodel in Viewmodels:GetChildren() do
	local GunModel = Viewmodel.GunModel
	local Configurations = require(GunModel.Configurations)
	local Animations = Configurations.Animations
	
	task.spawn(function()
		for AnimationTrack, AnimationId in Animations do
			if ClientAnimations[AnimationId] then continue end
			
			local AnimationInstance = Instance.new("Animation")
			AnimationInstance.AnimationId = AnimationId
			
			ContentProvider:PreloadAsync({AnimationInstance})
			
			ClientAnimations[AnimationId] = AnimationInstance
		end
	end)
end

local ClientWeapon = {}
ClientWeapon.__index = ClientWeapon

function ClientWeapon:Destroy()
	local Player = self.Player
	local UserId = Player.UserId
	
	if self.Maid then
		self.Maid:Clean()
	end
	
	if Player == Players.LocalPlayer then
		CrosshairController:Enable(false)
		
		UserInputService.MouseIconEnabled = true
	end
	
	ActiveWeapons[UserId] = nil
	
	table.clear(self)
	setmetatable(self, nil)
end

function ClientWeapon:IsFirstPerson()
	local Player = self.Player
	local Character = Player.Character
	
	if not Character then return end
	if not Character:FindFirstChild("Humanoid") then return end
	
	local CameraCFrame = Camera.CFrame
	local CameraSubject = Camera.CameraSubject
	
	if CameraSubject ~= Character.Humanoid then return false end
	
	local HeadNormal = CameraCFrame.Position - Character.Head.Position
	local DistanceFromHead = HeadNormal.Magnitude
	
	return DistanceFromHead <= 1
end

function ClientWeapon:GetModelConfiguration()
	local isFirstPerson = self:IsFirstPerson()
	local ConfigurationId = isFirstPerson and "First_Person" or "Third_Person"
	local Configuration = self.Configurations[ConfigurationId]
	
	return Configuration
end

function ClientWeapon:GetCameraOffset()
	local Player = self.Player
	local Character = Player.Character
	
	local Torso = Character and Character:FindFirstChild("Torso")
	local Head = Character and Character:FindFirstChild("Head")
	
	local isFirstPerson = self:IsFirstPerson()
	
	if isFirstPerson then
		return Camera.CFrame
	end
	
	return Torso and Torso.CFrame or CFrame.new()
end

function ClientWeapon:GetSwayOffset()
	local isFirstPerson = self:IsFirstPerson()
	local NewPivot = self:GetCameraOffset()
	
	local BaseConfiguration = self.Configurations.Modifiers

	local LastCFrame = self.LastCFrame or NewPivot

	local RotOffset = NewPivot:ToObjectSpace(LastCFrame)
	local x, y = RotOffset:ToOrientation()

	x = math.clamp(x, -1, 1)
	y = math.clamp(y, -1, 1)

	local SwayIntensity = BaseConfiguration.SwayIntensity or 0.2
	local SwayAlpha = BaseConfiguration.SwayAlpha or .05

	if self.Aiming then
		SwayIntensity /= 2
		SwayAlpha *= 2
	end

	self.SwayOffset = (self.SwayOffset or CFrame.new()):Lerp(
		CFrame.Angles(math.sin(x) * SwayIntensity, math.sin(y) * SwayIntensity, 0),
		SwayAlpha
	)

	self.LastCFrame = NewPivot

	return self.SwayOffset
end

function ClientWeapon:GetAimOffset()
	local D = CFrame.new()
	
	if not self.Aiming then return D end
	
	local Viewmodel = self.Viewmodel
	local GunModel = Viewmodel:FindFirstChild("GunModel")
	
	if not GunModel then return D end
	
	local Sight = GunModel:FindFirstChild("Sight")
	
	if not Sight then return D end
	
	local WorldOffset = Sight:FindFirstChild("WorldOffset")
	
	if not WorldOffset then return D end
	
	local isFirstPerson = self:IsFirstPerson()
	local Configuration = self:GetModelConfiguration()
	
	local BaseOffset = Configuration.Offset
	local NewOffset = Configuration.AimWorldOffset
	
	local AimOffset = WorldOffset.WorldCFrame * NewOffset
	
	return AimOffset:ToObjectSpace(Viewmodel:GetPivot())
end

function ClientWeapon:GetPivot()
	local Configuration = self:GetModelConfiguration()
	local BaseConfiguration = self.Configurations.Modifiers

	if not Configuration then return end

	local CameraOffset = self:GetCameraOffset()
	local BaseOffset = Configuration.Offset
	
	local AimOffset = self:GetAimOffset()
	
	self.AimOffset = (self.AimOffset or AimOffset):Lerp(AimOffset, BaseConfiguration.AimSpeed)
	
	return CameraOffset * BaseOffset * self.AimOffset * self:GetSwayOffset()
end

function ClientWeapon:GetMouseRay()
	local MouseLocation = UserInputService:GetMouseLocation()
	local X, Y = MouseLocation.X, MouseLocation.Y
	
	return Camera:ViewportPointToRay(X, Y)
end

function ClientWeapon:GetMouseWorldspace()
	local MouseRay = self:GetMouseRay()
	local Origin = MouseRay.Origin
	local Direction = MouseRay.Direction * 9999
	
	local Cast = workspace:Raycast(Origin, Direction, MouseRaycastParameters)
	
	return Cast and Cast.Position or MouseRay.Origin + Direction
end

function ClientWeapon:GetCrosshairSize()
	local BaseConfiguration = self.Configurations.Modifiers
	local BulletSpread = self.Aiming and BaseConfiguration.AimSpread or BaseConfiguration.BulletSpread
	
	local SpreadSize = (BulletSpread.X + BulletSpread.Y) / 2
	
	local Player = self.Player
	local Character = Player.Character
	local HumanoidRootPart = Character.HumanoidRootPart
	local Humanoid = Character.Humanoid
	
	local MovementSpeed = math.clamp(((Vector3.one - Vector3.yAxis) * HumanoidRootPart.Velocity).Magnitude, 0, Humanoid.WalkSpeed)
	
	local scalar = MovementSpeed / 8
	local movementMultiplier = math.lerp(1, 1.5, scalar)
	
	return SpreadSize * 5 * movementMultiplier
end

function ClientWeapon:GetBobOffset()
	local BaseCameraOffset = Vector3.zero
	local BaseConfiguration = self.Configurations.Modifiers
	
	local AimBobOffset = Vector3.zero
	
	local Player = self.Player
	local Character = Player.Character
	local HumanoidRootPart = Character.HumanoidRootPart
	local Humanoid = Character.Humanoid
	
	local MovementSpeed = math.clamp(((Vector3.one - Vector3.yAxis) * HumanoidRootPart.Velocity).Magnitude, 0, Humanoid.WalkSpeed)
	local Walking = MovementSpeed > .01
	
	if not self:IsFirstPerson() then
		
		AimBobOffset = (self.AimBobOffset or AimBobOffset):Lerp(
			self.Aiming and Vector3.new(2.5, 1.25, -2) or Vector3.zero,
			BaseConfiguration.AimSpeed
		)
		
	end
	
	local bobble = Vector3.zero
	
	if Walking then
		local c = 6

		local bobbleX = (math.cos(tick() * c) / 2) * (self.Aiming and .5 or 1)
		local bobbleY = (math.abs(math.sin(tick() * c)) / 2) * (self.Aiming and .5 or 1)

		bobble = Vector3.new(bobbleX, bobbleY)
	end
	
	BaseCameraOffset = (self.BaseBobOffset or BaseCameraOffset):Lerp(
		bobble,
		BaseConfiguration.WeightAlpha
	)
	
	self.AimBobOffset = AimBobOffset
	self.BaseBobOffset = BaseCameraOffset
	
	return BaseCameraOffset + AimBobOffset
end

function ClientWeapon:PlaySound(SoundCategory, SoundName, SoundVolume)
	local Viewmodel = self.Viewmodel
	local GunModel = Viewmodel.GunModel
	
	local Sounds = GunModel.Sounds
	
	local SoundFolder = Sounds:FindFirstChild(SoundCategory)
	local SoundInstance = SoundFolder and SoundFolder:FindFirstChild(SoundName)
	
	if not SoundInstance then return end
	
	SoundInstance = SoundInstance:Clone()
	SoundInstance.Parent = GunModel.Barrel
	
	SoundInstance.Volume = SoundVolume or SoundInstance.Volume
	SoundInstance:Play()
	
	SoundInstance.Ended:Once(function()
		SoundInstance:Destroy()
	end)
end

function ClientWeapon:SharedFire(BulletSpread, EmptyMag)
	if not EmptyMag then
		self:PlayAnimation("Fire", 0)
	end
	
	self:PlaySound("Physics", EmptyMag and "Click" or "Fire")
	
	local Viewmodel = self.Viewmodel
	local GunModel = Viewmodel.GunModel
	local Barrel = GunModel.Barrel
	
	local BarrelAttachment = Barrel.WorldOffset
	
	if EmptyMag then return end
	
	local Configurations = self.Configurations
	local Modifiers = Configurations.Modifiers
	
	self.Recoil += (Modifiers.RecoilKnockback * (self.Aiming and 1 or 2)) / (Modifiers.ShotgunSpread or 1)
	self.Ammo -= 1 / (Modifiers.ShotgunSpread or 1)
	
	self.RayParams.FilterDescendantsInstances = {self.Player.Character, workspace.Terrain}
	self.CastBehavior.RaycastParams = self.RayParams

	local MouseRay = self:GetMouseRay()
	local Origin = CFrame.new(BarrelAttachment.WorldCFrame.Position, MouseRay.Origin + (MouseRay.Direction * 9999)) * CFrame.new(0, 0, 5)
	
	local CrosshairSize = Random.new():NextNumber(-self.CrosshairSize/5, self.CrosshairSize/5)
	
	local theta = math.rad(math.random() * 360)
	local radius = math.tan(math.rad(CrosshairSize))
	
	local x = math.cos(theta) * radius
	local y = math.sin(theta) * radius

	local spreadDir = (Origin.LookVector + (Origin.RightVector * x) + (Origin.UpVector * y)).Unit
	local NextPoint = (MouseRay.Direction + spreadDir) * 9999

	local FinalPoint = Origin.Position + NextPoint

	local c = workspace:Raycast(MouseRay.Origin, NextPoint, self.RayParams)
	local fp = c and c.Position or FinalPoint

	local DirectionVector = (CFrame.new(Origin.Position, fp).LookVector) * 9999

	self.Caster:Fire(Origin.Position, DirectionVector, Modifiers.BulletSpeed, self.CastBehavior)
	
	for i, v in BarrelAttachment:GetChildren() do
		if v:IsA("ParticleEmitter") then
			v:Emit(v:GetAttribute("EmitCount") or v.Rate)
		elseif v.ClassName:match("Light") then
			v.Enabled = true
			v.Brightness = v:GetAttribute("Brightness") or 99
			
			task.delay(1/20, function()
				v.Brightness = 0
			end)
		end
	end
end

function ClientWeapon:Fire()
	if not self.Firing then return end
	
	local BaseConfiguration = self.Configurations.Modifiers
	
	if (tick() - (self.LastFire or 0)) < BaseConfiguration.Cooldown then return end
	
	if not BaseConfiguration.Automatic then
		self.Firing = false
	end
	
	if self.Ammo <= 0 then
		self.Firing = false
		
		self:SharedFire(Vector2.zero, true)
		
		Network:FireServer("FireServerWeapon", Vector2.zero)
		
		return self:PlaySound("Physics", "Click")
	end
	
	self.LastFire = tick()
	
	local BurstAmount = math.clamp(BaseConfiguration.BurstAmount or 1, 1, self.Ammo)
	local BurstDelay = BaseConfiguration.BurstDelay
	
	for i = 1, BurstAmount do
		for j = 1, BaseConfiguration.ShotgunSpread or 1 do
			local CrosshairSize = self.CrosshairSize
			local BulletSpread = Vector2.one * CrosshairSize

			local RNG = Random.new()

			BulletSpread = Vector2.new(
				RNG:NextNumber(-BulletSpread.X, BulletSpread.X),
				RNG:NextNumber(-BulletSpread.Y, BulletSpread.Y)
			)

			self:SharedFire(BulletSpread, false)

			Network:FireServer("FireServerWeapon", BulletSpread)
		end
		
		if BurstDelay then task.wait(BurstDelay) end
	end
end

function ClientWeapon:SharedReload()
	self:PlayAnimation("Reload", 0)
	
	local Character = self.Player.Character
	
	self.Aiming = false
	
	self.Firing = false
	self.LastFire = 0
end

function ClientWeapon:Reload()
	if self:AnimationPlaying("Fire") then return end
	if self:AnimationPlaying("Equip") then return end
	if self:AnimationPlaying("Reload") then return end
	
	if self.Ammo >= self.MagSize then return end
	
	local Reserve = self.MagazineExtents
	local Current = self.Ammo

	local ReloadOffset

	if Reserve >= math.huge then
		ReloadOffset = self.MagSize - self.Ammo
	end

	local ReloadOffset = math.min(self.MagSize - self.Ammo, Reserve)

	if ReloadOffset <= 0 then return end
	
	Network:FireServer("StartServerReload", self.Player.UserId)
	
	self:SharedReload()
end

function ClientWeapon:Update(dt)
	local isFirstPerson = self:IsFirstPerson()
	local Configuration = self:GetModelConfiguration()
	local BaseConfiguration = self.Configurations.Modifiers
	
	if not Configuration then return end
	
	local Player = self.Player
	local Character = Player.Character
	
	if not Character then return end
	
	local Humanoid = Character:FindFirstChild("Humanoid")
	
	if not Humanoid then return end
	
	local Larm = Character:FindFirstChild("Left Arm")
	local Rarm = Character:FindFirstChild("Right Arm")
	
	local Torso = Character:FindFirstChild("Torso")
	local Head = Character:FindFirstChild("Head")
	
	local HumanoidRootPart = Character:FindFirstChild("HumanoidRootPart")
	
	local Neck = Torso:WaitForChild("Neck")
	
	self.NeckOrigin = self.NeckOrigin or Neck.C0
	
	if Larm then
		Larm.Transparency = 1
	end
	
	if Rarm then
		Rarm.Transparency = 1
	end
	
	local WeaponPivot = self:GetPivot()
	local CrosshairSize = self:GetCrosshairSize()
	
	local WeaponAngular2D = CFrame.new()
	
	self.NeckRotation = (
		self.NeckRotation or CFrame.new()
	):Lerp(
		self.Aiming and CFrame.Angles(0, math.rad(-25), 0) or CFrame.new(),
		BaseConfiguration.AimSpeed
	)
	
	self.CrosshairSize = math.lerp(
		self.CrosshairSize or CrosshairSize,
		CrosshairSize,
		BaseConfiguration.AimSpeed
	)
	
	self.Recoil = math.lerp(
		self.Recoil or 0,
		0,
		BaseConfiguration.WeightAlpha
	)
	
	local Aimed_CameraCFrame
	local MouseWorldSpace = Player == LocalPlayer and self:GetMouseWorldspace()
	local MouseRay = Player == LocalPlayer and self:GetMouseRay()
	
	local isOneHanded = BaseConfiguration.isOneHanded or self.playerUsingLeftArm
	local isReloading = self:AnimationPlaying("Reload")
	
	if isOneHanded then
		local PlayerArmVisible = isReloading and 1 or 0
		local ViewportArmVisible = isReloading and 0 or 1

		Character["Left Arm"].Transparency = PlayerArmVisible
		self.Viewmodel["Left Arm"].Transparency = ViewportArmVisible
	end
	
	if Player == LocalPlayer then
		local state = not self.Aiming
		
		Humanoid.AutoRotate = state
		
		if not isFirstPerson then
			state = true
		end
		
		CrosshairController:Enable(state)
		
		if not Humanoid.AutoRotate then
			local Origin = Character:GetPivot()
			
			local MouseWs = Vector3.new(
				MouseWorldSpace.X,
				Origin.Y,
				MouseWorldSpace.Z
			)
			
			local LookCoordinate = CFrame.new(Origin.Position, MouseWs)
			
			Character:PivotTo(
				Origin:Lerp(LookCoordinate, BaseConfiguration.AimSpeed)
			)
		end
		
		if Camera.CameraSubject == Humanoid then
			Aimed_CameraCFrame = self.Aiming and CFrame.new(MouseRay.Origin, MouseRay.Origin + MouseRay.Direction * 99) or Camera.CFrame
		end
		
		local WalkSpeed = BaseConfiguration.WalkSpeed
		local SprintSpeed = BaseConfiguration.SprintSpeed
		
		local Speed = self.Sprinting and SprintSpeed or WalkSpeed
		local FOV = self.Aiming and BaseConfiguration.AimFOV or 70
		
		if self.Aiming then
			Speed /= 1.5
		end
		
		Humanoid.WalkSpeed = math.lerp(
			Humanoid.WalkSpeed,
			Speed,
			BaseConfiguration.WeightAlpha
		)
		
		Camera.FieldOfView = math.lerp(
			Camera.FieldOfView,
			FOV,
			BaseConfiguration.AimSpeed
		)
		
		Camera.CFrame *= CFrame.Angles(
			math.rad(self.Recoil * 3),
			0,
			0
		)
		
		Humanoid.CameraOffset = self:GetBobOffset()
		
		UserInputService.MouseBehavior = (self.Aiming or isFirstPerson) and Enum.MouseBehavior.LockCenter or Enum.MouseBehavior.Default
		
		local MovementSpeed = math.clamp(((Vector3.one - Vector3.yAxis) * HumanoidRootPart.Velocity).Magnitude, 0, Humanoid.WalkSpeed)
		local Walking = MovementSpeed > .01
		
		CrosshairController:SetSize(self.CrosshairSize)
		
		Network:FireServer("SetServerCameraCFrame", Camera.CFrame)
		
		self:Fire()
	end
	
	if not isFirstPerson and Torso then
		local camCF = Aimed_CameraCFrame or self.PsuedoCameraCFrame or CFrame.new()
		local x, y, z = camCF:ToOrientation()

		-- Credit to @SICKO_POOFY for math tyty
		local headCF = Head.CFrame
		local TorsoLV = Torso.CFrame.LookVector

		local dist = (headCF.p - camCF.p).magnitude
		local diff = headCF.Y - camCF.Y

		local asinDiffDist = math.asin(diff / dist)
		local whateverThisDoes = ((headCF.p - camCF.p).Unit:Cross(TorsoLV)).Y

		WeaponAngular2D = CFrame.Angles(x / 1.25, 0, 0)

		Neck.C0 = Neck.C0:lerp(self.NeckOrigin * CFrame.Angles(-1 * asinDiffDist * .6, 0, -1 * whateverThisDoes * 1) * self.NeckRotation, .15)
	end
	
	self.Viewmodel:PivotTo(WeaponPivot * WeaponAngular2D)
end

function ClientWeapon:LoadAnimation(AnimationTrack)
	local Viewmodel = self.Viewmodel
	local Humanoid = Viewmodel:FindFirstChild("Humanoid")
	
	local Configurations = self.Configurations
	local Animations = Configurations.Animations
	
	local AnimationId = Animations[AnimationTrack]
	
	if not AnimationId then return end
	
	local AnimationInstance = ClientAnimations[AnimationId]
	
	if not AnimationInstance then
		AnimationInstance = Instance.new("Animation")
		AnimationInstance.AnimationId = AnimationId
		
		ClientAnimations[AnimationId] = AnimationInstance
	end
	
	local Track = Humanoid:LoadAnimation(AnimationInstance) :: AnimationTrack
	
	if AnimationTrack:match("Equip") then
		Track.Priority = Enum.AnimationPriority.Action4
		Track.Looped = false
	elseif AnimationTrack:match("Idle") then
		Track.Priority = Enum.AnimationPriority.Idle
		Track.Looped = true
	elseif AnimationTrack:match("Fire") or AnimationTrack:match("Reload") then
		Track.Priority = Enum.AnimationPriority.Action
		Track.Looped = false
	end
	
	self.AnimationTracks[AnimationTrack] = Track
	
	return self.AnimationTracks[AnimationTrack]
end

function ClientWeapon:PlayAnimation(AnimationTrack, ...)
	local AnimationTracks = self.AnimationTracks
	
	if not AnimationTracks then return end
	
	local Track = AnimationTracks[AnimationTrack] or self:LoadAnimation(AnimationTrack)
	
	if not Track then return end
	
	if Track.isPlaying then 
		if not AnimationTrack:match("Fire") then return end

		Track:Stop()
	end
	
	Track:Play(...)
	
	return Track
end

function ClientWeapon:StopAnimation(AnimationTrack, ...)
	local AnimationTracks = self.AnimationTracks

	if not AnimationTracks then return end

	local Track = AnimationTracks[AnimationTrack] or self:LoadAnimation(AnimationTrack)

	if not Track then return end
	if not Track.isPlaying then return end
	
	Track:Stop(...)
	
	return Track
end

function ClientWeapon:AnimationPlaying(AnimationTrack)
	local AnimationTracks = self.AnimationTracks

	if not AnimationTracks then return end
	
	local Track = AnimationTracks[AnimationTrack]
	
	if not Track then return end
	
	return Track.isPlaying
end

function ClientWeapon:initClient()
	self.Maid:add(InputController:RegisterKeyPressed(Enum.UserInputType.MouseButton2):Connect(function()
		if self:AnimationPlaying("Equip") then return end
		if self:AnimationPlaying("Reload") then return end
		
		self.Aiming = true
		
		Network:FireServer("SetAimStatus", self.Aiming)
	end))
	
	self.Maid:add(InputController:RegisterKeyUnpressed(Enum.UserInputType.MouseButton2):Connect(function()
		if self:AnimationPlaying("Equip") then return end
		if self:AnimationPlaying("Reload") then return end

		self.Aiming = false
		
		Network:FireServer("SetAimStatus", self.Aiming)
	end))
	
	self.Maid:add(InputController:RegisterKeyPressed(Enum.UserInputType.MouseButton1):Connect(function()
		if self:AnimationPlaying("Equip") then return end
		if self:AnimationPlaying("Reload") then return end

		self.Firing = true
		self:Fire()
	end))

	self.Maid:add(InputController:RegisterKeyUnpressed(Enum.UserInputType.MouseButton1):Connect(function()
		if self:AnimationPlaying("Equip") then return end
		if self:AnimationPlaying("Reload") then return end

		self.Firing = false
	end))

	self.Maid:add(InputController:RegisterKeyPressed(Enum.KeyCode.LeftShift):Connect(function()
		self.Sprinting = true
	end))

	self.Maid:add(InputController:RegisterKeyUnpressed(Enum.KeyCode.LeftShift):Connect(function()
		self.Sprinting = false
	end))
	
	self.Maid:add(InputController:RegisterKeyPressed(Enum.KeyCode.R):Connect(function()
		self:Reload()
	end))
	
	CrosshairController:Enable(true)
	UserInputService.MouseIconEnabled = false
end

function ClientWeapon:init()
	local WeaponName = self.WeaponName
	local WeaponModel = Viewmodels:FindFirstChild(WeaponName)
	
	if not WeaponModel then
		return self:Destroy()
	end
	
	self.Viewmodel = self.Maid:add(WeaponModel:Clone())
	self.Viewmodel.Parent = WeaponsFolder
	
	local Viewmodel = self.Viewmodel
	local GunModel = Viewmodel.GunModel
	
	Viewmodel.Torso.Transparency = 1
	
	for i, v in self.Viewmodel:GetDescendants() do
		if v:IsA("BasePart") then
			v.CollisionGroup = "Weapon"
		end
	end
	
	self.Configurations = require(GunModel.Configurations)
	
	local Modifiers = self.Configurations.Modifiers
	
	self.MagSize = Modifiers.MagSize
	self.Ammo = self.WeaponData.Ammo or self.MagSize
	self.MagazineExtents = self.WeaponData.MagazineExtents or self.Ammo
	
	-- self.CastBehavior.Acceleration = Vector3.zero
	
	local Character = self.Player.Character
	
	local Shirt = Character:FindFirstChild("Shirt")
	local BodyColors = Character:FindFirstChild("Body Colors")
	
	if Shirt then
		Shirt:Clone().Parent = Viewmodel
	end
	
	if BodyColors then
		BodyColors:Clone().Parent = Viewmodel
	end
	
	for AnimationTrack in self.Configurations.Animations do
		self:LoadAnimation(AnimationTrack)
	end
	
	if self.Player == Players.LocalPlayer then
		self:initClient()
	end
	
	self.Caster.LengthChanged:Connect(function(cast, lastPoint, direction, length, velocity, bullet)
		if not bullet then return end
		if not self.Configurations then return bullet:Destroy() end

		local BulletLength = bullet.Size.Z/2
		local offset = CFrame.new(0, 0, -(length - BulletLength))

		bullet.CFrame = CFrame.lookAt(lastPoint, lastPoint + direction):ToWorldSpace(offset)
	end)

	self.Caster.RayHit:Connect(function(Cast, Results, Velocity, Bullet, origin)
		if not self.Configurations then return Bullet:Destroy() end
		
		local InstanceHit = Results.Instance

		if not InstanceHit then return Bullet:Destroy() end

		local OriginHit = InstanceHit

		repeat
			InstanceHit = InstanceHit.Parent
		until InstanceHit:IsA("Model") and InstanceHit:FindFirstChild("Humanoid") or InstanceHit == workspace

		local isModel = InstanceHit:IsA("Model") and InstanceHit:FindFirstChild("Humanoid")
		local isPlayer = isModel and self.Player.Parent and Players:GetPlayerFromCharacter(InstanceHit)

		-- Very smart, differs between NPC's and players
		local isNotOnTeam = (isPlayer and isPlayer.Team and self.Player.Team and isPlayer.Team ~= self.Player.Team) or (not isPlayer and true or false)

		if not isNotOnTeam then return Bullet:Destroy() end
		
		local Damage = (self.Configurations.Modifiers.Damage or 10) / (self.Configurations.Modifiers.ShotgunSpread or 1)

		if not isModel and Results.Position then
			BulletHoleReplicator:CreateBulletHole(Results.Instance, Results.Position, self.Configurations.Modifiers.Damage or 10)
		end

		if self.Player == Players.LocalPlayer and isModel then
			local Head = InstanceHit:FindFirstChild("Head")
			local isHeadShot = Head and (Head.Position - OriginHit.Position).Magnitude <= 1

			local Damage = self.Configurations.Modifiers.Damage or 10
			local HeadDamage = self.Configurations.Modifiers.HeadshotDamage or (Damage * 2.5)

			local nDamage = isHeadShot and HeadDamage or Damage

			--WeaponEffects:PlayHitmarkerEffect(isHeadShot)
			--WeaponEffects:MakeBloodSplatter(origin, nDamage, Results)
		end

		if self.Player == Players.LocalPlayer or self.Target then
			Network:FireServer("ReadFastCast", {
				Instance = Results.Instance,
				Position = Results.Position,
			})
		end

		Bullet:Destroy()
	end)
	
	self.Maid:add(
		self.AnimationTracks.Reload.Stopped:Connect(function()
			local Character = self.Player.Character
		end)
	)
	
	self.Maid:add(
		self.AnimationTracks.Reload.KeyframeReached:Connect(function(keyframeName)
			self:PlaySound("Mag", keyframeName)
			
			if keyframeName == "MagIn" then
				local Reserve = self.MagazineExtents
				local Current = self.Ammo

				local ReloadOffset

				if Reserve >= math.huge then
					ReloadOffset = self.MagSize - self.Ammo
				end

				local ReloadOffset = math.min(self.MagSize - self.Ammo, Reserve)
				
				Network:FireServer("FinishServerReload", self.Player.UserId)
				
				self.Ammo += ReloadOffset
				self.MagazineExtents -= ReloadOffset
			end
		end)
	)
	
	self.Maid:add(
		self.AnimationTracks.Equip.KeyframeReached:Connect(function(keyframeName)
			self:PlaySound("Physics", keyframeName)
		end)
	)
	
	self:PlayAnimation("Equip", 0)
	self:PlayAnimation("Idle", 0)
end

function ClientWeapon.new(Player: Player, WeaponData)
	local self = setmetatable({}, ClientWeapon)
	
	self.Player = Player
	
	self.WeaponData = WeaponData
	self.WeaponName = WeaponData.Name
	
	self.RayParams = RaycastParams.new()
	self.RayParams.FilterType = Enum.RaycastFilterType.Exclude
	self.RayParams.FilterDescendantsInstances = {self.Player.Character, workspace.Terrain}
	
	self.Caster = FastCast.new()
	
	local CastBehavior = FastCast.newBehavior()
	CastBehavior.RaycastParams = self.RayParams
	CastBehavior.Acceleration = Vector3.yAxis * -9.81
	CastBehavior.AutoIgnoreContainer = false
	CastBehavior.MaxDistance = 2_500
	CastBehavior.CosmeticBulletContainer = BulletsFolder
	CastBehavior.CosmeticBulletTemplate = BulletTemplate
	
	self.CastBehavior = CastBehavior
	
	self.Maid = RBXCleanUp.new()
	
	self.AnimationTracks = {}
	
	self.Aiming = false
	
	self:init()
	
	ActiveWeapons[Player.UserId] = self
	
	return self
end

function ClientWeapon.GetWeapon(Player)
	return ActiveWeapons[Player.UserId]
end

RunService:BindToRenderStep(
	"WeaponRender",
	Enum.RenderPriority.Camera.Value + 2,
	function(dt)
		for PlayerId, Weapon in ActiveWeapons do
			Weapon:Update(dt)
		end
	end
)

Network:Bind("UnequipWeapon", function(Player)	
	local ActiveWeapon = ClientWeapon.GetWeapon(Player)
	
	if not ActiveWeapon then return end
	
	return ActiveWeapon:Destroy()
end)

Network:Bind("EquipWeapon", function(Player, WeaponData)
	Network:Call("UnequipWeapon", Player)
	
	ClientWeapon.new(Player, WeaponData)
end)

Network:Bind("SetClientCameraCFrame", function(Player, CameraCFrame)
	local ActiveWeapon = ClientWeapon.GetWeapon(Player)

	if not ActiveWeapon then return end
	
	ActiveWeapon.PsuedoCameraCFrame = CameraCFrame
end)

Network:Bind("SetClientAim", function(Player, status)
	local ActiveWeapon = ClientWeapon.GetWeapon(Player)

	if not ActiveWeapon then return end
	
	ActiveWeapon.Aiming = status
end)

Network:Bind("FireClientWeapon", function(Player, ...)
	local ActiveWeapon = ClientWeapon.GetWeapon(Player)

	if not ActiveWeapon then return end
	
	return ActiveWeapon:SharedFire(...)
end)

Network:Bind("StartClientReload", function(Player)
	local ActiveWeapon = ClientWeapon.GetWeapon(Player)

	if not ActiveWeapon then return end
	
	return ActiveWeapon:SharedReload()
end)

Network:FireServer("LoadClientWeapons")

return ClientWeapon
