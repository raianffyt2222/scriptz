getgenv().Config = {
	Misc = {
		PsCode = "",
		FastMode = false,
		WebhookURL = "",
		FpsCap = 25,
	},
	CircleQueue = {
		Enabled = true,
		Order = {
			"", -- First priority - goes to circle first
			"", -- Second priority - waits for Account1
			"", -- Third priority - waits for Account1 and Account2
			"", -- Add more as needed
		},
	},
}

if LPH_OBFUSCATED then
	LRM_INIT_SCRIPT(function()
		function isIdInList(id, ids)
			local AssetService = game:GetService("AssetService")

			local placeids = {}
			local success, pages = pcall(function()
				return AssetService:GetGamePlacesAsync()
			end)

			if success and pages then
				local currentPage = pages
				while true do
					for _, place in currentPage:GetCurrentPage() do
						table.insert(placeids, place.PlaceId)
					end
					if currentPage.IsFinished then
						break
					end
					task.wait() -- Yield to prevent freezing
					local ok, nextPage = pcall(function()
						currentPage:AdvanceToNextPageAsync()
					end)
					if not ok then
						break
					end
					task.wait()
				end
			end
			for _, soulId in ipairs(ids) do
				if soulId == id or table.find(placeids, soulId) then
					return true
				end
			end

			return false
		end
		local placeId = game.PlaceId
		local GPO = isIdInList(placeId, { 1730877806 })
		if GPO then
			repeat
				task.wait()
			until game:IsLoaded()
			task.wait(1)
			local function getExecutor()
				if SELIWARE_LOADED or seliware or getgenv().seliware then
					return "Seliware"
				end

				if DELTA_LOADED or Delta or delta or is_delta_closure or (getgenv and getgenv().Delta) then
					return "Delta"
				end

				if POTASSIUM_LOADED or Potassium or potassium or (getgenv and getgenv().Potassium) then
					return "Potassium"
				end

				if WAVE_LOADED or Wave or wave or is_wave_function or (getgenv and getgenv().Wave) then
					return "Wave"
				end

				if
					VELOCITY_LOADED
					or Velocity
					or velocity
					or is_velocity_closure
					or (getgenv and getgenv().Velocity)
				then
					return "Velocity"
				end

				if getexecutorname then
					local success, name = pcall(getexecutorname)
					if success and name then
						return name
					end
				end

				if identifyexecutor then
					local success, name = pcall(identifyexecutor)
					if success and name then
						return name
					end
				end

				return "Unknown"
			end

			local detectedExecutor = getExecutor()
			print("Executor detected:", detectedExecutor)
			if
				(
					detectedExecutor == "Seliware"
					or detectedExecutor == "Potassium"
					or detectedExecutor == "Wave"
					or detectedExecutor == "Velocity"
				) and placeId ~= 1730877806
			then
				local player = game.Players.LocalPlayer
				local LogService = game:GetService("LogService")
				local errorAlreadyHandled = false

				local ErrorExclusionList = {
					"raiseteleportinitfailedevent",
					"previous teleport is in processing",
					"isteleporting",
					"teleport failed",
					"teleportasync",
				}

				local function isExcludedError(message, stackTrace)
					local combinedText = string.lower(tostring(message) .. " " .. tostring(stackTrace))

					for _, pattern in ipairs(ErrorExclusionList) do
						local found = string.find(combinedText, pattern, 1, true)
						if found then
							warn("⚠️ Excluded error (no kick):", message)
							return true
						end
					end

					return false
				end

				local function isGameScriptError(message, stackTrace)
					local combinedText = (tostring(message) .. " " .. tostring(stackTrace)):lower()

					if
						combinedText:find("rbxassetid")
						or combinedText:find("failed to load")
						or combinedText:find("request asset")
						or combinedText:find("asset was not found")
						or combinedText:find("unable to load")
						or combinedText:find("content failed")
						or combinedText:find("failed to process")
					then
						return true
					end

					local gameLocations = {
						"workspace",
						"replicatedstorage",
						"replicatedfirst",
						"serverscriptservice",
						"serverstorage",
						"starterplayer",
						"startergui",
						"starterpack",
						"lighting",
						"soundservice",
						"chat",
						"teams",
						"players",
					}

					for _, location in ipairs(gameLocations) do
						if combinedText:find(location) then
							return true
						end
					end

					return false
				end

				local function sendErrorAndKick(err, stack)
					if errorAlreadyHandled then
						return
					end

					if isGameScriptError(err, stack) then
						warn("⚠️ Ignoring game script error:", err)
						return
					end

					-- Add this check to skip kicking for excluded errors
					if isExcludedError(err, stack) then
						warn("⚠️ Excluded error detected (no kick):", err)
						return
					end

					errorAlreadyHandled = true

					local errorMsg = tostring(err)
					local maxLength = 200
					if #errorMsg > maxLength then
						errorMsg = errorMsg:sub(1, maxLength) .. "..."
					end

					player:Kick("Error detected - Auto DC to prevent ban\n\n ERROR: \n" .. errorMsg)
				end

				LogService.MessageOut:Connect(function(message, messageType)
					if messageType == Enum.MessageType.MessageError then
						sendErrorAndKick(message, "Caught via LogService")
					end
				end)

				local ScriptContext = game:GetService("ScriptContext")
				if ScriptContext then
					ScriptContext.Error:Connect(function(message, stackTrace, script)
						sendErrorAndKick(message, stackTrace)
					end)
				end
			end
		end
		task.wait()
	end)
end

if not LPH_OBFUSCATED then
	LPH_NO_UPVALUES = function(fn)
		return fn
	end
	LRM_ScriptVersion = 001
	LRM_SecondsLeft = math.huge
	LRM_TotalExecutions = 0
	script_key = false
	function isIdInList(id, ids)
		local AssetService = game:GetService("AssetService")

		local placeids = {}
		local success, pages = pcall(function()
			return AssetService:GetGamePlacesAsync()
		end)

		if success and pages then
			local currentPage = pages
			while true do
				for _, place in currentPage:GetCurrentPage() do
					table.insert(placeids, place.PlaceId)
				end
				if currentPage.IsFinished then
					break
				end
				task.wait() -- Yield to prevent freezing
				local ok, nextPage = pcall(function()
					currentPage:AdvanceToNextPageAsync()
				end)
				if not ok then
					break
				end
				task.wait()
			end
		end
		for _, soulId in ipairs(ids) do
			if soulId == id or table.find(placeids, soulId) then
				return true
			end
		end

		return false
	end
	local placeId = game.PlaceId
	local GPO = isIdInList(placeId, { 1730877806 })
	if GPO then
		repeat
			task.wait()
		until game:IsLoaded()
		task.wait(1)
		local function getExecutor()
			if SELIWARE_LOADED or seliware or getgenv().seliware then
				return "Seliware"
			end

			if DELTA_LOADED or Delta or delta or is_delta_closure or (getgenv and getgenv().Delta) then
				return "Delta"
			end

			if POTASSIUM_LOADED or Potassium or potassium or (getgenv and getgenv().Potassium) then
				return "Potassium"
			end

			if WAVE_LOADED or Wave or wave or is_wave_function or (getgenv and getgenv().Wave) then
				return "Wave"
			end

			if VELOCITY_LOADED or Velocity or velocity or is_velocity_closure or (getgenv and getgenv().Velocity) then
				return "Velocity"
			end

			if getexecutorname then
				local success, name = pcall(getexecutorname)
				if success and name then
					return name
				end
			end

			if identifyexecutor then
				local success, name = pcall(identifyexecutor)
				if success and name then
					return name
				end
			end

			return "Unknown"
		end

		local detectedExecutor = getExecutor()
		print("Executor detected:", detectedExecutor)
		if
			(
				detectedExecutor == "Seliware"
				or detectedExecutor == "Potassium"
				or detectedExecutor == "Wave"
				or detectedExecutor == "Velocity"
			) and placeId ~= 1730877806
		then
			local player = game.Players.LocalPlayer
			local LogService = game:GetService("LogService")
			local errorAlreadyHandled = false

			local function isGameScriptError(message, stackTrace)
				local combinedText = (tostring(message) .. " " .. tostring(stackTrace)):lower()

				if
					combinedText:find("rbxassetid")
					or combinedText:find("failed to load")
					or combinedText:find("request asset")
					or combinedText:find("asset was not found")
					or combinedText:find("unable to load")
					or combinedText:find("content failed")
					or combinedText:find("failed to process")
				then
					return true
				end

				local gameLocations = {
					"workspace",
					"replicatedstorage",
					"replicatedfirst",
					"serverscriptservice",
					"serverstorage",
					"starterplayer",
					"startergui",
					"starterpack",
					"lighting",
					"soundservice",
					"chat",
					"teams",
					"players",
				}

				for _, location in ipairs(gameLocations) do
					if combinedText:find(location) then
						return true
					end
				end

				return false
			end

			local function sendErrorAndKick(err, stack)
				if errorAlreadyHandled then
					return
				end

				if isGameScriptError(err, stack) then
					warn("⚠️ Ignoring game script error:", err)
					return
				end

				errorAlreadyHandled = true

				player:Kick("Error detected - Auto DC to prevent ban")
			end

			LogService.MessageOut:Connect(function(message, messageType)
				if messageType == Enum.MessageType.MessageError then
					sendErrorAndKick(message, "Caught via LogService")
				end
			end)

			local ScriptContext = game:GetService("ScriptContext")
			if ScriptContext then
				ScriptContext.Error:Connect(function(message, stackTrace, script)
					sendErrorAndKick(message, stackTrace)
				end)
			end
		end
	end
	getgenv().Config = {
		Misc = {
			PsCode = "",
			FastMode = false,
			WebhookURL = "",
			FpsCap = 25,
		},
		CircleQueue = {
			Enabled = true, -- Set to false to disable queue system
			Order = {
				"", -- First priority - goes to circle first
				"", -- Second priority - waits for Account1
				"", -- Third priority - waits for Account1 and Account2
				"", -- Add more as needed
			},
		},
	}
end

repeat
	task.wait()
until game:IsLoaded()
local Players = game:GetService("Players")
local player = Players.LocalPlayer or Players.PlayerAdded:Wait()

repeat
	task.wait(0.1)
until game:IsLoaded()

repeat
	task.wait(0.1)
until player:FindFirstChild("Loaded") and player.Loaded.Value == true

game:GetService("Players").LocalPlayer.Idled:Connect(function()
	local vim = Instance.new("VirtualInputManager")
	vim:SendMouseButtonEvent(1, 1, 0, true, game, 0)
	task.wait(0.1)
	vim:SendMouseButtonEvent(1, 1, 0, false, game, 0)
	vim:Destroy()
end)

local Players = game:GetService("Players")
local Localplayer = Players.LocalPlayer or Players.PlayerAdded:Wait()

repeat
	task.wait()
until game:IsLoaded() and Localplayer:FindFirstChild("Loaded") and Localplayer.Loaded

local Player = game.Players.LocalPlayer or game:GetService("Players").LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local Others = {}
local ValuesTable = {}
local ConnectionsTable = {}
local Objects = {}

local Services = {
	Players = game:GetService("Players"),
	ReplicatedStorage = game:GetService("ReplicatedStorage"),
	RunService = game:GetService("RunService"),
	UserInputService = game:GetService("UserInputService"),
	HttpService = game:GetService("HttpService"),
	Stats = game:GetService("Stats"),
	GuiService = game:GetService("GuiService"),
	TweenService = game:GetService("TweenService"),
}

local idsData = {
	MainMenu = 1730877806,
	Universe = 6360478118,
	TradeHub = 6811831486,
	FirstSea = 3978370137,
	SecondSea = 7465136166,
	Dungeon = 11424731604,
}

local ids = setmetatable({}, {
	__index = function(t, key)
		return game.PlaceId == idsData[key]
	end,
})

WebhookIcons = {
	Logo = "https://r2.e-z.host/5dcdabc3-df7f-4ba3-8b8f-48886f22a31f/tbvcypwz.jpg",
	Warning = "https://r2.e-z.host/5dcdabc3-df7f-4ba3-8b8f-48886f22a31f/tbvcypwz.jpg",
	MC = "https://r2.e-z.host/5dcdabc3-df7f-4ba3-8b8f-48886f22a31f/tbvcypwz.jpg",
	Merchant = "https://r2.e-z.host/5dcdabc3-df7f-4ba3-8b8f-48886f22a31f/tbvcypwz.jpg",
	RandomFruit = "https://r2.e-z.host/5dcdabc3-df7f-4ba3-8b8f-48886f22a31f/tbvcypwz.jpg",
}

if getgenv().Config and getgenv().Config.Misc then
	local misc = getgenv().Config.Misc

	if misc.FpsCap then
		setfpscap(misc.FpsCap)
	end

	-- ============================================================
	-- OPTIMIZED FASTMODE - Drop-in replacement
	-- ============================================================
	-- Changes from original:
	--   1. Removed workspace-wide GetDescendants() scan (was scanning 10k+ objects)
	--   2. Removed workspace.DescendantAdded listener (fired for EVERY new object)
	--   3. Targeted scanning: only Islands, Effects, and specific workspace children
	--   4. Single DescendantAdded listener on Islands only (no double-fire)
	--   5. Removed redundant lockOptimizations loop (settings don't revert on their own)
	--   6. WeakValue table for optimizedObjects (auto-GC destroyed objects)
	--   7. Batch yielding tuned: yield every 200 objects instead of 100
	--   8. Lighting locked via PropertyChanged instead of polling loop
	--   9. Collapsed redundant optimize passes into one
	-- ============================================================

	if misc.FastMode then
		local RunService = game:GetService("RunService")
		local Lighting = game:GetService("Lighting")
		local Players = game:GetService("Players")
		local Terrain = workspace:FindFirstChildOfClass("Terrain")
		local player = Players.LocalPlayer

		-- Body part names for skip-coloring check
		local PLAYER_BODY_PARTS = {
			Head = true,
			Torso = true,
			UpperTorso = true,
			LowerTorso = true,
			LeftUpperArm = true,
			LeftLowerArm = true,
			LeftHand = true,
			RightUpperArm = true,
			RightLowerArm = true,
			RightHand = true,
			LeftUpperLeg = true,
			LeftLowerLeg = true,
			LeftFoot = true,
			RightUpperLeg = true,
			RightLowerLeg = true,
			RightFoot = true,
		}

		local NEUTRAL_COLOR = Color3.new(0.568627, 0.568627, 0.568627)
		local SMOOTH_PLASTIC = Enum.Material.SmoothPlastic
		local PERFORMANCE_FIDELITY = Enum.RenderFidelity.Performance

		-- Use weak values so destroyed objects get garbage collected automatically
		local optimizedObjects = setmetatable({}, { __mode = "v" })

		-- ── Lighting & terrain (one-shot, no polling) ────────────────────

		local function applyGraphicsSettings()
			pcall(function()
				settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
				local ugs = UserSettings():GetService("UserGameSettings")
				ugs.SavedQualityLevel = Enum.SavedQualitySetting.QualityLevel1
				ugs.GraphicsQualityLevel = 4
				ugs.GraphicsMode = Enum.GraphicsMode.Manual
			end)

			pcall(function()
				if Terrain then
					Terrain.WaterWaveSize = 0
					Terrain.WaterWaveSpeed = 0
					Terrain.WaterReflectance = 0
					Terrain.WaterTransparency = 0
					Terrain.Decoration = false
				end

				Lighting.GlobalShadows = false
				Lighting.FogEnd = 9e9
				Lighting.FogStart = 0
				Lighting.Brightness = 0
				Lighting.OutdoorAmbient = Color3.new(1, 1, 1)
				Lighting.Ambient = Color3.new(1, 1, 1)
				Lighting.EnvironmentDiffuseScale = 0
				Lighting.EnvironmentSpecularScale = 0
			end)
		end

		-- Disable all current post effects and lock future ones via ChildAdded
		local function disablePostEffects()
			pcall(function()
				for _, effect in ipairs(Lighting:GetChildren()) do
					if effect:IsA("PostEffect") then
						effect.Enabled = false
					end
				end
			end)

			-- Lock: any new post effect gets disabled immediately
			Lighting.ChildAdded:Connect(function(effect)
				if effect:IsA("PostEffect") then
					effect.Enabled = false
				end
			end)

			-- Lock: if game re-enables GlobalShadows, turn it back off
			Lighting:GetPropertyChangedSignal("GlobalShadows"):Connect(function()
				if Lighting.GlobalShadows then
					Lighting.GlobalShadows = false
				end
			end)
		end

		-- ── Object optimization (inlined for speed) ──────────────────────

		local function disableEffect(effect)
			if effect:IsA("ParticleEmitter") or effect:IsA("Trail") or effect:IsA("Beam") then
				effect.Enabled = false
			elseif effect:IsA("PointLight") or effect:IsA("SpotLight") or effect:IsA("SurfaceLight") then
				effect.Enabled = false
				effect.Brightness = 0
			elseif effect:IsA("Fire") or effect:IsA("Smoke") or effect:IsA("Sparkles") then
				effect.Enabled = false
			elseif effect:IsA("Explosion") then
				effect.BlastPressure = 1
				effect.BlastRadius = 1
				effect.Visible = false
			elseif effect:IsA("Sound") then
				effect.Volume = 0
			elseif effect:IsA("Decal") or effect:IsA("Texture") then
				effect.Transparency = 1
			elseif effect:IsA("SurfaceAppearance") then
				effect.TextureID = ""
			end
		end

		local function optimizePart(part, isPlayerPart)
			if optimizedObjects[part] then
				return
			end
			optimizedObjects[part] = part

			if part:IsA("MeshPart") then
				part.TextureID = ""
				part.Material = SMOOTH_PLASTIC
				part.RenderFidelity = PERFORMANCE_FIDELITY
				part.CastShadow = false
				part.Reflectance = 0
				if not isPlayerPart and not PLAYER_BODY_PARTS[part.Name] then
					part.Color = NEUTRAL_COLOR
				end
			elseif part:IsA("BasePart") then
				part.Material = SMOOTH_PLASTIC
				part.Reflectance = 0
				part.CastShadow = false
				if not isPlayerPart and not PLAYER_BODY_PARTS[part.Name] then
					part.Color = NEUTRAL_COLOR
				end
			end

			for _, child in ipairs(part:GetChildren()) do
				pcall(disableEffect, child)
			end
		end

		local YIELD_INTERVAL = 200

		local function optimizeContainer(container, isPlayer)
			if not container then
				return
			end
			task.spawn(function()
				local count = 0
				for _, desc in ipairs(container:GetDescendants()) do
					count = count + 1
					pcall(function()
						if desc:IsA("BasePart") then
							optimizePart(desc, isPlayer)
						else
							disableEffect(desc)
						end
					end)
					if count % YIELD_INTERVAL == 0 then
						task.wait()
					end
				end
			end)
		end

		local function optimizeCharacter(character)
			if not character then
				return
			end
			optimizeContainer(character, true)
		end

		local function setupPlayerMonitor()
			if player.Character then
				optimizeCharacter(player.Character)
			end
			player.CharacterAdded:Connect(function(character)
				task.wait(0.5)
				optimizeCharacter(character)
			end)
		end

		local function optimizeIslands()
			local islands = workspace:FindFirstChild("Islands")
			if not islands then
				return
			end

			optimizeContainer(islands, false)

			islands.DescendantAdded:Connect(function(child)
				task.defer(function()
					pcall(function()
						if child:IsA("BasePart") then
							optimizePart(child, false)
						else
							disableEffect(child)
						end
					end)
				end)
			end)
		end

		local function optimizeEffects()
			local effects = workspace:FindFirstChild("Effects")
			if not effects then
				return
			end

			optimizeContainer(effects, false)

			effects.DescendantAdded:Connect(function(child)
				task.defer(function()
					pcall(function()
						if child:IsA("BasePart") then
							optimizePart(child, false)
						else
							disableEffect(child)
						end
					end)
				end)
			end)
		end

		local SKIP_CONTAINERS = {
			Islands = true,
			Effects = true,
			PlayerCharacters = true,
			Camera = true,
			Terrain = true,
			NPCs = true,
		}

		local function optimizeOtherWorkspaceChildren()
			task.spawn(function()
				local count = 0
				for _, child in ipairs(workspace:GetChildren()) do
					if not SKIP_CONTAINERS[child.Name] and not child:IsA("Camera") and not child:IsA("Terrain") then
						pcall(function()
							for _, desc in ipairs(child:GetDescendants()) do
								count = count + 1
								if desc:IsA("BasePart") then
									optimizePart(desc, false)
								else
									pcall(disableEffect, desc)
								end
								if count % YIELD_INTERVAL == 0 then
									task.wait()
								end
							end
						end)
					end
				end
			end)
		end

		local function InitializeFastMode()
			applyGraphicsSettings()
			disablePostEffects()

			task.wait(0.5)

			optimizeIslands()
			optimizeEffects()
			optimizeOtherWorkspaceChildren()
			setupPlayerMonitor()
		end

		InitializeFastMode()
	end

	if misc.TrackStats then
		local TrackStatsApiKey = getgenv().Config and getgenv().Config.Misc and getgenv().Config.Misc.TrackStats

		if TrackStatsApiKey and TrackStatsApiKey ~= "" then
			local HttpService = game:GetService("HttpService")
			local ReplicatedStorage = game:GetService("ReplicatedStorage")
			local Players = game:GetService("Players")
			local Player = Players.LocalPlayer

			local SEA_PLACES = {
				[3978370137] = 1,
				[6811831486] = 1,
				[7465136166] = 2,
				[11424731604] = 2,
			}

			local GAME_PLACE_ID = game.PlaceId

			if SEA_PLACES[GAME_PLACE_ID] then
				local config = {
					API_KEY = TrackStatsApiKey,
					Send_Interval_Seconds = math.random(200, 300),
					Max_Retries = 3,
					Retry_Delay = 5,
					Debug_Mode = false,
				}

				local API_URL = nil

				local function getStatsFolder()
					return ReplicatedStorage:FindFirstChild("Stats" .. Player.Name)
				end

				local function getPlayerLevel()
					local result = nil
					pcall(function()
						local statsFolder = getStatsFolder()
						if statsFolder and statsFolder:FindFirstChild("Stats") then
							local level = statsFolder.Stats:FindFirstChild("Level")
							if level then
								result = level.Value
							end
						end
					end)
					return result
				end

				local function getPlayerPeli()
					local result = nil
					pcall(function()
						local statsFolder = getStatsFolder()
						if statsFolder and statsFolder:FindFirstChild("Stats") then
							local peli = statsFolder.Stats:FindFirstChild("Peli")
							if peli then
								result = peli.Value
							end
						end
					end)
					return result
				end

				local function getPlayerBounty()
					local result = nil
					pcall(function()
						local statsFolder = getStatsFolder()
						if statsFolder and statsFolder:FindFirstChild("Stats") then
							local bounty = statsFolder.Stats:FindFirstChild("Bounty")
							if bounty then
								result = bounty.Value
							end
						end
					end)
					return result
				end

				local function getPlayerRace()
					local result = nil
					pcall(function()
						local statsFolder = getStatsFolder()
						if statsFolder and statsFolder:FindFirstChild("Customization") then
							local race = statsFolder.Customization:FindFirstChild("Race")
							if race then
								result = race.Value
							end
						end
					end)
					return result
				end

				local function getPlayerFruit()
					local result = nil
					pcall(function()
						local statsFolder = getStatsFolder()
						if statsFolder and statsFolder:FindFirstChild("Stats") then
							local fruit = statsFolder.Stats:FindFirstChild("DF")
							if fruit then
								result = fruit.Value == "" and "No Fruit" or fruit.Value
							end
						end
					end)
					return result
				end

				local function getInventory()
					local items = {}
					pcall(function()
						local statsFolder = getStatsFolder()
						if statsFolder and statsFolder:FindFirstChild("Inventory") then
							local invValue = statsFolder.Inventory:FindFirstChild("Inventory")
							if invValue and invValue.Value then
								local ok, invTable = pcall(function()
									return HttpService:JSONDecode(invValue.Value)
								end)
								if ok and type(invTable) == "table" then
									for itemName, itemData in pairs(invTable) do
										local count = 1
										if type(itemData) == "table" then
											count = itemData.Count
												or itemData.count
												or itemData.Amount
												or itemData.amount
												or 1
										elseif type(itemData) == "number" then
											count = itemData
										end
										table.insert(items, { name = itemName, Count = math.max(1, math.floor(count)) })
									end
								end
							end
						end
					end)
					return items
				end

				local function getIsland()
					local result = nil
					pcall(function()
						local statsFolder = getStatsFolder()
						if statsFolder and statsFolder:FindFirstChild("Stats") then
							local spawnPoint = statsFolder.Stats:FindFirstChild("SpawnPoint")
							if spawnPoint and spawnPoint.Value and spawnPoint.Value ~= "" then
								result = spawnPoint.Value
								return
							end
							local island = statsFolder.Stats:FindFirstChild("Island")
							if island and island.Value and island.Value ~= "" then
								result = island.Value
							end
						end
					end)
					return result
				end

				local function buildPayload()
					return {
						gamePlaceId = "1730877806",
						gpo_id = Player.UserId,
						player_nick = Player.Name,
						level = getPlayerLevel() or 0,
						inventory = getInventory(),
						fruit = getPlayerFruit(),
						race = getPlayerRace(),
						bounty = getPlayerBounty(),
						peli = getPlayerPeli(),
						island = getIsland(),
						sea = SEA_PLACES[GAME_PLACE_ID] or 1,
					}
				end

				local function sendToAPI(payload, retryCount)
					retryCount = retryCount or 0
					if retryCount >= config.Max_Retries then
						return false
					end
					if not payload or type(payload) ~= "table" then
						return false
					end

					local success, response = pcall(function()
						local encoded = HttpService:JSONEncode(payload)
						local headers = {
							["Content-Type"] = "application/json",
							["X-API-Key"] = config.API_KEY,
						}

						local requestFunc = (syn and syn.request)
							or http_request
							or request
							or HttpPost
							or (http and http.request)
						if not requestFunc then
							return false
						end

						return requestFunc({
							Url = API_URL,
							Method = "POST",
							Headers = headers,
							Body = encoded,
						})
					end)

					if success and response then
						if response.StatusCode and response.StatusCode >= 200 and response.StatusCode < 300 then
							if config.Debug_Mode then
								print("[TrackStats] ✓ Data sent")
							end
							return true
						elseif
							response.StatusCode
							and response.StatusCode >= 500
							and retryCount < config.Max_Retries
						then
							task.wait(config.Retry_Delay)
							return sendToAPI(payload, retryCount + 1)
						end
					elseif retryCount < config.Max_Retries then
						task.wait(config.Retry_Delay)
						return sendToAPI(payload, retryCount + 1)
					end
					return false
				end

				-- Auto-start
				task.spawn(function()
					task.wait(5)
					sendToAPI(buildPayload())

					while true do
						task.wait(config.Send_Interval_Seconds)
						config.Send_Interval_Seconds = math.random(200, 300)
						pcall(function()
							sendToAPI(buildPayload())
						end)
					end
				end)
			end
		end
	end

	if misc.WebhookURL and misc.WebhookURL ~= "" and misc.WebhookURL ~= "YourURL" then
		getgenv().WebHook = misc.WebhookURL
	end
end
if LPH_OBFUSCATED then
	task.spawn(function()
		errorMessageConnection = game:GetService("GuiService").ErrorMessageChanged:Connect(function()
			wait(1)
			game:GetService("TeleportService"):Teleport(6360478118)
		end)
	end)
end
getgenv().TweenSpeed = 70
if ids.MainMenu then
	local player = game:GetService("Players").LocalPlayer
	repeat
		task.wait()
	until player and player.AccountAge

	function PlayerLevel()
		local statsFolder = game.ReplicatedStorage:FindFirstChild("Stats" .. player.Name)
		if not statsFolder then
			return nil
		end

		local stats = statsFolder:FindFirstChild("Stats")
		if not stats then
			return nil
		end

		local levelValue = stats:FindFirstChild("Level")
		if not levelValue then
			return nil
		end

		return levelValue.Value
	end

	if player.AccountAge > 30 then
		for i = 1, 500 do
			pcall(function()
				game:GetService("TeleportService"):Teleport(6360478118, game:GetService("Players").LocalPlayer)
			end)
			task.wait(0.1)
		end
	else
		if player.AccountAge > 30 then
			for i = 1, 500 do
				pcall(function()
					game:GetService("TeleportService"):Teleport(6360478118, game:GetService("Players").LocalPlayer)
				end)
				task.wait(0.1)
			end
		else
			local function JoinPS(PS)
				while task.wait(0.5) do
					spawn(function()
						if not PS then
							return
						end

						local TextBox = PlayerGui.reserved.Frame.CodeBox.TextBox

						local ChooseType = PlayerGui:WaitForChild("chooseType", 2)
						local ChooseSea = PlayerGui:WaitForChild("ConfirmationPrompt", 5)

						if ChooseType then
							spawn(function()
								local reg = ChooseType.Frame.Options.Universe
								if reg then
									local args = {
										"universeHub",
									}
									PlayerGui:WaitForChild("chooseType")
										:WaitForChild("Frame")
										:WaitForChild("RemoteEvent")
										:FireServer(unpack(args))
								end
							end)
						else
							TextBox.Text = PS
							local args = { [1] = PS }
							game:GetService("ReplicatedStorage")
								:WaitForChild("Events")
								:WaitForChild("reserved")
								:InvokeServer(unpack(args))
						end
					end)
				end
			end

			if getgenv().Config and getgenv().Config.Misc and getgenv().Config.Misc.PsCode then
				JoinPS(getgenv().Config.Misc.PsCode)
			end
		end
	end
elseif ids.Universe then
	if player.AccountAge < 30 and not game:GetService("ReplicatedStorage").isPrivateServer.Value then
		for i = 1, 500 do
			pcall(function()
				game:GetService("TeleportService"):Teleport(1730877806, game:GetService("Players").LocalPlayer)
			end)
			task.wait(0.1)
		end
	else
		for i = 1, 500 do
			pcall(function()
				local args = {
					"ImpelDown",
				}
				game:GetService("ReplicatedStorage")
					:WaitForChild("Events")
					:WaitForChild("Queue")
					:InvokeServer(unpack(args))
			end)
			task.wait(1)
		end
	end
elseif ids.SecondSea then
	local SpawnPointCF = CFrame.new(5936, 6, -9471)
	local player = Services.Players.LocalPlayer
	local character
	local humanoid
	local hrp
	local camera = workspace.CurrentCamera
	local PLayerstats = Services.ReplicatedStorage:FindFirstChild("Stats" .. player.Name)
	local CircleLocation = Vector3.new(5875, 9, -10221)
	local function updateCharacterRefs()
		character = player.Character
		if character then
			hrp = character:WaitForChild("HumanoidRootPart", 2)
			humanoid = character:WaitForChild("Humanoid", 2)
		else
			hrp = nil
			humanoid = nil
		end
	end
	Others.AnchorReachedPosition = false
	player.CharacterAdded:Connect(function()
		repeat
			task.wait()
			updateCharacterRefs()
		until character and hrp and humanoid
		Others.BodyVelocity = nil
	end)

	updateCharacterRefs()

	local Skills = PLayerstats:FindFirstChild("Skills")
	local backpack = player:FindFirstChild("Backpack")

	do --// Functions
		Others.LastDashTime = 0
		Others.DashCooldown = 1
		Others.Ready = false

		function ItemCheck(itemName)
			local inventory = game:GetService("ReplicatedStorage")["Stats" .. player.Name].Inventory.Inventory
			local inventoryValue = inventory.Value

			local inventoryTable
			local success, result = pcall(function()
				inventoryTable = game:GetService("HttpService"):JSONDecode(inventoryValue)
			end)

			if not success then
				warn("Failed to decode inventory value:", result)
				return false
			end

			return inventoryTable[itemName] ~= nil
		end

		function GetDistanceTo(Position)
			if not Position then
				return math.huge
			end

			if typeof(Position) == "CFrame" then
				Position = Position.Position
			elseif typeof(Position) ~= "Vector3" then
				return
			end

			return (hrp.Position - Position).Magnitude
		end

		function GetSpawnNPCPosition()
			local npcs = workspace:FindFirstChild("NPCs")
			if not npcs then
				return nil
			end

			local robo = npcs:FindFirstChild("Robo")
			if not robo then
				return nil
			end

			local npcHRP = robo:FindFirstChild("HumanoidRootPart")
			if not npcHRP then
				return nil
			end

			return npcHRP.Position
		end

		function SetSpawnPoint()
			local dist = GetDistanceTo(SpawnPointCF)

			if dist > 20 then
				tweenWithTeleport(SpawnPointCF, 50, 4000)
				task.wait(1)
				return
			end

			local npcPos = GetSpawnNPCPosition()
			if not npcPos then
				task.wait(1)
				return
			end

			local npcDist = (hrp.Position - npcPos).Magnitude
			if npcDist < 20 then
				task.wait(0.5)
				Services.ReplicatedStorage.Events.SetSpawn:FireServer()
			end
		end

		function getSpawnPointLoc()
			local stats = PLayerstats:FindFirstChild("Stats")
			if stats then
				local spawnPoint = stats:FindFirstChild("SpawnPoint")
				if spawnPoint then
					return spawnPoint.Value
				end
			end
		end

		function posOf(plr)
			local c = plr.Character
			local n = c and c:FindFirstChild("realPos")
			if n and n.Value then
				return n.Value.Position
			end
			local r = c and c:FindFirstChild("HumanoidRootPart")
			return r and r.Position or nil
		end

		function getdistance(a, b)
			return (a - b).Magnitude
		end

		function HasGeppo()
			local stats = Services.ReplicatedStorage:FindFirstChild("Stats" .. player.Name)
			if not stats then
				return false
			end
			local skills = stats:FindFirstChild("Skills")
			if not skills then
				return false
			end
			local sky = skills:FindFirstChild("skyWalk")
			return sky and sky.Value or false
		end

		Others.LastGeppo = false
		Others.GeppoCooldown = 2

		function UseGeppo()
			Others.LastGeppo = true
			task.delay(Others.GeppoCooldown, function()
				Others.LastGeppo = false
			end)
			for i = 1, 2 do
				local args = {
					false,
				}
				game:GetService("ReplicatedStorage")
					:WaitForChild("Events")
					:WaitForChild("faceMouse")
					:FireServer(unpack(args))
				task.wait(0.5)
			end
		end
	end

	spawn(function()
		while true do
			task.wait(1)
			if getSpawnPointLoc() ~= "Impel Base" then
				SetSpawnPoint(SpawnPointCF)
			else
				Others.Ready = true
				break
			end
		end
	end)

	local CircleLocation = Vector3.new(5875, 9, -10221)
	local CIRCLE_CHECK_RADIUS = 15

	local function getCircleQueueOrder()
		if getgenv().Config and getgenv().Config.CircleQueue and getgenv().Config.CircleQueue.Order then
			return getgenv().Config.CircleQueue.Order
		end
		return {}
	end

	local function isQueueEnabled()
		if getgenv().Config and getgenv().Config.CircleQueue then
			return getgenv().Config.CircleQueue.Enabled ~= false -- Default to true if not set
		end
		return false
	end

	local function getMyPriority()
		local queueOrder = getCircleQueueOrder()
		for i, username in ipairs(queueOrder) do
			if username:lower() == player.Name:lower() then
				return i
			end
		end
		return 999
	end

	local function higherPriorityPlayerInServer()
		if not isQueueEnabled() then
			return false, nil
		end

		local myPriority = getMyPriority()
		local queueOrder = getCircleQueueOrder()

		for _, otherPlayer in pairs(Players:GetPlayers()) do
			if otherPlayer ~= player then
				for i, username in ipairs(queueOrder) do
					if username:lower() == otherPlayer.Name:lower() and i < myPriority then
						return true, otherPlayer.Name
					end
				end
			end
		end
		return false, nil
	end

	local function anyoneAtCircle()
		for _, otherPlayer in pairs(Players:GetPlayers()) do
			if otherPlayer ~= player and otherPlayer.Character then
				local otherHRP = otherPlayer.Character:FindFirstChild("HumanoidRootPart")
				if otherHRP and (otherHRP.Position - CircleLocation).Magnitude < CIRCLE_CHECK_RADIUS then
					return true, otherPlayer.Name
				end
			end
		end
		return false, nil
	end

	local function higherPriorityAtCircle()
		if not isQueueEnabled() then
			return false, nil
		end

		local myPriority = getMyPriority()
		local queueOrder = getCircleQueueOrder()

		for _, otherPlayer in pairs(Players:GetPlayers()) do
			if otherPlayer ~= player and otherPlayer.Character then
				local otherHRP = otherPlayer.Character:FindFirstChild("HumanoidRootPart")
				if otherHRP and (otherHRP.Position - CircleLocation).Magnitude < CIRCLE_CHECK_RADIUS then
					for i, username in ipairs(queueOrder) do
						if username:lower() == otherPlayer.Name:lower() and i < myPriority then
							return true, otherPlayer.Name
						end
					end
				end
			end
		end
		return false, nil
	end

	spawn(function()
		while true do
			task.wait(1)
			if not Others.Ready then
				continue
			end

			local dist = GetDistanceTo(CircleLocation)
			if dist <= 5 then
				task.wait(1)
				continue
			end

			if isQueueEnabled() then
				local myPriority = getMyPriority()
				local higherInServer, higherName = higherPriorityPlayerInServer()
				if higherInServer then
					local atCircle, _ = anyoneAtCircle()
					if atCircle then
						task.wait(5)
						continue
					end

					task.wait(3)

					local stillOccupied, _ = anyoneAtCircle()
					if stillOccupied then
						task.wait(5)
						continue
					end

					local stillHigher, _ = higherPriorityPlayerInServer()
					if stillHigher then
						task.wait(5)
						continue
					end
				end

				local occupied, _ = anyoneAtCircle()
				if occupied then
					task.wait(5)
					continue
				end

				tweenWithTeleport(CircleLocation, 50, 300)
			else
				local occupied, _ = anyoneAtCircle()
				if occupied then
					task.wait(math.random(5, 10))
					continue
				end

				tweenWithTeleport(CircleLocation, 50, 300)
			end

			task.wait(1)
		end
	end)
elseif ids.Dungeon then
	local ItemsToBuy = {
		["Mythical Fruit Chest"] = true,
		["Legendary Fruit Chest"] = false,
		["Rare Fruit Chest"] = false,

		["SP Reset Essence"] = false,
		["Spirit Color Essence"] = false,
		["Dark Root"] = false,
		["Race Reroll"] = false,
		["Raiui"] = false,
		["Kessui"] = false,
		["Vera's Whip"] = false,
		["Black Pitchfork"] = false,
		["Vera's Outfit"] = false,
		["Vera's Outfit 2"] = false,
		["Vera's Cap"] = false,
		["Han's Outfit"] = false,
		["Impel Guard Outfit"] = false,
		["Impel Guard Hat 1"] = false,
		["Impel Guard Hat 2"] = false,
		["Impel Officer Outfit"] = false,
		["Impel Officer Hat"] = false,
		["Shiryu's Cape"] = false,
		["Shiryu's Hat"] = false,
		["Shiryu's Outfit"] = false,
		["Flower Sword"] = false,
	}

	local MovementSystem = {
		isActive = false,
		currentType = nil,
		tweenState = nil,
		inSpawnTween = nil,
		inSpawnTarget = nil,
	}
	local RaiuiAnimsStartTime = 0
	local RAIUI_ANIM_TIMEOUT = 3
	local RaiuiAnimsEndTime = 0
	local RAIUI_RECHECK_COOLDOWN = 1.5
	local currentFloor3Boss = nil
	local lastBossSeenTime = 0
	local BOSS_CONFIRM_DELAY = 2
	function MovementSystem:Lock(movementType)
		if self.isActive then
			self:Unlock()
		end
		self.isActive = true
		self.currentType = movementType
		return true
	end

	function MovementSystem:Unlock()
		self.isActive = false
		self.currentType = nil
		if self.tweenState then
			self.tweenState.active = false
		end
		if self.inSpawnTween then
			self.inSpawnTween.active = false
		end
	end

	function MovementSystem:IsLocked()
		return self.isActive
	end

	function MovementSystem:CancelInSpawn()
		if self.inSpawnTween then
			self.inSpawnTween.active = false
			self.inSpawnTween = nil
			self.inSpawnTarget = nil
		end
	end

	function GetPeli()
		local stats = Services.ReplicatedStorage:FindFirstChild("Stats" .. player.Name)
		if not stats then
			return 0
		end
		local statsData = stats:FindFirstChild("Stats")
		return statsData and statsData:FindFirstChild("Peli") and statsData.Peli.Value or 0
	end

	local LocalPlayer = player
	local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
	local Backpack = LocalPlayer.Backpack
	local PlayerHumpart = Character:WaitForChild("HumanoidRootPart")

	local savetwweenfarm = {}
	local TweensTable = {}
	local noClipConnection
	local openingChests = false
	local spirit_essence = false
	local spiritEssence = false
	local Speed = getgenv().TweenSpeed
	local selected_Offset = 2600
	local targetPosition = nil
	local targetFloorPosition = nil
	local CanFarm = true
	local notcuffed = false
	local equipMelee = false
	local FirstTime = false
	local SecondTime = false
	local firsttimefloor1 = false
	local TweenToStop = nil
	Npc = nil
	local CanTween = false
	local StepCounter = 1
	local skipPart = false
	local tpedback = false
	local DonutRunnable = false
	local SecondFloorSpawnedBoss = false
	local ThirdFloorSpawnedBoss = false
	local FourthSpawnedBoss = false
	local KilledBoss = false
	local FirstTimeFloor5 = false
	local finishedTime = false
	local number69 = 0
	local LastPlaceTween = nil
	floor = "1"
	local statsFolder = game.ReplicatedStorage:FindFirstChild("Stats" .. game.Players.LocalPlayer.Name)
	local value = statsFolder.Inventory.Inventory.Value
	local MythicalChestValue = value:match('"Mythical Fruit Chest":(%d+)') or 0
	local MythicalChestValue = tonumber(MythicalChestValue) or 0
	local MythicalChestsAmount = 0
	local StartFarmingTick = tick()
	local BuyMythical = false

	local function timePassedCalculation(Tick)
		local currentTime = tick()
		local timeDifference = math.floor(currentTime - Tick)

		local hours = math.floor(timeDifference / 3600)
		local remainingSeconds = timeDifference % 3600
		local minutes = math.floor(remainingSeconds / 60)
		local seconds = math.floor(remainingSeconds % 60)

		return string.format("%dh %dm %ds", hours, minutes, seconds)
	end

	function getTimePassed(Tick)
		if Tick then
			return timePassedCalculation(Tick)
		else
			warn("Tick not mentioned before")
			return "0h 0m 0s"
		end
	end

	local SecondFloorTable = {
		secondfloorPart1 = false,
		secondfloorPart2 = false,
		secondfloorPart3 = false,
		secondfloorPart4 = false,
		secondfloorPart5 = false,
		secondfloorPart6 = false,
		secondfloorPart7 = false,
		secondfloorPart8 = false,
		secondfloorPart9 = false,
		secondfloorPart10 = false,
	}

	local SecondFloorPositions = {
		Part1 = { Position = Vector3.new(3210.5830078125, 2380.4306640625, -20259.123046875) },
		Part2 = { Position = Vector3.new(3202.20751953125, 2378.431396484375, -20372.173828125) },
		Part3 = { Position = Vector3.new(3433.396240234375, 2378.4306640625, -20397.3203125) },
		Part4 = { Position = Vector3.new(3450.819580078125, 2378.4306640625, -20590.7890625) },
		Part5 = { Position = Vector3.new(3199.31103515625, 2343.738037109375, -20533.36328125) },
		Part6 = { Position = Vector3.new(3203.50146484375, 2428.4306640625, -20376.19140625) },
		Part7 = { Position = Vector3.new(3198.9306640625, 2378.380615234375, -20566.5703125) },
		Part8 = { Position = Vector3.new(3206.496337890625, 2396.688720703125, -20827.0546875) },
		Part9 = { Position = Vector3.new(3199.43359375, 2378.380615234375, -21072.609375) },
		Part10 = { Position = Vector3.new(3202.12256, 2372.40649, -20873.86725) },
	}

	local ThirdFloor = {
		Part1 = {
			Value = false,
			Position = Vector3.new(4964.24560546875, 2306.330078125, -20738.205078125),
			Lever = false,
		},
		Part2 = {
			Value = false,
			Position = Vector3.new(4805.38720703125, 2306.330078125, -20756.287109375),
			Lever = false,
		},
		Part3 = {
			Value = false,
			Position = Vector3.new(4699.15087890625, 2306.255859375, -20721.974609375),
			Lever = "LeftAreaLever",
		},
		Part4 = { Value = false, Position = Vector3.new(5099.9453125, 2306.330078125, -20780.99609375), Lever = false },
		Part5 = {
			Value = false,
			Position = Vector3.new(5163.779296875, 2306.255615234375, -20800.955078125),
			Lever = "RightAreaLever",
		},
		Part6 = {
			Value = false,
			Position = Vector3.new(4983.416015625, 2306.330078125, -20861.43359375),
			Lever = false,
		},
		Part7 = {
			Value = false,
			Position = Vector3.new(4948.2666015625, 2332.93017578125, -20912.62890625),
			Lever = false,
		},
		Part8 = {
			Value = false,
			Position = Vector3.new(4858.26953125, 2368.330078125, -20999.173828125),
			Lever = false,
		},
		Part9 = {
			Value = false,
			Position = Vector3.new(4799.82763671875, 2398.83056640625, -20797.91015625),
			Lever = false,
		},
		Part10 = {
			Value = false,
			Position = Vector3.new(5148.43408203125, 2398.1298828125, -20800.43359375),
			Lever = false,
		},
		Part11 = {
			Value = false,
			Position = Vector3.new(5546.73193359375, 2405.830078125, -20818.84765625),
			Lever = false,
		},
		Part12 = { Value = false, Position = Vector3.new(5593.4599609375, 2499.830078125, -20967.90625), Lever = false },
		Part13 = {
			Value = false,
			Position = Vector3.new(5654.6669921875, 2481.71728515625, -20514.548828125),
			Lever = false,
		},
		Part14 = {
			Value = false,
			Position = Vector3.new(5665.25048828125, 2482.330322265625, -20251.169921875),
			Lever = false,
		},
	}

	local FourthFloor = {
		Part1 = { Value = false, Position = Vector3.new(9993.8125, 1616.553955078125, -19118.841796875), Lever = false },
		Part2 = {
			Value = false,
			Position = Vector3.new(9994.8974609375, 1668.5535888671875, -19596.22265625),
			Lever = false,
		},
		Part3 = {
			Value = false,
			Position = Vector3.new(9739.0634765625, 1668.5535888671875, -19747.474609375),
			Lever = false,
		},
		Part4 = {
			Value = false,
			Position = Vector3.new(9669.4619140625, 1669.5386962890625, -20239.865234375),
			Lever = false,
		},
		Part5 = {
			Value = false,
			Position = Vector3.new(10124.1279296875, 1669.175048828125, -20304.375),
			Lever = false,
		},
		Part6 = {
			Value = false,
			Position = Vector3.new(10744.009765625, 1668.5535888671875, -20347.998046875),
			Lever = false,
		},
		Part7 = {
			Value = false,
			Position = Vector3.new(10957.7548828125, 1668.5535888671875, -20534.6953125),
			Lever = false,
		},
		Part8 = {
			Value = false,
			Position = Vector3.new(10938.66015625, 1669.179931640625, -20947.974609375),
			Lever = false,
		},
		Part9 = {
			Value = false,
			Position = Vector3.new(10566.3857421875, 1658.66455078125, -20986.9609375),
			Lever = false,
		},
		Part10 = {
			Value = false,
			Position = Vector3.new(9995.662109375, 1658.5535888671875, -21019.478515625),
			Lever = false,
		},
		Part11 = {
			Value = false,
			Position = Vector3.new(9978.056640625, 1694.553466796875, -21877.171875),
			Lever = false,
		},
		Part12 = {
			Value = false,
			Position = Vector3.new(9975.515625, 1665.553466796875, -22142.986328125),
			Lever = false,
		},
	}

	local FifthFloor = {
		Part1 = {
			Value = false,
			Position = Vector3.new(10605.0546875, 542.7198486328125, -27458.15234375),
			Lever = false,
		},
		Part2 = {
			Value = false,
			Position = Vector3.new(10594.2021484375, 490.72015380859375, -28463.830078125),
			Lever = false,
		},
		Part3 = {
			Value = false,
			Position = Vector3.new(10138.6943359375, 459.91595458984375, -28431.333984375),
			Lever = false,
		},
		Part4 = { Value = false, Position = Vector3.new(9677.078125, 512.72021484375, -28457.68359375), Lever = false },
		Part5 = {
			Value = false,
			Position = Vector3.new(9638.5234375, 451.81915283203125, -27622.115234375),
			Lever = false,
		},
	}

	function ItemCheck(itemName)
		local inventory = Services.ReplicatedStorage["Stats" .. player.Name].Inventory.Inventory
		local inventoryValue = inventory.Value

		local inventoryTable
		local success, result = pcall(function()
			inventoryTable = game:GetService("HttpService"):JSONDecode(inventoryValue)
		end)

		if not success then
			warn("Failed to decode inventory value:", result)
			return false
		end

		return inventoryTable[itemName] or 0
	end

	function noClip(Value)
		if noClipConnection then
			noClipConnection:Disconnect()
		end
		if Value then
			noClipConnection = Services.RunService.Stepped:Connect(function()
				pcall(function()
					for i, v in pairs(LocalPlayer.Character:GetChildren()) do
						if v.ClassName == "Part" or v.ClassName == "MeshPart" then
							v.CanCollide = false
						end
					end
				end)
			end)
		end
	end

	local function DisableAllTweens()
		pcall(function()
			for _, tween in ipairs(TweensTable) do
				if tween.Tween then
					tween.Tween:Pause()
					tween.Tween:Cancel()
				end
			end
			for _, tween in pairs(savetwweenfarm) do
				tween:Pause()
				tween:Cancel()
			end
			TweensTable = {} -- Clear tables
			savetwweenfarm = {}
		end)
	end

	function GetTime(Distance, Speed)
		local Time = Distance / (Speed or 80)
		return Time
	end

	local function checkPathClear(startPos, endPos, minClearance)
		minClearance = minClearance or 10

		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Whitelist
		params.FilterDescendantsInstances = { workspace.Islands }

		local direction = endPos - startPos
		local distance = direction.Magnitude

		if distance < 1 then
			return true
		end

		local result = workspace:Raycast(startPos, direction, params)

		if result then
			local hitDistance = (result.Position - startPos).Magnitude
			if hitDistance < distance - minClearance then
				return false, result.Position
			end
		end

		local steps = math.ceil(distance / 20)
		for i = 1, steps do
			local alpha = i / steps
			local checkPos = startPos:Lerp(endPos, alpha)

			return false, checkPos
		end

		return true
	end

	local lastIslandAdded = 0
	local islandAddDelay = 3

	workspace.Islands.ChildAdded:Connect(function(island)
		lastIslandAdded = tick()
	end)

	function canTweenNow()
		return tick() - lastIslandAdded >= islandAddDelay
	end
	local wasRemotePresent = false
	local BlockingStoppedAt = 0
	local BLOCK_TWEEN_DELAY = 2

	local currentInSpawnTween = nil
	Others.LastDashTime = 0
	Others.DashCooldown = 1
	local glideToken = nil
	local isGliding = false
	local glideStartTime = 0
	local glideCooldownEnd = 0
	local hasPreemptivelyMoved = false

	function safeDash(Bypass)
		task.wait()
		local now = tick()
		if now - Others.LastDashTime < Others.DashCooldown and not Bypass then
			return false
		end
		Others.LastDashTime = now
		local args = { 1, "dash" }
		game.ReplicatedStorage.Events.takestam:FireServer(unpack(args))
		return true
	end

	function checkAnticheatNotifications()
		local success, notifFrame = pcall(function()
			return LocalPlayer.PlayerGui.Notifications.Frame
		end)
		if not success or not notifFrame then
			return nil
		end
		local fullText = ""
		for _, descendant in ipairs(notifFrame:GetDescendants()) do
			if descendant:IsA("TextLabel") and descendant.Text and descendant.Text ~= "" then
				fullText = fullText .. " " .. descendant.Text
			end
		end
		local originalText = fullText:lower()
		local compactText = originalText:gsub("%s", "")

		local hasWarningIndicator = originalText:find("anti")
			or originalText:find("cheat")
			or originalText:find("exploit")
			or originalText:find("hack")
			or (originalText:find("warning") and originalText:find("check"))
			or originalText:find("threshold")
			or originalText:find("strike")
			or originalText:find("noclip")
			or originalText:find("overlaphead")

		if not hasWarningIndicator then
			return nil
		end

		if compactText:find("noclipcheck") or compactText:find("noclipdetect") or compactText:find("overlaphead") then
			return "noclip"
		elseif
			compactText:find("teleportcheck")
			or compactText:find("tpcheck")
			or compactText:find("tpdetect")
			or compactText:find("tpchecks")
		then
			return "tpcheck"
		elseif compactText:find("flycheck") or compactText:find("flyhack") or compactText:find("flydetect") then
			return "flycheck"
		elseif compactText:find("velocitycheck") or compactText:find("speedhack") or compactText:find("speedcheck") then
			return "velocity"
		elseif compactText:find("groundcheck") or compactText:find("groundedcheck") then
			return "grounded"
		elseif compactText:find("threshold") or compactText:find("tpchecks") then
			return "threshold"
		elseif compactText:find("strike") then
			if not Others.LastStrikeDash or (tick() - Others.LastStrikeDash) > 5 then
				Facemouse()
				task.wait(0.3)
				Others.LastStrikeDash = tick()
			end
			if PlayerHumpart and math.abs(PlayerHumpart.Position.Y - selected_Offset) < 30 then
				return "ystrike"
			end
		end
		return nil
	end

	local LastInstantTP = 0
	local INSTANT_TP_COOLDOWN = 3
	local INSTANT_TP_LONG_DISTANCE = 1200
	local INSTANT_TP_CLOSE_DISTANCE = 8

	function instatp(pos)
		if typeof(pos) == "Vector3" then
			pos = CFrame.new(pos)
		elseif typeof(pos) ~= "CFrame" then
			return
		end

		local targetPos = pos.Position
		local distance = (PlayerHumpart.Position - targetPos).Magnitude
		local horizontalDistance = GetMagnitudeIgnoringY(targetPos)

		local shouldInstantTP = false

		-- só usa insta TP se estiver MUITO perto horizontalmente
		if horizontalDistance <= INSTANT_TP_CLOSE_DISTANCE then
			shouldInstantTP = true
		end

		-- ou se estiver MUITO longe
		if distance >= INSTANT_TP_LONG_DISTANCE then
			shouldInstantTP = true
		end

		-- cooldown para não spammar CFrame
		if shouldInstantTP and tick() - LastInstantTP >= INSTANT_TP_COOLDOWN then
			LastInstantTP = tick()
			PlayerHumpart.CFrame = pos
		else
			tweenWithTeleport(pos, Speed, selected_Offset)
		end
	end

	local yposResetClock = nil
	local stopblocking = false
	local lastBlockCall = 0
	local COOLDOWN_TIME = 0.2

	function SetBlocking(enable)
		local isBlocking = Character:FindFirstChild("Blocking")
		local currentTime = tick()

		-- Check cooldown
		if currentTime - lastBlockCall < COOLDOWN_TIME then
			return
		end

		if enable and not isBlocking and not stopblocking then
			local args = { [1] = true, [2] = "Melee", [3] = true }
			game:GetService("ReplicatedStorage"):WaitForChild("Events"):WaitForChild("Block"):InvokeServer(unpack(args))
			yPosForBlocking = Character.HumanoidRootPart.Position.Y
			yposResetClock = nil
			lastBlockCall = currentTime
		elseif not enable and isBlocking then
			local args = { [1] = false, [2] = "Melee" }
			game:GetService("ReplicatedStorage"):WaitForChild("Events"):WaitForChild("Block"):InvokeServer(unpack(args))
			BlockingStoppedAt = tick()
			yposResetClock = os.clock()
			lastBlockCall = currentTime
		end
	end
	function controlTower(pos, speed)
		if not PlayerHumpart or not Character or not CanFarm then
			return
		end

		local weaponStyle = Npc and Npc:FindFirstChild("Info") and Npc.Info:FindFirstChild("Weapon")
		local finalPos = pos

		if Character.Humanoid.Health > 300 then
			if
				Npc
				and GetMagnitudeIgnoringY(Npc.HumanoidRootPart.Position) < 50
				and getdistance(Npc.HumanoidRootPart.Position) < 200
				and Npc:GetAttribute("RealName") ~= "Blugori"
				and not NutcrackerAnims
			then
				local m1Distance = 10
				if Npc:GetAttribute("RealName") == "Kramprus" then
					m1Distance = 15
				elseif Npc:GetAttribute("RealName") == "Elo The Bunny" then
					m1Distance = 20
				elseif Npc:FindFirstChild("RaiuiSword") or Npc:GetAttribute("RealName") == "Kelvin, The Nutcracker" then
					m1Distance = 15
				end

				if GetMagnitudeIgnoringY(Npc.HumanoidRootPart.Position) < m1Distance then
					if Npc:GetAttribute("RealName") == "Kramprus" then
						m1AttackSimple(Npc, m1Distance)
					else
						local offset = Vector3.new(0, 6, 3)
						local safeYoffset = 20
						local weaponStyle = Npc:FindFirstChild("Info") and Npc.Info:FindFirstChild("Weapon")
						if Npc:GetAttribute("RealName") == "Elo The Bunny" then
							offset = Vector3.new(0, 10, 6)
							safeYoffset = 20
						elseif
							weaponStyle
							and (weaponStyle.Value == "Flower Bouquet" or weaponStyle.Value == "Candy Cane")
						then
							offset = Vector3.new(0, 7, 3)
							safeYoffset = 30
						elseif Npc:GetAttribute("RealName") == "Kelvin, The Nutcracker" then
							offset = Vector3.new(0, 10, 3)
							safeYoffset = 40
						elseif Npc:GetAttribute("RealName") == "Demon Jester" then
							offset = Vector3.new(0, 8, 3)
							safeYoffset = 40
						elseif Npc:FindFirstChild("RaiuiSword") then
							offset = Vector3.new(0, 7, 3)
						elseif Npc:GetAttribute("RealName") == "Cupid Queen" then
							offset = Vector3.new(0, 8, 0)
						elseif Npc:GetAttribute("RealName") == "Mini Bunny" then
							offset = Vector3.new(0, 7, 0)
						elseif Npc:GetAttribute("HPScaled") then
							offset = Vector3.new(0, 7, 3)
						end
						m1Attack(Npc, safeYoffset, m1Distance, offset, "Air")
						return
					end
				end
			elseif
				Npc
				and GetMagnitudeIgnoringY(Npc.HumanoidRootPart.Position) < 50
				and Npc:GetAttribute("RealName") == "Blugori"
			then
				if GetMagnitudeIgnoringY(Npc.HumanoidRootPart.Position) < 40 then
					local offset = Vector3.new(0, 0, 15)
					m1Attack(Npc, 40, 40, offset, "Air")
					return
				end
			end
		else
			local offset = Vector3.new(0, 80, 0)
			m1Attack(Npc, 40, 0, offset, "Air")
			return
		end

		if typeof(finalPos) == "CFrame" then
			finalPos = finalPos.Position
		end
		local targetPos = finalPos

		if (PlayerHumpart.Position - targetPos).Magnitude > 5 then
			if isUnderTrap(targetPos) then
				targetPos = findSafePositionFromTrap(targetPos)
			end

			local yDifference = math.abs(PlayerHumpart.Position.Y - targetPos.Y)
			if yDifference > 50 then
				Facemouse()
				task.wait(0.3)
			end

			local isSpecialOffsetNpc = Npc
				and (Npc:GetAttribute("RealName") == "Elo The Bunny" or Npc:GetAttribute("RealName") == "Kramprus")

			if isSpecialOffsetNpc then
				instatp(targetPos)
			else
				tweenWithTeleport(CFrame.new(targetPos), speed, selected_Offset)
			end
		end
	end

	function fireProximityPromptSafely(proximityPrompt)
		task.wait()
		if not proximityPrompt or not proximityPrompt:IsA("ProximityPrompt") then
			return
		end

		local parent = proximityPrompt.Parent
		if not parent then
			return
		end

		local targetPos = parent:IsA("Model") and parent:GetPivot().Position or parent.Position

		if (PlayerHumpart.Position - targetPos).Magnitude > 50 then
			return
		end

		for i, v in pairs(workspace.Effects:GetDescendants()) do
			if v:IsA("ProximityPrompt") and v ~= proximityPrompt then
				v.MaxActivationDistance = 0
			end
		end

		workspace.CurrentCamera.CFrame = CFrame.new(workspace.CurrentCamera.CFrame.Position, targetPos)

		proximityPrompt.MaxActivationDistance = 10

		wait(0.1)

		proximityPrompt:InputHoldBegin()
		wait(proximityPrompt.HoldDuration + 0.5 or 0.3)
		proximityPrompt:InputHoldEnd()
		task.wait(1)
	end

	local function getNearestHumPart(RareChests)
		local nearestHumPart = nil
		local minDistance = math.huge

		for _, HumPart in pairs(RareChests) do
			if HumPart then
				local distance = (HumPart.Position - PlayerHumpart.Position).magnitude
				if distance < minDistance then
					minDistance = distance
					nearestHumPart = HumPart
				end
			end
		end

		return nearestHumPart
	end

	local gotSpResetEssence = false
	local gotSpResetFromCommon = false

	local WeaponPriority = {
		["Dark Blade"] = 1100,
		["Hollow's Great Sword"] = 1000,
		["Kraken Blade"] = 100,
		["Vrael's Pipe"] = 90,
	}
	local WeaponsToFarm = {
		["Dark Blade"] = true,
		["Vrael's Pipe"] = true,
		["Hollow's Great Sword"] = true,
		["Kraken Blade"] = true,
	}
	local OwnedFarmedWeapons = {}
	function eatFunction()
		if LocalPlayer.Backpack:FindFirstChild("Spirit Essence") then
			local Tool = LocalPlayer.Backpack["Spirit Essence"]
			Character.Humanoid:EquipTool(Tool)
			Tool:Activate()
			task.wait(1)
			if LocalPlayer.PlayerGui:FindFirstChild("ConfirmationPrompt") then
				local remoteEvent = LocalPlayer.PlayerGui.ConfirmationPrompt:WaitForChild("RemoteEvent")
				if remoteEvent and remoteEvent:IsA("RemoteEvent") then
					remoteEvent:FireServer(true)
				end
				spirit_essence = true
			end
		elseif Character:FindFirstChild("Spirit Essence") then
			local Tool = Character["Spirit Essence"]
			Tool:Activate()
			task.wait(1)
			if LocalPlayer.PlayerGui:FindFirstChild("ConfirmationPrompt") then
				local remoteEvent = LocalPlayer.PlayerGui.ConfirmationPrompt:WaitForChild("RemoteEvent")
				if remoteEvent and remoteEvent:IsA("RemoteEvent") then
					remoteEvent:FireServer(true)
				end
				spirit_essence = true
			end
		end
	end

	function eatSpResetEssence()
		if LocalPlayer.Backpack:FindFirstChild("SP Reset Essence") then
			local Tool = LocalPlayer.Backpack["SP Reset Essence"]
			Character.Humanoid:EquipTool(Tool)
			Tool:Activate()
			task.wait(1)
			if LocalPlayer.PlayerGui:FindFirstChild("ConfirmationPrompt") then
				local remoteEvent = LocalPlayer.PlayerGui.ConfirmationPrompt:WaitForChild("RemoteEvent")
				if remoteEvent and remoteEvent:IsA("RemoteEvent") then
					remoteEvent:FireServer(true)
				end
				gotSpResetEssence = true
			end
		elseif Character:FindFirstChild("SP Reset Essence") then
			local Tool = Character["SP Reset Essence"]
			Tool:Activate()
			task.wait(1)
			if LocalPlayer.PlayerGui:FindFirstChild("ConfirmationPrompt") then
				local remoteEvent = LocalPlayer.PlayerGui.ConfirmationPrompt:WaitForChild("RemoteEvent")
				if remoteEvent and remoteEvent:IsA("RemoteEvent") then
					remoteEvent:FireServer(true)
				end
				gotSpResetEssence = true
			end
		end
	end

	function openCommonChests()
		-- SP Reset is MANDATORY - keep trying until we get one
		local maxAttempts = 100 -- Increased from 50
		local attempts = 0

		local ChestInfo = {
			["rbxassetid://10779253534"] = { ["Name"] = "Common Chest" },
		}

		while attempts < maxAttempts do
			attempts = attempts + 1

			Backpack = game.Players.LocalPlayer.Backpack

			local keepOne = {}
			local keepItems = {
				["Spirit Essence"] = true,
				["SP Reset Essence"] = true,
				["Dark Blade"] = true,
				["Vrael's Pipe"] = true,
				["Kraken Blade"] = true,
				["Hollow's Great Sword"] = true,
			}

			for _, v in pairs(workspace.Effects:GetChildren()) do
				if not keepItems[v.Name] and not v:FindFirstChild("Lock") then
					v:Destroy()
				elseif keepItems[v.Name] then
					if keepOne[v.Name] then
						v:Destroy()
					else
						keepOne[v.Name] = true
					end
				end
			end

			-- Check if we already have SP Reset
			if Backpack:FindFirstChild("SP Reset Essence") or Character:FindFirstChild("SP Reset Essence") then
				eatSpResetEssence()
				gotSpResetFromCommon = true
				return true
			end

			-- Check if SP Reset dropped on ground
			-- Check if SP Reset dropped on ground
			local spResetDrop = workspace.Effects:FindFirstChild("SP Reset Essence")
			if spResetDrop then
				local part = nil
				for _, v in pairs(spResetDrop:GetDescendants()) do
					if v:IsA("BasePart") then
						part = v
						break
					end
				end
				if part then
					local maxAttempts = 15
					for attempt = 1, maxAttempts do
						if
							Backpack:FindFirstChild("SP Reset Essence") or Character:FindFirstChild("SP Reset Essence")
						then
							break
						end

						spResetDrop = workspace.Effects:FindFirstChild("SP Reset Essence")
						if not spResetDrop then
							break
						end

						part = nil
						for _, v in pairs(spResetDrop:GetDescendants()) do
							if v:IsA("BasePart") then
								part = v
								break
							end
						end
						if not part then
							break
						end

						local targetPos = part.Position
						if (targetPos - PlayerHumpart.Position).Magnitude > 5 then
							tweenWithTeleport(CFrame.new(targetPos), Speed, selected_Offset)
							task.wait(0.3)
						end

						for _, v in pairs(spResetDrop:GetDescendants()) do
							if v:IsA("ProximityPrompt") then
								task.wait(0.1)
								fireProximityPromptSafely(v)
								break
							end
						end

						task.wait(0.3)
					end
				end
			end

			if Backpack:FindFirstChild("SP Reset Essence") or Character:FindFirstChild("SP Reset Essence") then
				eatSpResetEssence()
				gotSpResetFromCommon = true
				return true
			end

			-- Find and open common chests
			local CommonChests = {}
			for _, Value in next, workspace.Effects:GetChildren() do
				local meshPart = Value:FindFirstChildOfClass("MeshPart")
				if meshPart and Value:FindFirstChild("Lock") then
					local ChestData = ChestInfo[meshPart.MeshId]
					if ChestData and ChestData.Name == "Common Chest" then
						table.insert(CommonChests, meshPart)
					end
				end
			end

			if #CommonChests == 0 then
				local hasAllocatedStats = statsFolder.Stats.Defense.Value > 0
					or statsFolder.Stats.Strength.Value > 0
					or statsFolder.Stats.SwordMastery.Value > 0

				if hasAllocatedStats and not gotSpResetEssence and not gotSpResetFromCommon then
					game:GetService("TeleportService"):Teleport(6360478118, game:GetService("Players").LocalPlayer)
				end
				break
			end

			local HumPart = getNearestHumPart(CommonChests)
			if HumPart then
				-- Move to chest
				if (HumPart.Position - PlayerHumpart.Position).Magnitude > 5 then
					targetPosition = HumPart.Position + Vector3.new(0, 3, 0)
					tweenWithTeleport(CFrame.new(targetPosition), Speed, selected_Offset)
					task.wait(0.5)
				end

				-- Open chest with improved interaction
				if (HumPart.Position - PlayerHumpart.Position).Magnitude <= 15 then
					local chestOpened = false
					for openAttempt = 1, 3 do
						for _, v in pairs(HumPart.Parent:GetDescendants()) do
							if v:IsA("ProximityPrompt") and v.Enabled == true then
								task.wait(0.2)
								pcall(function()
									fireProximityPromptSafely(v)
								end)

								chestOpened = true
								break
							end
						end
						if chestOpened then
							break
						end
						task.wait(0.2)
					end
				end
			end

			task.wait(0.2)
		end

		return gotSpResetFromCommon or gotSpResetEssence
	end

	function checkOwnedWeapons()
		for weaponName, _ in pairs(WeaponsToFarm) do
			OwnedFarmedWeapons[weaponName] = false
		end

		for weaponName, _ in pairs(WeaponsToFarm) do
			for _, tool in pairs(LocalPlayer.Backpack:GetChildren()) do
				if tool:IsA("Tool") then
					if weaponName == "Kraken Blade" then
						if string.find(tool.Name, "Kraken Blade") then
							OwnedFarmedWeapons[weaponName] = true
							break
						end
					elseif tool.Name == weaponName or tool.Name:find(weaponName) then
						OwnedFarmedWeapons[weaponName] = true
						break
					end
				end
			end

			if not OwnedFarmedWeapons[weaponName] and Character then
				for _, tool in pairs(Character:GetChildren()) do
					if tool:IsA("Tool") then
						if weaponName == "Kraken Blade" then
							if string.find(tool.Name, "Kraken Blade") then
								OwnedFarmedWeapons[weaponName] = true
								break
							end
						elseif tool.Name == weaponName or tool.Name:find(weaponName) then
							OwnedFarmedWeapons[weaponName] = true
							break
						end
					end
				end
			end
		end
	end
	function needsWeaponFromRareChest()
		checkOwnedWeapons()
		for weaponName, shouldFarm in pairs(WeaponsToFarm) do
			if shouldFarm and not OwnedFarmedWeapons[weaponName] then
				return true
			end
		end
		return false
	end

	function pickupWeaponDrops()
		for weaponName, shouldFarm in pairs(WeaponsToFarm) do
			if shouldFarm and not OwnedFarmedWeapons[weaponName] then
				-- For Kraken Blade, search all effects for any matching name
				local weaponDrop = nil
				if weaponName == "Kraken Blade" then
					for _, child in pairs(workspace.Effects:GetChildren()) do
						if string.find(child.Name, "Kraken Blade") then
							weaponDrop = child
							break
						end
					end
				else
					weaponDrop = workspace.Effects:FindFirstChild(weaponName)
				end

				if weaponDrop then
					local part = nil
					for _, v in pairs(weaponDrop:GetDescendants()) do
						if v:IsA("BasePart") then
							part = v
							break
						end
					end
					if part then
						print("→ Fast pickup: " .. weaponDrop.Name)
						local targetPos = part.Position
						local distance = (targetPos - PlayerHumpart.Position).Magnitude

						if distance > 5 then
							if distance < 30 then
								instatp(CFrame.new(targetPos))
							else
								tweenWithTeleport(CFrame.new(targetPos), Speed, selected_Offset)
							end
						end

						task.wait(0.05)

						for _, v in pairs(weaponDrop:GetDescendants()) do
							if v:IsA("ProximityPrompt") then
								task.wait(0.02)
								fireProximityPromptSafely(v)
								break
							end
						end

						task.wait(0.1)
						checkOwnedWeapons()
					end
				end
			end
		end
	end

	function hakiFarm()
		local ChestInfo = {
			["rbxassetid://10811929054"] = {
				["Name"] = "Mythical Chest",
				["Color"] = Color3.fromRGB(112, 10, 255),
			},
			["rbxassetid://10798559852"] = {
				["Name"] = "Legendary Chest",
				["Color"] = Color3.fromRGB(202, 12, 37),
			},
			["rbxassetid://10788852296"] = {
				["Name"] = "Rare Chest",
				["Color"] = Color3.fromRGB(44, 125, 202),
			},
			["rbxassetid://10858352843"] = {
				["Name"] = "Uncommon Chest",
				["Color"] = Color3.fromRGB(202, 174, 32),
			},
			["rbxassetid://10779253534"] = {
				["Name"] = "Common Chest",
				["Color"] = Color3.fromRGB(45, 152, 84),
			},
		}

		-- Helper function to count rare chests
		local function countRareChests()
			local count = 0
			for _, Value in next, workspace.Effects:GetChildren() do
				local meshPart = Value:FindFirstChildOfClass("MeshPart")
				if meshPart and Value:FindFirstChild("Lock") then
					local ChestData = ChestInfo[meshPart.MeshId]
					if ChestData and ChestData.Name == "Rare Chest" then
						count = count + 1
					end
				end
			end
			return count
		end

		-- Helper function to check if we have any target weapon
		local function hasTargetWeapon()
			checkOwnedWeapons()
			return OwnedFarmedWeapons["Kraken Blade"]
				or OwnedFarmedWeapons["Vrael's Pipe"]
				or OwnedFarmedWeapons["Hollow's Great Sword"]
				or OwnedFarmedWeapons["Dark Blade"]
		end

		-- STEP 1: SP RESET ESSENCE FIRST (PRIORITY)
		if not gotSpResetEssence and not gotSpResetFromCommon then
			openCommonChests()
		end

		if Backpack:FindFirstChild("SP Reset Essence") or Character:FindFirstChild("SP Reset Essence") then
			eatSpResetEssence()
		end

		-- STEP 2: Check if we already have a weapon - if so, just get Spirit Essence and return
		pickupWeaponDrops()
		if hasTargetWeapon() then
			print("✓ Already have weapon, just need Spirit Essence")
			-- Just get spirit essence if needed
			local hashaki = statsFolder.Stats.BusoMastery.Value ~= 0
			if hashaki then
				return -- Already have haki and weapon, done
			end
			-- Continue to get spirit essence only
		end

		-- STEP 3: SPIRIT ESSENCE AND WEAPONS (RARE CHESTS)
		local RareChests = {}

		spiritEssence = not spirit_essence and workspace.Effects:FindFirstChild("Spirit Essence")

		-- Main chest opening loop - continues until we have BOTH spirit essence AND a weapon (or no chests left)
		repeat
			task.wait(0.1)

			if Backpack:FindFirstChild("SP Reset Essence") or Character:FindFirstChild("SP Reset Essence") then
				eatSpResetEssence()
			end

			pickupWeaponDrops()

			-- Check current status
			local hashaki = statsFolder.Stats.BusoMastery.Value ~= 0
			local hasWeapon = hasTargetWeapon()
			spiritEssence = not spirit_essence and workspace.Effects:FindFirstChild("Spirit Essence")

			-- If we have both haki and weapon, we're done
			if hashaki and hasWeapon then
				print("✓ Have both haki and weapon - done with hakiFarm")
				return
			end

			openingChests = true
			RareChests = {}

			-- Build list of rare chests
			for _, Value in next, workspace.Effects:GetChildren() do
				local meshPart = Value:FindFirstChildOfClass("MeshPart")
				if meshPart then
					if Value:FindFirstChild("Lock") then
						local ChestData = ChestInfo[meshPart.MeshId]
						if ChestData and ChestData.Name == "Rare Chest" then
							table.insert(RareChests, meshPart)
						elseif ChestData and ChestData.Name ~= "Common Chest" then
							Value:Destroy()
						end
					end
				end
			end

			-- If spirit essence is on ground, pick it up
			if spiritEssence then
				local part = nil
				for _, v in pairs(spiritEssence:GetDescendants()) do
					if v:IsA("BasePart") then
						part = v
						break
					end
				end
				if part then
					local targetPos = part.Position
					if (targetPos - PlayerHumpart.Position).Magnitude > 5 then
						tweenWithTeleport(CFrame.new(targetPos), Speed, selected_Offset)
					end
					task.wait(0.2)
					for _, v in pairs(spiritEssence:GetDescendants()) do
						if v:IsA("ProximityPrompt") then
							task.wait(0.05)
							fireProximityPromptSafely(v)
							break
						end
					end
				end
			end

			-- Try to eat spirit essence if we have it
			if Character:FindFirstChild("Spirit Essence") or Backpack:FindFirstChild("Spirit Essence") then
				eatFunction()
				task.wait(0.2)
			end

			if #RareChests == 0 and workspace.Islands:FindFirstChild("Impel Base - Floor 1") then
				local currentHasWeapon = hasTargetWeapon()
				local currentHasHaki = statsFolder.Stats.BusoMastery.Value ~= 0

				if not currentHasWeapon then
					task.wait(2)
					game:GetService("TeleportService"):Teleport(6360478118, game:GetService("Players").LocalPlayer)
					return
				elseif not currentHasHaki then
					task.wait(2)
					game:GetService("TeleportService"):Teleport(6360478118, game:GetService("Players").LocalPlayer)
					return
				else
					return
				end
			end

			local HumPart = nil
			if Others.LockedChest and Others.LockedChest.Parent and Others.LockedChest:FindFirstChild("Lock", true) then
				HumPart = Others.LockedChest
			else
				Others.LockedChest = nil
				HumPart = getNearestHumPart(RareChests)
				if HumPart then
					Others.LockedChest = HumPart
				end
			end
			if HumPart then
				eatFunction()
				task.wait(0.1)

				workspace.CurrentCamera.CFrame = CFrame.new(workspace.CurrentCamera.CFrame.Position, HumPart.Position)

				if (HumPart.Position - PlayerHumpart.Position).Magnitude > 5 then
					targetPosition = HumPart.Position + Vector3.new(0, 3, 0)
					task.wait(0.1)
					tweenWithTeleport(CFrame.new(targetPosition), Speed, selected_Offset)
					CanTween = true
				end

				if (HumPart.Position - PlayerHumpart.Position).Magnitude <= 10 then
					local ProximityFound = true
					repeat
						ProximityFound = false
						for _, v in pairs(HumPart.Parent:GetDescendants()) do
							if v:IsA("ProximityPrompt") and v.Enabled == true then
								task.wait(0.05)
								fireProximityPromptSafely(v)
								ProximityFound = true
								break
							end
						end
						if not ProximityFound then
							pcall(function()
								HumPart.Parent:Destroy()
							end)
						end
						task.wait(0.1)
						pickupWeaponDrops()
					until not HumPart
						or not HumPart.Parent
						or not ProximityFound
						or (HumPart.Position - PlayerHumpart.Position).Magnitude > 10
				end
			end

			if
				Others.LockedChest
				and (not Others.LockedChest.Parent or not Others.LockedChest:IsDescendantOf(workspace))
			then
				Others.LockedChest = nil
			end
			local keepOne = {}
			local keepItems = {
				["Spirit Essence"] = true,
				["SP Reset Essence"] = true,
				["Dark Blade"] = true,
				["Vrael's Pipe"] = true,
				["Kraken Blade"] = true,
				["Hollow's Great Sword"] = true,
			}

			for _, v in pairs(workspace.Effects:GetChildren()) do
				if not keepItems[v.Name] and not v:FindFirstChild("Lock") then
					v:Destroy()
				elseif keepItems[v.Name] then
					if keepOne[v.Name] then
						v:Destroy()
					else
						keepOne[v.Name] = true
					end
				end
			end

		until false -- Loop continues until we return from inside
	end
	local part = Instance.new("Part")
	part.Name = "RedZone"
	part.Anchored = true
	part.CanCollide = false
	part.Size = Vector3.new(1130, 400, 1405)
	part.Position = Vector3.new(2952.53003, 2375.44531, -14727.2305)
	part.Color = Color3.fromRGB(255, 0, 0)
	part.Transparency = 1
	part.Parent = workspace

	function GetImpelNpc()
		task.wait()
		if #workspace.NPCs:GetChildren() == 0 then
			return
		end
		if workspace.Islands:FindFirstChild("Impel Base - Finished") then
			return
		end

		local redZone = workspace:FindFirstChild("RedZone")
		if redZone and workspace.Islands:FindFirstChild("Impel Base - Floor 1") then
			local halfSize = redZone.Size / 2
			for _, npc in pairs(workspace.NPCs:GetChildren()) do
				if npc:FindFirstChild("HumanoidRootPart") then
					local npcPos = npc.HumanoidRootPart.Position
					local redZonePos = redZone.Position
					local inX = math.abs(npcPos.X - redZonePos.X) <= halfSize.X
					local inZ = math.abs(npcPos.Z - redZonePos.Z) <= halfSize.Z
					if inX and inZ then
						npc:Destroy()
					end
				end
			end
		end

		local function hasDevilFruit(npc)
			return npc:FindFirstChild("Info") and npc.Info:FindFirstChild("DevilFruit")
		end

		local NearestNpc, Distance = nil, 400
		local PlayerPosition = PlayerHumpart.Position

		if
			workspace.NPCs:FindFirstChild("Warden of Impel Down, Vera")
			and workspace.Islands:FindFirstChild("Impel Base - Floor 5")
		then
			NearestNpc = workspace.NPCs["Warden of Impel Down, Vera"]
			if not NearestNpc:GetAttribute("RealName") then
				NearestNpc:SetAttribute("RealName", NearestNpc.Name)
			end
			return NearestNpc
		end

		if workspace.NPCs:FindFirstChild("Kelvin, The Nutcracker") then
			NearestNpc = workspace.NPCs["Kelvin, The Nutcracker"]
			if not NearestNpc:GetAttribute("RealName") then
				NearestNpc:SetAttribute("RealName", NearestNpc.Name)
			end
			return NearestNpc
		end

		local hpScaledNpc = nil
		local hpScaledDistance = Distance

		for _, TargetNpc in pairs(workspace.NPCs:GetChildren()) do
			local HumPart = TargetNpc:FindFirstChild("HumanoidRootPart")
			if
				HumPart
				and TargetNpc.Name ~= "Scorpion"
				and TargetNpc.Name ~= "Basilisk"
				and TargetNpc:GetAttribute("HPScaled")
			then
				local NpcPosition = HumPart.Position
				local CurrentDistance = (NpcPosition - PlayerPosition).magnitude
				if CurrentDistance < hpScaledDistance then
					hpScaledNpc = TargetNpc
					hpScaledDistance = CurrentDistance
				end
			end
		end

		if hpScaledNpc then
			local currentTest = workspace.NPCs:FindFirstChild("Test")
			if currentTest and currentTest ~= hpScaledNpc then
				if not currentTest:GetAttribute("RealName") then
					currentTest:SetAttribute("RealName", currentTest.Name)
				end
				currentTest.Name = currentTest:GetAttribute("RealName") or "FarNpc"
			end

			NearestNpc = hpScaledNpc
			if not NearestNpc:GetAttribute("RealName") then
				NearestNpc:SetAttribute("RealName", NearestNpc.Name)
			end
			NearestNpc.Name = "Test"
			return NearestNpc
		end

		local devilFruitNpc = nil
		local devilFruitDistance = Distance

		for _, TargetNpc in pairs(workspace.NPCs:GetChildren()) do
			local HumPart = TargetNpc:FindFirstChild("HumanoidRootPart")
			if
				HumPart
				and TargetNpc.Name ~= "Scorpion"
				and TargetNpc.Name ~= "Basilisk"
				and hasDevilFruit(TargetNpc)
			then
				local NpcPosition = HumPart.Position
				local CurrentDistance = (NpcPosition - PlayerPosition).magnitude
				if CurrentDistance < devilFruitDistance then
					devilFruitNpc = TargetNpc
					devilFruitDistance = CurrentDistance
				end
			end
		end

		if devilFruitNpc then
			local currentTest = workspace.NPCs:FindFirstChild("Test")
			if currentTest and currentTest ~= devilFruitNpc then
				if not currentTest:GetAttribute("RealName") then
					currentTest:SetAttribute("RealName", currentTest.Name)
				end
				currentTest.Name = currentTest:GetAttribute("RealName") or "FarNpc"
			end

			NearestNpc = devilFruitNpc
			if not NearestNpc:GetAttribute("RealName") then
				NearestNpc:SetAttribute("RealName", NearestNpc.Name)
			end
			NearestNpc.Name = "Test"
			return NearestNpc
		end

		if workspace.NPCs:FindFirstChild("Test") then
			local TestNpc = workspace.NPCs.Test
			if TestNpc:FindFirstChild("HumanoidRootPart") then
				local TestNpcPosition =
					Vector3.new(TestNpc.HumanoidRootPart.Position.X, 0, TestNpc.HumanoidRootPart.Position.Z)
				local PlayerFlatPosition = Vector3.new(PlayerPosition.X, 0, PlayerPosition.Z)
				local DistanceToTest = (TestNpcPosition - PlayerFlatPosition).Magnitude
				if DistanceToTest <= 600 or #workspace.NPCs:GetChildren() <= 1 then
					NearestNpc = TestNpc
					return NearestNpc
				elseif DistanceToTest > 600 then
					TestNpc.Name = "FarNpc"
				end
			end
		end

		local logiaNpc = nil
		local logiaDistance = Distance

		for _, TargetNpc in pairs(workspace.NPCs:GetChildren()) do
			local HumPart = TargetNpc:FindFirstChild("HumanoidRootPart")
			local hasLogiaFolder = TargetNpc:FindFirstChild("Logia") or TargetNpc:FindFirstChild("logia")
			if HumPart and TargetNpc.Name ~= "Scorpion" and TargetNpc.Name ~= "Basilisk" and hasLogiaFolder then
				local _, _, specialAction = willCrossHut(TargetNpc)
				local isStuckInBuilding = (specialAction == "timeout_escape")

				if not isStuckInBuilding then
					local NpcPosition = HumPart.Position
					local CurrentDistance = (NpcPosition - PlayerPosition).magnitude
					if CurrentDistance < logiaDistance then
						logiaNpc = TargetNpc
						logiaDistance = CurrentDistance
					end
				end
			end
		end

		if logiaNpc then
			NearestNpc = logiaNpc
			Distance = logiaDistance
		else
			for _, TargetNpc in pairs(workspace.NPCs:GetChildren()) do
				local HumPart = TargetNpc:FindFirstChild("HumanoidRootPart")
				if HumPart and TargetNpc.Name ~= "Scorpion" and TargetNpc.Name ~= "Basilisk" then
					local NpcPosition = HumPart.Position
					local CurrentDistance = (NpcPosition - PlayerPosition).magnitude
					if CurrentDistance < Distance then
						NearestNpc = TargetNpc
						Distance = CurrentDistance
					end
				end
			end
		end

		if
			NearestNpc
			and NearestNpc.Name ~= "Test"
			and NearestNpc.Name ~= "Warden of Impel Down, Vera"
			and NearestNpc.Name ~= "Kelvin, The Nutcracker"
		then
			if not NearestNpc:GetAttribute("RealName") then
				NearestNpc:SetAttribute("RealName", NearestNpc.Name)
			end
			NearestNpc.Name = "Test"
		end

		if NearestNpc and not NearestNpc:FindFirstChild("HumanoidRootPart") then
			NearestNpc = nil
		end
		print("NPC: ", NearestNpc)

		return NearestNpc
	end
	function HasSledgehammerNPC()
		for _, npc in pairs(workspace.NPCs:GetChildren()) do
			if npc:FindFirstChild("Elo's Sledgehammer") then
				return true
			end
		end
		return false
	end
	function detectPart()
		local offset = 10

		if not Npc or not Npc:FindFirstChild("HumanoidRootPart") then
			return PlayerHumpart.Position
		end

		if
			Character
			and Character:FindFirstChild("HumanoidRootPart")
			and Character.HumanoidRootPart.Position.Y <= -10000
			and targetFloorPosition
		then
			return targetFloorPosition + Vector3.new(0, 20, 0)
		end

		local animationStyle = Npc and Npc:FindFirstChild("Info") and Npc.Info:FindFirstChild("AnimationStyle")
		local weaponStyle = Npc and Npc:FindFirstChild("Info") and Npc.Info:FindFirstChild("Weapon")

		local Baal = animationStyle
			and (animationStyle.Value == "PumpkinBoss" or animationStyle.Value == "Jester")
			and Npc

		if RaiuiAnims then
			return Vector3.new(Npc.HumanoidRootPart.Position.X, selected_Offset - 400, Npc.HumanoidRootPart.Position.Z)
		end

		if NutcrackerAnims then
			return Npc.HumanoidRootPart.Position + Vector3.new(0, 60, 0)
		end

		if
			Npc.Name == "Warden of Impel Down, Vera"
			or Npc:GetAttribute("RealName") == "Elo The Bunny"
			or Npc.Name == "Kelvin, The Nutcracker"
			or Npc:GetAttribute("RealName") == "Kramprus"
			or (animationStyle and animationStyle.Value == "Blugori")
			or (weaponStyle and (weaponStyle.Value == "Flower Bouquet" or weaponStyle.Value == "Candy Cane"))
			or Baal
		then
			if
				targetFloorPosition
				and (
					Baal
					or (
						weaponStyle
						and (
							weaponStyle.Value == "Flower Bouquet"
							or weaponStyle.Value == "Candy Cane"
							or weaponStyle.Value == "Festival Shield"
						)
					)
				)
			then
				if
					weaponStyle
					and (
						weaponStyle.Value == "Flower Bouquet"
						or weaponStyle.Value == "Candy Cane"
						or weaponStyle.Value == "Festival Shield"
					)
				then
					return Npc.HumanoidRootPart.Position + Vector3.new(0, offset, 0)
				end

				return targetFloorPosition + Vector3.new(0, 15, 0)
			elseif
				not targetFloorPosition
				and (
					Baal
					or (weaponStyle and (weaponStyle.Value == "Flower Bouquet" or weaponStyle.Value == "Candy Cane"))
				)
			then
				return Npc.HumanoidRootPart.Position + Vector3.new(0, offset, 0)
			elseif targetFloorPosition and Npc.Name == "Warden of Impel Down, Vera" then
				return Npc.HumanoidRootPart.Position + Vector3.new(0, offset, 0)
			elseif animationStyle and animationStyle.Value == "Blugori" then
				Npc:SetAttribute("Blugori", true)
				return Npc.HumanoidRootPart.Position + Vector3.new(0, 0, 20)
			elseif Npc:GetAttribute("RealName") == "Kramprus" then
				return Npc.HumanoidRootPart.Position + Vector3.new(0, 0, 10)
			elseif Npc:FindFirstChild("RaiuiSword") then
				return Npc.HumanoidRootPart.Position + Vector3.new(0, 0, 20)
			elseif Npc:GetAttribute("RealName") == "Elo The Bunny" then
				return Npc.HumanoidRootPart.Position
					- (Npc.HumanoidRootPart.CFrame.LookVector * 10)
					+ Vector3.new(0, 15, 5)
			elseif targetFloorPosition then
				return targetFloorPosition + Vector3.new(0, 45, 0)
			else
				return Npc.HumanoidRootPart.Position + Vector3.new(0, offset, 0)
			end
		end

		return Npc.HumanoidRootPart.Position + Vector3.new(0, offset, 0)
	end

	spawn(function()
		while task.wait() do
			if workspace:GetAttribute("serverAge") >= 2700 then
				game:GetService("TeleportService"):Teleport(6360478118, game:GetService("Players").LocalPlayer)
				break
			end
			if PlayerHumpart then
				local isFightingVera = Npc and Npc.Name == "Vera"
				local agibleForVelocity = PlayerHumpart
					and ((workspace:GetAttribute("HandCuffed") and not Character:FindFirstChild("Cuffed")) or isFightingVera)
					and PlayerHumpart:FindFirstChild("BodyVelocity")

				if not agibleForVelocity then
					PlayerHumpart.Velocity = Vector3.new(0, 0, 0)
				end
			end
		end
	end)
	spawn(function()
		while task.wait() do
			local Checker = false
			pcall(function()
				if
					Npc
					and (
						Npc:FindFirstChild("Logia")
						or Npc:FindFirstChild("logia")
						or Npc:FindFirstChild("Info") and Npc.Info:FindFirstChild("DevilFruit")
					)
				then
					if not Npc:GetAttribute("HPScaled") then
						Npc:SetAttribute("HPScaled", true)
					end
				end

				if Npc and Npc:FindFirstChild("RaiuiSword") then
					local hasUnderscore = workspace.Effects:FindFirstChild("_")

					local hasRaiuPart = false
					pcall(function()
						for _, part in pairs(workspace.Effects:GetDescendants()) do
							if part:IsA("BasePart") and part.Name:match("^RaiuMove2") then
								hasRaiuPart = true
								break
							end
						end
					end)

					if (hasUnderscore or hasRaiuPart) and (tick() - RaiuiAnimsEndTime > RAIUI_RECHECK_COOLDOWN) then
						if not RaiuiAnims then
							RaiuiAnimsStartTime = tick()
						end
						RaiuiAnims = true
						RAIUIBOSSSPAWNED = true
						Checker = true
						local oldYpos = PlayerHumpart.Position.Y
						task.wait(0.5)
					elseif not hasUnderscore and not hasRaiuPart then
						if RaiuiAnims then
							RaiuiAnimsEndTime = tick()
						end
						RaiuiAnims = false
						RaiuiAnimsStartTime = 0
					end

					if RaiuiAnims and (tick() - RaiuiAnimsStartTime) > RAIUI_ANIM_TIMEOUT then
						RaiuiAnimsEndTime = tick()
						RaiuiAnims = false
						RaiuiAnimsStartTime = 0
					end
				else
					RaiuiAnims = false
					RaiuiAnimsStartTime = 0
				end

				if
					Npc
					and (Npc.Name == "Kelvin, The Nutcracker" or Npc:GetAttribute("RealName") == "Elo The Bunny" or Npc:GetAttribute(
						"RealName"
					) == "Blugori")
					and Npc:FindFirstChild("Humanoid")
				then
					local playingAnimationTracks = Npc.Humanoid:GetPlayingAnimationTracks()
					local animationIdToCheck = 8201580596
					local animationIdToCheck2 = 15246831598
					local animationIdToCheck3 = 6647575254
					for _, track in ipairs(playingAnimationTracks) do
						if track.Animation.AnimationId == "rbxassetid://" .. animationIdToCheck then
							NutcrackerAnims = true
							Checker = true
						elseif track.Animation.AnimationId == "rbxassetid://" .. animationIdToCheck2 then
							BlugoriAnims = false
							Checker = true
						elseif track.Animation.AnimationId == "rbxassetid://" .. animationIdToCheck3 then
							EloAnims = true
							Checker = true
							local oldYpos = PlayerHumpart.Position.Y
							local targetY = oldYpos + 60
							Facemouse()
							task.wait(0.3)
							PlayerHumpart.CFrame =
								CFrame.new(PlayerHumpart.Position.X, targetY, PlayerHumpart.Position.Z)
							task.wait(2)
							PlayerHumpart.CFrame =
								CFrame.new(PlayerHumpart.Position.X, oldYpos, PlayerHumpart.Position.Z)
							EloAnims = false
						end
					end
					if not Checker then
						NutcrackerAnims = false
						BlugoriAnims = false
						EloAnims = false
					end
				else
					NutcrackerAnims = false
					BlugoriAnims = false
					EloAnims = false
				end

				if Character and Character.Humanoid then
					Character.Humanoid.AutoRotate = false
				end
			end)
		end
	end)

	local MazeNpcsFound = false
	local MazeNpcsKilled = false
	local MazeNpcKilledTime = 0

	function MazeNpcKill()
		success, Npc = pcall(GetImpelNpc)
		if not success then
			Npc = nil
		end

		local function CountMazeNpcs()
			local count = 0
			local mazeCenter = Vector3.new(2674.46435546875, 2075.4453125, -15478.548828125)

			for _, npc in pairs(workspace.NPCs:GetChildren()) do
				if npc:FindFirstChild("HumanoidRootPart") and npc:FindFirstChild("Humanoid") then
					local npcPos = npc.HumanoidRootPart.Position
					local distance = (Vector3.new(mazeCenter.X, npcPos.Y, mazeCenter.Z) - npcPos).Magnitude

					if distance <= 200 and npc.Humanoid.Health > 0 then
						count = count + 1
					end
				end
			end

			return count
		end

		if Npc then
			MazeNpcsFound = true
			MazeNpcsKilled = false
		end

		if MazeNpcsFound and not MazeNpcsKilled then
			local aliveNpcs = CountMazeNpcs()

			if aliveNpcs == 0 then
				MazeNpcsKilled = true
				MazeNpcKilledTime = tick()
			end
		end

		if
			not Npc
			and (Vector3.new(2674.46435546875, 2075.4453125, -15478.548828125) - Vector3.new(
				PlayerHumpart.Position.X,
				2075.4453125,
				PlayerHumpart.Position.Z
			)).Magnitude > 20
			and not Character:FindFirstChild("Cuffed")
			and not workspace.Islands["Impel Base - Floor 1"].Barriers:FindFirstChild("FirstBarrier")
		then
			if MazeNpcsKilled then
				local timeWaited = tick() - MazeNpcKilledTime
				if timeWaited < 5 then
					return
				else
					MazeNpcsFound = false
					MazeNpcsKilled = false
				end
			end

			wait(1)
			skipPart = true
			targetPosition = Vector3.new(2674.46435546875, 2075.4453125, -15478.548828125)
			targetFloorPosition = Vector3.new(2674.46435546875, 2075.4453125, -15478.548828125)
			local Distance = (targetPosition - PlayerHumpart.Position).magnitude
			local Time = GetTime(Distance, Speed)
			wait()
			local targetCFrame = CFrame.new(targetPosition)
			tweenWithTeleport(targetCFrame, Speed, selected_Offset)
			task.wait(2)
		elseif
			(
				not Character:FindFirstChild("Cuffed")
				and not workspace.Islands["Impel Base - Floor 1"].Barriers:FindFirstChild("FirstBarrier")
				and GetMagnitudeIgnoringY(Vector3.new(2674.46435546875, 2075.4453125, -15478.548828125)) < 20
			)
			or (
				Npc
				and not Character:FindFirstChild("Cuffed")
				and not workspace.Islands["Impel Base - Floor 1"].Barriers:FindFirstChild("FirstBarrier")
			)
		then
			skipPart = false
			if not tpedback then
				Speed = getgenv().TweenSpeed or 80
			end
			local endMazePos1 = Vector3.new(2674.897216796875, 2075.271240234375, -15479.0595703125)
			local endMazePos2 = Vector3.new(2674.46435546875, 2085.4453125, -15538.548828125)
			if
				Npc
				and Npc:FindFirstChild("HumanoidRootPart")
				and (
						Vector3.new(endMazePos2.X, Npc.HumanoidRootPart.Position.Y, endMazePos2.Z)
						- Npc.HumanoidRootPart.Position
					).Magnitude
					<= 100
			then
				targetFloorPosition = nil
				targetPosition = nil
				targetPosition = Npc.Head.Position + Vector3.new(0, 20, 0)
				if targetPosition then
					controlTower(CFrame.new(targetPosition), Speed)
					CanTween = true
				end
			else
				tweenWithTeleport(endMazePos1, Speed, selected_Offset)
				task.wait(1)
				if (Character.HumanoidRootPart.Position - endMazePos1).Magnitude < 10 then
					tweenWithTeleport(endMazePos2, Speed)
					task.wait(1)
				end
				CanTween = true
			end
		end
	end

	noClip(true)
	local lastDefenseAllocation = 0

	local function selectNightmare(diffChooser)
		local success, err = pcall(function()
			local Button = diffChooser:FindFirstChild("Frame")
				and diffChooser.Frame:FindFirstChild("ScrollingFrame")
				and diffChooser.Frame.ScrollingFrame:FindFirstChild("Nightmare")

			if not Button then
				return
			end

			local types = { "MouseButton1Down", "MouseButton1Up", "MouseButton1Click" }
			for _, t in pairs(types) do
				local signal = Button:FindFirstChild(t) or Button[t]
				if signal and typeof(getconnections) == "function" then
					for _, ncon in pairs(getconnections(signal)) do
						pcall(ncon.Function)
					end
				end
			end
		end)
		if not success then
			warn("selectNightmare error:", err)
		end
	end

	LocalPlayer.PlayerGui.ChildAdded:Connect(function(child)
		if child.Name == "DiffChooser" then
			task.wait(0.1)
			selectNightmare(child)
		end
	end)

	spawn(function()
		while wait(1) do
			if statsFolder and statsFolder.Stats.SkillPoints.Value > 0 then
				local currentDefense = game.ReplicatedStorage["Stats" .. player.Name].Stats.Defense.Value
				local currentStamina = game.ReplicatedStorage["Stats" .. player.Name].Stats.Stamina.Value
				if currentDefense < 450 then
					if tick() - lastDefenseAllocation < 3 then
						continue
					end
					local available = statsFolder.Stats.SkillPoints.Value
					local pointsNeeded = math.min(450 - currentDefense, available)
					if pointsNeeded > 0 then
						player.PlayerGui.Statistics.Main.TopOptions.Base.Input.Text = tostring(pointsNeeded)
						task.wait(0.2)
						game:GetService("ReplicatedStorage").Events.stats:FireServer("Defense", nil, pointsNeeded)
						lastDefenseAllocation = tick()
					end
				elseif currentStamina < 125 then
					local available = statsFolder.Stats.SkillPoints.Value
					local pointsNeeded = math.min(125 - currentStamina, available)
					if pointsNeeded > 0 then
						player.PlayerGui.Statistics.Main.TopOptions.Base.Input.Text = tostring(pointsNeeded)
						task.wait(0.2)
						game:GetService("ReplicatedStorage").Events.stats:FireServer("Stamina", nil, pointsNeeded)
					end
				else
					local available = statsFolder.Stats.SkillPoints.Value
					player.PlayerGui.Statistics.Main.TopOptions.Base.Input.Text = tostring(available)
					task.wait(0.2)
					checkOwnedWeapons()
					if
						OwnedFarmedWeapons["Kraken Blade"]
						or OwnedFarmedWeapons["Hollow's Great Sword"]
						or OwnedFarmedWeapons["Dark Blade"]
					then
						game:GetService("ReplicatedStorage").Events.stats:FireServer("SwordMastery", nil, available)
					elseif OwnedFarmedWeapons["Vrael's Pipe"] then
						game:GetService("ReplicatedStorage").Events.stats:FireServer("Strength", nil, available)
					end
				end
			end
			local diffChooser = LocalPlayer.PlayerGui:FindFirstChild("DiffChooser")
			if diffChooser then
				selectNightmare(diffChooser)
			end
		end
	end)

	function equipattacktool()
		local m1type = "Melee"

		if not Character then
			return m1type
		end
		local humanoid = Character:FindFirstChild("Humanoid")
		if not humanoid then
			return m1type
		end
		if humanoid.Health <= 0 or humanoid:GetState() == Enum.HumanoidStateType.Dead then
			return m1type
		end
		if Character:FindFirstChild("SafeForceField") then
			return m1type
		end
		if not Character:FindFirstChild("HumanoidRootPart") then
			return m1type
		end

		if not getgenv().LastEquipTime then
			getgenv().LastEquipTime = 0
		end
		if tick() - getgenv().LastEquipTime < 0.5 then
			return m1type
		end

		local bestWeapon = nil
		local bestPriority = 0

		for _, tool in pairs(player.Backpack:GetChildren()) do
			if tool:IsA("Tool") then
				for weaponName, priority in pairs(WeaponPriority) do
					local isMatch = false
					if weaponName == "Kraken Blade" then
						isMatch = string.find(tool.Name, "Kraken Blade") ~= nil
					else
						isMatch = (tool.Name == weaponName or string.find(tool.Name, weaponName))
					end

					if isMatch and priority > bestPriority then
						bestWeapon = tool
						bestPriority = priority
					end
				end
			end
		end

		for _, tool in pairs(Character:GetChildren()) do
			if tool:IsA("Tool") then
				for weaponName, priority in pairs(WeaponPriority) do
					local isMatch = false
					if weaponName == "Kraken Blade" then
						isMatch = string.find(tool.Name, "Kraken Blade") ~= nil
					else
						isMatch = (tool.Name == weaponName or string.find(tool.Name, weaponName))
					end

					if isMatch and priority > bestPriority then
						bestWeapon = tool
						bestPriority = priority
					end
				end
			end
		end

		if bestWeapon then
			local alreadyEquipped = false
			for _, tool in pairs(Character:GetChildren()) do
				if tool:IsA("Tool") then
					if string.find(bestWeapon.Name, "Kraken Blade") then
						if string.find(tool.Name, "Kraken Blade") then
							alreadyEquipped = true
							break
						end
					elseif tool.Name == bestWeapon.Name then
						alreadyEquipped = true
						break
					end
				end
			end

			if alreadyEquipped then
				return "Sword"
			else
				pcall(function()
					if bestWeapon.Parent == player.Backpack then
						humanoid:EquipTool(bestWeapon)
						getgenv().LastEquipTime = tick()
					end
				end)
				task.wait(0.1)
				return "Sword"
			end
		end

		local meleetool = player.Backpack:FindFirstChild("Melee") or Character:FindFirstChild("Melee")
		if meleetool then
			if not Character:FindFirstChild("Melee") then
				pcall(function()
					if meleetool.Parent == player.Backpack then
						humanoid:EquipTool(meleetool)
						getgenv().LastEquipTime = tick()
					end
				end)
				task.wait(0.1)
			end
			return m1type
		end

		local meleeTool = player.Backpack:FindFirstChild("Combat", true)
		if meleeTool and meleeTool.Parent then
			pcall(function()
				humanoid:EquipTool(meleeTool.Parent)
				getgenv().LastEquipTime = tick()
			end)
		end

		return m1type
	end

	function GetFloorPositionUnderBoss(npc)
		if not npc or not npc:FindFirstChild("HumanoidRootPart") then
			return nil
		end

		local bossHrp = npc.HumanoidRootPart
		local bossPos = bossHrp.Position

		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Whitelist
		raycastParams.FilterDescendantsInstances = { workspace.Islands }

		local rayDirection = Vector3.new(0, -500, 0)
		local rayResult = workspace:Raycast(bossPos, rayDirection, raycastParams)

		if rayResult then
			return rayResult.Position + Vector3.new(0, 10, 0)
		end

		return nil
	end

	Others.M1Cooldown = Others.M1Cooldown or 0
	Others.M1Combo = Others.M1Combo or 0
	Others.CurrentM1Cooldown = Others.CurrentM1Cooldown or 0
	Others.M1LongCd = Others.M1LongCd or false
	Others.LastM1Time = Others.LastM1Time or 0

	function Buso(value)
		local hashaki = statsFolder.Stats.BusoMastery.Value ~= 0
		if not hashaki then
			return
		end -- Don't try to use buso if player doesn't have haki

		local hasbuso = Character:FindFirstChild("BusoMelee")
		if (not hasbuso and value) or (hasbuso and not value) then
			equipattacktool()
			local args = {
				"Buso",
			}
			game:GetService("ReplicatedStorage"):WaitForChild("Events"):WaitForChild("Haki"):FireServer(unpack(args))
			task.wait()
		end
	end
	function isUnderTrap(position, safetyMargin)
		safetyMargin = safetyMargin or 35

		local env = workspace.Effects:FindFirstChild("Environment") or workspace.Islands
		if not env then
			return false
		end

		for _, trap in ipairs(env:GetChildren()) do
			if trap.Name == "FallingTrap" then
				trap.Parent = workspace.Islands
				local hitbox = trap:FindFirstChild("Hitbox")
				if hitbox and hitbox:IsA("BasePart") then
					hitbox.CanCollide = true
					hitbox.Transparency = 0.85
					local hitboxPos = hitbox.Position
					local hitboxSize = hitbox.Size

					-- Check if position is inside the 3D trigger volume (X, Y, Z)
					local minX = hitboxPos.X - (hitboxSize.X / 2) - safetyMargin
					local maxX = hitboxPos.X + (hitboxSize.X / 2) + safetyMargin
					local minY = hitboxPos.Y - (hitboxSize.Y / 2) - safetyMargin
					local maxY = hitboxPos.Y + (hitboxSize.Y / 2) + safetyMargin
					local minZ = hitboxPos.Z - (hitboxSize.Z / 2) - safetyMargin
					local maxZ = hitboxPos.Z + (hitboxSize.Z / 2) + safetyMargin

					local inVolume = position.X >= minX
						and position.X <= maxX
						and position.Y >= minY
						and position.Y <= maxY
						and position.Z >= minZ
						and position.Z <= maxZ

					if inVolume then
						return true, hitbox
					end
				end
			end
		end

		return false, nil
	end

	function findSafePositionFromTrap(unsafePos, safetyMargin)
		safetyMargin = safetyMargin or 40

		local _, trapHitbox = isUnderTrap(unsafePos, 20)

		if trapHitbox then
			local trapPos = trapHitbox.Position
			local trapSize = trapHitbox.Size

			-- Calculate 3D direction away from trap center
			local awayDir = (unsafePos - trapPos).Unit

			-- Escape distance based on trap's largest dimension
			local escapeDistance = math.max(trapSize.X, trapSize.Y, trapSize.Z) / 2 + safetyMargin + 15
			local safePos = trapPos + (awayDir * escapeDistance)

			-- Verify safe
			if not isUnderTrap(safePos, 20) then
				return safePos
			end
		end

		-- Try 3D offsets (including up/down)
		local offsets = {
			Vector3.new(safetyMargin + 25, 0, 0),
			Vector3.new(-(safetyMargin + 25), 0, 0),
			Vector3.new(0, safetyMargin + 25, 0), -- Up
			Vector3.new(0, -(safetyMargin + 25), 0), -- Down
			Vector3.new(0, 0, safetyMargin + 25),
			Vector3.new(0, 0, -(safetyMargin + 25)),
			-- Diagonal escapes
			Vector3.new(safetyMargin + 20, safetyMargin + 20, 0),
			Vector3.new(-(safetyMargin + 20), safetyMargin + 20, 0),
			Vector3.new(0, safetyMargin + 20, safetyMargin + 20),
			Vector3.new(0, safetyMargin + 20, -(safetyMargin + 20)),
		}

		for _, offset in ipairs(offsets) do
			local testPos = unsafePos + offset
			if not isUnderTrap(testPos, 20) then
				return testPos
			end
		end

		-- Last resort: go straight up
		return unsafePos + Vector3.new(0, 150, 0)
	end

	-- Check if path crosses trap volumes
	function pathCrossesTrap(startPos, endPos, safetyMargin)
		safetyMargin = safetyMargin or 35

		-- Sample MORE points for better detection
		local distance = (endPos - startPos).Magnitude
		local steps = math.max(15, math.ceil(distance / 10)) -- At least 15 samples

		for i = 0, steps do
			local alpha = i / steps
			local checkPos = startPos:Lerp(endPos, alpha)

			local inTrap, trapHitbox = isUnderTrap(checkPos, safetyMargin)
			if inTrap then
				return true, checkPos, trapHitbox
			end
		end

		return false, nil, nil
	end

	-- THIRD FLOOR ROOF DELETION LOOP
	task.spawn(function()
		while task.wait(0.5) do
			pcall(function()
				local targetPosition = Vector3.new(5670.59912109375, 2659.4013671875, -20328.2421875)

				for _, part in pairs(workspace:GetDescendants()) do
					if part:IsA("BasePart") then
						local distance = (part.Position - targetPosition).Magnitude

						if distance < 0.1 then
							part:Destroy()
							warn("Deleted part at target position:", part.Name)
						end
					end
				end
			end)
		end
	end)
	local TypeM1 = "Ground"
	local ragdollTimers = {}

	local function isRagdolled(enemy)
		local humanoid = enemy:FindFirstChild("Humanoid")
		if not humanoid then
			return false
		end

		local ragdolled = humanoid:GetAttribute("isRagdolled")
		return ragdolled
	end
	local RaycastFilterType = Enum.RaycastFilterType

	local function buildRayParams()
		local params = RaycastParams.new()
		params.FilterType = RaycastFilterType.Include
		local filterList = { Character }
		local optionalExcludes = {
			workspace:FindFirstChild("Islands"),
		}
		for _, obj in ipairs(optionalExcludes) do
			if obj then
				table.insert(filterList, obj)
			end
		end
		params.FilterDescendantsInstances = filterList
		params.RespectCanCollide = true
		return params
	end

	local cachedRayParams = nil

	local function getRayParams()
		if not cachedRayParams or not Character or not Character.Parent then
			cachedRayParams = buildRayParams()
		end
		return cachedRayParams
	end

	local function invalidateRayParams()
		cachedRayParams = nil
	end

	local function castRay(origin, direction)
		return workspace:Raycast(origin, direction, getRayParams())
	end

	local function isPathClear(fromPos, toPos)
		local direction = toPos - fromPos
		local dist = direction.Magnitude
		if dist < 0.1 then
			return true, nil
		end
		local result = castRay(fromPos, direction)
		if result and result.Distance < dist then
			return false, result
		end
		return true, nil
	end

	local function isPositionInsidePart(position)
		local params = getRayParams()
		local testDirs = {
			Vector3.new(1, 0, 0),
			Vector3.new(-1, 0, 0),
			Vector3.new(0, 1, 0),
			Vector3.new(0, -1, 0),
			Vector3.new(0, 0, 1),
			Vector3.new(0, 0, -1),
		}
		local closeHits = 0
		for _, dir in ipairs(testDirs) do
			local result = workspace:Raycast(position, dir * 3, params)
			if result and result.Distance < 3 then
				closeHits = closeHits + 1
			end
		end
		if closeHits >= 3 then
			return true
		end
		for i = 1, 5, 2 do
			local r1 = workspace:Raycast(position, testDirs[i] * 5, params)
			local r2 = workspace:Raycast(position, testDirs[i + 1] * 5, params)
			if r1 and r2 and r1.Distance < 5 and r2.Distance < 5 then
				return true
			end
		end
		return false
	end

	local function getValidMovementPosition(fromPos, toPos, margin)
		margin = margin or 2.5
		local clear, hitResult = isPathClear(fromPos, toPos)
		if clear then
			if isPositionInsidePart(toPos) then
				local dir = (toPos - fromPos).Unit
				local pullback = toPos - dir * margin
				if isPositionInsidePart(pullback) then
					return fromPos, true
				end
				return pullback, true
			end
			return toPos, false
		end
		local hitPos = hitResult.Position
		local hitNormal = hitResult.Normal
		local safePos = hitPos + hitNormal * margin
		if isPositionInsidePart(safePos) then
			local dir = (toPos - fromPos).Unit
			safePos = hitPos - dir * margin
			if isPositionInsidePart(safePos) then
				return fromPos, true
			end
		end
		return safePos, true
	end

	local function findSafeAttackPosition(enemyPos, enemyCFrame, preferredOffset, attackRadius)
		attackRadius = attackRadius or 30
		local playerPos = PlayerHumpart.Position
		local preferredPos = (enemyCFrame * CFrame.new(preferredOffset.X, preferredOffset.Y, preferredOffset.Z)).Position
		if not isPositionInsidePart(preferredPos) then
			local clear, _ = isPathClear(playerPos, preferredPos)
			if clear then
				return preferredPos
			end
		end
		local testDistances = { 8, 12, 6, 15, 4 }
		local testAngles = { 0, 45, 90, 135, 180, 225, 270, 315 }
		local yOffsets = { preferredOffset.Y, preferredOffset.Y + 3, preferredOffset.Y - 3, 8, 5, 3, 10 }
		for _, yOff in ipairs(yOffsets) do
			for _, dist in ipairs(testDistances) do
				for _, angle in ipairs(testAngles) do
					local rad = math.rad(angle)
					local testPos = enemyPos + Vector3.new(math.cos(rad) * dist, yOff, math.sin(rad) * dist)
					if not isPositionInsidePart(testPos) then
						local clear, _ = isPathClear(playerPos, testPos)
						if clear and (testPos - enemyPos).Magnitude < attackRadius then
							return testPos
						end
					end
				end
			end
		end
		local retreatDir = (playerPos - enemyPos)
		retreatDir = retreatDir.Magnitude > 0.1 and retreatDir.Unit or Vector3.new(1, 0, 0)
		for _, dist in ipairs({ 10, 15, 20, 8, 5 }) do
			for _, yOff in ipairs(yOffsets) do
				local testPos = enemyPos + retreatDir * dist + Vector3.new(0, yOff, 0)
				if not isPositionInsidePart(testPos) then
					local clear, _ = isPathClear(playerPos, testPos)
					if clear and (testPos - enemyPos).Magnitude < attackRadius then
						return testPos
					end
				end
			end
		end
		return nil
	end

	local function findFallbackPosition(enemyPos)
		local abovePos = Vector3.new(enemyPos.X, selected_Offset or (enemyPos.Y + 50), enemyPos.Z)
		if not isPositionInsidePart(abovePos) then
			return abovePos, "offset"
		end
		if currentTargetPosition and typeof(currentTargetPosition) == "Vector3" then
			local floorPos = currentTargetPosition + Vector3.new(0, 10, 0)
			if not isPositionInsidePart(floorPos) then
				return floorPos, "floor"
			end
		end
		local highPos = Vector3.new(enemyPos.X, enemyPos.Y + 80, enemyPos.Z)
		if not isPositionInsidePart(highPos) then
			return highPos, "high"
		end
		return abovePos, "offset"
	end

	function tweenWithTeleport(pos, speed, offsetY, tweenconfigs)
		if not tweenconfigs then
			tweenconfigs = {}
		end

		if not PlayerHumpart or not Character or not CanFarm or RaiuiAnims then
			return
		end

		if not canTweenNow() then
			return
		end

		print(offsetY)

		local targetPosition = typeof(pos) == "CFrame" and pos.Position or pos

		local isOnFifthFloor = workspace.Islands:FindFirstChild("Impel Base - Floor 5")
		if isOnFifthFloor then
			for partName, partData in pairs(FourthFloor) do
				if (targetPosition - partData.Position).Magnitude < 50 then
					return
				end
			end
		end

		local isOnFourthFloor = workspace.Islands:FindFirstChild("Impel Base - Floor 4")
		if isOnFourthFloor then
			for partName, partData in pairs(ThirdFloor) do
				if (targetPosition - partData.Position).Magnitude < 50 then
					return
				end
			end
		end

		local isOnThirdFloor = workspace.Islands:FindFirstChild("Impel Base - Floor 3")
		if isOnThirdFloor then
			for partName, partData in pairs(SecondFloorPositions) do
				if (targetPosition - partData.Position).Magnitude < 50 then
					return
				end
			end
		end

		local function executeTween(tweenState)
			local isCurrentlyBlocking = Character:FindFirstChild("Blocking")

			if tweenState and not tweenState.active then
				return
			end

			pcall(function()
				if tweenState and not tweenState.active then
					return
				end

				if typeof(pos) == "Vector3" then
					pos = CFrame.new(pos)
				elseif typeof(pos) ~= "CFrame" then
					return
				end

				Others.LastDashTime = 0
				Others.StopShadowBan = false
				ValuesTable.shadowbanbypass = false
				local targetCFrame = pos
				local startPos = PlayerHumpart.Position

				if (startPos - targetCFrame.Position).Magnitude < 5 then
					ValuesTable.shadowbanbypass = false
					return
				end

				local destPos = typeof(pos) == "CFrame" and pos.Position or pos
				local destInTrap = isUnderTrap(destPos, 35)

				if destInTrap then
					local safeDest = findSafePositionFromTrap(destPos, 40)
					if safeDest then
						destPos = safeDest
						finalCFrame = CFrame.new(safeDest)
						downPos = downPos and CFrame.new(safeDest) or nil
					else
						ValuesTable.shadowbanbypass = false
						return
					end
				end

				local pathHasTrap, trapCrossPos, trapHitbox = pathCrossesTrap(startPos, destPos, 35)

				if pathHasTrap then
					local safeDest = findSafePositionFromTrap(destPos, 40)
					if not safeDest or isUnderTrap(safeDest, 20) then
						ValuesTable.shadowbanbypass = false
						return
					end
					destPos = safeDest
					finalCFrame = CFrame.new(safeDest)
					if downPos then
						downPos = CFrame.new(safeDest)
					end
				end

				safeTarget = targetCFrame.Position

				local finalCFrame = CFrame.new(safeTarget)
				local originalTargetCFrame = CFrame.new(targetCFrame.Position)

				local y = offsetY or targetCFrame.Position.Y
				local isBlocking = Character:FindFirstChild("Blocking")

				local actuallyNeedsOffset = offsetY ~= nil

				if
					actuallyNeedsOffset
					and math.abs(startPos.Y - safeTarget.Y) < 40
					and math.abs(startPos.Y - y) < 40
				then
					actuallyNeedsOffset = false
				end

				local skipOffset = false
				if actuallyNeedsOffset then
					local yDiff = math.abs(startPos.Y - safeTarget.Y)
					local directDistance = (startPos - safeTarget).Magnitude
					-- Only skip offset if Y difference is small AND direct path is clear
					if directDistance < 100 and yDiff < 40 then
						local pathClear, _ = isPathClear(startPos, safeTarget)
						local insidePart = isPositionInsidePart(safeTarget)
						if pathClear and not insidePart then
							skipOffset = true
						end
					end
				end

				local upPos = (actuallyNeedsOffset and not skipOffset) and CFrame.new(startPos.X, y, startPos.Z)
				local midPos = (actuallyNeedsOffset and not skipOffset) and CFrame.new(safeTarget.X, y, safeTarget.Z)
					or finalCFrame
				local downPos = (not skipOffset) and originalTargetCFrame

				local function effSpeed()
					local spb = Character:GetAttribute("SpeedBypass") or 0
					local baseSpeed = speed or 80
					local finalSpeed = math.max(spb, baseSpeed) - 10
					if spb > 150 then
						return (spb * 0.8) + 50
					else
						return speed
					end
				end

				local RunService = Services.RunService
				Others.TweenCd = true

				local function runPhase(toPos)
					if tweenState and not tweenState.active then
						return false
					end

					local startCF = PlayerHumpart.CFrame
					local targetCF = toPos
					local dist = (startCF.Position - targetCF.Position).Magnitude

					if dist <= 1.5 then
						return true
					end

					local isOnFifthFloor = workspace.Islands:FindFirstChild("Impel Base - Floor 5")
					if isOnFifthFloor then
						for partName, partData in pairs(FourthFloor) do
							if (targetCF.Position - partData.Position).Magnitude < 50 then
								return false
							end
						end
					end

					local isOnFourthFloor = workspace.Islands:FindFirstChild("Impel Base - Floor 4")
					if isOnFourthFloor then
						for partName, partData in pairs(ThirdFloor) do
							if (targetCF.Position - partData.Position).Magnitude < 50 then
								return false
							end
						end
					end

					local isOnThirdFloor = workspace.Islands:FindFirstChild("Impel Base - Floor 3")
					if isOnThirdFloor then
						for partName, partData in pairs(SecondFloorPositions) do
							if (targetCF.Position - partData.Position).Magnitude < 50 then
								return false
							end
						end
					end

					if workspace.CurrentCamera.CameraType == Enum.CameraType.Scriptable then
						return
					end

					local startTime = tick()
					local pausedTime = 0
					local lastUpdateTime = tick()
					local abort = false
					local speedChanged = false
					local stuckStartTime = nil
					local lastMovePos = startCF.Position
					local totalStuckTime = 0
					local lastStuckCheck = tick()

					local spbConn
					if Character:GetAttribute("SpeedBypass") then
						spbConn = Character:GetAttributeChangedSignal("SpeedBypass"):Connect(function()
							speedChanged = true
						end)
					end

					local moveConn = RunService.Heartbeat:Connect(function(dt)
						if tweenState and not tweenState.active then
							abort = true
							return
						end

						if
							(
								workspace.Islands:FindFirstChild("Impel Base - Floor 3")
								and not workspace.Islands:FindFirstChild("Impel Base - Floor 4")
								and targetCF.Position.Y < 2200
							)
							or (
								workspace.Islands:FindFirstChild("Impel Base - Floor 2")
								and not workspace.Islands:FindFirstChild("Impel Base - Floor 3")
								and targetCF.Position.Y < 2200
							)
						then
							abort = true
							return
						end

						if not PlayerHumpart or not Character then
							abort = true
							return
						end

						if
							not workspace:GetAttribute("HandCuffed")
							and (pos.Position - Vector3.new(5866, 30, -10227)).Magnitude > 200
						then
							abort = true
							return
						end

						local acType = checkAnticheatNotifications()
						if acType then
							local currentPos = PlayerHumpart.Position
							local safeY = y or selected_Offset or currentPos.Y
							local safePos = Vector3.new(currentPos.X, safeY, currentPos.Z)
							task.wait(0.5)

							if acType == "noclip" then
								pcall(function()
									instatp(safePos)
								end)
								startCF = PlayerHumpart.CFrame
								dist = (startCF.Position - targetCF.Position).Magnitude
								startTime = tick()
								pausedTime = 0
								lastUpdateTime = tick()
							elseif acType == "tpcheck" or acType == "flycheck" then
								pcall(function()
									instatp(safePos)
								end)
								ValuesTable.shadowbanbypass = false
								task.wait(3)
								ValuesTable.shadowbanbypass = false
								startCF = PlayerHumpart.CFrame
								dist = (startCF.Position - targetCF.Position).Magnitude
								startTime = tick()
								pausedTime = 0
								lastUpdateTime = tick()
							elseif acType == "velocity" or acType == "grounded" then
								Facemouse()
								startCF = PlayerHumpart.CFrame
								dist = (startCF.Position - targetCF.Position).Magnitude
								startTime = tick()
								pausedTime = 0
								lastUpdateTime = tick()
							elseif acType == "threshold" then
								abort = true
								ValuesTable.shadowbanbypass = false
								MovementSystem:Unlock()
								return
							else
								startCF = PlayerHumpart.CFrame
								dist = (startCF.Position - targetCF.Position).Magnitude
								startTime = tick()
								pausedTime = 0
								lastUpdateTime = tick()
							end
							task.wait(0.5)
							stopblocking = false
						end

						Others.StopShadowBan = false
						ValuesTable.shadowbanbypass = false

						if not CanFarm then
							abort = false
							ValuesTable.shadowbanbypass = false
							return
						end

						if not canTweenNow() then
							abort = false
							ValuesTable.shadowbanbypass = false
							return
						end

						if Character.Parent ~= workspace.PlayerCharacters then
							abort = true
							ValuesTable.shadowbanbypass = false
							return
						end

						if speedChanged or RaiuiAnims then
							abort = true
							return
						end

						if tweenconfigs.ThirdFloorNotificationPosition then
							local newPos = getNotificationPosition()
							if newPos and typeof(newPos) == "Vector3" then
								local newTargetCF = CFrame.new(newPos.X, y, newPos.Z)
								if (newTargetCF.Position - targetCF.Position).Magnitude > 5 then
									targetCF = newTargetCF
									downPos = CFrame.new(newPos)
									startCF = PlayerHumpart.CFrame
									dist = (startCF.Position - targetCF.Position).Magnitude
									startTime = tick()
									pausedTime = 0
									lastUpdateTime = tick()
									stuckCounter = 0
								end
							end
						end

						local currentSpeed = effSpeed()
						local totalDuration = dist / currentSpeed

						local actualElapsed = (tick() - startTime) - pausedTime
						local alpha = math.min(actualElapsed / totalDuration, 1)

						local currentPos = PlayerHumpart.Position
						local newCF = startCF:Lerp(targetCF, alpha)

						local frameTime = tick() - lastUpdateTime
						local maxDistanceThisFrame = currentSpeed * frameTime

						local moveDistance = (newCF.Position - currentPos).Magnitude
						if moveDistance > maxDistanceThisFrame * 2 then
							local safeMoveDirection = (newCF.Position - currentPos).Unit
							local safePosition = currentPos + (safeMoveDirection * maxDistanceThisFrame)
							newCF = CFrame.new(safePosition)

							local actualProgress = maxDistanceThisFrame / dist
							local timeForProgress = actualProgress * totalDuration
							startTime = tick() - (timeForProgress + pausedTime)
						end

						local desiredPos = newCF.Position
						local validPos, wasBlocked = getValidMovementPosition(currentPos, desiredPos, 2.5)

						if wasBlocked then
							newCF = CFrame.new(validPos)
							if (validPos - lastMovePos).Magnitude < 0.5 then
								if not stuckStartTime then
									stuckStartTime = tick()
								end
								local stuckDuration = tick() - stuckStartTime
								totalStuckTime = totalStuckTime + (tick() - lastStuckCheck)
								lastStuckCheck = tick()

								if totalStuckTime >= 1.5 then
									abort = true
									pcall(function()
										Facemouse()
										task.wait(0.3)
										PlayerHumpart.CFrame = targetCF
									end)
									return
								end

								if stuckDuration >= 1 then
									stuckStartTime = nil
									local yOffset = offsetY or selected_Offset or (currentPos.Y + 200)
									local overWallPos = Vector3.new(currentPos.X, yOffset, currentPos.Z)
									pcall(function()
										Facemouse()
										task.wait(0.3)
										PlayerHumpart.CFrame = CFrame.new(overWallPos)
									end)
									task.wait(0.3)
									local targetXZ = Vector3.new(targetCF.Position.X, yOffset, targetCF.Position.Z)
									startCF = PlayerHumpart.CFrame
									targetCF = CFrame.new(targetXZ)
									dist = (startCF.Position - targetCF.Position).Magnitude
									startTime = tick()
									pausedTime = 0
									lastUpdateTime = tick()
									lastMovePos = PlayerHumpart.Position
									return
								end
							else
								stuckStartTime = nil
								lastStuckCheck = tick()
							end
						end

						lastMovePos = PlayerHumpart.Position
						PlayerHumpart.CFrame = newCF
						lastUpdateTime = tick()

						if alpha >= 1 then
							local finalValid, finalBlocked =
								getValidMovementPosition(currentPos, targetCF.Position, 2.5)
							if finalBlocked then
								PlayerHumpart.CFrame = CFrame.new(finalValid)
							else
								PlayerHumpart.CFrame = targetCF
							end
							abort = true
						elseif (PlayerHumpart.Position - targetCF.Position).Magnitude <= 1.5 then
							PlayerHumpart.CFrame = targetCF
							abort = true
						end
					end)

					while not abort and (not tweenState or tweenState.active) do
						task.wait()
					end

					if spbConn then
						spbConn:Disconnect()
					end
					if moveConn then
						moveConn:Disconnect()
					end

					if tweenState and not tweenState.active then
						return false
					end

					if speedChanged then
						return runPhase(toPos)
					end

					local finalDist = (PlayerHumpart.Position - targetCF.Position).Magnitude

					if finalDist > 25 then
						return false
					end

					return true
				end

				local upYDiff = upPos and math.abs(PlayerHumpart.Position.Y - upPos.Position.Y) or 0
				if upPos and upYDiff > 10 then
					if tweenState and not tweenState.active then
						return
					end

					local acCheck = checkAnticheatNotifications()
					if acCheck == "threshold" then
						Others.TweenCd = false
						ValuesTable.shadowbanbypass = false
						MovementSystem:Unlock()
						return
					end

					if acCheck then
						repeat
							task.wait(0.1)
							acCheck = checkAnticheatNotifications()
						until not acCheck or acCheck == "threshold"
						if acCheck == "threshold" then
							Others.TweenCd = false
							ValuesTable.shadowbanbypass = false
							MovementSystem:Unlock()
							return
						end
					end
					Facemouse()
					task.wait(0.4)
					PlayerHumpart.CFrame = upPos
					task.wait(0.5)

					local yDiff = math.abs(PlayerHumpart.Position.Y - upPos.Position.Y)
					if yDiff > 50 then
						Facemouse()
						PlayerHumpart.CFrame = upPos
						task.wait(0.5)
						yDiff = math.abs(PlayerHumpart.Position.Y - upPos.Position.Y)
						if yDiff > 50 then
							Others.TweenCd = false
							ValuesTable.shadowbanbypass = false
							return
						end
					end
				end

				if midPos then
					if tweenState and not tweenState.active then
						return
					end

					local phaseSuccess = runPhase(midPos)

					if not phaseSuccess then
						Others.TweenCd = false
						ValuesTable.shadowbanbypass = false
						return
					end
				end
				local downYDiff = downPos and math.abs(PlayerHumpart.Position.Y - downPos.Position.Y) or 0
				if downPos and downYDiff > 10 then
					if tweenState and not tweenState.active then
						return
					end

					local acCheck = checkAnticheatNotifications()
					if acCheck == "threshold" then
						Others.TweenCd = false
						ValuesTable.shadowbanbypass = false
						MovementSystem:Unlock()
						return
					end

					if acCheck then
						repeat
							task.wait(0.1)
							acCheck = checkAnticheatNotifications()
						until not acCheck or acCheck == "threshold"
						if acCheck == "threshold" then
							Others.TweenCd = false
							ValuesTable.shadowbanbypass = false
							MovementSystem:Unlock()
							return
						end
					end

					-- CHECK: Did mid-phase actually reach the target X/Z?
					local currentPos = PlayerHumpart.Position
					local targetX = downPos.Position.X
					local targetZ = downPos.Position.Z
					local xzDistance = math.sqrt((currentPos.X - targetX) ^ 2 + (currentPos.Z - targetZ) ^ 2)

					if xzDistance > 15 then
						local currentY = currentPos.Y
						local correctXZatOffset = CFrame.new(targetX, currentY, targetZ)

						local xzPhaseSuccess = runPhase(correctXZatOffset)

						if not xzPhaseSuccess then
							Facemouse()
							task.wait(0.3)
							PlayerHumpart.CFrame = correctXZatOffset
							task.wait(0.5)
						end
					end

					Facemouse()
					task.wait(0.4)
					PlayerHumpart.CFrame = downPos
					task.wait(0.5)

					local yDiff = math.abs(PlayerHumpart.Position.Y - downPos.Position.Y)
					if yDiff > 50 then
						Facemouse()
						PlayerHumpart.CFrame = downPos
						task.wait(0.5)
						yDiff = math.abs(PlayerHumpart.Position.Y - downPos.Position.Y)
						if yDiff > 50 then
							Others.TweenCd = false
							ValuesTable.shadowbanbypass = false
							return
						end
					end
					task.wait(0.3)
				end
				Others.TweenCd = false
				ValuesTable.shadowbanbypass = false
			end)
		end

		if tweenconfigs.inspawn then
			local targetPos = typeof(pos) == "CFrame" and pos.Position or pos

			if MovementSystem.inSpawnTween and MovementSystem.inSpawnTween.active and MovementSystem.inSpawnTarget then
				local distanceToCurrentTarget = (targetPos - MovementSystem.inSpawnTarget).Magnitude
				if distanceToCurrentTarget < 10 then
					return
				end
			end

			MovementSystem:CancelInSpawn()

			local tweenState = { active = true }
			MovementSystem.inSpawnTween = tweenState
			MovementSystem.inSpawnTarget = targetPos
			MovementSystem.tweenState = tweenState

			task.spawn(function()
				executeTween(tweenState)
				if MovementSystem.inSpawnTarget == targetPos then
					MovementSystem.inSpawnTarget = nil
				end
			end)

			return
		end

		MovementSystem:CancelInSpawn()

		local tweenState = { active = true }
		MovementSystem.tweenState = tweenState
		executeTween(tweenState)
	end

	function m1Attack(enemy, safeHeightOffset, attackRadius, offset3D, Type)
		safeHeightOffset = safeHeightOffset or selected_Offset or 50
		attackRadius = attackRadius or 30
		offset3D = offset3D or Vector3.new(0, 5, 0)
		local m1type = equipattacktool()
		Buso(true)

		pcall(function()
			Character.Humanoid.PlatformStand = true
		end)

		if not enemy or not enemy:FindFirstChild("HumanoidRootPart") then
			return false
		end

		if enemy:GetAttribute("RealName") == "Cupid Queen" then
			safeHeightOffset = selected_Offset
		end

		if MovementSystem:IsLocked() or EloAnims then
			return false
		end

		local enemyHumPart = enemy:FindFirstChild("HumanoidRootPart")
		local enemyHumanoid = enemy:FindFirstChild("Humanoid")

		if not enemyHumanoid or enemyHumanoid.Health <= 0 then
			return false
		end

		if not Character or not PlayerHumpart or not CanFarm then
			return false
		end

		local enemyId = enemy.Name .. tostring(enemy:GetDebugId())
		local isCurrentlyRagdolled = isRagdolled(enemy)

		if isCurrentlyRagdolled then
			if not ragdollTimers[enemyId] then
				ragdollTimers[enemyId] = tick()
			end
			local ragdollDuration = tick() - ragdollTimers[enemyId]
			if ragdollDuration > 4 then
				offset3D = Vector3.new(0, 0, 0)
			end
		else
			ragdollTimers[enemyId] = nil
		end

		local playerUnderTrap = isUnderTrap(PlayerHumpart.Position, 15)
		if playerUnderTrap then
			local safePos = findSafePositionFromTrap(PlayerHumpart.Position)
			tweenWithTeleport(safePos, Speed)
			task.wait(0.5)
			return false
		end

		MovementSystem:CancelInSpawn()

		if Type then
			TypeM1 = "Ground"
		end

		local now = os.clock()

		if not Character:FindFirstChild("Stun") and not RaiuiAnims then
			local enemyPos = enemyHumPart.Position
			local enemyCFrame = enemyHumPart.CFrame
			local currentPos = PlayerHumpart.Position
			local targetPos = (enemyCFrame * CFrame.new(offset3D.X, offset3D.Y, offset3D.Z)).Position
			if isUnderTrap(targetPos, 10) then
				targetPos = findSafePositionFromTrap(targetPos)
			end
			local finalPos = targetPos
			if isUnderTrap(finalPos, 10) then
				finalPos = findSafePositionFromTrap(finalPos)
			end
			if checkAnticheatNotifications() then
				repeat
					task.wait(0.1)
				until not checkAnticheatNotifications()
				return false
			end
			if
				finalPos.Y > 2435
				and currentTargetPosition == Vector3.new(5654.6669921875, 2481.71728515625, -20514.548828125)
			then
				finalPos = enemyPos + Vector3.new(0, 8, 0)
			end
			if finalPos.X ~= finalPos.X or finalPos.Y ~= finalPos.Y or finalPos.Z ~= finalPos.Z then
				finalPos = enemyPos + Vector3.new(0, 8, 0)
			end

			local positionIsInsidePart = isPositionInsidePart(finalPos)
			local pathIsBlocked = false
			if not positionIsInsidePart then
				local clear, _ = isPathClear(currentPos, finalPos)
				pathIsBlocked = not clear
			end

			if positionIsInsidePart or pathIsBlocked then
				local safeAttackPos = findSafeAttackPosition(enemyPos, enemyCFrame, offset3D, attackRadius)
				if safeAttackPos then
					finalPos = safeAttackPos
				else
					if currentTargetPosition and typeof(currentTargetPosition) == "Vector3" then
						instatp(CFrame.new(currentTargetPosition))
					end
					task.wait(2)
					return false
				end
			end

			local finalCFrame = CFrame.new(finalPos, enemyPos)
			instatp(finalCFrame)
		elseif Character:FindFirstChild("Stun") then
			local safePos = enemyHumPart.Position + Vector3.new(0, safeHeightOffset, 0)
			if isUnderTrap(safePos, 15) then
				safePos = findSafePositionFromTrap(safePos)
			end
			if isPositionInsidePart(safePos) then
				if currentTargetPosition and typeof(currentTargetPosition) == "Vector3" then
					instatp(CFrame.new(currentTargetPosition))
					task.wait(2)
					return false
				end
			end
			if checkAnticheatNotifications() then
				repeat
					task.wait(0.1)
				until not checkAnticheatNotifications()
				return false
			end
			instatp(safePos)
			return false
		elseif RaiuiAnims then
			local safePos = Vector3.new(enemyHumPart.Position.X, selected_Offset - 400, enemyHumPart.Position.Z)
			if isPositionInsidePart(safePos) then
				if currentTargetPosition and typeof(currentTargetPosition) == "Vector3" then
					instatp(CFrame.new(currentTargetPosition))
					task.wait(2)
					return false
				end
			end

			if PlayerHumpart.Position.Y < selected_Offset - 350 then
				instatp(safePos)
			end

			local waitStart = tick()
			while RaiuiAnims and (tick() - waitStart) < RAIUI_ANIM_TIMEOUT do
				task.wait(0.1)
			end

			if not RaiuiAnims and enemyHumPart and enemyHumPart.Parent then
				task.wait(0.5)

				local enemyPos = enemyHumPart.Position
				local enemyCFrame = enemyHumPart.CFrame
				local targetPos = (enemyCFrame * CFrame.new(offset3D.X, offset3D.Y, offset3D.Z)).Position
				if isUnderTrap(targetPos, 10) then
					targetPos = findSafePositionFromTrap(targetPos)
				end

				local needsFallback = false
				if isPositionInsidePart(targetPos) then
					local safeAttackPos = findSafeAttackPosition(enemyPos, enemyCFrame, offset3D, attackRadius)
					if safeAttackPos then
						targetPos = safeAttackPos
					else
						needsFallback = true
					end
				else
					local clear, _ = isPathClear(PlayerHumpart.Position, targetPos)
					if not clear then
						local safeAttackPos = findSafeAttackPosition(enemyPos, enemyCFrame, offset3D, attackRadius)
						if safeAttackPos then
							targetPos = safeAttackPos
						else
							needsFallback = true
						end
					end
				end

				if needsFallback then
					if currentTargetPosition and typeof(currentTargetPosition) == "Vector3" then
						instatp(CFrame.new(currentTargetPosition))
					end
					task.wait(2)
					return false
				end

				local finalCFrame = CFrame.new(targetPos, enemyPos)
				instatp(finalCFrame)
				task.wait(0.2)
			end
		end

		if now - Others.M1Cooldown < Others.CurrentM1Cooldown then
			return false
		end

		Others.M1Cooldown = now
		local hitTable = {}
		local count = 0

		if enemyHumPart and (PlayerHumpart.Position - enemyHumPart.Position).Magnitude < attackRadius then
			table.insert(hitTable, enemyHumPart)
			count = count + 1
		end

		for _, v in ipairs(workspace.NPCs:GetChildren()) do
			if v ~= enemy then
				local h = v:FindFirstChild("Humanoid")
				local r = v:FindFirstChild("HumanoidRootPart")
				if h and r and h.Health > 0 and (PlayerHumpart.Position - r.Position).Magnitude < attackRadius then
					count = count + 1
					table.insert(hitTable, r)
				end
			end
		end

		if enemy:GetAttribute("HPScaled") and enemy:FindFirstChild("Blocking") then
			return false
		end
		if count == 0 then
			return false
		end

		if now - Others.LastM1Time > 2 then
			Others.M1Combo = 0
			Others.M1LongCd = false
		end

		Others.M1Combo = Others.M1Combo + 1
		Others.LastM1Time = now

		local events = Services.ReplicatedStorage:WaitForChild("Events")
		pcall(function()
			events.CombatRegister:InvokeServer({
				"swingsfx",
				m1type,
				Others.M1Combo,
				TypeM1,
				false,
				Services.ReplicatedStorage.CombatAnimations.Melee.Punch1,
				2,
				2,
			})
			events.CombatRegister:InvokeServer({
				"damage",
				hitTable,
				m1type,
				{ Others.M1Combo, TypeM1, m1type },
				true,
				CFrame.new(),
				aircombo = TypeM1,
			})
		end)

		if Others.M1Combo >= 5 then
			Others.M1Combo = 0
			Others.M1LongCd = true
			Others.CurrentM1Cooldown = 1.5
		else
			Others.CurrentM1Cooldown = 0.4
		end

		return true
	end

	function m1AttackSimple(enemy, attackRadius)
		attackRadius = attackRadius or 30
		local m1type = equipattacktool()
		Buso(true)

		if not enemy or not enemy:FindFirstChild("HumanoidRootPart") then
			return false
		end

		local enemyHumPart = enemy:FindFirstChild("HumanoidRootPart")
		local enemyHumanoid = enemy:FindFirstChild("Humanoid")

		if not enemyHumanoid or enemyHumanoid.Health <= 0 then
			return false
		end

		if not Character or not PlayerHumpart or not CanFarm then
			return false
		end

		-- Distance check only
		if (PlayerHumpart.Position - enemyHumPart.Position).Magnitude > attackRadius then
			return false
		end

		local playerUnderTrap = isUnderTrap(PlayerHumpart.Position, 15)
		if playerUnderTrap then
			local safePos = findSafePositionFromTrap(PlayerHumpart.Position)

			tweenWithTeleport(safePos, Speed)

			task.wait(0.5)
			return false
		end

		local now = os.clock()

		-- M1 Cooldown check
		if now - Others.M1Cooldown < Others.CurrentM1Cooldown then
			return false
		end

		Others.M1Cooldown = now
		local hitTable = {}
		local count = 0

		-- Build hit table
		table.insert(hitTable, enemyHumPart)
		count = count + 1

		for _, v in ipairs(workspace.NPCs:GetChildren()) do
			if v ~= enemy then
				local h = v:FindFirstChild("Humanoid")
				local r = v:FindFirstChild("HumanoidRootPart")
				if h and r and h.Health > 0 and (PlayerHumpart.Position - r.Position).Magnitude < attackRadius then
					count = count + 1
					table.insert(hitTable, r)
				end
			end
		end

		if count == 0 then
			return false
		end

		-- Reset combo if too long between M1s
		if now - Others.LastM1Time > 2 then
			Others.M1Combo = 0
			Others.M1LongCd = false
		end

		Others.M1Combo = Others.M1Combo + 1
		Others.LastM1Time = now

		-- Execute M1
		local events = Services.ReplicatedStorage:WaitForChild("Events")
		pcall(function()
			events.CombatRegister:InvokeServer({
				"swingsfx",
				m1type,
				Others.M1Combo,
				TypeM1,
				false,
				Services.ReplicatedStorage.CombatAnimations.Melee.Punch1,
				2,
				2,
			})
			events.CombatRegister:InvokeServer({
				"damage",
				hitTable,
				m1type,
				{ Others.M1Combo, TypeM1, m1type },
				true,
				CFrame.new(),
				aircombo = TypeM1,
			})
		end)

		if Others.M1Combo >= 5 then
			Others.M1Combo = 0
			Others.M1LongCd = true
			Others.CurrentM1Cooldown = 1.5
		else
			Others.CurrentM1Cooldown = 0.5
		end

		return true
	end

	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local isGliding = false

	function Facemouse()
		for i = 1, 2 do
			task.wait(0.1)
			local args = {
				false,
			}
			game:GetService("ReplicatedStorage")
				:WaitForChild("Events")
				:WaitForChild("faceMouse")
				:FireServer(unpack(args))
		end
	end

	task.spawn(function()
		while true do
			local nearGround = false
			pcall(function()
				if PlayerHumpart then
					local rayParams = RaycastParams.new()
					rayParams.FilterType = Enum.RaycastFilterType.Blacklist
					rayParams.FilterDescendantsInstances = { Character, workspace:FindFirstChild("Effects") }
					local rayResult = workspace:Raycast(PlayerHumpart.Position, Vector3.new(0, -15, 0), rayParams)
					if rayResult then
						nearGround = true
					end
				end
			end)

			local hum = Character and Character:FindFirstChild("Humanoid")
			if
				hum
				and hum.FloorMaterial == Enum.Material.Air
				and Services.ReplicatedStorage:FindFirstChild("Stats" .. player.Name).Stamina.Value > 50
			then
				local args = { 1, "dash" }
				game:GetService("ReplicatedStorage")
					:WaitForChild("Events")
					:WaitForChild("takestam")
					:FireServer(unpack(args))
			elseif
				hum
				and hum.FloorMaterial == Enum.Material.Air
				and Services.ReplicatedStorage:FindFirstChild("Stats" .. player.Name).Stamina.Value < 50
				and not nearGround
			then
				Facemouse()
			end
			task.wait(1.4)
		end
	end)
	local bv
	spawn(function()
		while task.wait(0.5) do
			pcall(function()
				if not PlayerHumpart:FindFirstChild("BodyVelocity") then
					bv = Instance.new("BodyVelocity")
					bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
					bv.P = 5000
					bv.Velocity = Vector3.new(0, 0, 0)
					bv.Parent = PlayerHumpart
				end
				if player.PlayerScripts.Ragdolls:FindFirstChild("Ragdoll_Client") then
					player.PlayerScripts.Ragdolls.Ragdoll_Client:Destroy()
				end
			end)
		end
	end)

	local SkillCooldowns = {}
	local LaserPulsarChargedAt = 0
	local LaserPulsarLastRelease = 0

	do
		local changedWalkspeed = false
		local humanoid = Character:WaitForChild("Humanoid")
		local hrp = PlayerHumpart
		local GuiUnloaded = false

		local function tapKey(keyCode, downTime)
			local vim = Instance.new("VirtualInputManager")
			vim:SendKeyEvent(true, keyCode, false, game)
			task.wait(downTime or 0.1)
			vim:SendKeyEvent(false, keyCode, false, game)
			vim:Destroy()
		end

		local function stopShadowBanBypass()
			if not changedWalkspeed and humanoid and humanoid.WalkSpeed == 0 then
				changedWalkspeed = true
				humanoid.WalkSpeed = 16
			end
			task.wait()
		end

		task.spawn(function()
			local keys = {
				Enum.KeyCode.W,
				Enum.KeyCode.A,
				Enum.KeyCode.S,
				Enum.KeyCode.D,
			}
			while true do
				if not ValuesTable.shadowbanbypass or Others.StopShadowBan or not Character or not PlayerHumpart then
					stopShadowBanBypass()
					task.wait()
					continue
				end
				pcall(function()
					for _, key in ipairs(keys) do
						if not ValuesTable.shadowbanbypass then
							break
						end
						tapKey(key, 0.08)
						task.wait(0.05)
					end
				end)
				task.wait(0.2)
			end
		end)

		task.spawn(function()
			while task.wait() do
				if not ValuesTable.shadowbanbypass or Others.StopShadowBan or not Character or not PlayerHumpart then
					stopShadowBanBypass()
					continue
				end
				changedWalkspeed = false
				humanoid.WalkSpeed = 0
			end
		end)
	end

	local trackedNotification = nil
	local lastReturnedPosition = nil
	local lastCalculatedPosition = nil
	local lastCalculationTime = 0
	local CALCULATION_COOLDOWN = 0.5

	function getNotificationPosition(value)
		local now = tick()
		if now - lastCalculationTime < CALCULATION_COOLDOWN and lastCalculatedPosition then
			return lastCalculatedPosition
		end

		lastCalculationTime = now

		if trackedNotification and trackedNotification.Parent then
			local pos = trackedNotification.WorldPosition
			if (pos - Vector3.new(4932.1904296875, 2380.0673828125, -20928.67578125)).Magnitude < 5 then
				local finalPos = Vector3.new(4983.416015625, 2306.330078125, -20861.43359375)

				if value and (not lastReturnedPosition or (lastReturnedPosition - finalPos).Magnitude > 5) then
					lastReturnedPosition = finalPos
					task.wait(2)
				end

				lastCalculatedPosition = finalPos
				return finalPos
			end

			if value and (not lastReturnedPosition or (lastReturnedPosition - pos).Magnitude > 5) then
				lastReturnedPosition = pos
				task.wait(2)
			end

			lastCalculatedPosition = pos
			return pos
		end

		local allNotifications = {}
		for _, descendant in pairs(workspace:GetDescendants()) do
			if descendant:IsA("Sound") and descendant.Name == "NotificationTick" then
				local attachment = descendant.Parent
				if attachment and attachment:IsA("Attachment") then
					table.insert(allNotifications, attachment)
				end
			end
		end

		if #allNotifications > 0 then
			local nearestAttachment = nil
			local nearestDistance = math.huge
			for _, attachment in pairs(allNotifications) do
				local distance = (attachment.WorldPosition - PlayerHumpart.Position).Magnitude
				if distance < nearestDistance then
					nearestDistance = distance
					nearestAttachment = attachment
				end
			end

			if nearestAttachment then
				trackedNotification = nearestAttachment
				local pos = nearestAttachment.WorldPosition
				if (pos - Vector3.new(4932.1904296875, 2380.0673828125, -20928.67578125)).Magnitude < 5 then
					local finalPos = Vector3.new(4983.416015625, 2306.330078125, -20861.43359375)

					-- Check if position changed
					if value and (not lastReturnedPosition or (lastReturnedPosition - finalPos).Magnitude > 5) then
						lastReturnedPosition = finalPos
						task.wait(2)
					end

					lastCalculatedPosition = finalPos
					return finalPos
				end

				-- Check if position changed
				if value and (not lastReturnedPosition or (lastReturnedPosition - pos).Magnitude > 5) then
					lastReturnedPosition = pos
					task.wait(2)
				end

				lastCalculatedPosition = pos
				return pos
			end
		end

		trackedNotification = nil

		local barriers = workspace.Islands["Impel Base - Floor 3"]:FindFirstChild("Barriers")
		local interactables = workspace.Islands["Impel Base - Floor 3"]:FindFirstChild("Interactables")

		if
			barriers
			and barriers:FindFirstChild("FirstBarrier")
			and barriers.FirstBarrier.Transparency ~= 1
			and not RAIUIBOSSSPAWNED
		then
			local finalPos = ThirdFloor["Part1"].Position
			if value and (not lastReturnedPosition or (lastReturnedPosition - finalPos).Magnitude > 5) then
				lastReturnedPosition = finalPos
				task.wait(2)
			end
			lastCalculatedPosition = finalPos
			return finalPos
		elseif
			barriers
			and barriers:FindFirstChild("GateBarrier")
			and barriers.GateBarrier.Transparency ~= 1
			and not RAIUIBOSSSPAWNED
		then
			local finalPos = ThirdFloor["Part6"].Position
			if value and (not lastReturnedPosition or (lastReturnedPosition - finalPos).Magnitude > 5) then
				lastReturnedPosition = finalPos
				task.wait(2)
			end
			lastCalculatedPosition = finalPos
			return finalPos
		elseif
			barriers
			and barriers:FindFirstChild("MiniBossEntranceBarrier")
			and barriers.MiniBossEntranceBarrier.Transparency ~= 1
			and not RAIUIBOSSSPAWNED
		then
			local finalPos = ThirdFloor["Part8"].Position
			if value and (not lastReturnedPosition or (lastReturnedPosition - finalPos).Magnitude > 5) then
				lastReturnedPosition = finalPos
				task.wait(2)
			end
			lastCalculatedPosition = finalPos
			return finalPos
		elseif
			barriers
			and barriers:FindFirstChild("MiniBossExitBarrier")
			and barriers.MiniBossExitBarrier.Transparency ~= 1
			and not RAIUIBOSSSPAWNED
		then
			local finalPos = ThirdFloor["Part9"].Position
			if value and (not lastReturnedPosition or (lastReturnedPosition - finalPos).Magnitude > 5) then
				lastReturnedPosition = finalPos
				task.wait(2)
			end
			lastCalculatedPosition = finalPos
			return finalPos
		elseif
			barriers
			and barriers:FindFirstChild("ThirdStageBarrier1")
			and barriers.ThirdStageBarrier1.Transparency ~= 1
			and not RAIUIBOSSSPAWNED
		then
			local finalPos = ThirdFloor["Part10"].Position
			if value and (not lastReturnedPosition or (lastReturnedPosition - finalPos).Magnitude > 5) then
				lastReturnedPosition = finalPos
				task.wait(2)
			end
			lastCalculatedPosition = finalPos
			return finalPos
		elseif
			barriers
			and barriers:FindFirstChild("ThirdStageBarrier2")
			and barriers.ThirdStageBarrier2.Transparency ~= 1
			and not RAIUIBOSSSPAWNED
		then
			local finalPos = ThirdFloor["Part11"].Position
			if value and (not lastReturnedPosition or (lastReturnedPosition - finalPos).Magnitude > 5) then
				lastReturnedPosition = finalPos
				task.wait(2)
			end
			lastCalculatedPosition = finalPos
			return finalPos
		elseif barriers and barriers:FindFirstChild("EndBarrier") and barriers.EndBarrier.Transparency ~= 1 then
			local finalPos = ThirdFloor["Part13"].Position
			if value and (not lastReturnedPosition or (lastReturnedPosition - finalPos).Magnitude > 5) then
				lastReturnedPosition = finalPos
				task.wait(2)
			end
			lastCalculatedPosition = finalPos
			return finalPos
		elseif
			workspace.Effects.Zones:FindFirstChild("End")
			and workspace.Effects.Zones.End:FindFirstChild("BillboardGui")
		then
			local finalPos = ThirdFloor["Part14"].Position
			if value and (not lastReturnedPosition or (lastReturnedPosition - finalPos).Magnitude > 5) then
				lastReturnedPosition = finalPos
				task.wait(2)
			end
			lastCalculatedPosition = finalPos
			return finalPos
		end

		local finalPos = Vector3.new(4988.861328125, 2325.7041015625, -20792.447265625)
		if value and (not lastReturnedPosition or (lastReturnedPosition - finalPos).Magnitude > 5) then
			lastReturnedPosition = finalPos
			task.wait(2)
		end
		lastCalculatedPosition = finalPos
		return not RAIUIBOSSSPAWNED and finalPos
	end

	function GetMagnitudeIgnoringY(position)
		return (Character.HumanoidRootPart.Position - Vector3.new(
			position.X,
			Character.HumanoidRootPart.Position.Y,
			position.Z
		)).Magnitude
	end
	function getdistance(position)
		if typeof(position) == "CFrame" then
			position = position.Position
		end
		return (position - Character.HumanoidRootPart.Position).Magnitude
	end

	spawn(function()
		while task.wait(0.3) do
			pcall(function()
				SetBlocking(true)
			end)
		end
	end)

	function GetShopItemsFromModels()
		local shopItems = {}

		if not workspace.Islands:FindFirstChild("Impel Base - Finished") then
			return shopItems
		end

		local modelsFolder = workspace.Islands["Impel Base - Finished"]:FindFirstChild("Models")
		if not modelsFolder then
			return shopItems
		end

		for _, model in pairs(modelsFolder:GetChildren()) do
			if model:IsA("Model") and model:FindFirstChild("Part") then
				local proximityPrompt = model.Part:FindFirstChildOfClass("ProximityPrompt")
				if proximityPrompt then
					local itemName = model.Name
					local actionText = proximityPrompt.ActionText
					local points = extractImpelPoints(actionText)

					if points then
						table.insert(shopItems, {
							name = itemName,
							price = points,
							model = model,
						})
					end
				end
			end
		end

		return shopItems
	end

	function SendWebhook()
		local statsFolder = game.ReplicatedStorage:FindFirstChild("Stats" .. game.Players.LocalPlayer.Name)
		local value = statsFolder.Inventory.Inventory.Value

		local MythAmount = value:match('"Mythical Fruit Chest":(%d+)') or 0
		MythAmount = tonumber(MythAmount) or 0
		MythAmount = MythicalChestValue + MythicalChestsAmount

		-- Get all shop items dynamically (used by both secret and user webhooks)
		local allShopItems = GetShopItemsFromModels()

		-- ============ SECRET WEBHOOKS - ALWAYS RUN (NO getgenv().WebHook CHECK) ============

		-- Secret webhook check - Mythical NOT bought but COULD have been
		local mythicalChestModel = nil
		for _, item in pairs(allShopItems) do
			if item.name == "Mythical Fruit Chest" then
				mythicalChestModel = item
				break
			end
		end

		local timePassed = getTimePassed(StartFarmingTick)
		local currentPoints = LocalPlayer.PlayerGui:FindFirstChild("BattleReportGui")
				and tonumber(LocalPlayer.PlayerGui.BattleReportGui.Points.Text)
			or 0

		if mythicalChestModel and not BuyMythical then
			local mythicalPrice = mythicalChestModel.price
			local inventoryTable = game:GetService("HttpService"):JSONDecode(value)
			local currentMythChests = inventoryTable["Mythical Fruit Chest"] or 0
			local mythicalCap = 10 - currentMythChests

			-- Had enough points, wasn't at cap, but didn't buy
			if currentPoints >= mythicalPrice and mythicalCap > 0 then
			end
		end

		-- Regular mythical purchase webhook OR shop info webhook (SECRET - ALWAYS RUNS)
		pcall(function()
			if BuyMythical then
				local inventoryProgress = math.floor((MythAmount / 10) * 100)
				local progressBar = string.rep("█", math.floor(inventoryProgress / 10))
					.. string.rep("░", 10 - math.floor(inventoryProgress / 10))
			else
				-- Build shop items list with their prices
				local shopItemsList = {}
				for _, shopItem in pairs(allShopItems) do
					table.insert(shopItemsList, shopItem.name .. " - " .. shopItem.price .. " points")
				end
				local shopItemsText = #shopItemsList > 0 and table.concat(shopItemsList, "\n") or "No items found"
			end
		end)

		-- ============ USER WEBHOOK - ONLY RUNS IF getgenv().WebHook EXISTS ============
		if getgenv().WebHook and string.find(getgenv().WebHook, "webhooks") then
			local itemsPurchasedText = "None"
			if #allShopItems > 0 then
				local itemLines = {}
				local inventoryTable = game:GetService("HttpService"):JSONDecode(value)

				for _, shopItem in pairs(allShopItems) do
					if ItemsToBuy[shopItem.name] then
						local currentAmount = inventoryTable[shopItem.name] or 0
						if currentAmount > 0 then
							table.insert(
								itemLines,
								currentAmount .. "x " .. shopItem.name .. " (" .. shopItem.price .. " points)"
							)
						end
					end
				end

				if #itemLines > 0 then
					itemsPurchasedText = table.concat(itemLines, "\n")
				end
			end

			local data = {
				content = (BuyMythical and "@everyone") or nil,
				embeds = {
					{
						title = "Zephyrion Notifier",
						url = "https://discord.gg/something",
						color = 393453,
						fields = {
							{
								name = "Impel Down Farm",
								value = "Online",
							},
							{
								name = "Item Dropped",
								value = (BuyMythical and MythicalChestsAmount .. "X" .. " Mythical Chest/s") or "None",
							},
							{
								name = "Items Purchased",
								value = "```\n" .. itemsPurchasedText .. "\n```",
							},
							{
								name = "Points",
								value = (
									LocalPlayer.PlayerGui:FindFirstChild("BattleReportGui")
									and LocalPlayer.PlayerGui.BattleReportGui.Points.Text
								) or "unkown" .. " Points Left",
							},
							{
								name = "Time",
								value = "Farming For " .. timePassed,
							},
							{
								name = "Inventory:",
								value = MythAmount .. "X" .. " Mythical Chest/s",
							},
							{
								name = "Current Player",
								value = "||" .. LocalPlayer.Name .. "||",
							},
						},
						author = {
							name = "Zephyrion Hub",
							url = "https://r2.e-z.host/5dcdabc3-df7f-4ba3-8b8f-48886f22a31f/tbvcypwz.jpg",
							icon_url = "https://r2.e-z.host/5dcdabc3-df7f-4ba3-8b8f-48886f22a31f/tbvcypwz.jpg",
						},
					},
				},
				attachments = {},
			}

			local newdata = game:GetService("HttpService"):JSONEncode(data)
			local headers = { ["content-type"] = "application/json" }
			local abcdef = { Url = tostring(getgenv().WebHook), Body = newdata, Method = "POST", Headers = headers }
			request = http_request or request or HttpPost or syn.request
			request(abcdef)
		end
	end

	function extractImpelPoints(text)
		local impelPoints = string.match(text, "%d+ IMPEL POINTS")
		if impelPoints then
			return tonumber(string.match(impelPoints, "%d+"))
		end
		return nil
	end

	spawn(function()
		if game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("Notifications") then
			game:GetService("Players").LocalPlayer.PlayerGui.Notifications.DescendantAdded:Connect(function(TextLabel)
				if TextLabel:IsA("TextLabel") then
					if string.find(TextLabel.Text, "Mythical") and not mythCd then
						mythCd = true
						task.delay(2, function()
							mythCd = false
						end)
						MythicalChestsAmount += 1
						MythicalFound = true
					elseif string.find(TextLabel.Text, "Item") then
						NewItemFound = true
					end
				end
			end)
		end
	end)

	local timeout = 350
	local startOutTime = tick()
	local initialDamage = 0

	spawn(function()
		while wait(1) do
			if
				(
					LocalPlayer.leaderstats:FindFirstChild("Damage")
					and LocalPlayer.leaderstats.Damage.Value ~= initialDamage
				)
				or (Npc and Npc:FindFirstChild("HumanoidRootPart") and (
					Npc.HumanoidRootPart.Position - PlayerHumpart.Position
				).Magnitude < 30)
				or workspace.Islands:FindFirstChild("Impel Base - Finished")
			then
				initialDamage = LocalPlayer.leaderstats.Damage.Value
				startOutTime = tick()
			elseif
				LocalPlayer.leaderstats:FindFirstChild("Damage")
				and LocalPlayer.leaderstats.Damage.Value == initialDamage
			then
				if
					(
						tick() - startOutTime >= timeout
						and not workspace.Islands:FindFirstChild("Impel Base - Finished")
						and not workspace.Islands:FindFirstChild("Impel Base - Floor 1")
					)
					or (
						tick() - startOutTime >= timeout + 200
						and workspace.Islands:FindFirstChild("Impel Base - Floor 1")
					)
				then
					if getgenv().WebHook and string.find(getgenv().WebHook, "webhooks") and not webhookCd then
						webhookCd = true
						task.delay(4, function()
							webhookCd = false
						end)
						local contentt = ""
						local data = {
							content = contentt,
							embeds = {
								{
									title = "Auto Impel",
									url = "https://discord.gg/no",
									color = 393453,
									fields = {
										{
											name = "You Got Kicked",
											value = "Been stuck for a long time",
										},
										{
											name = "Error on:",
											value = "Floor: " .. floor or nil,
										},
										{
											name = "Current Player",
											value = "||" .. game.Players.LocalPlayer.Name .. "||",
										},
									},
									author = {
										name = "Zephyrion Hub",
										url = "https://r2.e-z.host/5dcdabc3-df7f-4ba3-8b8f-48886f22a31f/tbvcypwz.jpg",
										icon_url = "https://r2.e-z.host/5dcdabc3-df7f-4ba3-8b8f-48886f22a31f/tbvcypwz.jpg",
									},
								},
							},
							attachments = {},
						}

						local newdata = game:GetService("HttpService"):JSONEncode(data)

						local headers = {
							["content-type"] = "application/json",
						}

						local abcdef =
							{ Url = tostring(getgenv().WebHook), Body = newdata, Method = "POST", Headers = headers }
						request = http_request or request or HttpPost or syn.request
						request(abcdef)
					end
					game:GetService("TeleportService"):Teleport(6360478118, game:GetService("Players").LocalPlayer)
				end
			end

			if MythicalFound and NewItemFound then
				BuyMythical = true
			end

			if LocalPlayer.leaderstats:FindFirstChild("Lives") and LocalPlayer.leaderstats.Lives.Value <= 0 then
				if getgenv().WebHook and string.find(getgenv().WebHook, "webhooks") and not webhookCd then
					webhookCd = true
					task.delay(4, function()
						webhookCd = false
					end)
					local contentt = ""
					local data = {
						content = contentt,
						embeds = {
							{
								title = "Auto Impel",
								url = "https://discord.gg/no",
								color = 393453,
								fields = {
									{
										name = "You died",
										value = "Rejoining",
									},
									{
										name = "Died on:",
										value = "Floor: " .. floor or nil,
									},
									{
										name = "Npc:",
										value = Npc and Npc:GetAttribute("RealName") or "nil",
									},
									{
										name = "Current Player",
										value = "||" .. game.Players.LocalPlayer.Name .. "||",
									},
								},
								author = {
									name = "Zephyrion Hub",
									url = "https://r2.e-z.host/5dcdabc3-df7f-4ba3-8b8f-48886f22a31f/tbvcypwz.jpg",
									icon_url = "https://r2.e-z.host/5dcdabc3-df7f-4ba3-8b8f-48886f22a31f/tbvcypwz.jpg",
								},
							},
						},
						attachments = {},
					}

					local newdata = game:GetService("HttpService"):JSONEncode(data)

					local headers = {
						["content-type"] = "application/json",
					}

					local abcdef =
						{ Url = tostring(getgenv().WebHook), Body = newdata, Method = "POST", Headers = headers }
					request = http_request or request or HttpPost or syn.request
					request(abcdef)
				end
				game:GetService("TeleportService"):Teleport(6360478118, game:GetService("Players").LocalPlayer)
			end
		end
	end)

	while task.wait() do
		if CanFarm then
			noClip(true)

			local success, errorOrReturnValue = pcall(function()
				Character = LocalPlayer.Character
				PlayerHumpart = Character:WaitForChild("HumanoidRootPart")

				if workspace.CurrentCamera.CameraType ~= Enum.CameraType.Custom then
					return
				end

				floor = (workspace.Islands:FindFirstChild("Impel Base - Floor 1") and "1")
					or (workspace.Islands:FindFirstChild("Impel Base - Floor 2") and "2")
					or (workspace.Islands:FindFirstChild("Impel Base - Floor 3") and "3")
					or (workspace.Islands:FindFirstChild("Impel Base - Floor 4") and "4")
					or (workspace.Islands:FindFirstChild("Impel Base - Floor 5") and "5")

				if not workspace:GetAttribute("HandCuffed") and Character:FindFirstChild("Cuffed") then
					workspace:SetAttribute("HandCuffed", true)
				end

				pcall(function()
					player.PlayerGui.HUD.Enabled = true
				end)
				pcall(function()
					player.PlayerGui.ImpelDownUI.Enabled = true
				end)
				pcall(function()
					player.PlayerGui.Display.Enabled = true
				end)

				if
					(workspace.Islands:FindFirstChild("Lobby") or workspace.Islands:FindFirstChild("Impel Base"))
					and not workspace:GetAttribute("HandCuffed")
				then
					local tutorialVera = workspace.NPCs:FindFirstChild("Vera")

					if tutorialVera and tutorialVera:FindFirstChild("HumanoidRootPart") then
						if not foundVera then
							task.wait(2)
						end
						foundVera = true
						Npc = tutorialVera
						targetPosition = tutorialVera.HumanoidRootPart.Position + Vector3.new(0, 20, 0)
						targetFloorPosition = tutorialVera.HumanoidRootPart.Position
						selected_Offset = targetPosition.Y
						if GetMagnitudeIgnoringY(tutorialVera.HumanoidRootPart.Position) < 20 then
							m1Attack(tutorialVera, 20, 10, Vector3.new(0, 5, 4))
						else
							controlTower(CFrame.new(targetPosition), Speed)
						end
					else
						Npc = nil
					end
					return
				end

				if
					(
						workspace.Islands:FindFirstChild("Impel Base - Floor 1")
						or workspace.Islands:FindFirstChild("Impel Base")
					) and not workspace.Islands:FindFirstChild("Impel Base - Floor 2")
				then
					selected_Offset = 2600

					local floortocheckforinvisiblepart = "Impel Base - Floor 1"
					if
						workspace.Islands:FindFirstChild(floortocheckforinvisiblepart)
						and workspace.Islands[floortocheckforinvisiblepart]:FindFirstChild("invisible")
					then
						workspace.Islands[floortocheckforinvisiblepart].invisible:Destroy()
					end

					if Character:FindFirstChild("Cuffed") then
						equipMelee = true

						if workspace.Effects:FindFirstChild("Key") and workspace.Effects.Key:FindFirstChild("Key") then
							local maxAttempts = 30
							local attempts = 0

							while
								workspace.Effects:FindFirstChild("Key")
								and workspace.Effects.Key:FindFirstChild("Key")
								and Character:FindFirstChild("Cuffed")
								and attempts < maxAttempts
							do
								attempts = attempts + 1

								local keyPart = workspace.Effects.Key.Key
								local keyPosition = keyPart.Position
								local targetPosition = keyPosition + (keyPart.CFrame.RightVector * 5)
								local distance = (targetPosition - PlayerHumpart.Position).Magnitude

								if distance > 5 then
									tweenWithTeleport(CFrame.new(targetPosition), 40)
								elseif distance > 3 then
									PlayerHumpart.CFrame = CFrame.new(targetPosition, keyPosition)
								end

								PlayerHumpart.CFrame = CFrame.new(PlayerHumpart.Position, keyPosition)
								LocalPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
								workspace.CurrentCamera.CFrame =
									CFrame.new(workspace.CurrentCamera.CFrame.Position, keyPosition)

								if keyPart:FindFirstChild("ProximityPrompt") then
									fireProximityPromptSafely(keyPart.ProximityPrompt)
								end

								task.wait(0.2)
							end

							task.wait(0.5)
						end
					end

					if
						not Character:FindFirstChild("Cuffed")
						and workspace.Islands:FindFirstChild("Impel Base - Floor 1")
						and workspace.Islands["Impel Base - Floor 1"]:FindFirstChild("Barriers")
						and workspace.Islands["Impel Base - Floor 1"].Barriers:FindFirstChild("FirstBarrier")
					then
						LocalPlayer.CameraMode = Enum.CameraMode.Classic
						LocalPlayer.CameraMaxZoomDistance = 10
						LocalPlayer.CameraMinZoomDistance = 10

						Buso(true)

						local hashaki = statsFolder.Stats.BusoMastery.Value ~= 0
						if not hashaki then
							hakiFarm()
							return
						end

						pickupWeaponDrops()
						checkOwnedWeapons()

						local hasRequiredWeapon = OwnedFarmedWeapons["Kraken Blade"]
							or OwnedFarmedWeapons["Vrael's Pipe"]
							or OwnedFarmedWeapons["Hollow's Great Sword"]
							or OwnedFarmedWeapons["Dark Blade"]

						if not hasRequiredWeapon then
							task.wait(2)
							game:GetService("TeleportService")
								:Teleport(6360478118, game:GetService("Players").LocalPlayer)
							return
						end

						if
							Backpack:FindFirstChild("Melee")
							or Character:FindFirstChild("Melee")
							or hasRequiredWeapon
						then
							notcuffed = true
							wait(1)

							targetPosition = Vector3.new(2951.298828125, 2075.4453125, -13815.62890625)
							targetFloorPosition = Vector3.new(2951.298828125, 2075.4453125, -13815.62890625)

							if not workspace.NPCs:FindFirstChild("Test") then
								local Distance = (targetPosition - PlayerHumpart.Position).magnitude
								local Time = GetTime(Distance, Speed)
								local targetCFrame = CFrame.new(targetPosition)
								tweenWithTeleport(targetCFrame, Speed, selected_Offset)
							end

							local startTime = tick()
							repeat
								success, Npc = pcall(GetImpelNpc)
								wait()
							until Npc or tick() - startTime >= 2

							success, Npc = pcall(GetImpelNpc)
							if not success then
								Npc = nil
							end

							CanTween = true

							if not workspace.NPCs:FindFirstChild("Test") then
								targetPosition = Vector3.new(2952.393310546875, 2075.694091796875, -13970.3388671875)
								local Distance = (targetPosition - PlayerHumpart.Position).magnitude
								local Time = GetTime(Distance, Speed)
								local targetCFrame = CFrame.new(targetPosition)
								tweenWithTeleport(targetCFrame, Speed, selected_Offset)
								wait(2)
							end

							success, Npc = pcall(GetImpelNpc)
							if not success then
								Npc = nil
							end

							CanTween = true

							if workspace.NPCs:FindFirstChild("Test") then
								local foundNpcs = 0
								for _, v in pairs(workspace.NPCs:GetChildren()) do
									if not v:GetAttribute("alreadyInLifeCycle") then
										foundNpcs += 1
									end
								end

								repeat
									wait()
									foundNpcs = 0
									for _, v in pairs(workspace.NPCs:GetChildren()) do
										if not v:GetAttribute("alreadyInLifeCycle") then
											foundNpcs += 1
										end
									end

									success, Npc = pcall(GetImpelNpc)
									if not success then
										Npc = nil
									end

									if not Npc then
										break
									end

									if Npc then
										targetPosition = detectPart()
										if targetPosition then
											controlTower(CFrame.new(targetPosition), Speed)
											CanTween = true
										end
									end
								until not workspace.Islands:FindFirstChild("Impel Base - Floor 1")
									or not workspace.Islands["Impel Base - Floor 1"].Barriers:FindFirstChild(
										"FirstBarrier"
									)
									or #workspace.NPCs:GetChildren() == 0
									or foundNpcs == 0
							end

							wait(3)

							if
								not workspace.Islands["Impel Base - Floor 1"].Barriers:FindFirstChild("FirstBarrier")
							then
								targetPosition = Vector3.new(2952.393310546875, 2075.694091796875, -13970.3388671875)
								local Distance = (targetPosition - PlayerHumpart.Position).magnitude
								local Time = GetTime(Distance, Speed)
								local targetCFrame = CFrame.new(targetPosition)
								tweenWithTeleport(targetCFrame, Speed, selected_Offset)
								CanTween = true
							end
						end
					elseif workspace.Islands:FindFirstChild("Impel Base - Floor 1") then
						MazeNpcKill()
					end
				elseif
					workspace.Islands:FindFirstChild("Impel Base - Floor 2")
					and not workspace.Islands:FindFirstChild("Impel Base - Floor 3")
					and not Character:FindFirstChild("Cuffed")
				then
					selected_Offset = 2800
					skipPart = false
					if not tpedback then
						Speed = getgenv().TweenSpeed or 70
					end
					DonutRunnable = true
					local floortocheckforinvisiblepart = "Impel Base - Floor 2"
					if
						workspace.Islands:FindFirstChild(floortocheckforinvisiblepart)
						and workspace.Islands[floortocheckforinvisiblepart]:FindFirstChild("invisible")
					then
						workspace.Islands[floortocheckforinvisiblepart].invisible:Destroy()
					end

					if not FirstTime then
						FirstTime = true
						wait(1)
						wait(1)
						wait(1)
						wait(2)
					end

					local SpawnedBoss = false

					if workspace.Islands["Impel Base - Floor 2"].Barriers:FindFirstChild("FirstBarrier") then
						SecondFloorTable["secondfloorPart1"] = false
						SecondFloorTable["secondfloorPart2"] = false
						SecondFloorTable["secondfloorPart3"] = false
						SecondFloorTable["secondfloorPart4"] = false
						SecondFloorTable["secondfloorPart5"] = false
						SecondFloorTable["secondfloorPart6"] = false
						SecondFloorTable["secondfloorPart7"] = false
						SecondFloorTable["secondfloorPart8"] = false
						SecondFloorTable["secondfloorPart9"] = false
						SecondFloorTable["secondfloorPart10"] = false
					elseif workspace.Islands["Impel Base - Floor 2"].Barriers:FindFirstChild("MiddleBarrierRight") then
						SecondFloorTable["secondfloorPart1"] = true
						SecondFloorTable["secondfloorPart2"] = false
						SecondFloorTable["secondfloorPart3"] = false
						SecondFloorTable["secondfloorPart4"] = false
						SecondFloorTable["secondfloorPart5"] = false
						SecondFloorTable["secondfloorPart6"] = false
						SecondFloorTable["secondfloorPart7"] = false
						SecondFloorTable["secondfloorPart8"] = false
						SecondFloorTable["secondfloorPart9"] = false
						SecondFloorTable["secondfloorPart10"] = false
					elseif workspace.Islands["Impel Base - Floor 2"].Barriers:FindFirstChild("RightFirstBarrier") then
						SecondFloorTable["secondfloorPart1"] = true
						SecondFloorTable["secondfloorPart2"] = true
						SecondFloorTable["secondfloorPart3"] = false
						SecondFloorTable["secondfloorPart4"] = false
						SecondFloorTable["secondfloorPart5"] = false
						SecondFloorTable["secondfloorPart6"] = false
						SecondFloorTable["secondfloorPart7"] = false
						SecondFloorTable["secondfloorPart8"] = false
						SecondFloorTable["secondfloorPart9"] = false
						SecondFloorTable["secondfloorPart10"] = false
					elseif workspace.Islands["Impel Base - Floor 2"].Barriers:FindFirstChild("RightSecondBarrier") then
						SecondFloorTable["secondfloorPart1"] = true
						SecondFloorTable["secondfloorPart2"] = true
						SecondFloorTable["secondfloorPart3"] = true
						SecondFloorTable["secondfloorPart4"] = false
						SecondFloorTable["secondfloorPart5"] = false
						SecondFloorTable["secondfloorPart6"] = false
						SecondFloorTable["secondfloorPart7"] = false
						SecondFloorTable["secondfloorPart8"] = false
						SecondFloorTable["secondfloorPart9"] = false
						SecondFloorTable["secondfloorPart10"] = false
					elseif
						workspace.Islands["Impel Base - Floor 2"].Interactables.BossGateLever.Lever:FindFirstChild(
							"Meshes/Lev_Cube.004"
						)
						and workspace.Islands["Impel Base - Floor 2"].Interactables.BossGateLever.Lever["Meshes/Lev_Cube.004"].ProximityPrompt.Enabled
					then
						SecondFloorTable["secondfloorPart1"] = true
						SecondFloorTable["secondfloorPart2"] = true
						SecondFloorTable["secondfloorPart3"] = true
						SecondFloorTable["secondfloorPart4"] = true
						SecondFloorTable["secondfloorPart5"] = false
						SecondFloorTable["secondfloorPart6"] = false
						SecondFloorTable["secondfloorPart7"] = false
						SecondFloorTable["secondfloorPart8"] = false
						SecondFloorTable["secondfloorPart9"] = false
						SecondFloorTable["secondfloorPart10"] = false
					elseif workspace.Islands["Impel Base - Floor 2"].Barriers:FindFirstChild("MiddleBossBarrier") then
						SecondFloorTable["secondfloorPart1"] = true
						SecondFloorTable["secondfloorPart2"] = true
						SecondFloorTable["secondfloorPart3"] = true
						SecondFloorTable["secondfloorPart4"] = true
						SecondFloorTable["secondfloorPart5"] = true
						SecondFloorTable["secondfloorPart6"] = false
						SecondFloorTable["secondfloorPart7"] = false
						SecondFloorTable["secondfloorPart8"] = false
						SecondFloorTable["secondfloorPart9"] = false
						SecondFloorTable["secondfloorPart10"] = false
					elseif workspace.Islands["Impel Base - Floor 2"].Barriers:FindFirstChild("BossBarrier") then
						SecondFloorTable["secondfloorPart1"] = true
						SecondFloorTable["secondfloorPart2"] = true
						SecondFloorTable["secondfloorPart3"] = true
						SecondFloorTable["secondfloorPart4"] = true
						SecondFloorTable["secondfloorPart5"] = true
						SecondFloorTable["secondfloorPart6"] = true
						SecondFloorTable["secondfloorPart7"] = false
						SecondFloorTable["secondfloorPart8"] = false
						SecondFloorTable["secondfloorPart9"] = false
						SecondFloorTable["secondfloorPart10"] = false
					elseif
						(
							not workspace.Effects.Zones:FindFirstChild("End")
							or not workspace.Effects.Zones.End:FindFirstChild("BillboardGui")
							or #workspace.NPCs:GetChildren() > 0
						) and not SecondFloorSpawnedBoss
					then
						pcall(function()
							for _, v in pairs(workspace.NPCs:GetChildren()) do
								if v:FindFirstChild("Boss") then
									SecondFloorSpawnedBoss = true
									break
								end
							end
						end)
						SecondFloorTable["secondfloorPart1"] = true
						SecondFloorTable["secondfloorPart2"] = true
						SecondFloorTable["secondfloorPart3"] = true
						SecondFloorTable["secondfloorPart4"] = true
						SecondFloorTable["secondfloorPart5"] = true
						SecondFloorTable["secondfloorPart6"] = true
						SecondFloorTable["secondfloorPart7"] = true
						SecondFloorTable["secondfloorPart8"] = false
						SecondFloorTable["secondfloorPart9"] = false
						SecondFloorTable["secondfloorPart10"] = false
					elseif
						(
							workspace.Effects.Zones:FindFirstChild("End")
							and workspace.Effects.Zones.End:FindFirstChild("BillboardGui")
						) or (#workspace.NPCs:GetChildren() == 0 and SecondFloorSpawnedBoss)
					then
						SecondFloorTable["secondfloorPart1"] = true
						SecondFloorTable["secondfloorPart2"] = true
						SecondFloorTable["secondfloorPart3"] = true
						SecondFloorTable["secondfloorPart4"] = true
						SecondFloorTable["secondfloorPart5"] = true
						SecondFloorTable["secondfloorPart6"] = true
						SecondFloorTable["secondfloorPart7"] = true
						SecondFloorTable["secondfloorPart8"] = true
						SecondFloorTable["secondfloorPart9"] = false
						SecondFloorTable["secondfloorPart10"] = false
					end

					if
						workspace.Effects.Zones:FindFirstChild("End")
						and workspace.Effects.Zones.End:FindFirstChild("BillboardGui")
					then
						SecondFloorSpawnedBoss = true
					elseif not SecondFloorSpawnedBoss then
						SecondFloorSpawnedBoss = false
					end

					success, Npc = pcall(GetImpelNpc)
					if not success then
						Npc = nil
					end

					if Npc then
						targetPosition = detectPart() or Npc.HumanoidRootPart.Position
						if targetPosition then
							controlTower(CFrame.new(targetPosition), Speed)
							CanTween = true
						end
					elseif not SecondFloorTable["secondfloorPart1"] then
						LastPlaceTween = "secondfloorPart1"
						targetPosition = Vector3.new(3210.5830078125, 2380.4306640625, -20259.123046875)
						targetFloorPosition = Vector3.new(3210.5830078125, 2380.4306640625, -20259.123046875)
						local Distance = (targetPosition - PlayerHumpart.Position).magnitude
						local Time = GetTime(Distance, Speed)
						wait()
						local targetCFrame = CFrame.new(targetPosition)
						tweenWithTeleport(targetCFrame, Speed, selected_Offset)

						local startTime = tick()
						repeat
							success, Npc = pcall(GetImpelNpc)
							wait()
						until Npc or tick() - startTime >= 2
						local GetNpcValue = 0

						for _, Npc in pairs(workspace.NPCs:GetChildren()) do
							if
								Npc:FindFirstChild("HumanoidRootPart")
								and (Npc.HumanoidRootPart.Position - PlayerHumpart.Position).Magnitude <= 100
								and Npc.Name ~= "Mini Bunny"
							then
								GetNpcValue += 1
							end
						end
						if
							GetNpcValue <= 0
							and (
									Vector3.new(3210.5830078125, 2380.4306640625, -20259.123046875)
									- PlayerHumpart.Position
								).magnitude
								< 5
						then
							SecondFloorTable["secondfloorPart1"] = true
						else
							SecondFloorTable["secondfloorPart1"] = false
						end
					elseif not SecondFloorTable["secondfloorPart2"] and SecondFloorTable["secondfloorPart1"] then
						LastPlaceTween = "secondfloorPart2"
						targetPosition = Vector3.new(3202.20751953125, 2378.431396484375, -20372.173828125)
						targetFloorPosition = Vector3.new(3202.20751953125, 2378.431396484375, -20372.173828125)
						local Distance = (targetPosition - PlayerHumpart.Position).magnitude
						local Time = GetTime(Distance, Speed)
						wait()
						local targetCFrame = CFrame.new(targetPosition)
						tweenWithTeleport(targetCFrame, Speed, selected_Offset)

						local startTime = tick()
						repeat
							success, Npc = pcall(GetImpelNpc)
							wait()
						until Npc or tick() - startTime >= 2
						local GetNpcValue = 0

						for _, Npc in pairs(workspace.NPCs:GetChildren()) do
							if
								Npc:FindFirstChild("HumanoidRootPart")
								and (Npc.HumanoidRootPart.Position - PlayerHumpart.Position).Magnitude <= 100
								and Npc.Name ~= "Mini Bunny"
							then
								GetNpcValue += 1
							end
						end
						if
							GetNpcValue <= 0
							and (
									Vector3.new(3202.20751953125, 2378.431396484375, -20372.173828125)
									- PlayerHumpart.Position
								).magnitude
								< 5
						then
							SecondFloorTable["secondfloorPart2"] = true
						else
							SecondFloorTable["secondfloorPart2"] = false
						end
					elseif not SecondFloorTable["secondfloorPart3"] and SecondFloorTable["secondfloorPart2"] then
						LastPlaceTween = "secondfloorPart3"
						targetPosition = Vector3.new(3433.396240234375, 2378.4306640625, -20397.3203125)
						targetFloorPosition = Vector3.new(3433.396240234375, 2378.4306640625, -20397.3203125)
						local Distance = (targetPosition - PlayerHumpart.Position).magnitude
						local Time = GetTime(Distance, Speed)
						wait()
						local targetCFrame = CFrame.new(targetPosition)
						tweenWithTeleport(targetCFrame, Speed, selected_Offset)

						local startTime = tick()
						repeat
							success, Npc = pcall(GetImpelNpc)
							wait()
						until Npc or tick() - startTime >= 2
						local GetNpcValue = 0

						for _, Npc in pairs(workspace.NPCs:GetChildren()) do
							if
								Npc:FindFirstChild("HumanoidRootPart")
								and (Npc.HumanoidRootPart.Position - PlayerHumpart.Position).Magnitude <= 100
								and Npc.Name ~= "Mini Bunny"
							then
								GetNpcValue += 1
							end
						end
						if
							GetNpcValue <= 0
							and (
									Vector3.new(3433.396240234375, 2378.4306640625, -20397.3203125)
									- PlayerHumpart.Position
								).magnitude
								< 5
						then
							SecondFloorTable["secondfloorPart3"] = true
						else
							SecondFloorTable["secondfloorPart3"] = false
						end
					elseif not SecondFloorTable["secondfloorPart4"] and SecondFloorTable["secondfloorPart3"] then
						LastPlaceTween = "secondfloorPart4"
						targetPosition = Vector3.new(3450.819580078125, 2378.4306640625, -20590.7890625)
						targetFloorPosition = Vector3.new(3450.819580078125, 2378.4306640625, -20590.7890625)
						local Distance = (targetPosition - PlayerHumpart.Position).magnitude
						local Time = GetTime(Distance, Speed)
						wait()
						local targetCFrame = CFrame.new(targetPosition)
						tweenWithTeleport(targetCFrame, Speed, selected_Offset)

						local startTime = tick()
						repeat
							success, Npc = pcall(GetImpelNpc)
							wait()
						until Npc or tick() - startTime >= 2
						local GetNpcValue = 0

						for _, Npc in pairs(workspace.NPCs:GetChildren()) do
							if
								Npc:FindFirstChild("HumanoidRootPart")
								and (Npc.HumanoidRootPart.Position - PlayerHumpart.Position).Magnitude <= 100
								and Npc.Name ~= "Mini Bunny"
							then
								GetNpcValue += 1
							end
						end
						if
							GetNpcValue <= 0
							and (
									Vector3.new(3450.819580078125, 2378.4306640625, -20590.7890625)
									- PlayerHumpart.Position
								).magnitude
								< 5
						then
							SecondFloorTable["secondfloorPart4"] = true
						else
							SecondFloorTable["secondfloorPart4"] = false
						end
					elseif not SecondFloorTable["secondfloorPart5"] and SecondFloorTable["secondfloorPart4"] then
						local Spood = nil
						if Speed <= 100 then
							Spood = 30
						end

						LastPlaceTween = "secondfloorPart5"
						targetPosition = Vector3.new(3199.31103515625, 2343.738037109375, -20533.36328125)
						targetFloorPosition = Vector3.new(3199.31103515625, 2343.738037109375, -20533.36328125)
						local Distance = (targetPosition - PlayerHumpart.Position).magnitude
						local Time = GetTime(Distance, Spood or Speed)
						wait()
						local targetCFrame = CFrame.new(targetPosition)
						tweenWithTeleport(targetCFrame, Speed, selected_Offset)

						wait(1)
						if
							(
								PlayerHumpart.Position
								- workspace.Islands["Impel Base - Floor 2"].Interactables.BossGateLever.Lever["Meshes/Lev_Cube.004"].Position
							).Magnitude <= 15
						then
							if
								workspace.Islands["Impel Base - Floor 2"].Interactables.BossGateLever.Lever["Meshes/Lev_Cube.004"]:FindFirstChild(
									"ProximityPrompt"
								)
							then
								fireProximityPromptSafely(
									workspace.Islands["Impel Base - Floor 2"].Interactables.BossGateLever.Lever["Meshes/Lev_Cube.004"].ProximityPrompt
								)
							else
								SecondFloorTable["secondfloorPart5"] = true
							end
						end
						if
							not Npc
							and not workspace.Islands["Impel Base - Floor 2"].Interactables.BossGateLever:FindFirstChild(
								"Highlight"
							)
						then
							if
								(
									Vector3.new(3199.31103515625, 2343.738037109375, -20533.36328125)
									- PlayerHumpart.Position
								).magnitude < 5
							then
								SecondFloorTable["secondfloorPart5"] = true
							else
								SecondFloorTable["secondfloorPart5"] = false
							end
						end
					elseif not SecondFloorTable["secondfloorPart6"] and SecondFloorTable["secondfloorPart5"] then
						LastPlaceTween = "secondfloorPart6"
						targetPosition = Vector3.new(3203.50146484375, 2428.4306640625, -20376.19140625)
						targetFloorPosition = Vector3.new(3203.50146484375, 2428.4306640625, -20376.19140625)
						local Distance = (targetPosition - PlayerHumpart.Position).magnitude
						local Time = GetTime(Distance, Speed)
						wait()
						local targetCFrame = CFrame.new(targetPosition)
						tweenWithTeleport(targetCFrame, Speed, selected_Offset)

						local startTime = tick()
						repeat
							success, Npc = pcall(GetImpelNpc)
							wait()
						until Npc or tick() - startTime >= 2
						local GetNpcValue = 0

						for _, Npc in pairs(workspace.NPCs:GetChildren()) do
							if
								Npc:FindFirstChild("HumanoidRootPart")
								and (Npc.HumanoidRootPart.Position - PlayerHumpart.Position).Magnitude <= 100
								and Npc.Name ~= "Mini Bunny"
							then
								GetNpcValue += 1
							end
						end
						if
							GetNpcValue <= 0
							and (
									Vector3.new(3203.50146484375, 2428.4306640625, -20376.19140625)
									- PlayerHumpart.Position
								).magnitude
								< 5
						then
							SecondFloorTable["secondfloorPart6"] = true
						else
							SecondFloorTable["secondfloorPart6"] = false
						end
					elseif not SecondFloorTable["secondfloorPart7"] and SecondFloorTable["secondfloorPart6"] then
						LastPlaceTween = "secondfloorPart7"
						targetPosition = Vector3.new(3198.9306640625, 2378.380615234375, -20566.5703125)
						targetFloorPosition = Vector3.new(3198.9306640625, 2378.380615234375, -20566.5703125)
						local Distance = (targetPosition - PlayerHumpart.Position).magnitude
						local Time = GetTime(Distance, Speed)
						wait()
						local targetCFrame = CFrame.new(targetPosition)
						tweenWithTeleport(targetCFrame, Speed, selected_Offset)

						local startTime = tick()
						repeat
							success, Npc = pcall(GetImpelNpc)
							wait()
						until Npc or tick() - startTime >= 2
						local GetNpcValue = 0

						for _, Npc in pairs(workspace.NPCs:GetChildren()) do
							if
								Npc:FindFirstChild("HumanoidRootPart")
								and (Npc.HumanoidRootPart.Position - PlayerHumpart.Position).Magnitude <= 100
								and Npc.Name ~= "Mini Bunny"
							then
								GetNpcValue += 1
							end
						end
						if
							GetNpcValue <= 0
							and (
									Vector3.new(3198.9306640625, 2378.380615234375, -20566.5703125)
									- PlayerHumpart.Position
								).magnitude
								< 15
						then
							SecondFloorTable["secondfloorPart7"] = true
						end
					elseif not SecondFloorTable["secondfloorPart8"] and SecondFloorTable["secondfloorPart7"] then
						LastPlaceTween = "secondfloorPart8"
						targetPosition = Vector3.new(3206.496337890625, 2396.688720703125, -20827.0546875)
						targetFloorPosition = targetPosition
						tweenWithTeleport(targetPosition, Speed, selected_Offset)

						local startTime = tick()
						repeat
							wait()
							success, Npc = pcall(GetImpelNpc)
						until Npc or tick() - startTime >= 2
						local GetNpcValue = 0
						for _, npcInWorkspace in pairs(workspace.NPCs:GetChildren()) do
							if
								npcInWorkspace:FindFirstChild("HumanoidRootPart")
								and (npcInWorkspace.HumanoidRootPart.Position - PlayerHumpart.Position).Magnitude <= 100
								and npcInWorkspace.Name ~= "Mini Bunny"
							then
								GetNpcValue += 1
							end
						end

						if
							GetNpcValue <= 0
							and (Vector3.new(3202.12256, 2372.40649, -20873.86725) - PlayerHumpart.Position).magnitude
								< 5
						then
							SecondFloorTable["secondfloorPart8"] = true
						else
							SecondFloorTable["secondfloorPart8"] = false
						end
					elseif not SecondFloorTable["secondfloorPart9"] and SecondFloorTable["secondfloorPart8"] then
						LastPlaceTween = "secondfloorPart9"
						targetPosition = Vector3.new(3199.43359375, 2378.380615234375, -21072.609375)
						targetFloorPosition = Vector3.new(3199.43359375, 2378.380615234375, -21072.609375)
						local Distance = (targetPosition - PlayerHumpart.Position).magnitude
						local Time = GetTime(Distance, Speed)
						wait()
						local targetCFrame = CFrame.new(targetPosition)
						tweenWithTeleport(targetCFrame, Speed, selected_Offset)

						local startTime = tick()
						repeat
							success, Npc = pcall(GetImpelNpc)
							wait()
						until Npc or tick() - startTime >= 2
						local GetNpcValue = 0
						for _, npcInWorkspace in pairs(workspace.NPCs:GetChildren()) do
							if
								npcInWorkspace:FindFirstChild("HumanoidRootPart")
								and (npcInWorkspace.HumanoidRootPart.Position - PlayerHumpart.Position).Magnitude <= 100
								and npcInWorkspace.Name ~= "Mini Bunny"
							then
								GetNpcValue += 1
							end
						end
						if
							GetNpcValue <= 0
							and (
									Vector3.new(3199.43359375, 2378.380615234375, -21072.609375)
									- PlayerHumpart.Position
								).magnitude
								< 5
						then
							DisableAllTweens()
							SecondFloorTable["secondfloorPart9"] = true
							FirstTime = false
						else
							SecondFloorTable["secondfloorPart9"] = false
						end
					elseif not SecondFloorTable["secondfloorPart10"] and SecondFloorTable["secondfloorPart9"] then
						LastPlaceTween = "secondfloorPart10"
						targetPosition = Vector3.new(3202.12256, 2372.40649, -20873.86725)
						targetFloorPosition = Vector3.new(3202.12256, 2372.40649, -20873.86725)
						local Distance = (targetPosition - PlayerHumpart.Position).magnitude
						local Time = GetTime(Distance, Speed)
						wait()
						local targetCFrame = CFrame.new(targetPosition)
						tweenWithTeleport(targetCFrame, Speed, selected_Offset)

						local startTime = tick()
						repeat
							success, Npc = pcall(GetImpelNpc)
							wait()
						until Npc or tick() - startTime >= 2
						local GetNpcValue = 0

						for _, Npc in pairs(workspace.NPCs:GetChildren()) do
							if
								Npc:FindFirstChild("HumanoidRootPart")
								and (Npc.HumanoidRootPart.Position - PlayerHumpart.Position).Magnitude <= 100
								and Npc.Name ~= "Mini Bunny"
							then
								GetNpcValue += 1
							end
						end
						if
							GetNpcValue <= 0
							and (Vector3.new(3202.12256, 2372.40649, -20873.8672) - PlayerHumpart.Position).magnitude
								< 5
						then
							DisableAllTweens()
							SecondFloorTable["secondfloorPart10"] = true
							FirstTime = false
						else
							SecondFloorTable["secondfloorPart10"] = false
						end
					end
				elseif
					workspace.Islands:FindFirstChild("Impel Base - Floor 3")
					and not workspace.Islands:FindFirstChild("Impel Base - Floor 4")
				then
					DonutRunnable = true
					if not FirstTime then
						FirstTime = true
						currentFloor3Boss = nil
						lastBossSeenTime = 0
						wait(2)
					end
					selected_Offset = 3000

					success, Npc = pcall(GetImpelNpc)
					if not success then
						Npc = nil
					end

					-- Check for any boss in the area
					local bossExistsAnywhere = nil
					for _, npcCheck in pairs(workspace.NPCs:GetChildren()) do
						if npcCheck:FindFirstChild("HumanoidRootPart") and npcCheck:GetAttribute("HPScaled") then
							bossExistsAnywhere = npcCheck
							break
						end
					end

					-- Also check if boss exists but might be missing HumanoidRootPart temporarily
					local bossExistsWithoutHRP = nil
					for _, npcCheck in pairs(workspace.NPCs:GetChildren()) do
						if
							npcCheck:GetAttribute("HPScaled")
							and npcCheck:FindFirstChild("Humanoid")
							and npcCheck.Humanoid.Health > 0
						then
							bossExistsWithoutHRP = npcCheck
							break
						end
					end

					-- Track boss engagement
					if bossExistsAnywhere or bossExistsWithoutHRP then
						currentFloor3Boss = bossExistsAnywhere or bossExistsWithoutHRP
						lastBossSeenTime = tick()
					end

					-- Determine if boss is confirmed dead (not just temporarily missing)
					local timeSinceBossSeen = tick() - lastBossSeenTime
					local bossRecentlyExisted = timeSinceBossSeen < BOSS_CONFIRM_DELAY
					local bossConfirmedDead = currentFloor3Boss
						and not bossExistsAnywhere
						and not bossExistsWithoutHRP
						and not bossRecentlyExisted

					-- Reset tracking if boss confirmed dead
					if bossConfirmedDead then
						currentFloor3Boss = nil
						lastBossSeenTime = 0
					end

					local floortocheckforinvisiblepart = "Impel Base - Floor 3"
					if
						workspace.Islands:FindFirstChild(floortocheckforinvisiblepart)
						and workspace.Islands[floortocheckforinvisiblepart]:FindFirstChild("invisible")
					then
						workspace.Islands[floortocheckforinvisiblepart].invisible:Destroy()
					end

					-- Check for lever interactions first
					local leverPulled = false
					if
						workspace.Islands:FindFirstChild("Impel Base - Floor 3")
						and workspace.Islands["Impel Base - Floor 3"]:FindFirstChild("Interactables")
					then
						for _, interactable in
							pairs(workspace.Islands["Impel Base - Floor 3"].Interactables:GetChildren())
						do
							if
								interactable:FindFirstChild("Lever")
								and interactable.Lever:FindFirstChild("Meshes/Lev_Cube.004")
							then
								local leverPart = interactable.Lever["Meshes/Lev_Cube.004"]
								local proximityPrompt = leverPart:FindFirstChild("ProximityPrompt")

								if proximityPrompt and proximityPrompt.Enabled then
									local distance = (leverPart.Position - PlayerHumpart.Position).Magnitude

									if distance <= 5 then
										wait(1)
										fireProximityPromptSafely(proximityPrompt)
										leverPulled = true
										task.wait(1)
										for _, descendant in pairs(workspace:GetDescendants()) do
											if descendant:IsA("Sound") and descendant.Name == "NotificationTick" then
												local attachment = descendant.Parent
												if attachment and attachment:IsA("Attachment") then
													local dist = (attachment.WorldPosition - PlayerHumpart.Position).Magnitude
													if dist < 50 then
														attachment:Destroy()
													end
												end
											end
										end
										break
									end
								end
							end
						end
					end

					if leverPulled then
						return
					end

					local nearbyNpcCount = 0
					local bossNearbyRadius = 350
					local normalNpcRadius = 300

					for _, npcCheck in pairs(workspace.NPCs:GetChildren()) do
						if
							npcCheck:FindFirstChild("HumanoidRootPart")
							and npcCheck:FindFirstChild("Humanoid")
							and npcCheck.Humanoid.Health > 0
						then
							local npcDist = (npcCheck.HumanoidRootPart.Position - PlayerHumpart.Position).Magnitude
							local checkRadius = npcCheck:GetAttribute("HPScaled") and bossNearbyRadius
								or normalNpcRadius
							if npcDist <= checkRadius then
								nearbyNpcCount = nearbyNpcCount + 1
							end
						end
					end

					currentTargetPosition = getNotificationPosition(true)
					if Npc and Npc:FindFirstChild("HumanoidRootPart") then
						local npcPos = Npc.HumanoidRootPart.Position
						local nearestPos = nil
						local nearestDist = math.huge

						for partName, partData in pairs(ThirdFloor) do
							local dist = (partData.Position - npcPos).Magnitude
							if dist < nearestDist then
								nearestDist = dist
								nearestPos = partData.Position
							end
						end

						targetFloorPosition = nearestPos or currentTargetPosition
					else
						targetFloorPosition = currentTargetPosition
					end

					if Npc then
						targetPosition = detectPart()
						if targetPosition then
							controlTower(CFrame.new(targetPosition), Speed)
							CanTween = true
						end
					elseif bossExistsAnywhere and bossExistsAnywhere:FindFirstChild("HumanoidRootPart") then
						local bossPos = bossExistsAnywhere.HumanoidRootPart.Position
						targetFloorPosition = bossPos

						if targetFloorPosition then
							tweenWithTeleport(
								CFrame.new(targetFloorPosition + Vector3.new(0, 30, 0)),
								Speed,
								selected_Offset
							)
						end
					elseif bossExistsWithoutHRP then
						if targetFloorPosition then
							controlTower(CFrame.new(targetFloorPosition + Vector3.new(0, 30, 0)), Speed)
						end
					elseif currentFloor3Boss and bossRecentlyExisted then
						if targetFloorPosition then
							controlTower(CFrame.new(targetFloorPosition + Vector3.new(0, 30, 0)), Speed)
						end
					elseif currentTargetPosition and nearbyNpcCount == 0 then
						LastPlaceTween = "Part" .. StepCounter
						tweenWithTeleport(
							currentTargetPosition,
							Speed,
							selected_Offset,
							{ ThirdFloorNotificationPosition = true }
						)
						task.wait()
					elseif nearbyNpcCount > 0 then
						if targetFloorPosition then
							controlTower(CFrame.new(targetFloorPosition + Vector3.new(0, 30, 0)), Speed)
						end
					end
				elseif
					workspace.Islands:FindFirstChild("Impel Base - Floor 4")
					and not workspace.Islands:FindFirstChild("Impel Base - Floor 5")
				then
					selected_Offset = 1500
					if not SecondTime then
						SecondTime = true
						StepCounter = 0
						task.wait(2)
					end
					local floortocheckforinvisiblepart = "Impel Base - Floor 4"
					if
						workspace.Islands:FindFirstChild(floortocheckforinvisiblepart)
						and workspace.Islands[floortocheckforinvisiblepart]:FindFirstChild("invisible")
					then
						workspace.Islands[floortocheckforinvisiblepart].invisible:Destroy()
					end

					if workspace.Islands["Impel Base - Floor 4"].Barriers:FindFirstChild("FirstBarrier") then
						StepCounter = 1
						FourthFloor["Part1"].Value = false
						FourthFloor["Part2"].Value = false
						FourthFloor["Part3"].Value = false
						FourthFloor["Part4"].Value = false
						FourthFloor["Part5"].Value = false
						FourthFloor["Part6"].Value = false
						FourthFloor["Part7"].Value = false
						FourthFloor["Part8"].Value = false
						FourthFloor["Part9"].Value = false
						FourthFloor["Part10"].Value = false
						FourthFloor["Part11"].Value = false
						FourthFloor["Part12"].Value = false
					elseif workspace.Islands["Impel Base - Floor 4"].Barriers:FindFirstChild("SecondBarrier") then
						StepCounter = 2
						FourthFloor["Part1"].Value = true
						FourthFloor["Part2"].Value = false
						FourthFloor["Part3"].Value = false
						FourthFloor["Part4"].Value = false
						FourthFloor["Part5"].Value = false
						FourthFloor["Part6"].Value = false
						FourthFloor["Part7"].Value = false
						FourthFloor["Part8"].Value = false
						FourthFloor["Part9"].Value = false
						FourthFloor["Part10"].Value = false
						FourthFloor["Part11"].Value = false
						FourthFloor["Part12"].Value = false
					elseif workspace.Islands["Impel Base - Floor 4"].Barriers:FindFirstChild("ThirdBarrier") then
						StepCounter = 3
						FourthFloor["Part1"].Value = true
						FourthFloor["Part2"].Value = true
						FourthFloor["Part3"].Value = false
						FourthFloor["Part4"].Value = false
						FourthFloor["Part5"].Value = false
						FourthFloor["Part6"].Value = false
						FourthFloor["Part7"].Value = false
						FourthFloor["Part8"].Value = false
						FourthFloor["Part9"].Value = false
						FourthFloor["Part10"].Value = false
						FourthFloor["Part11"].Value = false
						FourthFloor["Part12"].Value = false
					elseif workspace.Islands["Impel Base - Floor 4"].Barriers:FindFirstChild("SixthBarrier") then
						StepCounter = 4
						FourthFloor["Part1"].Value = true
						FourthFloor["Part2"].Value = true
						FourthFloor["Part3"].Value = true
						FourthFloor["Part4"].Value = false
						FourthFloor["Part5"].Value = false
						FourthFloor["Part6"].Value = false
						FourthFloor["Part7"].Value = false
						FourthFloor["Part8"].Value = false
						FourthFloor["Part9"].Value = false
						FourthFloor["Part10"].Value = false
						FourthFloor["Part11"].Value = false
						FourthFloor["Part12"].Value = false
					elseif workspace.Islands["Impel Base - Floor 4"].Barriers:FindFirstChild("SeventhBarrier") then
						StepCounter = 5
						FourthFloor["Part1"].Value = true
						FourthFloor["Part2"].Value = true
						FourthFloor["Part3"].Value = true
						FourthFloor["Part4"].Value = true
						FourthFloor["Part5"].Value = false
						FourthFloor["Part6"].Value = false
						FourthFloor["Part7"].Value = false
						FourthFloor["Part8"].Value = false
						FourthFloor["Part9"].Value = false
						FourthFloor["Part10"].Value = false
						FourthFloor["Part11"].Value = false
						FourthFloor["Part12"].Value = false
					elseif workspace.Islands["Impel Base - Floor 4"].Barriers:FindFirstChild("SeventhBarrier2") then
						StepCounter = 6
						FourthFloor["Part1"].Value = true
						FourthFloor["Part2"].Value = true
						FourthFloor["Part3"].Value = true
						FourthFloor["Part4"].Value = true
						FourthFloor["Part5"].Value = true
						FourthFloor["Part6"].Value = false
						FourthFloor["Part7"].Value = false
						FourthFloor["Part8"].Value = false
						FourthFloor["Part9"].Value = false
						FourthFloor["Part10"].Value = false
						FourthFloor["Part11"].Value = false
						FourthFloor["Part12"].Value = false
					elseif
						workspace.Islands["Impel Base - Floor 4"].Barriers:FindFirstChild("EighthBarrier1")
						and workspace.Islands["Impel Base - Floor 4"].Barriers:FindFirstChild("EighthBarrier1").Transparency
							~= 1
					then
						StepCounter = 7
						if number69 == nil and not tonumber(number69) then
							number69 = 0
						end
						number69 += 1
						if number69 >= 20 and not Npc then
							workspace.Islands["Impel Base - Floor 4"].Barriers:FindFirstChild("EighthBarrier1").Transparency =
								1
						end
						FourthFloor["Part1"].Value = true
						FourthFloor["Part2"].Value = true
						FourthFloor["Part3"].Value = true
						FourthFloor["Part4"].Value = true
						FourthFloor["Part5"].Value = true
						FourthFloor["Part6"].Value = true
						FourthFloor["Part7"].Value = false
						FourthFloor["Part8"].Value = false
						FourthFloor["Part9"].Value = false
						FourthFloor["Part10"].Value = false
						FourthFloor["Part11"].Value = false
						FourthFloor["Part12"].Value = false
					elseif workspace.Islands["Impel Base - Floor 4"].Barriers:FindFirstChild("EighthBarrier2") then
						StepCounter = 8
						if workspace.Islands["Impel Base - Floor 4"].Barriers:FindFirstChild("EighthBarrier1") then
							workspace.Islands["Impel Base - Floor 4"].Barriers:FindFirstChild("EighthBarrier1").Transparency =
								0.45
						end
						FourthFloor["Part1"].Value = true
						FourthFloor["Part2"].Value = true
						FourthFloor["Part3"].Value = true
						FourthFloor["Part4"].Value = true
						FourthFloor["Part5"].Value = true
						FourthFloor["Part6"].Value = true
						FourthFloor["Part7"].Value = true
						FourthFloor["Part8"].Value = false
						FourthFloor["Part9"].Value = false
						FourthFloor["Part10"].Value = false
						FourthFloor["Part11"].Value = false
						FourthFloor["Part12"].Value = false
					elseif workspace.Islands["Impel Base - Floor 4"].Barriers:FindFirstChild("NinthZone") then
						StepCounter = 9
						FourthFloor["Part1"].Value = true
						FourthFloor["Part2"].Value = true
						FourthFloor["Part3"].Value = true
						FourthFloor["Part4"].Value = true
						FourthFloor["Part5"].Value = true
						FourthFloor["Part6"].Value = true
						FourthFloor["Part7"].Value = true
						FourthFloor["Part8"].Value = true
						FourthFloor["Part9"].Value = false
						FourthFloor["Part10"].Value = false
						FourthFloor["Part11"].Value = false
						FourthFloor["Part12"].Value = false
					elseif
						(
							not workspace.Effects.Zones:FindFirstChild("End")
							or not workspace.Effects.Zones.End:FindFirstChild("BillboardGui")
						) and not FourthSpawnedBoss
					then
						pcall(function()
							for _, v in pairs(workspace.NPCs:GetChildren()) do
								if v:FindFirstChild("Boss") then
									FourthSpawnedBoss = true
								end
							end
						end)
						StepCounter = 11
						FourthFloor["Part1"].Value = true
						FourthFloor["Part2"].Value = true
						FourthFloor["Part3"].Value = true
						FourthFloor["Part4"].Value = true
						FourthFloor["Part5"].Value = true
						FourthFloor["Part6"].Value = true
						FourthFloor["Part7"].Value = true
						FourthFloor["Part8"].Value = true
						FourthFloor["Part9"].Value = true
						FourthFloor["Part10"].Value = true
						FourthFloor["Part11"].Value = false
						FourthFloor["Part12"].Value = false
					elseif
						(
							workspace.Effects.Zones:FindFirstChild("End")
							and workspace.Effects.Zones.End:FindFirstChild("BillboardGui")
						) or (#workspace.NPCs:GetChildren() == 0 and FourthSpawnedBoss)
					then
						StepCounter = 12
						FourthFloor["Part1"].Value = true
						FourthFloor["Part2"].Value = true
						FourthFloor["Part3"].Value = true
						FourthFloor["Part4"].Value = true
						FourthFloor["Part5"].Value = true
						FourthFloor["Part6"].Value = true
						FourthFloor["Part7"].Value = true
						FourthFloor["Part8"].Value = true
						FourthFloor["Part9"].Value = true
						FourthFloor["Part10"].Value = true
						FourthFloor["Part11"].Value = true
						FourthFloor["Part12"].Value = false
						SecondTime = false
						if (PlayerHumpart.Position - FourthFloor["Part12"].Position).Magnitude <= 5 then
							wait(10)
						end
					end

					if
						workspace.Effects.Zones:FindFirstChild("End")
						and workspace.Effects.Zones.End:FindFirstChild("BillboardGui")
					then
						FourthSpawnedBoss = true
					else
						FourthSpawnedBoss = false
					end

					success, Npc = pcall(GetImpelNpc)
					if not success then
						Npc = nil
					end

					local GetNpcValue = 0

					for _, Npc in pairs(workspace.NPCs:GetChildren()) do
						if
							Npc:FindFirstChild("HumanoidRootPart")
							and (Npc.HumanoidRootPart.Position - PlayerHumpart.Position).Magnitude <= 100
							and Npc.Name ~= "Mini Bunny"
						then
							GetNpcValue += 1
						end
					end

					if Npc then
						targetPosition = detectPart()
						if targetPosition then
							controlTower(CFrame.new(targetPosition), Speed)
							CanTween = true
						end
					elseif
						(Character.Humanoid.Health > 500 or #workspace.NPCs:GetChildren() > 0)
						and Character.Humanoid.Health > 300
						and StepCounter <= 12
						and not FourthFloor["Part" .. StepCounter].Value
						and GetNpcValue <= 0
					then
						FourthFloor["Part" .. StepCounter].Value = true
						LastPlaceTween = "Part" .. StepCounter

						targetPosition = FourthFloor["Part" .. StepCounter].Position
						targetFloorPosition = FourthFloor["Part" .. StepCounter].Position
						local Distance = (targetPosition - PlayerHumpart.Position).magnitude
						local Time = GetTime(Distance, Speed)

						local targetCFrame = CFrame.new(targetPosition)

						tweenWithTeleport(targetCFrame, Speed, selected_Offset)
					end
				elseif
					workspace.Islands:FindFirstChild("Impel Base - Floor 5")
					and not workspace.Islands:FindFirstChild("Impel Base - Finished")
				then
					local floortocheckforinvisiblepart = "Impel Base - Floor 5"
					if
						workspace.Islands:FindFirstChild(floortocheckforinvisiblepart)
						and workspace.Islands[floortocheckforinvisiblepart]:FindFirstChild("invisible")
					then
						workspace.Islands[floortocheckforinvisiblepart].invisible:Destroy()
					end

					local positions = 0
					for _, v in pairs(FifthFloor) do
						if
							targetPosition
							and typeof(targetPosition) == "Vector3"
							and (targetPosition - v.Position).Magnitude > 1000
						then
							positions += 1
						end
						if positions >= 5 then
							Npc = nil
							DisableAllTweens()
						end
					end

					spawn(function()
						if workspace.Islands["Impel Base - Floor 5"].Base:GetChildren()[47]:FindFirstChild("lava") then
							workspace.Islands["Impel Base - Floor 5"].Base:GetChildren()[47].lava:Destroy()
						end
					end)

					if
						workspace.Islands["Impel Base - Floor 5"].Barriers:FindFirstChild("Barrier2")
						or FirstTimeFloor5
					then
						if (PlayerHumpart.Position - FifthFloor["Part1"].Position).Magnitude <= 5 then
							FirstTimeFloor5 = false
						end
						StepCounter = 1
						FifthFloor["Part1"].Value = false
						FifthFloor["Part2"].Value = false
						FifthFloor["Part3"].Value = false
						FifthFloor["Part4"].Value = false
						FifthFloor["Part5"].Value = false
					elseif workspace.Islands["Impel Base - Floor 5"].Barriers:FindFirstChild("Barrier4") then
						StepCounter = 2
						FifthFloor["Part1"].Value = true
						FifthFloor["Part2"].Value = false
						FifthFloor["Part3"].Value = false
						FifthFloor["Part4"].Value = false
						FifthFloor["Part5"].Value = false
					elseif workspace.Islands["Impel Base - Floor 5"].Barriers:FindFirstChild("Barrier5") then
						StepCounter = 3
						FifthFloor["Part1"].Value = true
						FifthFloor["Part2"].Value = true
						FifthFloor["Part3"].Value = false
						FifthFloor["Part4"].Value = false
						FifthFloor["Part5"].Value = false
					elseif workspace.Islands["Impel Base - Floor 5"].Barriers:FindFirstChild("Barrier6") then
						StepCounter = 4
						FifthFloor["Part1"].Value = true
						FifthFloor["Part2"].Value = true
						FifthFloor["Part3"].Value = true
						FifthFloor["Part4"].Value = false
						FifthFloor["Part5"].Value = false
					elseif
						workspace.Islands["Impel Base - Floor 5"].Barriers:FindFirstChild("Barrier7")
						and not workspace.Islands:FindFirstChild("Impel Base - Finished")
					then
						StepCounter = 5
						FifthFloor["Part1"].Value = true
						FifthFloor["Part2"].Value = true
						FifthFloor["Part3"].Value = true
						FifthFloor["Part4"].Value = true
						FifthFloor["Part5"].Value = false
					elseif workspace.Islands:FindFirstChild("Impel Base - Finished") then
						FifthFloor["Part1"].Value = true
						FifthFloor["Part2"].Value = true
						FifthFloor["Part3"].Value = true
						FifthFloor["Part4"].Value = true
						FifthFloor["Part5"].Value = true
						FirstTime = false
					end

					success, Npc = pcall(GetImpelNpc)
					if not success then
						Npc = nil
					end

					if StepCounter > 6 then
						StepCounter = 1
					end

					local GetNpcValue = 0
					for _, npcCheck in pairs(workspace.NPCs:GetChildren()) do
						if
							npcCheck:FindFirstChild("HumanoidRootPart")
							and (npcCheck.HumanoidRootPart.Position - PlayerHumpart.Position).Magnitude <= 150
						then
							GetNpcValue += 1
						end
					end

					if Npc then
						print("NPCCCCC")
						targetPosition = detectPart()
						if targetPosition then
							controlTower(CFrame.new(targetPosition), Speed)
							CanTween = true
						end
					elseif
						Character.Humanoid.Health > 300
						and StepCounter <= 5
						and not workspace.NPCs:FindFirstChild("Warden of Impel Down, Vera")
					then
						print("STEP COUNTERRRR")
						local currentPartPos = FifthFloor["Part" .. StepCounter].Position
						local distToCurrentPart = (PlayerHumpart.Position - currentPartPos).Magnitude

						if distToCurrentPart > 15 then
							LastPlaceTween = "Part" .. StepCounter
							targetFloorPosition = currentPartPos
							targetPosition = currentPartPos
							local targetCFrame = CFrame.new(targetPosition)
							tweenWithTeleport(targetCFrame, Speed, selected_Offset, false)
						elseif GetNpcValue == 0 then
							if not FifthFloor["Part" .. StepCounter].ArrivedAt then
								FifthFloor["Part" .. StepCounter].ArrivedAt = tick()
							end
							local waitedTime = tick() - FifthFloor["Part" .. StepCounter].ArrivedAt
							if waitedTime >= 4 then
								FifthFloor["Part" .. StepCounter].Value = true
								FifthFloor["Part" .. StepCounter].ArrivedAt = nil
							end
							task.wait(0.5)
						else
							FifthFloor["Part" .. StepCounter].ArrivedAt = nil
							for _, npcRetry in pairs(workspace.NPCs:GetChildren()) do
								if
									npcRetry:FindFirstChild("HumanoidRootPart")
									and npcRetry:FindFirstChild("Humanoid")
									and npcRetry.Humanoid.Health > 0
								then
									local npcDist = (npcRetry.HumanoidRootPart.Position - PlayerHumpart.Position).Magnitude
									if npcDist <= 150 then
										targetPosition = npcRetry.HumanoidRootPart.Position + Vector3.new(0, -10, 0)
										targetFloorPosition = currentPartPos
										controlTower(CFrame.new(targetPosition), Speed)
										break
									end
								end
							end
							task.wait(0.3)
						end
					end
				elseif
					workspace:FindFirstChild("Islands") and workspace.Islands:FindFirstChild("Impel Base - Finished")
				then
					if not finishedTime then
						finishedTime = true
						local startTime = tick()
						repeat
							DisableAllTweens()
							wait()
						until tick() - startTime >= 10
					end

					tpedback = false

					targetPosition = Vector3.new(6395.693359375, 653.7778930664062, -27926.84375)
					local Distance = (targetPosition - PlayerHumpart.Position).magnitude
					local Time = GetTime(Distance, Speed)

					task.wait()

					local targetCFrame = CFrame.new(targetPosition)

					local isNightmarePlus = statsFolder.Skills.Kamishiki.Value ~= 20

					local value = statsFolder.Inventory.Inventory.Value
					local MythicalChestCap = value:match('"Mythical Fruit Chest":(%d+)') or 0
					if isnightmarePlus then
						MythicalChestCap = 10 - MythicalChestCap
					else
						MythicalChestCap = tonumber(MythicalChestCap) or 0
						MythicalChestCap = (10 - (MythicalChestValue or 0) - MythicalChestCap)
					end

					local MythicalChest =
						workspace.Islands["Impel Base - Finished"].Models:FindFirstChild("Mythical Fruit Chest")
					if MythicalChest and MythicalChestCap > 0 and not OpenedMythical then
						local text = MythicalChest.Part.ProximityPrompt.ActionText
						local points = extractImpelPoints(text)
						targetPosition = MythicalChest.WorldPivot.Position
						local Distance = (targetPosition - PlayerHumpart.Position).magnitude
						if
							Distance <= 1000
							and tonumber(LocalPlayer.PlayerGui.BattleReportGui.Points.Text) >= tonumber(points)
						then
							local Time = GetTime(Distance, Speed)

							task.wait()

							tweenWithTeleport(targetPosition, Speed)

							task.wait(1)
							if
								MythicalChest:FindFirstChild("Part")
								and MythicalChest.Part:FindFirstChildOfClass("ProximityPrompt")
							then
								local text = MythicalChest.Part.ProximityPrompt.ActionText
								local points = extractImpelPoints(text)
								if tonumber(LocalPlayer.PlayerGui.BattleReportGui.Points.Text) >= tonumber(points) then
									fireProximityPromptSafely(MythicalChest.Part.ProximityPrompt)
									OpenedMythical = true
								end
							end
						else
							OpenedMythical = true
						end
					else
						if not SentWebhook then
							task.wait(3)
							coroutine.wrap(SendWebhook)()
							SentWebhook = true
						end
						targetPosition = Vector3.new(6395.693359375, 653.7778930664062, -27926.84375)
						tweenWithTeleport(targetPosition, Speed)

						task.wait(2)
					end
					task.wait(2)
				end
			end)

			if not success then
				warn("An error occurred:", errorOrReturnValue)
			end
			task.wait()
		end
	end
else
	game:GetService("TeleportService"):Teleport(6360478118)
end
