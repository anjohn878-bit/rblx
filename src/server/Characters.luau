-- Character dressing: collision group (so vehicles pass through people), a rank nametag, and a
-- parcel in the player's hands while they are carrying deliveries on foot.

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PlayerData = require(script.Parent.PlayerData)

local Characters = {}

local GROUPS = Config.CollisionGroups

local function registerGroups()
	for _, name in { GROUPS.Vehicles, GROUPS.Characters } do
		if not PhysicsService:IsCollisionGroupRegistered(name) then
			PhysicsService:RegisterCollisionGroup(name)
		end
	end
	PhysicsService:CollisionGroupSetCollidable(GROUPS.Vehicles, GROUPS.Characters, false)
end

local function setGroup(instance: Instance)
	if instance:IsA("BasePart") then
		instance.CollisionGroup = GROUPS.Characters
	end
end

local function updateNametag(session: PlayerData.Session)
	local character = session.Player.Character
	local head = character and character:FindFirstChild("Head")
	if not head then
		return
	end
	local rank = Config.Ranks[PlayerData.rankIndex(session)]
	local tag = head:FindFirstChild("RankTag") :: BillboardGui?
	if not tag then
		local gui = Instance.new("BillboardGui")
		gui.Name = "RankTag"
		gui.Size = UDim2.fromOffset(200, 46)
		gui.StudsOffset = Vector3.new(0, 2.6, 0)
		gui.MaxDistance = 70
		gui.LightInfluence = 0

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "PlayerName"
		nameLabel.BackgroundTransparency = 1
		nameLabel.Size = UDim2.fromScale(1, 0.55)
		nameLabel.Font = Enum.Font.FredokaOne
		nameLabel.TextScaled = true
		nameLabel.TextColor3 = Color3.new(1, 1, 1)
		nameLabel.TextStrokeTransparency = 0.5
		nameLabel.Text = session.Player.DisplayName
		nameLabel.Parent = gui

		local rankLabel = Instance.new("TextLabel")
		rankLabel.Name = "Rank"
		rankLabel.BackgroundTransparency = 1
		rankLabel.Position = UDim2.fromScale(0, 0.55)
		rankLabel.Size = UDim2.fromScale(1, 0.45)
		rankLabel.Font = Enum.Font.GothamBold
		rankLabel.TextScaled = true
		rankLabel.TextStrokeTransparency = 0.5
		rankLabel.Parent = gui

		gui.Parent = head
		tag = gui
	end
	local rankLabel = (tag :: BillboardGui):FindFirstChild("Rank") :: TextLabel
	rankLabel.Text = rank.Name
	rankLabel.TextColor3 = rank.Color
end

local function updateCarry(session: PlayerData.Session)
	local character = session.Player.Character
	if not character then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local parcel = character:FindFirstChild("CarriedParcel")
	local shouldCarry = #session.Jobs > 0 and root ~= nil and humanoid ~= nil and humanoid.SeatPart == nil

	if shouldCarry and not parcel and root then
		local part = Instance.new("Part")
		part.Name = "CarriedParcel"
		part.Size = Vector3.new(1.8, 1.4, 1.4)
		part.Color = Config.PackageKinds[1].Color
		part.Material = Enum.Material.Cardboard
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.CFrame = root.CFrame * CFrame.new(0, 0.1, -1.2)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
		part.Parent = character
	elseif not shouldCarry and parcel then
		parcel:Destroy()
	end
end

local function onCharacter(player: Player, character: Model)
	for _, descendant in character:GetDescendants() do
		setGroup(descendant)
	end
	character.DescendantAdded:Connect(setGroup)

	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	character:WaitForChild("Head", 10)
	character:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or player.Character ~= character then
		return
	end
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

	local session = PlayerData.waitFor(player, 20)
	if not session or player.Character ~= character then
		return
	end
	updateNametag(session)
	updateCarry(session)
	humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
		local current = PlayerData.get(player)
		if current then
			updateCarry(current)
		end
	end)
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
end

function Characters.init()
	registerGroups()
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	PlayerData.onChanged(function(session)
		updateNametag(session)
		updateCarry(session)
	end)
end

return Characters
