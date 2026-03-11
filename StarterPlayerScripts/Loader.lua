local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerScripts = script.Parent
local Modules = PlayerScripts.Modules
local WeaponController = Modules.WeaponController

require(WeaponController.Client)
