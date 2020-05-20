-- ==============================================================
--	GiftItToMe
--  Script for the actual "gifting"-action and maintenance checks
-- ==============================================================

-- Debugging mode switch
local debugMode = true;

-- Units and player variables
local currentPromotions = {};
local giftingPlayer = nil;
local recipientPlayer = nil;
local recievedUnit = nil;
local giftingUnit = nil;
local giftedUnitsTracker = {};
local freedResourceYields = {};
local freedResourceYieldTypes = {
	RESOURCE_COAL = 0,
	RESOURCE_OIL = 0,
	RESOURCE_ALUMINUM = 0,
	RESOURCE_URANIUM = 0
};

-- Unit property variables
local giftingUnitX = nil;
local giftingUnitY = nil;
local giftingUnitType = nil;
local giftingUnitName = nil;
local giftingUnitMilitaryFormation = nil;
local giftingUnitReligionType = nil;

-- Constants
-- Define how much unit maintenance-cost is max allowed
-- compared to current yields to keep gifted units (percent)
MAINTENANCE_GOLD_QUOTA_MAX = 85;					-- If maintenance eats more than X% gold-yield, destroy gifted units
MAINTENANCE_XP2_COAL_QUOTA_MAX = 80;			-- If maintenance eats more than X% coal-yield, destroy gifted coal-units
MAINTENANCE_XP2_OIL_QUOTA_MAX = 80;				-- If maintenance eats more than X% oil-yield, destroy gifted oil-units
MAINTENANCE_XP2_ALUMINUM_QUOTA_MAX = 80;	-- If maintenance eats more than X% aluminum-yield, destroy gifted aluminum-units
MAINTENANCE_XP2_URANIUM_QUOTA_MAX = 80;		-- If maintenance eats more than X% uranium-yield, destroy gifted uranium-units

-- Gift the unit from one player to another
-- For real guys, this game has no "ownership"-handling for modding
function OnGiftItNow(giftingPlayerId, recipientPlayerId, giftingUnitId)
	-- Memorize which promotions the unit has
	currentPromotions = {};

	-- Fetch the real stuff instead of numbers
	giftingPlayer = Players[giftingPlayerId];
	recipientPlayer = Players[recipientPlayerId];
	giftingUnit = giftingPlayer:GetUnits():FindID(giftingUnitId);

	-- If everything is real, go on
	if (giftingPlayer ~= nill and recipientPlayer ~= nil and giftingUnit ~= nil) then
		-- Memorize unit related stuff
		giftingUnitX = giftingUnit:GetX();
		giftingUnitY = giftingUnit:GetY();
		giftingUnitType = GameInfo.Units[giftingUnit:GetType()].UnitType;
		giftingUnitName = GameInfo.Units[giftingUnit:GetType()].Name;
		giftingUnitMilitaryFormation = giftingUnit:GetMilitaryFormation();
		giftingUnitReligionType = giftingUnit:GetReligion():GetReligionType();

		-- Memorize which promotions the unit has... already had that comment, hmm, ok this is the real memorizer
		for gPromotion in GameInfo.UnitPromotions() do
			if (GameInfo.Units[giftingUnit:GetType()].PromotionClass == gPromotion.PromotionClass) then
				if (gPromotion ~= nil and giftingUnit:GetExperience():HasPromotion(gPromotion.Index)) then
					table.insert(currentPromotions, gPromotion.Index)	-- MEM-O-RIZE
				end
			end
		end

		-- Gifting player loses his unit, its a gift afterall huh...
		UnitManager.Kill(giftingUnit);

		-- The lucky guy will get exact the same unit... but new and shiny...
		recievedUnit = UnitManager.InitUnit(recipientPlayer, giftingUnitType, giftingUnitX, giftingUnitY);

		-- Add the gifted unit to the tracking
		TrackGiftedUnit(recipientPlayerId, recievedUnit:GetID(), giftingPlayerId)

		-- Since a unit "changed" the owner, inform the gift-counter about this (persist data), see GiftUnit.lua::Initialize
		GameEvents.AddGiftThisTurn.Call(giftingPlayerId, recipientPlayerId);

		-- Handle reactions of other players to the gift process (AI may denounce, other humans get an info)
		GameEvents.HandleGiftReactions.Call(giftingPlayerId, recipientPlayerId, giftingUnitName, giftingUnitX, giftingUnitY);
	end
end

-- Populate the new received unit with promotions and formation
function PolulateItNow()
	-- New unit is real?
	if recievedUnit ~= nil then
		-- ... with promotions, if the "old" unit had any
		if #currentPromotions > 0 then
			for _, promotionIndex in ipairs(currentPromotions) do
				recievedUnit:GetExperience():SetPromotion(promotionIndex);
			end
		end

		-- Also dont forget to set the correct military formation type
		if (giftingUnitMilitaryFormation ~= nil and giftingUnitMilitaryFormation > 0) then
			recievedUnit:SetMilitaryFormation(giftingUnitMilitaryFormation);
		end

		-- In case it was a religious unit...
		if (giftingUnitReligionType ~= nil and giftingUnitReligionType > 0) then
			-- ...set the religion according to the gifted unit
			recievedUnit:GetReligion():SetReligionType(giftingUnitReligionType);

			-- Helper-event to get a updated unit object within UI context to update the UnitFlag properly
			-- @Fairaxis: Why the f.. hell is there no UnitReligionChange-Event like it is for cities!?
			UnitManager.PlaceUnit(recievedUnit, giftingUnitX, giftingUnitY);
		end
	end
end

-- Actual pay process for a gift
function OnPayForGiftingGameEvent (localPlayerID, params)
	-- Fetch parameters
	local gPlayerId = params.giftingPlayerId;
	local gPlayer = Players[gPlayerId];
	local amount = params.giftingUnitCost;

	-- Player is real
	if gPlayer ~= nil then
		-- Let him pay as requested
		gPlayer:GetTreasury():ChangeGoldBalance((0 - amount));
	end
end

-- Gold change for simulated deal
function OnGoldChangeGameEvent (localPlayerID, params)
	-- Fetch parameters
	local playerId = params.playerId;
	local player = Players[playerId];
	local amount = params.amount;

	-- Player is real
	if player ~= nil then
		-- Let him pay as requested
		player:GetTreasury():ChangeGoldBalance(amount);
	end
end

-- Event function (called from UI [Init] -> [OnStart])
function OnGiftUnitGameEvent(localPlayerID, params)
	OnGiftItNow(params.giftingPlayerID, params.recipientPlayerID, params.giftingUnitID);
end

-- Event function (called from UI [Init] -> [OnStart])
function OnPopulateUnitGameEvent(localPlayerID, params)
	PolulateItNow();
end

-- Debug function for logging
function WriteToLog(message)
	if (debugMode and message ~= nil) then
		print(message);
	end
end

-- Callback for sending a warning notification from AI to human player for supporting enemies
function OnSendWarningGameEvent(localPlayerID, params)
	-- Logging
	WriteToLog("OnSendWarningGameEvent");

	-- Fetch player data
	local sendingPlayer = Players[params.sPlayerId];
	local receivingPlayer = Players[params.rPlayerId];
	local sPlayerConfig = PlayerConfigurations[params.sPlayerId];

	-- Logging
	WriteToLog("Sending/Receiving Player"..params.sPlayerId.."/"..params.rPlayerId);
	WriteToLog("UnitX/Y"..params.gUnitX.."/"..params.gUnitY);

	-- Construct the message and send the notification
	local headline = Locale.Lookup("LOC_GIFTITTOME_WARNING_HEADLINE", sPlayerConfig:GetLeaderName());
	local content = Locale.Lookup("LOC_GIFTITTOME_WARNING_CONTENT");
	NotificationManager.SendNotification(params.rPlayerId, 96, headline, content, params.gUnitX, params.gUnitY);
end

-- Callback for sending a info notification from human to human player for gifting a unit
function OnSendInfoGameEvent(localPlayerID, params)
	-- Logging
	WriteToLog("OnSendInfoGameEvent");

	-- Fetch player data
	local sendingPlayer = Players[params.sPlayerId];
	local receivingPlayer = Players[params.rPlayerId];
	local sPlayerConfig = PlayerConfigurations[params.sPlayerId];

	-- Logging
	WriteToLog("Sending/Receiving Player"..params.sPlayerId.."/"..params.rPlayerId);
	WriteToLog("UnitX/Y"..params.gUnitX.."/"..params.gUnitY);
	WriteToLog("Unit Name"..params.gUnitName);

	-- Construct the message and send the notification
	local headline = Locale.Lookup("LOC_GIFTITTOME_INFO_HEADLINE", sPlayerConfig:GetLeaderName());
	local content = Locale.Lookup("LOC_GIFTITTOME_INFO_CONTENT", params.gUnitName);
	NotificationManager.SendNotification(params.rPlayerId, 94, headline, content, params.gUnitX, params.gUnitY);
end

-- Serialize a table to a string for persistance
function SerializeGiftedUnits()
	-- Initialize empty string
	local giftedUnitsSerializedAllPlayers = "";

	-- Loop the values
	for playerId, giftedUnits in ipairs(giftedUnitsTracker) do
		local giftedUnitsSerialized = "";

		-- Sub-loop
		for giftedUnitId, giftingPlayerId in pairs(giftedUnits) do
			giftedUnitsSerialized = giftedUnitsSerialized .. giftedUnitId .. "_" .. giftingPlayerId .. ";";
		end

		-- Build a string from each value and concat
		giftedUnitsSerializedAllPlayers = giftedUnitsSerializedAllPlayers .. playerId .. ":" .. giftedUnitsSerialized .. ",";
	end

	-- Return the value-string
	return giftedUnitsSerializedAllPlayers;
end

-- Unserualize a serialized string to a table from storage
function UnserializeGiftedUnits(giftedUnitsString)
	-- Initiate table
	local giftedUnitsUnserialized = {};

	-- Loop the split values (split by comma)
	for playerUnitsCombo in string.gmatch(giftedUnitsString, "([^,]+)") do
		-- If a value was splitted
		if playerUnitsCombo ~= nil then
			-- Count loops -> 1 = playerId, 2 = giftCount
			local index = 1;

			-- Temporary data container
			local giftedData = {};

			-- Split the combo by colon
			for value in string.gmatch(playerUnitsCombo, "([^:]+)") do
				-- Add the data sorted to the container
				if index == 1 then giftedData.playerId = value; else giftedData.giftedUnits = value; end

				-- Increment the index (data pointer)
				index = (index + 1);
			end

			-- Players gifted units container
			local playerUnitsUnserialized = {}

			-- Do we have gifted units
			if giftedData.giftedUnits ~= nil then
				-- Parse the gifted units string
				for unitsCombo in string.gmatch(giftedData.giftedUnits, "([^;]+)") do
					-- If a value was splitted
					if unitsCombo ~= nil then
						-- Count loops -> 1 = playerId, 2 = giftCount
						local index = 1;

						-- Temporary data container
						local giftedData = {};

						-- Split the combo by colon
						for value in string.gmatch(unitsCombo, "([^_]+)") do
							-- Add the data sorted to the container
							if index == 1 then giftedData.unitId = value; else giftedData.giftedPlayerId = value; end

							-- Increment the index (data pointer)
							index = (index + 1);
						end

						-- Add it to the unserialized table
						table.insert(playerUnitsUnserialized, tonumber(giftedData.unitId), tonumber(giftedData.giftedPlayerId));
					end
				end
			end

			-- Add it to the unserialized table
			table.insert(giftedUnitsUnserialized, tonumber(giftedData.playerId), playerUnitsUnserialized);
		end
	end

	-- Return table
	return giftedUnitsUnserialized;
end

-- Initial values on mod loaded state
function InitGiftedUnitsTracker()
	-- Fetch all alive players
	local players = Game.GetPlayers{Alive = true};

	-- Loop all players
	for _, player in ipairs(players) do
		-- Fetch player id
		local playerId = player:GetID();

		-- Only real players count
		if playerId ~= nil then
			-- Empty initial gift-list
			giftedUnitsTracker[playerId] = {};

			-- Empty initial freed-resources
			freedResourceYields[playerId] = freedResourceYieldTypes;
		end
	end
end

-- Callback event in case the gifted-lists have been loaded on the UI
function OnLoadedGiftedUnitsGameEvent(localPlayerId, params)
	-- If there is something loaded...
	if params.giftedUnitsString ~= nil then
		-- ...Unserialize it to a table of gifts
		giftedUnitsTrackerLoaded = UnserializeGiftedUnits(params.giftedUnitsString);

		-- Logging
		WriteToLog("OnLoadedGiftedUnitsGameEvent")

		-- If the unserialization produced something, continue
		if giftedUnitsTrackerLoaded ~= nil then
			-- Loop the loaded tables players
			for playerId, giftedUnits in ipairs(giftedUnitsTrackerLoaded) do
				-- Loop the players loaded gifted units list
				for unitId, giftingPlayerId in pairs(giftedUnits) do
					-- Logging
					WriteToLog("Loaded giftedUnitsTracker-Entry: "..playerId.."/"..unitId.."/"..giftingPlayerId);

					-- Assign the loaded value to the global
					giftedUnitsTracker[playerId][unitId] = giftingPlayerId;
				end
			end

			-- Debug out to doublecheck if loading was successful
			if debugMode then
				for playerId, giftedUnits in ipairs(giftedUnitsTracker) do
					for unitId, giftingPlayerId in pairs(giftedUnits) do
						WriteToLog("Verifying Loading giftedUnitsTracker-Entry: "..playerId.."/"..unitId.."/"..giftingPlayerId);
					end
				end
			end
		end
	end
end

-- Persist the gifted units
function PersistGiftedUnits()
	-- Serialize the gifted units tracker
	local giftedUnitsTrackerString = SerializeGiftedUnits();

	-- Logging
	WriteToLog("Persist giftedUnitsTracker: "..giftedUnitsTrackerString);

	-- Persist the string
	GameEvents.PersistGiftedUnits.Call(giftedUnitsTrackerString);
end

-- After a gifting happened, track that gifted unit
function TrackGiftedUnit(playerId, unitId, giftingPlayerId)
	-- Add the gifted unit to the tracker
	giftedUnitsTracker[playerId][unitId] = giftingPlayerId;

	-- Persist the tracker
	PersistGiftedUnits();
end

-- Handling for global turn-begin
function OnTurnBegin()
	-- Log message
	WriteToLog("OnTurnBegin");

	-- Reset freed resource counters
	-- Fetch all alive players
	local players = Game.GetPlayers{Alive = true};

	-- Loop all players
	for _, player in ipairs(players) do
		-- Fetch player id
		local playerId = player:GetID();

		-- Only real players count
		if playerId ~= nil then
			-- Empty freed-resources
			freedResourceYields[playerId] = freedResourceYieldTypes;
		end
	end
end

-- Handling for global turn-end
-- We check in here the AI economy vs. gifted units
function OnTurnEnd()
	-- Log message
	WriteToLog("OnTurnEnd");

	-- Loop the players
	for playerId, giftedUnits in ipairs(giftedUnitsTracker) do
		-- Init a counter for the Count!
		local giftedUnitsCount = 0;

		-- Loop the units of the player
		for unitId, giftingPlayerId in pairs(giftedUnits) do
			-- COUNT KRR KRR HAHA!
			giftedUnitsCount = (giftedUnitsCount + 1);
		end

		-- Logging
		WriteToLog("Player / Gifted Unit-Count: "..playerId.."/"..giftedUnitsCount);

		-- In case we have a major AI with units gifted, continue
		if (Players[playerId]~= nil and not Players[playerId]:IsHuman() and
		    Players[playerId]:IsMajor() and giftedUnitsCount > 0) then
			-- Fetch the player
			local player = Players[playerId];

			-- Determine the gold-maintenance quota, if the quota surpasses a threshold, trigger unit destructions
			HandleMaintenanceActions(playerId, giftedUnits, 'GOLD', MAINTENANCE_GOLD_QUOTA_MAX, GetGoldMaintenanceQuota);

			-- Check for XP2 strat resource yields in regard to economy of units
			if ExposedMembers.XP2Enabled then
				-- Determine the maintenance quotas of strategic resources, if the quota surpasses a threshold, trigger unit destructions
				HandleMaintenanceActions(playerId, giftedUnits, "RESOURCE_COAL", MAINTENANCE_XP2_COAL_QUOTA_MAX, GetResourceMaintenanceQuota);
				HandleMaintenanceActions(playerId, giftedUnits, "RESOURCE_OIL", MAINTENANCE_XP2_OIL_QUOTA_MAX, GetResourceMaintenanceQuota);
				HandleMaintenanceActions(playerId, giftedUnits, "RESOURCE_ALUMINUM", MAINTENANCE_XP2_ALUMINUM_QUOTA_MAX, GetResourceMaintenanceQuota);
				HandleMaintenanceActions(playerId, giftedUnits, "RESOURCE_URANIUM", MAINTENANCE_XP2_URANIUM_QUOTA_MAX, GetResourceMaintenanceQuota);
			end
		end
	end
end

-- Handle needed actions if quota is reached
function HandleMaintenanceActions(playerId, giftedUnits, quotaType, maintenanceMaxQuota, quotaCallback)
	-- Determine the quota value
	local maintenanceQuota = quotaCallback(playerId, quotaType);

	-- If the quota surpasses a threshold, trigger unit destructions
	if maintenanceQuota > maintenanceMaxQuota then
		-- Fetch the player
		local player = Players[playerId];

		-- Destroy units until the quota if fine or no more gifted units exist
		for giftedUnitId, giftedPlayerId in pairs(giftedUnits) do
			-- Fetch the unit data
			local giftedUnit = player:GetUnits():FindID(giftedUnitId);

			-- Check if the unit still exist (could have been destroyed on a previous check)
			if giftedUnit ~= nil then
				-- Fetch the unit type
				local giftedUnitType = GameInfo.Units[giftedUnit:GetType()].UnitType;
				local giftedUnitGoldMaintenance = GameInfo.Units[giftedUnit:GetType()].Maintenance;

				-- If gold is the issue, every unit may get destroyed
				if quotaType == "GOLD" then
					if giftedUnitGoldMaintenance > 0 then
						-- Logging
						WriteToLog("Destroyed Gifted Unit: "..playerId.."/"..giftedUnitId);

						-- And gone...
						UnitManager.Kill(giftedUnit);

						-- Memorize that a resource has been freed
						XP2FreeResourceConsumption(playerId, giftedUnitType);
					end
				else
					-- If a specific resource is the issue,
					-- only the units needing these resources may get destroyed
					if ExposedMembers.XP2Enabled then
						if GameInfo.Units_XP2 ~= nil then
							for row in GameInfo.Units_XP2() do
								if (row.UnitType == giftedUnitType and quotaType == row.ResourceMaintenanceType) then
									if row.ResourceMaintenanceAmount > 0 then
										-- Logging
										WriteToLog("Destroyed Gifted Unit: "..playerId.."/"..giftedUnitId);

										-- And gone...
										UnitManager.Kill(giftedUnit);

										-- Memorize that a resource has been freed
										XP2FreeResourceConsumption(playerId, giftedUnitType);
									end
								end
							end
						end
					end
				end
			end

			-- Recheck the quota after a gifted units destruction
			maintenanceQuota = quotaCallback(playerId, quotaType);

			-- In case we do match the quota now, stop destroying
			if maintenanceQuota <= maintenanceMaxQuota then
				break;
			end
		end
	end
end

-- Helper for quota calculation
function GetGoldMaintenanceQuota(playerId)
	-- Fetch player
	local player = Players[playerId];

	-- Fetch the players gold-yield
	local goldYield = player:GetTreasury():GetGoldYield();

	-- Logging
	WriteToLog("Player / Gold-Yield: "..playerId.."/"..goldYield);

	-- No calculation needed, technically 100% gold consumption
	if goldYield <= 0 then return 100; end

	-- Calculate the maintenance-to-yield quota
	local totalMaintenance = player:GetTreasury():GetTotalMaintenance();
	local upkeepGoldQuota = ((totalMaintenance * 100) / goldYield);

	-- Logging
	WriteToLog("Player / Gold-Total-Maintenance: "..playerId.."/"..totalMaintenance);
	WriteToLog("Player / Gold-Upkeep-Quota: "..playerId.."/"..upkeepGoldQuota);

	-- This is what we got
	return upkeepGoldQuota;
end

-- Helper for quota calculation
function GetResourceMaintenanceQuota(playerId, resourceType)
	-- Fetch player
	local player = Players[playerId];

	-- Fetch players resources
	local playerResources	= player:GetResources();

	-- Base values, in case the player does not own them
	local totalConsumptionPerTurn = 0;
	local totalYieldPerTurn = 0;

	-- Loop all games resources
	for resource in GameInfo.Resources() do
		-- Match oil
		if (resource.ResourceType == resourceType) then
			-- Fetch yields/costs
			GameEvents.FetchResourceYields.Call(playerId, resource.ResourceType);

			-- Read the values set by the UI
			local accumulationPerTurn = ExposedMembers.ResourceYields.accumulationPerTurn;
			local importPerTurn = ExposedMembers.ResourceYields.importPerTurn;
			local bonusPerTurn = ExposedMembers.ResourceYields.bonusPerTurn;
			local unitConsumptionPerTurn = ExposedMembers.ResourceYields.unitConsumptionPerTurn;
			local powerConsumptionPerTurn = ExposedMembers.ResourceYields.powerConsumptionPerTurn;

			-- Calculate totals
			totalYieldPerTurn = (accumulationPerTurn + importPerTurn + bonusPerTurn);
			totalConsumptionPerTurn = (unitConsumptionPerTurn + powerConsumptionPerTurn);

			-- Counter-count the already freed resources
			if freedResourceYields[playerId][resourceType] > 0 then
				totalConsumptionPerTurn = (totalConsumptionPerTurn - freedResourceYields[playerId][resourceType]);
			end

			-- Stop further looking
			break;
		end
	end

	-- Logging
	WriteToLog("Player / "..resourceType.."-Yield: "..playerId.."/"..totalYieldPerTurn);

	-- No calculation needed, technically 100% resource consumption
	if totalYieldPerTurn <= 0 then return 100; end

	-- Calculate the maintenance-to-yield quota
	local totalMaintenance = totalConsumptionPerTurn;
	local upkeepResourceQuota = ((totalMaintenance * 100) / totalYieldPerTurn);

	-- Logging
	WriteToLog("Player / "..resourceType.."-Total-Maintenance: "..playerId.."/"..totalMaintenance);
	WriteToLog("Player / "..resourceType.."-Upkeep-Quota: "..playerId.."/"..upkeepResourceQuota);

	-- This is what we got
	return upkeepResourceQuota;
end

-- Unit entered the stage of the world!
function OnUnitAddedToMap(playerId, unitId)
	-- Not used yet, buuut, nice to have it on board!
end

-- Unit left the stage of the world!
function OnUnitRemovedFromMap(playerId, unitId)
	-- In case the unit was a gift, remove it from the tracker
	if giftedUnitsTracker[playerId][unitId] ~= nil then
		-- Fire in the hole!
		giftedUnitsTracker[playerId][unitId] = nil;

		-- Persist the tracker
		PersistGiftedUnits();
	end
end

-- Set a resource-freed-state
function XP2FreeResourceConsumption(playerId, unitType)
	-- Check if we have XP2 enabled
	if ExposedMembers.XP2Enabled then
		if GameInfo.Units_XP2 ~= nil then
			-- Loop XP2 unit data
			for row in GameInfo.Units_XP2() do
				-- Our destroyed unit has been found
				if row.UnitType == unitType then
					-- If it does cost maintenance in resources
					if row.ResourceMaintenanceAmount > 0 then
						-- Memorize freed yields by destroying this unit
						freedResourceYields[playerId][row.ResourceMaintenanceType] = (freedResourceYields[playerId][row.ResourceMaintenanceType] + row.ResourceMaintenanceAmount);
					end
				end
			end
		end
	end
end

-- Hook into corp-formation
function OnUnitFormCorps(playerId, unitId)
	-- Logging
	WriteToLog("OnUnitFormCorps");
	WriteToLog(playerId);
	WriteToLog(unitId);

	-- Fetch player data
	local player = Players[playerId];
	local unit = player:GetUnits():FindID(unitId);

  -- Check if the unit has a type, if not there is nothing to free up
	-- I wonder what type of unit can have no "type" oO
	if unit:GetType() ~= nil then
		local unitType = GameInfo.Units[unit:GetType()].UnitType;

		-- Memorize freed resource
		XP2FreeResourceConsumption(playerId, unitType);
	else
		-- Lets find out if untyped units have names
		print("--ERROR - Found a unit without a type: "..unit:GetName());
	end
end

-- Hook into corp formations
function OnUnitFormArmy(playerId, unitId)
	-- Trigger army-formation-event
	OnUnitFormCorps(playerId, unitId);
end

-- Main function for initialization
function Initialize()
	-- Initialize the gifted-units-tracker
	InitGiftedUnitsTracker();

	-- Global turn ends
	Events.TurnEnd.Add(OnTurnEnd);

	-- Global turn begins
	Events.TurnBegin.Add(OnTurnBegin);

	-- Trigger multiplayer synced game-event for unit military formation changes
	Events.UnitFormCorps.Add(OnUnitFormCorps);
	Events.UnitFormArmy.Add(OnUnitFormArmy);

	-- Global notification of units added/left the game
	Events.UnitAddedToMap.Add(OnUnitAddedToMap);
	Events.UnitRemovedFromMap.Add(OnUnitRemovedFromMap);

	-- Trigger multiplayer synced game-event for loading gifted unit (see GiftUnit.lua::GiftUnit)
	GameEvents.LoadedGiftedUnits.Add(OnLoadedGiftedUnitsGameEvent);

	-- Trigger multiplayer synced game-event for gifting unit (see GiftUnit.lua::GiftUnit)
	GameEvents.GiftUnit.Add(OnGiftUnitGameEvent);

	-- Trigger multiplayer synced game-event for populating the unit promotions/formation (see GiftUnit.lua::GiftUnit)
	GameEvents.PopulateUnit.Add(OnPopulateUnitGameEvent);

	-- Trigger multiplayer synced game-event for payment for the unit (see GiftUnit.lua::GiftUnit)
	GameEvents.PayForGifting.Add(OnPayForGiftingGameEvent);

	-- Trigger multiplayer synced game-event for simulate gold change (see GiftUnit.lua::GiftUnit)
	GameEvents.GoldChange.Add(OnGoldChangeGameEvent);

	-- Trigger multiplayer synced game-event for notifications for the gift (see GiftUnit.lua::GiftUnit)
	GameEvents.SendWarning.Add(OnSendWarningGameEvent);
	GameEvents.SendInfo.Add(OnSendInfoGameEvent);

	-- Communicate with UI context via exposed-members
	ExposedMembers.GameEvents = GameEvents;

	-- Init message log
	print("Initialized.");
end

-- Initialize the script
Initialize();
