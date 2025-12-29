FishingInfoPanel = {}
local FIP = FishingInfoPanel

-- Database version constants
local DB_VERSION = 2
local DB_VERSION_KEY = "dbVersion"

-- Database migration functions
local function MigrateV1ToV2(db)
	-- V1 databases have no version field and may be missing some fields
	print("|cff00ff00FishingInfoPanel:|r Migrating database from v1 to v2...")

	-- Ensure all required fields exist
	if not db.bySkill then
		db.bySkill = {}
	end

	if not db.config then
		db.config = {
			showCatchMessages = true,
			debugLogging = false
		}
	end

	if not db.catchHistory then
		db.catchHistory = {}
	end

	if not db.castTimes then
		db.castTimes = {}
	end

	if not db.lastCatchTimes then
		db.lastCatchTimes = {}
	end

	-- Add version field
	db[DB_VERSION_KEY] = 2

	print("|cff00ff00FishingInfoPanel:|r Database migration to v2 complete!")
end

-- Migration dispatch table
local migrations = {
	[1] = MigrateV1ToV2,
	-- Future migrations can be added here:
	-- [2] = MigrateV2ToV3,
	-- [3] = MigrateV3ToV4,
}

-- Initialize saved variables structure with versioning
local function InitDB()
	-- Create new database if none exists
	if not FishingInfoPanelDB then
		print("|cff00ff00FishingInfoPanel:|r Creating new database (v" .. DB_VERSION .. ")...")
		FishingInfoPanelDB = {
			[DB_VERSION_KEY] = DB_VERSION,
			allTime = {}, -- [zone][subzone][itemID] = count
			currentSession = {},
			sessionStart = time(),
			-- Skill-based tracking
			bySkill = {}, -- [skillRange][itemID] = count
			-- Configuration settings
			config = {
				showCatchMessages = true,
				debugLogging = false
			},
			-- Catch rate tracking
			catchHistory = {}, -- Array of {time = timestamp, itemID = id}
			-- Cast time tracking
			castTimes = {}, -- Array of cast durations in seconds
			-- Last catch times for time-to-catch calculation
			lastCatchTimes = {} -- [itemID] = timestamp
		}
	else
		-- Existing database - check version and migrate if needed
		local currentVersion = FishingInfoPanelDB[DB_VERSION_KEY] or 1 -- Assume v1 if no version

		if currentVersion < DB_VERSION then
			print("|cff00ff00FishingInfoPanel:|r Database version " .. currentVersion .. " detected, updating to v" .. DB_VERSION)

			-- Run migrations sequentially from current version to target
			for version = currentVersion, DB_VERSION - 1 do
				if migrations[version] then
					migrations[version](FishingInfoPanelDB)
				end
			end
		elseif currentVersion > DB_VERSION then
			-- Database is newer than addon expects - warn but don't break
			print("|cffffff00FishingInfoPanel Warning:|r Database version " .. currentVersion .. " is newer than addon supports (v" .. DB_VERSION .. "). Some features may not work correctly.")
		end
	end

	-- Reset session data on login (always done regardless of version)
	FishingInfoPanelDB.currentSession = {}
	FishingInfoPanelDB.sessionStart = time()
	-- Clear ephemeral session data
	FishingInfoPanelDB.catchHistory = {}
	FishingInfoPanelDB.castTimes = {}
	FishingInfoPanelDB.lastCatchTimes = {}
end

-- State
FIP.showingAllTime = false
FIP.showingBySkill = false
FIP.currentZone = ""
FIP.currentSubzone = ""
FIP.currentSkillRange = ""
FIP.fishRows = {}
FIP.fishingStartTime = nil
FIP.lastTimeToCatch = {}

-- Get current location
local function GetCurrentLocation()
	local zone = GetRealZoneText() or "Unknown"
	local subzone = GetSubZoneText() or "Unknown"
	return zone, subzone
end

-- Get current fishing skill
local function GetFishingSkill()
	local prof1, prof2, archaeology, fishing, cooking = GetProfessions()
	if fishing then
		local name, icon, skillLevel, maxSkillLevel, numAbilities, spelloffset, skillLine, skillModifier = GetProfessionInfo(fishing)
		-- Total skill includes base skill + modifiers (lures, etc)
		local totalSkill = (skillLevel or 0) + (skillModifier or 0)
		return totalSkill, skillLevel, skillModifier
	end
	return 0, 0, 0
end

-- Get skill range for grouping (e.g., "1-50", "51-100", etc.)
-- Modern WoW fishing caps at 300 skill
local function GetSkillRange(skill)
	if skill <= 50 then return "1-50"
	elseif skill <= 100 then return "51-100"
	elseif skill <= 150 then return "101-150"
	elseif skill <= 200 then return "151-200"
	elseif skill <= 250 then return "201-250"
	elseif skill <= 300 then return "251-300"
	else return "300+"
	end
end

-- Calculate catch rate based on 5-minute window
local function GetCatchRate()
	if not FishingInfoPanelDB.catchHistory then
		return 0
	end

	local currentTime = time()
	local cutoffTime = currentTime - 300 -- 5 minutes
	local recentCatches = 0

	-- Count catches in the last 5 minutes
	for _, catch in ipairs(FishingInfoPanelDB.catchHistory) do
		if catch.time > cutoffTime then
			recentCatches = recentCatches + 1
		end
	end

	-- Calculate fish per hour based on 5-minute window
	-- If we have catches, project based on actual time window
	if recentCatches > 0 and #FishingInfoPanelDB.catchHistory > 0 then
		local oldestRecentCatch = currentTime
		for _, catch in ipairs(FishingInfoPanelDB.catchHistory) do
			if catch.time > cutoffTime and catch.time < oldestRecentCatch then
				oldestRecentCatch = catch.time
			end
		end

		local timeWindow = currentTime - oldestRecentCatch
		if timeWindow > 0 then
			local catchesPerSecond = recentCatches / timeWindow
			return catchesPerSecond * 3600 -- Convert to per hour
		end
	end

	return 0
end

-- Calculate mean and median cast times
local function GetCastTimeStats()
	if not FishingInfoPanelDB.castTimes or #FishingInfoPanelDB.castTimes == 0 then
		return 0, 0
	end

	-- Calculate mean
	local sum = 0
	for _, time in ipairs(FishingInfoPanelDB.castTimes) do
		sum = sum + time
	end
	local mean = sum / #FishingInfoPanelDB.castTimes

	-- Calculate median
	local sorted = {}
	for _, time in ipairs(FishingInfoPanelDB.castTimes) do
		table.insert(sorted, time)
	end
	table.sort(sorted)

	local median
	local count = #sorted
	if count % 2 == 0 then
		median = (sorted[count / 2] + sorted[count / 2 + 1]) / 2
	else
		median = sorted[math.ceil(count / 2)]
	end

	return mean, median
end

-- Calculate expected time to catch a specific fish (95% confidence interval)
local function GetExpectedTimeToFish(itemID, zone, subzone)
	if not FishingInfoPanelDB.castTimes or #FishingInfoPanelDB.castTimes < 3 then
		return 0 -- Need at least 3 casts for meaningful statistics
	end

	-- Get all-time catch data for this zone
	local zoneData = FishingInfoPanelDB.allTime[zone]
	if not zoneData or not zoneData[subzone] then
		return 0
	end

	-- Calculate total catches and this fish's catch count
	local totalCatches = 0
	local fishCatches = 0
	for id, count in pairs(zoneData[subzone]) do
		totalCatches = totalCatches + count
		if id == itemID then
			fishCatches = count
		end
	end

	if totalCatches == 0 or fishCatches == 0 then
		return 0
	end

	-- Calculate probability of catching this fish per cast
	local probability = fishCatches / totalCatches

	-- Calculate mean cast time
	local sum = 0
	for _, time in ipairs(FishingInfoPanelDB.castTimes) do
		sum = sum + time
	end
	local meanCastTime = sum / #FishingInfoPanelDB.castTimes

	-- Expected time to catch this fish = mean cast time / probability
	-- For 95% confidence, use geometric distribution quantile
	-- P(X <= k) = 1 - (1-p)^k >= 0.95
	-- k >= log(0.05) / log(1-p)

	-- Check for edge cases to prevent errors
	if probability >= 1 or probability <= 0 then
		if FishingInfoPanelDB.config.debugLogging then
			print(string.format("|cff00ff00FishingInfoPanel Debug:|r Error computing PMF for item %s: invalid probability %.4f", itemID, probability))
		end
		return 0
	end

	local success, expectedCasts = pcall(function()
		return math.log(0.05) / math.log(1 - probability)
	end)

	if not success or expectedCasts <= 0 or expectedCasts == math.huge then
		if FishingInfoPanelDB.config.debugLogging then
			print(string.format("|cff00ff00FishingInfoPanel Debug:|r Error computing PMF projected catch time for item %s", itemID))
		end
		return 0
	end

	local expectedTime = expectedCasts * meanCastTime

	return expectedTime
end

-- Record a fish catch
function FIP:RecordCatch(itemID)
	local zone, subzone = GetCurrentLocation()
	local totalSkill, baseSkill, modifier = GetFishingSkill()
	local skillRange = GetSkillRange(totalSkill)

	-- Initialize structures if needed
	FishingInfoPanelDB.allTime[zone] = FishingInfoPanelDB.allTime[zone] or {}
	FishingInfoPanelDB.allTime[zone][subzone] = FishingInfoPanelDB.allTime[zone][subzone] or {}

	FishingInfoPanelDB.currentSession[zone] = FishingInfoPanelDB.currentSession[zone] or {}
	FishingInfoPanelDB.currentSession[zone][subzone] = FishingInfoPanelDB.currentSession[zone][subzone] or {}

	FishingInfoPanelDB.bySkill[skillRange] = FishingInfoPanelDB.bySkill[skillRange] or {}

	-- Increment counts
	FishingInfoPanelDB.allTime[zone][subzone][itemID] = (FishingInfoPanelDB.allTime[zone][subzone][itemID] or 0) + 1
	FishingInfoPanelDB.currentSession[zone][subzone][itemID] = (FishingInfoPanelDB.currentSession[zone][subzone][itemID] or 0) + 1
	FishingInfoPanelDB.bySkill[skillRange][itemID] = (FishingInfoPanelDB.bySkill[skillRange][itemID] or 0) + 1

	-- Record catch time for catch rate tracking
	table.insert(FishingInfoPanelDB.catchHistory, {
		time = time(),
		itemID = itemID
	})

	-- Clean up old catches (keep only last 5 minutes)
	local cutoffTime = time() - 300 -- 5 minutes in seconds
	local newHistory = {}
	for _, catch in ipairs(FishingInfoPanelDB.catchHistory) do
		if catch.time > cutoffTime then
			table.insert(newHistory, catch)
		end
	end
	FishingInfoPanelDB.catchHistory = newHistory

	-- Catch logging (if enabled)
	if FishingInfoPanelDB.config.showCatchMessages then
		local itemName = GetItemInfo(itemID) or ("Item " .. itemID)
		local castTimeText = ""
		if FIP.fishingStartTime then
			local castDuration = GetTime() - FIP.fishingStartTime
			castTimeText = string.format(" (%.1fs)", castDuration)
		end

		local skillText
		if modifier > 0 then
			skillText = string.format("(%d+%d)", baseSkill, modifier)
		else
			skillText = string.format("(%d)", baseSkill)
		end

		print(string.format("|cff00ff00FishingInfoPanel:|r Caught %s %s%s",
			itemName, skillText, castTimeText))
	end

	-- Debug logging (if enabled)
	if FishingInfoPanelDB.config.debugLogging then
		local itemName = GetItemInfo(itemID) or ("Item " .. itemID)
		print(string.format("|cff00ff00FishingInfoPanel Debug:|r Caught %s (Total: %d [Base: %d + Modifier: %d]) in %s - %s (Range: %s)",
			itemName, totalSkill, baseSkill, modifier, zone, subzone, skillRange))
	end

	-- Record cast time if we have a start time
	if FIP.fishingStartTime then
		local castDuration = GetTime() - FIP.fishingStartTime
		table.insert(FishingInfoPanelDB.castTimes, castDuration)

		-- Keep only last 20 cast times
		if #FishingInfoPanelDB.castTimes > 20 then
			table.remove(FishingInfoPanelDB.castTimes, 1)
		end

		FIP.fishingStartTime = nil
	end

	-- Calculate time to catch this fish and store last catch time
	local currentTime = time()
	local previousCatchTime = FishingInfoPanelDB.lastCatchTimes[itemID] or FishingInfoPanelDB.sessionStart
	local timeToCatch = currentTime - previousCatchTime

	-- Store this catch time for future calculations
	FishingInfoPanelDB.lastCatchTimes[itemID] = currentTime

	-- Store the time to catch for display (we'll add this to the fish data structure)
	FIP.lastTimeToCatch = FIP.lastTimeToCatch or {}
	FIP.lastTimeToCatch[itemID] = timeToCatch

	-- Update display if showing current zone
	if FishingInfoPanelFrame:IsShown() then
		FIP:UpdateDisplay()
	end
end

-- Calculate percentages and get fish data
local function GetFishData(zone, subzone, useAllTime)
	local data = useAllTime and FishingInfoPanelDB.allTime or FishingInfoPanelDB.currentSession
	local allTimeData = FishingInfoPanelDB.allTime[zone] and FishingInfoPanelDB.allTime[zone][subzone]

	-- If showing session, but no all-time data exists, use session data only
	if not useAllTime and not allTimeData then
		if not data[zone] or not data[zone][subzone] then
			return {}
		end
	elseif not data[zone] or not data[zone][subzone] then
		-- If showing all-time and no data, return empty
		if useAllTime then
			return {}
		end
		-- If showing session and no session data, create empty structure
		data[zone] = data[zone] or {}
		data[zone][subzone] = {}
	end

	local fishData = {}
	local junkData = {
		itemID = "JUNK",
		name = "Junk",
		icon = "Interface\\Icons\\INV_Misc_Bag_10",  -- Generic bag icon for junk
		count = 0,
		percentage = 0,
		color = {0.5, 0.5, 0.5}  -- Gray color for junk
	}
	local total = 0

	-- Calculate total for current view
	if data[zone] and data[zone][subzone] then
		for itemID, count in pairs(data[zone][subzone]) do
			total = total + count
		end
	end

	-- When showing session, include all items from all-time with 0 counts
	local itemsToProcess = {}

	-- First, add all current data items
	if data[zone] and data[zone][subzone] then
		for itemID, count in pairs(data[zone][subzone]) do
			itemsToProcess[itemID] = count
		end
	end

	-- If showing session, add any all-time items not in session with 0 count
	if not useAllTime and allTimeData then
		for itemID, _ in pairs(allTimeData) do
			if not itemsToProcess[itemID] then
				itemsToProcess[itemID] = 0
			end
		end
	end

	-- Build fish data with percentages
	for itemID, count in pairs(itemsToProcess) do
		local itemName, _, itemQuality, _, _, _, _, _, _, itemIcon = GetItemInfo(itemID)

		-- Check if item is junk (gray quality = 0)
		if itemQuality == 0 then
			junkData.count = junkData.count + count
		else
			local currentPct = total > 0 and (count / total) * 100 or 0
			local color = {1, 1, 1} -- white default

			-- Compare to all-time if showing session
			if not useAllTime and FishingInfoPanelDB.allTime[zone] and FishingInfoPanelDB.allTime[zone][subzone] then
				local allTimeData = FishingInfoPanelDB.allTime[zone][subzone]
				local allTimeTotal = 0
				for _, c in pairs(allTimeData) do
					allTimeTotal = allTimeTotal + c
				end

				if allTimeTotal > 0 then
					local allTimePct = ((allTimeData[itemID] or 0) / allTimeTotal) * 100
					-- Only apply color if the item was caught this session
					if count > 0 then
						if currentPct > allTimePct + 0.5 then
							color = {0, 1, 0} -- green - above average
						elseif currentPct < allTimePct - 0.5 then
							color = {1, 0, 0} -- red - below average
						end
					else
						-- Items not caught this session show in gray
						color = {0.5, 0.5, 0.5}
					end
				end
			end

			table.insert(fishData, {
				itemID = itemID,
				name = itemName or ("Loading..."),
				icon = itemIcon or "Interface\\Icons\\INV_Misc_QuestionMark",
				count = count,
				percentage = currentPct,
				color = color
			})
		end
	end

	-- Check if junk exists in all-time data when showing session
	local allTimeJunkExists = false
	if not useAllTime and allTimeData then
		for itemID, _ in pairs(allTimeData) do
			local _, _, itemQuality = GetItemInfo(itemID)
			if itemQuality == 0 then
				allTimeJunkExists = true
				break
			end
		end
	end

	-- Add junk data if any junk was found (current or historical)
	if junkData.count > 0 or allTimeJunkExists then
		junkData.percentage = total > 0 and (junkData.count / total) * 100 or 0

		-- Compare junk percentage to all-time if showing session
		if not useAllTime and FishingInfoPanelDB.allTime[zone] and FishingInfoPanelDB.allTime[zone][subzone] then
			local allTimeData = FishingInfoPanelDB.allTime[zone][subzone]
			local allTimeTotal = 0
			local allTimeJunkCount = 0

			-- Calculate all-time totals and junk count
			for itemID, count in pairs(allTimeData) do
				allTimeTotal = allTimeTotal + count
				local _, _, itemQuality = GetItemInfo(itemID)
				if itemQuality == 0 then
					allTimeJunkCount = allTimeJunkCount + count
				end
			end

			if allTimeTotal > 0 then
				local allTimeJunkPct = (allTimeJunkCount / allTimeTotal) * 100
				-- Only apply colors if junk was caught this session
				if junkData.count > 0 then
					if junkData.percentage < allTimeJunkPct - 0.5 then
						junkData.color = {0, 1, 0} -- green - lower junk than usual
					elseif junkData.percentage > allTimeJunkPct + 0.5 then
						junkData.color = {1, 0, 0} -- red - higher junk than usual
					else
						junkData.color = {1, 1, 1} -- white - same as usual
					end
				else
					-- No junk caught this session, show in gray
					junkData.color = {0.5, 0.5, 0.5}
				end
			end
		end

		table.insert(fishData, junkData)
	end

	-- Sort by count descending
	table.sort(fishData, function(a, b) return a.count > b.count end)

	return fishData
end

-- Calculate percentages and get fish data by skill
local function GetFishDataBySkill(skillRange)
	local data = FishingInfoPanelDB.bySkill[skillRange]

	if not data then
		return {}
	end

	local fishData = {}
	local junkData = {
		itemID = "JUNK",
		name = "Junk",
		icon = "Interface\\Icons\\INV_Misc_Bag_10",
		count = 0,
		percentage = 0,
		color = {0.5, 0.5, 0.5}
	}
	local total = 0

	-- Calculate total
	for itemID, count in pairs(data) do
		total = total + count
	end

	if total == 0 then return {} end

	-- Build fish data with percentages
	for itemID, count in pairs(data) do
		local itemName, _, itemQuality, _, _, _, _, _, _, itemIcon = GetItemInfo(itemID)

		-- Check if item is junk (gray quality = 0)
		if itemQuality == 0 then
			junkData.count = junkData.count + count
		else
			local currentPct = (count / total) * 100

			table.insert(fishData, {
				itemID = itemID,
				name = itemName or ("Loading..."),
				icon = itemIcon or "Interface\\Icons\\INV_Misc_QuestionMark",
				count = count,
				percentage = currentPct,
				color = {1, 1, 1}
			})
		end
	end

	-- Add junk data if any junk was found
	if junkData.count > 0 then
		junkData.percentage = (junkData.count / total) * 100
		table.insert(fishData, junkData)
	end

	-- Sort by count descending
	table.sort(fishData, function(a, b) return a.count > b.count end)

	return fishData
end

-- Update the display
function FIP:UpdateDisplay()
	local fishData

	if FIP.showingBySkill then
		-- Show data by skill range
		local totalSkill = GetFishingSkill()
		local skillRange = GetSkillRange(totalSkill)
		FIP.currentSkillRange = skillRange

		-- Update zone info for skill view
		local baseSkill, modifier
		totalSkill, baseSkill, modifier = GetFishingSkill()

		FishingInfoPanelFrameZoneInfoZoneName:SetText("Skill Range: " .. skillRange)
		if modifier > 0 then
			FishingInfoPanelFrameZoneInfoSubzoneName:SetText(string.format("Fishing Skill: %d (+%d) = %d", baseSkill, modifier, totalSkill))
		else
			FishingInfoPanelFrameZoneInfoSubzoneName:SetText("Fishing Skill: " .. baseSkill)
		end

		-- Update toggle button
		FishingInfoPanelFrameToggleButton:SetText("Show by Zone")

		-- Get fish data by skill
		fishData = GetFishDataBySkill(skillRange)
	else
		-- Show data by zone
		local zone, subzone = GetCurrentLocation()
		FIP.currentZone = zone
		FIP.currentSubzone = subzone

		-- Update zone info
		FishingInfoPanelFrameZoneInfoZoneName:SetText(zone)
		FishingInfoPanelFrameZoneInfoSubzoneName:SetText(subzone)

		-- Update toggle button
		local buttonText = FIP.showingAllTime and "Show Current Session" or "Show All Time"
		FishingInfoPanelFrameToggleButton:SetText(buttonText)

		-- Get fish data by zone
		fishData = GetFishData(zone, subzone, FIP.showingAllTime)
	end

	-- Clear existing rows
	for _, row in ipairs(FIP.fishRows) do
		row:Hide()
	end

	-- Create/update rows
	local yOffset = 0
	for i, fish in ipairs(fishData) do
		local row = FIP.fishRows[i]

		if not row then
			row = CreateFrame("Frame", nil, FishingInfoPanelFrameScrollFrameScrollChild)
			row:SetSize(420, 30)

			-- Icon
			row.icon = row:CreateTexture(nil, "ARTWORK")
			row.icon:SetSize(24, 24)
			row.icon:SetPoint("LEFT", 5, 0)

			-- Name
			row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
			row.name:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
			row.name:SetWidth(135)
			row.name:SetJustifyH("LEFT")

			-- Count
			row.count = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
			row.count:SetPoint("LEFT", row, "LEFT", 200, 0)
			row.count:SetWidth(40)
			row.count:SetJustifyH("CENTER")

			-- Percentage
			row.percentage = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
			row.percentage:SetPoint("LEFT", row, "LEFT", 250, 0)
			row.percentage:SetWidth(50)
			row.percentage:SetJustifyH("CENTER")

			-- Expected time
			row.expectedTime = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			row.expectedTime:SetPoint("LEFT", row, "LEFT", 305, 0)
			row.expectedTime:SetWidth(50)
			row.expectedTime:SetJustifyH("CENTER")

			-- Actual time
			row.actualTime = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			row.actualTime:SetPoint("LEFT", row, "LEFT", 365, 0)
			row.actualTime:SetWidth(50)
			row.actualTime:SetJustifyH("RIGHT")

			FIP.fishRows[i] = row
		end

		row:SetPoint("TOPLEFT", 0, -yOffset)
		row.icon:SetTexture(fish.icon)
		row.name:SetText(fish.name)
		row.count:SetText(fish.count)
		row.percentage:SetText(string.format("%.1f%%", fish.percentage))
		row.percentage:SetTextColor(unpack(fish.color))

		-- Calculate and display expected time to catch this fish
		local expectedTime = GetExpectedTimeToFish(fish.itemID, FIP.currentZone, FIP.currentSubzone)
		if expectedTime > 0 and expectedTime < 3600 then -- Less than 1 hour
			if expectedTime < 60 then
				row.expectedTime:SetText(string.format("%.0fs", expectedTime))
			else
				row.expectedTime:SetText(string.format("%.1fm", expectedTime / 60))
			end
			row.expectedTime:SetTextColor(0.7, 0.7, 1.0) -- Light blue
		elseif expectedTime >= 3600 then -- More than 1 hour
			row.expectedTime:SetText(">1h")
			row.expectedTime:SetTextColor(0.5, 0.5, 0.7) -- Darker blue
		else
			-- No data or not ready
			local castTimeCount = FishingInfoPanelDB.castTimes and #FishingInfoPanelDB.castTimes or 0
			if castTimeCount < 3 then
				row.expectedTime:SetText("---")
				row.expectedTime:SetTextColor(0.5, 0.5, 0.5) -- Gray
			else
				row.expectedTime:SetText("n/a")
				row.expectedTime:SetTextColor(0.5, 0.5, 0.5) -- Gray
			end
		end

		-- Display actual time to catch this fish
		local actualTime = FIP.lastTimeToCatch[fish.itemID]
		if actualTime and actualTime > 0 then
			local timeText
			if actualTime < 60 then
				timeText = string.format("%.0fs", actualTime)
			elseif actualTime < 3600 then
				timeText = string.format("%.1fm", actualTime / 60)
			else
				timeText = string.format("%.1fh", actualTime / 3600)
			end
			row.actualTime:SetText(timeText)

			-- Color code based on comparison with expected time
			if expectedTime > 0 then
				if actualTime < expectedTime then
					row.actualTime:SetTextColor(0, 1, 0) -- Green - faster than expected
				elseif actualTime > expectedTime then
					row.actualTime:SetTextColor(1, 0, 0) -- Red - slower than expected
				else
					row.actualTime:SetTextColor(0.8, 0, 1) -- Purple - exactly as expected
				end
			else
				row.actualTime:SetTextColor(0.7, 1.0, 0.7) -- Default light green
			end
		else
			row.actualTime:SetText("")
		end

		row:Show()

		yOffset = yOffset + 32
	end

	-- Update scroll child height
	FishingInfoPanelFrameScrollFrameScrollChild:SetHeight(math.max(290, yOffset))

	-- Update catch rate and cast time display
	local catchRate = GetCatchRate()
	local meanCast, medianCast = GetCastTimeStats()

	local statsText
	local castTimeCount = FishingInfoPanelDB.castTimes and #FishingInfoPanelDB.castTimes or 0

	if castTimeCount == 0 then
		statsText = string.format("Fish/hr: %.1f | Cast times: No data yet", catchRate)
	elseif castTimeCount < 3 then
		-- Warming up - need at least 3 casts for PMF calculations
		statsText = string.format("Fish/hr: %.1f | Cast: %.1fs/%.1fs |cffff9900 [Cast history warming up %d/3]|r",
			catchRate, meanCast, medianCast, castTimeCount)
	else
		-- Warmed up - ready for PMF calculations
		statsText = string.format("Fish/hr: %.1f | Cast: %.1fs/%.1fs |cff00ff00 [Cast history ready]|r",
			catchRate, meanCast, medianCast)
	end

	FishingInfoPanelFrameCatchRateFrameText:SetText(statsText)
end

-- Toggle between session and all-time view
function FIP:ToggleView()
	if FIP.showingBySkill then
		-- Switch back to zone view
		FIP.showingBySkill = false
	else
		-- Toggle between session and all-time in zone view
		FIP.showingAllTime = not FIP.showingAllTime
	end
	FIP:UpdateDisplay()
end

-- Toggle to skill-based view
function FIP:ToggleSkillView()
	FIP.showingBySkill = not FIP.showingBySkill
	FIP:UpdateDisplay()
end

-- Toggle catch messages
function FIP:ToggleCatchMessages()
	FishingInfoPanelDB.config.showCatchMessages = not FishingInfoPanelDB.config.showCatchMessages
	local status = FishingInfoPanelDB.config.showCatchMessages and "enabled" or "disabled"
	print("|cff00ff00FishingInfoPanel:|r Catch messages " .. status)
end

-- Toggle debug logging
function FIP:ToggleDebugLogging()
	FishingInfoPanelDB.config.debugLogging = not FishingInfoPanelDB.config.debugLogging
	local status = FishingInfoPanelDB.config.debugLogging and "enabled" or "disabled"
	print("|cff00ff00FishingInfoPanel:|r Debug logging " .. status)
end

-- Show configuration
function FIP:ShowConfig()
	print("|cff00ff00FishingInfoPanel Configuration:|r")
	print("  Catch messages: " .. (FishingInfoPanelDB.config.showCatchMessages and "enabled" or "disabled"))
	print("  Debug logging: " .. (FishingInfoPanelDB.config.debugLogging and "enabled" or "disabled"))
	print("  Database version: " .. (FishingInfoPanelDB[DB_VERSION_KEY] or "unknown"))
	print("Commands: /fip catch, /fip debug, /fip config")
end

-- Toggle frame visibility
function FIP:ToggleFrame()
	if FishingInfoPanelFrame:IsShown() then
		FishingInfoPanelFrame:Hide()
	else
		FishingInfoPanelFrame:Show()
		FIP:UpdateDisplay()
	end
end

-- Calculate total items in cache
local function GetCacheSize()
	local totalItems = 0
	if FishingInfoPanelDB and FishingInfoPanelDB.allTime then
		for zone, subzones in pairs(FishingInfoPanelDB.allTime) do
			for subzone, items in pairs(subzones) do
				for itemID, count in pairs(items) do
					totalItems = totalItems + count
				end
			end
		end
	end
	return totalItems
end

-- Event handler
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("LOOT_OPENED")
eventFrame:RegisterEvent("ZONE_CHANGED")
eventFrame:RegisterEvent("ZONE_CHANGED_INDOORS")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
	if event == "ADDON_LOADED" then
		local addonName = ...
		if addonName == "FishingInfoPanel" then
			InitDB()

			-- Set up backdrop
			FishingInfoPanelFrame:SetBackdrop({
				bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
				edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
				tile = false,
				edgeSize = 32,
				insets = { left = 11, right = 12, top = 12, bottom = 11 }
			})
			FishingInfoPanelFrame:SetBackdropColor(1, 1, 1, 1)

			-- Register slash command
			SLASH_FISHINGINFO1 = "/fishinfo"
			SLASH_FISHINGINFO2 = "/fip"
			SlashCmdList["FISHINGINFO"] = function(msg)
				msg = msg:lower():trim()
				if msg == "skill" then
					FIP:ToggleSkillView()
				elseif msg == "catch" then
					FIP:ToggleCatchMessages()
				elseif msg == "debug" then
					FIP:ToggleDebugLogging()
				elseif msg == "config" then
					FIP:ShowConfig()
				else
					FIP:ToggleFrame()
				end
			end

			local cacheSize = GetCacheSize()
			print(string.format("|cff00ff00Fishing Info Panel loaded! Use /fip config for settings. Cache: %d catches|r", cacheSize))
		end
	elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
		local unit, castGUID, spellID = ...
		if unit == "player" then
			local name, text, texture, startTimeMS, endTimeMS = UnitChannelInfo("player")
			if name == "Fishing" then
				FIP.fishingStartTime = GetTime()
				if FishingInfoPanelDB.config.debugLogging then
					print("|cff00ff00FishingInfoPanel Debug:|r Fishing channel started")
				end
			end
		end
	elseif event == "LOOT_OPENED" then
		-- Check if this is fishing loot using the WoW API
		if IsFishingLoot() then

			local numItems = GetNumLootItems()

			for i = 1, numItems do
				local itemLink = GetLootSlotLink(i)
				if itemLink then
					local itemID = tonumber(itemLink:match("item:(%d+)"))
					if itemID then
						FIP:RecordCatch(itemID)
					end
				end
			end
		end
	elseif event:find("ZONE_CHANGED") then
		if FishingInfoPanelFrame:IsShown() then
			FIP:UpdateDisplay()
		end
	elseif event == "GET_ITEM_INFO_RECEIVED" then
		-- Update display when item info becomes available
		if FishingInfoPanelFrame:IsShown() then
			FIP:UpdateDisplay()
		end
	end
end)
