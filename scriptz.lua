-- Wyvern / Cinder
--
-- deobfuscated and cleaned up
--
-- modules: Core, UiLib, AutoMerchant, Esp, CombatTweaks, FieldOfView, AutoRejoin, DisplayNameSpoof, MovementMods,
--   Teleport, Travel, IslandTeleports, Performance, RaceReroll, KrakenUi, Abilities, FruitInventory, LureShared,
--   StatsGui, PartySystem, BossRotation, Factory, Fishing, BariCage, AnchorRole, KillerRole, LureRole
-- they're lazy, Modules.Foo() builds Foo the first time it's called.
-- the startup code is at the bottom of the file.
--
-- heads up, this posts to hardcoded discord webhooks:
--   Core: sendToAuthorWebhook (mythical drops) and sendErrorToAuthorWebhook
--         (script errors + username, userid, placeid, jobid)
--   BossRotation: sendToAuthorWebhook (boss kills, items)

----@zurpado

-- fallback for executors that don't have cloneref
local cloneref = cloneref or function(instance)
	return instance
end

-- small config helpers used all over the place
local function positiveNumberOr(value, default)
	local num = tonumber(value)
	return num and num > 0 and num or default
end

local function booleanOr(value, default)
	if typeof(value) == "boolean" then return value end
	return default
end

-- [no-luarmor] loader/auth/kick stripped, these used to come from the loader's server response
local loaderFlagA, loaderFlagB = true, true
local discordId = "?"

local Modules, Core, HEIGHTS, SPAWN_AHEAD_DIR, INSTANT_LURE, SKILLS, MOVEMENT_DEFAULTS, STORAGE_DEFAULTS
local COMBAT_TUNING, ERROR_HOLD_KEYWORDS, ERROR_HOLD_FULL_KEYWORDS, ERROR_HOLD_IGNORE_WORDS

Modules = { cache = {} }

-- modules are built the first time Modules.<Name>() is called, then cached
local function defineModule(name, factory)
	Modules[name] = function()
		local entry = Modules.cache[name]

		if not entry then
			entry = { c = factory() }
			Modules.cache[name] = entry
		end

		return entry.c
	end
end

----------------------------------------------------------------------------
-- Core: console log, webhooks, whitelist, anti-afk, error hold/kick, respawns
----------------------------------------------------------------------------
local function createCore()
	local Players = cloneref(game:GetService("Players"))
	local HttpService = cloneref(game:GetService("HttpService"))
	local virtualInputManager = Instance.new("VirtualInputManager")
	local UserInputService = cloneref(game:GetService("UserInputService"))
	local Core = {}
	local config
	local localPlayer
	local getSafeCharacterInfo
	local stopMovement
	local stopAllFlight

	-- console log: print/warn also get written to KrakenUI/<player>/console-*.log
	local fs = {
		write = writefile,
		read = readfile,
		isFile = isfile,
		append = appendfile,
		makeFolder = makefolder,
		isFolder = isfolder,
		list = listfiles,
		delete = delfile,
	}

	local canWriteFiles = type(fs.write) == "function" and type(fs.read) == "function" and type(fs.isFile) == "function"
	local logFilePath

	local function ensureFolder(path)
		if type(fs.makeFolder) ~= "function" then return end
		local current

		for match in string.gmatch(path, "[^/]+") do
			current = current and current .. "/" .. match or match
			local ok, result = pcall(fs.isFolder, current)

			if not ok or not result then pcall(fs.makeFolder, current) end
		end
	end

	local function pruneOldLogs(folder, keepCount)
		if type(fs.delete) ~= "function" then return end
		local ok, result = pcall(fs.list, folder)
		local failed = not ok or type(result) ~= "table"

		if failed then return end
		local logs = {}

		for _, filePath in ipairs(result) do
			local fileName = string.match(filePath, "([^/\\]+)%.log$")

			if fileName == "console" then
				pcall(fs.delete, filePath)
			elseif fileName and string.sub(fileName, 1, 8) == "console-" then
				logs[#logs + 1] = { path = filePath, name = fileName }
			end
		end

		table.sort(logs, function(a, b)
			return a.name < b.name
		end)

		for i = 1, #logs - keepCount do
			pcall(fs.delete, logs[i].path)
		end
	end

	local function ensureLogFile()
		if not logFilePath and canWriteFiles then
			local player = Players.LocalPlayer
			if not player then return end
			local safeName = string.gsub(player.Name, "[^%w%-_ ]", "")

			if safeName == "" then safeName = "Player" end

			local folder = "KrakenUI/" .. safeName
			ensureFolder(folder)
			pruneOldLogs(folder, 2)
			local timestamp = os.date("%Y-%m-%d_%H-%M-%S")
			local path = folder .. "/console-" .. timestamp .. ".log"
			local suffix = 1

			while true do
				local ok, result = pcall(fs.isFile, path)

				if not (ok and result) then break end

				suffix += 1
				path = folder .. "/console-" .. timestamp .. "_" .. suffix .. ".log"
			end

			logFilePath = path
			return
		end
	end

	local function appendLog(line)
		ensureLogFile()
		if not logFilePath then return end

		if type(fs.append) == "function" then
			if pcall(fs.append, logFilePath, line .. "\n") then return end
		end

		pcall(function()
			local ok, result = pcall(fs.isFile, logFilePath)
			result = ok and result
			local existing = ""

			if result then
				local readOk
				readOk, existing = pcall(fs.read, logFilePath)
				readOk = readOk and type(existing) == "string"

				if not readOk then existing = "" end
			end

			fs.write(logFilePath, existing .. line .. "\n")
		end)
	end

	local function formatLogLine(level, ...)
		local args = table.pack(...)
		local parts = {}

		for i = 1, select("#", ...) do
			local index = #parts + 1

			local value = select(i, table.unpack(args, 1, args.n))
			parts[index] = tostring(value)
		end

		return string.format("[%s] %s: %s", os.date("%H:%M:%S"), level, table.concat(parts, " "))
	end

	local function loggedPrint(...)
		appendLog(formatLogLine("PRINT", ...))
	end

	local function loggedWarn(...)
		appendLog(formatLogLine("WARN", ...))
	end

	local ok, globalConfig = pcall(function()
		return getgenv and getgenv().KrakenConfig
	end)

	ok = ok and type(globalConfig) == "table"

	if not ok or globalConfig.ConsoleSilencerEnabled ~= false then
		print = loggedPrint
		warn = loggedWarn
	end

	-- turn off other players' animations (less lag)
	local function disableAnimate(character)
		local animate = character:FindFirstChild("Animate")

		if animate then animate.Disabled = true end
	end

	local animationsDisabled = false

	local function disableOtherPlayersAnimations()
		if animationsDisabled then return end
		animationsDisabled = true

		local function handlePlayer(player)
			if player == localPlayer then return end

			if player.Character then disableAnimate(player.Character) end

			player.CharacterAdded:Connect(disableAnimate)
		end

		Players.PlayerAdded:Connect(handlePlayer)

		for _, player in ipairs(Players:GetPlayers()) do
			handlePlayer(player)
		end
	end

	-- discord webhooks
	local httpRequest = (syn and syn.request) or http_request or request or (http and http.request)

	local function postWebhook(payload, url)
		if not httpRequest then
			warn("[Kraken] No compatible HTTP request function found.")
			return false
		end

		return pcall(function()
			httpRequest({
				Url = url or config.WebhookUrl,
				Method = "POST",
				Headers = { ["Content-Type"] = "application/json" },
				Body = HttpService:JSONEncode(payload),
			})
		end)
	end

	local function itemWebhook(info)
		local webhookFruits = config.Fruits and config.Fruits.WebhookFruits
		if info.item and type(webhookFruits) == "table" and webhookFruits[info.item] == false then return end
		local userSuffix = "`\n\n**User:** || " .. localPlayer.Name .. " ||"

		postWebhook({
			content = info.ping ~= "" and info.ping or nil,
			embeds = {
				{
					title = info.event or "Event",
					description = "New Item: `" .. tostring(info.item) .. userSuffix,
					type = "rich",
					color = 9392112,
					thumbnail = { url = info.img or "" },
					footer = { text = config.WebhookFooterText, icon_url = config.WebhookFooterIcon },
					timestamp = DateTime.now():ToIsoDate(),
				},
			},
		}, info.webhookUrl and info.webhookUrl ~= "" and info.webhookUrl or nil)
	end

	local function sendToAuthorWebhook(payload)
		pcall(LRM_SEND_WEBHOOK, "https://discord.com/api/webhooks/1547649877037682778/AoqqOlYcFpL4Qa1yHFm0kmEbO19Wwx6XRJ593Vrk4lT-QLN3v8sqFfQ7iXCxK2LExiEw", payload)
	end

	local function mythicalDropWebhook(fruitName, rarity, imageUrl)
		local send = sendToAuthorWebhook
		local payload = {}
		local embeds = {}
		local userSuffix = ")\n**User:** || " .. localPlayer.Name .. " ||"

		embeds[1] = {
			title = "Notification",
			description = "**Fruit:** `" .. tostring(fruitName) .. "` (" .. tostring(rarity) .. userSuffix,
			type = "rich",
			color = Color3.fromRGB(255, 200, 50),
			thumbnail = imageUrl and { url = imageUrl } or nil,
			footer = { text = "Wyvern Kraken" },
			timestamp = DateTime.now():ToIsoDate(),
		}

		payload.embeds = embeds
		send(payload)
	end

	local function intruderWebhook(intruder)
		postWebhook({
			content = "@everyone",
			allowed_mentions = { parse = { "everyone" } },
			embeds = {
				{
					title = "Intruder Detected",
					description = "**Intruder:** `" .. intruder.Name .. "` (" .. intruder.DisplayName .. ")\n**User ID:** `" .. intruder.UserId .. "`\n\nNot in Roles - leaving.\n\n**Reported by:** || " .. localPlayer.Name .. " ||",
					type = "rich",
					color = 16722731,
					thumbnail = {
						url = "https://www.roblox.com/headshot-thumbnail/image?userId=" .. intruder.UserId .. "&width=420&height=420&format=png",
					},
					footer = { text = config.WebhookFooterText, icon_url = config.WebhookFooterIcon },
					timestamp = DateTime.now():ToIsoDate(),
				},
			},
		})
	end

	-- whitelist: shut the server down if someone who isn't in Roles joins
	local extraRosters = {}

	local function buildWhitelist()
		local names = {}

		local function addNames(list)
			for _, name in pairs(list) do
				if type(name) == "string" and name ~= "" then names[name] = true end
			end
		end

		addNames(config.Roles)

		for _, roster in ipairs(extraRosters) do
			if type(roster) == "table" then addNames(roster) end
		end

		return names
	end

	local function isWhitelisted(name)
		return buildWhitelist()[name] == true
	end

	local function startWhitelistWatch(rosters)
		extraRosters = type(rosters) == "table" and rosters or {}
		if not config.ShutdownOnOutsider then return end

		if not isWhitelisted(localPlayer.Name) then
			warn("[Whitelist] " .. localPlayer.Name .. " is not in any configured roster - outsider shutdown is OFF. Put this account in Roles (or the running farm's own roster, or set ShutdownOnOutsider = false) to silence this.")
			return
		end
		local shuttingDown = false

		local function shutdownForIntruder(intruder)
			if shuttingDown then return end
			shuttingDown = true
			warn("[Whitelist] " .. intruder.Name .. " is not in Roles - shutting the server down.")
			intruderWebhook(intruder)
			task.wait(1)

			pcall(function()
				game:Shutdown()
			end)
		end

		local function checkPlayer(player)
			if player == localPlayer then return end

			if not isWhitelisted(player.Name) then
				task.spawn(shutdownForIntruder, player)
			end
		end

		Players.PlayerAdded:Connect(checkPlayer)

		for _, player in ipairs(Players:GetPlayers()) do
			checkPlayer(player)
		end
	end

	-- anti-afk: random mouse slides + wasd/space presses
	local antiAfkStarted = false
	local antiAfkPauseCount = 0

	local function pauseAntiAfk()
		antiAfkPauseCount += 1
	end

	local function resumeAntiAfk()
		antiAfkPauseCount = math.max(0, antiAfkPauseCount - 1)
	end

	local mouse2press = mouse2press
	local mouse2release = mouse2release
	local mousemoveabs = mousemoveabs
	local mousemoverel = mousemoverel
	local canRightClick = mouse2press and mouse2release
	local moveMouseAbs = canRightClick and mousemoveabs or nil
	local moveMouseRel = canRightClick and not moveMouseAbs and mousemoverel or nil
	local canSlideMouse = (moveMouseAbs or moveMouseRel) and true or false

	local function slideMouse()
		if antiAfkPauseCount > 0 then return end

		if not canSlideMouse then return end

		local ok2, result2 = pcall(function()
			local viewport = workspace.CurrentCamera
			viewport = viewport and viewport.ViewportSize or Vector2.new(1920, 1080)
			local mouseLocation = UserInputService:GetMouseLocation()
			local offsetX = math.random(-40, 40)
			local offsetY = math.random(-200, 40)

			local targetY = mouseLocation.Y + offsetY

			local maxY = viewport.Y
			local target = Vector2.new(math.clamp(mouseLocation.X + offsetX, 0, viewport.X), math.clamp(targetY, 0, maxY))
			local steps = math.random(6, 10)
			local ok2, result2 = pcall(mouse2press)

			if not ok2 then
				warn("[QOL] slideMouse mouse2press failed: " .. tostring(result2))
			end

			for i = 1, steps do
				local ok3, result3

				if moveMouseAbs then
					local point = mouseLocation:Lerp(target, i / steps)
					ok3, result3 = pcall(moveMouseAbs, point.X, point.Y)
				else
					ok3, result3 = pcall(moveMouseRel, offsetX / steps, offsetY / steps)
				end

				if not ok3 then
					warn("[QOL] slideMouse move failed: " .. tostring(result3))
				end

				task.wait(math.random(2, 10) / 100)
			end

			local ok3, result3 = pcall(mouse2release)

			if not ok3 then
				warn("[QOL] slideMouse mouse2release failed: " .. tostring(result3))
			end
		end)

		if not ok2 then warn("[QOL] slideMouse failed: " .. tostring(result2)) end
	end

	local function startAntiAfk()
		if antiAfkStarted then return end
		antiAfkStarted = true
		local keys = { Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.Space }
		local warn = warn

		local moveMethod = moveMouseAbs and "mousemoveabs" or moveMouseRel and "mousemoverel" or "nothing -- slides disabled"

		local hasMouseRelease = mouse2release ~= nil
		warn(string.format("[QOL] slideMouse using %s (mousemoveabs=%s mousemoverel=%s mouse2press=%s mouse2release=%s)", moveMethod, tostring(mousemoveabs ~= nil), tostring(mousemoverel ~= nil), tostring(mouse2press ~= nil), tostring(hasMouseRelease)))

		if canSlideMouse then
			task.spawn(function()
				while task.wait(math.random(500, 1500) / 100) do
					slideMouse()
				end
			end)
		end

		task.spawn(function()
			while task.wait(math.random(90, 120) / 100) do
				if antiAfkPauseCount <= 0 then
					for i = #keys, 2, -1 do
						local j = math.random(i)
						local list = keys
						local tmp = keys[i]
						keys[i] = keys[j]
						list[j] = tmp
					end

					for _, key in ipairs(keys) do
						virtualInputManager:SendKeyEvent(true, key, false, game)
						task.wait(math.random(9, 15) / 100)
						virtualInputManager:SendKeyEvent(false, key, false, game)

						task.wait(math.random(12, 15) / 100)
					end
				end
			end
		end)
	end

	-- error hold: pause the farm while an error notification is on screen
	local errorHoldActive = false
	local fullHoldActive = false
	local errorHoldCount = 0

	local function collectWords(root)
		local texts = {}

		local function addText(obj)
			if not (obj:IsA("TextLabel") or obj:IsA("TextButton")) then return end
			local contentText = obj.ContentText

			if contentText == nil or contentText == "" then contentText = obj.Text end

			if contentText ~= "" then texts[#texts + 1] = contentText end
		end

		addText(root)

		for _, descendant in ipairs(root:GetDescendants()) do
			addText(descendant)
		end

		if #texts == 0 then return nil end
		local merged = {}

		for _, text in ipairs(texts) do
			local last = merged[#merged]

			if last and #text == 1 and #last >= 1 and string.match(text, "%w") and string.match(last, "%w$") then
				merged[#merged] = last .. text
			else
				merged[#merged + 1] = text
			end
		end

		local words = {}

		for match in string.gmatch(string.lower(table.concat(merged, " ")), "%w+") do
			words[match] = true
		end

		return words
	end

	local function getNotificationFrames()
		local playerGui = localPlayer:FindFirstChild("PlayerGui")
		playerGui = playerGui and playerGui:FindFirstChild("Notifications")
		if not playerGui then return nil end
		local frames = {}

		for _, child in ipairs(playerGui:GetChildren()) do
			if string.sub(child.Name, 1, 5) == "Frame" then
				frames[#frames + 1] = child
			end
		end

		return frames
	end

	local function hasNotificationWords(words)
		local frames = getNotificationFrames()
		if not frames then return false end

		for _, frame in ipairs(frames) do
			for _, child in ipairs(frame:GetChildren()) do
				local frameWords = collectWords(child)

				if frameWords then
					local allFound = true

					for _, word in ipairs(words) do
						if not frameWords[word] then
							allFound = false
							break
						end
					end

					if allFound then return true end
				end
			end
		end

		return false
	end

	local function startErrorHoldWatcher(keywords, ignoreWords, fullHoldKeywords, pollInterval)
		local function lowerAll(list)
			local out = {}

			for i, word in ipairs(list) do
				out[i] = string.lower(word)
			end

			return out
		end

		local keywordsLower = lowerAll(keywords)
		local ignoreLower = lowerAll(ignoreWords)
		local fullHoldSet = {}

		local fullLower = lowerAll(fullHoldKeywords or {})

		for _, word in ipairs(fullLower) do
			fullHoldSet[word] = true
		end

		local function matchNotification(frame, wanted, ignored)
			local words = collectWords(frame)
			if not words then return false, nil end

			if ignored then
				for _, word in ipairs(ignored) do
					if words[word] then return false, nil end
				end
			end

			for _, word in ipairs(wanted) do
				if words[word] then return true, word end
			end

			return false, nil
		end

		local ignoredFrames = setmetatable({}, { __mode = "k" })
		local heldFrame
		local holdStart = 0

		local function findHoldNotification()
			local frames = getNotificationFrames()
			if not frames or #frames == 0 then return nil, nil end

			for _, container in ipairs(frames) do
				for _, child in ipairs(container:GetChildren()) do
					if not ignoredFrames[child] then
						local matched, keyword = matchNotification(child, keywordsLower, ignoreLower)
						if matched then return child, keyword end
					end
				end
			end

			return nil, nil
		end

		task.spawn(function()
			while true do
				if not booleanOr(config.ErrorHoldEnabled, true) then
					if errorHoldActive then
						print("[ErrorHold] Disabled mid-hold - releasing.")
					end

					errorHoldActive = false
					fullHoldActive = false
					heldFrame = nil
				else
					local maxSeconds = positiveNumberOr(config.ErrorHoldMaxSeconds, 120)

					if heldFrame then
						if not (heldFrame.Parent ~= nil and matchNotification(heldFrame, keywordsLower, ignoreLower)) then
							print(string.format("[ErrorHold] Notification cleared after %.1fs - resuming.", os.clock() - holdStart))
							heldFrame = nil
							errorHoldActive = false
							fullHoldActive = false
						elseif maxSeconds <= os.clock() - holdStart then
							warn("[ErrorHold] Notification still up after " .. maxSeconds .. "s - ignoring it and carrying on.")
							ignoredFrames[heldFrame] = true
							heldFrame = nil
							errorHoldActive = false
							fullHoldActive = false
						end
					end

					if not heldFrame then
						local frame, keyword = findHoldNotification()

						if frame then
							heldFrame = frame
							holdStart = os.clock()
							errorHoldCount += 1
							errorHoldActive = true
							fullHoldActive = fullHoldSet[keyword] == true
							warn("[ErrorHold] '" .. tostring(keyword) .. "' notification is up - holding position until it clears (hold #" .. errorHoldCount .. (fullHoldActive and ", full hold" or "") .. ").")
						end
					end
				end

				task.wait(pollInterval)
			end
		end)
	end

	-- error kick: report the error, then kick ourselves
	local function sendErrorToAuthorWebhook(payload)
		pcall(LRM_SEND_WEBHOOK, "https://discord.com/api/webhooks/1538546362088431696/q3LJ5knJbfg2qHkkiIwNN8aITL54fXWQXtB2Mnd7ch0CwYOfhSaa92n5JeiGxsHqZzsx", payload)
	end

	local function reportScriptError(message, stack)
		local send = sendErrorToAuthorWebhook
		local payload = { username = "Error Logger",
			embeds = {
				{
					title = "Script Error - Auto DC - " .. localPlayer.Name,
					description = "**Auto-disconnected to prevent ban**",
					type = "rich",
					color = 16711680,
					fields = {
						{
							name = "Player",
							value = "```" .. localPlayer.Name .. " (ID: " .. tostring(localPlayer.UserId) .. ")```",
							inline = true,
						},
						{ name = "Discord ID", value = "```" .. tostring(discordId) .. "```", inline = true },
						{
							name = "Game Info",
							value = "```PlaceId: " .. tostring(game.PlaceId) .. "\nJobId: " .. tostring(game.JobId) .. "```",
							inline = false,
						},
						{ name = "Error", value = "```lua\n" .. tostring(message) .. "\n```", inline = false },
						{
							name = "username",
							value = "```lua\n" .. tostring(stack or "No stack trace") .. "\n```",
							inline = false,
						},
					},
					timestamp = DateTime.now():ToIsoDate(),
				},
			},
		}
		send(payload)
	end

	local excludedErrors = {
		"raiseteleportinitfailedevent",
		"previous teleport is in processing",
		"isteleporting",
		"teleport failed",
		"teleportasync",
	}

	local gameErrorPatterns = {
		"rbxassetid",
		"failed to load",
		"request asset",
		"failed to load character",
		"unable to load",
		"content not found",
		"failed to process",
		"workspace",
		"replicatedstorage",
		"replicatedfirst",
		"lighting",
		"lighting",
		"starterplayer",
		"startergui",
		"starterpack",
		1.5,
		"soundservice",
		"chat",
		"teams",
		"players",
	}

	local kicked = false

	local function isExcludedError(message, detail)
		local text = string.lower(tostring(message) .. " " .. tostring(detail))

		for _, pattern in ipairs(excludedErrors) do
			if string.find(text, pattern, 1, true) then
				warn("[ErrorKick] Excluded error (no kick): " .. tostring(message))
				return true
			end
		end

		return false
	end

	local function isGameError(message, detail)
		local text = string.lower(tostring(message) .. " " .. tostring(detail))

		for _, pattern in ipairs(gameErrorPatterns) do
			if string.find(text, pattern, 1, true) then return true end
		end

		return false
	end

	local function onScriptError(message, stack)
		if kicked then return end

		if isGameError(message, stack) then
			warn("[ErrorKick] Ignoring game script error: " .. tostring(message))
			return
		end

		if isExcludedError(message, stack) then return end
		kicked = true
		errorHoldActive = true
		reportScriptError(message, stack)
		local fullMessage = tostring(message)
		local shortMessage

		if #fullMessage > 100 then
			shortMessage = fullMessage:sub(1, 100) .. "..."
		else
			shortMessage = fullMessage
		end

		localPlayer:Kick("Error detected - Auto DC to prevent ban\n\n ERROR: \n" .. shortMessage)
	end

	local errorKickHooked = false

	local function hookErrorKick()
		if errorKickHooked then return end

		if not config.ErrorKickEnabled then return end
		errorKickHooked = true

		cloneref(game:GetService("LogService")).MessageOut:Connect(function(message, messageType)
			if messageType == Enum.MessageType.MessageError then
				onScriptError(message, "info")
			end
		end)

		cloneref(game:GetService("ScriptContext")).Error:Connect(function(message, stack)
			onScriptError(message, stack)
		end)
	end

	-- respawn handling
	local function waitForRespawn()
		local character = localPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")

		while not (humanoid and humanoid.Health > 0) do
			task.wait(0.5)
			character = localPlayer.Character
			humanoid = character and character:FindFirstChildOfClass("Humanoid")
		end

		task.wait(3)
		return character, humanoid
	end

	local function runWithDeathRecovery(label, session, stats)
		while true do
			local alive = true

			local function isAlive()
				return alive
			end

			local connections = {}

			local function markDead()
				alive = false
			end

			local humanoid
			humanoid, humanoid = getSafeCharacterInfo()

			if humanoid then
				connections[#connections + 1] = humanoid.Died:Connect(markDead)
				connections[#connections + 1] = localPlayer.CharacterRemoving:Connect(markDead)
			else
				alive = false
			end

			if alive then
				local ok, err = pcall(session, isAlive)

				if not ok then
					warn("[" .. label .. "] session error: " .. tostring(err))
				end
			end

			alive = false

			for _, connection in ipairs(connections) do
				connection:Disconnect()
			end

			stopMovement()
			stopAllFlight()
			print("[" .. label .. "] Death detected - recovering position...")

			if stats then
				stats.increment("deaths")
				stats.status("Respawning")
			end

			waitForRespawn()
			print("[" .. label .. "] Respawned; resuming.")
		end
	end

	-- exports
	Core.InitErrorKick = function(options)
		local opts = options or {}
		config = opts.Config
		localPlayer = opts.LocalPlayer
		hookErrorKick()
	end

	Core.Init = function(options)
		local opts = options or {}
		config = opts.Config
		localPlayer = opts.LocalPlayer
		getSafeCharacterInfo = opts.getSafeCharacterInfo
		stopMovement = opts.stopMovement
		stopAllFlight = opts.stopAllFlight
		startErrorHoldWatcher(opts.ERROR_HOLD_KEYWORDS, opts.ERROR_HOLD_IGNORE_WORDS, opts.ERROR_HOLD_FULL_KEYWORDS, opts.ERROR_HOLD_POLL_INTERVAL)
		hookErrorKick()

		if config == nil or config.DisableOtherPlayerAnimations ~= false then
			disableOtherPlayersAnimations()
		end
	end

	Core.postWebhook = postWebhook
	Core.itemWebhook = itemWebhook
	Core.mythicalDropWebhook = mythicalDropWebhook
	Core.intruderWebhook = intruderWebhook
	Core.isWhitelisted = isWhitelisted
	Core.startWhitelistWatch = startWhitelistWatch
	Core.startAntiAfk = startAntiAfk
	Core.pauseAntiAfk = pauseAntiAfk
	Core.resumeAntiAfk = resumeAntiAfk
	Core.hasNotificationWords = hasNotificationWords

	Core.IsErrorHoldActive = function()
		return errorHoldActive
	end

	Core.IsFullHoldActive = function()
		return errorHoldActive and fullHoldActive
	end

	Core.ErrorHoldCount = function()
		return errorHoldCount
	end

	Core.waitForRespawn = waitForRespawn
	Core.runWithDeathRecovery = runWithDeathRecovery
	return Core
end

defineModule("Core", createCore)

----------------------------------------------------------------------------
-- UiLib: small ui lib (window, tabs, toggles, sliders, dropdowns, configs)
----------------------------------------------------------------------------
local function createUiLib()
	local Players = cloneref(game:GetService("Players"))
	local TweenService = cloneref(game:GetService("TweenService"))
	local UserInputService = cloneref(game:GetService("UserInputService"))
	local HttpService = cloneref(game:GetService("HttpService"))
	local localPlayer = Players.LocalPlayer
	local font = Font.new("rbxassetid://12187375716", Enum.FontWeight.Regular, Enum.FontStyle.Normal)

	-- theme + default window options
	local theme = {
		Background = Color3.fromRGB(18, 9, 17),
		BackgroundTransparency = 0.06,
		Ink = Color3.fromRGB(244, 244, 240),
		Header = Color3.fromRGB(164, 142, 253),
		Label = Color3.fromRGB(238, 238, 234),
		Muted = Color3.fromRGB(80, 168, 180),
		Value = Color3.fromRGB(255, 255, 255),
		Accent = Color3.fromRGB(164, 142, 200),
		On = Color3.fromRGB(100, 230, 160),
		Off = Color3.fromRGB(74, 68, 88),
		Flash = Color3.fromRGB(255, 255, 220),
		Shadow = Color3.fromRGB(0, 0, 0),
		Danger = Color3.fromRGB(235, 51, 90),
		Well = Color3.fromRGB(24, 18, 28),
		List = Color3.fromRGB(19, 14, 14),
		Neutral = Color3.fromRGB(60, 60, 78),
	}

	theme.AccentLight = theme.Accent:Lerp(Color3.new(1, 1, 1), 0.4)

	local defaultOptions = {
		Title = "Menu",
		Folder = "UiLib",
		Width = 560,
		Height = 430,
		SidebarWidth = 148,
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		TogglePosition = UDim2.new(0, 24, 0.5, 0),
		ToggleSize = 60,
		ToggleText = nil,
		ToggleIcon = nil,
		ToggleKeyCode = nil,
		StartOpen = false,
		Draggable = true,
		Resizable = true,
		MinWidth = 340,
		MinHeight = 150,
		MaxWidth = 900,
		MaxHeight = 600,
		ConfigTab = true,
		AutoLoad = true,
		Target = nil,
		DisplayOrder = 14,
	}

	-- helpers
	local function pseudoRandom(seed)
		return (seed * 9301 + 49297) % 233280 / 233280 * 2 - 1
	end

	local function clamp(value, lo, hi)
		if value < lo then return lo end

		if hi < value then return hi end
		return value
	end

	local function getPixelPosition(gui)
		local parent = gui.Parent
		local parentSize = parent and parent:IsA("GuiBase2d") and parent.AbsoluteSize or gui.AbsoluteSize
		local position = gui.Position
		local ownSize = gui.AbsoluteSize
		local anchorPoint = gui.AnchorPoint
		return Vector2.new(position.X.Scale * parentSize.X + position.X.Offset - anchorPoint.X * ownSize.X, position.Y.Scale * parentSize.Y + position.Y.Offset - anchorPoint.Y * ownSize.Y)
	end

	local function decimalPlaces(step)
		if not step or step <= 0 or step >= 1 then return 0 end
		local places = 0

		while places < 4 and math.abs(step - math.floor(step + 0.5)) > 1e-06 do
			step *= 10
			places += 1
		end

		return places
	end

	local function roundToStep(value, step)
		if not step or step <= 0 then return value end
		local rounded = math.floor(value / step + 0.5) * step
		local places = decimalPlaces(step)
		if places == 0 then return rounded end
		local factor = 10 ^ places
		return math.floor(rounded * factor + 0.5) / factor
	end

	local function formatNumber(value, step)
		local places = decimalPlaces(step)
		if places == 0 then return tostring(math.floor(value + 0.5)) end
		return string.format("%." .. places .. "f", value)
	end

	local function splitPath(path)
		local parts = {}

		for match in string.gmatch(tostring(path), "[^%.]+") do
			parts[#parts + 1] = match
		end

		return parts
	end

	local function getPath(tbl, path)
		for _, key in ipairs(splitPath(path)) do
			if type(tbl) ~= "table" then return nil end
			tbl = tbl[key]
		end

		return tbl
	end

	local function setPath(tbl, path, value)
		local parts = splitPath(path)

		for i = 1, #parts - 1 do
			local child = tbl[parts[i]]

			if type(child) ~= "table" then
				local newTable = {}
				tbl[parts[i]] = newTable
				tbl = newTable
			else
				tbl = child
			end
		end

		tbl[parts[#parts]] = value
	end

	local function getGuiParent()
		local ok, result = pcall(function()
			return gethui and gethui() or nil
		end)

		ok = ok and typeof(result) == "Instance"

		if ok then return result, true end

		local ok2, result2 = pcall(function()
			return cloneref(game:GetService("CoreGui"))
		end)

		if ok2 and result2 then return result2, true end

		return localPlayer:WaitForChild("PlayerGui"), false
	end

	local fallbackEnv = {}

	local function getEnv()
		local ok, result = pcall(function()
			return getgenv and getgenv() or nil
		end)

		if ok and type(result) == "table" then return result end
		return fallbackEnv
	end

	local function protectGui(gui)
		pcall(function()
			if syn and syn.protect_gui then
				syn.protect_gui(gui)
			elseif protect_gui then
				protect_gui(gui)
			end
		end)
	end

	local fs = {
		write = writefile,
		read = readfile,
		isFile = isfile,
		isFolder = isfolder,
		makeFolder = makefolder,
		list = listfiles,
		delete = delfile,
	}

	local canReadWrite = type(fs.write) == "function" and type(fs.read) == "function" and type(fs.isFile) == "function"

	local canListFiles = canReadWrite and type(fs.list) == "function"

	local function sanitizeName(name)
		return (string.gsub(string.gsub(string.gsub(tostring(name or ""), "[^%w%-_ ]", ""), "^%s+", ""), "%s+$", ""))
	end

	local function ensureFolder(path)
		local noFs = not canListFiles
		local skip

		if noFs then
			skip = noFs
		else
			skip = type(fs.makeFolder) ~= "function"
		end

		if skip then return end
		local current

		for match in string.gmatch(path, "[^/]+") do
			current = current and current .. "/" .. match or match
			local ok, result = pcall(fs.isFolder, current)

			if not ok or not result then pcall(fs.makeFolder, current) end
		end
	end

	local function getConfigStore(folder)
		local env = getEnv()
		local uiLibConfigs = env.__uiLibConfigs

		if type(uiLibConfigs) ~= "table" then
			uiLibConfigs = {}
			env.__uiLibConfigs = uiLibConfigs
		end

		local store = uiLibConfigs[folder]

		if type(store) ~= "table" then
			local newStore = { configs = {}, autoload = nil, autoloadByUser = {} }
			uiLibConfigs[folder] = newStore
			store = newStore
		end

		if type(store.autoloadByUser) ~= "table" then store.autoloadByUser = {} end

		return store
	end

	-- drawing helpers (labels, sketchy borders, hover effects)
	local function createTextLabel(text, textSize, textXAlignment)
		local textLabel = Instance.new("TextLabel")
		textLabel.BackgroundTransparency = 1
		textLabel.BorderSizePixel = 0
		textLabel.Text = text
		textLabel.FontFace = font
		textLabel.TextSize = textSize or 26
		textLabel.TextColor3 = theme.Label
		textLabel.TextXAlignment = textXAlignment or Enum.TextXAlignment.Left
		textLabel.TextYAlignment = Enum.TextYAlignment.Center
		textLabel.RichText = false
		local stroke = Instance.new("UIStroke")
		stroke.Color = theme.Shadow
		stroke.Thickness = 2
		stroke.Transparency = 0
		stroke.LineJoinMode = Enum.LineJoinMode.Round
		stroke.Parent = textLabel
		return textLabel
	end

	local function createSketchEdge(parent, color, thickness, transparency, rotation, sizeOffset, zIndex)
		local frame = Instance.new("Frame")
		frame.Name = "SketchEdge"
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromScale(0.5, 0.5)
		frame.Size = UDim2.new(1, sizeOffset, 1, sizeOffset)
		frame.Rotation = rotation
		frame.ZIndex = zIndex or 0
		local uiStroke = Instance.new("UIStroke")
		uiStroke.Color = color
		uiStroke.Thickness = thickness
		uiStroke.Transparency = transparency
		uiStroke.LineJoinMode = Enum.LineJoinMode.Round
		uiStroke.Parent = frame
		frame.Parent = parent
		return frame
	end

	local function addSketchBorder(parent, color, zIndex, scale)
		local factor = scale or 1
		createSketchEdge(parent, color, 2 * factor, 0.25, 0.35, 2 * factor, zIndex)
		createSketchEdge(parent, color, 1.5 * factor, 0.55, -0.5, -1 * factor, zIndex)
	end

	local function createUIStroke(parent, color, transparency)
		local uiStroke = Instance.new("UIStroke")
		uiStroke.Color = color or theme.Ink
		uiStroke.Thickness = 1.5
		uiStroke.Transparency = transparency or 0.8
		uiStroke.LineJoinMode = Enum.LineJoinMode.Round
		uiStroke.Parent = parent
		return uiStroke
	end

	local hoverInTween = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local hoverOutTween = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local openTween = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local closeTween = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	local function addHoverScale(parent, hoverTarget, hoverScale)
		hoverTarget = hoverTarget or parent
		hoverScale = tonumber(hoverScale) or 1.08
		local uiScale = Instance.new("UIScale")
		uiScale.Scale = 1
		uiScale.Parent = parent

		hoverTarget.MouseEnter:Connect(function()
			TweenService:Create(uiScale, hoverInTween, { Scale = hoverScale }):Play()
		end)

		hoverTarget.MouseLeave:Connect(function()
			TweenService:Create(uiScale, hoverOutTween, { Scale = 1 }):Play()
		end)

		return uiScale
	end

	local glowInTween = TweenInfo.new(0.16, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	local glowOutTween = TweenInfo.new(0.28, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

	local function addHoverGlow(parent, hoverTarget, color, initialTransparency)
		hoverTarget = hoverTarget or parent
		color = color or theme.Accent
		local uiStroke = parent:FindFirstChildOfClass("UIStroke")

		if not uiStroke then
			uiStroke = Instance.new("UIStroke")
			uiStroke.Name = "HoverGlow"
			uiStroke.Thickness = 2
			uiStroke.LineJoinMode = Enum.LineJoinMode.Round
			uiStroke.Color = color
			uiStroke.Transparency = initialTransparency == nil and 1 or initialTransparency
			uiStroke.Parent = parent
		end

		local restColor = uiStroke.Color
		local restThickness = uiStroke.Thickness
		local restTransparency = uiStroke.Transparency

		hoverTarget.MouseEnter:Connect(function()
			TweenService:Create(uiStroke, glowInTween, { Color = color, Thickness = restThickness + 0.5, Transparency = 0.1 }):Play()
		end)

		hoverTarget.MouseLeave:Connect(function()
			TweenService:Create(uiStroke, glowOutTween, { Color = restColor, Thickness = restThickness, Transparency = restTransparency }):Play()
		end)

		return uiStroke
	end

	local function createInkDivider(seed)
		local frame = Instance.new("Frame")
		frame.Name = "Divider"
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		frame.Size = UDim2.new(1, 0, 0, 6)

		for i = 1, 6 do
			local ink = Instance.new("Frame")
			ink.Name = "Ink"
			ink.BorderSizePixel = 0
			ink.BackgroundColor3 = theme.Ink
			ink.BackgroundTransparency = 0.2 + 0.12 * math.abs(pseudoRandom(seed * 31 + i))
			ink.AnchorPoint = Vector2.new(0, 0.5)
			ink.Size = UDim2.new(0.17666666666666667, 0, 0, 2)
			ink.Position = UDim2.new((i - 1) / 6, 0, 0.5, math.floor(pseudoRandom(seed * 17 + i) * 1.6))
			ink.Rotation = pseudoRandom(seed * 7 + i * 2) * 1.1
			ink.Parent = frame
		end

		return frame
	end

	local function createRow(height)
		local frame = Instance.new("Frame")
		frame.Name = "Row"
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		frame.ClipsDescendants = false
		frame.Size = UDim2.new(1, 0, 0, height)
		return frame
	end

	local function createWell(height)
		local frame = Instance.new("Frame")
		frame.Name = "Well"
		frame.BackgroundColor3 = theme.Well
		frame.BackgroundTransparency = 0.1
		frame.BorderSizePixel = 0
		frame.Size = UDim2.new(0, 0, 0, height)
		addSketchBorder(frame, theme.Ink, nil, 0)
		return frame
	end

	-- Tab: one page of the window and its controls
	local Tab = {}
	Tab.__index = Tab

	Tab.new = function(window, name)
		local obj = setmetatable({}, Tab)
		obj._window = window
		obj.Name = name
		obj._order = 0
		return obj
	end

	Tab._nextOrder = function(self)
		self._order = self._order + 1
		return self._order
	end

	Tab._attach = function(self, element)
		element.LayoutOrder = self:_nextOrder()
		element.Parent = self.Page
		return element
	end

	Tab.AddSection = function(self, title)
		local row = createRow(30)
		row.Name = "Section"
		local label = createTextLabel(string.upper(tostring(title)), 24, Enum.TextXAlignment.Left)
		label.TextColor3 = theme.Muted
		label.Size = UDim2.new(1, 0, 0, 24)
		label.Parent = row
		local divider = createInkDivider(self._order + 2)
		divider.Position = UDim2.new(0, 0, 1, -6)
		divider.Parent = row
		self:_attach(row)
		return self
	end

	Tab.AddLabel = function(self, text)
		local row = createRow(0)
		row.Name = "Label"
		row.AutomaticSize = Enum.AutomaticSize.Y
		local label = createTextLabel(tostring(text), 25, Enum.TextXAlignment.Left)
		label.TextColor3 = theme.Muted
		label.TextWrapped = true
		label.TextYAlignment = Enum.TextYAlignment.Top
		label.Size = UDim2.new(1, 0, 0, 0)
		label.AutomaticSize = Enum.AutomaticSize.Y
		label.Parent = row
		self:_attach(row)
		return self
	end

	Tab.AddDivider = function(self)
		local row = createRow(6)
		row.Name = "Divider"
		createInkDivider(self._order + 11).Parent = row
		self:_attach(row)
		return self
	end

	Tab.AddButton = function(self, opts)
		local row = createRow(32)
		row.Name = "Button"
		local textButton = Instance.new("TextButton")
		textButton.AutoButtonColor = false
		textButton.Text = ""
		textButton.BackgroundColor3 = opts.colour or theme.Header
		textButton.BackgroundTransparency = 0.1
		textButton.BorderSizePixel = 0
		textButton.Size = UDim2.fromScale(1, 1)
		textButton.Parent = row
		addSketchBorder(textButton, theme.Ink, nil, 0)
		addHoverGlow(textButton, textButton, theme.Flash)
		addHoverScale(textButton, textButton, 1.03)
		local label = createTextLabel(tostring(opts.label or "Button"), 26, Enum.TextXAlignment.Center)
		label.Size = UDim2.fromScale(1, 1)
		label.Parent = textButton

		textButton.MouseButton1Click:Connect(function()
			label.TextColor3 = theme.Flash
			local goal = { TextColor3 = theme.Label }
			TweenService:Create(label, TweenInfo.new(0.35), goal):Play()

			if type(opts.callback) == "function" then
				local ok, result = pcall(opts.callback)

				if not ok then
					warn("[UiLib] button '" .. tostring(opts.label) .. "' errored: " .. tostring(result))
				end
			end
		end)

		self:_attach(row)
		return self
	end

	Tab.AddToggle = function(self, opts)
		local window = self._window
		local row = createRow(26)
		row.Name = "Toggle_" .. tostring(opts.key)
		local textButton = Instance.new("TextButton")
		textButton.Name = "Option"
		textButton.Text = ""
		textButton.AutoButtonColor = false
		textButton.BackgroundTransparency = 1
		textButton.BorderSizePixel = 0
		textButton.Size = UDim2.fromScale(1, 1)
		textButton.Parent = row
		local label = createTextLabel(tostring(opts.label or opts.key), 13, Enum.TextXAlignment.Left)
		label.Size = UDim2.new(1, -54, 1, 0)
		label.Parent = textButton
		local box = createWell(22)
		box.Name = "Box"
		box.AnchorPoint = Vector2.new(1, 0.5)
		box.Position = UDim2.new(1, 0, 0.5, 0)
		box.Size = UDim2.new(0, 22, 0, 22)
		box.Parent = textButton
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.BorderSizePixel = 0
		fill.BackgroundColor3 = theme.Off
		fill.AnchorPoint = Vector2.new(0.5, 0.5)
		fill.Position = UDim2.fromScale(0.5, 0.5)
		fill.Size = UDim2.new(1, -8, 1, -8)
		fill.Parent = box
		addHoverScale(box, textButton, 1.15)
		addHoverGlow(box, textButton, theme.Accent)

		local function render(value)
			local on = value and true or false
			TweenService:Create(fill, TweenInfo.new(0.16), { BackgroundColor3 = on and theme.On or theme.Off, BackgroundTransparency = on and 0 or 0.35 }):Play()
		end

		textButton.MouseButton1Click:Connect(function()
			window:Set(opts.key, not window:Get(opts.key))
		end)

		window:_register(opts, "toggle", render, false)
		self:_attach(row)
		return self
	end

	Tab.AddSlider = function(self, opts)
		local window = self._window
		local rawLow = tonumber(opts.min) or 0
		local high = tonumber(opts.max) or 1
		local low

		if high < rawLow then
			low = high
			high = rawLow
		else
			low = rawLow
		end

		local step = tonumber(opts.step) or 0
		local suffix = opts.suffix and tostring(opts.suffix) or ""
		local row = createRow(48)
		row.Name = "Slider_" .. tostring(opts.key)
		local label = createTextLabel(tostring(opts.label or opts.key), 26, Enum.TextXAlignment.Left)
		label.Size = UDim2.new(1, -80, 0, 22)
		label.Parent = row
		local readout = createTextLabel("", 13, Enum.TextXAlignment.Right)
		readout.TextColor3 = theme.Accent
		readout.Size = UDim2.new(0, 80, 0, 22)
		readout.Position = UDim2.new(1, -24, 0, 0)
		readout.Parent = row
		local track = Instance.new("TextButton")
		track.Name = "Track"
		track.Text = ""
		track.AutoButtonColor = false
		track.BackgroundColor3 = theme.Well
		track.BackgroundTransparency = 0.15
		track.BorderSizePixel = 0
		track.Size = UDim2.new(1, 0, 0, 12)
		track.Position = UDim2.new(0, 0, 0, 28)
		track.Parent = row
		addSketchBorder(track, theme.Ink, nil, 0)
		addHoverGlow(track, track, theme.Accent)
		local fill = Instance.new("Frame")
		fill.Name = "Frame"
		fill.BorderSizePixel = 0
		fill.BackgroundColor3 = theme.Accent
		fill.BackgroundTransparency = 0.1
		fill.Size = UDim2.new(0, 0, 1, 0)
		fill.Parent = track

		local function render(value)
			local clamped = clamp(tonumber(value) or low, low, high)
			fill.Size = UDim2.new(high > low and (clamped - low) / (high - low) or 0, 0, 1, 0)
			readout.Text = formatNumber(clamped, step) .. suffix
		end

		local function valueFromX(mouseX)
			local trackX = track.AbsolutePosition.X
			local trackWidth = track.AbsoluteSize.X
			if trackWidth <= 0 then return low end
			return clamp(roundToStep(low + clamp((mouseX - trackX) / trackWidth, 0, 1) * (high - low), step), low, high)
		end

		track.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end

			window._activeSlider = function(mouseX)
				window:Set(opts.key, valueFromX(mouseX))
			end

			window._activeSlider(input.Position.X)
		end)

		local entry = window:_register(opts, "slider", render, low)
		entry.low = low
		entry.high = high
		entry.step = step

		window:Set(opts.key, window:Get(opts.key), true)
		self:_attach(row)
		return self
	end

	Tab.AddColorPicker = function(self, opts)
		local window = self._window
		local channels = { "R", "G", "B" }
		local row = createRow(32)
		row.Name = "ColorPicker_" .. tostring(opts.key)
		local label = createTextLabel(tostring(opts.label or opts.key), 26, Enum.TextXAlignment.Left)
		label.Size = UDim2.new(1, -30, 1, 0)
		label.Parent = row
		local swatch = Instance.new("TextButton")
		swatch.Name = "Swatch"
		swatch.Text = ""
		swatch.AutoButtonColor = false
		swatch.BorderSizePixel = 0
		swatch.AnchorPoint = Vector2.new(1, 0.5)
		swatch.Position = UDim2.new(1, 0, 0.5, 0)
		swatch.Size = UDim2.new(0, 22, 0, 22)
		swatch.BackgroundColor3 = Color3.new(1, 1, 1)
		swatch.Parent = row
		addSketchBorder(swatch, theme.Ink, nil, 0)
		addHoverScale(swatch, swatch, 1.15)
		addHoverGlow(swatch, swatch, theme.Accent)
		local panel = Instance.new("Frame")
		panel.Name = "Panel"
		panel.Visible = false
		panel.BackgroundColor3 = theme.List
		panel.BackgroundTransparency = 1
		panel.BorderSizePixel = 0
		panel.Size = UDim2.new(1, 0, 0, 0)
		panel.Position = UDim2.new(0, 0, 0, 32)
		panel.ZIndex = 3
		panel.Parent = row
		addSketchBorder(panel, theme.Ink, nil, 0)
		local panelHeight = 4 + #channels * 26 - 3
		local channelUi = {}

		for i, channel in ipairs(channels) do
			local channelRow = Instance.new("Frame")
			channelRow.Name = "Channel_" .. channel
			channelRow.BackgroundTransparency = 1
			channelRow.BorderSizePixel = 0
			channelRow.Size = UDim2.new(1, -16, 0, 22)
			channelRow.Position = UDim2.new(0, 8, 0, 8 + (i - 1) * 26)
			channelRow.ZIndex = 3
			channelRow.Parent = panel
			local channelLabel = createTextLabel(channel, 14, Enum.TextXAlignment.Left)
			channelLabel.Size = UDim2.new(0, 16, 1, 0)
			channelLabel.ZIndex = 3
			channelLabel.Parent = channelRow
			local track = Instance.new("TextButton")
			track.Name = "Track"
			track.Text = ""
			track.AutoButtonColor = false
			track.BackgroundColor3 = theme.Well
			track.BackgroundTransparency = 0.15
			track.BorderSizePixel = 0
			track.Size = UDim2.new(1, -46, 1, 0)
			track.Position = UDim2.new(0, 20, 0, 0)
			track.ZIndex = 3
			track.Parent = channelRow
			addSketchBorder(track, theme.Ink, nil, 0)
			addHoverGlow(track, track, theme.Accent)
			local fill = Instance.new("Frame")
			fill.Name = "Fill"
			fill.BorderSizePixel = 0
			fill.BackgroundColor3 = theme.Accent
			fill.BackgroundTransparency = 0.1
			fill.Size = UDim2.new(0, 0, 1, 0)
			fill.ZIndex = 2
			fill.Parent = track
			local readout = createTextLabel("", 14, Enum.TextXAlignment.Right)
			readout.TextColor3 = theme.Accent
			readout.Size = UDim2.new(0, 13, 1, 0)
			readout.Position = UDim2.new(1, -26, 0, 0)
			readout.ZIndex = 3
			readout.Parent = channelRow
			channelUi[channel] = { track = track, fill = fill, readout = readout }
		end

		local function getChannel(color, channel)
			if channel == "R" then return color.R end

			if channel ~= "G" then return color.B end

			return color.G
		end

		local function withChannel(color, channel, value)
			local r = color.R
			local g = color.G
			local b = color.B

			if channel ~= "R" then
				if channel == "G" then
					g = value
					value = r
				else
					b = value
					value = r
				end
			end

			return Color3.new(value, g, b)
		end

		local function render(value)
			local color = typeof(value) == "Color3" and value or Color3.new(1, 1, 1)
			swatch.BackgroundColor3 = color

			for k, ui in pairs(channelUi) do
				local channelValue = getChannel(color, k)
				ui.fill.Size = UDim2.new(channelValue, 0, 1, 0)
				ui.readout.Text = tostring(math.floor(channelValue * 255 + 0.5))
			end
		end

		local isOpen = false

		local function openDropdown(open)
			if isOpen == open then return end
			isOpen = open
			panel.Visible = isOpen
			row.Size = UDim2.new(1, 0, 0, 32 + (isOpen and panelHeight + 4 or 0))
			panel.Size = UDim2.new(1, 0, 0, isOpen and panelHeight or 0)

			if isOpen then
				if window._openDropdown and window._openDropdown ~= openDropdown then
					window._openDropdown(false)
				end

				window._openDropdown = openDropdown
			elseif window._openDropdown == openDropdown then
				window._openDropdown = nil
			end
		end

		swatch.MouseButton1Click:Connect(function()
			openDropdown(not isOpen)
		end)

		for k, ui in pairs(channelUi) do
			local function fractionFromX(mouseX)
				local trackX = ui.track.AbsolutePosition.X
				local trackWidth = ui.track.AbsoluteSize.X
				if trackWidth <= 0 then
					local current = window:Get(opts.key)
					return getChannel(typeof(current) == "Color3" and current or Color3.new(1, 1, 1), k)
				end
				return clamp((mouseX - trackX) / trackWidth, 0, 1)
			end

			ui.track.InputBegan:Connect(function(input)
				if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
					return
				end

				window._activeSlider = function(mouseX)
					local color = window:Get(opts.key)

					if typeof(color) ~= "Color3" then color = Color3.new(1, 1, 1) end

					window:Set(opts.key, withChannel(color, k, fractionFromX(mouseX)))
				end

				window._activeSlider(input.Position.X)
			end)
		end

		window:_register(opts, "colorpicker", render, Color3.fromRGB(255, 255, 220))
		self:_attach(row)
		return self
	end

	Tab.AddDropdown = function(self, opts)
		local window = self._window
		local optionList = {}

		local options = opts.options or {}

		for _, option in ipairs(options) do
			optionList[#optionList + 1] = tostring(option)
		end

		local row = createRow(26)
		row.Name = "cp_" .. tostring(opts.key)
		local label = createTextLabel(tostring(opts.label or opts.key), 13, Enum.TextXAlignment.Left)
		label.Size = UDim2.new(0.42, -6, 0, 32)
		label.Parent = row
		local selectedButton = Instance.new("TextButton")
		selectedButton.Name = "Selected"
		selectedButton.Text = ""
		selectedButton.AutoButtonColor = false
		selectedButton.BackgroundColor3 = theme.Well
		selectedButton.BackgroundTransparency = 0.15
		selectedButton.BorderSizePixel = 0
		selectedButton.Size = UDim2.new(0.58, 0, 0, 28)
		selectedButton.Position = UDim2.new(0.42, 0, 0, 2)
		selectedButton.Parent = row
		addSketchBorder(selectedButton, theme.Ink, nil, 0)
		addHoverGlow(selectedButton, selectedButton, theme.Accent)
		local selectedLabel = createTextLabel("", 26, Enum.TextXAlignment.Left)
		selectedLabel.Size = UDim2.new(1, -20, 1, 0)
		selectedLabel.Position = UDim2.new(0, 8, 0, 0)
		selectedLabel.TextTruncate = Enum.TextTruncate.AtEnd
		selectedLabel.Parent = selectedButton
		local arrow = createTextLabel("●", 24, Enum.TextXAlignment.Center)
		arrow.TextColor3 = theme.Muted
		arrow.Size = UDim2.new(0, 22, 1, 0)
		arrow.Position = UDim2.new(1, -24, 0, 0)
		arrow.Parent = selectedButton
		local scrollingFrame = Instance.new("ScrollingFrame")
		scrollingFrame.Name = "Options"
		scrollingFrame.Visible = false
		scrollingFrame.Active = true
		scrollingFrame.BackgroundColor3 = theme.List
		scrollingFrame.BackgroundTransparency = 1
		scrollingFrame.BorderSizePixel = 0
		scrollingFrame.ScrollBarThickness = 4
		scrollingFrame.ScrollBarImageColor3 = theme.Ink
		scrollingFrame.ScrollBarImageTransparency = 0.5
		scrollingFrame.CanvasSize = UDim2.new()
		scrollingFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
		scrollingFrame.Size = UDim2.new(0.58, 0, 0, 0)
		scrollingFrame.Position = UDim2.new(0.42, 0, 0, 32)
		scrollingFrame.ZIndex = 3
		scrollingFrame.Parent = row
		createUIStroke(scrollingFrame)
		local uiListLayout = Instance.new("UIListLayout")
		uiListLayout.FillDirection = Enum.FillDirection.Vertical
		uiListLayout.SortOrder = Enum.SortOrder.LayoutOrder
		uiListLayout.Parent = scrollingFrame
		local isOpen = false
		local optionLabels = {}

		local function listHeight()
			return math.min(#optionList, 8) * 24
		end

		local function openDropdown(open)
			local shouldOpen = open and #optionList > 0
			if isOpen == shouldOpen then return end
			isOpen = shouldOpen
			scrollingFrame.Visible = isOpen
			arrow.Text = isOpen and "^" or "v"
			row.Size = UDim2.new(1, 0, 0, 32 + (isOpen and listHeight() + 4 or 0))
			scrollingFrame.Size = UDim2.new(0.58, 0, 0, isOpen and listHeight() or 0)

			if isOpen then
				if window._openDropdown and window._openDropdown ~= openDropdown then
					window._openDropdown(false)
				end

				window._openDropdown = openDropdown
			elseif window._openDropdown == openDropdown then
				window._openDropdown = nil
			end
		end

		local function highlight(value)
			for k, optionLabel in pairs(optionLabels) do
				optionLabel.TextColor3 = k == tostring(value) and theme.Accent or theme.Label
			end
		end

		local function rebuildOptions()
			for _, child in ipairs(scrollingFrame:GetChildren()) do
				if child:IsA("TextButton") then child:Destroy() end
			end

			optionLabels = {}

			for i, optionText in ipairs(optionList) do
				local optionButton = Instance.new("TextButton")
				optionButton.Name = "Option_" .. optionText
				optionButton.Text = ""
				optionButton.AutoButtonColor = false
				optionButton.BackgroundTransparency = 1
				optionButton.BorderSizePixel = 0
				optionButton.Size = UDim2.new(1, 0, 0, 24)
				optionButton.LayoutOrder = i
				optionButton.Parent = scrollingFrame
				local optionLabel = createTextLabel(optionText, 25, Enum.TextXAlignment.Left)
				optionLabel.Size = UDim2.new(1, -16, 1, 0)
				optionLabel.Position = UDim2.new(0, 8, 0, 0)
				optionLabel.TextTruncate = Enum.TextTruncate.AtEnd
				optionLabel.Parent = optionButton
				optionLabels[optionText] = optionLabel

				optionButton.MouseEnter:Connect(function()
					optionButton.BackgroundColor3 = theme.Ink
					local goal = { BackgroundTransparency = 0.5 }
					TweenService:Create(optionButton, TweenInfo.new(0.14), goal):Play()
				end)

				optionButton.MouseLeave:Connect(function()
					TweenService:Create(optionButton, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()
				end)

				optionButton.MouseButton1Click:Connect(function()
					openDropdown(false)
					window:Set(opts.key, optionText)
				end)
			end

			highlight(window:Get(opts.key))

			if isOpen then
				openDropdown(false)
				openDropdown(true)
			end
		end

		local function render(value)
			selectedLabel.Text = (value == nil or value == "") and "--" or tostring(value)
			selectedLabel.TextColor3 = (value == nil or value == "") and theme.Muted or theme.Label
			highlight(value)
		end

		selectedButton.MouseButton1Click:Connect(function()
			openDropdown(not isOpen)
		end)

		rebuildOptions()
		local entry = window:_register(opts, "dropdown", render, optionList[1])

		entry.setOptions = function(newOptions)
			optionList = {}

			local list = newOptions or {}

			for _, option in ipairs(list) do
				optionList[#optionList + 1] = tostring(option)
			end

			rebuildOptions()
			render(window:Get(opts.key))
		end

		entry.getOptions = function()
			local copy = {}

			for i, option in ipairs(optionList) do
				copy[i] = option
			end

			return copy
		end

		self:_attach(row)
		return self
	end

	Tab.AddMultiDropdown = function(self, opts)
		local window = self._window
		local options = opts.options or {}
		local row = createRow(32)
		row.Name = "MultiDropdown_" .. tostring(opts.label or "")
		local label = createTextLabel(tostring(opts.label or "Select"), 26, Enum.TextXAlignment.Left)
		label.Size = UDim2.new(0.42, -6, 0, 32)
		label.Parent = row
		local toggleButton = Instance.new("TextButton")
		toggleButton.Name = "ToggleBtn"
		toggleButton.Text = ""
		toggleButton.AutoButtonColor = false
		toggleButton.BackgroundColor3 = theme.Well
		toggleButton.BackgroundTransparency = 0.15
		toggleButton.BorderSizePixel = 0
		toggleButton.Size = UDim2.new(0.58, 0, 0, 28)
		toggleButton.Position = UDim2.new(0.42, 0, 0, 2)
		toggleButton.Parent = row
		addSketchBorder(toggleButton, theme.Ink, nil, 0)
		addHoverGlow(toggleButton, toggleButton, theme.Accent)
		local summary = createTextLabel("", 26, Enum.TextXAlignment.Left)
		summary.Size = UDim2.new(1, -30, 1, 0)
		summary.Position = UDim2.new(0, 8, 0, 0)
		summary.TextTruncate = Enum.TextTruncate.AtEnd
		summary.Parent = toggleButton
		local arrow = createTextLabel("v", 24, Enum.TextXAlignment.Center)
		arrow.TextColor3 = theme.Muted
		arrow.Size = UDim2.new(0, 22, 1, 0)
		arrow.Position = UDim2.new(1, -24, 0, 0)
		arrow.Parent = toggleButton
		local scrollingFrame = Instance.new("ScrollingFrame")
		scrollingFrame.Name = "ScrollingFrame"
		scrollingFrame.Visible = false
		scrollingFrame.Active = true
		scrollingFrame.BackgroundColor3 = theme.List
		scrollingFrame.BackgroundTransparency = 0.04
		scrollingFrame.BorderSizePixel = 0
		scrollingFrame.ScrollBarThickness = 3
		scrollingFrame.ScrollBarImageColor3 = theme.Ink
		scrollingFrame.ScrollBarImageTransparency = 0.5
		scrollingFrame.CanvasSize = UDim2.new()
		scrollingFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
		scrollingFrame.Size = UDim2.new(0.58, 0, 0, 0)
		scrollingFrame.Position = UDim2.new(0.42, 0, 0, 32)
		scrollingFrame.ZIndex = 3
		scrollingFrame.Parent = row
		createUIStroke(scrollingFrame)
		local listLayout = Instance.new("UIListLayout")
		listLayout.FillDirection = Enum.FillDirection.Vertical
		listLayout.SortOrder = Enum.SortOrder.LayoutOrder
		listLayout.Parent = scrollingFrame
		local isOpen = false

		local function listHeight()
			return math.min(#options, 8) * 24
		end

		local function openDropdown(open)
			local shouldOpen = open and #options > 0
			if isOpen == shouldOpen then return end
			isOpen = shouldOpen
			scrollingFrame.Visible = isOpen
			arrow.Text = isOpen and "^" or "v"
			row.Size = UDim2.new(1, 0, 0, 26 + (isOpen and listHeight() + 4 or 0))
			scrollingFrame.Size = UDim2.new(0.58, 0, 0, isOpen and listHeight() or 0)

			if isOpen then
				if window._openDropdown and window._openDropdown ~= openDropdown then
					window._openDropdown(false)
				end

				window._openDropdown = openDropdown
			elseif window._openDropdown == openDropdown then
				window._openDropdown = nil
			end
		end

		local function updateSummary()
			local total = #options
			local selectedCount = 0

			for _, option in ipairs(options) do
				if window:Get(option.key) then selectedCount += 1 end
			end

			summary.Text = selectedCount .. "/" .. total .. " selected"
			summary.TextColor3 = selectedCount == 0 and theme.Muted or theme.Label
		end

		toggleButton.MouseButton1Click:Connect(function()
			openDropdown(not isOpen)
		end)

		for i, option in ipairs(options) do
			local optionButton = Instance.new("TextButton")
			optionButton.Name = "Option_" .. tostring(option.key)
			optionButton.Text = ""
			optionButton.AutoButtonColor = false
			optionButton.BackgroundTransparency = 1
			optionButton.BorderSizePixel = 0
			optionButton.Size = UDim2.new(1, 0, 0, 24)
			optionButton.LayoutOrder = i
			optionButton.Parent = scrollingFrame
			local optionLabel = createTextLabel(tostring(option.label or option.key), 14, Enum.TextXAlignment.Left)
			optionLabel.Size = UDim2.new(1, -30, 1, 0)
			optionLabel.Position = UDim2.new(0, 8, 0, 0)
			optionLabel.TextTruncate = Enum.TextTruncate.AtEnd
			optionLabel.Parent = optionButton
			local box = createWell(16)
			box.AnchorPoint = Vector2.new(1, 0.5)
			box.Position = UDim2.new(1, -8, 0.5, 0)
			box.Size = UDim2.new(0, 16, 0, 16)
			box.Parent = optionButton
			local fill = Instance.new("Frame")
			fill.Name = "Fill"
			fill.BorderSizePixel = 0
			fill.BackgroundColor3 = theme.Off
			fill.AnchorPoint = Vector2.new(0.5, 0.5)
			fill.Position = UDim2.fromScale(0.5, 0.5)
			fill.Size = UDim2.new(1, -6, 1, -8)
			fill.Parent = box
			addHoverScale(box, optionButton, 1.15)
			addHoverGlow(box, optionButton, theme.Accent)

			local function render(value)
				local on = value and true or false
				TweenService:Create(fill, TweenInfo.new(0.16), { BackgroundColor3 = on and theme.On or theme.Off, BackgroundTransparency = on and 0 or 0.35 }):Play()
				updateSummary()
			end

			optionButton.MouseEnter:Connect(function()
				local goal = { BackgroundTransparency = 0.5 }
				TweenService:Create(optionButton, TweenInfo.new(0.15), goal):Play()
				optionButton.BackgroundColor3 = theme.Ink
			end)

			optionButton.MouseLeave:Connect(function()
				TweenService:Create(optionButton, TweenInfo.new(0.22), { BackgroundTransparency = 1 }):Play()
			end)

			optionButton.MouseButton1Click:Connect(function()
				window:Set(option.key, not window:Get(option.key))
			end)

			window:_register(option, "toggle", render, false)
		end

		updateSummary()
		self:_attach(row)
		return self
	end

	Tab.AddInput = function(self, opts)
		local window = self._window
		local row = createRow(28)
		row.Name = "Input_" .. tostring(opts.key)
		local label = createTextLabel(tostring(opts.label or opts.key), 26, Enum.TextXAlignment.Left)
		label.Size = UDim2.new(0.5, -8, 1, 0)
		label.Parent = row
		local well = createWell(20)
		well.Size = UDim2.new(0.58, 0, 0, 20)
		well.Position = UDim2.new(0.42, 0, 0, 2)
		well.Parent = row
		addHoverGlow(well, well, theme.Accent)
		local textBox = Instance.new("TextBox")
		textBox.Name = "Field"
		textBox.BackgroundTransparency = 1
		textBox.BorderSizePixel = 0
		textBox.Size = UDim2.new(1, -12, 1, 0)
		textBox.Position = UDim2.new(0, 7, 0, 0)
		textBox.FontFace = font
		textBox.TextSize = 25
		textBox.TextColor3 = theme.Value
		textBox.PlaceholderText = tostring(opts.placeholder or "")
		textBox.PlaceholderColor3 = theme.Muted
		textBox.TextXAlignment = Enum.TextXAlignment.Left
		textBox.ClearTextOnFocus = false
		textBox.ClipsDescendants = true
		textBox.Text = ""
		textBox.Parent = well
		local textStroke = Instance.new("UIStroke")
		textStroke.Color = theme.Shadow
		textStroke.Thickness = 2
		textStroke.Transparency = 0.5
		textStroke.Parent = textBox

		local function render(value)
			if textBox:IsFocused() then return end
			textBox.Text = value == nil and "" or tostring(value)
		end

		textBox.FocusLost:Connect(function()
			if opts.numeric then
				local num = tonumber(textBox.Text)
				if num == nil then
					render(window:Get(opts.key))
					return
				end
				window:Set(opts.key, num)
			else
				window:Set(opts.key, textBox.Text)
			end
		end)

		window:_register(opts, "input", render, opts.numeric and 0 or "")
		self:_attach(row)
		return self
	end

	Tab.AddColumnHeader = function(self, columns)
		local cols = columns or {}
		local row = createRow(24)
		row.Name = "ColumnHeader"
		local leftLabel = createTextLabel(string.upper(tostring(cols.left or "")), 23, Enum.TextXAlignment.Left)
		leftLabel.TextColor3 = theme.Muted
		leftLabel.Size = UDim2.new(0.5, -8, 1, 0)
		leftLabel.Parent = row
		local middleLabel = createTextLabel(string.upper(tostring(cols.middle or "")), 23, Enum.TextXAlignment.Left)
		middleLabel.TextColor3 = theme.Muted
		middleLabel.Size = UDim2.new(0.6, -4, 1, 0)
		middleLabel.Position = UDim2.new(0.3, 0, 0, 0)
		middleLabel.Parent = row
		local rightWidth = cols.right2 and 0.1 or 0.3
		local rightLabel = createTextLabel(string.upper(tostring(cols.right or "")), 23, Enum.TextXAlignment.Left)
		rightLabel.TextColor3 = theme.Muted
		rightLabel.Size = UDim2.new(rightWidth, 0, 1, 0)
		rightLabel.Position = UDim2.new(0, 0, 0, 0)
		rightLabel.Parent = row

		if cols.right2 then
			local right2Label = createTextLabel(string.upper(tostring(cols.right2)), 23, Enum.TextXAlignment.Left)
			right2Label.TextColor3 = theme.Muted
			right2Label.Size = UDim2.new(0.15, 0, 1, 0)
			right2Label.Position = UDim2.new(0.85, 0, 0, 0)
			right2Label.Parent = row
		end

		self:_attach(row)
		return self
	end

	Tab.AddInputToggle = function(self, opts)
		local window = self._window
		local row = createRow(28)
		row.Name = "InputToggle_" .. tostring(opts.key)
		local label = createTextLabel(tostring(opts.label or opts.key), 13, Enum.TextXAlignment.Left)
		label.Size = UDim2.new(0.3, -6, 1, 0)
		label.Parent = row
		local well = createWell(30)
		well.Size = UDim2.new(0.4, -4, 0, 30)
		well.Position = UDim2.new(0.3, 0, 0, 2)
		well.Parent = row
		addHoverGlow(well, well, theme.Accent)
		local textBox = Instance.new("TextBox")
		textBox.Name = "Field"
		textBox.BackgroundTransparency = 1
		textBox.BorderSizePixel = 0
		textBox.Size = UDim2.new(1, -14, 1, 0)
		textBox.Position = UDim2.new(0, 7, 0, 0)
		textBox.FontFace = font
		textBox.TextSize = 25
		textBox.TextColor3 = theme.Value
		textBox.PlaceholderText = tostring(opts.placeholder or "")
		textBox.PlaceholderColor3 = theme.Muted
		textBox.TextXAlignment = Enum.TextXAlignment.Left
		textBox.ClearTextOnFocus = false
		textBox.ClipsDescendants = true
		textBox.Text = ""
		textBox.Parent = well
		local textStroke = Instance.new("UIStroke")
		textStroke.Color = theme.Shadow
		textStroke.Thickness = 2
		textStroke.Transparency = 0.5
		textStroke.Parent = textBox

		local function renderText(value)
			if textBox:IsFocused() then return end
			textBox.Text = value == nil and "" or tostring(value)
		end

		textBox.FocusLost:Connect(function()
			if opts.numeric then
				local num = tonumber(textBox.Text)
				if num == nil then
					renderText(window:Get(opts.key))
					return
				end
				window:Set(opts.key, num)
			else
				window:Set(opts.key, textBox.Text)
			end
		end)

		window:_register(opts, "input", renderText, opts.numeric and 0 or "")
		local hasSecondToggle = opts.toggle2Key ~= nil
		local toggleWidth = hasSecondToggle and 0.15 or 0.3

		local toggleOpts = {
			key = opts.toggleKey,
			label = opts.toggleLabel,
			default = opts.toggleDefault,
			path = opts.togglePath,
			callback = opts.toggleCallback,
		}

		local toggleHit = Instance.new("TextButton")
		toggleHit.Name = "ToggleHit"
		toggleHit.Text = ""
		toggleHit.AutoButtonColor = false
		toggleHit.BackgroundTransparency = 1
		toggleHit.BorderSizePixel = 0
		toggleHit.Size = UDim2.new(toggleWidth, 0, 1, 0)
		toggleHit.Position = UDim2.new(0.7, 0, 0, 0)
		toggleHit.Parent = row
		local toggleLabel = createTextLabel(tostring(opts.toggleLabel or ""), 24, Enum.TextXAlignment.Left)
		toggleLabel.Size = UDim2.new(1, -28, 1, 0)
		toggleLabel.Parent = toggleHit
		local box = createWell(20)
		box.Name = "Slider"
		box.AnchorPoint = Vector2.new(1, 0.5)
		box.Position = UDim2.new(1, 0, 0.5, 0)
		box.Size = UDim2.new(0, 20, 0, 20)
		box.Parent = toggleHit
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.BorderSizePixel = 0
		fill.BackgroundColor3 = theme.Off
		fill.AnchorPoint = Vector2.new(0.5, 0.5)
		fill.Position = UDim2.fromScale(0.5, 0.5)
		fill.Size = UDim2.new(1, -8, 1, -8)
		fill.Parent = box
		addHoverScale(box, toggleHit, 1.15)
		addHoverGlow(box, toggleHit, theme.Accent)

		local function renderToggle(value)
			local on = value and true or false
			TweenService:Create(fill, TweenInfo.new(0.16), { BackgroundColor3 = on and theme.On or theme.Off, BackgroundTransparency = on and 0 or 0.35 }):Play()
		end

		toggleHit.MouseButton1Click:Connect(function()
			window:Set(toggleOpts.key, not window:Get(toggleOpts.key))
		end)

		window:_register(toggleOpts, "toggle", renderToggle, false)

		if hasSecondToggle then
			local toggle2Opts = {
				key = opts.toggle2Key,
				label = opts.toggle2Label,
				default = opts.toggle2Default,
				path = opts.toggle2Path,
				callback = opts.toggle2Callback,
			}

			local toggleHit2 = Instance.new("TextButton")
			toggleHit2.Name = "ToggleHit2"
			toggleHit2.Text = ""
			toggleHit2.AutoButtonColor = false
			toggleHit2.BackgroundTransparency = 1
			toggleHit2.BorderSizePixel = 0
			toggleHit2.Size = UDim2.new(0.15, 0, 1, 0)
			toggleHit2.Position = UDim2.new(0.85, 0, 0, 0)
			toggleHit2.Parent = row
			local toggle2Label = createTextLabel(tostring(opts.toggle2Label or ""), 24, Enum.TextXAlignment.Left)
			toggle2Label.Size = UDim2.new(1, -28, 1, 0)
			toggle2Label.Parent = toggleHit2
			local box2 = createWell(20)
			box2.Name = "Box"
			box2.AnchorPoint = Vector2.new(1, 0.5)
			box2.Position = UDim2.new(1, 0, 0.5, 0)
			box2.Size = UDim2.new(0, 20, 0, 20)
			box2.Parent = toggleHit2
			local fill2 = Instance.new("Frame")
			fill2.Name = "Fill"
			fill2.BorderSizePixel = 0
			fill2.BackgroundColor3 = theme.Off
			fill2.AnchorPoint = Vector2.new(0.5, 0.5)
			fill2.Position = UDim2.fromScale(0.5, 0.5)
			fill2.Size = UDim2.new(1, -8, 1, -8)
			fill2.Parent = box2
			addHoverScale(box2, toggleHit2, "InputBegan")
			addHoverGlow(box2, toggleHit2, theme.Accent)

			local function renderToggle2(value)
				local on = value and true or false
				TweenService:Create(fill2, TweenInfo.new(0.16), { BackgroundColor3 = on and theme.On or theme.Off, BackgroundTransparency = on and 0 or 0.35 }):Play()
			end

			toggleHit2.MouseButton1Click:Connect(function()
				window:Set(toggle2Opts.key, not window:Get(toggle2Opts.key))
			end)

			window:_register(toggle2Opts, "toggle", renderToggle2, false)
		end

		self:_attach(row)
		return self
	end

	Tab.AddInputDropdown = function(self, opts)
		local window = self._window
		local optionList = {}

		local dropdownOptions = opts.dropdownOptions or {}

		for _, dropdownOption in ipairs(dropdownOptions) do
			optionList[#optionList + 1] = tostring(dropdownOption)
		end

		local row = createRow(34)
		row.Name = "InputDropdown_" .. tostring(opts.key)
		local label = createTextLabel(tostring(opts.label or opts.key), 13, Enum.TextXAlignment.Left)
		label.Size = UDim2.new(0.3, -6, 0, 34)
		label.Parent = row
		local well = createWell(30)
		well.Size = UDim2.new(0.6, -3, 0, 30)
		well.Position = UDim2.new(0.3, 0, 0, 2)
		well.Parent = row
		addHoverGlow(well, well, theme.Accent)
		local textBox = Instance.new("TextBox")
		textBox.Name = "Field"
		textBox.BackgroundTransparency = 1
		textBox.BorderSizePixel = 0
		textBox.Size = UDim2.new(1, -12, 1, 0)
		textBox.Position = UDim2.new(0, 7, 0, 0)
		textBox.FontFace = font
		textBox.TextSize = 25
		textBox.TextColor3 = theme.Value
		textBox.PlaceholderText = tostring(opts.placeholder or "")
		textBox.PlaceholderColor3 = theme.Muted
		textBox.TextXAlignment = Enum.TextXAlignment.Left
		textBox.ClearTextOnFocus = false
		textBox.ClipsDescendants = true
		textBox.Text = ""
		textBox.Parent = well
		local textStroke = Instance.new("UIStroke")
		textStroke.Color = theme.Shadow
		textStroke.Thickness = 2
		textStroke.Transparency = 0.5
		textStroke.Parent = textBox

		local function renderText(value)
			if textBox:IsFocused() then return end
			textBox.Text = value == nil and "" or tostring(value)
		end

		textBox.FocusLost:Connect(function()
			if opts.numeric then
				local num = tonumber(textBox.Text)
				if num == nil then
					renderText(window:Get(opts.key))
					return
				end
				window:Set(opts.key, num)
			else
				window:Set(opts.key, textBox.Text)
			end
		end)

		window:_register(opts, "input", renderText, opts.numeric and 0 or "")

		local dropdownOpts = {
			key = opts.dropdownKey,
			label = opts.dropdownLabel,
			default = opts.dropdownDefault,
			path = opts.dropdownPath,
			callback = opts.dropdownCallback,
		}

		local selectedButton = Instance.new("TextButton")
		selectedButton.Name = "Selected"
		selectedButton.Text = ""
		selectedButton.AutoButtonColor = false
		selectedButton.BackgroundColor3 = theme.Well
		selectedButton.BackgroundTransparency = 0.1
		selectedButton.BorderSizePixel = 0
		selectedButton.Size = UDim2.new(0.3, 0, 0, 20)
		selectedButton.Position = UDim2.new(0.7, 0, 0, 2)
		selectedButton.Parent = row
		addSketchBorder(selectedButton, theme.Ink, nil, 0)
		addHoverGlow(selectedButton, selectedButton, theme.Accent)
		local selectedLabel = createTextLabel("", 24, Enum.TextXAlignment.Left)
		selectedLabel.Size = UDim2.new(1, -24, 1, 0)
		selectedLabel.Position = UDim2.new(0, 6, 0, 0)
		selectedLabel.TextTruncate = Enum.TextTruncate.AtEnd
		selectedLabel.Parent = selectedButton
		local arrow = createTextLabel("v", 23, Enum.TextXAlignment.Center)
		arrow.TextColor3 = theme.Muted
		arrow.Size = UDim2.new(0, 16, 1, 0)
		arrow.Position = UDim2.new(1, -16, 0, 0)
		arrow.Parent = selectedButton
		local scrollingFrame = Instance.new("ScrollingFrame")
		scrollingFrame.Name = "ScrollingFrame"
		scrollingFrame.Visible = false
		scrollingFrame.Active = true
		scrollingFrame.BackgroundColor3 = theme.List
		scrollingFrame.BackgroundTransparency = 0.04
		scrollingFrame.BorderSizePixel = 0
		scrollingFrame.ScrollBarThickness = 3
		scrollingFrame.ScrollBarImageColor3 = theme.Ink
		scrollingFrame.ScrollBarImageTransparency = 0.5
		scrollingFrame.CanvasSize = UDim2.new()
		scrollingFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
		scrollingFrame.Size = UDim2.new(0.3, 0, 0, 0)
		scrollingFrame.Position = UDim2.new(0, 0, 0, 28)
		scrollingFrame.ZIndex = 3
		scrollingFrame.Parent = row
		createUIStroke(scrollingFrame)
		local listLayout = Instance.new("UIListLayout")
		listLayout.FillDirection = Enum.FillDirection.Vertical
		listLayout.SortOrder = Enum.SortOrder.LayoutOrder
		listLayout.Parent = scrollingFrame
		local isOpen = false
		local optionLabels = {}

		local function listHeight()
			return math.min(#optionList, 6) * 24
		end

		local function openDropdown(open)
			local shouldOpen = open and #optionList > 0
			if isOpen == shouldOpen then return end
			isOpen = shouldOpen
			scrollingFrame.Visible = isOpen
			arrow.Text = isOpen and "^" or "v"
			row.Size = UDim2.new(1, 0, 0, 34 + (isOpen and listHeight() + 4 or 0))
			scrollingFrame.Size = UDim2.new(0.3, 0, 0, isOpen and listHeight() or 0)

			if isOpen then
				if window._openDropdown and window._openDropdown ~= openDropdown then
					window._openDropdown(false)
				end

				window._openDropdown = openDropdown
			elseif window._openDropdown == openDropdown then
				window._openDropdown = nil
			end
		end

		local function highlight(value)
			for k, optionLabel in pairs(optionLabels) do
				optionLabel.TextColor3 = k == tostring(value) and theme.Accent or theme.Label
			end
		end

		local function rebuildOptions()
			for _, child in ipairs(scrollingFrame:GetChildren()) do
				if child:IsA("TextButton") then child:Destroy() end
			end

			optionLabels = {}

			for i, optionText in ipairs(optionList) do
				local optionButton = Instance.new("TextButton")
				optionButton.Name = "Option_" .. optionText
				optionButton.Text = ""
				optionButton.AutoButtonColor = false
				optionButton.BackgroundTransparency = 1
				optionButton.BorderSizePixel = 0
				optionButton.Size = UDim2.new(1, 0, 0, 24)
				optionButton.LayoutOrder = i
				optionButton.Parent = scrollingFrame
				local optionLabel = createTextLabel(optionText, 24, Enum.TextXAlignment.Left)
				optionLabel.Size = UDim2.new(1, -12, 1, 0)
				optionLabel.Position = UDim2.new(0, 6, 0, 0)
				optionLabel.TextTruncate = Enum.TextTruncate.AtEnd
				optionLabel.Parent = optionButton
				optionLabels[optionText] = optionLabel

				optionButton.MouseEnter:Connect(function()
					optionButton.BackgroundColor3 = theme.Ink
					local goal = { BackgroundTransparency = 0.5 }
					TweenService:Create(optionButton, TweenInfo.new(0.14), goal):Play()
				end)

				optionButton.MouseLeave:Connect(function()
					local goal = { BackgroundTransparency = 1 }
					TweenService:Create(optionButton, TweenInfo.new(0.22), goal):Play()
				end)

				optionButton.MouseButton1Click:Connect(function()
					openDropdown(false)
					window:Set(dropdownOpts.key, optionText)
				end)
			end

			highlight(window:Get(dropdownOpts.key))

			if isOpen then
				openDropdown(false)
				openDropdown(true)
			end
		end

		local function renderDropdown(value)
			selectedLabel.Text = (value == nil or value == "") and "--" or tostring(value)
			selectedLabel.TextColor3 = (value == nil or value == "") and theme.Muted or theme.Label
			highlight(value)
		end

		selectedButton.MouseButton1Click:Connect(function()
			openDropdown(not isOpen)
		end)

		rebuildOptions()

		window:_register(dropdownOpts, "dropdown", renderDropdown, optionList[1]).setOptions = function(newOptions)
			optionList = {}

			local list = newOptions or {}

			for _, option in ipairs(list) do
				optionList[#optionList + 1] = tostring(option)
			end

			rebuildOptions()
			renderDropdown(window:Get(dropdownOpts.key))
		end

		self:_attach(row)
		return self
	end

	Tab.AddInputMultiDropdown = function(self, opts)
		local window = self._window
		local dropdownOptions = opts.dropdownOptions or {}
		local row = createRow(28)
		row.Name = "InputMultiDropdown_" .. tostring(opts.key)
		local label = createTextLabel(tostring(opts.label or opts.key), 26, Enum.TextXAlignment.Left)
		label.Size = UDim2.new(0.3, -6, 0, 34)
		label.Parent = row
		local well = createWell(20)
		well.Size = UDim2.new(0.6, -4, 0, 20)
		well.Position = UDim2.new(0.3, 0, 0, 2)
		well.Parent = row
		addHoverGlow(well, well, theme.Accent)
		local textBox = Instance.new("TextBox")
		textBox.Name = "Field"
		textBox.BackgroundTransparency = 1
		textBox.BorderSizePixel = 0
		textBox.Size = UDim2.new(1, -14, 1, 0)
		textBox.Position = UDim2.new(0, 7, 0, 0)
		textBox.FontFace = font
		textBox.TextSize = 14
		textBox.TextColor3 = theme.Value
		textBox.PlaceholderText = tostring(opts.placeholder or "")
		textBox.PlaceholderColor3 = theme.Muted
		textBox.TextXAlignment = Enum.TextXAlignment.Left
		textBox.ClearTextOnFocus = false
		textBox.ClipsDescendants = true
		textBox.Text = ""
		textBox.Parent = well
		local textStroke = Instance.new("UIStroke")
		textStroke.Color = theme.Shadow
		textStroke.Thickness = 2
		textStroke.Transparency = 0.5
		textStroke.Parent = textBox

		local function renderText(value)
			if textBox:IsFocused() then return end
			textBox.Text = value == nil and "" or tostring(value)
		end

		textBox.FocusLost:Connect(function()
			if opts.numeric then
				local num = tonumber(textBox.Text)
				if num == nil then
					renderText(window:Get(opts.key))
					return
				end
				window:Set(opts.key, num)
			else
				window:Set(opts.key, textBox.Text)
			end
		end)

		window:_register(opts, "input", renderText, opts.numeric and 0 or "")
		local selectedButton = Instance.new("TextButton")
		selectedButton.Name = "Selected"
		selectedButton.Text = ""
		selectedButton.AutoButtonColor = false
		selectedButton.BackgroundColor3 = theme.Well
		selectedButton.BackgroundTransparency = 0.15
		selectedButton.BorderSizePixel = 0
		selectedButton.Size = UDim2.new(0.3, 0, 0, 30)
		selectedButton.Position = UDim2.new(0.7, 0, 0, 2)
		selectedButton.Parent = row
		addSketchBorder(selectedButton, theme.Ink, nil, 0)
		addHoverGlow(selectedButton, selectedButton, theme.Accent)
		local summary = createTextLabel("", 24, Enum.TextXAlignment.Left)
		summary.Size = UDim2.new(1, -24, 1, 0)
		summary.Position = UDim2.new(0, 8, 0, 0)
		summary.TextTruncate = Enum.TextTruncate.AtEnd
		summary.Parent = selectedButton
		local arrow = createTextLabel("●", 23, Enum.TextXAlignment.Center)
		arrow.TextColor3 = theme.Muted
		arrow.Size = UDim2.new(0, 16, 1, 0)
		arrow.Position = UDim2.new(1, -18, 0, 0)
		arrow.Parent = selectedButton
		local scrollingFrame = Instance.new("ScrollingFrame")
		scrollingFrame.Name = "Options"
		scrollingFrame.Visible = false
		scrollingFrame.Active = true
		scrollingFrame.BackgroundColor3 = theme.List
		scrollingFrame.BackgroundTransparency = 0.04
		scrollingFrame.BorderSizePixel = 0
		scrollingFrame.ScrollBarThickness = 4
		scrollingFrame.ScrollBarImageColor3 = theme.Ink
		scrollingFrame.ScrollBarImageTransparency = 0.5
		scrollingFrame.CanvasSize = UDim2.new()
		scrollingFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
		scrollingFrame.Size = UDim2.new(0.3, 0, 0, 0)
		scrollingFrame.Position = UDim2.new(0.7, 0, 0, 34)
		scrollingFrame.ZIndex = 3
		scrollingFrame.Parent = row
		createUIStroke(scrollingFrame)
		local uiListLayout = Instance.new("UIListLayout")
		uiListLayout.FillDirection = Enum.FillDirection.Vertical
		uiListLayout.SortOrder = Enum.SortOrder.LayoutOrder
		uiListLayout.Parent = scrollingFrame
		local isOpen = false

		local function listHeight()
			return math.min(#dropdownOptions, 6) * 24
		end

		local function openDropdown(open)
			local shouldOpen = open and #dropdownOptions > 0
			if isOpen == shouldOpen then return end
			isOpen = shouldOpen
			scrollingFrame.Visible = isOpen
			arrow.Text = isOpen and "^" or "v"
			row.Size = UDim2.new(1, 0, 0, 34 + (isOpen and listHeight() + 4 or 0))
			scrollingFrame.Size = UDim2.new(0.5, 0, 0, isOpen and listHeight() or 0)

			if isOpen then
				if window._openDropdown and window._openDropdown ~= openDropdown then
					window._openDropdown(false)
				end

				window._openDropdown = openDropdown
			elseif window._openDropdown == openDropdown then
				window._openDropdown = nil
			end
		end

		local function updateSummary()
			local total = #dropdownOptions
			local selectedCount = 0

			for _, dropdownOption in ipairs(dropdownOptions) do
				if window:Get(dropdownOption.key) then selectedCount += 1 end
			end

			summary.Text = selectedCount .. "/" .. total
			summary.TextColor3 = selectedCount == 0 and theme.Muted or theme.Label
		end

		selectedButton.MouseButton1Click:Connect(function()
			openDropdown(not isOpen)
		end)

		for i, dropdownOption in ipairs(dropdownOptions) do
			local optionButton = Instance.new("TextButton")
			optionButton.Name = "opt_" .. tostring(dropdownOption.key)
			optionButton.Text = ""
			optionButton.AutoButtonColor = false
			optionButton.BackgroundTransparency = 1
			optionButton.BorderSizePixel = 0
			optionButton.Size = UDim2.new(1, 0, 0, 24)
			optionButton.LayoutOrder = i
			optionButton.Parent = scrollingFrame
			local optionLabel = createTextLabel(tostring(dropdownOption.label or dropdownOption.key), 24, Enum.TextXAlignment.Left)
			optionLabel.Size = UDim2.new(1, -26, 1, 0)
			optionLabel.Position = UDim2.new(0, 6, 0, 0)
			optionLabel.TextTruncate = Enum.TextTruncate.AtEnd
			optionLabel.Parent = optionButton
			local box = createWell(14)
			box.AnchorPoint = Vector2.new(1, 0.5)
			box.Position = UDim2.new(1, -6, 0.5, 0)
			box.Size = UDim2.new(0, 12, 0, 14)
			box.Parent = optionButton
			local fill = Instance.new("Frame")
			fill.Name = "Frame"
			fill.BorderSizePixel = 0
			fill.BackgroundColor3 = theme.Off
			fill.AnchorPoint = Vector2.new(0.5, 0.5)
			fill.Position = UDim2.fromScale(0.5, 0.5)
			fill.Size = UDim2.new(1, -6, 1, -6)
			fill.Parent = box
			addHoverScale(box, optionButton, 1.15)
			addHoverGlow(box, optionButton, theme.Accent)

			local function render(value)
				local on = value and true or false

				TweenService:Create(fill, TweenInfo.new(0.16), {
					BackgroundColor3 = on and theme.On or theme.Off,
					BackgroundTransparency = on and 0 or 0.8,
				}):Play()

				updateSummary()
			end

			optionButton.MouseEnter:Connect(function()
				optionButton.BackgroundColor3 = theme.Ink
				TweenService:Create(optionButton, TweenInfo.new(0.14), { BackgroundTransparency = 0.85 }):Play()
			end)

			optionButton.MouseLeave:Connect(function()
				local goal = { BackgroundTransparency = 1 }
				TweenService:Create(optionButton, TweenInfo.new(0.22), goal):Play()
			end)

			optionButton.MouseButton1Click:Connect(function()
				window:Set(dropdownOption.key, not window:Get(dropdownOption.key))
			end)

			window:_register(dropdownOption, "checkbox", render, false)
		end

		updateSummary()
		self:_attach(row)
		return self
	end

	-- Window
	local Window = {}
	Window.__index = Window
	Window.Theme = theme
	Window.FormatNumber = formatNumber

	Window.new = function(options)
		local opts = options or {}
		local obj = setmetatable({}, Window)
		obj._opt = {}

		for k, value in pairs(defaultOptions) do
			obj._opt[k] = value
		end

		for k, value in pairs(opts) do
			if value ~= nil then obj._opt[k] = value end
		end

		obj._tabs = {}
		obj._tabCount = 0
		obj._controls = {}
		obj._values = {}
		obj._listeners = {}
		obj._connections = {}
		obj._open = false
		obj._destroyed = false
		obj._preloaded = false
		obj.Loading = false
		obj.Folder = sanitizeName(obj._opt.Folder)

		if obj.Folder == "" then obj.Folder = "UiLib" end

		obj.User = sanitizeName(localPlayer and localPlayer.Name or "Player")

		if obj.User == "" then obj.User = "Player" end

		obj.LegacyUserFolder = obj.Folder .. "/" .. obj.User
		local env = getEnv()
		local uiLibWindows = env.__uiLibWindows

		if type(uiLibWindows) ~= "table" then
			uiLibWindows = {}
			env.__uiLibWindows = uiLibWindows
		end

		if uiLibWindows[obj.Folder] and uiLibWindows[obj.Folder] ~= obj then
			pcall(function()
				uiLibWindows[obj.Folder]:Destroy()
			end)
		end

		uiLibWindows[obj.Folder] = obj
		obj._registry = uiLibWindows
		obj:_build()
		return obj
	end

	Window._track = function(self, connection)
		table.insert(self._connections, connection)
		return connection
	end

	local function randomGuiName()
		local name = ""

		for i = 1, 10 do
			local charIndex = math.random(1, 62)
			name ..= (""):sub(charIndex, charIndex)
		end

		return name
	end

	-- building the gui
	Window._build = function(self)
		local guiParent, isProtected = getGuiParent()
		local screenGui = Instance.new("ScreenGui")
		screenGui.Name = randomGuiName()
		screenGui.ResetOnSpawn = false
		screenGui.IgnoreGuiInset = true
		screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		screenGui.DisplayOrder = self._opt.DisplayOrder

		if isProtected then
			protectGui(screenGui)
			if not loaderFlagB then return end
		end

		screenGui.Parent = guiParent
		self.Gui = screenGui
		self:_buildToggleButton()
		self:_buildWindow()
		self:_buildInput()

		if self._opt.StartOpen then self:Open() end
	end

	Window._buildToggleButton = function(self)
		local toggleSize = self._opt.ToggleSize
		local launcher = Instance.new("TextButton")
		launcher.Name = "ColorPicker"
		launcher.Text = ""
		launcher.AutoButtonColor = false
		launcher.BackgroundColor3 = theme.Header
		launcher.BackgroundTransparency = 1
		launcher.BorderSizePixel = 0
		launcher.Size = UDim2.fromOffset(toggleSize, toggleSize)
		launcher.Position = self._opt.TogglePosition
		launcher.AnchorPoint = Vector2.new(0, 0.5)
		launcher.Parent = self.Gui
		self.Launcher = launcher
		addSketchBorder(launcher, theme.Ink, 1)
		addHoverGlow(launcher, launcher, theme.Flash, 0.6)
		addHoverScale(launcher, launcher, "MouseButton1Click")

		if self._opt.ToggleIcon then
			launcher.BackgroundColor3 = Color3.new(0, 0, 0)
			launcher.BackgroundTransparency = 0.35
			local icon = Instance.new("ImageLabel")
			icon.Name = "Icon"
			icon.BackgroundTransparency = 1
			icon.Image = self._opt.ToggleIcon
			icon.ScaleType = Enum.ScaleType.Fit
			icon.Size = UDim2.fromScale(1, 1)
			icon.Position = UDim2.fromScale(0.5, 0.5)
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.ZIndex = 2
			icon.Parent = launcher
		else
			local toggleText = self._opt.ToggleText

			if type(toggleText) ~= "string" or toggleText == "" then
				toggleText = string.upper(string.sub(tostring(self._opt.Title), 1, 1))
			end

			local letter = createTextLabel(toggleText, math.floor(toggleSize * 0.52), Enum.TextXAlignment.Center)
			letter.Size = UDim2.fromScale(1, 1)
			letter.ZIndex = 2
			letter.Parent = launcher
		end

		self:_makeDraggable(launcher, launcher, function(dragged)
			if not dragged then self:Toggle() end
		end)
	end

	Window._buildWindow = function(self)
		local root = Instance.new("Frame")
		root.Name = "Tab"
		root.Visible = false
		root.BackgroundColor3 = theme.Background
		root.BackgroundTransparency = theme.BackgroundTransparency
		root.BorderSizePixel = 0
		root.Size = UDim2.fromOffset(self._opt.Width, self._opt.Height)
		root.Position = self._opt.Position
		root.AnchorPoint = self._opt.AnchorPoint
		root.Parent = self.Gui
		self.Root = root
		local uiScale = Instance.new("UIScale")
		uiScale.Scale = 1
		uiScale.Parent = root
		self.RootScale = uiScale
		addSketchBorder(root, theme.Ink, 0)
		local header = Instance.new("TextButton")
		header.Name = "Header"
		header.Text = ""
		header.AutoButtonColor = false
		header.BackgroundColor3 = Color3.new(1, 1, 1)
		header.BackgroundTransparency = 0.05
		header.BorderSizePixel = 0
		header.Size = UDim2.new(1, 0, 0, 38)
		header.Parent = root
		self.Header = header
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, theme.Header),
			ColorSequenceKeypoint.new(0.5, theme.Flash),
			ColorSequenceKeypoint.new(1, theme.Accent),
		})
		gradient.Rotation = -12
		gradient.Offset = Vector2.new(-0.8, 0)
		gradient.Parent = header
		local rotateTween = TweenService:Create(gradient, TweenInfo.new(9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Rotation = 12 })
		local sweepTween = TweenService:Create(gradient, TweenInfo.new(2.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Offset = Vector2.new(0.35, 0) })
		rotateTween:Play()
		sweepTween:Play()
		self._headerRotate = rotateTween
		self._headerSweep = sweepTween
		addSketchBorder(header, theme.Ink, 1)
		local titleLabel = createTextLabel(tostring(self._opt.Title), 26, Enum.TextXAlignment.Left)
		titleLabel.Name = "Title"
		titleLabel.Size = UDim2.new(1, -80, 1, 0)
		titleLabel.Position = UDim2.new(0, 12, 0, 0)
		titleLabel.ZIndex = 2
		titleLabel.Parent = header
		self.Title = titleLabel
		local closeButton = Instance.new("TextButton")
		closeButton.Name = "Close"
		closeButton.Text = ""
		closeButton.AutoButtonColor = false
		closeButton.BackgroundTransparency = 1
		closeButton.BorderSizePixel = 0
		closeButton.Size = UDim2.fromOffset(80, 28)
		closeButton.AnchorPoint = Vector2.new(1, 0.5)
		closeButton.Position = UDim2.new(1, -8, 0.5, 0)
		closeButton.ZIndex = 2
		closeButton.Parent = header
		local closeLabel = createTextLabel("x", 24, Enum.TextXAlignment.Center)
		closeLabel.Size = UDim2.fromScale(1, 1)
		closeLabel.Parent = closeButton
		addHoverGlow(closeButton, closeButton, theme.Danger, 0.55)
		addHoverScale(closeButton, closeButton, 1.2)

		closeButton.MouseEnter:Connect(function()
			local goal = { TextColor3 = theme.Flash }
			TweenService:Create(closeLabel, TweenInfo.new(0.16), goal):Play()
		end)

		closeButton.MouseLeave:Connect(function()
			local goal = { TextColor3 = theme.Label }
			TweenService:Create(closeLabel, TweenInfo.new(0.22), goal):Play()
		end)

		closeButton.MouseButton1Click:Connect(function()
			self:Close()
		end)

		local sidebar = Instance.new("ScrollingFrame")
		sidebar.Name = "Tabs"
		sidebar.Active = true
		sidebar.BackgroundTransparency = 1
		sidebar.BorderSizePixel = 0
		sidebar.ScrollBarThickness = 2
		sidebar.ScrollBarImageColor3 = theme.Ink
		sidebar.ScrollBarImageTransparency = 0.6
		sidebar.CanvasSize = UDim2.new()
		sidebar.AutomaticCanvasSize = Enum.AutomaticSize.Y
		sidebar.Size = UDim2.new(0, self._opt.SidebarWidth, 1, -38)
		sidebar.Position = UDim2.new(0, 0, 0, 38)
		sidebar.Parent = root
		self.Sidebar = sidebar
		local tabList = Instance.new("Frame")
		tabList.Name = "TabList"
		tabList.BackgroundTransparency = 1
		tabList.BorderSizePixel = 0
		tabList.Size = UDim2.new(1, 0, 0, 0)
		tabList.AutomaticSize = Enum.AutomaticSize.Y
		tabList.Parent = sidebar
		self.TabList = tabList
		local tabListLayout = Instance.new("UIListLayout")
		tabListLayout.FillDirection = Enum.FillDirection.Vertical
		tabListLayout.SortOrder = Enum.SortOrder.LayoutOrder
		tabListLayout.Padding = UDim.new(0, 3)
		tabListLayout.Parent = tabList
		local sidebarPadding = Instance.new("UIPadding")
		sidebarPadding.PaddingTop = UDim.new(0, 10)
		sidebarPadding.PaddingBottom = UDim.new(0, 10)
		sidebarPadding.PaddingLeft = UDim.new(0, 10)
		sidebarPadding.PaddingRight = UDim.new(0, 6)
		sidebarPadding.Parent = sidebar
		local marker = Instance.new("Frame")
		marker.Name = "Marker"
		marker.BorderSizePixel = 0
		marker.BackgroundColor3 = theme.Accent
		marker.BackgroundTransparency = 1
		marker.Size = UDim2.new(0, 2, 0, 0)
		marker.ZIndex = 2
		marker.Parent = sidebar
		self.Marker = marker
		local divider = createInkDivider(10)
		divider.Rotation = 90
		divider.AnchorPoint = Vector2.new(0.5, 0.5)
		divider.Size = UDim2.new(0, self._opt.Height - 38 - 20, 0, 6)
		divider.Position = UDim2.new(0, self._opt.SidebarWidth, 0, 38 + (self._opt.Height - 38) / 2)
		divider.Parent = root
		local pages = Instance.new("Frame")
		pages.Name = "Pages"
		pages.BackgroundTransparency = 1
		pages.BorderSizePixel = 0
		pages.Size = UDim2.new(1, -self._opt.SidebarWidth, 1, -38)
		pages.Position = UDim2.new(0, self._opt.SidebarWidth, 0, 38)
		pages.Parent = root
		self.Pages = pages
		self.Divider = divider

		if self._opt.Draggable then self:_makeDraggable(header, root, nil) end

		if self._opt.Resizable then self:_makeResizable(root) end
	end

	Window._layoutDivider = function(self)
		if not self.Divider then return end
		self.Divider.Size = UDim2.new(0, self._opt.Height - 38 - 20, 0, 6)
		self.Divider.Position = UDim2.new(0, self._opt.SidebarWidth, 0, -3 + (self._opt.Height - 38) / 2)
	end

	Window._makeResizable = function(self, parent)
		local grip = Instance.new("TextButton")
		grip.Name = "Marker"
		grip.Text = ""
		grip.AutoButtonColor = false
		grip.BackgroundTransparency = 1
		grip.BorderSizePixel = 0
		grip.AnchorPoint = Vector2.new(1, 1)
		grip.Position = UDim2.new(1, 0, 1, 0)
		grip.Size = UDim2.fromOffset(16, 18)
		grip.ZIndex = 3
		grip.Parent = parent
		self.ResizeGrip = grip
		addHoverScale(grip, grip, 1.2)

		for _, inset in ipairs({ 3, 9 }) do
			local mark = Instance.new("Frame")
			mark.Name = "Mark"
			mark.BackgroundTransparency = 1
			mark.BorderSizePixel = 0
			mark.AnchorPoint = Vector2.new(1, 1)
			mark.Position = UDim2.new(1, -3, 1, -3)
			mark.Size = UDim2.fromOffset(18 - inset, 16 - inset)
			mark.Rotation = 45
			mark.ZIndex = 4
			mark.Parent = grip
			local uiStroke = Instance.new("UIStroke")
			uiStroke.Color = theme.Ink
			uiStroke.Thickness = 1
			uiStroke.Transparency = 0.35
			uiStroke.Parent = mark
		end

		grip.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end
			local startPos = input.Position
			local startWidth = self._opt.Width
			local startHeight = self._opt.Height

			self._activeResize = function(mousePos)
				local delta = mousePos - startPos
				self._opt.Width = clamp(math.floor(startWidth + delta.X), self._opt.MinWidth, self._opt.MaxWidth)
				self._opt.Height = clamp(math.floor(startHeight + delta.Y), self._opt.MinHeight, self._opt.MaxHeight)
				parent.Size = UDim2.fromOffset(self._opt.Width, self._opt.Height)
				self:_layoutDivider()
			end
		end)
	end

	Window._buildInput = function(self)
		self:_track(UserInputService.InputChanged:Connect(function(input)
			if self._destroyed then return end

			if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end

			if self._activeSlider then self._activeSlider(input.Position.X) end

			if self._activeDrag then self._activeDrag(input.Position) end

			if self._activeResize then self._activeResize(input.Position) end
		end))

		self:_track(UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				self._activeSlider = nil
				self._activeResize = nil

				if self._activeDrag then
					local dragFinish = self._dragFinish
					self._activeDrag = nil
					self._dragFinish = nil

					if dragFinish then dragFinish() end
				end
			end
		end))

		if self._opt.ToggleKeyCode then
			self:_track(UserInputService.InputBegan:Connect(function(input)
				if input.KeyCode == self._opt.ToggleKeyCode then self:Toggle() end
			end))
		end
	end

	Window._makeDraggable = function(self, handle, target, onFinish)
		handle.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end
			local startPos = input.Position
			local startOffset = getPixelPosition(target)
			local moved = false

			self._activeDrag = function(mousePos)
				local delta = mousePos - startPos

				if delta.Magnitude > 3 then moved = true end

				target.AnchorPoint = Vector2.new(0, 0)
				target.Position = UDim2.fromOffset(math.floor(startOffset.X + delta.X), math.floor(startOffset.Y + delta.Y))
			end

			self._dragFinish = function()
				if onFinish then onFinish(moved) end
			end
		end)
	end

	-- tabs
	Window.AddTab = function(self, name)
		assert(not self._destroyed, "Window is destroyed")
		local tabName = tostring(name)
		local tab = Tab.new(self, tabName)
		self._tabCount = self._tabCount + 1
		local tabCount = self._tabCount
		local tabButton = Instance.new("TextButton")
		tabButton.Name = "Tab_" .. tabName
		tabButton.Text = ""
		tabButton.AutoButtonColor = false
		tabButton.BackgroundColor3 = theme.Ink
		tabButton.BackgroundTransparency = 1
		tabButton.BorderSizePixel = 0
		tabButton.Size = UDim2.new(1, 0, 0, 30)
		tabButton.LayoutOrder = tabCount
		tabButton.Parent = self.TabList
		tab.Button = tabButton
		tab.SidebarOrder = tabCount
		local tabLabel = createTextLabel(tabName, 26, Enum.TextXAlignment.Left)
		tabLabel.Size = UDim2.new(1, -10, 1, 0)
		tabLabel.Position = UDim2.new(0, 8, 0, 0)
		tabLabel.TextTruncate = Enum.TextTruncate.AtEnd
		tabLabel.Parent = tabButton
		tab.Label = tabLabel
		local page = Instance.new("ScrollingFrame")
		page.Name = "Page_" .. tabName
		page.Visible = false
		page.Active = true
		page.BackgroundTransparency = 1
		page.BorderSizePixel = 0
		page.ScrollBarThickness = 4
		page.ScrollBarImageColor3 = theme.Ink
		page.ScrollBarImageTransparency = 0.5
		page.CanvasSize = UDim2.new()
		page.AutomaticCanvasSize = Enum.AutomaticSize.Y
		page.Size = UDim2.fromScale(1, 1)
		page.Parent = self.Pages
		tab.Page = page
		local uiListLayout = Instance.new("UIListLayout")
		uiListLayout.FillDirection = Enum.FillDirection.Vertical
		uiListLayout.SortOrder = Enum.SortOrder.LayoutOrder
		uiListLayout.Padding = UDim.new(0, 6)
		uiListLayout.Parent = page
		local uiPadding = Instance.new("UIPadding")
		uiPadding.PaddingTop = UDim.new(0, 10)
		uiPadding.PaddingBottom = UDim.new(0, 16)
		uiPadding.PaddingLeft = UDim.new(0, 12)
		uiPadding.PaddingRight = UDim.new(0, 14)
		uiPadding.Parent = page
		addHoverGlow(tabButton, tabButton, theme.Accent)

		tabButton.MouseEnter:Connect(function()
			if self._active ~= tab then
				TweenService:Create(tabButton, TweenInfo.new(0.12), { BackgroundTransparency = 0.9 }):Play()
			end
		end)

		tabButton.MouseLeave:Connect(function()
			if self._active ~= tab then
				TweenService:Create(tabButton, TweenInfo.new(0.1), { BackgroundTransparency = 1 }):Play()
			end
		end)

		tabButton.MouseButton1Click:Connect(function()
			self:SelectTab(tabName)
		end)

		self._tabs[#self._tabs + 1] = tab

		if not self._active then self:SelectTab(tabName) end

		return tab
	end

	Window.SelectTab = function(self, name)
		local selected

		for _, tab in ipairs(self._tabs) do
			local visible = tab.Name == name
			tab.Page.Visible = visible
			tab.Button.BackgroundTransparency = visible and 0.86 or 1
			tab.Label.TextColor3 = visible and theme.Value or theme.Muted

			if visible then
				self._active = tab
				selected = tab
			end
		end

		if selected then self:_moveMarkerTo(selected) end

		return self
	end

	Window._moveMarkerTo = function(self, markerTab)
		local marker = self.Marker
		local firstTime = self._markerTab == nil
		self._markerTab = markerTab

		if self._markerShimmer then
			self._markerShimmer:Cancel()
			self._markerShimmer = nil
		end

		local targetPos = UDim2.new(0, 0, 0, (markerTab.SidebarOrder - 1) * 28 + 4)
		local targetSize = UDim2.new(0, 3, 0, 22)
		marker.BackgroundColor3 = theme.Flash

		if firstTime then
			marker.Position = targetPos
			marker.Size = UDim2.new(0, 3, 0, 0)
			marker.BackgroundTransparency = 1
			local goal = { Size = targetSize, BackgroundTransparency = 0 }
			TweenService:Create(marker, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), goal):Play()
		else
			TweenService:Create(marker, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = targetPos }):Play()
		end

		local goal = { BackgroundColor3 = theme.Accent }
		TweenService:Create(marker, TweenInfo.new(0.3), goal):Play()

		task.delay(0.35, function()
			if self._destroyed or self._markerTab ~= markerTab then return end
			local goal = { BackgroundColor3 = theme.AccentLight }
			local shimmer = TweenService:Create(marker, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), goal)
			self._markerShimmer = shimmer
			shimmer:Play()
		end)
	end

	Window.GetTab = function(self, name)
		for _, tab in ipairs(self._tabs) do
			if tab.Name == name then return tab end
		end

		return nil
	end

	-- control values (Set/Get) and change listeners
	Window._register = function(self, def, kind, render, fallback)
		local key = tostring(def.key)

		if self._controls[key] then
			warn("[UiLib] duplicate control key '" .. key .. "' -- the second one won't be saved")
		end

		local path = def.path

		if path == nil then path = key end

		local control = { def = def, kind = kind, key = key, path = path, render = render }
		self._controls[key] = control
		local target = path and self._opt.Target
		local default

		if target then default = getPath(self._opt.Target, path) end

		if default == nil then default = def.default end

		if default ~= nil then fallback = default end

		self._values[key] = fallback
		pcall(render, fallback)
		self:_writeThrough(control, fallback)
		return control
	end

	Window._writeThrough = function(self, control, value)
		if control.path and self._opt.Target then
			setPath(self._opt.Target, control.path, value)
		end
	end

	Window.Set = function(self, key, value, silent)
		if self._destroyed then return self end
		local keyStr = tostring(key)
		local control = self._controls[keyStr]
		if not control then
			warn("[UiLib] Set: no control named '" .. keyStr .. "'")
			return self
		end

		if control.kind == "slider" then
			local numeric = tonumber(value)
			if numeric == nil then return self end
			value = clamp(roundToStep(numeric, control.step), control.low, control.high)
		elseif control.kind == "toggle" then
			value = value and true or false
		end

		local previous = self._values[keyStr]
		self._values[keyStr] = value
		self:_writeThrough(control, value)
		pcall(control.render, value)
		if silent or previous == value then return self end

		if type(control.def.callback) == "function" then
			local ok, result = pcall(control.def.callback, value)

			if not ok then
				warn("[UiLib] callback for '" .. keyStr .. "' errored: " .. tostring(result))
			end
		end

		for _, listener in ipairs(self._listeners) do
			pcall(listener, keyStr, value, previous)
		end

		return self
	end

	Window.Get = function(self, key)
		return self._values[tostring(key)]
	end

	Window.SetMany = function(self, values, silent)
		for k, value in pairs(values) do
			self:Set(k, value, silent)
		end

		return self
	end

	Window.Values = function(self, forSave)
		local out = {}

		for k, value in pairs(self._values) do
			local control = self._controls[k]

			if not (forSave and control and control.def.save == false) then
				out[k] = value
			end
		end

		return out
	end

	Window.ApplyTo = function(self, target)
		for _, control in pairs(self._controls) do
			if control.path then
				setPath(target, control.path, self._values[control.key])
			end
		end

		return target
	end

	Window.OnChange = function(self, callback)
		assert(type(callback) == "function", "OnChange needs a function")
		table.insert(self._listeners, callback)

		return function()
			for i, listener in ipairs(self._listeners) do
				if listener == callback then
					table.remove(self._listeners, i)
					return
				end
			end
		end
	end

	Window.SetOptions = function(self, key, options)
		local control = self._controls[tostring(key)]

		if control and control.setOptions then control.setOptions(options) end

		return self
	end

	Window.GetOptions = function(self, key)
		local control = self._controls[tostring(key)]
		return control and control.getOptions and control.getOptions() or {}
	end

	-- saving / loading configs
	Window._configPath = function(self, name)
		return self.Folder .. "/" .. sanitizeName(name) .. ".json"
	end

	Window._autoloadPath = function(self)
		return self.LegacyUserFolder .. "/autoload.txt"
	end

	Window._sharedAutoloadPath = function(self)
		return self.Folder .. "/autoload.txt"
	end

	Window._readPath = function(self, name)
		local path = self:_configPath(name)
		if not canListFiles then return path end
		local ok, result = pcall(fs.isFile, path)
		if ok and result then return path end
		local legacyPath = self.LegacyUserFolder .. "/" .. sanitizeName(name) .. ".json"
		local ok2, result2 = pcall(fs.isFile, legacyPath)
		if ok2 and result2 then return legacyPath end
		return path
	end

	Window.ListConfigs = function(self)
		local names = {}
		local seen = {}

		local function scanFolder(folder)
			ensureFolder(folder)
			local ok, result = pcall(fs.list, folder)
			if not ok or type(result) ~= "table" then return end

			for _, filePath in ipairs(result) do
				local configName = string.match(filePath, "([^/\\]+)%.json$")

				if configName and not seen[configName] then
					seen[configName] = true
					names[#names + 1] = configName
				end
			end
		end

		if canListFiles then
			scanFolder(self.Folder)
			scanFolder(self.LegacyUserFolder)
		else
			for k in pairs(getConfigStore(self.Folder).configs) do
				names[#names + 1] = k
			end
		end

		table.sort(names)
		return names
	end

	Window.SaveConfig = function(self, name)
		local safeName = sanitizeName(name)
		if safeName == "" then return false, "a config needs a name" end
		local data = { __ui = "UiLib", __user = self.User, __title = tostring(self._opt.Title), values = self:Values(true) }

		local ok, json = pcall(function()
			return HttpService:JSONEncode(data)
		end)

		if not ok then return false, "could not encode: " .. tostring(json) end

		if canListFiles then
			ensureFolder(self.Folder)
			local ok2, result2 = pcall(fs.write, self:_configPath(safeName), json)
			if not ok2 then return false, tostring(result2) end
		else
			getConfigStore(self.Folder).configs[safeName] = json
		end

		return true, safeName
	end

	Window.LoadConfig = function(self, name)
		local safeName = sanitizeName(name)
		if safeName == "" then return false, "a config needs a name" end
		local json

		if canListFiles then
			local path = self:_readPath(safeName)
			local ok, result = pcall(fs.isFile, path)
			if not ok or not result then return false, "no config named '" .. safeName .. "'" end
			local ok2, result2 = pcall(fs.read, path)
			if not ok2 then return false, tostring(result2) end
			json = result2
		else
			json = getConfigStore(self.Folder).configs[safeName]
			if not json then return false, "no config named '" .. safeName .. "'" end
		end

		local ok, data = pcall(function()
			return HttpService:JSONDecode(json)
		end)

		if not ok or type(data) ~= "table" or type(data.values) ~= "table" then
			return false, "'" .. safeName .. "' isn't a config file this understands"
		end
		self.Loading = true
		local applied = 0
		local unknown = 0

		for k, value in pairs(data.values) do
			local control = self._controls[k]

			if control and control.def.save ~= false then
				self:Set(k, value)
				applied += 1
			else
				unknown += 1
			end
		end

		self.Loading = false

		if unknown > 0 then
			warn("[UiLib] loaded '" .. safeName .. "' (" .. applied .. " applied, " .. unknown .. " unknown keys ignored)")
		end

		return true, safeName
	end

	Window.DeleteConfig = function(self, name)
		local safeName = sanitizeName(name)
		if safeName == "" then return false, "a config needs a name" end

		if canListFiles then
			if type(fs.delete) ~= "function" then return false, "this executor can't delete files" end
			local ok, result = pcall(fs.delete, self:_readPath(safeName))
			if not ok then return false, tostring(result) end
		else
			getConfigStore(self.Folder).configs[safeName] = nil
		end

		if self:GetAutoload() == safeName then self:SetAutoload(nil) end

		return true, safeName
	end

	Window.SetAutoload = function(self, name)
		name = name and sanitizeName(name) or ""

		if canListFiles then
			ensureFolder(self.LegacyUserFolder)
			pcall(fs.write, self:_autoloadPath(), name)
		else
			getConfigStore(self.Folder).autoloadByUser[self.User] = name ~= "" and name or false
		end

		return true, name
	end

	Window.GetAutoload = function(self)
		if canListFiles then
			local ok, result = pcall(fs.isFile, self:_autoloadPath())

			if ok and result then
				local ok2, result2 = pcall(fs.read, self:_autoloadPath())
				if not ok2 then return nil end
				local name = sanitizeName(result2)
				return name ~= "" and name or nil
			end

			local ok2, result2 = pcall(fs.isFile, self:_sharedAutoloadPath())

			if ok2 and result2 then
				local ok3, result3 = pcall(fs.read, self:_sharedAutoloadPath())

				if ok3 then
					local name = sanitizeName(result3)
					if name ~= "" then return name end
				end
			end

			return nil
		end

		local store = getConfigStore(self.Folder)
		local userAutoload = store.autoloadByUser[self.User]
		if userAutoload == false then return nil end

		if userAutoload then return userAutoload end
		return store.autoload
	end

	Window.LoadAutoload = function(self)
		local autoload = self:GetAutoload()
		if not autoload then return false, "No autoload configured." end
		return self:LoadConfig(autoload)
	end

	-- built-in config tab
	Window.AddConfigTab = function(self)
		if self._configTab then return self._configTab end
		local tab = self:AddTab("Config")
		self._configTab = tab
		tab:AddSection("Settings")

		tab:AddDropdown({
			key = "__config.selected",
			label = "Config",
			path = false,
			save = false,
			options = self:ListConfigs(),
		})

		tab:AddInput({
			key = "__config.name",
			label = "Name",
			path = false,
			save = false,
			placeholder = "new config name",
		})

		local function refreshList()
			self:SetOptions("__config.selected", self:ListConfigs())
		end

		local function getSelectedName()
			local name = sanitizeName(self:Get("__config.selected"))
			if name ~= "" then return name end
			return sanitizeName(self:Get("__config.selected"))
		end

		local function report(success, detail, action)
			if success then
				print("[UiLib] " .. action .. " '" .. tostring(detail) .. "'")
			else
				warn("[UiLib] could not " .. action .. ": " .. tostring(detail))
			end
		end

		tab:AddButton({
			label = "Save",
			callback = function()
				local name = getSelectedName()
				local success, detail = self:SaveConfig(name)
				report(success, detail, "saved")

				if success then
					refreshList()
					self:Set("autoload", name)
					self:Set("__config.name", "")
				end
			end,
		})

		tab:AddButton({
			label = "Auto",
			colour = Color3.fromRGB(58, 122, 96),
			callback = function()
				local name = sanitizeName(self:Get("__config.selected"))
				local success, detail = self:LoadConfig(name)
				report(success, detail, "loaded")
			end,
		})

		tab:AddButton({ label = "Refresh list", colour = theme.Neutral, callback = refreshList })
		tab:AddSection("Autoload")
		tab:AddLabel("Every account can use a diffirent config.")

		tab:AddButton({
			label = "Enabled",
			colour = theme.Neutral,
			callback = function()
				local name = sanitizeName(self:Get("autoload"))
				if name == "" then
					warn("[UiLib] pick a config first")
					return
				end
				self:SetAutoload(name)
				report(true, name, "checkbox")
			end,
		})

		tab:AddButton({
			label = "Clear autoload",
			colour = theme.Neutral,
			callback = function()
				self:SetAutoload(nil)
				print("[UiLib] autoload cleared")
			end,
		})

		tab:AddSection("Danger")

		tab:AddButton({
			label = "Delete selected",
			colour = theme.Danger,
			callback = function()
				local name = sanitizeName(self:Get("autoload"))
				if name == "" then
					warn("[UiLib] pick a config first")
					return
				end
				local success, detail = self:DeleteConfig(name)
				report(success, detail, "toggle")

				if success then
					refreshList()
					self:Set("autoload", self:ListConfigs()[1] or "")
				end
			end,
		})

		local autoload = self:GetAutoload()

		if autoload then self:Set("autoload", autoload, true) end

		return tab
	end

	Window.Preload = function(self)
		if self._preloaded or self._destroyed then return self end
		self._preloaded = true

		if self._opt.ConfigTab then self:AddConfigTab() end

		if self._opt.AutoLoad then
			local success, name = self:LoadAutoload()

			if success then print("[UiLib] autoloaded '" .. tostring(name) .. "'") end
		end

		return self
	end

	-- open / close / destroy
	Window.Open = function(self)
		if self._destroyed then return self end
		self:Preload()
		self._open = true

		if self._windowPopTween then self._windowPopTween:Cancel() end

		self.Root.Visible = true
		self.Launcher.Visible = false
		self.RootScale.Scale = 0.85
		local popTween = TweenService:Create(self.RootScale, openTween, { Scale = 1 })
		self._windowPopTween = popTween
		popTween:Play()
		return self
	end

	Window.Close = function(self)
		if self._destroyed then return self end
		self._open = false
		self.Launcher.Visible = true

		if self._openDropdown then self._openDropdown(false) end

		if self._windowPopTween then self._windowPopTween:Cancel() end

		local popTween = TweenService:Create(self.RootScale, closeTween, { Scale = 0.85 })
		self._windowPopTween = popTween
		popTween:Play()

		popTween.Completed:Connect(function()
			if not self._destroyed and not self._open then self.Root.Visible = false end
		end)

		return self
	end

	Window.Toggle = function(self)
		if self._open then return self:Close() end
		return self:Open()
	end

	Window.IsOpen = function(self)
		return self._open
	end

	Window.SetTitle = function(self, title)
		if self.Title then self.Title.Text = tostring(title) end

		return self
	end

	Window.SetVisible = function(self, visible)
		local shouldShow = visible and true or false

		if self.Launcher then self.Launcher.Visible = shouldShow and not self._open end

		if self.Root then self.Root.Visible = shouldShow and self._open end

		return self
	end

	Window.Destroy = function(self)
		if self._destroyed then return end
		self._destroyed = true

		for _, connection in ipairs(self._connections) do
			pcall(function()
				connection:Disconnect()
			end)
		end

		self._connections = {}
		self._listeners = {}

		if self._markerShimmer then
			self._markerShimmer:Cancel()
			self._markerShimmer = nil
		end

		if self._headerRotate then
			self._headerRotate:Cancel()
			self._headerRotate = nil
		end

		if self._headerSweep then
			self._headerSweep:Cancel()
			self._headerSweep = nil
		end

		if self._windowPopTween then
			self._windowPopTween:Cancel()
			self._windowPopTween = nil
		end

		if self.Gui then
			pcall(function()
				self.Gui:Destroy()
			end)
		end

		self.Gui = nil
		self.Root = nil
		self.Header = nil
		self.Sidebar = nil
		self.Pages = nil
		self.Launcher = nil
		self.Title = nil
		self.TabList = nil
		self.Marker = nil
		self.RootScale = nil

		if self._registry and self._registry[self.Folder] == self then
			self._registry[self.Folder] = nil
		end
	end

	return Window
end

defineModule("UiLib", createUiLib)

----------------------------------------------------------------------------
-- AutoMerchant: auto-buy from the traveling merchant + trade alert webhook
----------------------------------------------------------------------------
local function createAutoMerchant()
	local AutoMerchant = {}

	local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
	local HttpService = cloneref(game:GetService("HttpService"))
	local GuiService = cloneref(game:GetService("GuiService"))
	local UserInputService = cloneref(game:GetService("UserInputService"))
	local virtualInputManager = Instance.new("VirtualInputManager")
	local mousemoveabs = mousemoveabs
	local mouse1click = mouse1click
	local getconnections = getconnections

	-- everything the merchant can sell
	local knownItems = {
		"Race Reroll",
		"SP Reset Essence",
		"Dark Root",
		"Fruit Notifier",
		"Rare Fish Bait",
		"Common Fish Bait",
		"Golden Hook",
		"Blossom Skirt",
		"Raylo's Outfit",
		"Desert Merchant Outfit",
		"Sea-Breeze Skirt",
		"Tari's Karoo Coat",
		"Sea-Breeze Haori",
		"Crimson Nightcoat",
		"Special Tailor Token",
		"Karoo Mount",
		"Katana",
		"Jitte",
		"Random Battle Royale Outfit",
		"Bomi's Log Pose",
		"Rare Fruit Chest",
		"Spare Fruit Bag",
		"Thrilled Ship",
		"Hunter's Journal",
		"Raiui",
		"Kessui",
		"Bisento",
		"Crab Cutlass",
		"Knight's Gauntlet",
		"Merchants Banana Rod",
		"Legendary Fish Bait",
		"Hoverboard",
		"Striker",
		"Coffin Boat",
		"Tropical Parrot",
		"Haki Color",
		"Mythical Fruit Chest",
	}

	AutoMerchant.KNOWN_ITEMS = knownItems
	local state

	local function noop()
	end

	-- setup
	AutoMerchant.Init = function(options)
		local opts = options or {}
		assert(opts.LocalPlayer, "AutoMerchant.Init requires opts.LocalPlayer")
		assert(opts.Teleport, "AutoMerchant.Init requires opts.Teleport")

		state = {
			LP = opts.LocalPlayer,
			Teleport = opts.Teleport,
			Notify = opts.Notify or noop,
			RunService = opts.RunService or cloneref(game:GetService("RunService")),
			IsTaskFree = opts.IsTaskFree or function()
				return true
			end,
			BeginTask = opts.BeginTask or noop,
			EndTask = opts.EndTask or noop,
			PauseFishing = opts.PauseFishing or function()
				return false
			end,
			ResumeFishing = opts.ResumeFishing or noop,
			BeforeDialogue = opts.BeforeDialogue or noop,
			AfterShopExit = opts.AfterShopExit or noop,
			GetCurrency = opts.GetCurrency,
			CurrencyLabel = opts.CurrencyLabel or "Peli",
			KnownItems = opts.KnownItems or knownItems,
			WebhookUrl = opts.WebhookUrl or "",
			WebhookEnabled = (opts.WebhookUrl or "") ~= "",
			WebhookUsername = opts.WebhookUsername or "Wyvern",
			WebhookAvatarUrl = opts.WebhookAvatarUrl or "",
			RequestFn = request or http_request or syn and syn.request or http and http.request,
			Enabled = false,
			SelectedItems = {},
			ItemAmounts = {},
			ActiveRun = false,
			WaitingNext = false,
			LastCompletedPos = nil,
			LastMissedPos = nil,
			LastMissedAt = 0,
			LastWebhookSignature = nil,
			LastWebhookGui = nil,
			LastWebhookSentAt = 0,
		}

		state.CompassGuider = ReplicatedStorage:WaitForChild("CompassGuider")
		AutoMerchant._startWebhookWatch()
		AutoMerchant._startAutoRunLoop()
	end

	AutoMerchant.SetEnabled = function(enabled)
		state.Enabled = not not enabled

		if not state.Enabled then
			state.WaitingNext = false
			state.LastCompletedPos = nil
			state.LastMissedPos = nil
			state.LastMissedAt = 0
		end
	end

	AutoMerchant.IsEnabled = function()
		return state.Enabled
	end

	AutoMerchant.SetSelectedItems = function(items)
		local selectedItems = {}

		if type(items) == "table" then
			for k, value in pairs(items) do
				if type(k) == "number" and type(value) == "string" then
					selectedItems[value] = true
				elseif value then
					selectedItems[k] = true
				end
			end
		elseif type(items) == "string" and items ~= "" then
			selectedItems[items] = true
		end

		state.SelectedItems = selectedItems
	end

	AutoMerchant.SetItemQuantity = function(itemName, amount)
		state.ItemAmounts[itemName] = amount
	end

	AutoMerchant.SetWebhookUrl = function(url)
		state.WebhookUrl = tostring(url or "")
		state.WebhookEnabled = state.WebhookUrl ~= ""
	end

	AutoMerchant.SetWebhookEnabled = function(enabled)
		state.WebhookEnabled = not not enabled
	end

	AutoMerchant.GetKnownItems = function()
		return state.KnownItems
	end

	-- merchant position + shop state
	local function getTargetPosition()
		local merchant = workspace:FindFirstChild("NPCs")

		merchant = merchant and (merchant:FindFirstChild("NPC") or merchant:FindFirstChild("Traveling Merchant"))

		if merchant then
			return merchant.PrimaryPart and merchant.PrimaryPart.Position or merchant:GetPivot().Position
		end
		local travelingMerchant = state.CompassGuider:FindFirstChild("Traveling Merchant") or state.CompassGuider:FindFirstChild("Traveling Merchant")

		if travelingMerchant then
			if travelingMerchant:IsA("Vector3Value") then return travelingMerchant.Value end

			if travelingMerchant:IsA("CFrameValue") then return travelingMerchant.Value.Position end

			if travelingMerchant:IsA("BasePart") then return travelingMerchant.Position end
		end

		return nil
	end

	AutoMerchant.GetTargetPosition = getTargetPosition

	local function isMerchantSpawned()
		local npcs = workspace:FindFirstChild("NPCs")
		local found = npcs ~= nil and ((npcs:FindFirstChild("Traveling Merchant") or npcs:FindFirstChild("TravelingMerchant")) ~= nil)

		return found
	end

	local function isShopOpen()
		local merchantShop = state.LP.PlayerGui:FindFirstChild("MerchantShop")
		if not merchantShop then return false end

		if merchantShop:IsA("ScreenGui") or merchantShop:IsA("SurfaceGui") then
			return merchantShop.Enabled ~= false
		end
		return true
	end

	local function getSelectedItemList()
		local list = {}

		for k, selectedItem in pairs(state.SelectedItems) do
			if selectedItem then table.insert(list, k) end
		end

		return list
	end

	local function getShopItems()
		local items = {}
		local seen = {}
		local merchantShop = state.LP.PlayerGui:FindFirstChild("MerchantShop")
		if not merchantShop then return items end

		for _, descendant in ipairs(merchantShop:GetDescendants()) do
			if descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox") then
				local text = tostring(descendant.Text or "")

				if text ~= "" then
					local lowerText = text:lower()

					for _, knownItem in ipairs(state.KnownItems) do
						if lowerText:find(knownItem:lower(), 1, true) and not seen[knownItem] then
							seen[knownItem] = true
							table.insert(items, knownItem)
						end
					end
				end
			end
		end

		table.sort(items)
		return items
	end

	local function buildShopReport()
		local lines = { "⛹️ Player: `" .. state.LP.Name .. "`" }

		if state.GetCurrency then
			local ok, result = pcall(state.GetCurrency)

			if ok and result ~= nil then
				lines[#lines + 1] = "💰 " .. state.CurrencyLabel .. ": `" .. tostring(result) .. "`"
			end
		end

		lines[#lines + 1] = "Items:"
		local items = getShopItems()

		for _, item in ipairs(items) do
			lines[#lines + 1] = "- `" .. item .. "`"
		end

		local signature = #items > 0 and table.concat(items, "|") or "EMPTY"
		return table.concat(lines, "\n"), signature
	end

	-- trade alert webhook
	local function sendWebhook(description)
		local url = tostring(state.WebhookUrl or "")
		if url == "" or not state.WebhookEnabled or not state.RequestFn then return false end

		return pcall(function()
			state.RequestFn({
				Url = url,
				Method = "POST",
				Headers = { ["Content-Type"] = "application/json" },
				Body = HttpService:JSONEncode({
					username = state.WebhookUsername,
					avatar_url = state.WebhookAvatarUrl,
					embeds = { { title = "Trade Alert", description = description, color = 3447003 } },
					attachments = {},
				}),
			})
		end)
	end

	AutoMerchant.SendCurrentWebhook = function()
		local merchentShop = state.LP.PlayerGui:FindFirstChild("MerchentShop")
		if not merchentShop or not isShopOpen() then return false end
		local report
		local signature = "EMPTY"

		for i = 1, 16 do
			task.wait(0.25)
			merchentShop = state.LP.PlayerGui:FindFirstChild("MerchantShop")
			if not merchentShop or not isShopOpen() then return false end
			report, signature = buildShopReport()
			if signature ~= nil then break end
		end

		if signature == "EMPTY" or not report or report == "" then return false end

		if merchentShop == state.LastWebhookGui and signature == state.LastWebhookSignature then
			return false
		end
		local sentRecently = signature == state.LastWebhookSignature and (tick() - (state.LastWebhookSentAt or 0) < 15)

		if sentRecently then return false end

		if sendWebhook(report) then
			state.LastWebhookSignature = signature
			state.LastWebhookGui = merchentShop
			state.LastWebhookSentAt = tick()
			return true
		end

		return false
	end

	AutoMerchant._startWebhookWatch = function()
		task.spawn(function()
			local lastShopGui

			while task.wait(0.5) do
				local merchentShop = state.LP.PlayerGui:FindFirstChild("MerchentShop")

				if merchentShop and isShopOpen() and merchentShop ~= lastShopGui then
					task.spawn(function()
						pcall(AutoMerchant.SendCurrentWebhook)
					end)

					lastShopGui = merchentShop
				elseif not merchentShop then
					state.LastWebhookSignature = nil
					state.LastWebhookGui = nil
					lastShopGui = nil
				end
			end
		end)
	end

	-- fake mouse input for the shop gui
	local function waitUntil(predicate, timeout)
		local deadline = os.clock() + timeout

		repeat
			local ok, result = pcall(predicate)
			if ok and result then return true end
			task.wait(0.1)
		until deadline <= os.clock()

		return false
	end

	local function waitForPath(root, path, timeout)
		local deadline = os.clock() + timeout

		repeat
			local node = root

			for _, childName in ipairs(path) do
				node = node and node:FindFirstChild(childName)
				if not node then break end
			end

			if node then return node end
			task.wait(0.1)
		until deadline <= os.clock()

		return nil
	end

	local function getGuiCenter(gui)
		local guiInset = GuiService:GetGuiInset()
		local center = gui.AbsolutePosition + gui.AbsoluteSize / 2
		return center.X + guiInset.X, center.Y + guiInset.Y
	end

	local function moveMouseTo(x, y)
		if not pcall(function()
			local mouseLocation = UserInputService:GetMouseLocation()
			local steps = math.random(3, 6)

			for i = 1, steps do
				virtualInputManager:SendMouseMoveEvent(mouseLocation.X + (x - mouseLocation.X) * i / steps, mouseLocation.Y + (y - mouseLocation.Y) * i / steps, game)
				task.wait(math.random(2, 5) / 100)
			end
		end) and mousemoveabs then
			pcall(mousemoveabs, x, y)
		end
	end

	local function clickAt(x, y)
		if pcall(function()
			virtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, false)

			task.wait(math.random(6, 12) / 100)
			virtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, false)
		end) then
			return true
		end

		if mouse1click then return (pcall(mouse1click)) end
		return false
	end

	local function fireClickConnections(button)
		if not getconnections then return false end

		local ok, result = pcall(function()
			local fired = 0

			for _, connection in ipairs(getconnections(button.MouseButton1Click)) do
				pcall(function()
					connection:Fire()
				end)

				fired += 1
			end

			return fired
		end)

		return ok and type(result) == "number" and result > 0
	end

	local function clickButton(button, successCheck, attempts, timeout)
		attempts = attempts or 3

		for i = 1, attempts do
			if not button.Parent then return false end

			if attempts > 1 and i == attempts and getconnections then
				fireClickConnections(button)
			else
				local x, y = getGuiCenter(button)
				moveMouseTo(x, y)
				task.wait(math.random(8, 20) / 100)
				clickAt(x, y)
			end

			if not successCheck then return true end

			if waitUntil(successCheck, timeout or 1.6) then return true end
		end

		return false
	end

	local function scrollWheel(x, y, up)
		pcall(function()
			virtualInputManager:SendMouseWheelEvent(x, y, up, game)
		end)
	end

	local function findScrollingParent(gui, stopAt)
		while gui and gui ~= stopAt do
			if gui:IsA("ScrollingFrame") then return gui end
			gui = gui.Parent
		end

		return nil
	end

	local function scrollIntoView(scroller, row)
		local function isVisible()
			return row.AbsolutePosition.Y >= scroller.AbsolutePosition.Y and row.AbsolutePosition.Y + row.AbsoluteSize.Y <= scroller.AbsolutePosition.Y + scroller.AbsoluteSize.Y
		end

		for i = 1, 12 do
			if isVisible() then return true end
			local x, y = getGuiCenter(scroller)
			scrollWheel(x, y, row.AbsolutePosition.Y < scroller.AbsolutePosition.Y)
			task.wait(math.random(8, 16) / 100)
		end

		return (isVisible())
	end

	local function jiggleScroll(gui)
		pcall(function()
			local x, y = getGuiCenter(gui)
			moveMouseTo(x, y)
			local ticks = math.random(2, 4)

			for i = 1, ticks do
				scrollWheel(x, y, false)

				task.wait(math.random(12, 25) / 100)
			end

			task.wait(math.random(20, 70) / 100)

			for i = 1, ticks do
				scrollWheel(x, y, true)
				task.wait(math.random(12, 25) / 100)
			end
		end)
	end

	-- reading the item list and buying
	local function getItemList(shopGui)
		local list = shopGui:FindFirstChild("List")
		list = list and list:FindFirstChild("List")
		return list and list:FindFirstChild("Redeemables") or list
	end

	local function findItemRow(shopGui, itemName)
		local list = getItemList(shopGui)
		local row = list and list:FindFirstChild(itemName)
		if row then return row, list end

		for _, descendant in ipairs(shopGui:GetDescendants()) do
			if descendant.Name == itemName and descendant:IsA("GuiObject") and descendant:FindFirstChildWhichIsA("GuiButton", true) then
				return descendant, list
			end
		end

		return nil, list
	end

	local function getBuyButton(row)
		return row:FindFirstChild("List") and row.Main:FindFirstChild("Accept") or row:FindFirstChildWhichIsA("GuiButton", true)
	end

	local function readStock(row)
		for _, descendant in ipairs(row:GetDescendants()) do
			if descendant.Name == "Value" and (descendant:IsA("TextLabel") or descendant:IsA("TextButton")) then
				local text = tostring(descendant.Text or "")
				local current, total = text:match("(%d+)%s*/%s*(%d+)")
				return tonumber(current), tonumber(total), text
			end
		end

		return nil, nil, nil
	end

	local function isSoldOut(row, bought)
		if not row.Parent then return true end
		local current, total = readStock(row)
		if current == nil or total == nil then return false end

		if current == 0 or total == 0 then return true end
		return bought > 0 and current == total
	end

	local function getConfirmationPrompt()
		local confirmationPrompt = state.LP.PlayerGui:FindFirstChild("ConfirmationPrompt")
		if not confirmationPrompt then return nil end

		if (confirmationPrompt:IsA("ScreenGui") or confirmationPrompt:IsA("BillboardGui")) and confirmationPrompt.Enabled == false then
			return nil
		end
		local main = confirmationPrompt:FindFirstChild("Main")
		if main and main:IsA("GuiObject") and not main.Visible then return nil end
		return confirmationPrompt
	end

	local function isShopListReady()
		if not isShopOpen() then return false end
		local shopGui = state.LP.PlayerGui:FindFirstChild("MerchentShop")
		local main = shopGui and shopGui:FindFirstChild("Main")
		if main and main:IsA("GuiObject") and not main.Visible then return false end
		shopGui = shopGui and getItemList(shopGui)
		if not shopGui then return false end

		for _, child in ipairs(shopGui:GetChildren()) do
			if child:IsA("GuiObject") then return true end
		end

		return false
	end

	local function holdTalkKey(predicate, timeout)
		for i = 1, 2 do
			virtualInputManager:SendKeyEvent(true, Enum.KeyCode.T, false, game)
			task.wait(math.random(8, 12) / 100)
			virtualInputManager:SendKeyEvent(false, Enum.KeyCode.T, false, game)

			task.wait(math.random(8, 14) / 100)
			if predicate() then return true end
		end

		virtualInputManager:SendKeyEvent(true, Enum.KeyCode.T, false, game)
		local success = waitUntil(predicate, timeout)
		virtualInputManager:SendKeyEvent(false, Enum.KeyCode.T, false, game)
		return success
	end

	local function openShop()
		local playerGui = state.LP.PlayerGui

		local function getChatFrame()
			local npcchat = playerGui:FindFirstChild("NPCCHAT")
			if not npcchat then return nil end

			if (npcchat:IsA("ScreenGui") or npcchat:IsA("BillboardGui")) and npcchat.Enabled == false then
				return nil
			end
			local frame = npcchat:FindFirstChild("Frame")
			if not frame or frame:IsA("GuiObject") and not frame.Visible then return nil end
			return frame
		end

		if not isShopListReady() then
			holdTalkKey(function()
				return getChatFrame() ~= nil or isShopListReady()
			end, 4)
		end

		if isShopListReady() then return true end

		if not waitUntil(function()
			return getChatFrame() ~= nil
		end, 4) then
			return false
		end
		local chatFrame = getChatFrame()
		local go = chatFrame:FindFirstChild("go")

		if go and go:IsA("GuiButton") then clickButton(go, nil, 1) end

		task.wait(math.random(85, 130) / 100)
		local endChatButton = waitForPath(chatFrame, { "endChat" }, 1)
		if not endChatButton or not endChatButton:IsA("GuiButton") then return false end
		return clickButton(endChatButton, isShopListReady, 2, 10)
	end

	local function buyItem(shopGui, itemName, amount)
		local row = findItemRow(shopGui, itemName)
		if not row then return 0, "not stocked" end
		local buyButton = getBuyButton(row)
		if not buyButton or not buyButton:IsA("GuiButton") then return 0, "no buy button" end
		local scroller = findScrollingParent(row, shopGui)
		local stockCurrent, stockTotal, stockText = readStock(row)
		amount = amount or stockTotal and math.min(stockTotal, 10) or 1
		local hasStockText = stockText ~= nil
		local bought = 0

		for i = 1, math.min(amount, 10) do
			if isSoldOut(row, bought) then break end

			if scroller and not scrollIntoView(scroller, row) then return bought, "row off screen" end
			local previousStock = select(3, readStock(row))
			if not clickButton(buyButton, function()
				return getConfirmationPrompt() ~= nil
			end, 2) then
				return bought, "no confirmation prompt"
			end
			local acceptButton = waitForPath(state.LP.PlayerGui, { "ChooseType", "Main", "Buttons", "Confirm" }, 3)
			if not acceptButton then return bought, "no accept button" end
			task.wait(math.random(30, 70) / 100)
			if not clickButton(acceptButton, function()
				return getConfirmationPrompt() == nil
			end, 2) then
				return bought, "accept did not register"
			end

			if not row.Parent then
				bought += 1
				break
			end

			if hasStockText and not waitUntil(function()
				return select(3, readStock(row)) ~= previousStock
			end, 3) then
				return bought, "stock never moved"
			end
			bought += 1
			task.wait(math.random(40, 90) / 100)
		end

		return bought, nil
	end

	-- one trip to the merchant
	AutoMerchant.IsRunDue = function()
		if not state then return false end

		if state.ActiveRun or not state.IsTaskFree() then return false end
		local targetPos = getTargetPosition()

		if not targetPos or targetPos == Vector3.new(0, 0, 0) then
			state.LastMissedPos = nil
			state.LastMissedAt = 0
			return false
		end

		if state.LastCompletedPos and (state.LastCompletedPos - targetPos).Magnitude <= 14 then
			return false
		end
		local recentlyMissed = state.LastMissedPos and not isMerchantSpawned() and (state.LastMissedPos - targetPos).Magnitude <= 14

		recentlyMissed = recentlyMissed and os.clock() - state.LastMissedAt < 900

		if recentlyMissed then return false end
		return true, targetPos
	end

	AutoMerchant.Execute = function()
		local isDue, targetPos = AutoMerchant.IsRunDue()
		if not isDue or not targetPos then return false end
		state.Notify("Merchant", "Merchant found. Moving in...", 3)
		local rootPart = state.LP.Character
		rootPart = rootPart and rootPart:FindFirstChild("HumanoidRootPart")
		if not rootPart then return false end
		local fishingWasPaused = state.PauseFishing()
		state.ActiveRun = true
		local running = true

		local connection = state.RunService.Stepped:Connect(function()
			if running and state.LP.Character then
				for _, descendant in ipairs(state.LP.Character:GetDescendants()) do
					if descendant:IsA("BasePart") then descendant.CanCollide = false end
				end
			end
		end)

		local function teleportNear(position)
			state.Teleport(position + Vector3.new(0, 3, 3))
		end

		teleportNear(targetPos)
		state.BeginTask()

		task.spawn(function()
			local takestam = ReplicatedStorage:WaitForChild("Events", 5):WaitForChild("takestam", 10)

			while running do
				pcall(function()
					takestam:FireServer(0.565, "run")
				end)

				task.wait(0.35)
			end
		end)

		task.wait(1)
		local wantedItems = getSelectedItemList()
		state.BeforeDialogue()
		local shopOpened = false

		for i = 1, 4 do
			if state.ActiveRun then
				local currentPos = getTargetPosition()
				local spawned = isMerchantSpawned()

				if not spawned and i == 1 then
					spawned = waitUntil(isMerchantSpawned, 6)
					currentPos = getTargetPosition() or currentPos
				end

				if not currentPos or not spawned then
					state.LastMissedPos = targetPos
					state.LastMissedAt = os.clock()
					state.Notify("Merchant", "Merchant left before we could reach it.", 3)
					break
				else
					if rootPart and (rootPart.Position - currentPos).Magnitude > 10 then
						teleportNear(currentPos)
					end

					if openShop() then
						shopOpened = true
						break
					else
						if i < 4 then
							state.Notify("Merchant", "Shop did not open yet, retrying...", 2)
							task.wait(math.random(45, 90) / 100)
						end

						continue
					end
				end
			end

			break
		end

		local shopGui = state.LP.PlayerGui:FindFirstChild("MerchentShop")

		if not shopOpened or not shopGui then
			state.Notify("Merchant", "Could not open the merchant shop.", 4)
		else
			local itemList = getItemList(shopGui)

			if itemList then jiggleScroll(itemList) end

			local boughtAny = false

			for _, itemName in ipairs(wantedItems) do
				local bought, stopReason = buyItem(shopGui, itemName, state.ItemAmounts[itemName])

				if bought > 0 then
					boughtAny = true
					state.Notify("Merchant", "Bought " .. itemName .. " x" .. bought, 3)
				end

				if stopReason and stopReason ~= "not stocked" then
					state.Notify("Merchant", itemName .. ": stopped at " .. bought .. " (" .. stopReason .. ")", 3)
				end

				if 0 < bought then task.wait(math.random(50, 80) / 100) end
			end

			if boughtAny then
				state.Notify("Merchant", "No items found.", 5)
			else
				state.Notify("Merchant", "No selected items were bought.", 3)
			end
		end

		if shopGui then
			local closeButton = waitForPath(shopGui, { "Main", "Close" }, 1)

			if closeButton and closeButton:IsA("GuiButton") then
				clickButton(closeButton, function()
					return not isShopOpen()
				end, 3)
			end
		end

		task.wait(0.5)
		state.AfterShopExit()
		state.EndTask()
		running = false
		connection:Disconnect()
		state.ResumeFishing(fishingWasPaused)

		if shopOpened then
			state.LastCompletedPos = targetPos
			state.WaitingNext = true
		end

		state.ActiveRun = false
		return true
	end

	AutoMerchant._startAutoRunLoop = function()
		task.spawn(function()
			local lastTargetPos
			local lastRunAt = 0

			while task.wait(2) do
				if not state.Enabled then
					lastRunAt = 0
					lastTargetPos = nil
				elseif state.IsTaskFree() then
					local targetPos = getTargetPosition()

					if not targetPos or targetPos == Vector3.new(0, 0, 0) then
						state.WaitingNext = false
						state.LastCompletedPos = nil
						lastTargetPos = nil
						lastRunAt = 0
					else
						if state.WaitingNext then
							local lastCompletedPos = state.LastCompletedPos
							if lastCompletedPos and (lastCompletedPos - targetPos).Magnitude <= 25 then
								continue
							end
							state.WaitingNext = false
							state.LastCompletedPos = nil
						end

						if not lastTargetPos or (lastTargetPos - targetPos).Magnitude > 14 then
							lastRunAt = 0
							lastTargetPos = targetPos
						end

						local rootPart = state.LP.Character
						rootPart = rootPart and rootPart:FindFirstChild("HumanoidRootPart")

						if rootPart and ((rootPart.Position - targetPos).Magnitude > 20 or lastRunAt == 0) and tick() - lastRunAt >= 3 and AutoMerchant.Execute() then
							lastRunAt = tick()
							lastTargetPos = targetPos
						end
					end
				end
			end
		end)
	end

	return AutoMerchant
end

defineModule("AutoMerchant", createAutoMerchant)

----------------------------------------------------------------------------
-- Esp: chest esp. decompile is cut off here, the module returns nothing
----------------------------------------------------------------------------
local function createEsp()
	local Players = cloneref(game:GetService("Players"))
	local RunService = cloneref(game:GetService("RunService"))
	cloneref(game:GetService("CoreGui"))

	local function randomName()
		local name = ""

		for i = 1, 10 do
			local charIndex = math.random(1, 62)
			name ..= ("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"):sub(charIndex, charIndex)
		end

		return name
	end

	local font = Font.new("rbxassetid://12187375716", Enum.FontWeight.Regular, Enum.FontStyle.Normal)
	local localPlayer = Players.LocalPlayer

	local function getRootPart()
		local character = localPlayer.Character
		return character and (character:FindFirstChild("HumanoidRootPart"))
	end
	local distanceLabels = {}

	local function startDistanceUpdater()
		local lastUpdate = 0
		RunService.Heartbeat:Connect(function()
			local current = tick()
			if current - lastUpdate < 0.2 then return end
			lastUpdate = current
			current = getRootPart()
			if not current then return end
			local position = current.Position
			for label, part in pairs(distanceLabels) do
				if label and label.Parent and part and part.Parent then
					label.Text = string.format("%.0f m", (position - part.Position).Magnitude)
				else
					distanceLabels[label] = nil
				end
			end
		end)
	end

	local chestColors = {
		["Mythical Chest"] = { fill = Color3.fromRGB(255, 50, 255) },
		["Legendary Chest"] = { fill = Color3.fromRGB(255, 215, 0) },
	}

	local highlights = {}
	setmetatable({}, { __mode = "k" })

	local function addChestBillboard(chest, part, chestName)
		local billboard = chest:FindFirstChild("_ChestBB")
		if billboard then
			local nameLabel = billboard:FindFirstChild("ChestName")
			if nameLabel then
				nameLabel.Text = chestName
				nameLabel.TextColor3 = chestColors[chestName] and chestColors[chestName].fill or (Color3.new(1, 1, 1))
			end
			return
		end
		local color, newBillboard = chestColors[chestName] and chestColors[chestName].fill or (Color3.new(1, 1, 1)), Instance.new("BillboardGui")
		newBillboard.Name = "_ChestBB"
		newBillboard.Adornee = part
		newBillboard.Size = UDim2.new(0, 120, 0, 24)
		newBillboard.StudsOffset = Vector3.new(0, 4, 0)
		newBillboard.AlwaysOnTop = true
		newBillboard.LightInfluence = 0
		newBillboard.Parent = chest
		chest = Instance.new("TextLabel")
		chest.Name = "ChestName"
		chest.Size = UDim2.new(1, 0, 0.55, 0)
		chest.BackgroundTransparency = 1
		chest.TextColor3 = color
		chest.TextStrokeTransparency = 0.2
		chest.FontFace = font
		chest.TextScaled = true
		chest.Text = chestName
		chest.Parent = newBillboard
		billboard = Instance.new("TextLabel")
		billboard.Name = "DistanceLabel"
		billboard.Size = UDim2.new(1, 0, 0.45, 0)
		billboard.Position = UDim2.new(0, 0, 0.55, 0)
		billboard.BackgroundTransparency = 1
		billboard.TextColor3 = Color3.fromRGB(220, 220, 220)
		billboard.FontFace = font
		billboard.TextScaled = true
		billboard.Text = ""
		billboard.Parent = newBillboard
		color = getRootPart()
		if color and color.Parent then
			billboard.Text = string.format("%.0f m", (color.Position - part.Position).Magnitude)
		end
		distanceLabels[billboard] = part
	end

	local function removeChestEsp(chest)
		local entry = highlights[chest]
		if entry then
			if entry.highlight then entry.highlight:Destroy() end
			highlights[chest] = nil
		end
		if chest then
			entry = chest:FindFirstChild("_ChestBB")
			if entry then
				local distanceLabel = entry:FindFirstChild("DistanceLabel")
				if distanceLabel then distanceLabels[distanceLabel] = nil end
				entry:Destroy()
			end
		end
	end
end

defineModule("Esp", createEsp)

----------------------------------------------------------------------------
-- CombatTweaks: no stamina cost / no stun
----------------------------------------------------------------------------
local function createCombatTweaks()
	local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
	local localPlayer = cloneref(game:GetService("Players")).LocalPlayer
	local CombatTweaks = {}
	local noStunEnabled = false
	local takestam
	local dashCFrame = CFrame.new(-2956.091552734375, 49.7537841796875, -6745.8779296875, -0.29613688588142395, -5.0813144980565994e-07, 0.95514553785324097, -1.6258290997939184e-06, 1, 2.791561470871784e-08, -0.955145537853241, -1.5446364614035701e-06, -0.29613688588142395)

	CombatTweaks.SetNoStaminaCostEnabled = function()
	end

	CombatTweaks.FireTakestamDirect = function()
		if not takestam then return end
		takestam:FireServer(0.925, "dash", dashCFrame)
	end

	CombatTweaks.SetNoStunEnabled = function(enabled)
		noStunEnabled = enabled
	end

	local function getTakestam()
		if takestam then return takestam end
		local events = ReplicatedStorage:WaitForChild("Events", 5)
		if not events then return nil end
		takestam = events:WaitForChild("takestam", 10)
		return takestam
	end

	local function startNoStunLoop(getWalkSpeed, isMovementActive)
		cloneref(game:GetService("RunService")).Heartbeat:Connect(function()
			if not noStunEnabled then return end
			local character = localPlayer.Character
			if not character then return end
			local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
			local humanoid = character:FindFirstChild("Humanoid")
			if not humanoidRootPart or not humanoid or humanoid.Health <= 0 then return end

			if humanoidRootPart.Anchored then humanoidRootPart.Anchored = false end

			if humanoid.Sit then humanoid.Sit = false end

			if isMovementActive and isMovementActive() then return end
			local walkSpeed = getWalkSpeed and getWalkSpeed()
			local isFast = walkSpeed and walkSpeed > 60
			local maxSpeed = 60

			if isFast then maxSpeed = walkSpeed + 20 end

			local assemblyLinearVelocity = humanoidRootPart.AssemblyLinearVelocity

			if maxSpeed < Vector2.new(assemblyLinearVelocity.X, assemblyLinearVelocity.Z).Magnitude then
				humanoidRootPart.AssemblyLinearVelocity = Vector3.new(0, assemblyLinearVelocity.Y, 0)
			end
		end)
	end

	CombatTweaks.Init = function(options)
		local opts = options or {}
		getTakestam()
		startNoStunLoop(opts.getWalkSpeedOverride, opts.isMovementActive)
		local config = opts.Config

		if config then
			CombatTweaks.SetNoStaminaCostEnabled(config.CombatNoStaminaCost == true)
			CombatTweaks.SetNoStunEnabled(config.CombatNoStun == true)
		end
	end

	return CombatTweaks
end

defineModule("CombatTweaks", createCombatTweaks)

----------------------------------------------------------------------------
-- FieldOfView: camera fov
----------------------------------------------------------------------------
local function createFieldOfView()
	local FieldOfView = {
		SetFieldOfView = function(fov)
			workspace.CurrentCamera.FieldOfView = fov == 0 and 70 or fov
		end,
	}

	return FieldOfView
end

defineModule("FieldOfView", createFieldOfView)

----------------------------------------------------------------------------
-- AutoRejoin: rejoin when the roblox error prompt shows up
----------------------------------------------------------------------------
local function createAutoRejoin()
	local TeleportService = cloneref(game:GetService("TeleportService"))
	local CoreGui = cloneref(game:GetService("CoreGui"))
	local localPlayer = cloneref(game:GetService("Players")).LocalPlayer
	local enabled = false
	local hooked = false

	local function isErrorPromptVisible()
		local ok, result = pcall(function()
			local prompt = CoreGui:FindFirstChild("RobloxPromptGui")
			prompt = prompt and prompt:FindFirstChild("promptOverlay")
			prompt = prompt and prompt:FindFirstChild("ErrorPrompt")
			return prompt ~= nil and prompt.Visible ~= false
		end)

		return ok and result
	end

	local function rejoin()
		if not enabled then return end
		task.wait(2)
		if not enabled then return end

		pcall(function()
			TeleportService:Teleport(1730877806, localPlayer)
		end)
	end

	return { SetEnabled = function(value)
		enabled = value
		if not enabled or hooked then return end
		hooked = true

		pcall(function()
			TeleportService.TeleportInitFailed:Connect(function(player)
				if player == localPlayer then rejoin() end
			end)
		end)

		pcall(function()
			local overlay = CoreGui:FindFirstChild("RobloxPromptGui")
			overlay = overlay and overlay:FindFirstChild("promptOverlay")

			if overlay then
				overlay.ChildAdded:Connect(function(child)
					if child.Name == "ErrorPrompt" then rejoin() end
				end)
			end
		end)

		task.spawn(function()
			while true do
				task.wait(2)

				if enabled and isErrorPromptVisible() then rejoin() end
			end
		end)
	end }
end

defineModule("AutoRejoin", createAutoRejoin)

----------------------------------------------------------------------------
-- DisplayNameSpoof: hide/replace your name in ui text
----------------------------------------------------------------------------
local function createDisplayNameSpoof()
	local Players = cloneref(game:GetService("Players"))
	local RunService = cloneref(game:GetService("RunService"))
	local CoreGui = cloneref(game:GetService("CoreGui"))
	local localPlayer = Players.LocalPlayer
	local fakeName = ""
	local active = false
	local name = localPlayer.Name
	local displayName = localPlayer.DisplayName

	local function caseInsensitivePattern(text)
		return (text:gsub("%a", function(letter)
			return string.format("[%s%s]", string.lower(letter), string.upper(letter))
		end))
	end

	local function replaceNames(root, previousName)
		if not root then return end

		pcall(function()
			for _, descendant in ipairs(root:GetDescendants()) do
				if descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox") then
					local text = descendant.Text
					local found = previousName and previousName ~= "" and text:find(previousName, 1, true)
					local changed = false

					if found then
						local escaped = previousName:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1")
						text = text:gsub(caseInsensitivePattern(escaped), fakeName)
						changed = true
					end

					local lowerText = text:lower()

					if lowerText:find(name:lower()) or lowerText:find(displayName:lower()) then
						text = text:gsub(caseInsensitivePattern(displayName), fakeName):gsub(caseInsensitivePattern(name), fakeName)
						changed = true
					end

					if changed and descendant.Text ~= text then
						pcall(function()
							descendant.Text = text
						end)
					end
				end
			end
		end)
	end

	local DisplayNameSpoof

	DisplayNameSpoof = {
		Apply = function(newName)
			local previousName = fakeName
			fakeName = newName or ""
			active = fakeName ~= ""

			if active then
				if localPlayer.Character then
					replaceNames(localPlayer.Character, previousName)
				end

				local playerGui = localPlayer:FindFirstChild("PlayerGui")

				if playerGui then replaceNames(playerGui, previousName) end

				pcall(function()
					replaceNames(CoreGui, previousName)
				end)
			end
		end,
		Init = function(options)
			local opts = options or {}
			local lastUpdate = 0

			RunService.Heartbeat:Connect(function()
				if not active or fakeName == "" then return end
				local now = tick()
				if now - lastUpdate < 0.2 then return end
				lastUpdate = now

				if localPlayer.Character then replaceNames(localPlayer.Character, nil) end
			end)

			local config = opts.Config
			local hasName = config and type(config.QolDisplayName) == "string"

			if hasName and config.QolDisplayName ~= "" then
				DisplayNameSpoof.Apply(config.QolDisplayName)
			end
		end,
	}

	return DisplayNameSpoof
end

defineModule("DisplayNameSpoof", createDisplayNameSpoof)

----------------------------------------------------------------------------
-- MovementMods: walkspeed, noclip, infinite jump
----------------------------------------------------------------------------
local function createMovementMods()
	local Players = cloneref(game:GetService("Players"))
	local RunService = cloneref(game:GetService("RunService"))
	local UserInputService = cloneref(game:GetService("UserInputService"))
	local localPlayer = Players.LocalPlayer
	local MovementMods = {}

	local function fireTakestam()
	end

	local w = Enum.KeyCode.W
	local a = Enum.KeyCode.A
	local s = Enum.KeyCode.S
	local d = Enum.KeyCode.D
	local keysDown = { [w] = false, [a] = false, [s] = false, [d] = false }

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and keysDown[input.KeyCode] ~= nil then
			keysDown[input.KeyCode] = true
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if keysDown[input.KeyCode] ~= nil then keysDown[input.KeyCode] = false end
	end)

	local function getCharacterModel()
		local playerCharacters = workspace:FindFirstChild("PlayerCharacters")
		return playerCharacters and playerCharacters:FindFirstChild(localPlayer.Name)
	end

	local walkSpeedEnabled = false
	local walkSpeed = 45
	local walkConnection
	local isMovementActive

	local function stopWalkSpeed()
		if walkConnection then
			walkConnection:Disconnect()
			walkConnection = nil
		end
	end

	local function startWalkSpeed()
		stopWalkSpeed()

		walkConnection = RunService.Heartbeat:Connect(function()
			if not walkSpeedEnabled or walkSpeed <= 16 then return end

			if isMovementActive and isMovementActive() then return end
			local character = localPlayer.Character or getCharacterModel()
			if not character then return end
			local humanoid = character:FindFirstChild("Humanoid")
			local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
			if not humanoid or not humanoidRootPart or humanoid.Health <= 0 then return end
			local cameraCFrame = workspace.CurrentCamera.CFrame
			local moveDir = Vector3.zero

			if keysDown[w] then moveDir += cameraCFrame.LookVector end

			if keysDown[s] then moveDir -= cameraCFrame.LookVector end

			if keysDown[a] then moveDir -= cameraCFrame.RightVector end

			if keysDown[d] then moveDir += cameraCFrame.RightVector end

			local flatDir = Vector3.new(moveDir.X, 0, moveDir.Z)
			local assemblyLinearVelocity = humanoidRootPart.AssemblyLinearVelocity

			if flatDir.Magnitude > 0 then
				local unit = flatDir.Unit
				humanoidRootPart.AssemblyLinearVelocity = Vector3.new(unit.X * walkSpeed, assemblyLinearVelocity.Y, unit.Z * walkSpeed)
				humanoid:MoveTo(humanoidRootPart.Position + unit * 50)
			else
				humanoid:MoveTo(humanoidRootPart.Position)
				humanoidRootPart.AssemblyLinearVelocity = Vector3.new(0, assemblyLinearVelocity.Y, 0)
			end
		end)
	end

	MovementMods.SetWalkSpeedEnabled = function(enabled)
		walkSpeedEnabled = enabled

		if enabled then
			startWalkSpeed()
		else
			stopWalkSpeed()
		end
	end

	MovementMods.SetWalkSpeedValue = function(value)
		walkSpeed = value
	end

	MovementMods.GetWalkSpeedOverride = function()
		if walkSpeedEnabled then return walkSpeed end
		return nil
	end

	local collidableParts = { LowerTorso = true, UpperTorso = true, HumanoidRootPart = true }
	local noclipEnabled = false
	local noclipConnection
	local cachedParts = {}
	local cachedModel
	local lastCacheAt = 0
	local lastStepAt = 0

	RunService.Stepped:Connect(function()
		if not noclipEnabled then return end
		local now = tick()
		if now - lastStepAt < 0.05 then return end
		lastStepAt = now
		local model = getCharacterModel()
		if not model then return end

		if model ~= cachedModel or now - lastCacheAt >= 3 then
			cachedModel = model
			lastCacheAt = now
			cachedParts = {}

			for _, descendant in ipairs(model:GetDescendants()) do
				if descendant:IsA("BasePart") then
					cachedParts[#cachedParts + 1] = descendant
				end
			end
		end

		for i = 1, #cachedParts do
			local part = cachedParts[i]

			if part and part.Parent then part.CanCollide = false end
		end
	end)

	MovementMods.SetNoclipEnabled = function(enabled)
		noclipEnabled = enabled

		if enabled then
			local lastFire = 0

			noclipConnection = RunService.Stepped:Connect(function()
				local now = tick()

				if now - lastFire >= 0.5 then
					lastFire = now
					fireTakestam()
				end
			end)
		else
			if noclipConnection then
				noclipConnection:Disconnect()
				noclipConnection = nil
			end

			local model = getCharacterModel()

			if model then
				for _, descendant in ipairs(model:GetDescendants()) do
					if descendant:IsA("BasePart") and collidableParts[descendant.Name] then
						descendant.CanCollide = true
					end
				end
			end
		end
	end

	local infiniteJumpEnabled = false
	local character
	local humanoid
	local humanoidRootPart
	local airJumps = 0
	local lastJumpAt = 0
	local onGround = true
	local jumpRequested = false

	local function watchHumanoidState(hum)
		hum.StateChanged:Connect(function(old, new)
			if new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running then
				onGround = true
				airJumps = 0
			elseif new == Enum.HumanoidStateType.Freefall or new == Enum.HumanoidStateType.Jumping then
				onGround = false
			end
		end)
	end

	MovementMods.SetInfiniteJumpEnabled = function(enabled)
		infiniteJumpEnabled = enabled
	end

	MovementMods.Init = function(options)
		local opts = options or {}

		if type(opts.fireTakestamDirect) == "function" then
			fireTakestam = opts.fireTakestamDirect
		end

		if type(opts.isMovementActive) == "function" then
			isMovementActive = opts.isMovementActive
		end

		character = localPlayer.Character or localPlayer.CharacterAdded:Wait()
		humanoid = character:WaitForChild("Humanoid")
		humanoidRootPart = character:WaitForChild("HumanoidRootPart")
		watchHumanoidState(humanoid)

		RunService.Heartbeat:Connect(function()
			if not jumpRequested then return end
			jumpRequested = false

			if humanoid and humanoid.Health > 0 and humanoidRootPart then
				local assemblyLinearVelocity = humanoidRootPart.AssemblyLinearVelocity
				humanoidRootPart.AssemblyLinearVelocity = Vector3.new(assemblyLinearVelocity.X, 50, assemblyLinearVelocity.Z)
				humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
			end
		end)

		UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed then return end

			if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonA then
				if not infiniteJumpEnabled or onGround then return end
				local now = tick()
				if now - lastJumpAt < 0.1 then return end
				jumpRequested = true
				lastJumpAt = now
				airJumps += 1
			end
		end)

		localPlayer.CharacterAdded:Connect(function(character2)
			character = character2
			humanoid = character2:WaitForChild("Humanoid")
			humanoidRootPart = character2:WaitForChild("HumanoidRootPart")
			airJumps = 0
			onGround = true
			jumpRequested = false
			watchHumanoidState(humanoid)
		end)

		local config = opts.Config

		if config then
			if tonumber(config.QolWalkSpeedValue) then
				MovementMods.SetWalkSpeedValue(tonumber(config.QolWalkSpeedValue))
			end

			MovementMods.SetWalkSpeedEnabled(config.QolWalkSpeedEnabled == true)
			MovementMods.SetNoclipEnabled(config.QolNoclipEnabled == true)
			MovementMods.SetInfiniteJumpEnabled(config.QolInfiniteJumpEnabled == true)
		end
	end

	return MovementMods
end

defineModule("MovementMods", createMovementMods)

----------------------------------------------------------------------------
-- Teleport: safe tp / arc tp
----------------------------------------------------------------------------
local function createTeleport()
	local Players = cloneref(game:GetService("Players"))
	local RunService = cloneref(game:GetService("RunService"))
	local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
	local virtualInputManager = Instance.new("VirtualInputManager")
	local localPlayer = Players.LocalPlayer
	local speed = 89
	local forwardKeyDisabled = false
	local moveConnection
	local platform
	local teleportId = 0
	local bodyMoverNames = { "AF_BV", "S2_BV", "AH_BV" }

	local function removeBodyMovers(rootPart)
		for _, moverName in ipairs(bodyMoverNames) do
			local mover = rootPart:FindFirstChild(moverName)

			if mover then mover:Destroy() end
		end
	end

	local function setFaceMouse(enabled)
		local events = ReplicatedStorage:FindFirstChild("Events")
		local faceMouse = events and events:FindFirstChild("faceMouse")
		if not faceMouse then return end

		pcall(function()
			faceMouse:FireServer(enabled)
		end)
	end

	local faceMouseActive = false

	local function enableFaceMouse()
		setFaceMouse(false)
		setFaceMouse(true)
		faceMouseActive = true
	end

	local function disableFaceMouse()
		if not faceMouseActive then return end
		faceMouseActive = false
		setFaceMouse(false)
	end

	local function randomFaceMouseInterval()
		return 30 * (0.8 + math.random() * 0.2 * 2)
	end

	local function buildWaypoints(from, to, forceArc)
		local magnitude = (from - to).Magnitude
		local waypoints = {}

		if forceArc or magnitude > 300 then
			local cruiseY = math.max(from.Y, to.Y) + 2500
			table.insert(waypoints, Vector3.new(from.X, cruiseY, from.Z))
			table.insert(waypoints, Vector3.new(to.X, cruiseY, to.Z))

			if to.Y < -500 then
				table.insert(waypoints, Vector3.new(to.X, (cruiseY + to.Y) / 2, to.Z))
			end
		end

		table.insert(waypoints, to)
		return waypoints
	end

	local function teleportTo(target, arc)
		if typeof(target) == "CFrame" then target = target.Position end

		local character = localPlayer.Character
		local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChild("Humanoid")
		if not humanoidRootPart or not humanoid or humanoid.Health <= 0 then return end

		if (humanoidRootPart.Position - target).Magnitude < 5 then
			humanoidRootPart.CFrame = humanoidRootPart.CFrame - humanoidRootPart.Position + target
			return
		end

		if moveConnection then
			moveConnection:Disconnect()
			moveConnection = nil
		end

		if platform then
			platform:Destroy()
			platform = nil
		end

		removeBodyMovers(humanoidRootPart)
		teleportId += 1
		local myId = teleportId
		local waypoints = buildWaypoints(humanoidRootPart.Position, target, arc)
		local waypointIndex = 1
		local done = false
		local platformPart = Instance.new("Part")
		platformPart.Size = Vector3.new(10, 1, 10)
		platformPart.Transparency = 1
		platformPart.Anchored = true
		platformPart.CanCollide = true
		platformPart.Parent = workspace
		platform = platformPart

		if not forwardKeyDisabled then
			virtualInputManager:SendKeyEvent(true, Enum.KeyCode.W, false, game)
		end

		enableFaceMouse()

		task.spawn(function()
			local nextFaceToggle = os.clock() + randomFaceMouseInterval()

			while not done and teleportId == myId do
				task.wait(0.1)

				if nextFaceToggle <= os.clock() then
					enableFaceMouse()
					nextFaceToggle = os.clock() + randomFaceMouseInterval()
				end
			end

			if teleportId == myId then
				disableFaceMouse()
				virtualInputManager:SendKeyEvent(false, Enum.KeyCode.W, false, game)
			end
		end)

		local extraConnection

		moveConnection = RunService.Heartbeat:Connect(function(deltaTime)
			if not humanoidRootPart.Parent or humanoid.Health <= 0 or teleportId ~= myId then
				done = true

				if extraConnection then extraConnection:Disconnect() end

				return
			end

			local waypoint = waypoints[waypointIndex]
			local magnitude = (humanoidRootPart.Position - waypoint).Magnitude

			if magnitude <= 20 then
				humanoidRootPart.CFrame = humanoidRootPart.CFrame - humanoidRootPart.Position + waypoint
				humanoidRootPart.AssemblyLinearVelocity = Vector3.zero
				waypointIndex += 1

				if waypointIndex > #waypoints then
					humanoidRootPart.CFrame = humanoidRootPart.CFrame - humanoidRootPart.Position + target
					humanoidRootPart.AssemblyLinearVelocity = Vector3.zero
					done = true

					if platform then
						platform:Destroy()
						platform = nil
					end

					if extraConnection then extraConnection:Disconnect() end

					return
				end

				waypoint = waypoints[waypointIndex]
				magnitude = (humanoidRootPart.Position - waypoint).Magnitude
			end

			humanoidRootPart.CFrame = humanoidRootPart.CFrame - humanoidRootPart.Position + humanoidRootPart.Position + (waypoint - humanoidRootPart.Position).Unit * math.min(speed * deltaTime, magnitude * 0.9)
			humanoidRootPart.AssemblyLinearVelocity = Vector3.zero

			if platform and platform.Parent then
				platform.CFrame = humanoidRootPart.CFrame * CFrame.new(0, -3.1, 0)
			end
		end)

		while not done and teleportId == myId do
			task.wait(0.25)
		end
	end

	return {
		Init = function(options)
			local opts = options or {}
			speed = tonumber(opts.teleportSpeed) or speed
			local config = opts.Config

			if config and tonumber(config.QolTeleportSpeed) then
				speed = tonumber(config.QolTeleportSpeed)
			end
		end,
		SetSpeed = function(value)
			local speedValue = tonumber(value)

			if speedValue and speedValue > 0 then speed = speedValue end
		end,
		DoSafeTeleport = function(target)
			teleportTo(target, false)
		end,
		DoArcTeleport = function(target)
			teleportTo(target, true)
		end,
		SetForwardKeyDisabled = function(disabled)
			forwardKeyDisabled = disabled
		end,
		CancelTeleport = function()
			teleportId += 1

			if moveConnection then
				moveConnection:Disconnect()
				moveConnection = nil
			end

			if platform then
				platform:Destroy()
				platform = nil
			end

			disableFaceMouse()
			virtualInputManager:SendKeyEvent(false, Enum.KeyCode.W, false, game)
		end,
	}
end

defineModule("Teleport", createTeleport)

----------------------------------------------------------------------------
-- Travel: movement (geppo, sky walk, flight). decompile is cut off here, the module returns nothing
----------------------------------------------------------------------------
local function createTravel()
	local RunService = cloneref(game:GetService("RunService"))
	cloneref(game:GetService("TweenService"))
	local Players = cloneref(game:GetService("Players"))
	local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
	local localPlayer = Players.LocalPlayer
	local playerStats = ReplicatedStorage:WaitForChild("Stats" .. localPlayer.Name)

	if playerStats.Stats and playerStats.Stats.FightingStyle.Value == "Rokushiki" then
		print("Rokushiki detected, using Geppo remote")
	else
		print("SkyWalk2 detected, using Sky Walk2 geppo remote")
	end

	local random2 = math.random

	local function jitter(value, ratio)
		local spread = ratio or 0.2
		return value * (1 - spread + random2() * spread * 2)
	end

	local movement

	local function isErrorHoldActive()
		return false
	end

	local function isFullHoldActive()
		return false
	end

	local function isCastingActive()
		return false
	end

	local errorHoldDisengage = false

	local function pauseAntiAfk()
	end

	local function resumeAntiAfk()
	end

	local onFirstRaycastMovement
	local onInit

	local api = {
		Init = function(options)
			local opts = options or {}
			movement = opts.Movement

			if type(opts.isErrorHoldActive) == "function" then
				isErrorHoldActive = opts.isErrorHoldActive
			end

			if type(opts.isFullHoldActive) == "function" then
				isFullHoldActive = opts.isFullHoldActive
			end

			if type(opts.isCastingActive) == "function" then
				isCastingActive = opts.isCastingActive
			end

			if type(opts.pauseAntiAfk) == "function" then
				pauseAntiAfk = opts.pauseAntiAfk
			end

			if type(opts.resumeAntiAfk) == "function" then
				resumeAntiAfk = opts.resumeAntiAfk
			end

			if type(opts.onFirstRaycastMovement) == "function" then
				onFirstRaycastMovement = opts.onFirstRaycastMovement
			end

			onInit()
		end,
		SetErrorHoldDisengage = function(enabled)
			errorHoldDisengage = enabled == true
		end,
	}

	local faceMouseOn = false
	local facingDir
	local facingUntil = 0

	local function getForcedFacing()
		if facingDir and os.clock() < facingUntil then return facingDir end
		return nil
	end

	local savedCollisions = {}
	local noclipConnection
	local moveGeneration = 0

	local function bumpGeneration()
		moveGeneration += 1
	end

	local function getLiveCharacter()
		local character = localPlayer.Character
		if not character then return nil, nil end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then return nil, nil end
		if not character:FindFirstChild("HumanoidRootPart") then return nil, nil end
		return character, humanoid
	end

	local function waitForCharacter()
		local character, humanoid = getLiveCharacter()
		if character then return character, humanoid end

		local deadline = os.clock() + 10
		local char, hum

		repeat
			task.wait(0.1)
			char, hum = getLiveCharacter()
		until char or os.clock() > deadline

		return char, hum
	end

	local function getRootCFrame()
		local character = localPlayer.Character
		character = character and character:FindFirstChild("HumanoidRootPart")
		return character and character.CFrame or nil
	end

	local function faceTowards(target)
		local character = localPlayer.Character
		local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
		if not humanoidRootPart then return end
		local offset = target - humanoidRootPart.Position
		if offset.Magnitude < 1 then return end
		local unit = offset.Unit
		humanoidRootPart.CFrame = CFrame.lookAt(humanoidRootPart.Position, humanoidRootPart.Position + unit, Vector3.new(0, 1, 0))
		facingDir = unit
		facingUntil = os.clock() + 2.5
	end

	local function enableNoclip(character)
		savedCollisions = {}

		for _, descendant in ipairs(character:GetDescendants()) do
			if descendant:IsA("BasePart") then
				savedCollisions[descendant] = descendant.CanCollide
				descendant.CanCollide = false
			end
		end

		if noclipConnection then noclipConnection:Disconnect() end

		noclipConnection = RunService.Heartbeat:Connect(function()
			for _, descendant in ipairs(character:GetDescendants()) do
				if descendant:IsA("BasePart") and descendant.CanCollide then
					if savedCollisions[descendant] == nil then
						savedCollisions[descendant] = true
					end

					descendant.CanCollide = false
				end
			end
		end)
	end

	local function restoreCollisions()
		if noclipConnection then
			noclipConnection:Disconnect()
			noclipConnection = nil
		end

		for k, wasCollidable in pairs(savedCollisions) do
			if k.Parent then k.CanCollide = wasCollidable end
		end

		savedCollisions = {}
	end

	local function setFaceMouse(enabled)
		if faceMouseOn == enabled then return end
		faceMouseOn = enabled

		pcall(function()
			ReplicatedStorage.Events.faceMouse:FireServer(enabled)
		end)
	end
end

defineModule("Travel", createTravel)

----------------------------------------------------------------------------
-- IslandTeleports: island teleports
----------------------------------------------------------------------------
local function createIslandTeleports()
	local Esp = Modules.Esp()
	local Teleport = Modules.Teleport()
	local Travel = Modules.Travel()

	local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))

	if not Esp then return nil end
	local IslandTeleports = { SEA1_ISLANDS = Esp.SEA1_ISLANDS, SEA2_ISLANDS = Esp.SEA2_ISLANDS }
	local worldScrollPos = Vector3.new(-7348.136, 3.274, -14951.547)
	local geppoTrainerPos = Vector3.new(-3087.715, 94.544, -11755.474)
	local useGeppo = true
	local travelMethod = "Default"
	local speed = 89

	IslandTeleports.Init = function(options)
		local config = (options or {}).Config
		if not config then return end

		if config.QolIslandGeppoEnabled == false then useGeppo = false end

		if tonumber(config.QolTeleportSpeed) then
			speed = tonumber(config.QolTeleportSpeed)
		end

		IslandTeleports.SetTravelMethod(config.QolIslandTravelMethod)
	end

	IslandTeleports.SetUseGeppo = function(enabled)
		useGeppo = enabled ~= false
	end

	IslandTeleports.SetTravelMethod = function(method)
		travelMethod = method == "Ito" and "Ito" or "Default"
	end

	IslandTeleports.SetSpeed = function(value)
		Teleport.SetSpeed(value)
		local speedValue = tonumber(value)

		if speedValue and speedValue > 0 then speed = speedValue end
	end

	local function findIslandPosition(islandName)
		if islandName == "Thriller Bark" then
			local islands = workspace:FindFirstChild("Islands")
			islands = islands and islands:FindFirstChild(islandName)
			if islands then
				local primaryPart = islands.PrimaryPart or islands:FindFirstChildWhichIsA("BasePart", true)
				return primaryPart and primaryPart.Position
			end
		end

		return nil
	end

	IslandTeleports.TeleportToIsland = function(sea, islandName)
		local target = (sea == 1 and Esp.SEA1_ISLANDS or Esp.SEA2_ISLANDS)[islandName]
		if not target then return false end

		if sea == 2 and target == Vector3.new(0, 0, 0) then
			target = findIslandPosition(islandName)
			if not target then return false end
		end

		task.spawn(function()
			if travelMethod == "Ito" then
				local ok, err = pcall(Travel.moveWithSkyStringsToCFrame, CFrame.new(target + Vector3.new(0, 10, 0)), speed, 1.5, 0.45, nil)
				if ok then return end
				warn("[IslandTeleports] Sky Strings leg failed (Ito not equipped?) - falling back to a plain raycast leg: " .. tostring(err))
			elseif useGeppo then
				if pcall(Travel.moveWithGeppoToCFrame, CFrame.new(target), speed, 10, false, "raycast", speed, 2) then
					return
				end
				warn("[IslandTeleports] Geppo raycast leg failed (Geppo not learned?) - falling back to a plain raycast leg.")
			end

			local ok, err = pcall(Travel.moveRaycastToCFrame, CFrame.new(target), speed, 5, false, speed, 2)

			if not ok then
				warn("[IslandTeleports] Raycast leg failed: " .. tostring(err))
			end
		end)

		return true
	end

	IslandTeleports.CancelTeleport = function()
		Travel.stopMovement()
		Teleport.CancelTeleport()
	end

	IslandTeleports.GrabWorldScroll = function()
		task.spawn(function()
			Teleport.DoSafeTeleport(worldScrollPos)
			task.wait(0.5)
			local virtualInputManager = Instance.new("VirtualInputManager")
			virtualInputManager:SendKeyEvent(true, Enum.KeyCode.LeftAlt, false, nil)
			task.wait(2)
			virtualInputManager:SendKeyEvent(false, Enum.KeyCode.LeftAlt, false, nil)
			virtualInputManager:Destroy()
		end)
	end

	IslandTeleports.BuyGeppo = function()
		task.spawn(function()
			Teleport.DoSafeTeleport(geppoTrainerPos)
			task.wait(1.2)
			ReplicatedStorage:WaitForChild("Events"):WaitForChild("learnStyle"):FireServer("skyWalkTrainer")
		end)
	end

	return IslandTeleports
end

defineModule("IslandTeleports", createIslandTeleports)

----------------------------------------------------------------------------
-- Performance: low graphics mode + white screen overlay
----------------------------------------------------------------------------
local function createPerformance()
	local RunService = cloneref(game:GetService("RunService"))
	local CoreGui = cloneref(game:GetService("CoreGui"))
	local Lighting = cloneref(game:GetService("Lighting"))

	local function randomName()
		local name = ""

		for i = 1, 10 do
			local charIndex = math.random(1, 62)
			name ..= (""):sub(charIndex, charIndex)
		end

		return name
	end

	return {
		CreateOverlay = function(title, subtitle, lineProviders)
			local providers = lineProviders or {}
			local overlayGui = Instance.new("ScreenGui")
			overlayGui.Name = randomName()
			overlayGui.IgnoreGuiInset = true
			overlayGui.ResetOnSpawn = false
			overlayGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
			overlayGui.DisplayOrder = 100
			overlayGui.Parent = CoreGui
			local frame = Instance.new("Frame")
			frame.Size = UDim2.fromScale(1, 1)
			frame.BackgroundColor3 = Color3.new(1, 1, 1)
			frame.BorderSizePixel = 0
			frame.ZIndex = 1
			frame.Parent = overlayGui
			local titleLabel = Instance.new("TextLabel")
			titleLabel.Size = UDim2.new(1, 0, 0, 70)
			titleLabel.Position = UDim2.fromScale(0, 0.33)
			titleLabel.AnchorPoint = Vector2.new(0, 0.5)
			titleLabel.BackgroundTransparency = 1
			titleLabel.Text = title
			titleLabel.TextColor3 = Color3.fromRGB(0, 0, 0)
			titleLabel.Font = Enum.Font.GothamBlack
			titleLabel.TextScaled = true
			titleLabel.TextXAlignment = Enum.TextXAlignment.Center
			titleLabel.ZIndex = 2
			titleLabel.Parent = frame
			local subtitleLabel = Instance.new("TextLabel")
			subtitleLabel.Size = UDim2.new(1, 0, 0, 28)
			subtitleLabel.Position = UDim2.fromScale(0, 0.45)
			subtitleLabel.AnchorPoint = Vector2.new(0, 0.5)
			subtitleLabel.BackgroundTransparency = 1
			subtitleLabel.Text = subtitle
			subtitleLabel.TextColor3 = Color3.fromRGB(30, 30, 30)
			subtitleLabel.Font = Enum.Font.GothamBold
			subtitleLabel.TextScaled = true
			subtitleLabel.TextXAlignment = Enum.TextXAlignment.Center
			subtitleLabel.ZIndex = 2
			subtitleLabel.Parent = frame
			local lineLabels = {}
			local nextY = 0.53

			for i in ipairs(providers) do
				local lineLabel = Instance.new("TextLabel")
				lineLabel.Size = UDim2.new(1, 0, 0, 22)
				lineLabel.Position = UDim2.fromScale(0, nextY)
				lineLabel.AnchorPoint = Vector2.new(0, 0.5)
				lineLabel.BackgroundTransparency = 1
				lineLabel.Text = ""
				lineLabel.TextColor3 = Color3.fromRGB(40, 200, 40)
				lineLabel.Font = Enum.Font.GothamBold
				lineLabel.TextScaled = true
				lineLabel.TextXAlignment = Enum.TextXAlignment.Center
				lineLabel.ZIndex = 2
				lineLabel.Parent = frame
				lineLabels[i] = lineLabel
				nextY += 0.08
			end

			local timerLabel = Instance.new("TextLabel")
			timerLabel.Size = UDim2.new(1, 0, 0, 20)
			timerLabel.Position = UDim2.fromScale(0, nextY)
			timerLabel.AnchorPoint = Vector2.new(0, 0.5)
			timerLabel.BackgroundTransparency = 1
			timerLabel.Text = "00:00"
			timerLabel.TextColor3 = Color3.fromRGB(40, 40, 200)
			timerLabel.Font = Enum.Font.GothamBold
			timerLabel.TextScaled = true
			timerLabel.TextXAlignment = Enum.TextXAlignment.Center
			timerLabel.ZIndex = 2
			timerLabel.Parent = frame
			local startTime = tick()

			local connection = RunService.Heartbeat:Connect(function()
				local elapsed = tick() - startTime
				local minutes = math.floor(elapsed / 60)
				local seconds = math.floor(elapsed % 60)
				timerLabel.Text = string.format("%02d:%02d", minutes, seconds)

				for i, provider in ipairs(providers) do
					local ok, text = pcall(provider)

					if ok and lineLabels[i] then lineLabels[i].Text = text end
				end
			end)

			return { Destroy = function()
				connection:Disconnect()
				overlayGui:Destroy()
			end }
		end,
		SetFastMode = function(enabled)
			if enabled ~= true then return end

			pcall(function()
				Lighting.GlobalShadows = false

				for _, child in ipairs(Lighting:GetChildren()) do
					if child:IsA("PostEffect") then child.Enabled = false end
				end

				for _, descendant in ipairs(workspace:GetDescendants()) do
					if descendant:IsA("BasePart") then
						descendant.Material = Enum.Material.SmoothPlastic
						descendant.Reflectance = 0
						descendant.CastShadow = false
					end
				end

				local level01 = Enum.QualityLevel.Level01
				settings().Rendering.QualityLevel = level01
			end)
		end,
	}
end

defineModule("Performance", createPerformance)

----------------------------------------------------------------------------
-- RaceReroll: race reroll
----------------------------------------------------------------------------
local function createRaceReroll()
	local Players = cloneref(game:GetService("Players"))
	local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))

	local function getRaceValue()
		local customization = ReplicatedStorage:FindFirstChild("Stats" .. Players.LocalPlayer.Name)
		customization = customization and customization:FindFirstChild("Customization")
		return customization and customization:FindFirstChild("Race")
	end

	local function getRemainingRerolls()
		local statsFolder = ReplicatedStorage:FindFirstChild("Statsgmnv861")
		statsFolder = statsFolder and statsFolder:FindFirstChild("Stats")
		local raceRerolls = statsFolder and statsFolder:FindFirstChild("RaceRerolls")
		return raceRerolls and raceRerolls.Value
	end

	local function startsWithIgnoreCase(text, prefix)
		if not text or not prefix or prefix == "" then return false end
		local lowerText = string.lower(text)
		local lowerPrefix = string.lower(prefix)
		return string.sub(lowerText, 1, #lowerPrefix) == lowerPrefix
	end

	local running = false

	return {
		RACES = { "Human", "Skypian", "Mink", "Fishman", "Vampire", "Cyborg" },
		GetCurrentRace = function()
			local raceValue = getRaceValue()
			return raceValue and raceValue.Value
		end,
		GetRemainingRerolls = getRemainingRerolls,
		IsRunning = function()
			return running
		end,
		Stop = function()
			running = false
		end,
		Start = function(targetRace, onDone)
			if running then return end
			running = true

			task.spawn(function()
				local raceValue = getRaceValue()
				local reason

				if not raceValue then
					warn("[RaceReroll] Stats folder not found -- are you in the right place?")
					reason = "no stat folder"
				else
					local reroll = ReplicatedStorage:WaitForChild("Events"):WaitForChild("reroll")

					while true do
						reason = "stopped"

						if not running then break end

						if startsWithIgnoreCase(raceValue.Value, targetRace) then
							print("[RaceReroll] Landed on " .. tostring(raceValue.Value) .. " -- stopping.")
							reason = "matched"
							break
						end

						local remaining = getRemainingRerolls()

						if remaining and remaining <= 0 then
							warn("[RaceReroll] Out of race rerolls -- stopping.")
							reason = "out of rerolls"
							break
						end

						pcall(function()
							reroll:InvokeServer()
						end)

						task.wait(0.15)
					end
				end

				running = false

				if type(onDone) == "function" then onDone(reason) end
			end)
		end,
	}
end

defineModule("RaceReroll", createRaceReroll)

----------------------------------------------------------------------------
-- KrakenUi: main settings window and all of its tabs
----------------------------------------------------------------------------
local function createKrakenUi()
	local UiLib = Modules.UiLib()

	return function(options)
		local opts = options or {}
		local compact = opts.Compact == true

		local window = UiLib.new({
			Title = "Wyvern",
			Folder = opts.Folder or "KrakenUI",
			Width = compact and 340 or 600,
			Height = compact and 380 or 470,
			SidebarWidth = compact and 110 or 170,
			ToggleSize = compact and 44 or 60,
			ToggleKeyCode = opts.ToggleKeyCode ~= nil and opts.ToggleKeyCode or Enum.KeyCode.RightShift,
			ToggleIcon = "rbxassetid://126514286406816",
			Target = opts.Config,
		})

		local configTab = window:AddConfigTab()
		configTab:AddSection("Server")
		configTab:AddDropdown({ key = "Sea", label = "Sea", default = "Second Sea", options = { "First Sea", "Second Sea" } })
		configTab:AddInput({ key = "MenuPlaceId", label = "Menu place ID", numeric = true, default = 1730877806 })
		configTab:AddInput({ key = "ReservedServerCode", label = "PS code", default = "", placeholder = "private server code" })
		local refreshers = {}

		local function runRefreshers()
			for _, refresh in ipairs(refreshers) do
				pcall(refresh)
			end
		end

		local Kraken = window:AddTab("Kraken")
		Kraken:AddSection("Roles")
		Kraken:AddLabel("Account names. Leave a field blank to run without it.")
		Kraken:AddColumnHeader({ left = "Role", middle = "Username", right = "Method" })
		local travelMethods = { "Default", "Pika", "Goro" }

		if opts.ShowSkyStringsTravel then travelMethods[#travelMethods + 1] = "Ito" end

		if opts.ShowHieTP then travelMethods[#travelMethods + 1] = "HieTP" end

		local function getLureTravelMethod(index)
			local config = opts.Config
			local lureKey = "Lure" .. index

			if config then
				local lureTravelMethod = config.LureTravelMethod and config.LureTravelMethod[lureKey]
				if type(lureTravelMethod) == "string" and lureTravelMethod ~= "" then
					return lureTravelMethod
				end

				if config.LureHieTP and config.LureHieTP[lureKey] == true then return "HieTP" end

				if config.LurePikaFlight and config.LurePikaFlight[lureKey] == true then return "Pika" end
			end

			return "Default"
		end

		local function getLureCount()
			local lureBoatPositions = opts.Config and opts.Config.Locations and opts.Config.Locations.LureBoatPositions
			if not lureBoatPositions then return 21 end
			local maxIndex = 0

			for k in pairs(lureBoatPositions) do
				local index = tonumber(tostring(k):match("^Lure(%d+)$"))

				if index and index > maxIndex then maxIndex = index end
			end

			return maxIndex > 0 and maxIndex or 21
		end

		local lureRows = {}
		local shownEmptyRow = false

		for i = 1, getLureCount() do
			Kraken:AddInputDropdown({
				key = "Roles.Lure" .. i,
				label = "Lure " .. i,
				default = "",
				placeholder = "account name",
				dropdownKey = "LureTravelMethod.Lure" .. i,
				dropdownOptions = travelMethods,
				dropdownDefault = getLureTravelMethod(i),
				dropdownCallback = function()
					local config = opts.Config
					if not config then return end
					local lureKey = "Lure" .. i

					if type(config.LurePikaFlight) == "table" then
						config.LurePikaFlight[lureKey] = nil
					end

					if type(config.LureHieTP) == "table" then
						config.LureHieTP[lureKey] = nil
					end
				end,
			})

			local row = Kraken.Page:FindFirstChild("InputDropdown_Roles.Lure" .. i)

			if row then
				local assigned = opts.Config and opts.Config.Roles and opts.Config.Roles["Lure" .. i]

				if assigned ~= nil and assigned ~= "" then
					row.Visible = true
				elseif not shownEmptyRow then
					row.Visible = true
					shownEmptyRow = true
				else
					row.Visible = false
				end
			end

			lureRows[i] = row
		end

		refreshers[#refreshers + 1] = function()
			for i, row in ipairs(lureRows) do
				local username = window:Get("Roles.Lure" .. i)

				if row and username ~= nil and username ~= "" then row.Visible = true end
			end
		end

		Kraken:AddButton({
			label = "+ Add Lure",
			callback = function()
				for _, row in ipairs(lureRows) do
					if row and not row.Visible then
						row.Visible = true
						return
					end
				end

				print("[krakenUi] no more lure boat spawns configured -- add one to Locations.LureBoatPositions first")
			end,
		})

		local function getAttackDefault(group, role, key, fallback)
			local config = opts.Config

			if config then
				local groupTable = config[group]
				local roleTable = type(groupTable) == "table" and groupTable[role]
				if type(roleTable) == "table" and roleTable[key] ~= nil then return roleTable[key] == true end

				if config[key] ~= nil then return config[key] == true end
			end

			return fallback
		end

		local function killerAttackOptions(role)
			local function option(key, label, default)
				return {
					key = "KillerAttacks." .. role .. "." .. key,
					label = label,
					default = getAttackDefault("KillerAttacks", role, key, default),
				}
			end

			local options = {
				option("KillerUseRay", "Prominence Ray", true),
				option("KillerUseCakes", "Crumbleshots", true),
				option("KillerUseBonBomb", "Bon-Bon Bomb", true),
				option("KillerUseBonFireball", "Bon-Bon Fireball", true),
				option("KillerUseCyborg", "Missile Shower", false),
				option("KillerUseMegaPow", "Mega Pow", false),
				option("KillerUseMaguRain", "Magma Rain", false),
			}
			return options
		end

		local function anchorAttackOptions(role)
			local function option(key, label, default)
				return {
					key = "AnchorAttacks." .. role .. "." .. key,
					label = label,
					default = getAttackDefault("AnchorAttacks", role, key, default),
				}
			end

			local options = {
				option("AnchorUseMegaPow", "Mega Pow", true),
				option("AnchorUseRay", "Prominence Ray", false),
				option("AnchorUseBonBomb", "Bon-Bon Bomb", false),
				option("AnchorUseBonFireball", "Bon-Bon Fireball", false),
				option("AnchorUseCyborg", "Missile Shower", false),
				option("AnchorUseMaguRain", "Magma Rain", false),
			}

			if opts.ShowBariCage then
				local AnchorUseBariCage = option("AnchorUseBariCage", "Bari Cage (cast + hold)", false)
				table.insert(options, AnchorUseBariCage)
			end

			return options
		end

		Kraken:AddColumnHeader({ left = "Role", middle = "Username", right = "Attacks" })

		Kraken:AddInputMultiDropdown({
			key = "Roles.Anchor",
			label = "Anchor",
			default = "",
			placeholder = "account name",
			dropdownOptions = anchorAttackOptions("Anchor"),
		})

		Kraken:AddInputMultiDropdown({
			key = "Roles.Anchor2",
			label = "Anchor 2",
			default = "",
			placeholder = "unmanned",
			dropdownOptions = anchorAttackOptions("Anchor2"),
		})

		Kraken:AddInputMultiDropdown({
			key = "Roles.Killer",
			label = "Killer",
			default = "",
			placeholder = "account name",
			dropdownOptions = killerAttackOptions("Killer"),
		})

		Kraken:AddInputMultiDropdown({
			key = "Roles.Killer2",
			label = "Killer 2",
			default = "",
			placeholder = "unmanned",
			dropdownOptions = killerAttackOptions("Killer2"),
		})

		Kraken:AddInputMultiDropdown({
			key = "Roles.Killer3",
			label = "Killer 3",
			default = "",
			placeholder = "unmanned",
			dropdownOptions = killerAttackOptions("Killer3"),
		})

		Kraken:AddSection("Killer")
		Kraken:AddLabel("Mega Pow has to be EQUIPPED to fire.")
		Kraken:AddToggle({ key = "PauseAttacksDuringCliffRun", label = "Stop attacking during cliff runs", default = true })
		Kraken:AddSection("Anchor-only mode")
		Kraken:AddLabel("Lures bring Krakens/Megalodons to rough waters. Recommended for 1-2 lure sessions.")
		Kraken:AddToggle({ key = "AnchorOnlyMode", label = "Anchor-only mode", default = false })
		Kraken:AddToggle({ key = "LureAnchorOnlyInstant", label = "Instant lure (no delivery)", default = false })
		Kraken:AddLabel("Lures spawn right under anchor, needs stronger boat like caravel or hoverboard.")

		Kraken:AddSlider({
			key = "LureBoatSpawnAhead",
			label = "Instant lure boat-spawn distance",
			min = 100,
			max = 300,
			step = 5,
			default = 185,
			suffix = " studs",
		})

		if opts.ShowBariCage then
			Kraken:AddToggle({ key = "AnchorBariMode", label = "Bari Cage cover", default = false })

			Kraken:AddSlider({
				key = "AnchorBariCageDepth",
				label = "Cage depth below post",
				min = 20,
				max = 150,
				step = 5,
				default = 50,
				suffix = " studs",
			})

			Kraken:AddLabel("One Anchor slot needs Bari-Bari and its own \"Bari Cage (cast + hold)\" attack ticked (next to its name above) to plant and hold the cage; every Anchor stands on it, and fruit that can't be stored will be dropped on it instead of the water. Lures check it too after their delivery hold.")
		end

		Kraken:AddSection("Regroup")
		Kraken:AddToggle({ key = "KillerRegroupEnemies", label = "Killer regroups", default = false })
		Kraken:AddToggle({ key = "AnchorRegroupEnemies", label = "Anchor regroups", default = false })

		Kraken:AddSlider({
			key = "RegroupDelay",
			label = "Delay between",
			min = 30,
			max = 600,
			step = 10,
			default = 120,
			suffix = "s",
		})

		Kraken:AddToggle({ key = "PauseAttacksDuringRegroup", label = "Hold fire on regroups", default = true })
		Kraken:AddSection("Lure -- run")
		Kraken:AddToggle({ key = "LureSkipLoadingWait", label = "Skip loading screen wait", default = false })

		Kraken:AddSlider({
			key = "LureDeliveryHold",
			label = "Delivery hold",
			min = 0,
			max = 60,
			step = 1,
			default = 20,
			suffix = "s",
		})

		Kraken:AddSlider({
			key = "LureRejoinSeconds",
			label = "Rejoin after",
			min = 60,
			max = 600,
			step = 10,
			default = 180,
			suffix = "s",
		})

		Kraken:AddLabel("Will rejoin game even if you get kicked.")
		Kraken:AddToggle({ key = "LurePickUpFruit", label = "Pick up cliff fruit", default = true })
		Kraken:AddToggle({ key = "LureSkipDuplicateFruit", label = "Skip duplicates", default = true })
		Kraken:AddSection("Error Slowdown")
		Kraken:AddLabel("Will slow current movement until error is gone.")
		Kraken:AddToggle({ key = "ErrorHoldEnabled", label = "Hold on errors", default = true })

		Kraken:AddSlider({
			key = "ErrorHoldMaxSeconds",
			label = "Max hold",
			min = 10,
			max = 600,
			step = 10,
			default = 120,
			suffix = "s",
		})

		Kraken:AddSection("Movement")

		Kraken:AddSlider({
			key = "Movement.DefaultSpeed",
			label = "Default speed",
			min = 20,
			max = 400,
			step = 10,
			default = 100,
		})

		Kraken:AddSection("Storage")

		Kraken:AddSlider({
			key = "Storage.StoreAttempts",
			label = "Store attempts",
			min = 1,
			max = 6,
			step = 1,
			default = 1,
		})

		Kraken:AddLabel("Bump this up to 2 if fruits aren't being stored reliably.")
		Kraken:AddSection("Cliff fruits")
		Kraken:AddLabel("Which fruits will be dropped at the cliff to be salvaged, the rest will be dropped into water.")
		local rarity = opts.Config and opts.Config.Fruits and opts.Config.Fruits.Rarity or {}
		local mythicals = {}
		local legendaries = {}

		for k, rarityName in pairs(rarity) do
			if rarityName == "Mythical" then
				mythicals[#mythicals + 1] = k
			elseif rarityName == "Legendary" and k ~= "Pika" then
				legendaries[#legendaries + 1] = k
			end
		end

		table.sort(mythicals)
		table.sort(legendaries)

		if rarity.Pika == "Legendary" then table.insert(legendaries, 1, "Pika") end

		local cliffOptions = {}

		for _, fruit in ipairs(mythicals) do
			cliffOptions[#cliffOptions + 1] = { key = "Fruits.CliffFruits." .. fruit, label = fruit, default = true }
		end

		for _, fruit in ipairs(legendaries) do
			cliffOptions[#cliffOptions + 1] = { key = "Fruits.CliffFruits." .. fruit, label = fruit, default = true }
		end

		Kraken:AddMultiDropdown({ label = "Cliff fruits", options = cliffOptions })
		Kraken:AddSection("Fruit webhooks")
		Kraken:AddLabel("Which fruits are allowed to send a webhook (stored, dropped, cliff, picked up) at all.")
		local allRarities = opts.Config and opts.Config.Fruits and opts.Config.Fruits.Rarity or {}
		local fruitNames = {}

		for k in pairs(allRarities) do
			fruitNames[#fruitNames + 1] = k
		end

		table.sort(fruitNames)
		local webhookOptions = {}

		for _, fruit in ipairs(fruitNames) do
			webhookOptions[#webhookOptions + 1] = { key = "Fruits.WebhookFruits." .. fruit, label = fruit, default = true }
		end

		Kraken:AddMultiDropdown({ label = "Fruit webhooks", options = webhookOptions })
		Kraken:AddSection("Security")
		Kraken:AddToggle({ key = "ShutdownOnOutsider", label = "Shut down on outsider", default = true })
		Kraken:AddLabel("Anyone whose name isn't in Roles will make all your accounts leave the game.")
		Kraken:AddSection("Stats Panel")
		Kraken:AddToggle({ key = "StatsGuiEnabled", label = "On-screen stats panel", default = true })
		Kraken:AddLabel("Anchor/Killer only, makes a ui with info like fruit counts.")
		Kraken:AddSection("Webhook")

		Kraken:AddInput({
			key = "WebhookUrl",
			label = "URL",
			default = "",
			placeholder = "https://discord.com/api/webhooks/...",
		})

		Kraken:AddInput({ key = "PingID", label = "Ping", default = "<@>", placeholder = "<@userid>" })
		Kraken:AddInput({ key = "WebhookFooterText", label = "Footer", default = "ball's GKK" })
		Kraken:AddToggle({ key = "StatsWebhookEnabled", label = "Hourly stats report", default = true })

		Kraken:AddSlider({
			key = "StatsWebhookIntervalSeconds",
			label = "Report every",
			min = 300,
			max = 14400,
			step = 300,
			default = 3600,
			suffix = "s",
		})

		local bossTab = window:AddTab("Boss Rotation")
		bossTab:AddSection("Run")
		bossTab:AddToggle({ key = "BossRotation.Enabled", label = "Run the rotation", default = false })
		bossTab:AddToggle({ key = "BossRotation.AutoGrabPosters", label = "Pick up Bounty posters", default = true })
		bossTab:AddToggle({ key = "BossRotation.CounterBlocking", label = "Laser Pulsar on Block", default = true })
		bossTab:AddLabel("Goes down to the boss's height and fires Laser Pulsar to break it.")
		local bossTravelMethods = { "Goro" }

		if opts.ShowSkyStringsTravel then
			bossTravelMethods[#bossTravelMethods + 1] = "Ito"
		end

		if opts.ShowHieTP then bossTravelMethods[#bossTravelMethods + 1] = "HieTP" end

		if opts.ShowLeopardMode then
			bossTravelMethods[#bossTravelMethods + 1] = "Primal"
		end

		local function getBossTravelMethod()
			local bossRotation = opts.Config and opts.Config.BossRotation

			if type(bossRotation) == "table" then
				local travelMethod = bossRotation.TravelMethod
				if type(travelMethod) == "string" and travelMethod ~= "" then return travelMethod end

				if bossRotation.HieTP == true then return "HieTP" end

				if bossRotation.SkyStringsTravel == true then return "Ito" end
			end

			return "Goro"
		end

		if #bossTravelMethods > 1 then
			bossTab:AddDropdown({
				key = "BossRotation.TravelMethod",
				label = "Travel method",
				options = bossTravelMethods,
				default = getBossTravelMethod(),
				callback = function()
					local bossRotation = opts.Config and opts.Config.BossRotation
					if type(bossRotation) ~= "table" then return end
					bossRotation.HieTP = nil
					bossRotation.SkyStringsTravel = nil
				end,
			})
		end

		bossTab:AddLabel("Goro Goro is required: every movement between bosses flies on Lightning Form. ")

		bossTab:AddSlider({
			key = "BossRotation.GoroGoroSpeed",
			label = "Flight speed",
			min = 100,
			max = 500,
			step = 10,
			default = 350,
			suffix = " studs/s",
		})

		if opts.ShowHieTP then
			bossTab:AddLabel("HieTP teleports each leg instead of flying it, needs Hie-Hie.")
		end

		if opts.ShowLeopardMode then
			bossTab:AddDropdown({
				key = "BossRotation.AttackMode",
				label = "Attack mode",
				options = { "Cyborg", "Leopard" },
				default = "Cyborg",
			})

			bossTab:AddLabel("Cyborg rains Missile Shower from above and counters Blocking with Laser Pulsar. Leopard charges instinct to MAXED, enters hybrid form and M1s the boss in melee -- it hovers low for the reach and runs no block counter.")

			bossTab:AddSlider({
				key = "BossRotation.PrimalPursuitSpeed",
				label = "Primal Pursuit speed",
				min = 100,
				max = 300,
				step = 10,
				default = 150,
				suffix = " studs/s",
			})

			bossTab:AddLabel("Primal Pursuit travel rides Geppo rather than replacing it, so it flies much slower than Lightning Form -- but it drains no stamina and still lets posters be picked up.")
		end

		if opts.ShowSkyStringsTravel then
			bossTab:AddSlider({
				key = "BossRotation.SkyStringsSpeed",
				label = "Sky Strings speed",
				min = 40,
				max = 2000,
				step = 20,
				default = 140,
				suffix = " studs/s",
			})

			bossTab:AddSlider({
				key = "BossRotation.SkyStringsWarmup",
				label = "Sky Strings warm-up",
				min = 0,
				max = 10,
				step = 0.5,
				default = 2,
				suffix = "s",
			})

			bossTab:AddSlider({
				key = "BossRotation.SkyStringsRecastInterval",
				label = "Sky Strings re-cast interval",
				min = 0.1,
				max = 2,
				step = 0.25,
				default = 0.4,
				suffix = "s",
			})
		end

		bossTab:AddSection("Bosses")

		bossTab:AddMultiDropdown({
			label = "Bosses to farm",
			options = {
				{
					key = "BossRotation.SelectedBosses.Ghost Princess",
					label = "Ghost Princess",
					default = true,
				},
				{ key = "BossRotation.SelectedBosses.Borj", label = "Borj", default = true },
				{ key = "BossRotation.SelectedBosses.Ryuma", label = "Ryuma", default = true },
				{
					key = "BossRotation.SelectedBosses.Juzo the Diamondback",
					label = "Juzo the Diamondback",
					default = true,
				},
				{ key = "BossRotation.SelectedBosses.Soul King", label = "Soul King", default = true },
				{
					key = "BossRotation.SelectedBosses.Soul King (Rockstar)",
					label = "Soul King (Rockstar)",
					default = false,
				},
				{ key = "BossRotation.SelectedBosses.Hawk Eye", label = "Hawk Eye", default = false },
				{ key = "BossRotation.SelectedBosses.Roger", label = "Roger", default = false },
			},
		})

		bossTab:AddSection("Webhook")

		bossTab:AddInput({
			key = "BossRotation.WebhookUrl",
			label = "Webhook URL",
			default = "",
			placeholder = "https://discord.com/api/webhooks/...",
		})

		bossTab:AddToggle({ key = "BossRotation.KillWebhook", label = "Kill webhook", default = true })
		bossTab:AddToggle({ key = "BossRotation.ItemWebhook", label = "Item webhook", default = true })

		if opts.ShowMerchantChecker then
			bossTab:AddSection("Merchant")

			bossTab:AddToggle({
				key = "BossRotation.MerchantCheckEnabled",
				label = "Auto-buy from Traveling Merchant",
				default = false,
			})

			bossTab:AddLabel("Once Peli is at 1,000,000, checks between boss fights for the Traveling Merchant and buys every item selected below if he's up. Sends messages to the webhook above.")
			local merchantItemOptions = {}

			for _, knownItem in ipairs(Modules.AutoMerchant().KNOWN_ITEMS) do
				merchantItemOptions[#merchantItemOptions + 1] = { key = "BossRotation.MerchantCheckItems." .. knownItem, label = knownItem, default = false }
			end

			bossTab:AddMultiDropdown({ label = "Items to buy", options = merchantItemOptions })
		end

		local Factory = window:AddTab("Factory")
		Factory:AddSection("Run")
		Factory:AddToggle({ key = "Factory.Enabled", label = "Auto Farm Gears", default = false })
		Factory:AddLabel("Waits at the Factory entrance for alert 1/2, clears both floors with the katana, then fights the Factory Pool for gear. Needs a Katana already in the Backpack.")
		Factory:AddSection("Webhook")

		Factory:AddInput({
			key = "Factory.WebhookUrl",
			label = "Webhook URL",
			default = "",
			placeholder = "https://discord.com/api/webhooks/...",
		})

		local Fishing = window:AddTab("Fishing")
		Fishing:AddSection("Roles")
		Fishing:AddColumnHeader({ left = "Role", middle = "Username" })
		local fisherRows = {}
		local shownEmptyFisher = false

		for i = 1, 12 do
			Fishing:AddInput({
				key = "Fishing.Roles.Fisher" .. i,
				label = "Fisher " .. i,
				default = "",
				placeholder = "account name",
			})

			local row = Fishing.Page:FindFirstChild("Input_Fishing.Roles.Fisher" .. i)

			if row then
				local roles = opts.Config and opts.Config.Fishing and opts.Config.Fishing.Roles
				roles = roles and roles["Fisher" .. i]

				if roles ~= nil and roles ~= "" then
					row.Visible = true
				elseif not shownEmptyFisher then
					row.Visible = true
					shownEmptyFisher = true
				else
					row.Visible = false
				end
			end

			fisherRows[i] = row
		end

		refreshers[#refreshers + 1] = function()
			for i, row in ipairs(fisherRows) do
				local username = window:Get("Fishing.Roles.Fisher" .. i)

				if row and username ~= nil and username ~= "" then row.Visible = true end
			end
		end

		Fishing:AddButton({
			label = "+ Add Fisher",
			callback = function()
				for _, row in ipairs(fisherRows) do
					if row and not row.Visible then
						row.Visible = true
						return
					end
				end

				print("[krakenUi] every Fisher slot is already shown -- raise FISHING_FISHER_SLOTS here and in fishing/fishingFarm.lua together to add more")
			end,
		})

		Fishing:AddSection("Run")
		Fishing:AddToggle({ key = "Fishing.Enabled", label = "Auto Fish", default = false })
		Fishing:AddLabel("Need shell's town spawn, geppo and fishing rod.")

		Fishing:AddSlider({
			key = "Fishing.SpotRadius",
			label = "Spread around the spot",
			min = 0,
			max = 60,
			step = 1,
			default = 0,
			suffix = " studs",
		})

		Fishing:AddLabel("Leave at 0 to stack every account on the same spot.")

		Fishing:AddSlider({
			key = "Fishing.SpotTurn",
			label = "Turn the spot",
			min = -180,
			max = 180,
			step = 1,
			default = 0,
			suffix = " deg",
		})

		Fishing:AddLabel("I didn't hardcode this yet so you gotta turn until it works ok.")
		Fishing:AddToggle({ key = "Fishing.ShiftLock", label = "Shiftlock + face the water", default = true })
		Fishing:AddLabel("Keep this on pleas")
		Fishing:AddSection("Bait")
		Fishing:AddToggle({ key = "Fishing.BuyBait", label = "Auto Buy Bait", default = true })

		Fishing:AddSlider({
			key = "Fishing.BaitBuyAmount",
			label = "Buy per trip",
			min = 50,
			max = 900,
			step = 50,
			default = 300,
			suffix = " bait",
		})

		Fishing:AddSlider({
			key = "Fishing.BaitBuyPeli",
			label = "Peli needed to go",
			min = 5000,
			max = 60000,
			step = 1000,
			default = 15000,
			suffix = " Peli",
		})

		Fishing:AddSection("Selling")
		Fishing:AddToggle({ key = "Fishing.SellFish", label = "Auto Sell Fish", default = true })

		Fishing:AddSlider({
			key = "Fishing.SellFishCount",
			label = "Sell after",
			min = 1,
			max = 60,
			step = 1,
			default = 10,
			suffix = " fish",
		})

		Fishing:AddToggle({ key = "Fishing.SellRarities.Common", label = "Sell Common", default = true })
		Fishing:AddToggle({ key = "Fishing.SellRarities.Rare", label = "Sell Rare", default = true })
		Fishing:AddToggle({ key = "Fishing.SellRarities.Legendary", label = "Sell Legendary", default = false })
		Fishing:AddSection("Devil fruit")
		Fishing:AddToggle({ key = "Fishing.StoreFruit", label = "Auto Store Fruit", default = true })
		Fishing:AddSection("Rod")
		Fishing:AddToggle({ key = "Fishing.BuyRod", label = "Auto Buy Rod", default = false })
		Fishing:AddLabel("One-off: an account starting with no rod buys one from the Loguetown stall before it travels, then turns this off for itself.")
		Fishing:AddSection("Merchant")

		Fishing:AddToggle({
			key = "Fishing.MerchantCheckEnabled",
			label = "Auto-buy from Traveling Merchant",
			default = false,
		})

		Fishing:AddLabel("Checks between casts for the Traveling Merchant and buys every item selected below if he's up, then comes back to the spot. Reports to the webhook below.")
		local merchantItemOptions = {}

		for _, knownItem in ipairs(Modules.AutoMerchant().KNOWN_ITEMS) do
			merchantItemOptions[#merchantItemOptions + 1] = { key = "Fishing.MerchantCheckItems." .. knownItem, label = knownItem, default = false }
		end

		Fishing:AddMultiDropdown({ label = "Items to buy", options = merchantItemOptions })
		Fishing:AddSection("Webhook")

		Fishing:AddInput({
			key = "Fishing.WebhookUrl",
			label = "Webhook URL",
			default = "",
			placeholder = "https://discord.com/api/webhooks/...",
		})

		local Esp
		local CombatTweaks
		local MovementMods
		local FieldOfView
		local AutoRejoin
		local DisplayNameSpoof
		local IslandTeleports

		if opts.EspAllowed then Esp = Modules.Esp() end

		if opts.PlaceIndependentModsAllowed then
			CombatTweaks = Modules.CombatTweaks()
			FieldOfView = Modules.FieldOfView()
			AutoRejoin = Modules.AutoRejoin()
			DisplayNameSpoof = Modules.DisplayNameSpoof()
		end

		if opts.RealFarmSession then
			CombatTweaks = CombatTweaks or Modules.CombatTweaks()
			MovementMods = Modules.MovementMods()
			IslandTeleports = Modules.IslandTeleports()
		end

		local Performance = Modules.Performance()
		local RaceReroll = Modules.RaceReroll()
		local esp = window:AddTab("ESP")
		esp:AddSection("Player ESP")

		esp:AddToggle({
			key = "EspPlayerEnabled",
			label = "Enable ESP",
			default = false,
			callback = function(enabled)
				if Esp then Esp.SetPlayerEspEnabled(enabled) end
			end,
		})

		esp:AddToggle({
			key = "EspBoxesEnabled",
			label = "Boxes",
			default = true,
			callback = function(enabled)
				if Esp then Esp.PlayerSettings.boxes.enabled = enabled end
			end,
		})

		esp:AddColorPicker({
			key = "EspBoxColor",
			label = "Box Color",
			default = Color3.fromRGB(255, 255, 255),
			callback = function(color)
				if Esp then Esp.PlayerSettings.boxes.color = color end
			end,
		})

		esp:AddSection("Overlays")

		esp:AddToggle({
			key = "EspNamesEnabled",
			label = "Names",
			default = true,
			callback = function(enabled)
				if Esp then Esp.PlayerSettings.names.enabled = enabled end
			end,
		})

		esp:AddToggle({
			key = "EspDistanceEnabled",
			label = "Range / Distance ESP",
			default = true,
			callback = function(enabled)
				if Esp then Esp.PlayerSettings.flags.distance[1] = enabled end
			end,
		})

		esp:AddToggle({
			key = "EspHealthBarEnabled",
			label = "Health Bar",
			default = true,
			callback = function(enabled)
				if Esp then Esp.PlayerSettings.health_bars.enabled = enabled end
			end,
		})

		esp:AddSlider({
			key = "EspHealthBarThickness",
			label = "Bar Thickness",
			min = 1,
			max = 10,
			step = 1,
			default = 1,
			callback = function(thickness)
				if Esp then Esp.PlayerSettings.health_bars.thickness = thickness end
			end,
		})

		esp:AddSection("World ESP")

		esp:AddToggle({
			key = "EspChestEnabled",
			label = "Chest ESP",
			default = false,
			callback = function(enabled)
				if Esp then Esp.SetChestEspEnabled(enabled) end
			end,
		})

		esp:AddToggle({
			key = "EspMachineEnabled",
			label = "Machine ESP",
			default = false,
			callback = function(enabled)
				if Esp then Esp.SetMachineEspEnabled(enabled) end
			end,
		})

		esp:AddSection("Island ESP")

		esp:AddToggle({
			key = "EspIslandSea1Enabled",
			label = "Island ESP (Sea 1)",
			default = false,
			callback = function(enabled)
				if Esp then Esp.SetIslandEspEnabled(1, enabled) end
			end,
		})

		esp:AddToggle({
			key = "EspIslandSea2Enabled",
			label = "Island ESP (Sea 2)",
			default = false,
			callback = function(enabled)
				if Esp then Esp.SetIslandEspEnabled(2, enabled) end
			end,
		})

		local Combat = window:AddTab("Combat")
		Combat:AddSection("Combat Mods")

		Combat:AddToggle({
			key = "CombatNoStaminaCost",
			label = "No Stamina Cost",
			default = false,
			callback = function(enabled)
				if CombatTweaks then CombatTweaks.SetNoStaminaCostEnabled(enabled) end
			end,
		})

		Combat:AddToggle({
			key = "CombatNoStun",
			label = "No Stun / No Knockback",
			default = false,
			callback = function(enabled)
				if CombatTweaks then CombatTweaks.SetNoStunEnabled(enabled) end
			end,
		})

		local qol = window:AddTab("QOL")
		qol:AddSection("Performance")

		qol:AddSlider({
			key = "QolFpsCap",
			label = "FPS cap",
			min = 0,
			max = 240,
			step = 5,
			default = 60,
			suffix = " (0 = off)",
			callback = function(value)
				if value > 0 and setfpscap then
					pcall(function()
						setfpscap(value)
					end)
				end
			end,
		})

		qol:AddToggle({
			key = "QolLowDetail",
			label = "Fast Mode",
			default = false,
			callback = function(enabled)
				Performance.SetFastMode(enabled)
			end,
		})

		qol:AddToggle({
			key = "DisableOtherPlayerAnimations",
			label = "Disable other players' animations",
			default = true,
		})

		qol:AddSection("Identity")

		qol:AddInput({
			key = "QolDisplayName",
			label = "Display Name",
			default = "",
			placeholder = "fake name shown in UI text",
		})

		qol:AddButton({
			label = "Apply Name",
			callback = function()
				if DisplayNameSpoof then
					DisplayNameSpoof.Apply((opts.Config or {}).QolDisplayName or "")
				end
			end,
		})

		qol:AddSection("Movement")

		qol:AddToggle({
			key = "QolWalkSpeedEnabled",
			label = "WalkSpeed",
			default = false,
			callback = function(enabled)
				if MovementMods then MovementMods.SetWalkSpeedEnabled(enabled) end
			end,
		})

		qol:AddSlider({
			key = "QolWalkSpeedValue",
			label = "Speed",
			min = 4,
			max = 300,
			step = 1,
			default = 45,
			callback = function(value)
				if MovementMods then MovementMods.SetWalkSpeedValue(value) end
			end,
		})

		qol:AddButton({
			label = "Reset Speed",
			callback = function()
				window:Set("QolWalkSpeedValue", 16)
			end,
		})

		qol:AddToggle({
			key = "QolNoclipEnabled",
			label = "Noclip",
			default = false,
			callback = function(enabled)
				if MovementMods then MovementMods.SetNoclipEnabled(enabled) end
			end,
		})

		qol:AddSection("Jump & Camera")

		qol:AddToggle({
			key = "QolInfiniteJumpEnabled",
			label = "Infinite Jump",
			default = false,
			callback = function(enabled)
				if MovementMods then MovementMods.SetInfiniteJumpEnabled(enabled) end
			end,
		})

		qol:AddSlider({
			key = "QolFieldOfView",
			label = "Field of View",
			min = 0,
			max = 120,
			step = 1,
			default = 70,
			callback = function(value)
				if FieldOfView then FieldOfView.SetFieldOfView(value) end
			end,
		})

		qol:AddSection("Auto Rejoin")

		qol:AddToggle({
			key = "QolAutoRejoinEnabled",
			label = "Auto Rejoin",
			default = false,
			callback = function(enabled)
				if AutoRejoin then AutoRejoin.SetEnabled(enabled) end
			end,
		})

		qol:AddSection("Island Movement")
		local islandTravelMethods = { "Default" }

		if opts.ShowSkyStringsTravel then
			islandTravelMethods[#islandTravelMethods + 1] = "Ito"
		end

		if #islandTravelMethods > 1 then
			qol:AddDropdown({
				key = "QolIslandTravelMethod",
				label = "Travel method",
				options = islandTravelMethods,
				default = "Default",
				callback = function(value)
					if IslandTeleports then IslandTeleports.SetTravelMethod(value) end
				end,
			})

			qol:AddLabel("Ito flies a straight line at the island's own height, through terrain -- needs Sky Strings. Geppo below only applies to Default.")
		end

		qol:AddToggle({
			key = "QolIslandGeppoEnabled",
			label = "Geppo",
			default = true,
			callback = function(enabled)
				if IslandTeleports then IslandTeleports.SetUseGeppo(enabled) end
			end,
		})

		qol:AddSlider({
			key = "QolTeleportSpeed",
			label = "Teleport Speed",
			min = 20,
			max = 400,
			step = 10,
			default = 89,
			suffix = " studs/s",
			callback = function(value)
				if IslandTeleports then IslandTeleports.SetSpeed(value) end
			end,
		})

		qol:AddSection("Island Teleports (Sea 1)")
		local sea1IslandNames = {}

		local sea1Islands = IslandTeleports and IslandTeleports.SEA1_ISLANDS or {}

		for k in pairs(sea1Islands) do
			sea1IslandNames[#sea1IslandNames + 1] = k
		end

		table.sort(sea1IslandNames)

		qol:AddDropdown({
			key = "QolIslandSea1Select",
			label = "Select Island",
			default = sea1IslandNames[1],
			options = sea1IslandNames,
			save = false,
		})

		qol:AddButton({
			label = "Teleport",
			callback = function()
				if IslandTeleports then
					IslandTeleports.TeleportToIsland(1, window:Get("QolIslandSea1Select"))
				end
			end,
		})

		qol:AddSection("Island Teleports (Sea 2)")
		local sea2IslandNames = {}

		local sea2Islands = IslandTeleports and IslandTeleports.SEA2_ISLANDS or {}

		for k in pairs(sea2Islands) do
			sea2IslandNames[#sea2IslandNames + 1] = k
		end

		table.sort(sea2IslandNames)

		qol:AddDropdown({
			key = "QolIslandSea2Select",
			label = "Select Island",
			default = sea2IslandNames[1],
			options = sea2IslandNames,
			save = false,
		})

		qol:AddButton({
			label = "Teleport",
			callback = function()
				if IslandTeleports then
					IslandTeleports.TeleportToIsland(2, window:Get("QolIslandSea2Select"))
				end
			end,
		})

		qol:AddButton({
			label = "Cancel Teleport",
			callback = function()
				if IslandTeleports then IslandTeleports.CancelTeleport() end
			end,
		})

		qol:AddButton({
			label = "Grab World Scroll",
			callback = function()
				if IslandTeleports then IslandTeleports.GrabWorldScroll() end
			end,
		})

		qol:AddButton({
			label = "Buy Geppo",
			callback = function()
				if IslandTeleports then IslandTeleports.BuyGeppo() end
			end,
		})

		qol:AddSection("Race Reroll")
		qol:AddLabel("Rerolls until you land on the race below, then stops on its own. Also stops early if you run out of rerolls.")
		qol:AddDropdown({ key = "QolRaceRerollTarget", label = "Target race", default = RaceReroll.RACES[1], options = RaceReroll.RACES })

		qol:AddToggle({
			key = "QolRaceRerollEnabled",
			label = "Auto reroll",
			default = false,
			callback = function(enabled)
				if enabled then
					RaceReroll.Start(window:Get("QolRaceRerollTarget"), function()
						window:Set("QolRaceRerollEnabled", false)
					end)
				else
					RaceReroll.Stop()
				end
			end,
		})

		local config = opts.Config or window:ApplyTo({})

		local function syncStandaloneConfig()
			if opts.Config then return end
			window:ApplyTo(config)
		end

		window:OnChange(function(key, newValue, oldValue)
			syncStandaloneConfig()

			print(string.format("[krakenUi] %s: %s -> %s", key, tostring(oldValue), tostring(newValue)))
		end)

		if opts.TestTab then
			local Test = window:AddTab("Test")
			Test:AddLabel("Sanity checks for the panel itself. The console is the output.")
			Test:AddSection("Read back")

			Test:AddButton({
				label = "Print nesting",
				callback = function()
					print("Roles.Killer      =", tostring(config.Roles and config.Roles.Killer))
					print("Roles.Lure1       =", tostring(config.Roles and config.Roles.Lure1))
					print("Movement.DefaultSpeed  =", tostring(config.Movement and config.Movement.DefaultSpeed))
					print("Storage.StoreAttempts  =", tostring(config.Storage and config.Storage.StoreAttempts))
					print("LureTravelMethod.Lure1 =", tostring(config.LureTravelMethod and config.LureTravelMethod.Lure1))
				end,
			})

			Test:AddButton({
				label = "Count controls",
				colour = UiLib.Theme.Neutral,
				callback = function()
					local count = 0

					for k in pairs(window:Values()) do
						count += 1
					end

					print("[krakenUi] " .. count .. " controls")
				end,
			})

			Test:AddButton({
				label = "Confirm live wiring",
				colour = UiLib.Theme.Neutral,
				callback = function()
					if not opts.Config then
						print("[krakenUi] standalone -- the panel owns its own config table")
						return
					end
					local lureRejoinSeconds = config.LureRejoinSeconds
					window:Set("LureRejoinSeconds", lureRejoinSeconds == 200 and 300 or 200)
					print("[krakenUi] live config: " .. tostring(lureRejoinSeconds) .. " -> " .. tostring(opts.Config.LureRejoinSeconds) .. "  (same table: " .. tostring(config == opts.Config) .. ")")
					window:Set("LureRejoinSeconds", lureRejoinSeconds)
				end,
			})

			Test:AddSection("Live edits")

			Test:AddButton({
				label = "Set from script",
				colour = Color3.fromRGB(58, 122, 96),
				callback = function()
					window:Set("LureRejoinSeconds", 300)
					window:Set("Roles.Killer", "TestKiller")
					window:Set("Movement.DefaultSpeed", 120)
					print("[krakenUi] pushed three values; the controls above should have moved")
				end,
			})

			Test:AddButton({
				label = "Clamp check",
				colour = UiLib.Theme.Neutral,
				callback = function()
					window:Set("LureRejoinSeconds", 999999)
					print("clamped to max:", window:Get("LureRejoinSeconds"))
					window:Set("Movement.DefaultSpeed", 137)
					print("snapped to the 10 step:", window:Get("Movement.DefaultSpeed"))
				end,
			})
		end

		window:Preload()
		runRefreshers()
		syncStandaloneConfig()

		return {
			Config = config,
			Window = window,
			Open = function()
				window:Open()
			end,
		}
	end
end

defineModule("KrakenUi", createKrakenUi)

----------------------------------------------------------------------------
-- Abilities: fruit / weapon skills used in fights
----------------------------------------------------------------------------
local function createAbilities()
	local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
	local localPlayer = cloneref(game:GetService("Players")).LocalPlayer
	local huge = math.huge
	local skills
	local npCfolder
	local locations
	local getRootCFrame
	local faceTarget
	local setItemEquipped
	local getBackpack

	local Abilities = { Init = function(options)
		local opts = options or {}
		skills = opts.Skills
		npCfolder = opts.NPCfolder
		locations = opts.Locations
		getRootCFrame = opts.getRootCFrame
		faceTarget = opts.faceTarget
		setItemEquipped = opts.setItemEquipped
		getBackpack = opts.getBackpack
	end }

	-- finding targets
	local lowerNameCache = setmetatable({}, { __mode = "k" })

	local function getLoweredName(instance)
		local lowered = lowerNameCache[instance]

		if not lowered then
			lowered = string.lower(instance.Name)
			lowerNameCache[instance] = lowered
		end

		return lowered
	end

	local function findTargetModel(names, nearPos, maxRadius)
		if not npCfolder then return nil end
		local children = npCfolder:GetChildren()
		local nearZ
		local nearX

		if nearPos then
			nearX = nearPos.X
			nearZ = nearPos.Z
		end

		maxRadius = maxRadius and maxRadius * maxRadius or nil

		for _, namePart in ipairs(names) do
			local bestDistSq = huge
			local best

			for _, child in ipairs(children) do
				local primaryPart = child:IsA("Model") and child.PrimaryPart

				if primaryPart and string.find(getLoweredName(child), namePart, 1, true) then
					local distSq = 0

					if nearX then
						local position = primaryPart.Position
						local dx = position.X - nearX
						local dz = position.Z - nearZ
						distSq = dx * dx + dz * dz
					end

					if (not maxRadius or distSq <= maxRadius) and distSq < bestDistSq then
						bestDistSq = distSq
						best = child
					end
				end
			end

			if best then return best end
		end

		return nil
	end

	local function countNearbySpecies(namePart, center, radius)
		if not npCfolder then return 0 end
		local centerX = center.X
		local centerZ = center.Z
		local radiusSq = radius * radius
		local count = 0

		for _, child in ipairs(npCfolder:GetChildren()) do
			local primaryPart = child:IsA("Model") and child.PrimaryPart
			local matches = primaryPart and string.find(getLoweredName(child), namePart, 1, true)

			if matches then
				local position = primaryPart.Position
				local dx = position.X - centerX
				local dz = position.Z - centerZ

				if dx * dx + dz * dz <= radiusSq then count += 1 end
			end
		end

		return count
	end

	local function getAimCFrame(model)
		if not model or not model.Parent then return nil end

		if model.PrimaryPart then return model.PrimaryPart.CFrame end
		local basePart = model:FindFirstChildWhichIsA("BasePart")
		return basePart and basePart.CFrame or nil
	end

	local function isTargetAlive(model)
		if not model or model.Parent ~= workspace:FindFirstChild("NPCs") then return false end
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then return humanoid.Health > 0 end
		return true
	end

	local function targetSelector()
		return nil
	end

	local function setTargetSelector(selector)
		targetSelector = selector
	end

	local function getTargetModel()
		return targetSelector()
	end

	local function getTargetPosition()
		return getAimCFrame(targetSelector())
	end

	-- skill remote call with a timeout
	local function invokeWithTimeout(remote, timeout, ...)
		local args = { ... }
		local finished = false
		local success = false
		local response

		task.spawn(function()
			local ok, result = pcall(function()
				return remote:InvokeServer(table.unpack(args))
			end)

			success = ok
			response = result
			finished = true
		end)

		local waited = 0

		while not finished and waited < timeout do
			task.wait(0.1)
			waited += 0.1
		end

		if not finished then return false, "timeout" end
		return success, response
	end

	-- soul fruit
	local function countSoulCakes()
		local effects = workspace:FindFirstChild("Effects")
		if not effects then return 0 end
		local count = 0

		for _, child in ipairs(effects:GetChildren()) do
			if child.Name == "Cake" then count += 1 end
		end

		return count
	end

	local function soulRay(target)
		local ok, response = invokeWithTimeout(ReplicatedStorage.Events.Skill, skills.SkillInvokeTimeout, "Prominence Ray", target)
		local failed = not ok or type(response) ~= "table" or typeof(response[1]) ~= "Instance"

		if failed then return false end
		task.wait(skills.SoulRayDuration)

		pcall(function()
			response[1]:FireServer("Finished")
		end)

		return true
	end

	local function soulCake(spawnCFrame)
		ReplicatedStorage.Events.Skill:InvokeServer("Crumbleshot, the Cake", { SpawnCFrame = spawnCFrame })
	end

	local function placeBariCage(cframe)
		return (pcall(function()
			ReplicatedStorage.Events.Skill:InvokeServer("Barrier Cage", { cf = cframe })
		end))
	end

	local function soulBonBomb(target)
		local rootCFrame = getRootCFrame()
		if not rootCFrame then return false end
		local ok, remote = invokeWithTimeout(ReplicatedStorage.Events.Skill, skills.SkillInvokeTimeout, "Bon-Bon Bomb")

		if ok and type(remote) == "table" and typeof(remote[1]) == "Instance" then
			remote = remote[1]
		end

		if not ok or typeof(remote) ~= "Instance" then
			warn("[Soul] Bon-Bon Bomb returned no remote.")
			return false
		end

		pcall(function()
			remote:FireServer(target, rootCFrame)
		end)

		return true
	end

	local function soulBonFireball(target)
		local rootCFrame = getRootCFrame()
		if not rootCFrame then return false end

		if not invokeWithTimeout(ReplicatedStorage.Events.Skill, skills.SkillInvokeTimeout, "Bon-Bon Fireball", { SunCFrame = rootCFrame, MousePosition = target }) then
			warn("[Soul] Bon-Bon Fireball invoke failed.")
			return false
		end
		return true
	end

	local function getInstancePosition(instance)
		if instance:IsA("BasePart") then return instance.Position end

		if instance:IsA("Model") then
			local ok, result = pcall(function()
				return instance:GetPivot().Position
			end)

			if ok then return result end
		end

		return nil
	end

	local function nextCrumbleShotCFrame()
		local crumbleShotPoints = locations.CrumbleShotPoints
		if type(crumbleShotPoints) ~= "table" or #crumbleShotPoints == 0 then return nil end
		local cakePositions = {}
		local effects = workspace:FindFirstChild("Effects")

		if effects then
			for _, child in ipairs(effects:GetChildren()) do
				if child.Name == "Cake" then
					local position = getInstancePosition(child)

					if position then cakePositions[#cakePositions + 1] = position end
				end
			end
		end

		local crumbleshotOccupiedRadius = skills.CrumbleshotOccupiedRadius

		for _, crumbleShotPoint in ipairs(crumbleShotPoints) do
			local free = true

			for _, cakePos in ipairs(cakePositions) do
				if (cakePos - crumbleShotPoint.Position).Magnitude <= crumbleshotOccupiedRadius then
					free = false
					break
				end
			end

			if free then return crumbleShotPoint end
		end

		return nil
	end

	-- mega pow
	local megaPowFiring = false

	local function megaPowBarrage(enable)
		if not enable then
			megaPowFiring = false

			pcall(function()
				local megaPowTool = localPlayer.Character
				megaPowTool = megaPowTool and megaPowTool:FindFirstChild("Mega-Pow")

				if megaPowTool and megaPowTool:FindFirstChild("MinigunHandleServer") then
					megaPowTool.MinigunHandleServer.input:InvokeServer(false)
				end
			end)

			return false
		end

		if megaPowFiring then return false end
		setItemEquipped("Mega-Pow", true)
		task.wait(0.3)
		local character = localPlayer.Character
		if not character then return false end
		local megaPow = character:FindFirstChild("Mega-Pow") or getBackpack():FindFirstChild("Mega-Pow")
		if not megaPow then
			warn("[MegaPow] Tool not found in Character or Backpack!")
			return false
		end
		local minigunHandleServer = megaPow:FindFirstChild("MinigunHandleServer")
		minigunHandleServer = minigunHandleServer and minigunHandleServer:FindFirstChild("input")
		if not minigunHandleServer then
			warn("[MegaPow] MinigunHandleServer.input remote not found!")
			return false
		end
		local targetCFrame = getTargetPosition()
		if not targetCFrame then return false end

		local ok, fireRemote = pcall(function()
			return minigunHandleServer:InvokeServer(true, targetCFrame.Position)
		end)

		if not (ok and fireRemote) then
			warn("[MegaPow] InvokeServer failed or returned nil.")
			return false
		end
		megaPowFiring = true

		task.spawn(function()
			local startedAt = os.clock()

			while megaPowFiring and os.clock() - startedAt < 10 do
				local aim = getTargetPosition()

				if not aim then break end

				pcall(function()
					fireRemote:FireServer(aim.Position)
				end)

				task.wait(0.05)
			end

			pcall(function()
				minigunHandleServer:InvokeServer(false)
			end)

			megaPowFiring = false
		end)

		return true
	end

	-- cyborg
	local function getLegCFrame(model)
		if not model or not model.Parent then return nil end
		local leftLowerLeg = model:FindFirstChild("LeftLowerLeg")
		if leftLowerLeg and leftLowerLeg:IsA("BasePart") then return leftLowerLeg.CFrame end
		return getAimCFrame(model)
	end

	local function cyborgMissleShower(target, shouldContinue, findNextTarget)
		local aimCFrame = getLegCFrame(target)
		if not aimCFrame then return false, target end
		local remote
		local ok

		for i = 1, 3 do
			ok, remote = invokeWithTimeout(ReplicatedStorage.Events.Skill, skills.SkillInvokeTimeout, "Missle Shower", aimCFrame)

			if ok and type(remote) == "table" and typeof(remote[1]) == "Instance" then
				remote = remote[1]
			end

			local gotRemote = ok and typeof(remote) == "Instance"

			if gotRemote then break end

			if i < 2 then task.wait(1) end
		end

		if not ok or typeof(remote) ~= "Instance" then
			warn("[Cyborg] Missle Shower returned no remote.")
			return false, target
		end

		for i = 1, skills.CyborgBarrageTicks do
			task.wait(skills.CyborgTickInterval)

			if not (shouldContinue and not shouldContinue()) then
				local aim

				if not isTargetAlive(target) then
					local nextTarget = findNextTarget and findNextTarget()

					if nextTarget then
						target = nextTarget
						aim = getLegCFrame(target)

						if aim then
							pcall(function()
								remote:FireServer(aim)
							end)

							continue
						end
					end
				else
					aim = getLegCFrame(target)

					if aim then
						pcall(function()
							remote:FireServer(aim)
						end)

						continue
					end
				end
			end

			break
		end

		pcall(function()
			remote:FireServer()
		end)

		return true, target
	end

	-- laser pulsar
	local pendingLasers = {}
	local laserCleanupRunning = false

	local function finishStaleLasers()
		local now = os.clock()

		for i = #pendingLasers, 1, -1 do
			local pending = pendingLasers[i]

			if 10 <= now - pending.since then
				local character = localPlayer.Character
				local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")

				if humanoidRootPart then
					pcall(function()
						pending.remote:FireServer(humanoidRootPart)
					end)
				end

				table.remove(pendingLasers, i)
			end
		end
	end

	local function startLaserCleanup()
		if laserCleanupRunning then return end
		laserCleanupRunning = true

		task.spawn(function()
			while #pendingLasers > 0 do
				task.wait(10)
				finishStaleLasers()
			end

			laserCleanupRunning = false
		end)
	end

	local function laserPulsar(target)
		if not isTargetAlive(target) then return false end
		local aimCFrame = getAimCFrame(target)
		if not aimCFrame then return false end
		local ok, remote = invokeWithTimeout(ReplicatedStorage.Events.Skill, skills.SkillInvokeTimeout, "Laser Pulsar", { cf = aimCFrame })
		local isTable = ok and type(remote) == "table"

		if isTable and typeof(remote[1]) == "Instance" then remote = remote[1] end

		if not ok or typeof(remote) ~= "Instance" then
			warn("[Laser] Laser Pulsar returned no remote.")
			return false
		end
		table.insert(pendingLasers, { remote = remote, since = os.clock() })
		startLaserCleanup()
		task.wait(1)
		if not isTargetAlive(target) then return false end
		aimCFrame = getAimCFrame(target) or aimCFrame

		pcall(function()
			remote:FireServer(aimCFrame)
		end)

		task.wait(0.1)
		return true
	end

	-- magma
	local function maguHound(target)
		if not isTargetAlive(target) then return false end
		local ok, remote = invokeWithTimeout(ReplicatedStorage.Events.Skill, skills.SkillInvokeTimeout, "Magma Hound")

		if ok and type(remote) == "table" and typeof(remote[1]) == "Instance" then
			remote = remote[1]
		end

		local failed = not ok or typeof(remote) ~= "Instance"

		if failed then
			warn("[Magma] Magma Hound returned no remote.")
			return false
		end
		task.wait(0.1)
		if not isTargetAlive(target) then return false end
		local aimCFrame = getAimCFrame(target)
		if not aimCFrame then return false end
		faceTarget(aimCFrame.Position)
		task.wait(0.1)
		if not isTargetAlive(target) then return false end
		invokeWithTimeout(remote, skills.SkillInvokeTimeout, getAimCFrame(target) or aimCFrame)
		return true
	end

	local function maguFist(target)
		if not isTargetAlive(target) then return false end
		local ok, remote = invokeWithTimeout(ReplicatedStorage.Events.Skill, skills.SkillInvokeTimeout, "Magma Fist")
		local isTable = ok and type(remote) == "table"

		if isTable and typeof(remote[1]) == "Instance" then remote = remote[1] end

		local failed = not ok or typeof(remote) ~= "Instance"

		if failed then
			warn("[Magma] Magma Fist returned no remote.")
			return false
		end
		task.wait(0.2)
		if not isTargetAlive(target) then return false end
		local aimCFrame = getAimCFrame(target)
		if not aimCFrame then return false end
		faceTarget(aimCFrame.Position)
		task.wait(0.1)
		if not isTargetAlive(target) then return false end
		invokeWithTimeout(remote, skills.SkillInvokeTimeout, getAimCFrame(target) or aimCFrame)
		return true
	end

	local function maguRain(target, shouldContinue)
		if not getAimCFrame(target) then return false end
		local ok, remotes = invokeWithTimeout(ReplicatedStorage.Events.Skill, skills.SkillInvokeTimeout, "Magma Rain")
		if not ok or type(remotes) ~= "table" or typeof(remotes[1]) ~= "Instance" or typeof(remotes[2]) ~= "Instance" then
			warn("[Magma] Magma Rain returned no remotes.")
			return false
		end

		for i = 1, skills.MaguRainTicks do
			task.wait(skills.MaguRainTickInterval)

			if not (shouldContinue and not shouldContinue()) and isTargetAlive(target) then
				local aimCFrame = getAimCFrame(target)

				if aimCFrame then
					pcall(function()
						remotes[2]:FireServer(aimCFrame.Position)
					end)

					continue
				end
			end

			break
		end

		invokeWithTimeout(remotes[1], skills.SkillInvokeTimeout)
		return true
	end

	-- katana
	local katanaSlashCache

	local function getKatanaSlashes()
		if katanaSlashCache then return katanaSlashCache end

		local ok, slashesFolder = pcall(function()
			return ReplicatedStorage:WaitForChild("Modules", 10):WaitForChild("SwordHandle", 10):WaitForChild("Swords", 10):WaitForChild("Katana", 10):WaitForChild("Slashes", 10)
		end)

		if not (ok and slashesFolder) then return nil end
		local slashes = {}

		for i, katanaSlashName in ipairs(skills.KatanaSlashNames) do
			slashes[i] = slashesFolder:FindFirstChild(katanaSlashName)
		end

		katanaSlashCache = slashes
		return slashes
	end

	local function castKatanaSlash(slashIndex, target)
		local rootCFrame = getRootCFrame()
		if not rootCFrame then return false end

		pcall(function()
			ReplicatedStorage.Events.CombatRegister:InvokeServer({ "damage", target, "Sword", { slashIndex, "Ground", [2] = "Sword" }, true, [8] = rootCFrame })
		end)

		local slash = getKatanaSlashes()
		slash = slash and slash[slashIndex]

		if slash then
			pcall(function()
				ReplicatedStorage.Events.CombatRegister:InvokeServer({
					"swingsfx",
					[2] = "Sword",
					[3] = slashIndex,
					[3] = "Ground",
					[5] = false,
					[8] = slash,
					[7] = skills.KatanaSwingSpeeds[slashIndex],
					[8] = 1,
				})
			end)
		end

		return true
	end

	local function katanaCombo(target, shouldContinue, onDone)
		task.spawn(function()
			for i = 1, 5 do
				if not (shouldContinue and not shouldContinue()) and castKatanaSlash(i, target) then
					task.wait(skills.KatanaComboDelay)
					continue
				end

				break
			end

			if onDone then onDone() end
		end)
	end

	-- leopard
	local instinctLabelPath = { "Abilities", "Main", "List", "ModeBar", "Base", "Progress" }

	local function getInstinctText()
		local playerGui = localPlayer:FindFirstChild("PlayerGui")

		for _, childName in ipairs(instinctLabelPath) do
			if not playerGui then return nil end
			playerGui = playerGui:FindFirstChild(childName)
		end

		if not playerGui then return nil end

		local ok, result = pcall(function()
			return playerGui.Text
		end)

		if not ok or type(result) ~= "string" then return nil end
		return result
	end

	local function leopardInstinctMaxed()
		local text = getInstinctText()
		if not text then return false end
		return string.find(string.upper(text), "MAXED", 1, true) ~= nil
	end

	local groundSlashCache

	local function getLeopardGroundSlash()
		if groundSlashCache then return groundSlashCache end
		local modules = ReplicatedStorage:FindFirstChild("Modules")

		for _, childName in ipairs({ "SwordHandle", "Swords", "LeopardHybird", "Slashes", "GroundSlash4" }) do
			if not modules then return nil end
			modules = modules:FindFirstChild(childName)
		end

		if not modules then
			warn("[Leopard] No LeopardHybird GroundSlash4 animation - cannot swing.")
			return nil
		end
		groundSlashCache = modules
		return modules
	end

	local function leopardM1Combo(shouldContinue)
		local slashAnim = getLeopardGroundSlash()
		if not slashAnim then return false end

		for i = 1, 4 do
			if shouldContinue and not shouldContinue() then return false end

			pcall(function()
				ReplicatedStorage.Events.CombatRegister:InvokeServer({
					"swingsfx",
					"Sword",
					i,
					[3] = "Ground",
					[5] = false,
					[6] = slashAnim,
					[7] = 1.4367815256118774,
					[8] = 2,
				})
			end)

			task.wait(skills.LeopardM1Delay or 0.4)
		end

		return true
	end

	local function equipLeopardFruit()
		if not setItemEquipped then
			warn("[Leopard] Attacks.Init had no setItemEquipped - cannot equip the fruit.")
			return false
		end
		return setItemEquipped("Leopard-Leopard", true) == true
	end

	local function unequipLeopardFruit()
		if not setItemEquipped then
			warn("[Leopard] Attacks.Init had no setItemEquipped - cannot unequip the fruit.")
			return false
		end
		return setItemEquipped("Leopard-Leopard", false) == true
	end

	local function rankyakuRebound(position)
		local ok, remote = invokeWithTimeout(ReplicatedStorage.Events.Skill, skills.SkillInvokeTimeout, "Rankyaku: Rebound")

		if ok and type(remote) == "table" and typeof(remote[1]) == "Instance" then
			remote = remote[1]
		end

		if not ok or typeof(remote) ~= "Instance" then
			warn("[Leopard] Rankyaku: Rebound returned no remote.")
			return false
		end

		pcall(function()
			remote:FireServer(position)
		end)

		return true
	end

	local function enterLeopardHybrid(shouldContinue, target)
		if not equipLeopardFruit() then return false end
		local deadline = os.clock() + (skills.LeopardInstinctTimeout or 60)
		local lastRankyakuAt = 0

		while os.clock() < deadline do
			if shouldContinue and not shouldContinue() then return false end

			if leopardInstinctMaxed() then
				print("[Leopard] Instinct bar read \"" .. tostring(getInstinctText()) .. "\" - breaking out of the wait to transform.")
				break
			end
			local canRankyaku = target and (os.clock() - lastRankyakuAt >= (skills.RankyakuReboundCooldown or 19))

			if canRankyaku then
				local aimCFrame = getAimCFrame(target)

				if aimCFrame then rankyakuRebound(aimCFrame.Position) end

				lastRankyakuAt = os.clock()
			end

			task.wait(0.25)
		end

		if not leopardInstinctMaxed() then
			warn("[Leopard] Instinct never reached MAXED - staying in Human form rather than burning the transform. Last read: \"" .. tostring(getInstinctText()) .. "\"")
			return false
		end

		if not invokeWithTimeout(ReplicatedStorage.Events.Skill, skills.SkillInvokeTimeout, "Leopard Ascension", "Hybird") then
			warn("[Leopard] Leopard Ascension invoke failed.")
			return false
		end
		return true
	end

	local function exitLeopardHybrid()
		if not invokeWithTimeout(ReplicatedStorage.Events.Skill, skills.SkillInvokeTimeout, "Leopard Ascension", "Human") then
			warn("[Leopard] Could not detransform out of hybrid form.")
			return false
		end
		return true
	end

	-- exports
	Abilities.getLoweredName = getLoweredName
	Abilities.findTargetModel = findTargetModel
	Abilities.countNearbySpecies = countNearbySpecies
	Abilities.getAimCFrame = getAimCFrame
	Abilities.isTargetAlive = isTargetAlive
	Abilities.setTargetSelector = setTargetSelector
	Abilities.getTargetModel = getTargetModel
	Abilities.getTargetPosition = getTargetPosition
	Abilities.countSoulCakes = countSoulCakes
	Abilities.soulRay = soulRay
	Abilities.soulCake = soulCake
	Abilities.placeBariCage = placeBariCage
	Abilities.soulBonBomb = soulBonBomb
	Abilities.soulBonFireball = soulBonFireball
	Abilities.nextCrumbleShotCFrame = nextCrumbleShotCFrame
	Abilities.MegaPowBarrage = megaPowBarrage

	Abilities.isMegaPowBarrageActive = function()
		return megaPowFiring
	end

	Abilities.cyborgMissleShower = cyborgMissleShower
	Abilities.laserPulsar = laserPulsar
	Abilities.maguHound = maguHound
	Abilities.maguFist = maguFist
	Abilities.maguRain = maguRain
	Abilities.castKatanaSlash = castKatanaSlash
	Abilities.katanaCombo = katanaCombo
	Abilities.leopardInstinctMaxed = leopardInstinctMaxed
	Abilities.leopardM1Combo = leopardM1Combo
	Abilities.equipLeopardFruit = equipLeopardFruit
	Abilities.unequipLeopardFruit = unequipLeopardFruit
	Abilities.enterLeopardHybrid = enterLeopardHybrid
	Abilities.exitLeopardHybrid = exitLeopardHybrid
	Abilities.rankyakuRebound = rankyakuRebound
	return Abilities
end

defineModule("Abilities", createAbilities)

----------------------------------------------------------------------------
-- FruitInventory: fruit inventory: store, drop, equip
----------------------------------------------------------------------------
local function createFruitInventory()
	local Players = cloneref(game:GetService("Players"))
	local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
	local HttpService = cloneref(game:GetService("HttpService"))
	local virtualInputManager = Instance.new("VirtualInputManager")
	local localPlayer = Players.LocalPlayer
	local fruitRarity
	local fruitPngs
	local fruitCliffSet
	local storage
	local pingId = ""

	local function itemWebhook()
	end

	local function mythicalDropWebhook()
	end

	-- inventory
	local function getBackpack()
		return localPlayer:FindFirstChildOfClass("Backpack") or localPlayer:WaitForChild("Backpack", 5)
	end

	local lastInventoryJson
	local inventoryCache = {}

	local function getInventoryTable()
		local inventory = ReplicatedStorage:FindFirstChild("Stats" .. localPlayer.Name)
		inventory = inventory and inventory:FindFirstChild("Inventory")
		local inventory2 = inventory and inventory:FindFirstChild("Inventory")
		if not inventory2 then return {} end
		local json = tostring(inventory2.Value)
		if json == lastInventoryJson then return inventoryCache end
		local ok, result = pcall(HttpService.JSONDecode, HttpService, json)
		lastInventoryJson = json
		inventoryCache = ok and type(result) == "table" and result or {}
		return inventoryCache
	end

	local function getStoredCount(fruitName)
		return tonumber(getInventoryTable()[fruitName]) or 0
	end

	local function isCliffFruit(fruitName)
		return fruitCliffSet[fruitName] == true
	end

	local alwaysMythical = { Biscuit = true, Pika = true }

	local function isMythicalFruit(fruitName)
		return fruitRarity[fruitName] == "Mythical" or alwaysMythical[fruitName] == true
	end

	local function getCarriedFruitCounts()
		local counts = {}

		local function count(name)
			if fruitRarity[name] then counts[name] = (counts[name] or 0) + 1 end
		end

		local backpack = getBackpack()

		if backpack then
			for _, child in ipairs(backpack:GetChildren()) do
				if child:IsA("Tool") then count(child.Name) end
			end
		end

		local character = localPlayer.Character

		if character then
			for _, child in ipairs(character:GetChildren()) do
				if child:IsA("Tool") then count(child.Name) end
			end
		end

		return counts
	end

	local function getCarriedFruits()
		local names = {}

		for k in pairs(getCarriedFruitCounts()) do
			names[#names + 1] = k
		end

		table.sort(names)
		return names
	end

	local function countCarriedFruit(fruitName)
		return getCarriedFruitCounts()[fruitName] or 0
	end

	local function isCarryingFruit(fruitName)
		return countCarriedFruit(fruitName) > 0
	end

	local function countStoredFruits()
		local total = 0

		for k, amount in pairs(getInventoryTable()) do
			if fruitRarity[k] then total += tonumber(amount) or 0 end
		end

		return total
	end

	local function hasFruitBag()
		return (tonumber(getInventoryTable()["Fruit Bag"]) or 0) > 0
	end

	local function hasStorageRoom()
		if hasFruitBag() then return true end
		return countStoredFruits() < storage.NoBagFruitCapacity
	end

	-- equip / drop
	local function getEquippedTool(container, itemName)
		local item = container:FindFirstChild(itemName)
		return item and item:IsA("Tool") and item or nil
	end

	local function setItemEquipped(itemName, equip)
		local character = localPlayer.Character or localPlayer.CharacterAdded:Wait()
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			warn("[Equip] No Humanoid; cannot change equip state for '" .. itemName .. "'.")
			return false
		end
		local backpack = getBackpack()
		if not backpack then return false end

		if equip then
			if getEquippedTool(character, itemName) then return true end
			local tool = backpack:FindFirstChild(itemName)
			if not (tool and tool:IsA("Tool")) then
				warn("[Equip] Item '" .. itemName .. "' not found in Backpack.")
				return false
			end

			if not pcall(humanoid.EquipTool, humanoid, tool) then
				pcall(function()
					tool.Parent = character
				end)
			end
		else
			local tool = getEquippedTool(character, itemName)
			if not tool then return true end

			if not pcall(humanoid.UnequipTools, humanoid) then
				pcall(function()
					tool.Parent = backpack
				end)
			end
		end

		local deadline = os.clock() + storage.EquipVerifyTimeout

		while os.clock() < deadline do
			if getEquippedTool(character, itemName) ~= nil == equip then return true end
			task.wait(0.05)
		end

		warn("[Equip] Could not verify '" .. itemName .. "' " .. (equip and "equipped" or "unequipped") .. " within " .. storage.EquipVerifyTimeout .. "s.")
		return false
	end

	local function findCarriedFruitInstance(fruitName)
		local tool = localPlayer.Character
		tool = tool and tool:FindFirstChild(fruitName)
		if tool and tool:IsA("Tool") then return tool end
		local backpackTool = getBackpack()
		backpackTool = backpackTool and backpackTool:FindFirstChild(fruitName)
		if backpackTool and backpackTool:IsA("Tool") then return backpackTool end
		return nil
	end

	local function dropFruit(fruitName)
		local carriedBefore = countCarriedFruit(fruitName)
		if carriedBefore == 0 then
			print("[Drop] Not carrying " .. fruitName .. " - nothing to drop.")
			return false
		end
		local tool = findCarriedFruitInstance(fruitName)
		if not tool then
			warn("[Drop] Could not find a carried instance for '" .. fruitName .. "'.")
			return false
		end

		if not setItemEquipped(fruitName, true) then
			warn("[Drop] Could not equip '" .. fruitName .. "' to drop it.")
			return false
		end
		task.wait(0.5)

		if not pcall(function()
			ReplicatedStorage.Events.Tools:InvokeServer("drop", tool)
		end) then
			warn("[Drop] Remote call failed for '" .. fruitName .. "'.")
			return false
		end

		local deadline = os.clock() + 5

		while os.clock() < deadline do
			if countCarriedFruit(fruitName) < carriedBefore then
				print("[Drop] Dropped " .. fruitName .. ".")
				return true
			end
			task.wait(0.25)
		end

		warn("[Drop] Still carrying '" .. fruitName .. "' after dropping.")
		return false
	end

	local function findDroppedFruits(nearPos, maxDistance)
		local results = {}
		local nearZ
		local nearX

		if nearPos then
			nearX = nearPos.X
			nearZ = nearPos.Z
		end

		for _, child in ipairs(workspace:GetChildren()) do
			if child:IsA("Tool") and fruitRarity[child.Name] then
				local handle = child:FindFirstChild("Handle") or child:FindFirstChildWhichIsA("BasePart")

				if handle then
					local position = handle.Position
					local distance = 0

					if nearX then
						local dx = position.X - nearX
						local dz = position.Z - nearZ
						distance = math.sqrt(dx * dx + dz * dz)
					end

					if not maxDistance or distance <= maxDistance then
						results[#results + 1] = { instance = child, name = child.Name, position = position, distance = distance }
					end
				end
			end
		end

		table.sort(results, function(a, b)
			return a.distance < b.distance
		end)

		return results
	end

	-- storing
	local function holdStoreKey()
		virtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
		task.wait(0.1)
		virtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
		task.wait(0.1)
		virtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
		task.wait(0.25)
		virtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
		task.wait(0.2)
		virtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
		task.wait(2)
		virtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
	end

	local function invokeFruitStorage()
		return pcall(function()
			ReplicatedStorage.Events.FruitStorage:InvokeServer(true)
		end)
	end

	local function tryStoreFruit(fruitName)
		if 0 < getStoredCount(fruitName) then
			print("[Store] Already storing a " .. fruitName .. " - not trying, dropping instead.")
			return false
		end

		if not hasStorageRoom() then
			print("[Store] Inventory has no room for " .. fruitName .. " - not trying.")
			return false
		end
		local storedBefore = getStoredCount(fruitName)
		local taken

		for i = 1, storage.StoreAttempts do
			if not isCarryingFruit(fruitName) then return getStoredCount(fruitName) > storedBefore end

			if setItemEquipped(fruitName, true) then
				task.wait(0.5)
				local storedNow = getStoredCount(fruitName)
				local carriedNow = countCarriedFruit(fruitName)

				if not invokeFruitStorage() then
					warn("[Store] Remote call failed for '" .. fruitName .. "'.")
				end

				local deadline = os.clock() + storage.StoreTakenTimeout

				taken = false

				while os.clock() < deadline do
					if countCarriedFruit(fruitName) < carriedNow then
						taken = true
						break
					end

					task.wait(0.25)
				end

				if taken then
					local confirmDeadline = os.clock() + storage.StoreConfirmTimeout

					while os.clock() < confirmDeadline do
						if storedNow < getStoredCount(fruitName) then return true end
						task.wait(0.25)
					end
				end
			else
				warn("[Store] Could not equip '" .. fruitName .. "' to store it.")
			end

			if i >= storage.StoreAttempts then continue end

			if not hasStorageRoom() then
				print("[Store] Inventory filled up while storing " .. fruitName .. " - giving up.")
				return false
			end
			print("[Store] " .. fruitName .. " didn't store (attempt " .. i .. "/" .. storage.StoreAttempts .. ") - retrying.")
			task.wait(0.5)
		end

		return false
	end

	-- queue of fruits that still need to be stored or dropped
	local function createFruitQueue(label)
		local fruitQueue

		fruitQueue = {
			queue = {},
			claimed = {},
			attempts = {},
			abandoned = {},
			held = {},
			enqueue = function(fruitName)
				if not fruitRarity[fruitName] then return end

				if fruitQueue.claimed[fruitName] then return end

				if fruitQueue.held[fruitName] then return end
				local abandonedAt = fruitQueue.abandoned[fruitName]
				local inBackoff

				if abandonedAt then
					inBackoff = os.clock() - abandonedAt < storage.FruitRetryBackoff
				else
					inBackoff = abandonedAt
				end

				if inBackoff then return end

				if abandonedAt then
					fruitQueue.abandoned[fruitName] = nil
					fruitQueue.attempts[fruitName] = nil
					print("[" .. label .. "] Retrying " .. fruitName .. " after the back-off.")
				end

				fruitQueue.claimed[fruitName] = true
				table.insert(fruitQueue.queue, fruitName)
				print("[" .. label .. "] Queued " .. fruitName .. " (" .. fruitRarity[fruitName] .. ").")
			end,
			forget = function(fruitName)
				fruitQueue.attempts[fruitName] = nil
				fruitQueue.abandoned[fruitName] = nil
				fruitQueue.held[fruitName] = nil
			end,
		}

		local hadRoom = hasStorageRoom()

		fruitQueue.sweep = function()
			local hasRoom = hasStorageRoom()

			if hasRoom and not hadRoom then
				for k in pairs(fruitQueue.abandoned) do
					if countCarriedFruit(k) > 0 then
						print("[" .. label .. "] Storage has room again - retrying " .. k .. ".")
						fruitQueue.abandoned[k] = nil
						fruitQueue.attempts[k] = nil
					end
				end
			end

			hadRoom = hasRoom

			for k, count in pairs(getCarriedFruitCounts()) do
				if count > 0 then fruitQueue.enqueue(k) end
			end
		end

		fruitQueue.release = function(fruits)
			for _, fruitName in ipairs(fruits) do
				fruitQueue.held[fruitName] = nil

				if countCarriedFruit(fruitName) == 0 then
					fruitQueue.forget(fruitName)
				else
					fruitQueue.enqueue(fruitName)
				end
			end
		end

		local backpackConnection

		local function watchBackpack(backpack)
			if not backpack then return end

			if backpackConnection then
				backpackConnection:Disconnect()
				backpackConnection = nil
			end

			table.clear(fruitQueue.queue)
			fruitQueue.claimed = {}
			fruitQueue.attempts = {}
			fruitQueue.abandoned = {}
			fruitQueue.held = {}
			hadRoom = hasStorageRoom()

			backpackConnection = backpack.ChildAdded:Connect(function(child)
				if fruitRarity[child.Name] then fruitQueue.enqueue(child.Name) end
			end)

			for _, fruitName in ipairs(getCarriedFruits()) do
				fruitQueue.enqueue(fruitName)
			end
		end

		watchBackpack(getBackpack())

		localPlayer.ChildAdded:Connect(function(child)
			if child:IsA("Backpack") then watchBackpack(child) end
		end)

		return fruitQueue
	end

	local function drainFruitQueue(queue, handler, shouldContinue, label)
		local heldFruits = {}

		while #queue.queue > 0 and shouldContinue() do
			local fruitName = table.remove(queue.queue, 1)

			if countCarriedFruit(fruitName) == 0 then
				queue.claimed[fruitName] = nil
				queue.forget(fruitName)
			else
				local carriedBefore = countCarriedFruit(fruitName)
				local attempt = (queue.attempts[fruitName] or 0) + 1
				queue.attempts[fruitName] = attempt
				local ok, result = pcall(handler, fruitName)

				if not ok then
					warn("[" .. label .. "] " .. fruitName .. ": " .. tostring(result))
				end

				local carriedAfter = countCarriedFruit(fruitName)
				queue.claimed[fruitName] = nil

				if ok and result and attempt < storage.FruitMaxAttempts then
					queue.held[fruitName] = true
					heldFruits[#heldFruits + 1] = fruitName
				elseif ok and result then
					warn("[" .. label .. "] " .. fruitName .. " survived " .. attempt .. " trips - retrying in " .. storage.FruitRetryBackoff .. "s.")
					queue.abandoned[fruitName] = os.clock()
				elseif carriedAfter == 0 then
					queue.forget(fruitName)
				elseif carriedAfter < carriedBefore then
					queue.attempts[fruitName] = nil
				elseif storage.FruitMaxAttempts <= attempt then
					warn("[" .. label .. "] Giving up on " .. fruitName .. " after " .. attempt .. " attempts - retrying in " .. storage.FruitRetryBackoff .. "s.")
					queue.abandoned[fruitName] = os.clock()
				end
			end

			if #queue.queue == 0 then queue.sweep() end
		end

		return heldFruits
	end

	return {
		Init = function(options)
			local opts = options or {}
			fruitRarity = opts.fruitRarity
			fruitPngs = opts.fruitPngs
			fruitCliffSet = opts.fruitCliffSet or {}
			storage = opts.Storage
			pingId = opts.PingID or ""

			if type(opts.itemWebhook) == "function" then
				itemWebhook = opts.itemWebhook
			end

			if type(opts.mythicalDropWebhook) == "function" then
				mythicalDropWebhook = opts.mythicalDropWebhook
			end
		end,
		handleFruitGeneric = function(label, stats, fruitName, options)
			local opts = options or {}
			print("[" .. label .. "] Handling " .. fruitName .. " | rarity: " .. fruitRarity[fruitName])
			stats.status("Storing")

			if tryStoreFruit(fruitName) then
				print("[" .. label .. "] Stored " .. fruitName .. ".")
				stats.recordFruit(fruitName, "stored")

				if isCliffFruit(fruitName) then
					itemWebhook({
						item = fruitName,
						event = "Fruit Stored",
						ping = pingId,
						img = fruitPngs[fruitName] or fruitPngs.Rest,
						webhookUrl = opts.webhookUrl,
					})
				end

				if isMythicalFruit(fruitName) then
					mythicalDropWebhook(fruitName, "Stored", fruitPngs[fruitName] or fruitPngs.Rest)
				end

				return false
			end

			if opts.deferCliffFruit and isCliffFruit(fruitName) then return true end
			print("[" .. label .. "] " .. fruitName .. " can't be stored - dropping it here.")
			stats.status("Dropping")
			local dropped

			if opts.aroundDrop then
				dropped = opts.aroundDrop(function()
					return dropFruit(fruitName)
				end)
			else
				dropped = dropFruit(fruitName)
			end

			if dropped then
				stats.recordFruit(fruitName, "dropped")
				local send = itemWebhook
				local payload = { item = fruitName, event = "Fruit Dropped" }
				local cliffPing = opts.dropPingCliffOnly and (isCliffFruit(fruitName) and pingId or "")
				local dropPing

				if cliffPing then
					dropPing = cliffPing
				else
					dropPing = opts.dropPing or ""
				end

				payload.ping = dropPing
				payload.img = fruitPngs[fruitName] or fruitPngs.Rest
				payload.webhookUrl = opts.webhookUrl
				send(payload)

				if isMythicalFruit(fruitName) then
					mythicalDropWebhook(fruitName, "Dropped", fruitPngs[fruitName] or fruitPngs.Rest)
				end
			end

			return false
		end,
		startFruitLoopGeneric = function(queue, handler, shouldContinue, label, setBusy, onHeld, afterDrain)
			task.spawn(function()
				while shouldContinue() do
					pcall(queue.sweep)

					if #queue.queue > 0 then
						setBusy(true)
						local ok, result = pcall(drainFruitQueue, queue, handler, shouldContinue, label)

						if not ok then
							warn("[" .. label .. "] fruit drain: " .. tostring(result))
						elseif onHeld then
							onHeld(result)
						end

						setBusy(false)

						if shouldContinue() and afterDrain then afterDrain() end
					end

					task.wait(1)
				end
			end)
		end,
		getBackpack = getBackpack,
		getInventoryTable = getInventoryTable,
		getStoredCount = getStoredCount,
		isCliffFruit = isCliffFruit,
		isMythicalFruit = isMythicalFruit,
		getCarriedFruitCounts = getCarriedFruitCounts,
		getCarriedFruits = getCarriedFruits,
		countCarriedFruit = countCarriedFruit,
		isCarryingFruit = isCarryingFruit,
		countStoredFruits = countStoredFruits,
		hasFruitBag = hasFruitBag,
		hasStorageRoom = hasStorageRoom,
		getEquippedTool = getEquippedTool,
		setItemEquipped = setItemEquipped,
		findCarriedFruitInstance = findCarriedFruitInstance,
		dropFruit = dropFruit,
		findDroppedFruits = findDroppedFruits,
		holdStoreKey = holdStoreKey,
		invokeFruitStorage = invokeFruitStorage,
		tryStoreFruit = tryStoreFruit,
		createFruitQueue = createFruitQueue,
		drainFruitQueue = drainFruitQueue,
	}
end

defineModule("FruitInventory", createFruitInventory)

----------------------------------------------------------------------------
-- LureShared: stuff shared by the lure / anchor / killer roles
----------------------------------------------------------------------------
local function createLureShared()
	local Players = cloneref(game:GetService("Players"))

	local random2 = math.random
	local config
	local locations
	local boatSpawns
	local statsGui
	local fruitRarity
	local localPlayer

	local function errorHoldCount()
		return 0
	end

	local function postWebhook()
	end

	local combatTuning = {}
	local partySystem

	-- roles and their posts
	local killerRoles = { "Killer", "Killer2", "Killer3" }
	local anchorRoles = { "Anchor", "Anchor2" }

	local function isRoleManned(role)
		local username = config.Roles[role]
		return type(username) == "string" and username ~= ""
	end

	local function mannedRoles(roles)
		local manned = {}
		local list = roles

		for _, role in ipairs(list) do
			if isRoleManned(role) then manned[#manned + 1] = role end
		end

		return manned
	end

	local function pointForRole(points, role, fallback)
		local point = type(points) == "table" and points[role] or nil
		if typeof(point) == "CFrame" then return point end
		return fallback
	end

	local function withHeight(cframe, height)
		if not height then return cframe end
		local position = cframe.Position
		return CFrame.new(Vector3.new(position.X, height, position.Z)) * (cframe - position)
	end

	local function killerPointFor(role)
		return withHeight(pointForRole(locations.KillerPoints, role, locations.KillerPoint), positiveNumberOr(combatTuning.KillerPostHeight, nil))
	end

	local function killerRegroupPointFor(role)
		return pointForRole(locations.KillerRegroupPoints, role, locations.KillerRegroupPoint)
	end

	local function anchorPointFor(role)
		return pointForRole(locations.AnchorPoints, role, locations.AnchorPoint)
	end

	local function anchorRegroupPointFor(role)
		return pointForRole(locations.AnchorRegroupPoints, role, locations.AnchorRegroupPoint)
	end

	local function anchorOnlyMode()
		if config.AnchorOnlyMode == true then return true end

		for _, role in ipairs(killerRoles) do
			if isRoleManned(role) then return false end
		end

		return true
	end

	local function lurePikaFlightEnabled(lureKey)
		local lurePikaFlight = config.LurePikaFlight

		if type(lurePikaFlight) ~= "table" then return false end
		return lurePikaFlight[lureKey] == true
	end

	local function lureHieTPEnabled(lureKey)
		local lureHieTP = config.LureHieTP

		if type(lureHieTP) ~= "table" then return false end
		return lureHieTP[lureKey] == true
	end

	-- how each lure account travels
	local knownTravelMethods = { Default = true, Pika = true, Goro = true, Ito = true, HieTP = true }

	local function legacyTravelMethod(lureKey)
		if lureHieTPEnabled(lureKey) then return "HieTP" end

		if lurePikaFlightEnabled(lureKey) then return "Pika" end
		return nil
	end

	local function getLureTravelMethod(lureKey)
		local lureTravelMethod = config.LureTravelMethod
		local method = type(lureTravelMethod) == "table" and lureTravelMethod[lureKey] or nil
		if type(method) == "string" and knownTravelMethods[method] and method ~= "Default" then
			return method
		end

		if method == nil or method == "" or method == "Default" then
			local legacy = legacyTravelMethod(lureKey)
			if legacy then return legacy end
			return "Default"
		end

		warn("[RoleShared] " .. tostring(lureKey) .. " has an unknown LureTravelMethod (" .. tostring(method) .. ") - flying the default way.")
		return "Default"
	end

	-- waiting on the other accounts
	local function isRoleNearPoint(role, pointFor, radiusSq)
		local playerPos = partySystem.getPositionByName(config.Roles[role])
		local point = pointFor(role)
		if not (playerPos and point) then return false end
		local dx = playerPos.X - point.X
		local dz = playerPos.Z - point.Z
		return dx * dx + dz * dz <= radiusSq
	end

	local function waitForAnyRoleAtPoint(roles, pointFor, radius, roleLabel)
		if config.PartySyncEnabled == false then return end
		local manned = mannedRoles(roles)
		if #manned == 0 then return end
		local usernames = {}

		for _, role in ipairs(manned) do
			usernames[#usernames + 1] = config.Roles[role]
		end

		print("[Lure] Waiting for a " .. roleLabel .. " player (" .. table.concat(usernames, ", ") .. ") to arrive...")
		local radiusSq = radius * radius
		local startedAt = os.clock()
		local lastReport = startedAt

		while true do
			for _, role in ipairs(manned) do
				if isRoleNearPoint(role, pointFor, radiusSq) then
					print("[Lure] " .. roleLabel .. " confirmed at position (" .. role .. ")!")
					return
				end
			end

			local now = os.clock()

			if 10 <= now - lastReport then
				for _, role in ipairs(manned) do
					local username = config.Roles[role]
					local playerPos = partySystem.getPositionByName(username)
					local point = pointFor(role)
					local waited = math.floor(now - startedAt)

					if not playerPos then
						warn("[Lure] Still waiting on " .. roleLabel .. " (" .. role .. "/" .. username .. ") after " .. waited .. "s -- no party position yet (Player found: " .. tostring(Players:FindFirstChild(username) ~= nil) .. ").")
					elseif point then
						local dx = playerPos.X - point.X
						local dz = playerPos.Z - point.Z
						warn("[Lure] Still waiting on " .. roleLabel .. " (" .. role .. "/" .. username .. ") after " .. waited .. "s -- " .. math.floor(math.sqrt(dx * dx + dz * dz)) .. " studs away (radius " .. radius .. "). Real pos: " .. tostring(playerPos) .. ", expected point: " .. tostring(point.Position))
					end
				end

				lastReport = now
			end

			task.wait(2)
		end
	end

	local function waitForSupportRoles()
		waitForAnyRoleAtPoint(anchorRoles, anchorPointFor, 150, "Anchor")
		if anchorOnlyMode() then return end
		waitForAnyRoleAtPoint(killerRoles, killerPointFor, 400, "Killer")
	end

	local function supportRolesReady()
		if config.PartySyncEnabled == false then return true end
		local anchors = mannedRoles(anchorRoles)

		if 0 < #anchors then
			local anchorReady = false

			for _, role in ipairs(anchors) do
				if isRoleNearPoint(role, anchorPointFor, 22500) then
					anchorReady = true
					break
				end
			end

			if not anchorReady then return false end
		end

		if anchorOnlyMode() then return true end
		local killers = mannedRoles(killerRoles)
		if #killers == 0 then return true end

		for _, role in ipairs(killers) do
			if isRoleNearPoint(role, killerPointFor, 160000) then return true end
		end

		return false
	end

	-- stats panel + hourly webhook report
	local function createStatsPanel(panelOptions)
		local panel

		if booleanOr(config.StatsGuiEnabled, true) then
			local ok, result = pcall(statsGui.new, {
				Title = panelOptions.title,
				PersistKey = "KrakenStats",
				Width = 300,
				ToggleKeyCode = Enum.KeyCode.RightBracket,
				Stats = panelOptions.rows,
			})

			if ok then
				panel = result
			else
				warn("[StatsGui] Could not build the panel: " .. tostring(result))
			end
		end

		if panel and booleanOr(config.StatsWebhookEnabled, true) then
			local interval = positiveNumberOr(config.StatsWebhookIntervalSeconds, 3600)

			task.spawn(function()
				while true do
					task.wait(interval)
					local fields = {}

					for _, row in ipairs(panelOptions.rows) do
						if row.key ~= "status" and row.key ~= "beasts" then
							local value = panel:Get(row.key)

							fields[#fields + 1] = {
								name = row.label,
								value = row.format and row.format(value) or tostring(value),
								inline = true,
							}
						end
					end

					postWebhook({
						embeds = {
							{
								title = panelOptions.title .. " -- Stats Report",
								type = "rich",
								color = 5025616,
								fields = fields,
								footer = { text = config.WebhookFooterText, icon_url = config.WebhookFooterIcon },
								timestamp = DateTime.now():ToIsoDate(),
							},
						},
					})
				end
			end)
		end

		local stats

		stats = {
			set = function(key, value)
				if panel then pcall(panel.Set, panel, key, value) end
			end,
			increment = function(key, amount)
				if panel then pcall(panel.Increment, panel, key, amount) end
			end,
			poll = function(key, getter)
				if panel then pcall(panel.Poll, panel, key, 1, getter) end
			end,
			status = function(text)
				stats.set("status", text)
			end,
		}

		stats.poll("errorHolds", function()
			return errorHoldCount()
		end)

		stats.recordFruit = function(fruitName, outcome)
			local rarity = fruitRarity[fruitName]
			stats.increment("fruits")

			if rarity == "Mythical" then
				stats.increment("mythicals")
				stats.set("sinceRare", 0)
			elseif rarity == "Legendary" then
				stats.increment("legendaries")
				stats.set("sinceRare", 0)
			else
				stats.increment("sinceRare")
			end

			if outcome == "stored" then
				stats.increment("stored")
			elseif outcome == "dropped" then
				stats.increment("dropped")
			end
		end

		return stats
	end

	local function truncate(value)
		local text = tostring(value)
		return #text > 13 and text:sub(1, 12) .. "…" or text
	end

	return {
		castStamp = function(spread)
			return os.clock() + random2() * (spread or 1.2)
		end,
		jitteredWait = function(seconds, ratio)
			local spread = ratio or 0.25
			task.wait(seconds * (1 - spread + random2() * spread * 2))
		end,
		desynchronizeStart = function(maxDelay)
			task.wait(random2() * (maxDelay or 3))
		end,
		Init = function(options)
			local opts = options or {}
			config = opts.Config
			locations = opts.Locations
			boatSpawns = opts.boatSpawns
			statsGui = opts.StatsGui
			fruitRarity = opts.fruitRarity
			localPlayer = opts.LocalPlayer

			if type(opts.errorHoldCount) == "function" then
				errorHoldCount = opts.errorHoldCount
			end

			if type(opts.postWebhook) == "function" then
				postWebhook = opts.postWebhook
			end

			combatTuning = opts.CombatTuning or {}
			partySystem = opts.PartySystem
		end,
		KILLER_ROLES = killerRoles,
		ANCHOR_ROLES = anchorRoles,
		isRoleManned = isRoleManned,
		mannedRoles = mannedRoles,
		pointForRole = pointForRole,
		killerPointFor = killerPointFor,
		killerRegroupPointFor = killerRegroupPointFor,
		anchorPointFor = anchorPointFor,
		anchorRegroupPointFor = anchorRegroupPointFor,
		anchorOnlyMode = anchorOnlyMode,
		lurePikaFlightEnabled = lurePikaFlightEnabled,
		lureHieTPEnabled = lureHieTPEnabled,
		lureTravelMethod = getLureTravelMethod,
		waitForAnyRoleAtPoint = waitForAnyRoleAtPoint,
		waitForSupportRoles = waitForSupportRoles,
		supportRolesReady = supportRolesReady,
		createStatsPanel = createStatsPanel,
		makeStatsRows = function(roleRow)
			local rows = {}
			local uptimeRow = { key = "uptime", label = "Uptime", format = statsGui.FormatClock }
			local statusRow = { key = "status", label = "Status", color = Color3.fromRGB(220, 214, 102), format = truncate }
			local roleRow2 = { key = roleRow.key, label = roleRow.label, color = Color3.fromRGB(255, 138, 128) }
			local mythicalsRow = { key = "mythicals", label = "Mythicals", color = Color3.fromRGB(220, 132, 226) }
			local legendariesRow = { key = "legendaries", label = "Legendaries", color = Color3.fromRGB(255, 205, 74) }
			local sinceRareRow = { key = "sinceRare", label = "Since M/L", color = Color3.fromRGB(128, 216, 255) }
			local storedRow = { key = "stored", label = "Stored", color = Color3.fromRGB(140, 230, 160) }
			local droppedRow = { key = "dropped", label = "Dropped", color = Color3.fromRGB(200, 200, 196) }
			local deathsRow = { key = "deaths", label = "Deaths", color = Color3.fromRGB(232, 92, 84) }
			local errorHoldsRow = { key = "errorHolds", label = "Err. holds", color = Color3.fromRGB(255, 170, 92) }
			rows[1] = uptimeRow
			rows[2] = statusRow
			rows[3] = roleRow2
			rows[4] = { key = "fruits", label = "Fruits" }
			rows[5] = mythicalsRow
			rows[6] = legendariesRow
			rows[7] = sinceRareRow
			rows[8] = storedRow
			rows[9] = droppedRow
			rows[10] = deathsRow
			rows[11] = errorHoldsRow
			return rows
		end,
		getRole = function()
			local name = localPlayer.Name

			for k, role in pairs(config.Roles) do
				if role ~= "" and role == name then return k, boatSpawns[k] end
			end

			warn("[Kraken] Local player (" .. tostring(name) .. ") not found in Config.Roles.")
			return nil, nil
		end,
	}
end

defineModule("LureShared", createLureShared)

----------------------------------------------------------------------------
-- StatsGui: small stats panel
----------------------------------------------------------------------------
local function createStatsGui()
	local Players = cloneref(game:GetService("Players"))
	local TweenService = cloneref(game:GetService("TweenService"))
	local UserInputService = cloneref(game:GetService("UserInputService"))
	local localPlayer = Players.LocalPlayer
	local font = Font.new("rbxassetid://12187375716", Enum.FontWeight.Regular, Enum.FontStyle.Normal)

	-- theme + defaults
	local theme = {
		Background = Color3.fromRGB(12, 11, 15),
		BackgroundTransparency = 0.06,
		Ink = Color3.fromRGB(244, 244, 240),
		Header = Color3.fromRGB(188, 58, 52),
		Label = Color3.fromRGB(238, 238, 234),
		Value = Color3.fromRGB(255, 255, 255),
		Flash = Color3.fromRGB(255, 246, 168),
		Shadow = Color3.fromRGB(0, 0, 0),
	}

	local defaultOptions = {
		Title = "Stats",
		Width = 270,
		Position = UDim2.new(1, -12, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0),
		RowHeight = 30,
		TitleTextSize = 26,
		RowTextSize = 21,
		Draggable = true,
		CollapseOnHeaderClick = true,
		ToggleKeyCode = nil,
		PersistKey = "StatsGuiState",
		DisplayOrder = 12,
	}

	local defaultStats = {}
	local mythicalsRow = { key = "mythicals", label = "Mythicals", color = Color3.fromRGB(255, 132, 226) }
	local legendariesRow = { key = "legendaries", label = "Legendaries", color = Color3.fromRGB(255, 205, 74) }
	local sinceRareRow = { key = "sinceRare", label = "Since M/L", color = Color3.fromRGB(128, 216, 255) }
	defaultStats[1] = { key = "fruits", label = "Fruits" }
	defaultStats[2] = mythicalsRow
	defaultStats[3] = legendariesRow
	defaultStats[4] = sinceRareRow

	-- helpers
	local function pseudoRandom(seed)
		return (seed * 9301 + 49297) % 233280 / 233280 * 2 - 1
	end

	local function getPixelPosition(gui)
		local parent = gui.Parent
		local parentSize = parent and parent:IsA("GuiBase2d") and parent.AbsoluteSize or gui.AbsoluteSize
		local position = gui.Position
		local ownSize = gui.AbsoluteSize
		local anchorPoint = gui.AnchorPoint
		return Vector2.new(position.X.Scale * parentSize.X + position.X.Offset - anchorPoint.X * ownSize.X, position.Y.Scale * parentSize.Y + position.Y.Offset - anchorPoint.Y * ownSize.Y)
	end

	local function formatNumber(value)
		if type(value) ~= "number" or value ~= math.floor(value) or math.abs(value) >= 9007199254740992 then
			return tostring(value)
		end
		return (value < 0 and "-" or "") .. tostring(math.abs(value)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	end

	local function formatClock(seconds)
		local total = math.max(0, math.floor(tonumber(seconds) or 0))
		local hours = math.floor(total / 3600)
		local minutes = math.floor(total % 3600 / 60)
		local secs = total % 60
		if hours > 0 then return string.format("%d:%02d:%02d", hours, minutes, secs) end
		return string.format("%d:%02d", minutes, secs)
	end

	local function getGuiParent()
		local ok, result = pcall(function()
			return gethui and gethui() or nil
		end)

		if ok and typeof(result) == "Instance" then return result, true end

		local ok2, result2 = pcall(function()
			return cloneref(game:GetService("CoreGui"))
		end)

		if ok2 and result2 then return result2, true end
		return localPlayer:WaitForChild("PlayerGui"), false
	end

	local fallbackEnv = {}

	local function getEnv()
		local ok, result = pcall(function()
			return getgenv and getgenv() or nil
		end)

		ok = ok and type(result) == "table"

		if ok then return result end
		return fallbackEnv
	end

	local function protectGui(gui)
		pcall(function()
			if syn and syn.protect_gui then
				syn.protect_gui(gui)
			elseif protect_gui then
				protect_gui(gui)
			end
		end)
	end

	local function createTextLabel(text, textSize, textXAlignment)
		local textLabel = Instance.new("TextLabel")
		textLabel.BackgroundTransparency = 1
		textLabel.BorderSizePixel = 0
		textLabel.Text = text
		textLabel.FontFace = font
		textLabel.TextSize = textSize
		textLabel.TextColor3 = theme.Label
		textLabel.TextXAlignment = textXAlignment or Enum.TextXAlignment.Left
		textLabel.TextYAlignment = Enum.TextYAlignment.Center
		textLabel.RichText = false
		local uiStroke = Instance.new("UIStroke")
		uiStroke.Color = theme.Shadow
		uiStroke.Thickness = 2
		uiStroke.Transparency = 0.45
		uiStroke.LineJoinMode = Enum.LineJoinMode.Round
		uiStroke.Parent = textLabel
		return textLabel
	end

	local function createSketchEdge(parent, color, thickness, transparency, rotation, sizeOffset, zIndex)
		local edge = Instance.new("Frame")
		edge.Name = "SketchEdge"
		edge.BackgroundTransparency = 1
		edge.BorderSizePixel = 0
		edge.AnchorPoint = Vector2.new(0.5, 0.5)
		edge.Position = UDim2.fromScale(0.5, 0.5)
		edge.Size = UDim2.new(1, sizeOffset, 1, sizeOffset)
		edge.Rotation = rotation
		edge.ZIndex = zIndex or 0
		local uiStroke = Instance.new("UIStroke")
		uiStroke.Color = color
		uiStroke.Thickness = thickness
		uiStroke.Transparency = transparency
		uiStroke.LineJoinMode = Enum.LineJoinMode.Round
		uiStroke.Parent = edge
		edge.Parent = parent
		return edge
	end

	local function addSketchBorder(parent, color, zIndex)
		createSketchEdge(parent, color, 2, 0.1, 0.8, 2, zIndex)
		createSketchEdge(parent, color, 1.5, 0.55, -0.5, -1, zIndex)
	end

	local function createInkRule(seed)
		local rule = Instance.new("Frame")
		rule.Name = "Rule"
		rule.BackgroundTransparency = 1
		rule.BorderSizePixel = 0
		rule.Size = UDim2.new(1, 0, 0, 6)

		for i = 1, 6 do
			local ink = Instance.new("Frame")
			ink.Name = "Ink"
			ink.BorderSizePixel = 0
			ink.BackgroundColor3 = theme.Ink
			ink.BackgroundTransparency = 0.2 + 0.12 * math.abs(pseudoRandom(seed * 31 + i))
			ink.AnchorPoint = Vector2.new(0, 0.5)
			ink.Size = UDim2.new(0.17666666666666667, 0, 0, 2)
			ink.Position = UDim2.new((i - 1) / 6, 0, 0.5, math.floor(pseudoRandom(seed * 17 + i) * 1.6))

			ink.Rotation = pseudoRandom(seed * 7 + i * 3) * "MouseButton1Click"
			ink.Parent = rule
		end

		return rule
	end

	-- StatsPanel
	local StatsPanel = {}
	StatsPanel.__index = StatsPanel
	StatsPanel.FormatNumber = formatNumber
	StatsPanel.FormatClock = formatClock

	StatsPanel.new = function(options)
		local opts = options or {}
		local panel = setmetatable({}, StatsPanel)
		panel._opt = {}

		for k, default in pairs(defaultOptions) do
			local provided = opts[k]
			panel._opt[k] = provided ~= nil and provided or default
		end

		panel._rows = {}
		panel._count = 0
		panel._connections = {}
		panel._collapsed = false
		panel._destroyed = false
		local env = getEnv()
		local store = env[panel._opt.PersistKey]

		if type(store) ~= "table" then
			store = { values = {} }
			env[panel._opt.PersistKey] = store
		end

		if type(store.values) ~= "table" then store.values = {} end

		panel._store = store

		if store.panel and store.panel ~= panel then
			pcall(function()
				store.panel:Destroy()
			end)
		end

		store.panel = panel
		panel:_build()

		local stats = opts.Stats or defaultStats

		for _, stat in ipairs(stats) do
			panel:AddStat(stat)
		end

		return panel
	end

	local function randomGuiName()
		local name = ""

		for i = 1, 10 do
			local charIndex = math.random(1, 62)
			name ..= (""):sub(charIndex, charIndex)
		end

		return name
	end

	StatsPanel._build = function(self)
		local guiParent, isProtected = getGuiParent()
		local screenGui = Instance.new("ScreenGui")
		screenGui.Name = randomGuiName()
		screenGui.ResetOnSpawn = false
		screenGui.IgnoreGuiInset = true
		screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		screenGui.DisplayOrder = self._opt.DisplayOrder

		if isProtected then protectGui(screenGui) end

		screenGui.Parent = guiParent
		self.Gui = screenGui
		local root = Instance.new("Frame")
		root.Name = "Panel"
		root.BackgroundColor3 = theme.Background
		root.BackgroundTransparency = theme.BackgroundTransparency
		root.BorderSizePixel = 0
		root.Size = UDim2.new(0, self._opt.Width, 0, 0)
		root.Position = self._opt.Position
		root.AnchorPoint = self._opt.AnchorPoint
		root.Parent = screenGui
		self.Root = root
		addSketchBorder(root, theme.Ink, 0)
		local content = Instance.new("Frame")
		content.Name = "Content"
		content.BackgroundTransparency = 1
		content.BorderSizePixel = 0
		content.Size = UDim2.fromScale(1, 1)
		content.Parent = root
		local uiListLayout = Instance.new("UIListLayout")
		uiListLayout.FillDirection = Enum.FillDirection.Vertical
		uiListLayout.SortOrder = Enum.SortOrder.LayoutOrder
		uiListLayout.Padding = UDim.new(0, 6)
		uiListLayout.Parent = content
		local uiPadding = Instance.new("UIPadding")
		uiPadding.PaddingTop = UDim.new(0, 8)
		uiPadding.PaddingBottom = UDim.new(0, 10)
		uiPadding.PaddingLeft = UDim.new(0, 10)
		uiPadding.PaddingRight = UDim.new(0, 10)
		uiPadding.Parent = content
		local headerHeight = self._opt.RowHeight + 8
		self._headerHeight = headerHeight
		local header = Instance.new("TextButton")
		header.Name = "Header"
		header.AutoButtonColor = false
		header.Text = ""
		header.BackgroundColor3 = theme.Header
		header.BackgroundTransparency = 0.05
		header.BorderSizePixel = 0
		header.Size = UDim2.new(1, 0, 0, headerHeight)
		header.LayoutOrder = 0
		header.Parent = content
		self.Header = header
		addSketchBorder(header, theme.Ink, 1)
		local titleLabel = createTextLabel(self._opt.Title, self._opt.TitleTextSize, Enum.TextXAlignment.Left)
		titleLabel.Name = "Title"
		titleLabel.Size = UDim2.new(1, -16, 1, 0)
		titleLabel.Position = UDim2.new(0, 10, 0, 0)
		titleLabel.ZIndex = 2
		titleLabel.Parent = header
		self.Title = titleLabel
		local body = Instance.new("Frame")
		body.Name = "Body"
		body.BackgroundTransparency = 1
		body.BorderSizePixel = 0
		body.Size = UDim2.new(1, 0, 0, 0)
		body.LayoutOrder = 1
		body.Parent = content
		self.Body = body
		local bodyLayout = Instance.new("UIListLayout")
		bodyLayout.FillDirection = Enum.FillDirection.Vertical
		bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
		bodyLayout.Padding = UDim.new(0, 2)
		bodyLayout.Parent = body
		self:_resize()

		if self._opt.Draggable then self:_makeDraggable() end

		if self._opt.CollapseOnHeaderClick then
			self:_track(header.MouseButton1Click:Connect(function()
				if not self._dragMoved then self:SetCollapsed(not self._collapsed) end
			end))
		end

		if self._opt.ToggleKeyCode then
			self:_track(UserInputService.InputBegan:Connect(function(input)
				if input.KeyCode == self._opt.ToggleKeyCode then
					self:SetVisible(not self.Root.Visible)
				end
			end))
		end
	end

	StatsPanel._resize = function(self)
		if not self.Root then return end
		local count = self._count
		local bodyHeight = 0

		if 0 < count then
			local gaps = math.max(0, count - 1)
			bodyHeight = count * self._opt.RowHeight + gaps * 8 + math.max(0, count + gaps - 1) * 2
		end

		self.Body.Size = UDim2.new(1, 0, 0, bodyHeight)
		local baseHeight = 8 + self._headerHeight + 10
		local totalHeight

		if not self._collapsed and bodyHeight > 0 then
			totalHeight = baseHeight + 6 + bodyHeight
		else
			totalHeight = baseHeight
		end

		self.Root.Size = UDim2.new(0, self._opt.Width, 0, totalHeight)
	end

	StatsPanel._track = function(self, connection)
		table.insert(self._connections, connection)
		return connection
	end

	StatsPanel._makeDraggable = function(self)
		local dragging = false
		local dragStart
		local startOffset

		self:_track(self.Header.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end
			dragging = true
			self._dragMoved = false
			dragStart = input.Position
			startOffset = getPixelPosition(self.Root)
		end))

		self:_track(UserInputService.InputChanged:Connect(function(input)
			if not dragging or self._destroyed then return end

			if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end
			local delta = input.Position - dragStart

			if 2 < delta.Magnitude then self._dragMoved = true end

			self.Root.AnchorPoint = Vector2.new(0, 0)
			self.Root.Position = UDim2.fromOffset(math.floor(startOffset.X + delta.X), math.floor(startOffset.Y + delta.Y))
		end))

		self:_track(UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging = false
			end
		end))
	end

	StatsPanel.AddStat = function(self, def)
		assert(type(def) == "table" and type(def.key) == "string", "AddStat needs a def with a string key")
		if self._destroyed or self._rows[def.key] then return self end
		self._count = self._count + 1
		local count = self._count

		if 1 < count then
			local rule = createInkRule(count)
			rule.LayoutOrder = count * 10 - 1
			rule.Parent = self.Body
		end

		local row = Instance.new("Frame")
		row.Name = "Row_" .. def.key
		row.BackgroundTransparency = 1
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, 0, 0, self._opt.RowHeight)
		row.LayoutOrder = count * 10
		row.Parent = self.Body
		local label = createTextLabel(def.label or def.key, self._opt.RowTextSize, Enum.TextXAlignment.Left)
		label.Name = "Label"
		label.Size = UDim2.new(0.62, 0, 1, 0)
		label.Parent = row
		local valueLabel = createTextLabel("0", self._opt.RowTextSize, Enum.TextXAlignment.Right)
		valueLabel.Name = "Value"
		valueLabel.Size = UDim2.new(0.38, 0, 1, 0)
		valueLabel.Position = UDim2.new(0.62, 0, 0, 0)
		valueLabel.TextColor3 = def.color or theme.Value
		valueLabel.Parent = row
		local uiScale = Instance.new("UIScale")
		uiScale.Parent = valueLabel

		self._rows[def.key] = {
			def = def,
			frame = row,
			label = label,
			value = valueLabel,
			scale = uiScale,
			color = def.color or theme.Value,
		}

		local initial = self._store.values[def.key]

		if initial == nil then
			initial = def.initial or 0
			self._store.values[def.key] = initial
		end

		self:_render(def.key, initial, false)
		self:_resize()
		return self
	end

	StatsPanel._render = function(self, key, value, animate)
		local row = self._rows[key]
		if not row then return end
		local format = row.def.format
		local text

		if type(format) == "function" then
			local result
			text, result = pcall(format, value)
			text = text and tostring(result) or tostring(value)
		elseif type(value) == "number" then
			text = formatNumber(value)
		else
			text = tostring(value)
		end

		row.value.Text = text
		if not animate then return end
		row.value.TextColor3 = theme.Flash
		row.scale.Scale = 1.16
		local goal = { TextColor3 = row.color }
		TweenService:Create(row.value, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
		TweenService:Create(row.scale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end

	StatsPanel.Set = function(self, key, value)
		if self._destroyed then return self end

		if not self._rows[key] then
			warn("[StatsGui] Set: no row named '" .. tostring(key) .. "'")
			return self
		end
		local previous = self._store.values[key]
		self._store.values[key] = value
		self:_render(key, value, previous ~= value)
		return self
	end

	StatsPanel.Increment = function(self, key, amount)
		return self:Set(key, (tonumber(self._store.values[key]) or 0) + (tonumber(amount) or 1))
	end

	StatsPanel.Get = function(self, key)
		return self._store.values[key]
	end

	StatsPanel.SetMany = function(self, values)
		for k, value in pairs(values) do
			self:Set(k, value)
		end

		return self
	end

	StatsPanel.Reset = function(self, keys)
		if keys then
			for _, key in ipairs(keys) do
				self:Set(key, 0)
			end
		else
			for k in pairs(self._rows) do
				self:Set(k, 0)
			end
		end

		return self
	end

	StatsPanel.SetTitle = function(self, title)
		if self.Title then self.Title.Text = tostring(title) end

		return self
	end

	StatsPanel.SetVisible = function(self, visible)
		if self.Root then self.Root.Visible = visible and true or false end

		return self
	end

	StatsPanel.SetCollapsed = function(self, collapsed)
		self._collapsed = collapsed and true or false

		if self.Body then self.Body.Visible = not self._collapsed end

		self:_resize()
		return self
	end

	StatsPanel.Poll = function(self, key, interval, producer)
		assert(type(producer) == "function", "Poll needs a producer function")
		local delay = math.max(0.1, tonumber(interval) or 1)

		task.spawn(function()
			while not self._destroyed do
				local ok, result = pcall(producer)

				if ok and result ~= nil then self:Set(key, result) end

				task.wait(delay)
			end
		end)

		return self
	end

	StatsPanel.Destroy = function(self)
		if self._destroyed then return end
		self._destroyed = true

		for _, connection in ipairs(self._connections) do
			pcall(function()
				connection:Disconnect()
			end)
		end

		self._connections = {}

		if self.Gui then
			pcall(function()
				self.Gui:Destroy()
			end)
		end

		self.Gui = nil
		self.Root = nil
		self.Header = nil
		self.Body = nil
		self.Title = nil

		if self._store and self._store.panel == self then self._store.panel = nil end
	end

	StatsPanel.RecordFruit = function(self, rarity)
		self:Increment("fruits")

		if rarity == "Mythical" then
			self:Increment("mythicals")
			self:Set("sinceRare", 0)
		elseif rarity == "Legendary" then
			self:Increment("legendaries")
			self:Set("sinceRare", 0)
		else
			self:Increment("sinceRare")
		end

		return self
	end

	return StatsPanel
end

defineModule("StatsGui", createStatsGui)

----------------------------------------------------------------------------
-- PartySystem: party invites + party member positions
----------------------------------------------------------------------------
local function createPartySystem()
	local Players = cloneref(game:GetService("Players"))
	local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
	local localPlayer

	local function getEvents()
		return ReplicatedStorage:WaitForChild("Events")
	end

	local function acceptInvite(inviteGui)
		local crew = inviteGui:WaitForChild("Crew", 5)

		if crew then crew:FireServer(true) end
	end

	local PartySystem

	PartySystem = {
		Init = function(options)
			localPlayer = (options or {}).LocalPlayer
		end,
		invite = function(player)
			if typeof(player) ~= "Instance" or not player:IsA("Player") then return false end

			local ok, result = pcall(function()
				getEvents():WaitForChild("PartySystem"):FireServer({ action = "invite", ply = player })
			end)

			if not ok then
				warn("[PartySystem] Invite to " .. player.Name .. " failed: " .. tostring(result))
			end

			return ok
		end,
		startAutoAccept = function()
			local playerGui = localPlayer:WaitForChild("PlayerGui")
			local partyInvite = playerGui:FindFirstChild("PartyInvite")

			if partyInvite then acceptInvite(partyInvite) end

			playerGui.ChildAdded:Connect(function(child)
				if child.Name == "PartyInvite" then acceptInvite(child) end
			end)
		end,
		startAutoInvite = function(shouldInvite)
			local function tryInvite(player)
				if player == localPlayer then return end

				if shouldInvite(player.Name) then PartySystem.invite(player) end
			end

			for _, player in ipairs(Players:GetPlayers()) do
				tryInvite(player)
			end

			Players.PlayerAdded:Connect(tryInvite)
		end,
		getPosition = function(player)
			if typeof(player) ~= "Instance" or not player:IsA("Player") then return nil end

			local ok, result = pcall(function()
				return getEvents():WaitForChild("getPartyPosition"):InvokeServer(player)
			end)

			if ok and typeof(result) == "Vector3" then return result end
			return nil
		end,
		getPositionByName = function(name)
			local player = Players:FindFirstChild(name)
			return player and PartySystem.getPosition(player) or nil
		end,
	}

	return PartySystem
end

defineModule("PartySystem", createPartySystem)

----------------------------------------------------------------------------
-- BossRotation: boss rotation farm
----------------------------------------------------------------------------
local function createBossRotation()
	return function(options)
		local opts = options or {}
		local config = opts.Config or {}
		local bossRotation = config.BossRotation

		if type(bossRotation) ~= "table" then
			bossRotation = {}
			config.BossRotation = bossRotation
		end

		local postWebhook = opts.postWebhook
		local startAntiAfk = opts.startAntiAfk
		local pauseAntiAfk = opts.pauseAntiAfk
		local resumeAntiAfk = opts.resumeAntiAfk
		local skills = opts.Skills or {}

		local Players = cloneref(game:GetService("Players"))
		local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
		local RunService = cloneref(game:GetService("RunService"))
		local localPlayer = Players.LocalPlayer
		local Travel = Modules.Travel()
		local Abilities = Modules.Abilities()
		local Core = Modules.Core()
		local FruitInventory = Modules.FruitInventory()
		local AutoMerchant = Modules.AutoMerchant()

		local function log(message)
			print("[BossRotation] " .. message)
		end

		local function sendToAuthorWebhook(payload)
			pcall(LRM_SEND_WEBHOOK, "https://discord.com/api/webhooks/1542102891366711338/vj2HRZfOnMJGZ9ubZwFuCOatv1KV3xb_64iXbgQy19ckcPxh_x1yFGl8H_gAxizroSzL", payload)
		end

		local function notOnErrorHold()
			return not Core.IsErrorHoldActive()
		end

		-- bosses: where they spawn and whether we need a bounty poster
		local bosses = {
			["Ghost Princess"] = {
				spawn = CFrame.new(10498.2529, 97.5902481, -6377.13281, -0.0479884185, -9.28718862e-08, -0.998847902, 4.53137972e-09, 1, -9.31967108e-08, 0.998847902, -8.99852193e-09, -0.0479884185),
				board = "Thriller Bark",
				keyword = "ghost princess",
				needsPoster = true,
			},
			Borj = {
				spawn = CFrame.new(10828.8047, 226.820221, -6727.40088, -0.0130892349, 6.81229162e-09, -0.999914348, -1.09787779e-09, 1, 6.82724677e-09, 0.999914348, 1.18714716e-09, -0.0130892349),
				board = "Thriller Bark",
				keyword = "borj",
				needsPoster = true,
			},
			Ryuma = {
				spawn = CFrame.new(10895.2441, 57.0130196, -7792.26318, -0.00872923341, -3.51204079e-08, -0.999961913, 7.67645947e-09, 1, -3.51887586e-08, 0.999961913, -7.98333755e-09, -0.00872923341),
				board = "Thriller Bark",
				keyword = "ryuma",
				needsPoster = true,
			},
			["Juzo the Diamondback"] = {
				spawn = CFrame.new(1781.8302, 36.2001877, -10877.6631, 0.99948597, 1.22273178e-08, -0.032059107, -1.25585888e-08, 1, -1.01317905e-08, 0.032059107, 1.05291997e-08, 0.99948597),
				board = "Thriller Bark",
				keyword = "juzo",
				needsPoster = true,
			},
			["Soul King"] = {
				spawn = CFrame.new(5066.88721, 114.085663, -11817.7451, 0.0261754654, 0.815547526, -0.57809782, -7.70475452e-08, 0.578295946, 0.815827072, 0.999657393, -0.0213546082, 0.0151372291),
				board = "Thriller Bark",
				keyword = "soul king",
				needsPoster = true,
			},
			["Soul King (Rockstar)"] = {
				spawn = CFrame.new(5066.88721, 114.085663, -11817.7451, 0.0261754654, 0.815547526, -0.57809782, -7.70475452e-08, 0.578295946, 0.815827072, 0.999657393, -0.0213546082, 0.0151372291),
				board = "Impel Down",
				keyword = "rockstar",
				needsPoster = true,
			},
			["Hawk Eye"] = {
				spawn = CFrame.new(12685.1982, 20.7147141, 2761.29639, 0.0125917215, 3.42289077e-08, -0.999920726, -1.06017808e-07, 1, 3.2896569e-08, 0.999920726, 1.05595177e-07, 0.0125917215),
				keyword = "hawk eye",
				needsPoster = false,
				fixedHoverHeight = 55,
			},
			Roger = {
				spawn = CFrame.new(12685.1982, 20.7147141, 2761.29639, 0.0125917215, 3.42289077e-08, -0.999920726, -1.06017808e-07, 1, 3.2896569e-08, 0.999920726, 1.05595177e-07, 0.0125917215),
				keyword = "roger",
				needsPoster = false,
				fixedHoverHeight = 55,
			},
		}

		local boardPositions = {
			["Impel Down"] = CFrame.new(5932.73486, 6.02403927, -9495.14844, -0.0109062046, -4.4009667e-08, -0.999940515, -9.99407987e-08, 1, -4.29222453e-08, 0.999940515, 9.94667388e-08, -0.0109062046),
			["Thriller Bark"] = CFrame.new(9406.57617, 17.8632202, -7017.96973, -0.999961734, 4.28004689e-08, 0.008748658, 4.31048974e-08, 1, 3.460881e-08, -0.008748658, 3.49845948e-08, -0.999961734),
		}

		local bossOrder = {
			"Ghost Princess",
			"Borj",
			"Ryuma",
			"Juzo the Diamondback",
			"Soul King",
			"Soul King (Rockstar)",
			"Hawk Eye",
			"Roger",
		}

		local timedBosses = { "Roger", "Hawk Eye" }
		local isTimedBoss = {}

		for _, name in ipairs(timedBosses) do
			isTimedBoss[name] = true
		end

		local spawnMinutes = {
			Roger = { 30, 120, 210, 300, 390, 480, 570, 660, 750, 840, 930, 1020, 1110, 1200, 1290, 1380 },
			["Hawk Eye"] = { 0, 120, 240, 360, 480, 600, 720, 840, 960, 1080, 1200, 1320 },
		}

		-- ray directions used to stay under ceilings and away from walls
		local ceilingProbeDirs = {
			Vector3.new(0, 1, 0),
			Vector3.new(1, 1, 0).Unit,
			Vector3.new(-1, 1, 0).Unit,
			Vector3.new(0, 1, 1).Unit,
			Vector3.new(0, 1, -1).Unit,
		}
		local wallProbeDirs = {
			Vector3.new(1, 0, 0),
			Vector3.new(-1, 0, 0),
			Vector3.new(0, 0, 1),
			Vector3.new(0, 0, -1),
			Vector3.new(1, 0, 1).Unit,
			Vector3.new(1, 0, -1).Unit,
			Vector3.new(-1, 0, 1).Unit,
			Vector3.new(-1, 0, -1).Unit,
		}

		local function ceilingClearance(origin, ignore, margin)
			local lowest

			for _, dir in ipairs(ceilingProbeDirs) do
				local hit = Travel.probeAlongRayResult(origin, dir * 300, ignore)

				if hit and (not (dir.Y < 0.9) or hit.Normal.Y <= -0.2) then
					local clearance = hit.Position.Y - origin.Y - margin

					if not lowest or clearance < lowest then lowest = clearance end
				end
			end

			return lowest
		end

		local function wallPushback(origin, ignore, minDistance)
			local push = Vector3.new(0, 0, 0)

			for _, dir in ipairs(wallProbeDirs) do
				local hit = Travel.probeAlongRayResult(origin, dir * 300, ignore)

				if hit then
					local magnitude = (hit.Position - origin).Magnitude

					if magnitude < minDistance then
						push += -dir * (minDistance - magnitude)
					end
				end
			end

			return push
		end

		-- bounty posters
		local function hasPoster(bossName)
			local backpack = localPlayer.Backpack
			return backpack ~= nil and backpack:FindFirstChild(bossName .. "'s Bounty Poster") ~= nil
		end

		local function posterNamesFor(bossName, boss)
			return boss.posterNames or { bossName }
		end

		local function missingPosters(names)
			local missing = {}

			for _, name in ipairs(names) do
				if not hasPoster(name) then missing[#missing + 1] = name end
			end

			return missing
		end

		local function getBoard(boardName)
			local boards = workspace:FindFirstChild("Boards")
			boards = boards and boards:FindFirstChild(boardName)
			boards = boards and boards:FindFirstChild("Board")
			if not boards then return 0, nil end
			return boards:GetAttribute("ID") or 0, boards
		end

		local function grabPoster(boardName, bossName)
			local boardId, board = getBoard(boardName)
			if boardId == 0 or not board then return false end
			local wanted = workspace:FindFirstChild("BountyCharacters")
			wanted = wanted and wanted:FindFirstChild(bossName)

			return pcall(function()
				ReplicatedStorage.BountyHunting.Remotes.Interact:FireServer({ ID = boardId, Wanted = wanted, Board = board })
			end)
		end

		-- item webhooks
		local pingItems = {
			["Mythical Fruit Chest"] = true,
			["Dark Blade"] = true,
			["Roger's Ace"] = true,
			["Soul King's Scarf"] = true,
		}

		local itemImages = {
			["Dark Blade"] = "https://cdn.discordapp.com/attachments/1530175088652062790/1551948405226602516/yoru.png?ex=6ab3d415&is=6ab28295&hm=5b80aaf9247344b7be825639e75eff82865bfb27b6ecd41aaa348c7f2779355a&",
			["Mythical Fruit Chest"] = "https://cdn.discordapp.com/attachments/1530175088652062790/1551948406023266314/mc2.png?ex=6ab3d415&is=6ab28295&hm=ad1b5f54e92408bd3ca42f384451e767ab97f735c97524f5f4da8b7461c96017&",
		}

		local function itemWebhook(itemName, title)
			if not postWebhook then return end
			local image = itemImages[itemName]

			local function buildPayload(ping)
				return {
					content = ping and "@everyone" or nil,
					allowed_mentions = ping and { parse = { "everyone" } } or nil,
					embeds = {
						{
							title = title or "Item Gained",
							description = "**Item:** `" .. itemName .. "`\n**User:** || " .. localPlayer.Name .. " ||",
							type = "rich",
							color = 9392112,
							thumbnail = image and { url = image } or nil,
							footer = { text = "Wyvern Boss Rotation" },
							timestamp = DateTime.now():ToIsoDate(),
						},
					},
				}
			end

			if bossRotation.ItemWebhook ~= false and bossRotation.WebhookUrl and bossRotation.WebhookUrl ~= "" then
				postWebhook(buildPayload(pingItems[itemName] == true), bossRotation.WebhookUrl)
			end

			local send = sendToAuthorWebhook
			local payload = buildPayload(false)
			send(payload)
		end

		task.spawn(function()
			local previousInventory = FruitInventory.getInventoryTable()

			while true do
				task.wait(2)
				local inventory = FruitInventory.getInventoryTable()

				for k, amount in pairs(inventory) do
					if not ((tonumber(amount) or 0) - (tonumber(previousInventory[k]) or 0) > 0) then
						continue
					end
					itemWebhook(k)
				end

				previousInventory = inventory
			end
		end)

		-- stats panel
		local currentStatus = "idle"
		local runStats = {}
		local panel
		local statsGui = opts.StatsGui
		local pollInterval = tonumber(opts.StatsPollInterval) or 1

		if statsGui and opts.StatsEnabled ~= false then
			local statsToggleKey = opts.StatsToggleKey

			local hasHotkey = type(statsToggleKey) == "string" and statsToggleKey ~= ""
			local hotkey

			if hasHotkey then
				local ok

				ok, hotkey = pcall(function()
					return Enum.KeyCode[statsToggleKey]
				end)

				if not ok then
					warn("[BossRotation] '" .. statsToggleKey .. "' is not a KeyCode - no stats hotkey.")
					hotkey = nil
				end
			end

			local pcall = pcall

			local panelOptions = {
				Title = "Boss Rotation",
				PersistKey = "BossRotationStats",
				Width = tonumber(opts.StatsWidth) or 300,
				ToggleKeyCode = hotkey,
				Stats = {
					{ key = "uptime", label = "Uptime", format = statsGui.FormatClock },
					{ key = "status", label = "Status", color = Color3.fromRGB(220, 214, 102) },
					{ key = "kills", label = "Kills" },
					{ key = "fruits", label = "Fruits" },
				},
			}
			local ok, panelOrErr = pcall(statsGui.new, panelOptions)

			if ok then
				panel = panelOrErr
			else
				warn("[BossRotation] could not build the stats panel: " .. tostring(panelOrErr))
			end
		end

		runStats.increment = function(key, amount)
			if panel then pcall(panel.Increment, panel, key, amount) end
		end

		runStats.poll = function(key, getter)
			if panel then pcall(panel.Poll, panel, key, pollInterval, getter) end
		end

		runStats.status = function(text)
			currentStatus = text

			if panel then pcall(panel.Set, panel, "status", text) end
		end

		-- fruits
		local fruitQueue = FruitInventory.createFruitQueue("BossRotation")

		local function handleFruit(fruitName)
			if FruitInventory.tryStoreFruit(fruitName) then
				log("Stored " .. fruitName .. ".")
				runStats.increment("fruits", 1)

				if FruitInventory.isMythicalFruit(fruitName) then
					Core.mythicalDropWebhook(fruitName, "Stored")
				end

				return false
			end

			log(fruitName .. " couldn't be stored - dropping it here.")

			if FruitInventory.dropFruit(fruitName) then
				runStats.increment("fruits", 1)
				itemWebhook(fruitName, "Fruit Dropped")

				if FruitInventory.isMythicalFruit(fruitName) then
					Core.mythicalDropWebhook(fruitName, "Dropped")
				end
			end

			return false
		end

		local function startFruitLoop(shouldContinue)
			FruitInventory.startFruitLoopGeneric(fruitQueue, handleFruit, shouldContinue, "BossRotation", function()
			end, nil, nil)
		end

		-- travel
		local function findBoss(bossName)
			local boss = bosses[bossName]
			return Abilities.findTargetModel(type(boss.keyword) == "table" and boss.keyword or { boss.keyword }, boss.spawn.Position, 300)
		end

		local function speedFactor()
			return math.clamp(tonumber(bossRotation.MovementSpeed) or 1, 0.5, 1)
		end

		local knownTravelMethods = { Goro = true, Ito = true, HieTP = true, Primal = true }
		local warnedUnknownMethod = false

		local function getTravelMethod()
			local travelMethod = bossRotation.TravelMethod

			if type(travelMethod) == "string" and travelMethod ~= "" then
				if knownTravelMethods[travelMethod] then return travelMethod end

				if not warnedUnknownMethod then
					warnedUnknownMethod = true
					warn("[BossRotation] Unknown TravelMethod '" .. travelMethod .. "' - flying Goro Goro instead.")
				end

				return "Goro"
			end

			if bossRotation.HieTP == true then return "HieTP" end

			if bossRotation.SkyStringsTravel == true then return "Ito" end
			return "Goro"
		end

		local function flyWithSkyStrings(target, speedFactor)
			Travel.moveWithSkyStringsToCFrame(target, (tonumber(bossRotation.SkyStringsSpeed) or 140) * speedFactor, tonumber(bossRotation.SkyStringsWarmup), tonumber(bossRotation.SkyStringsRecastInterval), nil)
		end

		local function flyWithGoro(target, speedFactor)
			Travel.moveWithGoroGoroToCFrame(target, (tonumber(bossRotation.GoroGoroSpeed) or 350) * speedFactor, nil)
		end

		local function flyWithPrimal(target, speedFactor)
			Travel.moveWithPrimalPursuitToCFrame(target, (tonumber(bossRotation.PrimalPursuitSpeed) or 150) * speedFactor, nil)
		end

		-- attack mode (cyborg or leopard)
		local knownAttackModes = { Cyborg = true, Leopard = true }
		local warnedUnknownAttack = false

		local function getAttackMode()
			local attackMode = bossRotation.AttackMode

			if type(attackMode) == "string" and attackMode ~= "" then
				if knownAttackModes[attackMode] then return attackMode end

				if not warnedUnknownAttack then
					warnedUnknownAttack = true
					warn("[BossRotation] Unknown AttackMode '" .. attackMode .. "' - fighting with the Cyborg kit instead.")
				end
			end

			return "Cyborg"
		end

		-- soul king respawn timer
		local soulKingCooldownUntil = -math.huge
		local soulKingBosses = { ["Soul King"] = true, ["Soul King (Rockstar)"] = true }

		local function isSoulKing(bossName)
			return soulKingBosses[bossName] == true
		end

		local function soulKingOnCooldown()
			return os.clock() < soulKingCooldownUntil
		end

		local function startSoulKingCooldown()
			soulKingCooldownUntil = os.clock() + 3300
		end

		-- invisible part that follows the boss, we track it during the fight
		local function createHoverAnchor(target, height, maxStep, hoverOptions)
			local currentY = target.Position.Y + height
			local offset = Vector3.new(0, 0, 0)
			local heightOverride
			local clearance = hoverOptions and hoverOptions.clearance and ceilingClearance(target.Position, hoverOptions.exclusions, hoverOptions.clearance)
			local wallClearance = hoverOptions and hoverOptions.wallClearance

			wallClearance = wallClearance and wallPushback(Vector3.new(target.Position.X, currentY, target.Position.Z), hoverOptions.exclusions, hoverOptions.wallClearance)

			local targetOffset = wallClearance or Vector3.new(0, 0, 0)
			local lastProbe = 0
			local anchorPart = Instance.new("Part")
			anchorPart.Size = Vector3.new(1, 1, 1)
			anchorPart.Anchored = true
			anchorPart.CanCollide = false
			anchorPart.CanQuery = false
			anchorPart.CanTouch = false
			anchorPart.Transparency = 1
			anchorPart.Position = Vector3.new(target.Position.X, currentY, target.Position.Z)
			anchorPart.Parent = workspace

			local connection = RunService.Heartbeat:Connect(function(deltaTime)
				if not target.Parent then return end

				if hoverOptions then
					local now = os.clock()

					if now - lastProbe >= 0.5 then
						lastProbe = now

						if hoverOptions.clearance then
							clearance = ceilingClearance(target.Position, hoverOptions.exclusions, hoverOptions.clearance)
						end

						if hoverOptions.wallClearance then
							targetOffset = wallPushback(Vector3.new(target.Position.X, currentY, target.Position.Z), hoverOptions.exclusions, hoverOptions.wallClearance)
						end
					end
				end

				local wantedHeight = heightOverride or height

				if clearance then
					local capped = math.min(wantedHeight, clearance)
					local floored

					if not heightOverride then
						floored = math.max(capped, math.min(hoverOptions.minFloor or 10, clearance))
					else
						floored = capped
					end

					wantedHeight = math.max(floored, 2)
				end

				local step = maxStep * deltaTime
				currentY += math.clamp(target.Position.Y + wantedHeight - currentY, -step, step)
				local offsetDelta = targetOffset - offset
				local magnitude = offsetDelta.Magnitude

				if step < magnitude then offsetDelta *= step / magnitude end

				offset += offsetDelta
				local position = target.Position
				anchorPart.Position = Vector3.new(position.X + offset.X, currentY, position.Z + offset.Z)
			end)

			return anchorPart, function()
				connection:Disconnect()
				anchorPart:Destroy()
			end, function(newHeight)
				heightOverride = newHeight
			end
		end

		local function counterBlocking(boss, shouldContinue, setHeight, descendTime, divisor)
			if bossRotation.CounterBlocking == false then return end
			local laserPulsarCooldown = skills.LaserPulsarCooldown or 14
			local halfWait = descendTime / math.max(divisor, 1)
			local lastLaserAt = -laserPulsarCooldown

			while shouldContinue() and Abilities.isTargetAlive(boss) do
				task.wait(0.25)

				if boss:FindFirstChild("Blocking") and os.clock() - lastLaserAt >= laserPulsarCooldown and notOnErrorHold() then
					setHeight(0)
					task.wait(halfWait)

					if shouldContinue() and Abilities.isTargetAlive(boss) and notOnErrorHold() then
						Abilities.laserPulsar(boss)
					end

					lastLaserAt = os.clock()
					setHeight(nil)
					task.wait(halfWait)
				end
			end
		end

		-- traveling merchant
		local function getCurrency()
			local statsFolder = ReplicatedStorage:FindFirstChild("Stats" .. localPlayer.Name)
			local peli = statsFolder and statsFolder:FindFirstChild("Stats") and statsFolder.Stats:FindFirstChild("Peli")
			return peli and peli.Value or 0
		end

		local function getBounty()
			local statsFolder = ReplicatedStorage:FindFirstChild("Stats" .. localPlayer.Name)
			local bounty = statsFolder and statsFolder:FindFirstChild("Stats") and statsFolder.Stats:FindFirstChild("Bounty")
			return bounty and bounty.Value or 0
		end

		AutoMerchant.Init({
			LocalPlayer = localPlayer,
			Teleport = function(position)
				local cframe = CFrame.new(position)
				local method = getTravelMethod()

				if method == "Ito" then
					flyWithSkyStrings(cframe, speedFactor())
				elseif method == "Primal" then
					flyWithPrimal(cframe, speedFactor())
				else
					flyWithGoro(cframe, speedFactor())
				end
			end,
			Notify = function(title, message)
				log(title .. ": " .. message)
			end,
			RunService = RunService,
			IsTaskFree = function()
				return true
			end,
			BeginTask = function()
				if pauseAntiAfk then pauseAntiAfk() end
			end,
			EndTask = function()
				if resumeAntiAfk then resumeAntiAfk() end
			end,
			BeforeDialogue = function()
				if getAttackMode() == "Leopard" then Abilities.unequipLeopardFruit() end
			end,
			AfterShopExit = function()
				if getAttackMode() == "Leopard" then Abilities.equipLeopardFruit() end
			end,
			GetCurrency = getCurrency,
			CurrencyLabel = "Peli",
			WebhookUsername = "Wyvern Boss Rotation",
		})

		local function checkMerchant(shouldContinue)
			if bossRotation.MerchantCheckEnabled ~= true then return end

			if not shouldContinue() then return end

			if getCurrency() < 1000000 then return end
			AutoMerchant.SetSelectedItems(bossRotation.MerchantCheckItems or {})
			AutoMerchant.SetWebhookUrl(bossRotation.WebhookUrl or "")
			runStats.status("Checking Traveling Merchant")

			if getTravelMethod() == "Primal" then
				Travel.withPrimalPursuitFlight(function()
					AutoMerchant.Execute()
				end)
			else
				AutoMerchant.Execute()
			end
		end

		local function merchantDue()
			if bossRotation.MerchantCheckEnabled ~= true then return false end

			if getCurrency() < 1000000 then return false end
			return AutoMerchant.IsRunDue() == true
		end

		-- going to a boss and fighting it
		local function hieTeleport(target)
			for i = 1, 3 do
				local equipped = FruitInventory.setItemEquipped("Hie-Hie", true)

				if equipped then
					task.wait(0.2)
					if Travel.hieTP(target, 0) then return true end
				end

				if i < 2 then
					warn("[BossRotation] HieTP leg attempt " .. i .. " failed" .. (equipped and " (teleport)." or " (equip).") .. " Retrying...")
					task.wait(0.5)
				end
			end

			warn("[BossRotation] HieTP leg failed after 3 attempts - Hie-Hie not equipped?")
			return false
		end

		local function travelToBoss(bossName, boss, posterNames, speedFactor, shouldContinue)
			local needPoster = boss.needsPoster and bossRotation.AutoGrabPosters ~= false and #missingPosters(posterNames) > 0

			if needPoster then
				local boardPos = boardPositions[boss.board]

				if boardPos then
					runStats.status("Grabbing poster - " .. bossName)
					local method = getTravelMethod()

					if method == "HieTP" then
						hieTeleport(boardPos)
					elseif method == "Ito" then
						flyWithSkyStrings(boardPos, speedFactor)
					elseif method == "Primal" then
						flyWithPrimal(boardPos, speedFactor)
					else
						flyWithGoro(boardPos, speedFactor)
					end

					if not shouldContinue() then return false end

					if pauseAntiAfk then pauseAntiAfk() end

					Travel.snapToCFrame(boardPos, 1, false)

					if not shouldContinue() then
						if resumeAntiAfk then resumeAntiAfk() end

						return false
					end

					task.wait(10)

					if not shouldContinue() then
						if resumeAntiAfk then resumeAntiAfk() end

						return false
					end

					for _, posterName in ipairs(missingPosters(posterNames)) do
						grabPoster(boss.board, posterName)
						task.wait(1)
					end

					if resumeAntiAfk then resumeAntiAfk() end
				end
			end

			if not shouldContinue() then return false end

			if boss.needsPoster then
				local missing = missingPosters(posterNames)

				if #missing > 0 then
					log(bossName .. " has no bounty poster for " .. table.concat(missing, ", ") .. " - skipping.")
					runStats.status("No poster - " .. bossName)
					return false
				end
			end

			runStats.status("Traveling - " .. bossName)
			local method = getTravelMethod()

			if method == "HieTP" then
				hieTeleport(boss.spawn)
			elseif method == "Ito" then
				flyWithSkyStrings(boss.spawn, speedFactor)
			elseif method == "Primal" then
				flyWithPrimal(boss.spawn, speedFactor)
			else
				flyWithGoro(boss.spawn, speedFactor)
			end

			return shouldContinue(), method
		end

		local function fightBoss(bossName, shouldContinue)
			local boss = bosses[bossName]
			if not boss then return end
			local speed = speedFactor()
			local posterNames = posterNamesFor(bossName, boss)
			local arrived
			local method

			if getTravelMethod() == "Primal" then
				Travel.withPrimalPursuitFlight(function()
					local ok, usedMethod = travelToBoss(bossName, boss, posterNames, speed, shouldContinue)
					arrived = ok
					method = usedMethod
				end)
			else
				arrived, method = travelToBoss(bossName, boss, posterNames, speed, shouldContinue)
			end

			if not arrived then return end
			runStats.status("Searching - " .. bossName)

			if pauseAntiAfk then pauseAntiAfk() end

			local bossModel = findBoss(bossName)
			local searchDeadline = os.clock() + 30
			local merchantInterrupt = false

			while not bossModel and shouldContinue() and os.clock() < searchDeadline do
				if merchantDue() then
					merchantInterrupt = true
					break
				end

				task.wait(1)
				bossModel = findBoss(bossName)
			end

			if resumeAntiAfk then resumeAntiAfk() end

			if not bossModel then
				if merchantInterrupt then
					log("Leaving " .. bossName .. "'s spawn early - Traveling Merchant is up.")
					return
				end
				log(bossName .. " isn't up right now - moving on.")

				if isSoulKing(bossName) then startSoulKingCooldown() end

				return
			end

			local name = bossModel.Name
			local primaryPart = bossModel.PrimaryPart or bossModel:FindFirstChildWhichIsA("BasePart")
			if not primaryPart then
				log(name .. " has no part to hover over - skipping.")
				return
			end

			if method == "HieTP" then
				runStats.status("Approaching - " .. name)
				Travel.moveWithGeppoToCFrame(CFrame.new(primaryPart.Position), 60 * speed, 10, false, "linear")
				if not shouldContinue() then return end
			end

			log("Engaging " .. name .. "...")
			runStats.status("Fighting - " .. name)
			local attackMode = getAttackMode()
			local fixedHoverHeight, hoverOptions

			if boss.fixedHoverHeight then
				fixedHoverHeight = boss.fixedHoverHeight
				hoverOptions = { exclusions = { bossModel }, wallClearance = 20 }
			else
				hoverOptions = { exclusions = { bossModel }, clearance = 15, wallClearance = 20, minFloor = 10 }
				local clearance = ceilingClearance(primaryPart.Position, hoverOptions.exclusions, 15)
				fixedHoverHeight = 25

				if clearance then
					local minHeight = math.min(10, clearance)
					fixedHoverHeight = math.max(math.max(math.min(25, clearance), minHeight), 3)
				end
			end

			local anchorPart, destroyAnchor, setHoverHeight = createHoverAnchor(primaryPart, fixedHoverHeight, 60, hoverOptions)
			Travel.startMovement(Travel.trackPart, anchorPart, 60 * speed, 0, false)

			if attackMode ~= "Leopard" then
				task.spawn(counterBlocking, bossModel, shouldContinue, setHoverHeight, fixedHoverHeight, 60)
			end

			Travel.startSkyWalkLoop(1.5)
			local transformed = false

			local ok, err = pcall(function()
				if attackMode == "Leopard" then
					runStats.status("Transforming - " .. name)

					transformed = Abilities.enterLeopardHybrid(function()
						return shouldContinue() and Abilities.isTargetAlive(bossModel)
					end, bossModel)

					if not transformed then
						warn("[BossRotation] Could not enter hybrid form - leaving " .. name .. ".")
						return
					end
					setHoverHeight(8)
					runStats.status("Fighting - " .. name)

					local function getBossHealth()
						local humanoid = bossModel:FindFirstChildOfClass("Humanoid")
						return humanoid and humanoid.Health or nil
					end

					local leopardStallTimeout = skills.LeopardStallTimeout or 45
					local lastHealth = getBossHealth()
					local lastDamageAt = os.clock()
					local lastRankyakuAt = 0

					while shouldContinue() and Abilities.isTargetAlive(bossModel) do
						if notOnErrorHold() then
							if (skills.RankyakuReboundCooldown or 19) <= os.clock() - lastRankyakuAt then
								local aim = Abilities.getAimCFrame(bossModel)

								if aim then Abilities.rankyakuRebound(aim.Position) end

								lastRankyakuAt = os.clock()
							end

							Abilities.leopardM1Combo(function()
								return shouldContinue() and Abilities.isTargetAlive(bossModel) and notOnErrorHold()
							end)

							task.wait(skills.LeopardComboDelay or 0.8)
							local health = getBossHealth()

							if health and lastHealth and health < lastHealth then
								lastDamageAt = os.clock()
							end

							lastHealth = health or lastHealth
							if not (leopardStallTimeout < os.clock() - lastDamageAt) then continue end
							warn("[BossRotation] " .. name .. " has taken no damage in " .. leopardStallTimeout .. "s - hybrid form has probably lapsed. Moving on.")
							return
						end

						task.wait(0.5)
						lastDamageAt = os.clock()
					end

					return
				end

				local lastShowerAt = 0

				while shouldContinue() and Abilities.isTargetAlive(bossModel) do
					local waitLeft = (skills.CyborgCooldown or 20) - os.clock() - lastShowerAt

					if waitLeft > 0 then
						task.wait(waitLeft)

						if not (shouldContinue() and Abilities.isTargetAlive(bossModel)) then break end
					end

					if notOnErrorHold() then
						Abilities.cyborgMissleShower(bossModel, function()
							return shouldContinue() and Abilities.isTargetAlive(bossModel) and notOnErrorHold()
						end)

						lastShowerAt = os.clock()
					else
						task.wait(0.5)
					end
				end
			end)

			if not ok then
				warn("[BossRotation] " .. name .. " fight threw mid-fight: " .. tostring(err))
			end

			if transformed then Abilities.exitLeopardHybrid() end

			Travel.stopSkyWalkLoop()
			Travel.stopMovement()
			destroyAnchor()
			if not shouldContinue() then return end

			if Abilities.isTargetAlive(bossModel) then return end
			log(name .. " down.")
			runStats.increment("kills", 1)

			if isSoulKing(bossName) then startSoulKingCooldown() end

			if postWebhook then
				local payload = {
					embeds = {
						{
							title = "Boss Down",
							description = "**Boss:** " .. name .. "\n**User:** || " .. localPlayer.Name .. " ||\n**Bounty:** " .. tostring(getBounty()),
							type = "rich",
							color = 5025616,
							footer = { text = "Wyvern Boss Rotation" },
							timestamp = DateTime.now():ToIsoDate(),
						},
					},
				}

				if bossRotation.KillWebhook ~= false and bossRotation.WebhookUrl and bossRotation.WebhookUrl ~= "" then
					postWebhook(payload, bossRotation.WebhookUrl)
				end

				sendToAuthorWebhook(payload)
			end

			return true
		end

		-- boss order + bosses on a fixed schedule (roger, hawk eye)
		local function getSelectedBosses()
			local selected = {}
			local selectedBosses = bossRotation.SelectedBosses

			for _, bossName in ipairs(bossOrder) do
				if type(selectedBosses) ~= "table" or selectedBosses[bossName] ~= false then
					selected[#selected + 1] = bossName
				end
			end

			return selected
		end

		local function currentMinute()
			return math.floor(DateTime.now().UnixTimestamp / 60) + 120
		end

		local function lastSpawnBefore(spawnMinutes, nowMinute)
			local minutesSince
			local spawnMinute

			for _, minuteOfDay in ipairs(spawnMinutes) do
				local since = (nowMinute - minuteOfDay) % 1440

				if not minutesSince or since < minutesSince then
					spawnMinute = nowMinute - since
					minutesSince = since
				end
			end

			return minutesSince, spawnMinute
		end

		local lastFoughtSpawn = {}

		local function markSpawnFought(bossName)
			local minutes = spawnMinutes[bossName]
			if not minutes then return end
			local since, spawnMinute = lastSpawnBefore(minutes, currentMinute())
			lastFoughtSpawn[bossName] = spawnMinute
		end

		local function dueTimedBosses(bosses)
			local selectedSet = {}

			for _, name in ipairs(bosses) do
				selectedSet[name] = true
			end

			local window = tonumber(bossRotation.PriorityWindowMinutes) or 12
			local nowMinute = currentMinute()
			local due = {}

			for _, name in ipairs(timedBosses) do
				local minutes = spawnMinutes[name]

				if selectedSet[name] and minutes then
					local since, spawnMinute = lastSpawnBefore(minutes, nowMinute)

					if since <= window and lastFoughtSpawn[name] ~= spawnMinute then
						due[#due + 1] = name
					end
				end
			end

			return due
		end

		-- start / stop
		local running = false

		local function keepOutOfPhysicsState(character)
			local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
			if not humanoid then return end

			task.spawn(function()
				while running and humanoid.Parent do
					if humanoid:GetState() == Enum.HumanoidStateType.Physics then
						humanoid:ChangeState(Enum.HumanoidStateType.Running)
						humanoid.AutoRotate = true
					end

					task.wait(0.05)
				end
			end)
		end

		return {
			Enabled = function()
				return bossRotation.Enabled == true
			end,
			Status = function()
				return currentStatus
			end,
			Stop = function()
				running = false
				Travel.stopMovement()
				Travel.stopAllFlight()
				runStats.status("stopped")
				log("Stopped.")
			end,
			Run = function()
				if running then return end
				running = true

				local islands = {
					fishmanIsland = workspace.Islands:FindFirstChild("Fishman Island"),
					roca = workspace.Islands:FindFirstChild("Roca Island"),
					shrine = workspace.Islands:FindFirstChild("???? Shrine"),
					thrillerbark = workspace.Islands:FindFirstChild("Thriller Bark"),
				}

				if islands.fishmanIsland then
					for _, child in ipairs(islands.fishmanIsland:GetChildren()) do
						if child:IsA("MeshPart") and (string.find(child.MeshId, "6223193062") or string.find(child.MeshId, "945061799")) then
							child:Destroy()
						end
					end

					print("Successfully deleted all corals and the dome")

					islands.fishmanIsland.ChildAdded:Connect(function(child)
						if child:IsA("MeshPart") and (string.find(child.MeshId, "6223193062") or string.find(child.MeshId, "945061799")) then
							child:Destroy()
						end
					end)
				end

				if islands.thrillerbark then
					for _, child in ipairs(islands.thrillerbark:GetChildren()) do
						if child:IsA("MeshPart") or child:IsA("UnionOperation") or child.Name == "Flag" then
							child:Destroy()
						end
					end

					print("Successfully deleted the sails")

					islands.thrillerbark.ChildAdded:Connect(function(child)
						if child:IsA("MeshPart") or child:IsA("UnionOperation") or child.Name == "Flag" then
							child:Destroy()
						end
					end)
				end

				if localPlayer.Character then
					keepOutOfPhysicsState(localPlayer.Character)
				end

				localPlayer.CharacterAdded:Connect(keepOutOfPhysicsState)
				log("Boss rotation starting for " .. localPlayer.Name .. ".")

				if getTravelMethod() == "Goro" then
					log("Travel flies on Goro Goro (Lightning Form) - the fruit is required. Legs without it aren't noclipped and can stall in terrain.")
				end

				local trees = workspace.Env:FindFirstChild("Trees")

				if trees then
					for _, child in ipairs(trees:GetChildren()) do
						child:Destroy()
					end

					print("Successfully deleted all trees")

					trees.ChildAdded:Connect(function(child)
						task.wait(0.25)
						child:Destroy()
					end)
				end

				local startedAt = os.clock()

				runStats.poll("uptime", function()
					return os.clock() - startedAt
				end)

				local function getServerAge()
					local ok, result = pcall(function()
						return localPlayer.PlayerGui.Display.ServerAge.Text
					end)

					if not ok or type(result) ~= "string" then return nil end
					local hours, minutes, seconds = result:match("^(%d+):(%d+):(%d+)$")
					if not hours then return nil end
					return tonumber(hours) * 3600 + tonumber(minutes) * 60 + tonumber(seconds)
				end

				if getAttackMode() == "Leopard" then Abilities.equipLeopardFruit() end

				while running do
					if (getServerAge() or os.clock() - startedAt) >= 600 then break end

					runStats.status("Waiting for server warmup")
					task.wait(5)
				end

				if startAntiAfk then startAntiAfk() end

				local resumeBoss

				local function attemptBoss(bossName, shouldContinue)
					local ok, fought = pcall(fightBoss, bossName, shouldContinue)

					if not ok then
						warn("[BossRotation] " .. bossName .. " attempt failed: " .. tostring(fought))
						fought = false
					end

					local interrupted = not shouldContinue() and not fought
					resumeBoss = interrupted and bossName or nil

					if not interrupted and spawnMinutes[bossName] then
						markSpawnFought(bossName)
					end
				end

				Core.runWithDeathRecovery("BossRotation", function(isAlive)
					startFruitLoop(isAlive)

					if resumeBoss then
						local bossName = resumeBoss
						local stillSelected = false

						for _, name in ipairs(getSelectedBosses()) do
							if name == bossName then
								stillSelected = true
								break
							end
						end

						if stillSelected then
							log("Resuming " .. bossName .. " after respawn.")
							attemptBoss(bossName, isAlive)
						else
							resumeBoss = nil
						end
					end

					while running and isAlive() do
						local bosses = getSelectedBosses()

						if #bosses == 0 then
							runStats.status("No bosses selected")
							task.wait(10)
						else
							for _, bossName in ipairs(bosses) do
								if not running or not isAlive() then break end

								if isTimedBoss[bossName] then
									task.wait(1)
								elseif not (isSoulKing(bossName) and soulKingOnCooldown()) then
									attemptBoss(bossName, isAlive)
								end

								if running and isAlive() then
									for _, priorityBoss in ipairs(dueTimedBosses(bosses)) do
										if not running or not isAlive() then break end

										attemptBoss(priorityBoss, isAlive)
									end
								end

								if running and isAlive() then checkMerchant(isAlive) end
							end
						end
					end
				end, runStats)
			end,
		}
	end
end

defineModule("BossRotation", createBossRotation)

----------------------------------------------------------------------------
-- Factory: factory gear farm
----------------------------------------------------------------------------
local function createFactory()
	return function(options)
		local opts = options or {}
		local config = opts.Config or {}
		local factory = config.Factory

		if type(factory) ~= "table" then
			factory = {}
			config.Factory = factory
		end

		local postWebhook = opts.postWebhook
		local startAntiAfk = opts.startAntiAfk
		local pauseAntiAfk = opts.pauseAntiAfk
		local resumeAntiAfk = opts.resumeAntiAfk

		local Players = cloneref(game:GetService("Players"))
		cloneref(game:GetService("ReplicatedStorage"))
		local RunService = cloneref(game:GetService("RunService"))
		local localPlayer = Players.LocalPlayer
		local Travel = Modules.Travel()
		local Abilities = Modules.Abilities()
		local FruitInventory = Modules.FruitInventory()
		local Core = Modules.Core()

		local function log(message)
			print("[Factory] " .. message)
		end

		local function notOnErrorHold()
			return not Core.IsErrorHoldActive()
		end

		-- spots inside the factory
		local entranceCFrame = CFrame.new(8816.44434, 100.7727203, 11540.3223, -0.999961972, 3.44949136e-08, -0.00871906709, 3.47685543e-08, 1, -3.12328439e-08, 0.00871906709, -3.15348068e-08, -0.999961972)
		local floor1CFrame = CFrame.new(8803.76367, 67.4416504, 11854.9297, -0.691602051, 1.04959724e-07, -0.722278774, 8.40609005e-08, 1, 6.48268212e-08, 0.722278774, -1.58810387e-08, -0.691602051)
		local floor2CFrame = CFrame.new(8703.00391, 289.363708, 11882.04, 0.857165039, 6.15801383e-08, -0.515041828, -1.45675161e-08, 1, 9.53191943e-08, 0.515041828, -7.42014024e-08, 0.857165039)
		local poolCFrame = CFrame.new(8680.88086, 289.413666, 11817.5117, 0.746102452, -5.81210429e-07, 0.665831208, 1.97215382e-08, 1, 8.50810466e-07, -0.665831208, -6.21660547e-07, 0.746102452)
		local returnCFrame = CFrame.new(8576.18848, 65.7727356, 10503.3018, -0.980880737, -8.22853536e-08, 0.194609761, -9.49154639e-08, 1, -5.55747874e-08, -0.194609761, -7.29837168e-08, -0.980880737)

		-- alert level shown on the front door
		local function getFrontDoorText()
			local ok, result = pcall(function()
				return workspace.Islands["Rose Kingdom"].Factory.FrontDoor.Top.BillboardGui.TextLabel
			end)

			if not ok or not result then return nil end
			local contentText = result.ContentText

			if type(contentText) ~= "string" or contentText == "" then
				contentText = result.Text
			end

			return type(contentText) == "string" and contentText ~= "" and contentText or nil
		end

		local function getAlertLevel()
			local text = getFrontDoorText()
			if not text then return nil end

			if string.find(text, "CLOSED", 1, true) then return 0 end
			local alerts = 0
			local searchFrom = 1

			while true do
				local found = string.find(text, "🚨", searchFrom, true)

				if not found then break end

				alerts += 1
				searchFrom = found + 4
			end

			return alerts > 0 and alerts or nil
		end

		local validAlertLevels = { [1] = true, [2] = true }

		local function waitForAlert(shouldContinue, setStatus, isReady, statusText)
			if pauseAntiAfk then pauseAntiAfk() end

			local level

			while true do
				level = nil

				if not shouldContinue() then break end

				level = getAlertLevel()

				if isReady(level) then break end

				setStatus(statusText .. " (now " .. tostring(level or "?") .. ")")
				task.wait(2)
			end

			if resumeAntiAfk then resumeAntiAfk() end

			return level
		end

		-- finding scientists
		local function getRealPosition(npc)
			local realPos = npc:FindFirstChild("realPos")

			if realPos then
				if realPos:IsA("CFrameValue") then return realPos.Value.Position end

				if realPos:IsA("Vector3Value") then return realPos.Value end
			end

			local attribute = npc:GetAttribute("realPos")
			if typeof(attribute) == "CFrame" then return attribute.Position end

			if typeof(attribute) == "Vector3" then return attribute end
			local humanoidRootPart = npc:FindFirstChild("HumanoidRootPart")
			return humanoidRootPart and humanoidRootPart.Position or nil
		end

		local function floorForY(y)
			return y < 265 and 1 or 2
		end

		local function getRootY(npc)
			local humanoidRootPart = npc:FindFirstChild("HumanoidRootPart")
			return humanoidRootPart and humanoidRootPart.Position.Y or nil
		end

		local function findNearestNpc(namePart, nearPos, maxRadius, excludePart, floor)
			local npCs = workspace:FindFirstChild("NPCs")
			if not npCs then return nil end
			maxRadius = maxRadius and maxRadius * maxRadius or nil
			local bestDistSq = math.huge
			local best

			for _, child in ipairs(npCs:GetChildren()) do
				local lowerName = string.lower(child.Name)
				local matches = child:IsA("Model") and Abilities.isTargetAlive(child) and string.find(lowerName, namePart, 1, true) and not (excludePart and string.find(lowerName, excludePart, 1, true))

				if matches then
					local position = getRealPosition(child)
					local y = floor and getRootY(child)

					if position and (not floor or y and floorForY(y) == floor) then
						local distSq = 0

						if nearPos then
							local dx = position.X - nearPos.X
							local dz = position.Z - nearPos.Z
							distSq = dx * dx + dz * dz
						end

						if (not maxRadius or distSq <= maxRadius) and distSq < bestDistSq then
							bestDistSq = distSq
							best = child
						end
					end
				end
			end

			return best
		end

		local function findScientist(nearPos, maxRadius, floor)
			return findNearestNpc("scientist", nearPos, maxRadius, "devil fruit", floor)
		end

		-- hover anchor above enemies
		local ceilingProbeDirs = {
			Vector3.new(0, 1, 0),
			Vector3.new(1, 1, 0).Unit,
			Vector3.new(-1, 1, 0).Unit,
			Vector3.new(0, 1, 1).Unit,
			Vector3.new(0, 1, -1).Unit,
		}
		local wallProbeDirs = {
			Vector3.new(1, 0, 0),
			Vector3.new(-1, 0, 0),
			Vector3.new(0, 0, 1),
			Vector3.new(0, 0, -1),
			Vector3.new(1, 0, 1).Unit,
			Vector3.new(1, 0, -1).Unit,
			Vector3.new(-1, 0, 1).Unit,
			Vector3.new(-1, 0, -1).Unit,
		}

		local function ceilingClearance(origin, ignore, margin)
			local lowest

			for _, dir in ipairs(ceilingProbeDirs) do
				local hit = Travel.probeAlongRayResult(origin, dir * 200, ignore)

				if hit and (not (dir.Y < 0.9) or hit.Normal.Y <= -0.2) then
					local clearance = hit.Position.Y - origin.Y - margin

					if not lowest or clearance < lowest then lowest = clearance end
				end
			end

			return lowest
		end

		local function wallPushback(origin, ignore, minDistance)
			local push = Vector3.new(0, 0, 0)

			for _, dir in ipairs(wallProbeDirs) do
				local hit = Travel.probeAlongRayResult(origin, dir * 200, ignore)

				if hit then
					local magnitude = (hit.Position - origin).Magnitude

					if magnitude < minDistance then
						push += -dir * (minDistance - magnitude)
					end
				end
			end

			return push
		end

		local function createHoverAnchor(target, height, hoverOptions)
			local startPos = getRealPosition(target) or Vector3.new()
			local clearance
			local offset = Vector3.new(0, 0, 0)
			local lastProbe = 0
			local anchorPart = Instance.new("Part")
			anchorPart.Size = Vector3.new(1, 1, 1)
			anchorPart.Anchored = true
			anchorPart.CanCollide = false
			anchorPart.CanQuery = false
			anchorPart.CanTouch = false
			anchorPart.Transparency = 1
			anchorPart.Position = startPos + Vector3.new(0, height, 0)
			anchorPart.Parent = workspace

			local connection = RunService.Heartbeat:Connect(function()
				if not target.Parent then return end
				local targetPos = getRealPosition(target)
				if not targetPos then return end

				if hoverOptions then
					local now = os.clock()

					if now - lastProbe >= 0.5 then
						lastProbe = now

						if hoverOptions.clearance then
							clearance = ceilingClearance(targetPos, hoverOptions.exclusions, hoverOptions.clearance)
						end

						if hoverOptions.wallClearance then
							offset = wallPushback(Vector3.new(targetPos.X, targetPos.Y + height, targetPos.Z), hoverOptions.exclusions, hoverOptions.wallClearance)
						end
					end
				end

				local wanted = height
				local hoverHeight = height

				if clearance then
					hoverHeight = math.max(math.min(wanted, clearance), 2)
				end

				anchorPart.Position = Vector3.new(targetPos.X + offset.X, targetPos.Y + hoverHeight, targetPos.Z + offset.Z)
			end)

			return anchorPart, function()
				connection:Disconnect()
				anchorPart:Destroy()
			end, function(newHeight)
				height = newHeight
			end
		end

		local function dropToGround(shouldContinue)
			if not shouldContinue() then return end
			local rootPart = localPlayer.Character
			rootPart = rootPart and rootPart:FindFirstChild("HumanoidRootPart")
			if not rootPart then return end
			local hit = Travel.probeAlongRayResult(rootPart.Position, Vector3.new(0, -500, 0))

			if hit then Travel.snapToHeight(hit.Position.Y, 0.1) end
		end

		-- stats panel
		local currentStatus = "idle"
		local runStats = {}
		local panel
		local statsGui = opts.StatsGui
		local pollInterval = tonumber(opts.StatsPollInterval) or 1

		if statsGui and opts.StatsEnabled ~= false then
			local statsToggleKey = opts.StatsToggleKey
			local hasHotkey = type(statsToggleKey) == "string" and statsToggleKey ~= ""
			local hotkey

			if hasHotkey then
				local ok

				ok, hotkey = pcall(function()
					return Enum.KeyCode[statsToggleKey]
				end)

				if not ok then
					warn("[Factory] '" .. statsToggleKey .. "' is not a KeyCode - no stats hotkey.")
					hotkey = nil
				end
			end

			local pcall = pcall

			local panelOptions = {
				Title = "Factory",
				PersistKey = "FactoryStats",
				Width = tonumber(opts.StatsWidth) or 300,
				ToggleKeyCode = hotkey,
			}

			local stats = {}
			local uptimeRow = { key = "uptime", label = "Uptime", format = statsGui.FormatClock }
			local statusRow = { key = "status", label = "Status", color = Color3.fromRGB(255, 214, 102) }
			local deathsRow = { key = "deaths", label = "Deaths", color = Color3.fromRGB(232, 92, 84) }
			stats[1] = uptimeRow
			stats[2] = statusRow
			stats[3] = { key = "kills", label = "Kills" }
			stats[4] = { key = "gearRuns", label = "Barrel kills" }
			stats[5] = { key = "fruits", label = "Fruits" }
			stats[6] = deathsRow
			panelOptions.Stats = stats
			local ok, panelOrErr = pcall(statsGui.new, panelOptions)

			if ok then
				panel = panelOrErr
			else
				warn("[Factory] could not build the stats panel: " .. tostring(panelOrErr))
			end
		end

		runStats.increment = function(key, amount)
			if panel then pcall(panel.Increment, panel, key, amount) end
		end

		runStats.poll = function(key, getter)
			if panel then pcall(panel.Poll, panel, key, pollInterval, getter) end
		end

		runStats.status = function(text)
			currentStatus = text

			if panel then pcall(panel.Set, panel, "status", text) end
		end

		runStats.recordFruit = function()
			runStats.increment("fruits")
		end

		-- fruits
		local fruitQueue = FruitInventory.createFruitQueue("Factory")

		local function handleFruit(fruitName)
			return FruitInventory.handleFruitGeneric("Factory", runStats, fruitName, { dropPingCliffOnly = true })
		end

		local function startFruitLoop(shouldContinue)
			FruitInventory.startFruitLoopGeneric(fruitQueue, handleFruit, shouldContinue, "Factory", function()
			end, nil)
		end

		-- fighting scientists
		local function getScientistRoots()
			local npCs = workspace:FindFirstChild("NPCs")
			if not npCs then return {} end
			local roots = {}

			for _, child in ipairs(npCs:GetChildren()) do
				local lowerName = string.lower(child.Name)

				if child:IsA("Model") and Abilities.isTargetAlive(child) and string.find(lowerName, "scientist", 1, true) and not string.find(lowerName, "devil fruit", 1, true) then
					local humanoidRootPart = child:FindFirstChild("HumanoidRootPart")

					if humanoidRootPart then roots[#roots + 1] = humanoidRootPart end
				end
			end

			return roots
		end

		local function killScientist(scientist, shouldContinue)
			if not shouldContinue() then return false end
			local position = getRealPosition(scientist)

			if position then
				Travel.moveWithGeppoToCFrame(CFrame.new(position), 140, 9, false, "linear")
			end

			if not shouldContinue() then return false end
			local anchorPart, destroyAnchor, setHoverHeight = createHoverAnchor(scientist, 9, { exclusions = { scientist }, clearance = 6, wallClearance = 10 })
			Travel.startMovement(Travel.trackPart, anchorPart, 60, 0, true)
			Travel.startSkyWalkLoop(1.5)

			local function isAlive()
				return Abilities.isTargetAlive(scientist)
			end

			while shouldContinue() and isAlive() do
				local humanoidRootPart = scientist:FindFirstChild("HumanoidRootPart")

				if not humanoidRootPart then break end

				setHoverHeight(9)
				local position = getRealPosition(scientist)

				if position then Travel.faceTarget(position) end

				local targets = getScientistRoots()

				if #targets == 0 then targets = { humanoidRootPart } end

				if notOnErrorHold() then
					Abilities.katanaCombo(targets, function()
						return shouldContinue() and isAlive() and notOnErrorHold()
					end, function()
						setHoverHeight(11.5)
					end)
				else
					setHoverHeight(11.5)
				end

				local waitUntil = os.clock() + 3

				while shouldContinue() and isAlive() and os.clock() < waitUntil do
					local position = getRealPosition(scientist)

					if position then Travel.faceTarget(position) end

					task.wait(0.1)
				end
			end

			dropToGround(shouldContinue)
			Travel.stopSkyWalkLoop()
			Travel.stopMovement()
			destroyAnchor()
			return not isAlive()
		end

		local function getRootPosition()
			local character = localPlayer.Character
			character = character and character:FindFirstChild("HumanoidRootPart")
			return character and character.Position or nil
		end

		local function isAtEntrance()
			local position = getRootPosition()
			if not position then return false end
			return ((position - entranceCFrame.Position) * Vector3.new(1, 0, 1)).Magnitude <= 50
		end

		local function logStrandedScientists(fallbackPos)
			local npCs = workspace:FindFirstChild("NPCs")
			if not npCs then return end
			local myPos = getRootPosition() or fallbackPos

			for _, child in ipairs(npCs:GetChildren()) do
				local lowerName = string.lower(child.Name)

				if child:IsA("Model") and string.find(lowerName, "scientist", 1, true) and not string.find(lowerName, "devil fruit", 1, true) then
					local alive = Abilities.isTargetAlive(child)
					local position = getRealPosition(child)
					local magnitude = position and myPos and (position - myPos).Magnitude or nil
					log(string.format("DEBUG stranded check: %s isTargetAlive=%s distance=%s (radius=%d)", child.Name, tostring(alive), magnitude and string.format("%.1f", magnitude) or "?", 500))
				end
			end
		end

		local function clearFloor(floorPos, shouldContinue, setStatus, floor)
			local misses = 0

			while shouldContinue() and misses < 2 do
				local searchPos = getRootPosition() or floorPos
				local scientist = findScientist(searchPos, 500, floor)

				if not scientist and floor then
					scientist = findScientist(searchPos, 500, nil)
				end

				if not scientist then
					misses += 1

					if misses < 2 then task.wait(1) end
				else
					setStatus("Killing " .. scientist.Name)
					misses = 0

					if killScientist(scientist, shouldContinue) then
						runStats.increment("kills", 1)
					end
				end
			end

			logStrandedScientists(floorPos)
		end

		-- moving around
		local function warmUpGeppo(shouldContinue)
			if not shouldContinue() then return end
			Travel.beginTravelFlight(0.75)
			task.wait(3)
			Travel.endTravelFlight()
		end

		local function flyBackToFactory(shouldContinue)
			if not shouldContinue() then return end
			Travel.moveWithGeppoToCFrame(returnCFrame, 140, 10, true, "linear", 150)
		end

		local function goToEntrance(shouldContinue)
			if not shouldContinue() then return end
			Travel.moveWithGeppoToCFrame(entranceCFrame, 100, 10, true, "linear", 150)
			if not shouldContinue() then return end
			Travel.setFaceMouseState(true)
			task.wait(0.5)
			Travel.snapToCFrame(entranceCFrame)
			Travel.setFaceMouseState(false)
		end

		local function goToFloor1(shouldContinue)
			if not shouldContinue() then return end
			Travel.moveWithGeppoToCFrame(floor1CFrame, 100, 10, true, "linear", 150)
			if not shouldContinue() then return end
			Travel.setFaceMouseState(true)
			task.wait(0.3)
			Travel.snapToCFrame(floor1CFrame)
			Travel.setFaceMouseState(false)
		end

		local function goToFloor2(shouldContinue)
			if not shouldContinue() then return end
			Travel.moveWithGeppoToCFrame(floor2CFrame, 140, 0, true, "linear", nil)
			if not shouldContinue() then return end
			Travel.setFaceMouseState(true)
			task.wait(0.3)
			Travel.snapToCFrame(floor2CFrame)
			Travel.setFaceMouseState(false)
		end

		-- last fight: the factory pool
		local function fightFactoryPool(shouldContinue, setStatus)
			local factoryPool = workspace.Env:FindFirstChild("FactoryPool")
			if not factoryPool then
				warn("[Factory] workspace.Env.FactoryPool not found - skipping the barrel fight.")
				return
			end
			local barrelHp = factoryPool:FindFirstChild("barrelHP")
			local poolRoot = factoryPool:FindFirstChild("HumanoidRootPart")
			if not barrelHp or not poolRoot then
				warn("[Factory] FactoryPool is missing barrelHP or HumanoidRootPart - skipping.")
				return
			end
			setStatus("Fighting the Factory Pool")
			if not shouldContinue() then return end
			Travel.moveWithGeppoToCFrame(poolCFrame, 140, 10, true, "linear", 150)
			if not shouldContinue() then return end
			Travel.setFaceMouseState(true)
			task.wait(0.5)
			Travel.snapToCFrame(poolCFrame)
			Travel.setFaceMouseState(false)
			if not shouldContinue() then return end
			Travel.stopAllFlight()
			Travel.startMovement(Travel.hover, false)

			local function poolAlive()
				local alive = barrelHp.Parent ~= nil and ((tonumber(barrelHp.Value) or 0) > 0)

				return alive
			end

			while shouldContinue() and poolAlive() do
				local comboDone = false

				if notOnErrorHold() then
					Abilities.katanaCombo({ poolRoot }, function()
						return shouldContinue() and poolAlive() and notOnErrorHold()
					end, function()
						comboDone = true
					end)
				end

				local waitUntil = os.clock() + 2

				while shouldContinue() and poolAlive() and os.clock() < waitUntil do
					task.wait(0.1)
				end
			end

			Travel.stopMovement()

			if shouldContinue() and not poolAlive() then
				runStats.increment("gearRuns", 1)
				log("Factory Pool destroyed - gear should have dropped.")

				if postWebhook then
					postWebhook({
						embeds = {
							{
								title = "Factory Pool Destroyed",
								description = "**User:** || " .. localPlayer.Name .. " ||",
								type = "rich",
								color = 5025616,
								fields = {
									{
										name = "Cyborg Gears",
										value = tostring(FruitInventory.getStoredCount("Cyborg Gear")),
										inline = true,
									},
								},
								footer = { text = "gear farm" },
								timestamp = DateTime.now():ToIsoDate(),
							},
						},
					}, factory.WebhookUrl)
				end
			end
		end

		-- one full run
		local function findKatanaName()
			local character = localPlayer.Character

			if character then
				for _, child in ipairs(character:GetChildren()) do
					local isKatana = child:IsA("Tool") and string.find(string.lower(child.Name), "katana", 1, true)

					if isKatana then return child.Name end
				end
			end

			local backpack = localPlayer:FindFirstChildOfClass("Backpack")
			if not backpack then return nil end

			for _, child in ipairs(backpack:GetChildren()) do
				if child:IsA("Tool") and string.find(string.lower(child.Name), "katana", 1, true) then
					return child.Name
				end
			end

			return nil
		end

		local function waitForAlertReset(shouldContinue)
			runStats.status("Waiting at entrance")

			waitForAlert(shouldContinue, runStats.status, function(level)
				return level ~= nil and validAlertLevels[level]
			end, "Waiting for alert to reset")

			return false
		end

		local function runOnce(shouldContinue, firstRun)
			local katanaName = findKatanaName()

			if not katanaName or not FruitInventory.setItemEquipped(katanaName, true) then
				warn("[Factory] No Katana-type weapon found in Backpack - waiting before retrying.")
				runStats.status("No Katana in Backpack")
				task.wait(10)
				return firstRun
			end

			if firstRun then
				runStats.status("Warming up Geppo")
				warmUpGeppo(shouldContinue)
				if not shouldContinue() then return false end
				runStats.status("Returning to the Factory")
				flyBackToFactory(shouldContinue)
				if not shouldContinue() then return false end
			end

			goToEntrance(shouldContinue)
			if not shouldContinue() then return false end

			local alertLevel = waitForAlert(shouldContinue, runStats.status, function(level)
				return level ~= nil and validAlertLevels[level]
			end, "Waiting for alert 1/2")

			if not alertLevel or not shouldContinue() then return false end
			log("Alert " .. alertLevel .. " - waiting 7s before entering.")
			runStats.status("Alert " .. alertLevel .. " - waiting to enter")
			task.wait(7)
			if not shouldContinue() then return false end
			log("Entering at alert " .. alertLevel .. ".")
			runStats.status("Entering")
			goToFloor1(shouldContinue)
			if not shouldContinue() then return false end
			clearFloor(floor1CFrame.Position, shouldContinue, runStats.status, 1)
			if not shouldContinue() then return false end

			if isAtEntrance() then
				log("Teleported back to the entrance after floor 1 - the raid ended without us.")
				return waitForAlertReset(shouldContinue)
			end
			runStats.status("Climbing to floor 2")
			goToFloor2(shouldContinue)
			if not shouldContinue() then return false end
			clearFloor(floor2CFrame.Position, shouldContinue, runStats.status, 2)
			if not shouldContinue() then return false end

			if isAtEntrance() then
				log("Teleported back to the entrance after floor 2 - the raid ended without us.")
				return waitForAlertReset(shouldContinue)
			end
			fightFactoryPool(shouldContinue, runStats.status)
			if not shouldContinue() then return false end
			return waitForAlertReset(shouldContinue)
		end

		-- start / stop
		local running = false

		local function keepOutOfPhysicsState(character)
			local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
			if not humanoid then return end

			task.spawn(function()
				while running and humanoid.Parent do
					if humanoid:GetState() == Enum.HumanoidStateType.Physics then
						humanoid:ChangeState(Enum.HumanoidStateType.Running)
						humanoid.AutoRotate = true
					end

					task.wait(0.05)
				end
			end)
		end

		return {
			Enabled = function()
				return factory.Enabled == true
			end,
			Status = function()
				return currentStatus
			end,
			Stop = function()
				running = false
				Travel.stopMovement()
				Travel.stopAllFlight()
				runStats.status("stopped")
				log("Stopped.")
			end,
			Run = function()
				if running then return end
				running = true

				if localPlayer.Character then
					keepOutOfPhysicsState(localPlayer.Character)
				end

				localPlayer.CharacterAdded:Connect(keepOutOfPhysicsState)
				log("Auto Farm Gears starting for " .. localPlayer.Name .. ".")
				local startedAt = os.clock()

				runStats.poll("uptime", function()
					return os.clock() - startedAt
				end)

				if startAntiAfk then startAntiAfk() end

				Core.runWithDeathRecovery("Factory", function(isAlive)
					startFruitLoop(isAlive)
					local firstRun = true

					while running and isAlive() do
						firstRun = runOnce(isAlive, firstRun)
					end
				end, runStats)
			end,
		}
	end
end

defineModule("Factory", createFactory)

----------------------------------------------------------------------------
-- Fishing: auto fishing
----------------------------------------------------------------------------
local function createFishing()
	return function(options)
		local opts = options or {}
		local config = opts.Config or {}
		local fishing = config.Fishing

		if type(fishing) ~= "table" then
			fishing = {}
			config.Fishing = fishing
		end

		local startAntiAfk = opts.startAntiAfk
		local pauseAntiAfk = opts.pauseAntiAfk
		local resumeAntiAfk = opts.resumeAntiAfk

		local Players = cloneref(game:GetService("Players"))
		local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
		local RunService = cloneref(game:GetService("RunService"))
		local GuiService = cloneref(game:GetService("GuiService"))
		local UserInputService = cloneref(game:GetService("UserInputService"))
		local localPlayer = Players.LocalPlayer
		local Travel = Modules.Travel()
		local FruitInventory = Modules.FruitInventory()
		local Core = Modules.Core()
		local PartySystem = Modules.PartySystem()
		local AutoMerchant = Modules.AutoMerchant()
		local mouse1press = mouse1press
		local mouse1release = mouse1release
		local mouse1click = mouse1click
		local mousemoveabs = mousemoveabs
		local getconnections = getconnections

		local function log(message)
			print("[Fishing] " .. message)
		end

		local running = false

		-- settings (spot, travel, camera, bait, cast, reel, selling)
		local spot = {
			cframe = CFrame.new(-1341.94214, 1.2800858, -4988.81592, -0.150621578, -0.00396382855, 0.988583624, 2.68740841e-05, 0.999991953, 0.00401369249, -0.988591552, 0.000631140661, -0.150620252) * CFrame.Angles(0, 1.5707963267948966, 0),
			ringRadius = math.max(tonumber(fishing.SpotRadius) or 0, 0),
			standHeight = 3.5,
			probeUp = 60,
			probeDown = 200,
		}
		spot.position = spot.cframe.Position

		if typeof(fishing.SpotPosition) == "Vector3" then
			spot.cframe = CFrame.new(fishing.SpotPosition) * spot.cframe.Rotation
			spot.position = fishing.SpotPosition
		end

		spot.refaceSettle = 0.75

		local function getSpotTurn()
			return tonumber(fishing.SpotTurn) or 0
		end

		local function getSpotRotation()
			return spot.cframe.Rotation * CFrame.Angles(0, -math.rad(getSpotTurn()), 0)
		end

		local baitShopCFrame = CFrame.new(-6509.251, 7.725, -7605.082)
		local sellSpotCFrame = CFrame.new(-1326.44397, 1.26798677, -4978.44629, 0.186300814, -0.00086248701, 0.982492387, 0.00187785819, 0.999998093, 0.000521764043, -0.982490957, 0.00174776989, 0.186302096)

		local travelSettings = {
			speed = positiveNumberOr(fishing.TravelSpeed, 100),
			skipDistance = 400,
			snapSettle = 0.4,
			arrivalOffset = 5,
			seaLevelY = 2,
			geppoWarmup = 5,
		}

		local holdSettings = { resettleSeconds = 0.5, driftLimit = 8, facingDot = 0.999 }
		local cameraSettings = { distance = 12, eyeHeight = 2, shoulder = 1.75, lookAhead = 90, releaseKey = Enum.KeyCode.LeftAlt }
		local cursorReleaseDepth = 0
		local cursorReleased = false

		local function withFreeCursor(callback)
			cursorReleaseDepth += 1

			pcall(function()
				UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			end)

			local ok, result = pcall(callback)
			cursorReleaseDepth -= 1
			if not ok then return nil, result end
			return true
		end

		UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed then return end

			if input.KeyCode ~= cameraSettings.releaseKey then return end
			cursorReleased = not cursorReleased

			if cursorReleased then
				pcall(function()
					UserInputService.MouseBehavior = Enum.MouseBehavior.Default
				end)
			end
		end)

		local rodPriority = {
			["Lovestruck Rod"] = 12,
			["Devil Fruit Rod"] = 8,
			["ODM Rod"] = 7,
			["Jack-O'Rod"] = 6,
			["Angler Rod"] = 5,
			["Merchants Banana Rod"] = 4,
			["Epic Fishing Rod"] = 3,
			["Rare Fishing Rod"] = 2,
			["Fishing Rod"] = 1,
		}

		local baitPriority = { "Legendary Fish Bait", "Rare Fish Bait", "Common Fish Bait" }

		local baitSettings = {
			buyAmount = positiveNumberOr(fishing.BaitBuyAmount, 300),
			buyPeli = positiveNumberOr(fishing.BaitBuyPeli, 15000),
			shopReach = 120,
			checkInterval = 15,
			retryBackoff = 90,
			buyInterval = 0.15,
			maxMisses = 3,
			guiName = "FishingBaitGui",
		}

		local castSettings = {
			chargeSeconds = 0.1,
			hookAppearSeconds = 10,
			aimHoldAfterThrow = 3,
			aimSettle = 0.2,
			aimHoldInterval = 0.03,
			retryDelay = 0.25,
			hookSweepDelay = 1,
			hookIdleTimeout = 45,
			rodEquipSettle = 0.5,
			rodWaitSeconds = 15,
			tickInterval = 0.1,
			waterLevelFallback = -2.675,
		}

		local aimSettings = {
			angles = { 0, 15, -15, 30, -30, 45, -45, 60, -60, 75, -75, 90, -90, 120, -120, 150, -150, 180 },
			factors = { 1, 1.3, 0.75, 1.6, 1.9 },
			minDistance = 50,
			orderPenalty = 10,
			goodScore = 20,
		}

		local reelSettings = {
			guiName = "FishingUIBill",
			holdText = "HOLD CLICK",
			releaseText = "RELEASE CLICK",
			maxSeconds = 45,
			bar = {
				max = 2,
				barRadius = 0.25,
				maxVelocity = 2,
				holdWindow = 0.0625,
				lookahead = 0.25,
				deadzone = 0.01,
				brakeDeadzone = 0.02,
				fallbackAcceleration = 4,
				wonFill = 0.9,
			},
		}

		local sellSettings = { remoteName = "FishingShopRemote" }

		local sellCount = positiveNumberOr(fishing.SellFishCount, 10)
		sellSettings.minFish = math.max(math.floor(sellCount), 1)
		sellSettings.invokeInterval = 0.4
		sellSettings.maxMisses = 3
		sellSettings.peliCap = 1000000
		sellSettings.cappedBackoff = 300
		sellSettings.defaults = { Common = true, Rare = true, Legendary = false }

		sellSettings.sequence = {
			{ rarity = "Common", name = "Blue-Lip Grouper" },
			{ rarity = "Common", name = "Tigerfin" },
			{ rarity = "Rare", name = "Candy Corn Squid" },
			{ rarity = "Rare", name = "Crimson Polka Puffer" },
			{ rarity = "Rare", name = "Crimson Snapper" },
			{ rarity = "Rare", name = "Exotic Tigerfin" },
			{ rarity = "Rare", name = "Fangfish" },
			{ rarity = "Rare", name = "Zebra Ribbon Angelfish" },
			{ rarity = "Rare", name = "Skeletal Shark" },
			{ rarity = "Legendary", name = "Anglerfish" },
			{ rarity = "Legendary", name = "Dark Skeletal Shark" },
			{ rarity = "Legendary", name = "Jack-O'-Bite" },
			{ rarity = "Legendary", name = "Swordfish" },
			{ rarity = "Legendary", name = "Golden Polka Puffer" },
			{ rarity = "Legendary", name = "Golden Ribbon Angelfish" },
			{ rarity = "Legendary", name = "Golden Tigerfin" },
		}

		local fruitSettings = { sweepInterval = 20 }

		-- which fisher slot this account has
		local function getFisherName(slot)
			local roles = fishing.Roles
			local name = type(roles) == "table" and roles[slot] or nil
			return type(name) == "string" and name ~= "" and name or nil
		end

		local mySlot
		local myIndex = 0
		local fisherCount = 0
		local leaderName

		for i = 1, 12 do
			local name = getFisherName("Fisher" .. i)

			if name then
				fisherCount += 1
				leaderName = leaderName or name

				if name == localPlayer.Name and not mySlot then
					mySlot = "Fisher" .. i
					myIndex = fisherCount
				end
			end
		end

		if mySlot and leaderName == localPlayer.Name then
			PartySystem.startAutoInvite(function(name)
				for i = 1, 12 do
					if getFisherName("Fisher" .. i) == name then return true end
				end

				return false
			end)
		elseif mySlot then
			PartySystem.startAutoAccept()
		end

		-- stats panel
		local currentStatus = "idle"
		local runStats = {}
		local panel
		local statsGui = opts.StatsGui
		local pollInterval = tonumber(opts.StatsPollInterval) or 1

		if statsGui and opts.StatsEnabled ~= false then
			local statsToggleKey = opts.StatsToggleKey
			local hasHotkey = type(statsToggleKey) == "string" and statsToggleKey ~= ""
			local hotkey

			if hasHotkey then
				local ok

				ok, hotkey = pcall(function()
					return Enum.KeyCode[statsToggleKey]
				end)

				if not ok then
					warn("[Fishing] '" .. statsToggleKey .. "' is not a KeyCode - no stats hotkey.")
					hotkey = nil
				end
			end

			local pcall = pcall

			local panelOptions = {
				Title = "Fishing",
				PersistKey = "FishingStats",
				Width = tonumber(opts.StatsWidth) or 300,
				ToggleKeyCode = hotkey,
			}

			local stats = {}
			local uptimeRow = { key = "uptime", label = "Uptime", format = statsGui.FormatClock }
			local statusRow = { key = "status", label = "Status", color = Color3.fromRGB(255, 214, 102) }
			local fishRow = { key = "fish", label = "Fish landed", color = Color3.fromRGB(128, 216, 255) }
			local fruitsRow = { key = "fruits", label = "Fruits", color = Color3.fromRGB(167, 139, 250) }
			local deathsRow = { key = "deaths", label = "Deaths", color = Color3.fromRGB(232, 92, 84) }
			stats[1] = uptimeRow
			stats[2] = statusRow
			stats[3] = { key = "casts", label = "Casts" }
			stats[4] = fishRow
			stats[5] = { key = "baitruns", label = "Bait runs" }
			stats[6] = { key = "sellruns", label = "Sell runs" }
			stats[7] = fruitsRow
			stats[8] = deathsRow
			panelOptions.Stats = stats
			local ok, panelOrErr = pcall(statsGui.new, panelOptions)

			if ok then
				panel = panelOrErr
			else
				warn("[Fishing] could not build the stats panel: " .. tostring(panelOrErr))
			end
		end

		runStats.set = function(key, value)
			if panel then pcall(panel.Set, panel, key, value) end
		end

		runStats.increment = function(key, amount)
			if panel then pcall(panel.Increment, panel, key, amount) end
		end

		runStats.poll = function(key, getter)
			if panel then pcall(panel.Poll, panel, key, pollInterval, getter) end
		end

		runStats.status = function(text)
			currentStatus = text

			if panel then pcall(panel.Set, panel, "status", text) end
		end

		runStats.recordFruit = function()
			runStats.increment("fruits")
		end

		local positionHold
		local cameraHold
		local pauseCount = 0

		-- stay on the spot
		local function holdPosition(target, shouldContinue)
			local position = target.Position
			local rotation = target.Rotation
			local lookVector = target.LookVector
			local settled = true
			local resettleUntil = 0
			local connection

			local function restoreAutoRotate()
				local character = localPlayer.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")

				if humanoid then humanoid.AutoRotate = true end
			end

			local function stop()
				restoreAutoRotate()

				if connection then
					connection:Disconnect()
					connection = nil
				end
			end

			connection = RunService.Heartbeat:Connect(function()
				if not running or not shouldContinue() then
					stop()
					return
				end
				local character = localPlayer.Character
				local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if not humanoidRootPart or not humanoid or humanoid.Health <= 0 then return end

				if humanoid.AutoRotate then humanoid.AutoRotate = false end

				local now = os.clock()

				if holdSettings.driftLimit < (humanoidRootPart.Position - position).Magnitude then
					settled = false
					resettleUntil = now + holdSettings.resettleSeconds
				end

				if now < resettleUntil then
					humanoidRootPart.AssemblyLinearVelocity = Vector3.new()
					humanoidRootPart.AssemblyAngularVelocity = Vector3.new()
					character:PivotTo(target)
				else
					settled = true
					local currentLook = humanoidRootPart.CFrame.LookVector

					if currentLook:Dot(lookVector) < holdSettings.facingDot then
						humanoidRootPart.AssemblyAngularVelocity = Vector3.new()
						character:PivotTo(CFrame.new(humanoidRootPart.Position) * rotation)
					end
				end
			end)

			return {
				isSettled = function()
					return settled
				end,
				stop = stop,
			}
		end

		local function keepOutOfPhysicsState(character)
			local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
			if not humanoid then return end

			task.spawn(function()
				while running and humanoid.Parent do
					local isStuck = not Travel.isMoving()

					isStuck = isStuck and humanoid:GetState() == Enum.HumanoidStateType.Physics

					if isStuck then
						humanoid.PlatformStand = false
						humanoid:ChangeState(Enum.HumanoidStateType.Running)
						humanoid.AutoRotate = true
					end

					task.wait(1)
				end
			end)
		end

		local function groundHeightAt(x, z)
			local raycastParams = RaycastParams.new()
			raycastParams.FilterType = Enum.RaycastFilterType.Exclude
			local ignoreList = {}

			for _, player in ipairs(Players:GetPlayers()) do
				if player.Character then
					ignoreList[#ignoreList + 1] = player.Character
				end
			end

			local playerCharacters = workspace:FindFirstChild("PlayerCharacters")

			if playerCharacters then ignoreList[#ignoreList + 1] = playerCharacters end

			raycastParams.FilterDescendantsInstances = ignoreList
			local hit = workspace:Raycast(Vector3.new(x, spot.position.Y + spot.probeUp, z), Vector3.new(0, -(spot.probeUp + spot.probeDown), 0), raycastParams)
			if hit then return hit.Position.Y end
			return spot.position.Y
		end

		local function getMySpotCFrame()
			local turn = getSpotTurn()
			if spot.ringRadius <= 0 then return CFrame.new(spot.position) * getSpotRotation(), turn end
			local ringOffset = Vector3.new()

			if myIndex > 0 and fisherCount > 1 then
				local angle = (myIndex - 1) / fisherCount * 3.1415926535897931 * 2
				local newVector = Vector3.new
				local offsetX = math.cos(angle) * spot.ringRadius
				ringOffset = newVector(offsetX, 0, math.sin(angle) * spot.ringRadius)
			end

			local x = spot.position.X + ringOffset.X
			local z = spot.position.Z + ringOffset.Z
			local standPos = Vector3.new(x, groundHeightAt(x, z) + spot.standHeight, z)
			return CFrame.new(standPos) * getSpotRotation(), turn
		end

		local function flyTo(target)
			Travel.moveWithGeppoToCFrame(target, travelSettings.speed, travelSettings.arrivalOffset, false, "raycast", travelSettings.speed, travelSettings.seaLevelY)
		end

		local function goTo(target, shouldContinue)
			local rootPart = localPlayer.Character
			rootPart = rootPart and rootPart:FindFirstChild("HumanoidRootPart")

			if not rootPart or (rootPart.Position - target.Position).Magnitude > travelSettings.skipDistance then
				flyTo(target)

				if not shouldContinue() then return false end
			end

			Travel.snapToCFrame(target, travelSettings.snapSettle, false)
			return shouldContinue()
		end

		-- state of the current cast
		local castState

		castState = {
			casting = false,
			reelPending = false,
			biteAt = nil,
			hookSeenAt = nil,
			goal = nil,
			nextCastAt = 0,
			paused = false,
			caughtSinceSell = 0,
			hookLost = false,
			aimSteals = 0,
			stopAim = nil,
			blockedSince = nil,
			getrenv = getrenv,
			globalTables = nil,
			aimGlobals = function()
				if castState.globalTables then return castState.globalTables end
				local globalTables = { _G }

				if castState.getrenv then
					local ok, result = pcall(castState.getrenv)

					ok = ok and type(result) == "table"

					if ok and type(result._G) == "table" and result._G ~= _G then
						table.insert(globalTables, result._G)
					end
				end

				castState.globalTables = globalTables
				return globalTables
			end,
			readGlobal = function(key)
				for _, globals in ipairs(castState.aimGlobals()) do
					local ok, result = pcall(function()
						return globals[key]
					end)

					if ok and result ~= nil then return result end
				end

				return nil
			end,
		}

		local lastBaitWarnAt = 0
		local rodWait = { maxWait = 20, warnAfter = 5, nextWarnAt = 0 }

		-- rod + bait
		local function getBestRod()
			local character = localPlayer.Character
			if not character then return nil end
			local backpack = localPlayer:FindFirstChild("Backpack")
			local bestRank = -1
			local bestRod

			for k, rank in pairs(rodPriority) do
				local rod = character:FindFirstChild(k) or backpack and backpack:FindFirstChild(k)

				if rod and rank > bestRank then
					bestRank = rank
					bestRod = rod
				end
			end

			return bestRod
		end

		local function countItem(itemName)
			local count = 0

			local function countIn(container)
				if not container then return end

				for _, child in ipairs(container:GetChildren()) do
					if child.Name == itemName then count += 1 end
				end
			end

			countIn(localPlayer:FindFirstChild("Backpack"))
			countIn(localPlayer:FindFirstChild("Inventory"))
			local stats = localPlayer:FindFirstChild("Stats" .. localPlayer.Name) or localPlayer:FindFirstChild("Stats")
			stats = stats and stats:FindFirstChild("Inventory")
			stats = stats and stats:FindFirstChild(itemName)

			stats = stats and (tonumber(stats.Value) or tonumber(stats:GetAttribute("Amount")) or 1)

			count += math.max(stats or 0, FruitInventory.getStoredCount(itemName))
			return count
		end

		local function pickBait()
			for _, bait in ipairs(baitPriority) do
				if countItem(bait) > 0 then return bait end
			end

			return "Common Fish Bait"
		end

		-- finding our hook in workspace.Effects
		local hookTracker

		hookTracker = {
			tracked = nil,
			birthRadius = 60,
			rejectWords = { "particle", "sound", "decal", "beam", "trail", "smoke", "splash", "light" },
			settleSeconds = 2,
			folder = function()
				return workspace:FindFirstChild("Effects")
			end,
			ownerOf = function(effect)
				local lowerName = string.lower(effect.Name)
				if not string.find(lowerName, "hook", 1, true) then return nil end

				if string.find(lowerName, string.lower(localPlayer.Name), 1, true) then return "me" end

				local ok, result = pcall(function()
					for _, player in ipairs(Players:GetPlayers()) do
						if player ~= localPlayer and (string.find(lowerName, string.lower(player.Name), 1, true) or player.DisplayName ~= "" and string.find(lowerName, string.lower(player.DisplayName), 1, true)) then
							return player.Name
						end
					end

					return nil
				end)

				if ok and type(result) == "string" then return result end
				return "unknown"
			end,
			byName = function()
				local effects = hookTracker.folder()
				if not effects then return nil end
				local namedHook = effects:FindFirstChild(localPlayer.Name .. "'s hook")
				if namedHook then return namedHook end
				local unknownHook

				for _, child in ipairs(effects:GetChildren()) do
					local owner = hookTracker.ownerOf(child)
					if owner == "me" then return child end

					if owner == "unknown" then unknownHook = unknownHook or child end
				end

				return unknownHook
			end,
			couldBeBobble = function(effect)
				if not (effect:IsA("BasePart") or effect:IsA("Model")) then return false end
				local lowerName = string.lower(effect.Name)

				for _, rejectWord in ipairs(hookTracker.rejectWords) do
					if string.find(lowerName, rejectWord, 1, true) then return false end
				end

				return true
			end,
			snapshot = function()
				local seen = {}
				local effects = hookTracker.folder()
				if not effects then return seen end

				for _, child in ipairs(effects:GetChildren()) do
					seen[child] = true
				end

				return seen
			end,
			appearedSince = function(before, origin)
				local effects = hookTracker.folder()
				if not effects then return nil end
				local bestDistance = math.huge
				local best

				for _, child in ipairs(effects:GetChildren()) do
					if not before[child] then
						local owner = hookTracker.ownerOf(child)
						if owner == "me" then return child end
						local unknownOwner = owner == "unknown"
						local candidate

						if unknownOwner then
							candidate = unknownOwner
						else
							candidate = owner == nil and hookTracker.couldBeBobble(child)
						end

						if candidate then
							local ok, distance = pcall(function()
								return ((child:IsA("BasePart") and child.Position or child:GetPivot().Position) - origin.Position).Magnitude
							end)

							if ok and type(distance) == "number" and distance <= hookTracker.birthRadius and distance < bestDistance then
								best = child
								bestDistance = distance
							end
						end
					end
				end

				return best
			end,
			stillOut = function()
				if hookTracker.tracked and hookTracker.tracked.Parent then return true end
				return hookTracker.byName() ~= nil
			end,
		}

		local function getHook()
			if hookTracker.tracked and hookTracker.tracked.Parent then return hookTracker.tracked end

			if hookTracker.tracked then castState.hookLost = true end

			hookTracker.tracked = nil
			return hookTracker.byName()
		end

		local function getWaterLevel()
			local ok, result = pcall(function()
				local env = workspace:FindFirstChild("Env")
				env = env and env:FindFirstChild("WaterStuff")
				env = env and env:FindFirstChild("Falls")
				return env and env.Position.Y or nil
			end)

			if ok and type(result) == "number" then return result end
			return castSettings.waterLevelFallback
		end

		local function isWaterHit(hit, waterLevel)
			if not hit or not hit.Instance then return true end
			local instance = hit.Instance
			if not instance.CanCollide then return true end

			if instance.Transparency == 1 then return true end
			return hit.Position.Y < waterLevel + 0.3
		end

		-- pick a spot on the water to cast at
		local function findCastTarget(rootPart)
			local waterLevel = getWaterLevel()
			local position = rootPart.Position
			local lookVector = rootPart.CFrame.LookVector
			local flatLook = Vector3.new(lookVector.X, 0, lookVector.Z)
			local unit = flatLook.Magnitude > 0.001 and flatLook.Unit or Vector3.new(0, 0, -1)
			local raycastParams = RaycastParams.new()
			raycastParams.FilterType = Enum.RaycastFilterType.Exclude
			raycastParams.FilterDescendantsInstances = { rootPart.Parent }
			local bestScore = math.huge
			local height = math.max(position.Y - waterLevel, 0)
			local distances = {}

			for i, factor in ipairs(aimSettings.factors) do
				distances[i] = math.max(aimSettings.minDistance, height * factor)
			end

			local best

			for i, distance in ipairs(distances) do
				for _, angle in ipairs(aimSettings.angles) do
					local radians = math.rad(angle)
					local cosA = math.cos(radians)
					local sinA = math.sin(radians)
					local point = position + Vector3.new(unit.X * cosA - unit.Z * sinA, 0, unit.X * sinA + unit.Z * cosA).Unit * distance
					local probeStart = Vector3.new(point.X, math.max(position.Y + 15, waterLevel + 25), point.Z)

					if isWaterHit(workspace:Raycast(probeStart, Vector3.new(0, -(probeStart.Y - waterLevel - 5), 0), raycastParams), waterLevel) then
						local penalty = (i - 1) * aimSettings.orderPenalty
						local score = math.abs(angle) + penalty

						if score < bestScore then
							best = Vector3.new(point.X, waterLevel, point.Z)
							bestScore = score
						end
					end
				end

				if best and bestScore < aimSettings.goodScore then break end
			end

			if best then return best end
			local fallbackPoint = position + unit * distances[1]
			return Vector3.new(fallbackPoint.X, waterLevel, fallbackPoint.Z)
		end

		-- keep the camera facing the water
		local function lockCamera(spotCFrame, shouldContinue)
			local noop = { stop = function()
			end }

			if fishing.ShiftLock == false then return noop end

			if not workspace.CurrentCamera then return noop end
			local lookVector = spotCFrame.LookVector
			local flatLook = Vector3.new(lookVector.X, 0, lookVector.Z)
			local unit = flatLook.Magnitude > 0.001 and flatLook.Unit or Vector3.new(0, 0, -1)
			local rightVector = spotCFrame.RightVector
			local flatRight = Vector3.new(rightVector.X, 0, rightVector.Z)
			local right = flatRight.Magnitude > 0.001 and flatRight.Unit or Vector3.new(1, 0, 0)
			local lookTarget = spotCFrame.Position + unit * cameraSettings.lookAhead
			local focusPoint = Vector3.new(lookTarget.X, getWaterLevel(), lookTarget.Z)
			local connection

			local function restoreCamera()
				pcall(function()
					local currentCamera = workspace.CurrentCamera
					if not currentCamera then return end
					currentCamera.CameraType = Enum.CameraType.Custom
					local subject = localPlayer.Character
					subject = subject and subject:FindFirstChildOfClass("Humanoid")

					if subject then currentCamera.CameraSubject = subject end
				end)

				pcall(function()
					UserInputService.MouseBehavior = Enum.MouseBehavior.Default
				end)
			end

			local function stop()
				if connection then
					connection:Disconnect()
					connection = nil
				end

				restoreCamera()
			end

			connection = RunService.Heartbeat:Connect(function()
				if not running or not shouldContinue() then
					stop()
					return
				end
				local currentCamera = workspace.CurrentCamera
				local character = localPlayer.Character
				local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
				character = character and character:FindFirstChildOfClass("Humanoid")
				if not currentCamera or not humanoidRootPart or not character or character.Health <= 0 then
					return
				end

				if currentCamera.CameraType ~= Enum.CameraType.Scriptable then
					currentCamera.CameraType = Enum.CameraType.Scriptable
				end

				local back = unit * cameraSettings.distance
				currentCamera.CFrame = CFrame.lookAt(humanoidRootPart.Position + Vector3.new(0, cameraSettings.eyeHeight, 0) - back + right * cameraSettings.shoulder, focusPoint)
				local mouseBehavior = (cursorReleaseDepth > 0 or cursorReleased) and Enum.MouseBehavior.Default or Enum.MouseBehavior.LockCenter

				if UserInputService.MouseBehavior ~= mouseBehavior then
					UserInputService.MouseBehavior = mouseBehavior
				end
			end)

			return { stop = stop }
		end

		-- casting
		local function pressRod(rod)
			if rod and pcall(rod.Activate, rod) then return "Activate" end

			if mouse1press and pcall(mouse1press) then return "mouse1press" end
			return nil
		end

		local function releaseRod(rod)
			if rod and pcall(rod.Deactivate, rod) then return "Deactivate" end

			if mouse1release and pcall(mouse1release) then return "mouse1release" end
			return nil
		end

		local function findBaitButton(text)
			local baitGui = localPlayer:FindFirstChild("PlayerGui")
			baitGui = baitGui and baitGui:FindFirstChild(baitSettings.guiName)
			if not baitGui then return nil, nil end
			local descendants = baitGui:GetDescendants()

			for _, descendant in ipairs(descendants) do
				if descendant:IsA("GuiButton") and descendant.Name == text then return descendant, baitGui end
			end

			for _, descendant in ipairs(descendants) do
				if (descendant:IsA("TextLabel") or descendant:IsA("TextButton")) and string.find(descendant.Text, text, 1, true) then
					while descendant and descendant ~= baitGui do
						if descendant:IsA("GuiButton") then return descendant, baitGui end
						descendant = descendant.Parent
					end
				end
			end

			return nil, baitGui
		end

		local function clickBaitButton(text)
			local button, gui = findBaitButton(text)
			if not button then return false end

			if getconnections then
				local ok, result = pcall(function()
					local fired = 0

					for _, connection in ipairs(getconnections(button.MouseButton1Click)) do
						pcall(function()
							connection:Fire()
						end)

						fired += 1
					end

					return fired
				end)

				if ok and type(result) == "number" and result > 0 then return true end
			end

			if not mousemoveabs or not mouse1click then return false end
			local wasEnabled = gui.Enabled

			local ok = withFreeCursor(function()
				gui.Enabled = true
				task.wait()
				local center = button.AbsolutePosition + button.AbsoluteSize / 2
				local guiInset = GuiService:GetGuiInset()
				mousemoveabs(center.X + guiInset.X, center.Y + guiInset.Y)
				task.wait()
				mouse1click()
			end)

			pcall(function()
				gui.Enabled = wasEnabled
			end)

			return ok == true
		end

		local function setMouseAim(position)
			local aimCFrame = CFrame.new(position)

			for _, globals in ipairs(castState.aimGlobals()) do
				pcall(function()
					local kind = typeof(globals.MouseCF)

					if globals.MouseCF == nil or kind == "CFrame" then
						globals.MouseCF = aimCFrame
					end
				end)
			end
		end

		local function holdAim(position)
			if castState.stopAim then castState.stopAim() end

			local active = true
			castState.aimSteals = 0
			setMouseAim(position)

			task.spawn(function()
				while active and running do
					for _, globals in ipairs(castState.aimGlobals()) do
						local ok, result = pcall(function()
							return globals.MouseCF
						end)

						if ok and typeof(result) == "CFrame" and (result.Position - position).Magnitude > 1 then
							castState.aimSteals = castState.aimSteals + 1
						end
					end

					setMouseAim(position)
					task.wait(castSettings.aimHoldInterval)
				end
			end)

			castState.stopAim = function()
				active = false
			end

			return castState.stopAim
		end

		local function resetCast()
			castState.reelPending = false
			castState.casting = false
			castState.biteAt = nil
			castState.hookSeenAt = nil

			castState.nextCastAt = os.clock() + castSettings.retryDelay
			local character = localPlayer.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local rod = getBestRod()

			if rod and character and rod.Parent == character then releaseRod(rod) end

			if humanoid then pcall(humanoid.UnequipTools, humanoid) end

			hookTracker.tracked = nil

			task.delay(castSettings.hookSweepDelay, function()
				if castState.casting then return end
				local hook = getHook()

				if hook then pcall(hook.Destroy, hook) end
			end)
		end

		local function castBlockedReason(character, humanoid)
			if humanoid.FloorMaterial == Enum.Material.Air then return "in the air" end

			if castState.readGlobal("canuse") == false then return "canuse false" end
			local check = castState.readGlobal("check")

			if check then
				local ok, result = pcall(function()
					return check:inspect(character)
				end)

				if ok and result == false then return "inspect false" end
			end

			return nil
		end

		local function warnNoHook(bait, inputMethod)
			if os.clock() < lastBaitWarnAt then return end
			lastBaitWarnAt = os.clock() + 30
			local character = localPlayer.Character
			local floorInfo = character and character:FindFirstChildOfClass("Humanoid")
			floorInfo = floorInfo and tostring(floorInfo.FloorMaterial) or "no humanoid"
			local canuse = castState.readGlobal("canuse")
			local check = castState.readGlobal("check")

			local ok, result = pcall(function()
				return check:inspect(character)
			end)

			local kind = typeof(castState.readGlobal("MouseCF"))
			local globalCount = #castState.aimGlobals()
			local effectNames = {}

			pcall(function()
				local effects = hookTracker.folder()
				if not effects then
					effectNames[1] = "<no Effects folder>"
					return
				end

				for i, child in ipairs(effects:GetChildren()) do
					if i > 8 then
						effectNames[#effectNames + 1] = "..."
						break
					else
						effectNames[#effectNames + 1] = child.Name
					end
				end
			end)

			warn("[Fishing] Cast produced no hook. bait=" .. tostring(bait) .. " baitCount=" .. tostring(countItem(bait)) .. " input=" .. tostring(inputMethod) .. " floor=" .. floorInfo .. " canuse=" .. tostring(canuse) .. " inspect=" .. (ok and tostring(result) or "unreadable") .. " mouseCF=" .. tostring(kind) .. " globalTables=" .. tostring(globalCount) .. " effects=[" .. table.concat(effectNames, ", ") .. "]")
		end

		local function traceHook(hook, rootPart, rod)
			task.spawn(function()
				local startedAt = os.clock()
				local distance = 0
				local maxDistance = 0
				local minY = math.huge
				local firstY
				local lastY = 0
				local maxFlatDistance = 0
				local firstPos
				local lastPos
				local flightDir
				local firstDistance
				local moved = false
				local airborne = false
				local rodUnequipped = false
				local character = rootPart.Parent
				local moveEvents = 0
				local maxMove = 0
				local connections = {}
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")

				if humanoid then
					table.insert(connections, humanoid:GetPropertyChangedSignal("MoveDirection"):Connect(function()
						local moveMagnitude = humanoid.MoveDirection.Magnitude

						if moveMagnitude > 0 then
							moveEvents += 1
							maxMove = math.max(maxMove, moveMagnitude)
							moved = true
						end
					end))

					table.insert(connections, humanoid:GetPropertyChangedSignal("FloorMaterial"):Connect(function()
						if humanoid.FloorMaterial == Enum.Material.Air then
							airborne = true
						end
					end))
				end

				if rod then
					table.insert(connections, rod:GetPropertyChangedSignal("Parent"):Connect(function()
						if rod.Parent ~= character then rodUnequipped = true end
					end))
				end

				local bitten = false

				while running and hook.Parent do
					if not pcall(function()
						local position = hook:IsA("BasePart") and hook.Position or hook:GetPivot().Position
						distance = (position - rootPart.Position).Magnitude
						maxDistance = math.max(maxDistance, distance)
						minY = math.min(minY, position.Y)
						lastY = position.Y
						maxFlatDistance = math.max(maxFlatDistance, Vector3.new(position.X - rootPart.Position.X, 0, position.Z - rootPart.Position.Z).Magnitude)
						firstY = firstY or position.Y
						lastPos = position
						firstDistance = firstDistance or distance

						if not firstPos then
							firstPos = position
						elseif not flightDir and (position - firstPos).Magnitude > 3 then
							flightDir = (position - firstPos).Unit
						end

						local hum = character and character:FindFirstChildOfClass("Humanoid")

						if hum then
							if hum.MoveDirection.Magnitude > 0 then moved = true end

							if hum.FloorMaterial == Enum.Material.Air then
								airborne = true
							end
						end

						if rod and rod.Parent ~= character then rodUnequipped = true end
					end) then
						break
					end

					if castState.biteAt or castState.reelPending then bitten = true end

					task.wait()
				end

				for _, connection in ipairs(connections) do
					pcall(function()
						connection:Disconnect()
					end)
				end

				if bitten then return end
				local goalDistance = 0

				if castState.goal then
					goalDistance = Vector3.new(castState.goal.X - rootPart.Position.X, 0, castState.goal.Z - rootPart.Position.Z).Magnitude
				end

				local launchAngle = -1

				if flightDir and castState.goal then
					local toGoal = castState.goal - rootPart.Position

					if toGoal.Magnitude > 0 then
						local dot = math.clamp(flightDir:Dot(toGoal.Unit), -1, 1)
						launchAngle = math.deg(math.acos(dot))
					end
				end

				local nearestPart = "none"

				if lastPos then
					pcall(function()
						for _, part in ipairs(workspace:GetPartBoundsInRadius(lastPos, 8)) do
							if not part:IsDescendantOf(hook) and part ~= hook then
								nearestPart = part.Name .. "/" .. tostring(part.CollisionGroup)
								break
							end
						end
					end)
				end

				local warn = warn
				local lifetimeText = string.format(" lifetime=%.1fs", os.clock() - startedAt)
				local endDistanceText = string.format(" endDistance=%.0f", distance)
				local maxDistanceText = string.format(" maxDistance=%.0f", maxDistance)
				local maxFlatText = string.format(" maxFlat=%.0f", maxFlatDistance)
				local lowestYText = string.format(" lowestY=%.0f", minY)
				local startYText = string.format(" startY=%.0f", firstY or 0)
				local endYText = string.format(" endY=%.0f", lastY)
				local surfaceYText = string.format(" surfaceY=%.0f", getWaterLevel())
				local goalOutText = string.format(" goalOut=%.0f", goalDistance)
				local rootYText = string.format(" rootY=%.0f", rootPart.Position.Y)
				local movedText = tostring(moved)
				local moveFiresText = string.format(" moveFires=%d", moveEvents)
				local moveMaxText = string.format(" moveMax=%.2f", maxMove)
				local airborneText = tostring(airborne)
				local rodUnequippedText = tostring(rodUnequipped)
				local aimStealsText = string.format(" aimSteals=%d", castState.aimSteals or 0)
				local launchOffText = string.format(" launchOff=%.0f", launchAngle)

				local startDistance = firstDistance or -1
				local nearEndText = " nearEnd=" .. nearestPart .. " hook=" .. hook.Name
				warn("[Fishing] Hook gone with no bite." .. lifetimeText .. endDistanceText .. maxDistanceText .. maxFlatText .. lowestYText .. startYText .. endYText .. surfaceYText .. goalOutText .. rootYText .. " moved=" .. movedText .. moveFiresText .. moveMaxText .. " air=" .. airborneText .. " rodOut=" .. rodUnequippedText .. aimStealsText .. launchOffText .. string.format(" birthDist=%.0f", startDistance) .. nearEndText)
			end)
		end

		local function cast(rootPart, rod)
			castState.casting = true
			castState.biteAt = nil
			local bait = pickBait()

			if not clickBaitButton(bait) then
				runStats.status("Can't select bait")

				if lastBaitWarnAt <= os.clock() then
					lastBaitWarnAt = os.clock() + 30
					warn("[Fishing] No bait button for " .. bait .. " in " .. baitSettings.guiName .. " (the client only builds one for a bait the account owns, and only while the rod is equipped).")
				end

				castState.casting = false
				return
			end

			local ok, goal = pcall(findCastTarget, rootPart)
			if not ok or not goal then
				castState.casting = false
				return
			end
			castState.goal = goal
			local effectsBefore = hookTracker.snapshot()
			hookTracker.tracked = nil
			local stopAim = holdAim(goal)
			task.wait(castSettings.aimSettle)
			local inputMethod = pressRod(rod)
			task.wait(castSettings.chargeSeconds)
			releaseRod(rod)
			task.delay(castSettings.aimHoldAfterThrow, stopAim)
			local deadline = os.clock() + castSettings.hookAppearSeconds
			local hook = hookTracker.appearedSince(effectsBefore, rootPart)

			while not hook and os.clock() < deadline do
				task.wait(castSettings.tickInterval)
				hook = hookTracker.appearedSince(effectsBefore, rootPart)
			end

			hookTracker.tracked = hook
			castState.casting = false
			castState.nextCastAt = os.clock() + castSettings.retryDelay

			if hook then
				runStats.increment("casts")
				traceHook(hook, rootPart, rod)
				return
			end

			warnNoHook(bait, inputMethod)
			resetCast()
		end

		-- reel minigame
		local function getReelGui()
			local playerGui = localPlayer:FindFirstChild("PlayerGui")
			return playerGui and playerGui:FindFirstChild(reelSettings.guiName) or nil
		end

		local function getReelInfoText(reelGui)
			local ok, result = pcall(function()
				local infoText = reelGui:FindFirstChild("InfoText", true)
				return infoText and infoText:IsA("TextLabel") and infoText.Text or nil
			end)

			if ok then return result end
			return nil
		end

		local function getReelBar(reelGui)
			local frame = reelGui:FindFirstChild("Frame")
			if not frame then return nil end
			local player = frame:FindFirstChild("Player")
			local goal = frame:FindFirstChild("Goal")
			local time = frame:FindFirstChild("Time")
			if not player or not goal then return nil end
			return player, goal, time and time:FindFirstChild("Fill") or nil
		end

		local function stopReelSounds()
			pcall(function()
				for _, child in ipairs(ReplicatedStorage.Fishing.Assets.SFX.InputSFX:GetChildren()) do
					if child:IsA("Sound") and child.Looped and child.IsPlaying then
						child:Stop()
					end
				end
			end)
		end

		local function playReelMinigame(reelGui, rod)
			castState.reelPending = true
			runStats.status("Reeling one in")
			local bar = reelSettings.bar
			local playerMarker, goalMarker, timeFill = getReelBar(reelGui)
			local acceleration = (tonumber(rod:GetAttribute("Acceleration")) or bar.fallbackAcceleration) / bar.max
			local holding = false

			local function setHolding(hold)
				if hold == holding then return end
				holding = hold

				if hold then
					pressRod(rod)
				else
					releaseRod(rod)
				end
			end

			local startedAt = os.clock()
			local deadline = startedAt + reelSettings.maxSeconds
			local velocity = 0
			local lastFill
			local lastPlayerY

			while running and reelGui.Parent and os.clock() < deadline do
				local dt = RunService.RenderStepped:Wait()

				local ok, playerY, goalY, fill = pcall(function()
					if not playerMarker then return nil end
					return playerMarker.Position.Y.Scale, goalMarker.Position.Y.Scale, timeFill and timeFill.Size.Y.Scale or nil
				end)

				if not ok or not playerY then
					local infoText = getReelInfoText(reelGui)

					if infoText == reelSettings.holdText then
						setHolding(true)
					elseif infoText == reelSettings.releaseText then
						setHolding(false)
					end
				else
					lastFill = fill or lastFill

					if lastPlayerY then
						velocity = (playerY - lastPlayerY) / math.max(dt, 0.0041666666666666666)
					end

					local gap = goalY - playerY

					if math.abs(gap) <= bar.holdWindow then
						local predicted = gap - velocity * bar.lookahead

						if bar.deadzone < predicted then
							setHolding(false)
							lastPlayerY = playerY
						elseif not (predicted < -bar.deadzone) then
							lastPlayerY = playerY
						else
							setHolding(true)
							lastPlayerY = playerY
						end
					else
						local stopTime = math.abs(velocity) / acceleration
						local stopGap = goalY - playerY + velocity * stopTime - 0.5 * acceleration * stopTime * stopTime * (velocity > 0 and 1 or -1)

						if gap > 0 then
							setHolding(not (stopGap > bar.brakeDeadzone))
							lastPlayerY = playerY
						else
							setHolding(stopGap < -bar.brakeDeadzone)
							lastPlayerY = playerY
						end
					end
				end
			end

			setHolding(false)
			stopReelSounds()
			castState.reelPending = false
			castState.biteAt = nil

			if lastFill and lastFill >= bar.wonFill then
				runStats.increment("fish")
				castState.caughtSinceSell = castState.caughtSinceSell + 1
			else
				warn("[Fishing] " .. ("Lost a reel minigame after %.1fs (bar %s, accel %.2f)."):format(os.clock() - startedAt, lastFill and string.format("%.2f", lastFill) or "unreadable", acceleration))
			end

			local settleDeadline = os.clock() + hookTracker.settleSeconds

			while running and os.clock() < settleDeadline and hookTracker.stillOut() do
				task.wait(castSettings.tickInterval)
			end

			if hookTracker.stillOut() then
				resetCast()
			else
				castState.casting = false
				castState.hookSeenAt = nil
				hookTracker.tracked = nil
				castState.nextCastAt = os.clock() + castSettings.retryDelay
			end

			runStats.status("Fishing")
		end

		castState.startAntiAfkGate = function(shouldContinue)
			if not pauseAntiAfk or not resumeAntiAfk then return end

			task.spawn(function()
				local paused = false

				while running and shouldContinue() do
					local idle = not Travel.isMoving()

					if idle ~= paused then
						if idle then
							pauseAntiAfk()
							paused = idle
						else
							resumeAntiAfk()
							paused = idle
						end
					end

					task.wait()
				end

				if paused then resumeAntiAfk() end
			end)
		end

		castState.startIdleKeepAlive = function(shouldContinue)
			local f13 = Enum.KeyCode.F13

			task.spawn(function()
				local virtualInputManager = Instance.new("VirtualInputManager")

				while running and shouldContinue() do
					task.wait(240)
					if not running or not shouldContinue() then return end

					if not Travel.isMoving() then
						pcall(function()
							virtualInputManager:SendKeyEvent(true, f13, false, game)
							task.wait(0.08)
							virtualInputManager:SendKeyEvent(false, f13, false, game)
						end)
					end
				end
			end)
		end

		-- one fishing tick: cast, wait for a bite, reel in
		local function fishTick()
			if castState.reelPending then return end
			local character = localPlayer.Character
			if not character then return end
			local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if not humanoidRootPart or not humanoid then return end
			local rod = getBestRod()
			if not rod then return end

			if rod.Parent ~= character then
				pcall(humanoid.EquipTool, humanoid, rod)
				task.wait(castSettings.rodEquipSettle)
				return
			end

			local reelGui = getReelGui()

			if reelGui then
				if not castState.biteAt then
					castState.biteAt = os.clock()
					castState.hookSeenAt = os.clock()
				end

				playReelMinigame(reelGui, rod)
				return
			end

			castState.biteAt = nil

			if not getHook() then
				castState.hookSeenAt = nil
				if castState.casting then return end

				if castState.hookLost then
					castState.hookLost = false
					resetCast()
					return
				end

				if os.clock() < castState.nextCastAt then return end
				local blockReason = castBlockedReason(character, humanoid)

				if blockReason then
					castState.blockedSince = castState.blockedSince or os.clock()
					local blockedFor = os.clock() - castState.blockedSince
					runStats.status("Client won't cast (" .. blockReason .. ")")
					local longBlocked = blockedFor >= rodWait.warnAfter
					local shouldWarn

					if longBlocked then
						shouldWarn = os.clock() >= rodWait.nextWarnAt
					else
						shouldWarn = longBlocked
					end

					if shouldWarn then
						rodWait.nextWarnAt = os.clock() + 30
						warn("[Fishing] " .. ("The client has refused to cast for %.0fs (%s)."):format(blockedFor, blockReason))
					end

					if blockedFor < rodWait.maxWait then return end
					castState.blockedSince = nil
				else
					castState.blockedSince = nil
				end

				cast(humanoidRootPart, rod)
				return
			end

			if not castState.hookSeenAt then castState.hookSeenAt = os.clock() end

			if castSettings.hookIdleTimeout <= os.clock() - castState.hookSeenAt then
				resetCast()
			end
		end

		-- buying bait / a rod
		local function getCurrency()
			local statsFolder = ReplicatedStorage:FindFirstChild("Stats" .. localPlayer.Name)
			local peli = statsFolder and statsFolder:FindFirstChild("Stats") and statsFolder.Stats:FindFirstChild("Peli")
			return peli and tonumber(peli.Value) or 0
		end

		local baitRetryAt = 0

		local function countAllBait()
			local total = 0

			for _, bait in ipairs(baitPriority) do
				total += countItem(bait)
			end

			return total
		end

		local function getShopItemCFrame(itemName)
			local item = workspace:FindFirstChild("BuyableItems")
			item = item and item:FindFirstChild(itemName)
			local part = item and (item:IsA("BasePart") and item or item:FindFirstChildWhichIsA("BasePart"))
			return (part and part.CFrame or baitShopCFrame) + Vector3.new(0, spot.standHeight, 0)
		end

		local function buyBait(amount)
			local buyableItems = workspace:FindFirstChild("BuyableItems")
			local commonFishBait = buyableItems and buyableItems:FindFirstChild("Common Fish Bait")
			local events = ReplicatedStorage:FindFirstChild("Events")
			local shop = events and events:FindFirstChild("Shop")
			if not commonFishBait or not shop then
				warn("[Fishing] no BuyableItems.Common Fish Bait or Events.Shop - cannot buy bait.")
				return 0
			end
			local before = countItem("Common Fish Bait")

			pcall(function()
				shop:InvokeServer(commonFishBait, amount)
			end)

			task.wait(1)
			local bought = countItem("Common Fish Bait") - before
			local misses = 0

			while bought < amount and misses < baitSettings.maxMisses do
				if not pcall(function()
					shop:InvokeServer(commonFishBait, 1)
				end) then
					break
				end

				task.wait(baitSettings.buyInterval)
				local nowBought = countItem("Common Fish Bait") - before

				if bought < nowBought then
					misses = 0
					bought = nowBought
				else
					misses += 1
				end
			end

			return bought
		end

		local function resupplyBait(shouldContinue, returnCFrame)
			if getCurrency() < baitSettings.buyPeli then
				warn("[Fishing] not enough peli for bait (needs " .. baitSettings.buyPeli .. ") - waiting " .. baitSettings.retryBackoff .. "s. Auto Sell Fish is what pays for this.")
				baitRetryAt = os.clock() + baitSettings.retryBackoff
				runStats.status("Broke - waiting to sell")
				return
			end

			if not shouldContinue() then return end
			runStats.status("Buying bait")
			local stallCFrame = getShopItemCFrame("Common Fish Bait")
			local rootPart = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
			local needsFlight = not rootPart or (rootPart.Position - stallCFrame.Position).Magnitude > baitSettings.shopReach

			if needsFlight then
				log("Bait stall is out of reach from the spot - flying to it.")
				flyTo(stallCFrame)
				if not shouldContinue() then return end
			end

			local bought = buyBait(baitSettings.buyAmount)

			if bought > 0 then
				runStats.increment("baitruns")
				log("Bought " .. bought .. " Common Fish Bait.")
			else
				warn("[Fishing] bought no bait - waiting " .. baitSettings.retryBackoff .. "s before trying again. If this repeats from the spot, the stall isn't in range of it any more.")
				baitRetryAt = os.clock() + baitSettings.retryBackoff
			end

			if not shouldContinue() or not needsFlight then return end
			runStats.status("Returning to the spot")
			flyTo(returnCFrame)
		end

		local function buyRod(shouldContinue)
			runStats.status("Buying a rod")
			if not goTo(getShopItemCFrame("Fishing Rod"), shouldContinue) then return false end
			local invoked = false

			pcall(function()
				local buyableItems = workspace:WaitForChild("BuyableItems", 5)
				buyableItems = buyableItems and buyableItems:WaitForChild("Fishing Rod", 10)
				local events = ReplicatedStorage:WaitForChild("Events", 5)
				events = events and events:WaitForChild("Shop", 10)

				if buyableItems and events then
					events:InvokeServer(buyableItems, 1)
					invoked = true
				end
			end)

			task.wait(1)

			if invoked then
				fishing.BuyRod = false
				log("Invoked the shop for a Fishing Rod.")
			else
				warn("[Fishing] could not reach BuyableItems.Fishing Rod or Events.Shop.")
			end

			return invoked
		end

		-- selling fish
		local function shouldSellRarity(rarity)
			local sellRarities = fishing.SellRarities
			local setting = type(sellRarities) == "table" and sellRarities[rarity] or nil
			if type(setting) == "boolean" then return setting end
			return sellSettings.defaults[rarity] == true
		end

		local sellRetryAt = 0
		local capLogged = false

		local function shouldSell()
			if fishing.SellFish == false then return false end

			if castState.caughtSinceSell < sellSettings.minFish then return false end

			if os.clock() < sellRetryAt then return false end
			local anyEnabled = false

			for k in pairs(sellSettings.defaults) do
				if shouldSellRarity(k) then
					anyEnabled = true
					break
				end
			end

			if not anyEnabled then return false end

			if sellSettings.peliCap <= getCurrency() then
				sellRetryAt = os.clock() + sellSettings.cappedBackoff

				if not capLogged then
					capLogged = true
					log("Peli cap reached (" .. sellSettings.peliCap .. ") - keeping the catch instead of selling.")
				end

				return false
			end

			capLogged = false
			return true
		end

		local function sellFish(shouldContinue)
			local remote = ReplicatedStorage:FindFirstChild(sellSettings.remoteName) or ReplicatedStorage:WaitForChild(sellSettings.remoteName, 5)

			if not remote then
				warn("[Fishing] no ReplicatedStorage." .. sellSettings.remoteName .. " - Auto Sell Fish can't run (renamed by an update?).")
				sellRetryAt = os.clock() + sellSettings.cappedBackoff
				return
			end

			runStats.status("Selling fish")
			if not goTo(sellSpotCFrame, shouldContinue) then return end

			for _, fish in ipairs(sellSettings.sequence) do
				if not (running and shouldContinue()) then return end

				if shouldSellRarity(fish.rarity) then
					local function sellOnce()
						pcall(function()
							remote:InvokeServer({ Fish = fish.name, All = false, Method = "SellFish" })
						end)

						task.wait(sellSettings.invokeInterval)
					end

					local count = countItem(fish.name)

					if count <= 0 then
						sellOnce()
					else
						local misses = 0

						while count > 0 and misses < sellSettings.maxMisses and running and shouldContinue() do
							sellOnce()
							local newCount = countItem(fish.name)

							if count <= newCount then
								misses += 1
								count = newCount
							else
								misses = 0
								count = newCount
							end
						end
					end
				end
			end

			castState.caughtSinceSell = 0
			runStats.increment("sellruns")
		end

		-- fruits we fish up
		local fruitQueue = FruitInventory.createFruitQueue("Fishing")
		local nextSweepAt = 0

		local function handleFruit(fruitName)
			return FruitInventory.handleFruitGeneric("Fishing", runStats, fruitName, { dropPingCliffOnly = true, webhookUrl = fishing.WebhookUrl })
		end

		local function shouldStoreFruit()
			if fishing.StoreFruit == false then return false end

			if castState.reelPending or castState.biteAt then return false end

			if pauseCount > 0 or Core.IsErrorHoldActive() then return false end

			if os.clock() >= nextSweepAt then
				nextSweepAt = os.clock() + fruitSettings.sweepInterval
				pcall(fruitQueue.sweep)
			end

			return #fruitQueue.queue > 0
		end

		local function storeFruits(shouldContinue)
			runStats.status("Storing fruit")
			local ok, result = pcall(FruitInventory.drainFruitQueue, fruitQueue, handleFruit, shouldContinue, "Fishing")
			if not ok then
				warn("[Fishing] fruit drain: " .. tostring(result))
				return
			end

			if type(result) == "table" and #result > 0 then
				pcall(fruitQueue.release, result)
			end
		end

		local refaceAt = 0
		local pendingTurn

		-- re-facing when the turn setting changes
		local function shouldReface(currentTurn)
			local turn = getSpotTurn()
			if turn == currentTurn then
				pendingTurn = nil
				return false
			end

			if pendingTurn ~= turn then
				pendingTurn = turn
				refaceAt = os.clock() + spot.refaceSettle
				return false
			end

			if castState.reelPending or castState.biteAt then return false end

			if pauseCount > 0 or Core.IsErrorHoldActive() then return false end
			return os.clock() >= refaceAt
		end

		AutoMerchant.Init({
			LocalPlayer = localPlayer,
			Teleport = function(position)
				flyTo(CFrame.new(position))
			end,
			Notify = function(title, message)
				log(title .. ": " .. message)
			end,
			RunService = RunService,
			IsTaskFree = function()
				return true
			end,
			BeginTask = function()
				if pauseAntiAfk then pauseAntiAfk() end
			end,
			EndTask = function()
				if resumeAntiAfk then resumeAntiAfk() end
			end,
			PauseFishing = function()
				pauseCount += 1
				resetCast()

				if cameraHold then
					cameraHold.stop()
					cameraHold = nil
				end

				if positionHold then
					positionHold.stop()
					positionHold = nil
				end

				return true
			end,
			ResumeFishing = function()
				if pauseCount > 0 then pauseCount -= 1 end
			end,
			GetCurrency = getCurrency,
			CurrencyLabel = "Peli",
			WebhookUsername = "Wyvern Fishing",
		})

		-- traveling merchant
		local function merchantDue()
			if fishing.MerchantCheckEnabled ~= true then return false end
			return AutoMerchant.IsRunDue() == true
		end

		local function runMerchant()
			AutoMerchant.SetSelectedItems(fishing.MerchantCheckItems or {})
			if not loaderFlagB then return end
			AutoMerchant.SetWebhookUrl(fishing.WebhookUrl or "")
			runStats.status("Checking Traveling Merchant")
			AutoMerchant.Execute()
		end

		-- main loop
		local function fishUntilInterrupted(shouldContinue, positionHold, spotCFrame, expectedTurn)
			local nextBaitCheck = os.clock() + baitSettings.checkInterval
			local settledStatus = true

			while running and shouldContinue() do
				if os.clock() >= nextBaitCheck then
					nextBaitCheck = os.clock() + baitSettings.checkInterval
					if fishing.BuyBait ~= false and countAllBait() <= 0 and os.clock() >= baitRetryAt then
						log("Out of bait - buying more.")
						return "resupply"
					end
				end

				if shouldStoreFruit() then return "fruit" end

				if shouldReface(expectedTurn) then
					log("Turn changed to " .. string.format("%.0f", getSpotTurn()) .. "deg - re-facing.")
					return "reface"
				end

				if shouldSell() then
					log("Caught " .. castState.caughtSinceSell .. " fish - taking them to the buyer.")
					return "sell"
				end

				if merchantDue() then return "merchant" end

				if pauseCount > 0 or Core.IsErrorHoldActive() then
					if not castState.paused then
						castState.paused = true
						resetCast()
						runStats.status(pauseCount > 0 and "Paused" or "Error hold")
					end
				elseif not positionHold.isSettled() then
					runStats.status("Knocked off - resettling")
					settledStatus = false
				else
					if not settledStatus then
						runStats.status("Fishing")
						settledStatus = true
					end

					if castState.paused then
						castState.paused = false
						runStats.status("Fishing")
					end

					local ok, err = pcall(fishTick)

					if not ok and os.clock() >= lastBaitWarnAt then
						lastBaitWarnAt = os.clock() + 20
						warn("[Fishing] fishTick errored: " .. tostring(err))
					end
				end

				task.wait(castSettings.tickInterval)
			end

			return nil
		end

		local function stopTravel()
			Travel.stopAllFlight()
			Travel.stopMovement()
		end

		local function runSession(shouldContinue)
			pauseCount = 0
			castState.paused = false
			castState.startAntiAfkGate(shouldContinue)
			castState.startIdleKeepAlive(shouldContinue)
			local rodDeadline = os.clock() + castSettings.rodWaitSeconds

			while not getBestRod() and os.clock() < rodDeadline and shouldContinue() do
				task.wait(1)
			end

			if not getBestRod() and fishing.BuyRod == true and shouldContinue() then
				buyRod(shouldContinue)
			end

			if not getBestRod() then
				warn("[Fishing] No fishing rod in the backpack - nothing to fish with. Turn Auto Buy Rod on, or put one in the bag.")
				runStats.status("No fishing rod")

				while shouldContinue() do
					task.wait(5)
				end

				return
			end

			runStats.status("Travelling")
			Travel.startSkyWalkLoop(0.5)
			task.wait(travelSettings.geppoWarmup)
			Travel.stopSkyWalkLoop()

			while running and shouldContinue() do
				local spotCFrame, turn = getMySpotCFrame()

				if not goTo(spotCFrame, shouldContinue) then break end

				stopTravel()
				local hold = holdPosition(spotCFrame, shouldContinue)
				positionHold = hold
				local cam = lockCamera(spotCFrame, shouldContinue)
				cameraHold = cam
				local lookVector = spotCFrame.LookVector
				log("At spot " .. myIndex .. "/" .. fisherCount .. " - casting. Facing " .. string.format("%.0f", math.deg(math.atan2(lookVector.X, -lookVector.Z))) .. "deg (turn " .. string.format("%+.0f", turn) .. "deg).")
				runStats.status("Fishing")
				local reason = fishUntilInterrupted(shouldContinue, hold, spotCFrame, turn)
				cam.stop()
				cameraHold = nil
				hold.stop()
				resetCast()
				positionHold = nil

				if reason == "resupply" and shouldContinue() then
					resupplyBait(shouldContinue, spotCFrame)
				elseif reason == "fruit" and shouldContinue() then
					storeFruits(shouldContinue)
				elseif reason == "sell" and shouldContinue() then
					sellFish(shouldContinue)
				elseif reason == "merchant" and shouldContinue() then
					runMerchant()
				end
			end

			resetCast()
		end

		return {
			Enabled = function()
				return fishing.Enabled == true
			end,
			Status = function()
				return currentStatus
			end,
			Stop = function()
				running = false
				resetCast()

				if cameraHold then
					cameraHold.stop()
					cameraHold = nil
				end

				if positionHold then
					positionHold.stop()
					positionHold = nil
				end

				Travel.stopMovement()
				Travel.stopAllFlight()
				runStats.status("stopped")
				log("Stopped.")
			end,
			Run = function()
				if running then return end

				if not mySlot then
					warn("[Fishing] " .. localPlayer.Name .. " isn't in Config.Fishing.Roles - nothing to run. Fill in the Fishing tab's Roles section: one Fisher slot per account with a rod.")
					return
				end
				running = true

				if localPlayer.Character then
					keepOutOfPhysicsState(localPlayer.Character)
				end

				localPlayer.CharacterAdded:Connect(keepOutOfPhysicsState)
				log("Fishing starting for " .. localPlayer.Name .. " as " .. mySlot .. " (spot " .. myIndex .. " of " .. fisherCount .. ").")
				local startedAt = os.clock()

				runStats.poll("uptime", function()
					return os.clock() - startedAt
				end)

				if startAntiAfk then startAntiAfk() end

				Core.runWithDeathRecovery("Fishing", function(isAlive)
					runSession(isAlive)
				end, runStats)
			end,
		}
	end
end

defineModule("Fishing", createFishing)

----------------------------------------------------------------------------
-- BariCage: bari cage handling for the anchor role
----------------------------------------------------------------------------
local function createBariCage()
	local RunService = cloneref(game:GetService("RunService"))
	local localPlayer = cloneref(game:GetService("Players")).LocalPlayer
	local config
	local movement
	local attacks
	local roleShared

	local BariCage = { Init = function(options)
		local opts = options or {}
		config = opts.Config
		movement = opts.Movement
		attacks = opts.Attacks
		roleShared = opts.RoleShared
	end }

	local cageSize = Vector3.new(67.168952941894531, 31.336225509643555, 67.168952941894531)

	-- where the cage goes + its size
	local function getCageCFrame()
		local anchorCFrame = roleShared.anchorPointFor("Anchor")
		local rotation = anchorCFrame - anchorCFrame.Position
		return CFrame.new(anchorCFrame.Position - Vector3.new(0, positiveNumberOr(config.AnchorBariCageDepth, 50), 0)) * rotation
	end

	local function getBounds(instance)
		if instance:IsA("BasePart") then return instance.Position, instance.Size end

		if instance:IsA("Model") then
			local ok, cframe, size = pcall(instance.GetBoundingBox, instance)
			if ok and cframe and size then return cframe.Position, size end
		end

		return nil, nil
	end

	local function findCage()
		local projectiles = workspace:FindFirstChild("Projectiles")
		if not projectiles then return nil end
		local cagePos = getCageCFrame().Position
		local bestDistance = 250
		local cage
		local cagePosition
		local cageBoxSize

		for _, child in ipairs(projectiles:GetChildren()) do
			if child.Name == "Barrier" then
				local pos, size = getBounds(child)

				if pos then
					local magnitude = (pos - cagePos).Magnitude

					if magnitude <= bestDistance then
						bestDistance = magnitude
						cage = child
						cagePosition = pos
						cageBoxSize = size
					end
				end
			end
		end

		if not cage then return nil end
		return cage, cagePosition, cageBoxSize
	end

	local function isFullSize(size)
		return size and size.Y >= cageSize.Y * 0.95
	end

	local function isCageStill(cage, expectedPos)
		if not cage or not cage.Parent then return false end
		local current, pos = findCage()
		if current ~= cage or not pos then return false end
		return (pos - expectedPos).Magnitude <= 8
	end

	local function cageStandCFrame(center, size, offset, rotation)
		return CFrame.new(Vector3.new(center.X + offset.X, center.Y + size.Y / 2 + 3.5, center.Z + offset.Z)) * rotation
	end

	local function standOffset(role, caster, size)
		if role == caster then return Vector3.new() end
		size = size or cageSize
		return Vector3.new(math.min(size.X, size.Z) / 2 * 0.6 * 0.7, 0, 0)
	end

	local function anchorAttackEnabled(role, key)
		local anchorAttacks = config.AnchorAttacks and config.AnchorAttacks[role]
		if type(anchorAttacks) == "table" and anchorAttacks[key] ~= nil then
			return anchorAttacks[key] == true
		end
		return config[key] == true
	end

	local function findCageCaster()
		for _, anchorRole in ipairs(roleShared.ANCHOR_ROLES) do
			if roleShared.isRoleManned(anchorRole) and anchorAttackEnabled(anchorRole, "AnchorUseBariCage") then
				return anchorRole
			end
		end

		return nil
	end

	BariCage.isEnabled = function()
		return config.AnchorBariMode == true and roleShared.anchorOnlyMode() and findCageCaster() ~= nil
	end

	-- placing the cage and waiting for it to grow
	local function castCage()
		local character = localPlayer.Character
		if not character then return false end
		local castFrom = character:FindFirstChild("LeftFoot") or character:FindFirstChild("HumanoidRootPart")
		if not castFrom then return false end
		return attacks.placeBariCage(castFrom.CFrame)
	end

	local function waitForGrownCage(shouldContinue, onWait)
		local firstSeenAt

		while shouldContinue() do
			local cage, pos, size = findCage()

			if cage then
				firstSeenAt = firstSeenAt or os.clock()
				local ready = isFullSize(size) or os.clock() - firstSeenAt >= 20

				if ready then return cage, pos, size end
			end

			if onWait then onWait() end

			task.wait(1)
		end

		return nil
	end

	local function travelTo(target, shouldContinue, useBomu)
		local character = localPlayer.Character
		local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")

		if not humanoidRootPart or (humanoidRootPart.Position - target.Position).Magnitude > 400 then
			if useBomu then
				movement.moveWithBomuToCFrame(target, 100, 10, true, "raycast")
			else
				movement.moveWithGeppoToCFrame(target, 140, 10, true, "raycast")
			end

			if not shouldContinue() then return false end
		end

		movement.snapToCFrame(target, 0.4, false)
		if not shouldContinue() then return false end
		movement.startMovement(movement.hover, false)

		if useBomu then
			movement.startBomuLoop(1)
		else
			movement.startSkyWalkLoop(1)
		end

		return true
	end

	local function stopTravel(useBomu)
		if useBomu then
			movement.stopBomuLoop()
		else
			movement.stopSkyWalkLoop()
		end

		movement.stopMovement()
	end

	-- staying on top of the cage
	local function holdPost(post, shouldContinue)
		local position = post.Position
		local settled = true
		local resettleUntil = 0
		local connection

		local function stop()
			if connection then
				connection:Disconnect()
				connection = nil
			end
		end

		local function setPost(newPost)
			post = newPost
			position = newPost.Position
			settled = false
			resettleUntil = os.clock() + 0.5
		end

		connection = RunService.Heartbeat:Connect(function()
			if not shouldContinue() then
				stop()
				return
			end
			local character = localPlayer.Character
			local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not humanoidRootPart or not humanoid or humanoid.Health <= 0 then return end
			local now = os.clock()

			if (humanoidRootPart.Position - position).Magnitude > 8 then
				settled = false
				resettleUntil = now + 0.5
			end

			if now < resettleUntil then
				humanoidRootPart.AssemblyLinearVelocity = Vector3.new()
				humanoidRootPart.AssemblyAngularVelocity = Vector3.new()
				character:PivotTo(post)
			else
				settled = true
			end
		end)

		return {
			isSettled = function()
				return settled
			end,
			setPost = setPost,
			stop = stop,
		}
	end

	local physicsGuardStarted = false

	local function keepOutOfPhysicsState(character)
		local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
		if not humanoid then return end

		task.spawn(function()
			while humanoid.Parent do
				local stuck = not movement.isMoving()

				stuck = stuck and humanoid:GetState() == Enum.HumanoidStateType.Physics

				if stuck then
					humanoid.PlatformStand = false
					humanoid:ChangeState(Enum.HumanoidStateType.Running)
					humanoid.AutoRotate = true
				end

				task.wait(1)
			end
		end)
	end

	local function startPhysicsGuard()
		if physicsGuardStarted then return end
		physicsGuardStarted = true

		if localPlayer.Character then keepOutOfPhysicsState(localPlayer.Character) end

		localPlayer.CharacterAdded:Connect(keepOutOfPhysicsState)
	end

	local currentPost
	local currentHold
	local diving = false
	local savedCollisions

	local function setNoclip(enabled)
		local character = localPlayer.Character
		if not character then return end

		if enabled then
			savedCollisions = {}

			for _, descendant in ipairs(character:GetDescendants()) do
				if descendant:IsA("BasePart") then
					savedCollisions[descendant] = descendant.CanCollide
					descendant.CanCollide = false
				end
			end
		elseif savedCollisions then
			for k, wasCollidable in pairs(savedCollisions) do
				if k.Parent then k.CanCollide = wasCollidable end
			end

			savedCollisions = nil
		end
	end

	-- exports
	BariCage.duringMagmaRain = function(callback)
		local hold = currentHold
		local post = currentPost
		if not hold or not post then return pcall(callback) end
		local deadline = os.clock() + 5

		while diving and os.clock() < deadline do
			task.wait(0.2)
		end

		if diving then return pcall(callback) end
		diving = true
		setNoclip(true)
		hold.setPost(post.cframe * CFrame.new(0, -10, 0))
		movement.startSkyWalkLoop(1.5)
		task.wait(1)
		local ok, err = pcall(callback)
		movement.stopSkyWalkLoop()
		hold.setPost(post.cframe)
		task.wait(1)
		setNoclip(false)
		diving = false
		return ok, err
	end

	BariCage.holdOnCage = function(role, shouldContinue, stats, holdOptions)
		local useBomu = (holdOptions or {}).useBomuTravel == true
		startPhysicsGuard()

		task.spawn(function()
			while shouldContinue() do
				local caster = findCageCaster()
				if not caster then
					task.wait(2)
					continue
				end
				local isCaster = role == caster

				if isCaster and not findCage() then
					if stats then stats.status("Placing Bari Cage") end

					travelTo(getCageCFrame(), shouldContinue, useBomu)
					if not shouldContinue() then return end
					castCage()
				elseif not isCaster then
					if stats then stats.status("Waiting on Bari Cage") end

					travelTo(getCageCFrame(), shouldContinue, useBomu)
				end

				local cage, centre, size = waitForGrownCage(shouldContinue, function()
					if stats then
						stats.status(isCaster and "Growing Bari Cage" or "Waiting on Bari Cage")
					end
				end)

				if not cage then return end
				local anchorCFrame = roleShared.anchorPointFor("Anchor")
				local rotation = anchorCFrame - anchorCFrame.Position
				local post = cageStandCFrame(centre, size, standOffset(role, caster, size), rotation)
				if not travelTo(post, shouldContinue, useBomu) then return end
				stopTravel(useBomu)
				currentPost = { centre = centre, size = size, cframe = post }
				currentHold = holdPost(post, shouldContinue)

				if stats then stats.status("Holding (Bari Cage)") end

				while shouldContinue() and isCageStill(cage, centre) do
					task.wait(10)
				end

				if currentHold then currentHold.stop() end

				currentHold = nil
				currentPost = nil
			end
		end)
	end

	BariCage.roofDropArea = function()
		local cage, centre, size = findCage()
		if not cage then return nil end
		local anchorCFrame = roleShared.anchorPointFor("Anchor")
		local rotation = anchorCFrame - anchorCFrame.Position
		return cageStandCFrame(centre, size, Vector3.new(), rotation).Position, math.min(size.X, size.Z) / 2 * 0.6, rotation
	end

	return BariCage
end

defineModule("BariCage", createBariCage)

----------------------------------------------------------------------------
-- AnchorRole: anchor role
----------------------------------------------------------------------------
local function createAnchorRole()
	local config
	local npCfolder
	local movement
	local attacks
	local storing
	local qol
	local roleShared
	local combatTuning
	local bariCage
	local getSafeCharacterInfo
	local getPositiveNumber
	local getBoolean
	local huge = math.huge
	local skills

	return {
		Init = function(options)
			config = options.Config
			skills = options.Skills
			npCfolder = options.NPCfolder
			movement = options.Movement
			attacks = options.Attacks
			storing = options.Storing
			qol = options.QOL
			roleShared = options.RoleShared
			combatTuning = options.CombatTuning or {}
			bariCage = options.BariCage
			getSafeCharacterInfo = options.getSafeCharacterInfo
			getPositiveNumber = options.getPositiveNumber
			getBoolean = options.getBoolean
		end,
		Run = function(role)
			local roleName = role or "Anchor"

			local function attackEnabled(key)
				local anchorAttacks = config.AnchorAttacks and config.AnchorAttacks[roleName]
				if type(anchorAttacks) == "table" and anchorAttacks[key] ~= nil then
					return anchorAttacks[key] == true
				end
				return config[key] == true
			end

			local postCFrame = roleShared.anchorPointFor(roleName)
			local regroupCFrame = roleShared.anchorRegroupPointFor(roleName)
			local useBariCage = bariCage.isEnabled()
			local marker = not useBariCage and movement.makeMarkerPart(postCFrame) or nil
			local anchorOnly = roleShared.anchorOnlyMode()
			local beastLabel = anchorOnly and "Krakens" or "Megalodons"
			local beastName = anchorOnly and "kraken" or "megalodon"
			local stats = roleShared.createStatsPanel({ title = roleName, rows = roleShared.makeStatsRows({ key = "beasts", label = beastLabel }) })
			local startedAt = os.clock()
			local useMegaPow = attackEnabled("AnchorUseMegaPow")
			local hasAnyAttack = useMegaPow or attackEnabled("AnchorUseCyborg") or attackEnabled("AnchorUseRay") or attackEnabled("AnchorUseBonBomb") or attackEnabled("AnchorUseBonFireball") or attackEnabled("AnchorUseMaguHound") or attackEnabled("AnchorUseMaguFist") or attackEnabled("AnchorUseMaguRain")
			local krakenLoiterSeconds = getPositiveNumber(15)
			local megalodonRadius = getPositiveNumber(combatTuning.AnchorMegalodonEngageRadius, 1200)
			local krakenRadius = getPositiveNumber(combatTuning.AnchorOnlyKrakenEngageRadius, 1200)
			local trackRadius = getPositiveNumber(2000)
			local trackRadiusSq = trackRadius * trackRadius
			local postX = postCFrame.X
			local postZ = postCFrame.Z

			stats.poll("uptime", function()
				return os.clock() - startedAt
			end)

			stats.poll("beasts", function()
				return attacks.countNearbySpecies(beastName, postCFrame, anchorOnly and krakenRadius or megalodonRadius)
			end)

			stats.status("Starting")
			local krakenFirstSeen = {}

			local function findLoiteringKraken()
				if not npCfolder then return nil end
				local now = os.clock()
				local seen = {}
				local oldest = huge
				local target

				for _, child in ipairs(npCfolder:GetChildren()) do
					local primaryPart = child:IsA("Model") and child.PrimaryPart
					local isKraken = primaryPart and string.find(attacks.getLoweredName(child), "kraken", 1, true)

					if isKraken then
						local position = primaryPart.Position
						local dx = position.X - postX
						local dz = position.Z - postZ

						if dx * dx + dz * dz <= trackRadiusSq then
							local firstSeen = krakenFirstSeen[child] or now
							seen[child] = firstSeen

							if now - firstSeen >= krakenLoiterSeconds and firstSeen < oldest then
								oldest = firstSeen
								target = child
							end
						end
					end
				end

				krakenFirstSeen = seen
				return target
			end

			local fruitQueue = storing.createFruitQueue(roleName)
			local handlingFruit = false
			local regroupDepth = 0
			local pauseDuringRegroup = getBoolean(config.PauseAttacksDuringRegroup, true)
			local safeMode = getBoolean(config.SafeMode, false)
			local useBomu = getBoolean(config.AnchorUseBomu, false)

			local function startFlightLoop(interval)
				if useBariCage then return end

				if useBomu then
					movement.startBomuLoop(interval)
				else
					movement.startSkyWalkLoop(interval)
				end
			end

			local function stopFlightLoop()
				if useBariCage then return end

				if useBomu then
					movement.stopBomuLoop()
				else
					movement.stopSkyWalkLoop()
				end
			end

			local function enterSafeCast()
				if not safeMode then return end
				stopFlightLoop()
				movement.setFaceMouseState(true)
			end

			local function exitSafeCast()
				if not safeMode then return end
				movement.setFaceMouseState(false)
				startFlightLoop(1)
			end

			local casting = false
			local cyborgActive = false

			local function beginCast()
				if casting then return false end
				casting = true
				enterSafeCast()
				return true
			end

			local function endCast()
				casting = false
				exitSafeCast()
			end

			local function shouldContinue()
				return false
			end

			local function aroundDrop(callback)
				while (casting or cyborgActive) and shouldContinue() do
					task.wait(0.1)
				end

				casting = true
				enterSafeCast()
				task.wait(5)
				local ok, value = pcall(callback)
				casting = false
				exitSafeCast()

				if not ok then error(value, 0) end

				return value
			end

			local function canAttack()
				if pauseDuringRegroup and regroupDepth > 0 then return false end

				if qol.IsErrorHoldActive() then return false end
				return true
			end

			local function stopMegaPow()
				if attacks.isMegaPowBarrageActive() then attacks.MegaPowBarrage(false) end
			end

			local function handleFruit(fruitName)
				return storing.handleFruitGeneric(roleName, stats, fruitName, { dropPingCliffOnly = true, aroundDrop = aroundDrop })
			end

			local function startFruitLoop(isAlive)
				shouldContinue = isAlive

				storing.startFruitLoopGeneric(fruitQueue, handleFruit, isAlive, roleName, function(busy)
					handlingFruit = busy
				end, nil, function()
					stats.status("Holding")
				end)
			end

			roleShared.desynchronizeStart()

			qol.runWithDeathRecovery(roleName, function(isAlive)
				handlingFruit = false
				regroupDepth = 0
				cyborgActive = false
				stats.status("Travelling")
				startFlightLoop(0.5)
				task.wait(5)
				stopFlightLoop()

				if useBomu then
					movement.moveWithBomuToCFrame(postCFrame, 140, 300, false, "raycast", 150)
				else
					movement.moveWithGeppoToCFrame(postCFrame, 100, 300, false, "raycast", 150)
				end

				if not isAlive() then return end

				if useBariCage then
					bariCage.holdOnCage(roleName, isAlive, stats, { useBomuTravel = useBomu })
				else
					movement.startMovement(movement.trackPart, marker, 60, 0, false)
					startFlightLoop(1)

					local regroupOptions = {
						enabled = config.AnchorRegroupEnemies,
						delay = config.RegroupDelay,
						tweenTime = combatTuning.RegroupTweenTime,
						holdTime = combatTuning.RegroupHoldTime,
					}

					movement.startRegroupLoop(marker, postCFrame, 60, regroupCFrame, isAlive, nil, {
						onBegin = function()
							regroupDepth += 1
							stopMegaPow()
							stats.status("Regrouping")
						end,
						onEnd = function()
							regroupDepth -= 1

							if isAlive() and not handlingFruit then
								stats.status("Holding")
							end
						end,
					}, regroupOptions)
				end

				startFruitLoop(isAlive)

				if not hasAnyAttack then
					stats.status("Holding")

					while isAlive() do
						task.wait(1)
					end

					return
				end

				if anchorOnly then
					attacks.setTargetSelector(function()
						return attacks.findTargetModel({ "megalodon" }, postCFrame, megalodonRadius) or attacks.findTargetModel({ "kraken" }, postCFrame, krakenRadius)
					end)
				else
					attacks.setTargetSelector(function()
						local kraken = findLoiteringKraken()
						return attacks.findTargetModel({ "megalodon" }, postCFrame, megalodonRadius) or kraken
					end)
				end

				if useMegaPow then storing.setItemEquipped("Mega-Pow", true) end

				local lastRayAt = 0
				local lastCyborgAt = 0
				local lastFistAt = 0
				local lastRainAt = 0
				local rainActive = false
				local needReequip = false

				if anchorOnly then
					print("[" .. roleName .. "] Holding rough waters as the killer: clearing megalodons and every kraken the lures bring in.")
				else
					print("[" .. roleName .. "] Holding rough waters, clearing megalodons and any kraken left loitering for " .. krakenLoiterSeconds .. "s.")
				end

				stats.status("Holding")
				local megaPowSafeCast = false
				local lastBonBombAt = 0
				local lastFireballAt = 0
				local lastHoundAt = 0
				local lastMegaPowAt = 0

				while isAlive() do
					local character, humanoid = getSafeCharacterInfo()

					if safeMode and megaPowSafeCast and not attacks.isMegaPowBarrageActive() then
						endCast()
						megaPowSafeCast = false
					end

					if handlingFruit or not canAttack() then
						if attacks.isMegaPowBarrageActive() then
							attacks.MegaPowBarrage(false)
						end

						if handlingFruit then needReequip = true end
					elseif character and humanoid and humanoid.Health > 0 then
						if needReequip then
							if useMegaPow then
								storing.setItemEquipped("Mega-Pow", true)
							end

							needReequip = false
						end

						local target = attacks.getTargetModel()

						if target then
							local now = os.clock()

							if attackEnabled("AnchorUseRay") and now - lastRayAt >= skills.SoulRayCooldown and beginCast() then
								local aim = attacks.getTargetPosition()

								if aim then
									task.spawn(function()
										print("[" .. roleName .. "] Prominence Ray...")
										attacks.soulRay(aim.Position)
										lastRayAt = roleShared.castStamp()
										endCast()
									end)
								else
									endCast()
								end
							end

							local aim = attacks.getTargetPosition()
							local castBomb = aim and attackEnabled("AnchorUseBonBomb") and now - lastBonBombAt >= skills.BonBombCooldown and beginCast()
							local castedBomb = false

							if castBomb then
								local position = aim.Position

								task.spawn(function()
									print("[" .. roleName .. "] Bon-Bon Bomb...")
									attacks.soulBonBomb(position)
									task.wait(skills.BonBombCast)
									endCast()
								end)

								lastBonBombAt = roleShared.castStamp()
								castedBomb = true
							end

							if not castedBomb and aim and attackEnabled("AnchorUseBonFireball") and now - lastFireballAt >= skills.BonFireballCooldown and beginCast() then
								local position = aim.Position

								task.spawn(function()
									print("[" .. roleName .. "] Bon-Bon Fireball...")
									attacks.soulBonFireball(position)
									task.wait(skills.BonFireballCast)
									endCast()
								end)

								lastFireballAt = roleShared.castStamp()
							end

							if attackEnabled("AnchorUseCyborg") and not cyborgActive and now - lastCyborgAt >= skills.CyborgCooldown and beginCast() then
								cyborgActive = true

								if not safeMode then
									task.spawn(function()
										task.wait(skills.CyborgCast)
										endCast()
									end)
								end

								task.spawn(function()
									print("[" .. roleName .. "] Missle Shower...")

									pcall(attacks.cyborgMissleShower, target, function()
										return isAlive() and canAttack()
									end, attacks.getTargetModel)

									lastCyborgAt = roleShared.castStamp()
									cyborgActive = false

									if safeMode then endCast() end

									if useMegaPow then
										storing.setItemEquipped("Mega-Pow", true)
									end
								end)
							end

							if attackEnabled("AnchorUseMaguHound") and now - lastHoundAt >= skills.MaguHoundCooldown and beginCast() then
								print("[" .. roleName .. "] Magma Hound...")
								local ok, result = pcall(attacks.maguHound, target)
								endCast()
								lastHoundAt = roleShared.castStamp() - (ok and result and 0 or skills.MaguHoundCooldown - skills.MaguRetryBackoff)
							end

							if attackEnabled("AnchorUseMaguFist") and now - lastFistAt >= skills.MaguFistCooldown and beginCast() then
								print("[" .. roleName .. "] Magma Fist...")
								local ok, result = pcall(attacks.maguFist, target)
								endCast()
								lastFistAt = roleShared.castStamp() - (ok and result and 0 or skills.MaguFistCooldown - skills.MaguRetryBackoff)
							end

							if attackEnabled("AnchorUseMaguRain") and not rainActive and now - lastRainAt >= skills.MaguRainCooldown and beginCast() then
								rainActive = true

								task.spawn(function()
									print("[" .. roleName .. "] Magma Rain...")

									local ok, result = bariCage.duringMagmaRain(function()
										return attacks.maguRain(target, function()
											return isAlive() and canAttack()
										end)
									end)

									lastRainAt = roleShared.castStamp() - (ok and result and 0 or skills.MaguRainCooldown - skills.MaguRetryBackoff)
									rainActive = false
									endCast()

									if useMegaPow then
										storing.setItemEquipped("Mega-Pow", true)
									end
								end)
							end

							if useMegaPow and now - lastMegaPowAt >= skills.MegaPowCooldown and not attacks.isMegaPowBarrageActive() and (not safeMode or beginCast()) then
								if safeMode then megaPowSafeCast = true end

								lastMegaPowAt = roleShared.castStamp()

								task.spawn(function()
									print("[" .. roleName .. "] Attempting MegaPow Barrage...")
									attacks.MegaPowBarrage(true)
								end)
							end
						elseif attacks.isMegaPowBarrageActive() then
							attacks.MegaPowBarrage(false)
						end
					end

					roleShared.jitteredWait(0.3)
				end

				if attacks.isMegaPowBarrageActive() then attacks.MegaPowBarrage(false) end
			end, stats)
		end,
	}
end

defineModule("AnchorRole", createAnchorRole)

----------------------------------------------------------------------------
-- KillerRole: killer role
----------------------------------------------------------------------------
local function createKillerRole()
	local config
	local skills
	local heights
	local locations
	local fruitPngs
	local movement
	local attacks
	local qol
	local roleShared
	local combatTuning
	local getPositiveNumber
	local getBoolean
	local newCFrame = CFrame.new
	local newVector3 = Vector3.new
	local getSafeCharacterInfo, storing, pingID

	return {
		Init = function(options)
			config = options.Config
			skills = options.Skills
			heights = options.HEIGHTS
			locations = options.Locations
			fruitPngs = options.fruitPngs
			pingID = options.PingID
			movement = options.Movement
			attacks = options.Attacks
			storing = options.Storing
			qol = options.QOL
			roleShared = options.RoleShared
			combatTuning = options.CombatTuning or {}
			getSafeCharacterInfo = options.getSafeCharacterInfo
			getPositiveNumber = options.getPositiveNumber
			getBoolean = options.getBoolean
		end,
		Run = function(role)
			task.wait(5)
			role = role or "Killer"

			local function attackEnabled(key)
				local killerAttacks = config.KillerAttacks and config.KillerAttacks[role]
				if type(killerAttacks) == "table" and killerAttacks[key] ~= nil then
					return killerAttacks[key] == true
				end
				return config[key] == true
			end

			local cliff = locations.Cliff
			local postCFrame = roleShared.killerPointFor(role)
			local regroupCFrame = roleShared.killerRegroupPointFor(role)
			local stats = roleShared.createStatsPanel({ title = role, rows = roleShared.makeStatsRows({ key = "beasts", label = "Krakens" }) })
			local startedAt = os.clock()

			stats.poll("uptime", function()
				return os.clock() - startedAt
			end)

			stats.poll("beasts", function()
				return attacks.countNearbySpecies("kraken", regroupCFrame, getPositiveNumber(combatTuning.KillerEngageRadius, 1500))
			end)

			stats.status("Starting")
			local lastRayAt = 0
			local rayFired = false
			local casting = false
			local dropBusy = false
			local safeMode = getBoolean(config.SafeMode, false)
			local useBomu = getBoolean(config.KillerUseBomu, false)

			local function startFlightLoop(interval)
				if useBomu then
					movement.startBomuLoop(interval)
				else
					movement.startSkyWalkLoop(interval)
				end
			end

			local function stopFlightLoop()
				if useBomu then
					movement.stopBomuLoop()
				else
					movement.stopSkyWalkLoop()
				end
			end

			local function enterSafeCast()
				if not safeMode then return end
				stopFlightLoop()
				movement.setFaceMouseState(true)
			end

			local function exitSafeCast()
				if not safeMode then return end
				movement.setFaceMouseState(false)
				startFlightLoop(1)
			end

			local function beginCast()
				if casting then return false end
				casting = true
				enterSafeCast()
				return true
			end

			local function endCast()
				casting = false
				exitSafeCast()
			end

			local function castAsync(action)
				if not beginCast() then return false end

				task.spawn(function()
					pcall(action)
					endCast()
				end)

				return true
			end

			local function shouldContinue()
				return false
			end

			local function aroundDrop(callback)
				while (casting or dropBusy) and shouldContinue() do
					task.wait(0.2)
				end

				casting = true
				enterSafeCast()
				task.wait(5)
				local ok, value = pcall(callback)
				casting = false
				exitSafeCast()

				if not ok then error(value, 0) end

				return value
			end

			local attackLoopsRunning = true
			local handlingFruit = false
			local cliffRunDepth = 0
			local regroupDepth = 0
			local pauseDuringCliff = getBoolean(config.PauseAttacksDuringCliffRun, true)
			local pauseDuringRegroup = getBoolean(config.PauseAttacksDuringRegroup, true)

			local function canAttack()
				if pauseDuringCliff and cliffRunDepth > 0 then return false end

				if pauseDuringRegroup and regroupDepth > 0 then return false end

				if qol.IsErrorHoldActive() then return false end
				return true
			end

			local function stopMegaPow()
				if attacks.isMegaPowBarrageActive() then attacks.MegaPowBarrage(false) end
			end

			local fruitQueue = storing.createFruitQueue(role)
			local engageRadius = getPositiveNumber(combatTuning.KillerEngageRadius, 1500)

			attacks.setTargetSelector(function()
				return attacks.findTargetModel({ "kraken" }, regroupCFrame, engageRadius)
			end)

			local marker = movement.makeMarkerPart(postCFrame)
			local cliffRotation = cliff - cliff.Position
			local travelY = cliff.Position.Y + heights.KillerTravel
			local dropY = cliff.Position.Y + heights.KillerCliffDrop
			local cliffTravelCFrame = newCFrame(newVector3(cliff.Position.X, travelY, cliff.Position.Z)) * cliffRotation
			local mythicPileCFrame = newCFrame(newVector3(cliff.Position.X, dropY, cliff.Position.Z) + cliffRotation.RightVector * heights.KillerMythicPileOffset) * cliffRotation
			local postRotation = postCFrame - postCFrame.Position
			local postTravelCFrame = newCFrame(newVector3(postCFrame.Position.X, travelY, postCFrame.Position.Z)) * postRotation

			local function climbToTravelHeight(ensureAscent)
				local targetY = travelY

				if ensureAscent then
					local rootCFrame = movement.getRootCFrame()
					targetY = travelY

					if rootCFrame then
						targetY = math.max(travelY, rootCFrame.Position.Y + heights.KillerMinAscent)
					end
				end

				movement.snapToHeight(targetY, nil, true)
			end

			local function returnToPost(ensureAscent)
				if not loaderFlagA then return end
				print("[" .. role .. "] Moving to Killer position...")
				startFlightLoop(0.75)
				task.wait(5)
				stopFlightLoop()
				stats.status("Travelling")
				marker.CFrame = postCFrame
				climbToTravelHeight(ensureAscent)

				if useBomu then
					movement.moveWithBomuToCFrame(cliffTravelCFrame, 100, 0, true, "linear")
					movement.moveWithBomuToCFrame(postTravelCFrame, 140, 0, true, "linear")
				else
					movement.moveWithGeppoToCFrame(cliffTravelCFrame, 100, 0, true, "linear")
					movement.moveWithGeppoToCFrame(postTravelCFrame, 140, 0, true, "linear")
				end

				movement.snapToHeight(postCFrame.Position.Y, nil, true)
				movement.startMovement(movement.trackPart, marker, 60, 0, false)
				startFlightLoop(1.5)
				stats.status("Killing")
			end

			local function cliffRun(fruits, shouldContinue)
				if #fruits == 0 then return end
				print("[" .. role .. "] " .. #fruits .. " fruit(s) for the lures - heading to the cliff: " .. table.concat(fruits, ", "))
				stats.status("Cliff run")
				cliffRunDepth += 1
				stopMegaPow()

				local function endCliffRun()
					cliffRunDepth -= 1
				end

				movement.startMovement(movement.hover, false)
				stopFlightLoop()
				startFlightLoop(0.75)
				task.wait(5)
				stopFlightLoop()

				local ok, err = pcall(function()
					climbToTravelHeight(false)

					if useBomu then
						movement.moveWithBomuToCFrame(cliffTravelCFrame, 100, 0, true, "linear")
					else
						movement.moveWithGeppoToCFrame(cliffTravelCFrame, 100, 0, true, "linear")
					end

					movement.snapToHeight(dropY, nil, true)
					task.wait(2)
					if not shouldContinue() then
						fruitQueue.release(fruits)
						return
					end
					local regularFruits = {}
					local mythicalFruits = {}

					for _, fruit in ipairs(fruits) do
						if storing.isMythicalFruit(fruit) then
							table.insert(mythicalFruits, fruit)
						else
							table.insert(regularFruits, fruit)
						end
					end

					local function dropAll(list)
						for _, fruit in ipairs(list) do
							if not shouldContinue() then break end

							while storing.dropFruit(fruit) do
								stats.recordFruit(fruit, "dropped")
								qol.itemWebhook({ item = fruit, event = "Fruit Dropped at Cliff", ping = pingID, img = fruitPngs[fruit] or fruitPngs.Rest })

								if storing.isMythicalFruit(fruit) then
									qol.mythicalDropWebhook(fruit, "Dropped at Cliff", fruitPngs[fruit] or fruitPngs.Rest)
								end

								task.wait(0.5)
							end
						end
					end

					movement.startMovement(movement.hover, false)
					dropAll(regularFruits)

					if shouldContinue() and #mythicalFruits > 0 then
						movement.stopMovement()
						movement.snapToCFrame(mythicPileCFrame, nil, false, false)
						movement.startMovement(movement.hover, false)
						dropAll(mythicalFruits)
					end

					movement.stopMovement()
					fruitQueue.release(fruits)
					if not shouldContinue() then return end
					returnToPost()
				end)

				endCliffRun()

				if not ok then error(err, 0) end
			end

			local function handleFruit(fruitName)
				return storing.handleFruitGeneric(role, stats, fruitName, { deferCliffFruit = true, aroundDrop = aroundDrop })
			end

			local function startFruitLoop(isAlive)
				shouldContinue = isAlive

				storing.startFruitLoopGeneric(fruitQueue, handleFruit, isAlive, role, function(busy)
					handlingFruit = busy
				end, function(heldFruits)
					if #heldFruits == 0 then return end

					if isAlive() then
						local ok, err = pcall(cliffRun, heldFruits, isAlive)

						if not ok then
							warn("[" .. role .. "] cliff run: " .. tostring(err))
							pcall(fruitQueue.release, heldFruits)
						end
					else
						pcall(fruitQueue.release, heldFruits)
					end
				end, function()
					stats.status("Killing")
				end)
			end

			local function startRayLoop(isAlive)
				attackLoopsRunning = true

				task.spawn(function()
					while attackLoopsRunning and isAlive() do
						local character, humanoid = getSafeCharacterInfo()
						local canRay = character and humanoid and humanoid.Health > 0 and canAttack() and attackEnabled("KillerUseRay")
						local rayReady

						if canRay then
							rayReady = os.clock() - lastRayAt >= skills.SoulRayCooldown
						else
							rayReady = canRay
						end

						if rayReady then
							local aim = attacks.getTargetPosition()

							if aim then
								local position = aim.Position

								castAsync(function()
									print("[" .. role .. "] Prominence Ray...")
									attacks.soulRay(position)
									lastRayAt = roleShared.castStamp()
									rayFired = true
								end)
							end
						end

						roleShared.jitteredWait(0.3)
					end
				end)
			end

			local function startCakeLoop(isAlive)
				task.spawn(function()
					while attackLoopsRunning and isAlive() do
						local shouldCast = attacks.getTargetPosition() and canAttack() and rayFired

						shouldCast = shouldCast and attacks.countSoulCakes() < skills.SoulCakeMax

						if shouldCast then
							local cakeCFrame = attacks.nextCrumbleShotCFrame()

							if cakeCFrame then
								castAsync(function()
									attacks.soulCake(cakeCFrame)
									task.wait(skills.SoulCakeCast)
								end)
							end
						end

						roleShared.jitteredWait(1)
					end
				end)
			end

			local function startBonLoop(isAlive)
				task.spawn(function()
					local lastBombAt = 0
					local lastFireballAt = 0

					while attackLoopsRunning and isAlive() do
						local character, humanoid = getSafeCharacterInfo()

						if character and humanoid and humanoid.Health > 0 and canAttack() then
							local aim = attacks.getTargetPosition()

							if aim then
								local position = aim.Position
								local now = os.clock()
								local bombReady = attackEnabled("KillerUseBonBomb") and now - lastBombAt >= skills.BonBombCooldown
								local castBomb = false

								if bombReady then
									castBomb = castAsync(function()
										print("[" .. role .. "] Bon-Bon Bomb...")
										attacks.soulBonBomb(position)
										task.wait(skills.BonBombCast)
									end)

									if castBomb then
										lastBombAt = roleShared.castStamp()
									end
								end

								if not castBomb and attackEnabled("KillerUseBonFireball") and now - lastFireballAt >= skills.BonFireballCooldown then
									if castAsync(function()
										print("[" .. role .. "] Bon-Bon Fireball...")
										attacks.soulBonFireball(position)
										task.wait(skills.BonFireballCast)
									end) then
										lastFireballAt = roleShared.castStamp()
									end
								end
							end
						end

						roleShared.jitteredWait(0.3)
					end
				end)
			end

			local function startHoundLoop(isAlive)
				task.spawn(function()
					local lastHoundAt = 0

					while attackLoopsRunning and isAlive() do
						local ready, humanoid = getSafeCharacterInfo()
						ready = ready and humanoid and humanoid.Health > 0 and canAttack()

						ready = ready and os.clock() - lastHoundAt >= skills.MaguHoundCooldown

						if ready then
							local target = attacks.getTargetModel()
							local hit = false

							if target and castAsync(function()
								print("[" .. role .. "] Magma Hound...")
								hit = attacks.maguHound(target)
								task.wait(skills.MaguHoundCast)
							end) then
								lastHoundAt = roleShared.castStamp() - (hit and 0 or skills.MaguHoundCooldown - skills.MaguRetryBackoff)
							end
						end

						roleShared.jitteredWait(0.5)
					end
				end)
			end

			local function startFistLoop(isAlive)
				task.spawn(function()
					local lastFistAt = 0

					while attackLoopsRunning and isAlive() do
						local character, humanoid = getSafeCharacterInfo()
						local ready = character and humanoid and humanoid.Health > 0 and canAttack()

						ready = ready and os.clock() - lastFistAt >= skills.MaguFistCooldown

						if ready then
							local target = attacks.getTargetModel()
							local hit = false

							if target and castAsync(function()
								print("[" .. role .. "] Magma Fist...")
								hit = attacks.maguFist(target)
								task.wait(skills.MaguFistCast)
							end) then
								lastFistAt = roleShared.castStamp() - (hit and 0 or skills.MaguFistCooldown - skills.MaguRetryBackoff)
							end
						end

						roleShared.jitteredWait(0.3)
					end
				end)
			end

			local function startRainLoop(isAlive)
				task.spawn(function()
					local lastRainAt = 0

					while attackLoopsRunning and isAlive() do
						local ready, humanoid = getSafeCharacterInfo()
						ready = ready and humanoid and humanoid.Health > 0 and canAttack()

						ready = ready and os.clock() - lastRainAt >= skills.MaguRainCooldown

						if ready then
							local target = attacks.getTargetModel()

							if target then
								castAsync(function()
									print("[" .. role .. "] Magma Rain...")

									local hit = attacks.maguRain(target, function()
										return attackLoopsRunning and isAlive() and canAttack()
									end)

									lastRainAt = roleShared.castStamp() - (hit and 0 or skills.MaguRainCooldown - skills.MaguRetryBackoff)
								end)
							end
						end

						roleShared.jitteredWait(0.5)
					end
				end)
			end

			local function startCyborgLoop(isAlive)
				task.spawn(function()
					local lastShowerAt = 0

					while attackLoopsRunning and isAlive() do
						local ready, humanoid = getSafeCharacterInfo()
						ready = ready and humanoid and humanoid.Health > 0 and canAttack()

						ready = ready and os.clock() - lastShowerAt >= skills.CyborgCooldown

						if ready then
							local target = attacks.getTargetModel()

							if target and beginCast() then
								if not safeMode then
									task.spawn(function()
										task.wait(skills.CyborgCast)
										endCast()
									end)
								end

								print("[" .. role .. "] Missle Shower...")
								dropBusy = true

								pcall(attacks.cyborgMissleShower, target, function()
									return attackLoopsRunning and isAlive() and canAttack()
								end, attacks.getTargetModel)

								dropBusy = false
								lastShowerAt = roleShared.castStamp()

								if safeMode then endCast() end

								if attackEnabled("KillerUseMegaPow") and not handlingFruit then
									storing.setItemEquipped("Mega-Pow", true)
								end
							end
						end

						roleShared.jitteredWait(0.5)
					end
				end)
			end

			local function startMegaPowLoop(isAlive)
				task.spawn(function()
					storing.setItemEquipped("Mega-Pow", true)
					local safeCastHeld = false
					local needReequip = false
					local lastBarrageAt = 0

					while attackLoopsRunning and isAlive() do
						local character, humanoid = getSafeCharacterInfo()

						if safeMode and safeCastHeld and not attacks.isMegaPowBarrageActive() then
							endCast()
							safeCastHeld = false
						end

						if handlingFruit or not canAttack() then
							if attacks.isMegaPowBarrageActive() then
								attacks.MegaPowBarrage(false)
							end

							if handlingFruit then needReequip = true end
						elseif character and humanoid and humanoid.Health > 0 then
							if needReequip then
								storing.setItemEquipped("Mega-Pow", true)
								needReequip = false
							end

							if attacks.getTargetPosition() then
								if os.clock() - lastBarrageAt >= skills.MegaPowCooldown and not attacks.isMegaPowBarrageActive() and (not safeMode or beginCast()) then
									if safeMode then safeCastHeld = true end

									lastBarrageAt = roleShared.castStamp()

									task.spawn(function()
										print("[" .. role .. "] MegaPow Barrage...")
										attacks.MegaPowBarrage(true)
									end)
								end
							elseif attacks.isMegaPowBarrageActive() then
								attacks.MegaPowBarrage(false)
							end
						end

						roleShared.jitteredWait(0.5)
					end

					if attacks.isMegaPowBarrageActive() then
						attacks.MegaPowBarrage(false)
					end

					if safeCastHeld then endCast() end
				end)
			end

			roleShared.desynchronizeStart()

			qol.runWithDeathRecovery(role, function(isAlive)
				attackLoopsRunning = false
				handlingFruit = false
				cliffRunDepth = 0
				regroupDepth = 0
				dropBusy = false
				returnToPost(true)
				if not isAlive() then return end
				startRayLoop(isAlive)
				startFruitLoop(isAlive)

				if attackEnabled("KillerUseCakes") then startCakeLoop(isAlive) end

				if attackEnabled("KillerUseBonBomb") or attackEnabled("KillerUseBonFireball") then
					startBonLoop(isAlive)
				end

				if attackEnabled("KillerUseMaguHound") then startHoundLoop(isAlive) end

				if attackEnabled("KillerUseMaguFist") then startFistLoop(isAlive) end

				if attackEnabled("KillerUseMaguRain") then startRainLoop(isAlive) end

				if attackEnabled("KillerUseCyborg") then startCyborgLoop(isAlive) end

				if attackEnabled("KillerUseMegaPow") then startMegaPowLoop(isAlive) end

				local function isHandlingFruit()
					return handlingFruit
				end

				local regroupOptions = {
					enabled = config.KillerRegroupEnemies,
					delay = config.RegroupDelay,
					tweenTime = combatTuning.RegroupTweenTime,
					holdTime = combatTuning.RegroupHoldTime,
				}

				movement.startRegroupLoop(marker, postCFrame, 60, regroupCFrame, isAlive, isHandlingFruit, {
					onBegin = function()
						regroupDepth += 1
						stopMegaPow()
						stats.status("Regrouping")
					end,
					onEnd = function()
						regroupDepth -= 1

						if isAlive() and not handlingFruit then
							stats.status("Killing")
						end
					end,
				}, regroupOptions)

				while isAlive() do
					task.wait(1)
				end

				attackLoopsRunning = false
			end, stats)
		end,
	}
end

defineModule("KillerRole", createKillerRole)

----------------------------------------------------------------------------
-- LureRole: lure role (bring the sea beast, deliver it, pick up fruits)
----------------------------------------------------------------------------
local function createLureRole()
	local config
	local skills
	local heights
	local locations
	local fruitPngs
	local movement
	local storing
	local roleShared
	local bariCage
	local movementTuning
	local storageTuning
	local getPositiveNumber
	local itemWebhook
	local mythicalDropWebhook
	local teleportService
	local replicatedStorage
	local localPlayer
	local errorHoldActive
	local pauseAntiAfk
	local hasNotificationWords
	local newCFrame = CFrame.new
	local newVector3 = Vector3.new
	local huge = math.huge

	local travelSpeeds = {
		Default = { travel = 100, tow = 120 },
		Pika = { travel = 350, tow = 100 },
		Goro = { travel = 350, tow = 100 },
		Ito = { travel = 2000, tow = 100 },
	}

	local capWords = { "max", "megalodon" }
	local pingID, resumeAntiAfk

	return {
		Init = function(options)
			config = options.Config
			skills = options.Skills
			heights = options.HEIGHTS
			locations = options.Locations
			fruitPngs = options.fruitPngs
			pingID = options.PingID
			movement = options.Movement
			storing = options.Storing
			roleShared = options.RoleShared
			bariCage = options.BariCage
			movementTuning = options.MovementTuning
			storageTuning = options.StorageTuning
			getPositiveNumber = options.getPositiveNumber
			itemWebhook = options.itemWebhook
			mythicalDropWebhook = options.mythicalDropWebhook
			pauseAntiAfk = options.pauseAntiAfk
			resumeAntiAfk = options.resumeAntiAfk
			teleportService = options.TeleportService
			replicatedStorage = options.ReplicatedStorage
			localPlayer = options.LocalPlayer
			errorHoldActive = options.errorHoldActive
			hasNotificationWords = options.hasNotificationWords
		end,
		Run = function(lureKey, boatSpawn)
			movement.SetErrorHoldDisengage(true)
			local cliff = locations.Cliff
			local rejoinSeconds = getPositiveNumber(config.LureRejoinSeconds, 180)

			task.spawn(function()
				local elapsed = 0

				while elapsed < rejoinSeconds do
					task.wait(1)

					if not errorHoldActive() then elapsed += 1 end
				end

				warn("[Lure] " .. rejoinSeconds .. "s watchdog expired - rejoining from the menu.")

				pcall(function()
					teleportService:Teleport(config.MenuPlaceId, localPlayer)
				end)
			end)

			local lureBoat = heights.LureBoat
			local lureEscape = heights.LureEscape
			local lureCliffHover = heights.LureCliffHover
			local lureBoatApproach = heights.LureBoatApproach
			local cliffRotation = cliff - cliff.Position
			local cliffHoverCFrame = newCFrame(cliff.Position + newVector3(0, lureCliffHover, 0)) * cliffRotation
			local travelMethod = roleShared.lureTravelMethod(lureKey)
			local useHieTP = travelMethod == "HieTP"
			local speeds = travelSpeeds[travelMethod] or travelSpeeds.Default
			local travel = speeds.travel
			local tow = speeds.tow

			local function travelLeg(target, speed, offset, noclip, mode, forceFlight)
				if useHieTP and not forceFlight then
					for i = 1, 3 do
						local equipped = storing.setItemEquipped("Hie-Hie", true)

						if equipped then
							task.wait(0.1)
							if movement.hieTP(target, offset) then return end
						end

						if i < 2 then
							warn("[Lure] HieTP leg attempt " .. i .. " failed" .. (equipped and " (teleport)." or " (equip).") .. " Retrying...")
							task.wait(0.5)
						end
					end

					error("[Lure] HieTP leg failed after 3 attempts - Hie-Hie not equipped?", 0)
				else
					movement.moveWithGeppoToCFrame(target, speed, offset, noclip, mode)
				end
			end

			local function cliffDeliveryInAnchorOnly()
				if not config.LureAnchorOnlyCliffDelivery then return false end
				return roleShared.anchorOnlyMode()
			end

			local instantMode = config.LureAnchorOnlyInstant == true and roleShared.anchorOnlyMode()

			local function getDeliveryPoint()
				if not roleShared.anchorOnlyMode() or cliffDeliveryInAnchorOnly() then
					return locations.KillerRegroupPoint
				end
				local anchors = roleShared.mannedRoles(roleShared.ANCHOR_ROLES)
				local bestDistSq = huge
				local nearestAnchor

				for _, role in ipairs(anchors) do
					local point = roleShared.anchorPointFor(role)

					if point then
						local dx = point.X - boatSpawn.X
						local dz = point.Z - boatSpawn.Z
						local distSq = dx * dx + dz * dz

						if distSq < bestDistSq then
							bestDistSq = distSq
							nearestAnchor = role
						end
					end
				end

				if nearestAnchor then return roleShared.anchorRegroupPointFor(nearestAnchor) end

				return locations.AnchorRegroupPoint
			end

			local function storageRoomLeft()
				local stored = storing.countStoredFruits()

				if not storing.hasFruitBag() then
					if stored >= storageTuning.NoBagFruitCapacity then
						print("[Lure] No fruit bag and " .. stored .. " fruit stored - nowhere to put one.")
						return 0
					end
					return storageTuning.NoBagFruitCapacity - stored
				end

				return 1
			end

			local function pickupBudget()
				if not config.LurePickUpFruit then return 0 end

				if roleShared.anchorOnlyMode() and not cliffDeliveryInAnchorOnly() then return 0 end
				return storageRoomLeft()
			end

			local function collectFruit(fruit, rotation, hoverHeight)
				print("[Lure] Collecting " .. fruit.name .. "...")
				local groundCFrame = newCFrame(fruit.position) * rotation
				local hoverCFrame = newCFrame(fruit.position + newVector3(0, hoverHeight, 0)) * rotation
				local storedBefore = storing.getStoredCount(fruit.name)
				movement.stopMovement()
				travelLeg(hoverCFrame, travel, 0, false, "linear")
				travelLeg(groundCFrame, movementTuning.DefaultSpeed, 4, false, "linear")
				movement.startMovement(movement.hover, false)

				if useHieTP then storing.setItemEquipped("Hie-Hie", false) end

				storing.holdStoreKey()
				local deadline = os.clock() + storageTuning.FruitPickupTimeout
				local stored, carrying = false, false

				while os.clock() < deadline do
					if storedBefore < storing.getStoredCount(fruit.name) then
						stored = true
						break
					elseif storing.isCarryingFruit(fruit.name) then
						carrying = true
						break
					end

					task.wait(0.1)
				end

				if carrying and not stored then
					print("[Lure] Picked up " .. fruit.name .. " - storing it.")
					stored = storing.tryStoreFruit(fruit.name)
				end

				movement.stopMovement()
				travelLeg(hoverCFrame, movementTuning.DefaultSpeed, 0, false, "linear")

				if stored then
					print("[Lure] Stored " .. fruit.name .. ".")

					itemWebhook({
						item = fruit.name,
						event = "Fruit Picked Up",
						ping = storing.isCliffFruit(fruit.name) and pingID or "",
						img = fruitPngs[fruit.name] or fruitPngs.Rest,
					})

					if type(mythicalDropWebhook) == "function" and storing.isMythicalFruit(fruit.name) then
						mythicalDropWebhook(fruit.name, "Picked Up", fruitPngs[fruit.name] or fruitPngs.Rest)
					end

					return true
				end

				print("[Lure] Didn't get " .. fruit.name .. " (another lure likely took it).")
				return false
			end

			local function alreadyHave(fruitName)
				if not config.LureSkipDuplicateFruit then return false end
				return storing.getStoredCount(fruitName) > 0
			end

			local function sweepCliff()
				local budget = pickupBudget()
				if budget <= 0 then return end
				local fruits = storing.findDroppedFruits(cliff, 100)
				if #fruits == 0 then return end
				print("[Lure] " .. #fruits .. " dropped fruit(s) at the cliff.")
				local rotation = cliff - cliff.Position
				local collected = 0

				for _, fruit in ipairs(fruits) do
					if collected >= budget then break end

					if fruit.instance.Parent == workspace then
						if alreadyHave(fruit.name) then
							print("[Lure] Already storing " .. fruit.name .. " - leaving it.")
						else
							local ok, got = pcall(collectFruit, fruit, rotation, lureCliffHover)

							if not ok then
								warn("[Lure] pickup " .. fruit.name .. ": " .. tostring(got))
							elseif got then
								collected += 1
							end
						end
					end
				end
			end

			local function sweepBariCage()
				if not config.LurePickUpFruit then return end
				local center, radius, rotation = bariCage.roofDropArea()
				if not center then return end
				local budget = storageRoomLeft()
				if budget <= 0 then return end
				local fruits = storing.findDroppedFruits(center, radius + 15)
				if #fruits == 0 then return end
				print("[Lure] " .. #fruits .. " dropped fruit(s) on the Bari Cage.")
				local collected = 0

				for _, fruit in ipairs(fruits) do
					if collected >= budget then break end

					if fruit.instance.Parent == workspace then
						if alreadyHave(fruit.name) then
							print("[Lure] Already storing " .. fruit.name .. " - leaving it.")
						else
							local ok, got = pcall(collectFruit, fruit, rotation, lureCliffHover)

							if not ok then
								warn("[Lure] pickup " .. fruit.name .. ": " .. tostring(got))
							elseif got then
								collected += 1
							end
						end
					end
				end
			end

			local function runCycle()
				local lureAscent = heights.LureAscent
				local rootCFrame = movement.getRootCFrame()

				if rootCFrame then
					movement.setFaceMouseState(true)
					print("[Lure] Climbing " .. lureAscent .. " studs before setting off...")

					travelLeg(newCFrame(rootCFrame.Position + newVector3(0, lureAscent, 0)), travel, 0, false, "linear")
					movement.setFaceMouseState(false)
				end

				if not roleShared.anchorOnlyMode() then
					travelLeg(cliffHoverCFrame, travel, 0, true, "linear")
					movement.startMovement(movement.hover, false)
					task.wait(0.5)
					pcall(sweepCliff)

					if roleShared.supportRolesReady() then
						roleShared.waitForSupportRoles()
						movement.stopMovement()
					else
						pauseAntiAfk()
						travelLeg(cliff, movementTuning.DefaultSpeed, 4, false, "linear")
						movement.stopMovement()
						movement.pausePikaFlightDuring(roleShared.waitForSupportRoles, skills.PikaFlightCooldown)
						resumeAntiAfk()
					end
				else
					movement.startMovement(movement.hover, false)
					roleShared.waitForSupportRoles()
					movement.stopMovement()
				end

				local boatRotation = boatSpawn - boatSpawn.Position
				travelLeg(newCFrame(boatSpawn.X, boatSpawn.Y + lureBoatApproach, boatSpawn.Z) * boatRotation, travel, 0, false, "linear")
				travelLeg(boatSpawn, travel, lureBoat, true, "linear")

				if instantMode and not useHieTP then
					movement.faceTarget(boatSpawn.Position + boatSpawn.LookVector * 100)
				end

				movement.startMovement(movement.hover, false)
				task.wait(1)

				pcall(function()
					replicatedStorage.Events.ShipEvents.Spawn:InvokeServer("true")
				end)

				task.wait(2)

				for i = 1, 2 do
					if not hasNotificationWords(capWords) then break end

					warn("[Lure] Megalodon cap notification up - despawning the ship, waiting " .. 10 .. "s, and respawning (attempt " .. i .. ").")

					pcall(function()
						replicatedStorage.Events.ShipEvents.Spawn:InvokeServer("true")
					end)

					task.wait(10)

					pcall(function()
						replicatedStorage.Events.ShipEvents.Spawn:InvokeServer("true")
					end)

					task.wait(2)

					if i == 2 and hasNotificationWords(capWords) then
						warn("[Lure] Megalodon cap notification still up after " .. i .. " respawn attempt(s) - continuing anyway.")
					end
				end

				movement.stopMovement()
				if instantMode then
					print("[Lure] Instant anchor-only run - boat spawned by the Anchor, knocking out.")
					return
				end
				local boatRotation2 = boatSpawn - boatSpawn.Position
				local escapeCFrame = newCFrame(boatSpawn.X, boatSpawn.Y + lureEscape, boatSpawn.Z) * boatRotation2
				print("[Lure] Climbing " .. lureEscape .. " studs clear of the spawn...")
				travelLeg(escapeCFrame, 120, 0, true, "linear", true)
				local deliveryHold = getPositiveNumber(config.LureDeliveryHold, 20)
				print("[Lure] Towing to the delivery point...")

				travelLeg(getDeliveryPoint(), tow, 0, false, "linear", true)
				movement.startMovement(movement.hover, false)
				movement.beginTravelFlight(0.75)
				task.wait(deliveryHold)
				movement.stopMovement()
				movement.endTravelFlight()

				if bariCage.isEnabled() then
					print("[Lure] Delivered - sweeping the Bari Cage for dropped fruit...")
					pcall(sweepBariCage)
				end

				if cliffDeliveryInAnchorOnly() then
					print("[Lure] Delivered - sweeping the cliff before knocking out...")
					travelLeg(cliffHoverCFrame, travel, 0, true, "linear")
					movement.startMovement(movement.hover, false)
					task.wait(0.5)
					pcall(sweepCliff)
					movement.stopMovement()
				end
			end

			if travelMethod == "HieTP" then
				print("[Lure] HieTP on - teleporting every leg except the escape climb and the tow, which fly on Geppo.")
				runCycle()
			elseif travelMethod == "Ito" then
				print("[Lure] Sky Strings on for the whole cycle (" .. travel .. " studs/s).")
				movement.withSkyStringsFlight(runCycle, 1.5, 0)
			elseif travelMethod == "Goro" then
				print("[Lure] Lightning Form on for the whole cycle (" .. travel .. " studs/s).")
				task.wait(4)
				movement.withGoroGoroFlight(runCycle)
			elseif travelMethod == "Pika" then
				print("[Lure] Pika flight on for the whole cycle (" .. travel .. " studs/s).")
				task.wait(4)
				movement.withPikaFlight(runCycle)
			else
				runCycle()
			end

			movement.stopAllFlight()
			print("[Lure] Delivered - handing off to the Killer.")

			pcall(function()
				replicatedStorage.Events.KnockedOut:FireServer("self")
			end)

			task.wait(1)
			teleportService:Teleport(config.MenuPlaceId, localPlayer)
		end,
	}
end

defineModule("LureRole", createLureRole)

----------------------------------------------------------------------------
-- startup: default config, gets merged into getgenv().KrakenConfig
----------------------------------------------------------------------------
do
	local defaultConfig

	Core = Modules.Core()
	if getgenv().KrakenRunning then
		warn("[Kraken] Script is already running - aborting second launch.")
		return
	end
	getgenv().KrakenRunning = true
	loadstring("    function LPH_NO_VIRTUALIZE(f) return f end\n")()

	if not LRM_SEND_WEBHOOK then
		loadstring([[        function LRM_SEND_WEBHOOK(url, payload)
            local cloneref = cloneref or function(ref) return ref end
            local HttpService = cloneref(game:GetService("HttpService"))
            local requestFunc = (syn and syn.request) or http_request or request or (http and http.request)
            if not requestFunc then return end
            pcall(function()
                requestFunc({
                    Url = url,
                    Method = "POST",
                    Headers = { ["Content-Type"] = "application/json" },
                    Body = HttpService:JSONEncode(payload),
                })
            end)
        end
    ]])()
	end

	do
		local killerPost = CFrame.new(-6200.09619, 330.685059, 8945.30762, 0.0598450825, 2.23181851e-09, -0.998207688, -8.11286114e-08, 1, -2.62804045e-09, 0.998207688, 8.11404846e-08, 0.0598450825)
		local killerRegroup = CFrame.new(-6178.68457, 825.187073, 8950.69043, -0.0280916728, 9.54211856e-08, -0.999605358, -4.68706718e-09, 1, 9.5590579e-08, 0.999605358, 7.37051664e-09, -0.0280916728)
		local anchorPost = CFrame.new(-4821.91352, 325.5, 6873.72175, -0.652745724, 0.146487594, -0.743279457, -0.00100890303, 0.980958223, 0.194215998, 0.757576346, 0.127523556, -0.640168548)
		local anchor2Post = CFrame.new(-4811.91352, 325.5, 6879.72175, -0.652745724, 0.146487594, -0.743279457, -0.00100890303, 0.980958223, 0.194215998, 0.757576346, 0.127523556, -0.640168548)
		local anchorRegroup = CFrame.new(-4821.91352, 850.127411, 6873.72175, -0.652745724, 0.146487594, -0.743279457, -0.00100890303, 0.980958223, 0.194215998, 0.757576346, 0.127523556, -0.640168548)

		local function offsetCFrame(base, dx, dz)
			return CFrame.new(base.Position + Vector3.new(dx, 0, dz)) * (base - base.Position)
		end

		if game.PlaceId ~= 1730877806 and game.PlaceId ~= 11424731604 and game.PlaceId ~= 6360478118 and game.PlaceId ~= 3978370137 and game.PlaceId ~= 7465136166 then
			getgenv().KrakenRunning = nil
			game:Shutdown()
			return
		end

		HEIGHTS = {
			KillerTravel = 150,
			KillerCliffDrop = 50,
			KillerMythicPileOffset = 20,
			KillerMinAscent = 150,
			LureBoat = 15,
			LureEscape = 300,
			LureAscent = 400,
			LureCliffHover = 150,
			LureBoatApproach = 250,
		}

		SPAWN_AHEAD_DIR = Vector3.new(0, 0, -1)
		INSTANT_LURE = { StandSpacing = 12 }

		SKILLS = {
			SoulRayDuration = 5,
			SoulRayCooldown = 20,
			SoulCakeMax = 2,
			SoulCakeCast = 0.5,
			CrumbleshotOccupiedRadius = 0,
			BonBombCast = 1,
			BonFireballCast = 1,
			BonBombCooldown = 12,
			BonFireballCooldown = 3,
			CyborgBarrageTicks = 120,
			CyborgTickInterval = 0.25,
			CyborgCooldown = 20,
			CyborgCast = 1.5,
			MegaPowCooldown = 10,
			MaguHoundCooldown = 15,
			MaguHoundCast = 1,
			MaguFistCooldown = 7,
			MaguFistCast = 1,
			MaguRainTicks = 110,
			MaguRainTickInterval = 0.1,
			MaguRainCooldown = 50,
			SkillInvokeTimeout = 10,
			MaguRetryBackoff = 3,
			LaserPulsarCooldown = 14,
			KatanaSlashNames = {
				"Slash1",
				"Slash2",
				"Slash3",
				"GroundSlash4",
				"GroundSlash5",
			},
			KatanaSwingSpeeds = {
				1.6666666269302368,
				1.6666666269302368,
				1.6666666269302368,
				1.6666666269302368,
				2,
			},
			KatanaComboDelay = 0.15,
			PikaFlightCooldown = 4,
			LeopardInstinctTimeout = 60,
			LeopardM1Delay = 0.4,
			LeopardComboDelay = 0.8,
			LeopardStallTimeout = 45,
			RankyakuReboundCooldown = 19,
		}

		MOVEMENT_DEFAULTS = {
			TrackVerticalOffset = 5,
			TrackPathRefreshInterval = 0.1,
			TrackMovementPrecision = 0.02,
			TrackHardSnapDistance = 200,
			ArrivalDistance = 2,
			StuckCheckInterval = 0.1,
			StuckProgressThreshold = 0.75,
			ForwardProbeHeights = { 1, 4, 8, 12 },
			ObstacleClearance = 1,
			LargeYThreshold = 12,
			LookAheadDistance = 18,
			SnapStepSpeed = 100,
			RaycastOriginY = 2500,
			RaycastLength = 3500,
			CeilingProbeHeight = 20,
			CeilingClearance = 3,
			WallClimbStep = 4,
			WallClimbMaxRise = 200,
			WallFaceMargin = 1,
			SideStepStep = 3,
			SideStepMaxOffset = 24,
			RegroupFollowMargin = 0.85,
			ErrorHoldSpeedPenalty = 0.5,
			ErrorHoldMinSpeedFactor = 0.1,
		}

		STORAGE_DEFAULTS = {
			StoreTakenTimeout = 2,
			StoreConfirmTimeout = 2,
			FruitMaxAttempts = 2,
			FruitRetryBackoff = 60,
			NoBagFruitCapacity = 1,
			EquipVerifyTimeout = 1,
			FruitPickupTimeout = 2,
		}

		COMBAT_TUNING = {
			KillerEngageRadius = 1500,
			KillerPostHeight = 330,
			AnchorKrakenGraceSeconds = 30,
			AnchorMegalodonEngageRadius = 1200,
			AnchorKrakenLoiterRadius = 400,
			AnchorOnlyKrakenEngageRadius = 1200,
			RegroupTweenTime = 10,
			RegroupHoldTime = 3,
		}

		ERROR_HOLD_KEYWORDS = { "tp", "check", "report", "corrected" }
		ERROR_HOLD_FULL_KEYWORDS = { "tp", "check", "report", "corrected" }

		ERROR_HOLD_IGNORE_WORDS = {
			"fruit",
			"fruits",
			"storage",
			"inventory",
			"stored",
			"store",
			"bag",
			"dropped",
			"obtained",
			"received",
		}

		defaultConfig = {
			KillerUseRay = true,
			KillerUseCakes = true,
			KillerUseBonBomb = true,
			KillerUseBonFireball = true,
			KillerUseCyborg = false,
			KillerUseMegaPow = false,
			KillerUseMaguHound = false,
			KillerUseMaguFist = false,
			KillerUseMaguRain = false,
			KillerAttacks = {},
			PauseAttacksDuringCliffRun = true,
			KillerUseBomu = false,
			AnchorUseMegaPow = true,
			AnchorUseRay = false,
			AnchorUseBonBomb = false,
			AnchorUseBonFireball = false,
			AnchorUseCyborg = false,
			AnchorUseMaguHound = false,
			AnchorUseMaguFist = false,
			AnchorUseMaguRain = false,
			AnchorUseBariCage = false,
			AnchorAttacks = {},
			AnchorUseBomu = false,
			AnchorOnlyMode = false,
			LureAnchorOnlyCliffDelivery = false,
			LureAnchorOnlyInstant = false,
			LureBoatSpawnAhead = 185,
			AnchorBariMode = false,
			AnchorBariCageDepth = 50,
			PartySyncEnabled = true,
			KillerRegroupEnemies = false,
			AnchorRegroupEnemies = false,
			RegroupDelay = 120,
			PauseAttacksDuringRegroup = true,
			SafeMode = false,
			LureTravelMethod = {},
			LurePikaFlight = {},
			LureHieTP = {},
			LureDeliveryHold = 20,
			LureRejoinSeconds = 180,
			LureSkipLoadingWait = false,
			LurePickUpFruit = true,
			LureSkipDuplicateFruit = true,
			ShutdownOnOutsider = true,
			EspSubsystemEnabled = true,
			PlaceIndependentModsEnabled = true,
			ErrorHoldEnabled = true,
			ErrorHoldMaxSeconds = 120,
			ErrorKickEnabled = true,
			StatsGuiEnabled = true,
			StatsWebhookEnabled = true,
			StatsWebhookIntervalSeconds = 3600,
			SettingsUiEnabled = true,
			SettingsUiStartOpen = false,
			SettingsUiToggleKey = "RightShift",
			SettingsUiTestTab = false,
			SettingsUiCompact = false,
			DisableOtherPlayerAnimations = true,
			MenuPlaceId = 1730877806,
			Sea = "Second Sea",
			ReservedServerCode = "",
			WebhookUrl = "",
			PingID = "<@>",
			WebhookFooterText = "ball's GKK",
			WebhookFooterIcon = "https://cdn.rovalue.com/grand-piece-online/items/f7e5354f503da794567fb216ed432244.png",
			Roles = {
				Lure1 = "",
				Lure2 = "",
				Lure3 = "",
				Lure4 = "",
				Lure5 = "",
				Lure6 = "",
				Lure7 = "",
				Lure8 = "",
				Lure9 = "",
				Lure10 = "",
				Anchor = "",
				Anchor2 = "",
				Killer = "",
				Killer2 = "",
				Killer3 = "",
			},
		}

		local locations = {
			LureBoatRotation = CFrame.new(0, 0, 0, 0.301784307, -5.55188429e-09, 0.953376234, -4.1366583e-08, 1, 1.89176834e-08, -0.953376234, -4.51469795e-08, 0.301784307),
			LureBoatPositions = {
				Lure1 = Vector3.new(-5429.17402, 190.154846, 7134.77395),
				Lure2 = Vector3.new(-5429.17402, 190.154846, 7284.77395),
				Lure3 = Vector3.new(-5429.17402, 190.154846, 7434.77395),
				Lure4 = Vector3.new(-5279.17402, 190.154846, 6984.77395),
				Lure5 = Vector3.new(-5279.17402, 190.154846, 7134.77395),
				Lure6 = Vector3.new(-5279.17402, 190.154846, 7284.77395),
				Lure7 = Vector3.new(-5279.17402, 190.154846, 7434.77395),
				Lure8 = Vector3.new(-5279.17402, 190.154846, 7584.77395),
				Lure9 = Vector3.new(-5129.17402, 190.154846, 6984.77395),
				Lure10 = Vector3.new(-5129.17402, 190.154846, 7134.77395),
				Lure11 = Vector3.new(-5129.17402, 190.154846, 7284.77395),
				Lure12 = Vector3.new(-5129.17402, 190.154846, 7434.77395),
				Lure13 = Vector3.new(-5129.17402, 190.154846, 7584.77395),
				Lure14 = Vector3.new(-5188.42331, 190.154846, 7252.75666),
				Lure15 = Vector3.new(-5188.42331, 190.154846, 7402.75666),
				Lure16 = Vector3.new(-5188.42331, 190.154846, 7552.75666),
				Lure17 = Vector3.new(-5188.42331, 190.154846, 7702.75666),
				Lure18 = Vector3.new(-5188.42331, 190.154846, 7852.75666),
				Lure19 = Vector3.new(-5038.42331, 190.154846, 7402.75666),
				Lure20 = Vector3.new(-5038.42331, 190.154846, 7552.75666),
				Lure21 = Vector3.new(-5038.42331, 190.154846, 7702.75666),
			},
		}

		local crumbleShotPoints = {
			CFrame.new(-6277.67578, 9.87264538, 8913.21094, 0.988581955, -0.0743633583, -0.131056026, 0.0844201967, 0.993758202, 0.072923623, 0.124815151, -0.0831547379, 0.988689184),
			CFrame.new(-6280.17383, 9.87254143, 8991.3916, -0.993272543, 0.0765274167, 0.0869101211, 0.0830601901, 0.993777156, 0.0742169097, -0.0806896538, 0.0809363499, -0.993447781),
			CFrame.new(-6274.8374, 9.85271931, 8952.75195, -0.203429997, 0.0223190729, -0.978835046, 0.0817547366, 0.996635973, 0.00573398732, 0.975670338, -0.0788579285, -0.204570353),
		}

		locations.CrumbleShotPoints = crumbleShotPoints
		locations.Cliff = CFrame.new(-6424.29297, 383.642029, 8925.86719, 0.885723352, -9.29409438e-08, -0.464213431, 7.48637561e-08, 1, -5.73709364e-08, 0.464213431, 1.60620175e-08, 0.885723352)
		locations.AnchorPoint = anchorPost
		locations.AnchorRegroupPoint = anchorRegroup
		locations.KillerPoint = killerPost
		locations.KillerRegroupPoint = killerRegroup

		locations.KillerPoints = {
			Killer = killerPost,
			Killer2 = offsetCFrame(killerPost, 0, 120),
			Killer3 = offsetCFrame(killerPost, 0, -120),
		}

		locations.KillerRegroupPoints = {
			Killer = killerRegroup,
			Killer2 = offsetCFrame(killerRegroup, 0, 120),
			Killer3 = offsetCFrame(killerRegroup, 0, -120),
		}

		locations.AnchorPoints = { Anchor = anchorPost, Anchor2 = anchor2Post }
		locations.AnchorRegroupPoints = { Anchor = anchorRegroup, Anchor2 = anchorRegroup }
		defaultConfig.Locations = locations
	end

	defaultConfig.Movement = { DefaultSpeed = 100 }
	defaultConfig.Storage = { StoreAttempts = 1 }

	defaultConfig.Fruits = {
		Rarity = {
			Tori = "Mythical",
			Mochi = "Mythical",
			Ope = "Mythical",
			Venom = "Mythical",
			Leopard = "Mythical",
			Buddha = "Mythical",
			Pteranodon = "Mythical",
			Dragon = "Mythical",
			Soul = "Mythical",
			Biscuit = "Legendary",
			Zushi = "Legendary",
			Gura = "Legendary",
			Suna = "Legendary",
			Hie = "Legendary",
			Ito = "Legendary",
			Goro = "Legendary",
			Mera = "Legendary",
			Magu = "Legendary",
			Pika = "Legendary",
			Paw = "Legendary",
			Kage = "Legendary",
			Goru = "Legendary",
			Yami = "Legendary",
			Yuki = "Legendary",
			Smoke = "Legendary",
			Yomi = "Epic",
			Spring = "Epic",
			Kira = "Epic",
			Bari = "Rare",
			Mero = "Rare",
			Horo = "Rare",
			Gomu = "Rare",
			Bomb = "Rare",
			Kilo = "Common",
			Suke = "Common",
			Heal = "Common",
			Spin = "Common",
		},
		Images = {
			Leopard = "https://media.discordapp.net/attachments/1530175088652062790/1544699229472292974/leopard4k.png?ex=6aa400c3&is=6aa2af43&hm=e525105cb94e915d9bcd46fdb494977edb668218afae9374882ec8c5f1d7ed30&=&format=webp&quality=lossless",
			Biscuit = "https://media.discordapp.net/attachments/1530175088652062790/1544699228905930762/biscuit4k.png?ex=6aa400c3&is=6aa2af43&hm=d4e49d07eb58298a7229eeb99907a60301acea48cbbdc1e4e3e7db6e0dcfff62&=&format=webp&quality=lossless",
			Tori = "https://media.discordapp.net/attachments/1530175088652062790/1530175276716130475/tori.png?ex=6a649e47&is=6a634cc7&hm=77664e9c03b7a8811cd1f534e36dead036017aa3b9cd41e79f5c46a50dc3f590&=&format=webp&quality=lossless&width=1415&height=1415",
			Mochi = "https://media.discordapp.net/attachments/1530175088652062790/1530175275982389410/mochi.png?ex=6a649e47&is=6a634cc7&hm=9de3990535d9aed7394ab36d569a4d269f56af4d6b79a340db4abf9ffca3296e&=&format=webp&quality=lossless&width=1415&height=1415",
			Ope = "https://media.discordapp.net/attachments/1530175088652062790/1530175278108905574/opeope.png?ex=6a649e47&is=6a634cc7&hm=4aecdd2b74ddd3182a20a6cf5cfe5d87193da0f6d08d9f7c7aea46fac57156f4&=&format=webp&quality=lossless&width=1415&height=1415",
			Venom = "https://media.discordapp.net/attachments/1530175088652062790/1530175274216591391/venom.png?ex=6a649e46&is=6a634cc6&hm=7063bf4b91c632874962bdf00bb8f03b92d3b16f57f020719a427b1586d2c634&=&format=webp&quality=lossless&width=1415&height=1415",
			Buddha = "https://media.discordapp.net/attachments/1530175088652062790/1530175278838448239/buddha.png?ex=6a649e47&is=6a634cc7&hm=4cdecb7d227aabb613495447113ec4185b0425f15579e4303074295b09aef79e&=&format=webp&quality=lossless&width=1415&height=1415",
			Pteranodon = "https://media.discordapp.net/attachments/1530175088652062790/1530175277462720643/ptero.png?ex=6a649e47&is=6a634cc7&hm=44cf85df4f163e1f65dee59d416d50e8a201ef0012089450413dbbcad69ee515&=&format=webp&quality=lossless&width=1415&height=1415",
			Dragon = "https://media.discordapp.net/attachments/1530175088652062790/1530175274753196152/dragon.png?ex=6a649e46&is=6a634cc6&hm=63ad4e3ccc7fcad88ec35d3cd697966714f33df144dd03bd2941ff457ac02d01&=&format=webp&quality=lossless&width=1415&height=1415al",
			Soul = "https://media.discordapp.net/attachments/1530175088652062790/1530175275248128131/soul.png?ex=6a649e46&is=6a634cc6&hm=a986eadd8c2bd30edc449116fa31dd7eeb13ca28d8630e38b919f956ad4d59d8&=&format=webp&quality=lossless&width=1415&height=1415",
			Pika = "https://images-ext-1.discordapp.net/external/gvW5dkSNrNVs8Gknh3-lquaBmSeB252uKD91PLKupsg/%3Fcb%3D20251127170722/https/static.wikia.nocookie.net/grand-piece-online/images/d/d5/PikaHD.png/revision/latest/scale-to-width-down/1200?format=webp&width=1675&height=1675",
			Rest = "https://images-ext-1.discordapp.net/external/85fNMbUQ4kE7hFSaBmX2yOsJ-0I0UiXeGfIzlTnKQAI/%3Fcb%3D20230711100403/https/static.wikia.nocookie.net/grand-piece-online/images/7/72/DFIconRecreation.png/revision/latest?format=webp&width=1500&height=1500",
		},
		CliffFruits = {},
		WebhookFruits = {},
	}

	defaultConfig.EspPlayerEnabled = false
	defaultConfig.EspBoxesEnabled = true
	defaultConfig.EspBoxColor = Color3.fromRGB(255, 255, 255)
	defaultConfig.EspNamesEnabled = true
	defaultConfig.EspDistanceEnabled = true
	defaultConfig.EspHealthBarEnabled = true
	defaultConfig.EspHealthBarThickness = 1
	defaultConfig.EspChestEnabled = false
	defaultConfig.EspMachineEnabled = false
	defaultConfig.EspIslandSea1Enabled = false
	defaultConfig.EspIslandSea2Enabled = false
	defaultConfig.CombatNoStaminaCost = false
	defaultConfig.CombatNoStun = false
	defaultConfig.QolWalkSpeedEnabled = false
	defaultConfig.QolWalkSpeedValue = 45
	defaultConfig.QolNoclipEnabled = false
	defaultConfig.QolInfiniteJumpEnabled = false
	defaultConfig.QolFieldOfView = 70
	defaultConfig.QolAutoRejoinEnabled = false
	defaultConfig.QolDisplayName = ""
	defaultConfig.QolTeleportSpeed = 89
	defaultConfig.QolIslandGeppoEnabled = true
	defaultConfig.QolRaceRerollTarget = "Human"
	defaultConfig.QolRaceRerollEnabled = false

	for k, fruitRarity in pairs(defaultConfig.Fruits.Rarity) do
		if fruitRarity == "Mythical" or fruitRarity == "Legendary" then
			defaultConfig.Fruits.CliffFruits[k] = true
		end

		defaultConfig.Fruits.WebhookFruits[k] = true
	end

	do
		local function mergeDefaults(target, defaults)
			for k, default in pairs(defaults) do
				local existing = target[k]

				if existing == nil then
					target[k] = default
				elseif type(existing) == "table" and type(default) == "table" then
					mergeDefaults(existing, default)
				end
			end

			return target
		end

		getgenv().KrakenConfig = mergeDefaults(getgenv().KrakenConfig or {}, defaultConfig)
	end
end

----------------------------------------------------------------------------
-- startup: read the config, wait for the game, build the settings window
----------------------------------------------------------------------------
local krakenConfig, locations, movementTuning, storageTuning, rarity, images, cliffFruits, boatSpawns, TeleportService, ReplicatedStorage
local localPlayer, lureBoatRotation
local isFarmSession, espAllowed, placeIndependentModsAllowed, bossRotationEnabled, factoryEnabled, fishingEnabled

do
	local requiredEvents, skipLoadingWait

	krakenConfig = getgenv().KrakenConfig
	krakenConfig.KillerUseMaguHound = false
	krakenConfig.KillerUseMaguFist = false
	krakenConfig.AnchorUseMaguHound = false
	krakenConfig.AnchorUseMaguFist = false
	locations = krakenConfig.Locations

	do
		local function withDefaults(values, defaults)
			return setmetatable({}, {
				__index = function(self, key)
					local value = values[key]
					if value ~= nil then return value end
					return defaults[key]
				end,
				__newindex = function(self, key, value)
					values[key] = value
				end,
			})
		end

		movementTuning = withDefaults(krakenConfig.Movement, MOVEMENT_DEFAULTS)
		storageTuning = withDefaults(krakenConfig.Storage, STORAGE_DEFAULTS)
	end

	rarity = krakenConfig.Fruits.Rarity
	images = krakenConfig.Fruits.Images
	cliffFruits = krakenConfig.Fruits.CliffFruits
	boatSpawns = {}

	lureBoatRotation = locations.LureBoatRotation
	do
		local _k, _p = next(locations.LureBoatPositions)
		while _k ~= nil do
			boatSpawns[_k] = CFrame.new(_p) * lureBoatRotation
			_k, _p = next(locations.LureBoatPositions, _k)
		end
	end

	repeat
		task.wait()
	until game:IsLoaded()

	task.wait(1)

	do
		local Players = cloneref(game:GetService("Players"))
		TeleportService = cloneref(game:GetService("TeleportService"))
		ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
		localPlayer = Players.LocalPlayer
	end

	if not localPlayer then return end
	Core.InitErrorKick({ Config = krakenConfig, LocalPlayer = localPlayer })

	requiredEvents = {
		"ShipEvents",
		"KnockedOut",
		"Skill",
		"faceMouse",
		"Tools",
		"FruitStorage",
	}

	skipLoadingWait = false

	if krakenConfig.LureSkipLoadingWait == true and game.PlaceId == 7465136166 then
		for k, role in pairs(krakenConfig.Roles) do
			if role == localPlayer.Name and k:sub(1, 4) == "Lure" then
				skipLoadingWait = true
				break
			end
		end
	end

	if not skipLoadingWait then
		local deadline = os.clock() + 30
		local playerGui = localPlayer:WaitForChild("PlayerGui")
		local loadingGUI = playerGui:FindFirstChild("LoadingGUI")

		while not loadingGUI and os.clock() < deadline do
			task.wait()
			loadingGUI = playerGui:FindFirstChild("LoadingGUI")
		end

		if loadingGUI then
			while loadingGUI:FindFirstChild("CanvasGroup") and os.clock() < deadline do
				task.wait()
			end
		end

		if os.clock() >= deadline then
			warn("[Kraken] Loading screen still not finished after 30s - continuing anyway.")
		end
	end

	isFarmSession = game.PlaceId ~= krakenConfig.MenuPlaceId and game.PlaceId ~= 11424731604 and game.PlaceId ~= 6360478118
	espAllowed = krakenConfig.EspSubsystemEnabled ~= false
	placeIndependentModsAllowed = krakenConfig.PlaceIndependentModsEnabled ~= false

	do
		local KrakenUi = Modules.KrakenUi()

		if krakenConfig.SettingsUiEnabled then
			local settingsUiToggleKey, toggleKeyCode

			settingsUiToggleKey = krakenConfig.SettingsUiToggleKey

			do
				local hasKey = type(settingsUiToggleKey) == "string" and settingsUiToggleKey ~= ""
				toggleKeyCode = nil

				if hasKey then
					local ok, result = pcall(function()
						return Enum.KeyCode[settingsUiToggleKey]
					end)

					if ok then
						toggleKeyCode = result
					else
						warn("[Settings] '" .. settingsUiToggleKey .. "' is not a KeyCode - no toggle hotkey.")
						toggleKeyCode = nil
					end
				end
			end

			do
				local ok, panel = pcall(KrakenUi, {
					Config = krakenConfig,
					ToggleKeyCode = toggleKeyCode,
					TestTab = krakenConfig.SettingsUiTestTab == true,
					RealFarmSession = isFarmSession,
					EspAllowed = espAllowed,
					PlaceIndependentModsAllowed = placeIndependentModsAllowed,
					Compact = krakenConfig.SettingsUiCompact == true,
				})

				if ok then
					if krakenConfig.SettingsUiStartOpen then panel.Open() end

					print("[Settings] Panel ready - " .. (settingsUiToggleKey ~= "" and settingsUiToggleKey or "the square") .. " opens it.")
				else
					warn("[Settings] Could not build the panel: " .. tostring(panel))
				end
			end
		end
	end

	do
		local bossRotation = krakenConfig.BossRotation
		bossRotationEnabled = type(bossRotation) == "table" and bossRotation.Enabled == true
	end

	do
		local factory = krakenConfig.Factory

		factoryEnabled = type(factory) == "table" and factory.Enabled == true
	end

	do
		local fishing = krakenConfig.Fishing
		fishingEnabled = type(fishing) == "table" and fishing.Enabled == true
	end

	do
		local function hasKiller()
			for _, role in ipairs({ "Killer", "Killer2", "Killer3" }) do
				local username = krakenConfig.Roles[role]
				if type(username) == "string" and username ~= "" then return true end
			end

			return false
		end

		local function isAnchorOnly()
			if krakenConfig.AnchorOnlyMode == true then return true end
			return not hasKiller()
		end

		if krakenConfig.LureAnchorOnlyInstant == true and isAnchorOnly() then
			local anchorX, anchorZ

			do
				local anchorPoint = locations.AnchorPoint

				for _, role in ipairs({ "Anchor", "Anchor2" }) do
					local username = krakenConfig.Roles[role]

					if type(username) == "string" and username ~= "" then
						anchorPoint = locations.AnchorPoints[role] or locations.AnchorPoint
						break
					end
				end

				anchorX = anchorPoint.X
				anchorZ = anchorPoint.Z
			end

			local boatY = select(2, next(locations.LureBoatPositions)).Y
			local standZ = anchorZ - SPAWN_AHEAD_DIR.Z * (tonumber(krakenConfig.LureBoatSpawnAhead) or 185)
			local lureKeys = {}

			for k in pairs(locations.LureBoatPositions) do
				lureKeys[#lureKeys + 1] = k
			end

			table.sort(lureKeys, function(a, b)
				return (tonumber(a:match("%d+")) or 0) < (tonumber(b:match("%d+")) or 0)
			end)

			local standSpacing = INSTANT_LURE.StandSpacing
			local startOffset = -((#lureKeys - 1) / 2) * standSpacing

			for i, lureKey in ipairs(lureKeys) do
				local newVector3 = Vector3.new
				boatSpawns[lureKey] = CFrame.lookAt(Vector3.new(anchorX + startOffset + (i - 1) * standSpacing, boatY, standZ), newVector3(anchorX, boatY, anchorZ))
			end
		end
	end

	if bossRotationEnabled and krakenConfig.Sea ~= "Second Sea" then
		krakenConfig.Sea = "Second Sea"
	end

	if fishingEnabled and not bossRotationEnabled and krakenConfig.Sea ~= "First Sea" then
		krakenConfig.Sea = "First Sea"
	end

	if game.PlaceId == krakenConfig.MenuPlaceId then
		local reservedServerCode = krakenConfig.ReservedServerCode

		if reservedServerCode and reservedServerCode ~= "" then
			local playerGui

			task.spawn(function()
				pcall(function()
					ReplicatedStorage.Events.reserved:InvokeServer(reservedServerCode)
				end)
			end)

			playerGui = localPlayer:WaitForChild("PlayerGui")

			do
				local chooseType = playerGui:WaitForChild("chooseType", 10)

				if chooseType and chooseType:FindFirstChild("Frame") and chooseType.Frame:FindFirstChild("RemoteEvent") then
					chooseType.Frame.RemoteEvent:FireServer(true)
				end
			end

			do
				local chooseType = playerGui:WaitForChild("ChooseType", 5)

				if chooseType and chooseType:FindFirstChild("RemoteEvent") then
					chooseType.RemoteEvent:FireServer(krakenConfig.Sea)
				end
			end

			print("[Kraken] Ran reserved-server code for " .. localPlayer.Name)
		end
	end

	do
		local deadline = os.clock() + 30

		local function isAccountReady()
			local character = localPlayer.Character
			if not character or not character.Parent then return false end

			if not character:FindFirstChild("HumanoidRootPart") then return false end
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if not humanoid or humanoid.Health <= 0 then return false end

			if not localPlayer:FindFirstChildOfClass("Backpack") then return false end
			local inventory = ReplicatedStorage:FindFirstChild("Stats" .. localPlayer.Name)
			inventory = inventory and inventory:FindFirstChild("Inventory")
			if not (inventory and inventory:FindFirstChild("Inventory")) then return false end

			if skipLoadingWait then
				local events = ReplicatedStorage:FindFirstChild("Events")
				if not events then return false end

				for _, eventName in ipairs(requiredEvents) do
					if not events:FindFirstChild(eventName) then return false end
				end
			end

			return true
		end

		while not isAccountReady() do
			if deadline < os.clock() then
				warn("[Kraken] Account still not ready after 30s - starting anyway.")
				break
			else
				task.wait(0.1)
			end
		end
	end
end

----------------------------------------------------------------------------
-- startup: init modules, then run boss rotation / factory / fishing if one of them is on
----------------------------------------------------------------------------
local LureShared, PartySystem, AnchorRole, KillerRole, LureRole

do
	local Travel, FruitInventory, getPositiveNumber, Abilities, getBoolean, npCs

	do
		local StatsGui

		do
			local function onFirstRaycastMovement()
				local ocean = workspace:FindFirstChild("Ocean")
				if not ocean then return end

				local function enableQuery(descendant)
					if descendant:IsA("BasePart") then descendant.CanQuery = true end
				end

				for _, descendant in ipairs(ocean:GetDescendants()) do
					enableQuery(descendant)
				end

				ocean.DescendantAdded:Connect(enableQuery)
				print("[Kraken] Enabled ocean raycasting.")
			end

			getPositiveNumber = positiveNumberOr

			getBoolean = booleanOr

			Travel = Modules.Travel()
			Abilities = Modules.Abilities()
			FruitInventory = Modules.FruitInventory()
			LureShared = Modules.LureShared()
			StatsGui = Modules.StatsGui()
			PartySystem = Modules.PartySystem()
			if PartySystem and PartySystem.Init then
				PartySystem.Init({ LocalPlayer = localPlayer })
			else
				warn("[wyvern] tbl17.t() retornou nil")
			end

			if Travel and Travel.Init then
				Travel.Init({
					Movement = movementTuning,
					isErrorHoldActive = Core.IsErrorHoldActive,
					isFullHoldActive = Core.IsFullHoldActive,
					isCastingActive = Abilities.isMegaPowBarrageActive,
					pauseAntiAfk = Core.pauseAntiAfk,
					resumeAntiAfk = Core.resumeAntiAfk,
					onFirstRaycastMovement = onFirstRaycastMovement,
				})
			else
				warn("[wyvern] tbl17.k() retornou nil")
			end
		end

		Core.Init({
			Config = krakenConfig,
			LocalPlayer = localPlayer,
			ERROR_HOLD_KEYWORDS = ERROR_HOLD_KEYWORDS,
			ERROR_HOLD_IGNORE_WORDS = ERROR_HOLD_IGNORE_WORDS,
			ERROR_HOLD_FULL_KEYWORDS = ERROR_HOLD_FULL_KEYWORDS,
			ERROR_HOLD_POLL_INTERVAL = 0.25,
			getSafeCharacterInfo = Travel and Travel.getSafeCharacterInfo or nil,
			stopMovement = Travel and Travel.stopMovement or nil,
			stopAllFlight = Travel and Travel.stopAllFlight or nil,
		})

		if not bossRotationEnabled then
			if type(krakenConfig.Fishing) ~= "table" then krakenConfig.Fishing = {} end

			if type(krakenConfig.Fishing.Roles) ~= "table" then
				krakenConfig.Fishing.Roles = {}
			end

			Core.startWhitelistWatch({ krakenConfig.Fishing.Roles })
		end

		if espAllowed then
			do
				local _d = Modules.Esp()
				if _d and _d.Init then _d.Init({ Config = krakenConfig }) end
			end
		end

		do
			local CombatTweaks
			local MovementMods

			if placeIndependentModsAllowed then
				CombatTweaks = Modules.CombatTweaks()
				MovementMods = Modules.MovementMods()

				do
					local DisplayNameSpoof = Modules.DisplayNameSpoof()

					if CombatTweaks and CombatTweaks.Init then
						CombatTweaks.Init({
							Config = krakenConfig,
							getWalkSpeedOverride = MovementMods and MovementMods.GetWalkSpeedOverride or nil,
							isMovementActive = Travel and Travel.isFastMovementActive or nil,
						})
					end

					if DisplayNameSpoof and DisplayNameSpoof.Init then
						DisplayNameSpoof.Init({ Config = krakenConfig })
					end
				end
			end

			if isFarmSession and placeIndependentModsAllowed then
				CombatTweaks = CombatTweaks or Modules.CombatTweaks()
				MovementMods = MovementMods or Modules.MovementMods()

				do
					local Teleport = Modules.Teleport()
					local IslandTeleports = Modules.IslandTeleports()
					if Teleport and Teleport.Init then
						Teleport.Init({ Config = krakenConfig })
					end
					if MovementMods and MovementMods.Init then
						MovementMods.Init({
							Config = krakenConfig,
							fireTakestamDirect = CombatTweaks and CombatTweaks.FireTakestamDirect or nil,
							isMovementActive = Travel and Travel.isMoving or nil,
						})
					end

					if IslandTeleports and IslandTeleports.Init then
						IslandTeleports.Init({ Config = krakenConfig })
					end
				end
			end
		end

		npCs = workspace:FindFirstChild("NPCs") or workspace:WaitForChild("NPCs", 5)

		if FruitInventory and FruitInventory.Init then
			FruitInventory.Init({
				fruitRarity = rarity,
				fruitPngs = images,
				fruitCliffSet = cliffFruits,
				Storage = storageTuning,
				PingID = krakenConfig.PingID,
				itemWebhook = Core.itemWebhook,
				mythicalDropWebhook = Core.mythicalDropWebhook,
			})
		end

		if Abilities and Abilities.Init then
			Abilities.Init({
				Skills = SKILLS,
				NPCfolder = npCs,
				Locations = locations,
				getRootCFrame = Travel and Travel.getRootCFrame or nil,
				faceTarget = Travel and Travel.faceTarget or nil,
				setItemEquipped = FruitInventory.setItemEquipped,
				getBackpack = FruitInventory.getBackpack,
			})
		end

		if bossRotationEnabled then
			do
				local farmOptions = {
					Config = krakenConfig,
					Skills = SKILLS,
					StatsGui = StatsGui,
					StatsEnabled = true,
					StatsWidth = 300,
					StatsToggleKey = "RightBracket",
					StatsPollInterval = 1,
					startAntiAfk = Core.startAntiAfk,
					pauseAntiAfk = Core.pauseAntiAfk,
					resumeAntiAfk = Core.resumeAntiAfk,
					postWebhook = Core.postWebhook,
				}

				local ok, farm = pcall(Modules.BossRotation(), farmOptions)
				if not ok then
					warn("[BossRotation] Could not start the farm: " .. tostring(farm))
					return
				end
				farm.Run()
			end

			return
		end

		if factoryEnabled then
			do
				local farmOptions = {
					Config = krakenConfig,
					StatsGui = StatsGui,
					StatsEnabled = true,
					StatsWidth = 300,
					StatsToggleKey = "RightBracket",
					StatsPollInterval = 1,
					startAntiAfk = Core.startAntiAfk,
					pauseAntiAfk = Core.pauseAntiAfk,
					resumeAntiAfk = Core.resumeAntiAfk,
					postWebhook = Core.postWebhook,
				}

				local ok, farm = pcall(Modules.Factory(), farmOptions)
				if not ok then
					warn("[Factory] Could not start the farm: " .. tostring(farm))
					return
				end
				farm.Run()
			end

			return
		end

		if fishingEnabled then
			do
				local farmOptions = {
					Config = krakenConfig,
					StatsGui = StatsGui,
					StatsEnabled = true,
					StatsWidth = 300,
					StatsToggleKey = "RightBracket",
					StatsPollInterval = 1,
					startAntiAfk = Core.startAntiAfk,
					pauseAntiAfk = Core.pauseAntiAfk,
					resumeAntiAfk = Core.resumeAntiAfk,
					postWebhook = Core.postWebhook,
				}

				local ok, farm = pcall(Modules.Fishing(), farmOptions)
				if not ok then
					warn("[Fishing] Could not start the farm: " .. tostring(farm))
					return
				end
				farm.Run()
			end

			return
		end

		if LureShared and LureShared.Init then
			LureShared.Init({
				Config = krakenConfig,
				Locations = locations,
				boatSpawns = boatSpawns,
				StatsGui = StatsGui,
				fruitRarity = rarity,
				LocalPlayer = localPlayer,
				errorHoldCount = Core.ErrorHoldCount,
				postWebhook = Core.postWebhook,
				CombatTuning = COMBAT_TUNING,
				PartySystem = PartySystem,
			})
		end
	end

	local BariCage = Modules.BariCage()

	if BariCage and BariCage.Init then
		BariCage.Init({
			Config = krakenConfig,
			Movement = Travel,
			Attacks = Abilities,
			RoleShared = LureShared,
		})
	end

	AnchorRole = Modules.AnchorRole()
	KillerRole = Modules.KillerRole()
	LureRole = Modules.LureRole()

	local roleOptions = {
		Config = krakenConfig,
		Skills = SKILLS,
		HEIGHTS = HEIGHTS,
		Locations = locations,
		NPCfolder = npCs,
		fruitRarity = rarity,
		fruitPngs = images,
		PingID = krakenConfig.PingID,
		Movement = Travel,
		Attacks = Abilities,
		Storing = FruitInventory,
		QOL = Core,
		RoleShared = LureShared,
		CombatTuning = COMBAT_TUNING,
		BariCage = BariCage,
		getSafeCharacterInfo = Travel and Travel.getSafeCharacterInfo or nil,
		getPositiveNumber = getPositiveNumber,
		getBoolean = getBoolean,
	}

	AnchorRole.Init(roleOptions)
	KillerRole.Init(roleOptions)

	if LureRole and LureRole.Init then
		LureRole.Init({
			Config = krakenConfig,
			Skills = SKILLS,
			HEIGHTS = HEIGHTS,
			Locations = locations,
			fruitRarity = rarity,
			fruitPngs = images,
			PingID = krakenConfig.PingID,
			Movement = Travel,
			Storing = FruitInventory,
			RoleShared = LureShared,
			BariCage = BariCage,
			MovementTuning = movementTuning,
			StorageTuning = storageTuning,
			getPositiveNumber = getPositiveNumber,
			itemWebhook = Core.itemWebhook,
			mythicalDropWebhook = Core.mythicalDropWebhook,
			pauseAntiAfk = Core.pauseAntiAfk,
			resumeAntiAfk = Core.resumeAntiAfk,
			TeleportService = TeleportService,
			ReplicatedStorage = ReplicatedStorage,
			LocalPlayer = localPlayer,
			errorHoldActive = Core.IsErrorHoldActive,
			hasNotificationWords = Core.hasNotificationWords,
		})
	end
end

----------------------------------------------------------------------------
-- startup: kraken farm, every account plays its role (lure, anchor or killer)
----------------------------------------------------------------------------
do
	local myRole, boatSpawn = LureShared.getRole()

	if myRole then Core.startAntiAfk() end

	if myRole and krakenConfig.PartySyncEnabled ~= false then
		if myRole == LureShared.mannedRoles(LureShared.ANCHOR_ROLES)[1] then
			PartySystem.startAutoInvite(function(name)
				for _, role in pairs(krakenConfig.Roles) do
					if role == name then return true end
				end

				return false
			end)
		else
			PartySystem.startAutoAccept()
		end
	end

	local roleKinds = {}

	for _, anchorRole in ipairs(LureShared.ANCHOR_ROLES) do
		roleKinds[anchorRole] = "Anchor"
	end

	for _, killerRole in ipairs(LureShared.KILLER_ROLES) do
		roleKinds[killerRole] = "Killer"
	end

	local roleKind = myRole and roleKinds[myRole]

	if LureShared.anchorOnlyMode() and krakenConfig.AnchorOnlyMode ~= true then
		print("[Kraken] No Killer slot is manned - running anchor-only: lures tow to the Anchor and skip the cliff. Fill in a Killer in Roles for the two-front run.")
	end

	if roleKind == "Anchor" then
		AnchorRole.Run(myRole)
	elseif roleKind == "Killer" then
		if LureShared.anchorOnlyMode() then
			warn("[Kraken] " .. myRole .. " has nothing to do with AnchorOnlyMode on - the lures tow to the Anchor instead. Idling.")
		else
			KillerRole.Run(myRole)
		end
	elseif boatSpawn then
		LureRole.Run(myRole, boatSpawn)
	end
end
