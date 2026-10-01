-- Avatar preview spawner for your own Roblox experience.
-- Place this Script in ServerScriptService alongside main.lua in StarterPlayerScripts.
-- Spawned characters are NPC models, not real connected Player instances.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local REMOTE_NAME = "OwnGameAvatarSpawner"
local FOLDER_NAME = "OwnGamePreviewAvatars"
local MAX_PER_PLAYER = 6
local SPAWN_COOLDOWN = 1
local FIVE_INCHES_IN_STUDS = 5 / 11.02

-- Add developer UserIds here to permit use in a published test place.
-- Studio play tests are always permitted.
local ALLOWED_USER_IDS = {}

-- Optional UserIds for the random-player button to choose between.
-- Other players in the current server are added automatically. If this list is
-- empty and the server is solo, the button still builds a randomized R15 avatar.
local RANDOM_USER_IDS = {}

local rng = Random.new()
local states = {}

local remote = ReplicatedStorage:FindFirstChild(REMOTE_NAME)
if remote and not remote:IsA("RemoteFunction") then
	remote:Destroy()
	remote = nil
end
if not remote then
	remote = Instance.new("RemoteFunction")
	remote.Name = REMOTE_NAME
	remote.Parent = ReplicatedStorage
end

local npcFolder = workspace:FindFirstChild(FOLDER_NAME)
if npcFolder and not npcFolder:IsA("Folder") then
	error(("Workspace.%s must be a Folder"):format(FOLDER_NAME))
end
if not npcFolder then
	npcFolder = Instance.new("Folder")
	npcFolder.Name = FOLDER_NAME
	npcFolder.Parent = workspace
end

local function isAuthorized(player)
	if RunService:IsStudio() then
		return true
	end

	if game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then
		return true
	end

	return table.find(ALLOWED_USER_IDS, player.UserId) ~= nil
end

local function getState(player)
	local state = states[player.UserId]
	if not state then
		state = {
			models = {},
			pending = 0,
			lastSpawnAt = 0,
		}
		states[player.UserId] = state
	end
	return state
end

local function getActiveModels(state)
	local models = {}
	for id, model in pairs(state.models) do
		if model and model.Parent then
			table.insert(models, {id = id, model = model})
		else
			state.models[id] = nil
		end
	end
	return models
end

local function clearPlayerModels(player)
	local state = states[player.UserId]
	if not state then
		return 0
	end

	local models = getActiveModels(state)
	for _, entry in ipairs(models) do
		entry.model:Destroy()
	end
	table.clear(state.models)
	return #models
end

local function randomDescription()
	local skinTones = {
		Color3.fromRGB(255, 224, 189),
		Color3.fromRGB(241, 194, 125),
		Color3.fromRGB(198, 134, 66),
		Color3.fromRGB(141, 85, 36),
		Color3.fromRGB(255, 219, 172),
	}
	local tone = skinTones[rng:NextInteger(1, #skinTones)]
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = tone
	description.TorsoColor = tone
	description.LeftArmColor = tone
	description.RightArmColor = tone
	description.LeftLegColor = tone
	description.RightLegColor = tone
	description.HeightScale = rng:NextNumber(0.9, 1.08)
	description.WidthScale = rng:NextNumber(0.85, 1.08)
	description.DepthScale = rng:NextNumber(0.85, 1.08)
	description.HeadScale = rng:NextNumber(0.92, 1.12)
	description.BodyTypeScale = rng:NextNumber(0, 0.6)
	description.ProportionScale = rng:NextNumber(0, 0.6)
	return description
end

local function getRandomUserIds(requestingPlayer)
	local ids = {}
	local seen = {}

	local function addId(userId)
		if typeof(userId) == "number" and userId > 0 and not seen[userId] then
			seen[userId] = true
			table.insert(ids, userId)
		end
	end

	for _, userId in ipairs(RANDOM_USER_IDS) do
		addId(userId)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= requestingPlayer then
			addId(player.UserId)
		end
	end

	return ids
end

local function makePreview(player, description, displayName, sourceUserId)
	local createOk, modelOrError = pcall(function()
		return Players:CreateHumanoidModelFromDescriptionAsync(description, Enum.HumanoidRigType.R15)
	end)
	description:Destroy()
	if not createOk then
		error(tostring(modelOrError))
	end

	local model = modelOrError
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then
		model:Destroy()
		error("The avatar model is missing a Humanoid or HumanoidRootPart.")
	end

	local character = player.Character or player.CharacterAdded:Wait()
	local playerRoot = character:WaitForChild("HumanoidRootPart", 10)
	if not playerRoot then
		model:Destroy()
		error("Your character is still loading. Try again in a moment.")
	end
	if player.Parent ~= Players then
		model:Destroy()
		error("The player left before the avatar finished loading.")
	end

	local id = HttpService:GenerateGUID(false)
	model.Name = "PreviewAvatar_" .. id:sub(1, 8)
	model:SetAttribute("OwnGamePreviewAvatar", true)
	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("PreviewName", displayName)
	if sourceUserId then
		model:SetAttribute("SourceUserId", sourceUserId)
	end
	humanoid.DisplayName = displayName
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff

	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("BasePart") then
			item.CanCollide = false
			item.CanTouch = false
			item.CanQuery = false
		end
	end

	model.Parent = npcFolder
	model:PivotTo(playerRoot.CFrame)
	local _, playerBounds = character:GetBoundingBox()
	local _, modelBounds = model:GetBoundingBox()
	local rearOffset = (playerBounds.Z + modelBounds.Z) / 2 + FIVE_INCHES_IN_STUDS
	model:PivotTo(playerRoot.CFrame * CFrame.new(0, 0, rearOffset))
	root.Anchored = true

	local state = getState(player)
	state.models[id] = model
	model.Destroying:Connect(function()
		local currentState = states[player.UserId]
		if currentState then
			currentState.models[id] = nil
		end
	end)

	return {name = displayName}
end

local function spawnForPlayer(player, action, value)
	if not isAuthorized(player) then
		return false, "This test spawner is disabled in live servers for your account."
	end

	if action == "Clear" then
		return true, {removed = clearPlayerModels(player)}
	end

	local state = getState(player)
	local active = getActiveModels(state)
	if #active + state.pending >= MAX_PER_PLAYER then
		return false, ("You can have up to %d preview avatars at once."):format(MAX_PER_PLAYER)
	end
	if state.lastSpawnAt > 0 and os.clock() - state.lastSpawnAt < SPAWN_COOLDOWN then
		return false, "Wait a moment before spawning another avatar."
	end
	state.lastSpawnAt = os.clock()
	state.pending += 1

	local success, result = pcall(function()
		if action == "SpawnUser" then
			if typeof(value) ~= "string" then
				error("Enter a Roblox username.")
			end
			local username = string.match(value, "^%s*(.-)%s*$") or ""
			if #username < 3 or #username > 20 or not string.match(username, "^[%w_]+$") then
				error("Enter a valid Roblox username.")
			end

			local userId = Players:GetUserIdFromNameAsync(username)
			local description = Players:GetHumanoidDescriptionFromUserIdAsync(userId)
			return makePreview(player, description, username, userId)
		elseif action == "SpawnRandom" then
			local ids = getRandomUserIds(player)
			for attempt = 1, math.min(3, #ids) do
				-- Remove each attempted id so a failed profile lookup isn't retried.
				local userId = table.remove(ids, rng:NextInteger(1, #ids))
				local avatarOk, description = pcall(function()
					return Players:GetHumanoidDescriptionFromUserIdAsync(userId)
				end)
				if avatarOk and description then
					local nameOk, username = pcall(function()
						return Players:GetNameFromUserIdAsync(userId)
					end)
					return makePreview(player, description, nameOk and username or "Random Avatar", userId)
				end
			end

			return makePreview(player, randomDescription(), "Random Avatar")
		end

		error("Unknown spawner action.")
	end)

	state.pending -= 1
	if not success then
		warn("[OwnGameAvatarSpawner] " .. tostring(result))
		if action == "SpawnRandom" then
			return false, "Couldn't create a random avatar right now. Try again in a moment."
		end
		return false, "Couldn't load that user avatar. Check the username and try again."
	end
	return true, result
end

remote.OnServerInvoke = function(player, action, value)
	if typeof(action) ~= "string" then
		return false, "Unknown spawner action."
	end
	return spawnForPlayer(player, action, value)
end

Players.PlayerRemoving:Connect(function(player)
	clearPlayerModels(player)
	states[player.UserId] = nil
end)
