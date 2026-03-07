--!strict
-- Безопасный шаблон серверной админ-панели для Roblox.
-- Используйте ТОЛЬКО в своей игре.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

-- Настройки
local ADMIN_USER_IDS: {[number]: boolean} = {
	[12345678] = true, -- замените на ваш UserId
}

local COMMAND_COOLDOWN_SECONDS = 0.2
local MAX_TRAP_TIME_SECONDS = 30

-- Папка и RemoteEvent создаются на сервере.
local adminFolder = ReplicatedStorage:FindFirstChild("AdminRemotes")
if not adminFolder then
	adminFolder = Instance.new("Folder")
	adminFolder.Name = "AdminRemotes"
	adminFolder.Parent = ReplicatedStorage
end

local commandEvent = adminFolder:FindFirstChild("AdminCommand") :: RemoteEvent?
if not commandEvent then
	commandEvent = Instance.new("RemoteEvent")
	commandEvent.Name = "AdminCommand"
	commandEvent.Parent = adminFolder
end

local lastCommandAt: {[number]: number} = {}
local flyConnections: {[number]: RBXScriptConnection} = {}

local function isAdmin(player: Player): boolean
	return ADMIN_USER_IDS[player.UserId] == true
end

local function getPlayerByNamePrefix(prefix: string): Player?
	local loweredPrefix = string.lower(prefix)
	for _, player in ipairs(Players:GetPlayers()) do
		if string.sub(string.lower(player.Name), 1, #loweredPrefix) == loweredPrefix then
			return player
		end
	end
	return nil
end

local function getHumanoidRootPart(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function setFly(target: Player, enabled: boolean)
	local hrp = getHumanoidRootPart(target)
	if not hrp then
		return
	end

	local userId = target.UserId
	if flyConnections[userId] then
		flyConnections[userId]:Disconnect()
		flyConnections[userId] = nil
	end

	if enabled then
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero

		local bodyVelocity = Instance.new("BodyVelocity")
		bodyVelocity.Name = "AdminFlyVelocity"
		bodyVelocity.MaxForce = Vector3.new(1e7, 1e7, 1e7)
		bodyVelocity.Velocity = Vector3.new(0, 0, 0)
		bodyVelocity.Parent = hrp

		local bodyGyro = Instance.new("BodyGyro")
		bodyGyro.Name = "AdminFlyGyro"
		bodyGyro.MaxTorque = Vector3.new(1e7, 1e7, 1e7)
		bodyGyro.CFrame = hrp.CFrame
		bodyGyro.Parent = hrp

		flyConnections[userId] = hrp.AncestryChanged:Connect(function(_, parent)
			if not parent then
				if flyConnections[userId] then
					flyConnections[userId]:Disconnect()
					flyConnections[userId] = nil
				end
			end
		end)
	else
		local v = hrp:FindFirstChild("AdminFlyVelocity")
		local g = hrp:FindFirstChild("AdminFlyGyro")
		if v then v:Destroy() end
		if g then g:Destroy() end
	end
end

local function killPlayer(target: Player)
	local character = target.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = 0
	end
end

local function trapPlayer(target: Player, durationSeconds: number)
	local hrp = getHumanoidRootPart(target)
	if not hrp then
		return
	end

	local clampedDuration = math.clamp(durationSeconds, 1, MAX_TRAP_TIME_SECONDS)
	local cage = Instance.new("Part")
	cage.Name = "AdminTrap"
	cage.Size = Vector3.new(8, 8, 8)
	cage.CFrame = hrp.CFrame
	cage.Transparency = 0.35
	cage.Material = Enum.Material.ForceField
	cage.Anchored = true
	cage.CanCollide = true
	cage.Parent = workspace

	Debris:AddItem(cage, clampedDuration)
end

local function spawnBrainrotModel(modelName: string, spawnCFrame: CFrame)
	-- Для легального использования: храните NPC-модели в ServerStorage.Brainrots
	local serverStorage = game:GetService("ServerStorage")
	local folder = serverStorage:FindFirstChild("Brainrots")
	if not folder then
		warn("[AdminPanel] ServerStorage.Brainrots не найден")
		return
	end

	local source = folder:FindFirstChild(modelName)
	if not source or not source:IsA("Model") then
		warn("[AdminPanel] Модель Brainrot не найдена: " .. modelName)
		return
	end

	local clone = source:Clone()
	clone:PivotTo(spawnCFrame)
	clone.Parent = workspace
end

local function canUseCommand(player: Player): boolean
	if not isAdmin(player) then
		warn(("[AdminPanel] %s попытался использовать админ-команду без прав"):format(player.Name))
		return false
	end

	local now = os.clock()
	local prev = lastCommandAt[player.UserId]
	if prev and now - prev < COMMAND_COOLDOWN_SECONDS then
		return false
	end

	lastCommandAt[player.UserId] = now
	return true
end

(commandEvent :: RemoteEvent).OnServerEvent:Connect(function(sender: Player, payload: {[string]: any})
	if not canUseCommand(sender) then
		return
	end
	if typeof(payload) ~= "table" then
		return
	end

	local command = payload.command
	if typeof(command) ~= "string" then
		return
	end

	if command == "fly" or command == "unfly" or command == "kill" or command == "trap" or command == "untrap" then
		local targetName = payload.target
		if typeof(targetName) ~= "string" or #targetName < 1 then
			return
		end

		local target = getPlayerByNamePrefix(targetName)
		if not target then
			return
		end

		if command == "fly" then
			setFly(target, true)
		elseif command == "unfly" then
			setFly(target, false)
		elseif command == "kill" then
			killPlayer(target)
		elseif command == "trap" then
			local duration = (typeof(payload.duration) == "number") and payload.duration or 5
			trapPlayer(target, duration)
		elseif command == "untrap" then
			for _, part in ipairs(workspace:GetChildren()) do
				if part:IsA("Part") and part.Name == "AdminTrap" then
					part:Destroy()
				end
			end
		end
		return
	end

	if command == "spawnbrainrot" then
		local modelName = payload.model
		if typeof(modelName) ~= "string" or #modelName < 1 then
			return
		end

		local senderRoot = getHumanoidRootPart(sender)
		if not senderRoot then
			return
		end

		spawnBrainrotModel(modelName, senderRoot.CFrame * CFrame.new(0, 0, -8))
	end
end)
