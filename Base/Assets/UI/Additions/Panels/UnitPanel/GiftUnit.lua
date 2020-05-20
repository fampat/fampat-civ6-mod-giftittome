-- ==================================================
--	GiftUnit
--	UI implementation of our gift-button and handling
-- ==================================================

-- Add a log event for loading this
print("Loading GiftUnit.lua");

-- Includes
include("InstanceManager");
include("PopupDialog");

-- Debugging mode switch
local debugMode = true;

-- Enabled mods check
local isExpansion2Active = Modding.IsModActive("4873eb62-8ccc-4574-b784-dda455e74e68");

-- UI controls
local giftActionIM = InstanceManager:new("UnitActionInstance", "UnitActionButton", Controls.GiftSecondaryActionsStack);

-- Variables for gifting handling
local giftsThisTurn = {};
local receivedGiftsThisTurn = {};
local maxGiftsPerTurn = 5;
local warningFromWarEnemiesOfReceipientAtReceivedGiftsPerTurn = 2;
local denounceFromWarEnemiesOfReceipientAtReceivedGiftsPerTurn = 4;
local unitIsGiftable = false;
local recipientPlayer = nil;
local giftingPlayer = nil;
local giftingUnit = nil;
local giftingUnitX = nil;
local giftingUnitY = nil;
local giftingInProgress = false;
local teleportLastUnitId = nil;
local teleportTriggerUnitFlagUpdate = false;

-- Callback after the game has loaded
function OnLoadGameViewStateDone()
	-- Load from persistend storage the gift-count for the players
	LoadGiftsThisTurn();

	-- Load from persistend storage the gift-received-count for the players
	LoadReceivedGiftsThisTurn();

	-- Load from persistend storage the gifted-units-per-player
	LoadGiftedUnits();

	-- Make the xp2-status available to our script
	ExposedMembers.XP2Enabled = isExpansion2Active;
end

-- Event callback for setting the current gifting-counts
function OnSetGiftsThisTurn (giftsCounter)
	-- Yeah, set it!
	giftsThisTurn = giftsCounter;
end

-- Event callback for setting the current received gifting-counts
function OnSetReceivedGiftsThisTurn (receivedGiftsCounter)
	-- Yeah, set it!
	receivedGiftsThisTurn = receivedGiftsCounter;
end

-- Turn ends, reset received giftcount
function OnTurnEnd()
	-- As said, reset the count
	ResetGiftsThisTurn();
	ResetReceivedGiftsThisTurn();
end

-- Update the gift-option after units move
function OnUnitMoveComplete(playerId, unitId, locationX, locationY)
	-- Use existing function
	OnUnitSelectionChanged(playerId, unitId, locationX, locationY);
end

-- Update the gift-option after unit change
function OnUnitSelectionChanged(playerId, unitId, locationX, locationY, locationZ, isSelected, isEditable)
	if playerId == Game.GetLocalPlayer() then
		-- Check/Set circumstances
		SetUnitGiftableStatus(playerId, unitId, locationX, locationY);

		-- Create the button
		CreateGiftButton();

		-- Attach it to the existing UI
		AttachGiftButtonToUnitPanelActions();
	end
end

-- Descision to not gift the unit
function OnNoGift()
	-- Reset gifting and teleport-status
	giftingInProgress = false;
	teleportLastUnitId = nil;
	teleportTriggerUnitFlagUpdate = false;
end

-- Gift promp (Do you really... bla bla)
function OnPromptToGiftUnit()
	-- Active/selected unit
	local pUnit	= UI.GetHeadSelectedUnit();

	-- Only one prompt per unit please
    if giftingInProgress then
        return;
    end

	-- Is it really giftable
    if (unitIsGiftable and pUnit ~= nill) then
		-- Unit name
		local unitName = GameInfo.Units[pUnit:GetUnitType()].Name;

		-- Gift message
		local promptMessage = (not MustPayForGifting() and Locale.Lookup("LOC_HUD_UNIT_PANEL_ARE_YOU_SURE_GIFT", unitName, (giftsThisTurn[Game.GetLocalPlayer()] + 1), maxGiftsPerTurn)) or
														   Locale.Lookup("LOC_HUD_UNIT_PANEL_ARE_YOU_SURE_GIFT_PAY", unitName, GetUnitGiftCost(), (giftsThisTurn[Game.GetLocalPlayer()] + 1), maxGiftsPerTurn);

		-- Create the popup-dialogue with callback functions
		local popup = PopupDialogInGame:new( "UnitPanelPopup" );
		popup:ShowYesNoDialog(promptMessage, function() GiftUnit() end, OnNoGift);	-- On success trigger the actual gifting-process

		-- Handle variable
		giftingInProgress = true;
	end
end

-- Create the gift-button
function CreateGiftButton ()
	-- Some sort of lua-singleton version i guess...
	giftActionIM:DestroyInstances();

	-- Get an button instance from the instance-manager
	local instance = giftActionIM:GetInstance();

	-- Set button data and action handler
	instance.UnitActionIcon:SetIcon("ICON_UNITCOMMAND_GIFT");
	instance.UnitActionButton:SetDisabled((not unitIsGiftable));
	instance.UnitActionButton:SetAlpha((not unitIsGiftable and 0.4) or 1);
	instance.UnitActionButton:SetToolTipString((not unitIsGiftable and Locale.Lookup("LOC_GIFTITTOME_GIFT_THIS_UNIT_DISABLED", maxGiftsPerTurn)) or Locale.Lookup("LOC_GIFTITTOME_GIFT_THIS_UNIT"));
	instance.UnitActionButton:RegisterCallback(Mouse.eLClick,
		function(void1, void2)
			UI.PlaySound("Unit_CondemnHeretic_2D");
			if unitIsGiftable then
				-- Open the "do you really... bla bla"-prompt
				OnPromptToGiftUnit();
			end
		end
	);
end

-- Execute gifting process
function GiftUnit ()
	-- Reset gift handle variable
	giftingInProgress = true;

	-- In case we gift a settler, remove settler lens upon gifting away the settler
	if GameInfo.Units[giftingUnit:GetType()].UnitType == "UNIT_SETTLER" then
		-- Woosh!
		UILens.ClearLayerHexes(UILens.CreateLensLayerHash("Hex_Coloring_Water_Availablity"));
	end

	-- Pay for gifting! Now! (at least if you name is Matthias...)
	PayForGifting();

	-- Initialize parameters for script-callback
	parameters = {}

	-- Define start-event-callback (game-event-name in script context: GiftItToMeNow.lua::Initialize)
	parameters.OnStart = "GiftUnit"

	-- Add parameters for the gift-event-callback
	parameters.giftingPlayerID = giftingPlayer:GetID()
	parameters.recipientPlayerID = recipientPlayer:GetID()
	parameters.giftingUnitID = giftingUnit:GetID()

	-- Game-event callback to destroy the gifted unit and create a new one
	UI.RequestPlayerOperation(Game.GetLocalPlayer(), PlayerOperations.EXECUTE_SCRIPT, parameters);
end

-- Change a players gold balance
function OnChangeGoldBalance(gPlayerId, gGoldBalanceChange)
	-- Initialize parameters for script-callback
	local parameters = {};

	-- Define start-event-callback (game-event-name in script context: GiftItToMeNow.lua::Initialize)
	parameters.OnStart = "GoldChange";

	-- Add parameters for the gift-event-callback
	parameters.playerId = gPlayerId;
	parameters.amount = gGoldBalanceChange;

	-- Game-event callback to destroy the gifted unit and create a new one
	UI.RequestPlayerOperation(Game.GetLocalPlayer(), PlayerOperations.EXECUTE_SCRIPT, parameters);
end

-- Gives an option-boost for the gifting player if the recipient is a AI
function OpinionBoostForGiftingPlayer(giftingPlayer, recipientPlayer)
	-- Make sure players are real and the recipient is a AI
	if (giftingPlayer ~= nil and recipientPlayer ~= nil and recipientPlayer:IsMajor() and not recipientPlayer:IsHuman()) then
		-- Skip the diplo-screen for this trade (its a simulation to get the diplo-nice-guy)
		LuaEvents.SkipDiplomaticStatement(true);

		-- Add a gold amount to the gifting player, he will trade it to the recipient
		OnChangeGoldBalance(giftingPlayer:GetID(), 100)

		-- Initiate a deal
		local pDeal = DealManager.GetWorkingDeal(DealDirection.OUTGOING, giftingPlayer:GetID(), recipientPlayer:GetID());

		-- Deal is about a hundred gold (no duration)
		pDealItem = pDeal:AddItemOfType(DealItemTypes.GOLD, giftingPlayer:GetID());
		pDealItem:SetAmount(100);
		pDealItem:SetDuration(0);

		-- Make it so!
		DealManager.SendWorkingDeal(DealProposalAction.ACCEPTED, giftingPlayer:GetID(), recipientPlayer:GetID());

		-- Fetch an close the session to trigger additional events
		local sessionID = DiplomacyManager.FindOpenSessionID(giftingPlayer:GetID(), recipientPlayer:GetID());
		DiplomacyManager.AddResponse(sessionID, giftingPlayer:GetID(), "POSITIVE");
		DiplomacyManager.CloseSession(sessionID);

		-- Remove a gold amount from the recipient player, all this was just for the opinion-boost
		OnChangeGoldBalance(recipientPlayer:GetID(), -100)
	end
end

-- Determine how to react to gifting, civs at war with the recipient might get angry against the gifting-civ
function OnHandleGiftReactions(giftingPlayerId, recipientPlayerId, giftedUnitName, giftedUnitX, giftedUnitY)
	-- Logging
	WriteToLog("HandleGiftReactions");

	-- Fetching player data
	local players = Game.GetPlayers{Alive = true};
	local giftingPlayer = Players[giftingPlayerId];
	local recipientPlayer = Players[recipientPlayerId];
	local recipientRecievedGifts = receivedGiftsThisTurn[recipientPlayer:GetID()];

	-- In case the recipient is a AI, deal gold to it to obtain a opinion-boost for gifting a unit
	OpinionBoostForGiftingPlayer(giftingPlayer, recipientPlayer);

	-- Loop all players
	for _, player in ipairs(players) do
		-- Pick players that are not involved in the gifting
		if (player:GetID() ~= giftingPlayer:GetID() and player:GetID() ~= recipientPlayer:GetID()) then
			-- Check if the player not involved might get angry because the recipient player is an enemy (only Major-AI get angry)
			if (recipientPlayer:GetDiplomacy():IsAtWarWith(player:GetID()) and player:IsMajor() and not player:IsHuman()) then
				-- Only get anry if they know each other
				if giftingPlayer:GetDiplomacy():HasMet(player:GetID()) then
					-- First, send a warning notification, then, denounce if player keeps gifting!
					if recipientRecievedGifts >= warningFromWarEnemiesOfReceipientAtReceivedGiftsPerTurn and
					   recipientRecievedGifts < denounceFromWarEnemiesOfReceipientAtReceivedGiftsPerTurn then
						-- Logging
						WriteToLog("Send Warning: "..player:GetID().." -> "..giftingPlayer:GetID());

						-- Initialize a call to the script and collect needed paramters
						parameters = {};
						parameters.OnStart = "SendWarning";
						parameters.sPlayerId = player:GetID();
						parameters.rPlayerId = giftingPlayer:GetID();
						parameters.gUnitName = giftedUnitName;
						parameters.gUnitX = giftedUnitX;
						parameters.gUnitY = giftedUnitY;

						-- Call the script for sending a warning notification
						UI.RequestPlayerOperation(Game.GetLocalPlayer(), PlayerOperations.EXECUTE_SCRIPT, parameters);
					elseif recipientRecievedGifts >= denounceFromWarEnemiesOfReceipientAtReceivedGiftsPerTurn then
						-- Ok, i warned you, now take the diplomatic action!
						WriteToLog("Denounce: "..player:GetID().." -> "..giftingPlayer:GetID());	-- Logging

						-- Denounce the gifting player
						DiplomacyManager.RequestSession(giftingPlayer:GetID(), player:GetID(), "DENOUNCE");

						-- Prevent denounce spam by resetting the received-gift-counter for that player
						ResetReceivedGiftsThisTurnForOne(recipientPlayer:GetID());
					end
				end
			end
		end
	end

	-- In case the gifting player and recipient are both human,
	-- send a notification to the recipient about the shiny new unit
	if (giftingPlayer:IsHuman() and recipientPlayer:IsHuman()) then
		-- Logging
		WriteToLog("Send Info: "..giftingPlayer:GetID().." -> "..recipientPlayer:GetID());

		-- Initialize a call to the script and collect needed paramters
		parameters = {};
		parameters.OnStart = "SendInfo";
		parameters.sPlayerId = giftingPlayer:GetID();
		parameters.rPlayerId = recipientPlayer:GetID();
		parameters.gUnitName = giftedUnitName;
		parameters.gUnitX = giftedUnitX;
		parameters.gUnitY = giftedUnitY;

		-- Call the script for sending a info notification
		UI.RequestPlayerOperation(Game.GetLocalPlayer(), PlayerOperations.EXECUTE_SCRIPT, parameters);
	end
end

-- Update units flag within the flag-manager
function OnUpdateReligionFlag(playerID, unitID, unitX, unitY)
	-- Call the ui update event on UnitFlagManager.lua::OnUpdateUnitFlagReligious
	LuaEvents.UpdateUnitFlagReligious(playerID, unitID, unitX, unitY);
end

-- Jobbed from UnitFlagManager.lua by Firaxis
-- Get remaining levy turns for a unit
function GetLevyTurnsRemaining(pUnit)
	-- Unit is real?
	if (pUnit ~= nil) then
		-- Unit is an combatant?
		if (pUnit:GetCombat() > 0) then
			-- Fetch some owner stuffz
			local iOwner = pUnit:GetOwner();
			local iOriginalOwner = pUnit:GetOriginalOwner();

			-- If the original owner isnt to current one, its levied
			if (iOwner ~= iOriginalOwner) then
				-- Fetch the original owner (city-state)
				local pOriginalOwner = Players[iOriginalOwner];

				-- Real is real if it gets influence, nothen else!
				if (pOriginalOwner ~= nil and pOriginalOwner:GetInfluence() ~= nil) then
					-- Are we there yeti?
					local iLevyTurnCounter = pOriginalOwner:GetInfluence():GetLevyTurnCounter();

					-- Yeti?
					if (iLevyTurnCounter >= 0 and iOwner == pOriginalOwner:GetInfluence():GetSuzerain()) then
						-- Yes!
						return (pOriginalOwner:GetInfluence():GetLevyTurnLimit() - iLevyTurnCounter);
					end
				end
			end
		end
	end

	-- No!
	return -1;
end

-- Helper to fetch the owner player of an location
function GetTerritoryOwnerByCoordinates (locationX, locationY)
	-- Fetching some plot data
	local plot = Map.GetPlot(locationX, locationY);
	local plotOwnerId = plot:GetOwner();
	local plotOwner = nil;

	-- Plot owner is real?
	if (plotOwnerId ~= nil and plotOwnerId > -1) then
		-- He is!
		plotOwner = Players[plotOwnerId];
	end

	-- Its the OWNER!
	return plotOwner;
end

-- Check if the gifting player also needs to add gold to his gift
function MustPayForGifting ()
	-- Gifting player is real?
	if giftingPlayer ~= nil then
		-- Get his config
		local playerConfig = PlayerConfigurations[giftingPlayer:GetID()];

		-- Check if the gifting player is corvinus and if he wants to gift to a suzerain state
		if (giftingUnit ~= nil and playerConfig:GetLeaderTypeName() == "LEADER_MATTHIAS_CORVINUS" and IsRecipientPlayerMinor()) then
			-- To gift to a suzerain state, pay! (if its a combat unit)
			if (IsGiftingPlayerSuzerainToRecipientPlayer() and giftingUnit:GetCombat() > 0) then
				-- PAY PAY PAY!
				return true;
			end
		end
	end

	-- ITS FREE!
	return false;
end

-- Check if the player is able to pay for the gift
function CanPayForGifting ()
	-- Determine how much is needed to pay
	local giftingUnitCost = GetUnitGiftCost();

	-- Only real player with real money and real unit costs need to pay
	if (giftingPlayer ~= nil and giftingUnitCost > 0) then
		-- Does he have enough gold?
		return giftingPlayer:GetTreasury():GetGoldBalance() >= giftingUnitCost;
	end

	-- Uhm.. yeah...
	return false;
end

-- Pay now dude! money!
function PayForGifting ()
	-- He dont need to pay *wave-hand*
	if not MustPayForGifting() then
		return true;
	end

	--	Determine cost
	local giftingUnitCost = GetUnitGiftCost();

	-- Cost, player and balance check?
	if (giftingPlayer ~= nil and giftingUnitCost > 0 and CanPayForGifting()) then
		-- Empty params for now
		local parameters = {};

		-- This will trigger a unit teleportation on the gameplay-script
		parameters.OnStart = "PayForGifting";

		-- Other parameters
		parameters.giftingPlayerId = giftingPlayer:GetID();
		parameters.giftingUnitCost = giftingUnitCost;

		-- Call the gameplay script to pay the costs, KACHING!
		UI.RequestPlayerOperation(Game.GetLocalPlayer(), PlayerOperations.EXECUTE_SCRIPT, parameters);

		-- KACHING Done!
		return true;
	end

	return false;
end

-- Fetch unit costs
function GetUnitGiftCost ()
	-- For real units
	if giftingUnit ~= nil then
		-- Round it please, cant pay 0.123456 gold-piece ...
		return RoundNumber((giftingUnit:GetUpgradeCost() / 2), 0);
	end

	-- Pseudo-cost if everything fails
	return 99999999999999;
end

-- Check if the recipient is a city-state that is suzerain to the gifting player
function IsGiftingPlayerSuzerainToRecipientPlayer ()
	-- Is it a minor civ?
	if IsRecipientPlayerMinor() then
		-- Loop the minors
		for _, minorPlayer in ipairs(PlayerManager.GetAliveMinors()) do
			-- Minor found!
			if (recipientPlayer ~= nil and minorPlayer:GetID() == recipientPlayer:GetID()) then
				-- Fetch the influencers! (no.. not instagram or youtube!)
				local minorPlayerInfluence = minorPlayer:GetInfluence();

				-- Influencer found?
				if minorPlayerInfluence ~= nil then
					-- Get is suzerain player
					local suzerainPlayerID = minorPlayerInfluence:GetSuzerain();

					-- Is it the gifting player?
					if (giftingPlayer ~= nil and giftingPlayer:GetID() == suzerainPlayerID) then
						-- Won!
						return true;
					end
				end
			end
		end
	end

	-- Lose
	return false;
end

-- Basic check if the recipient player is a city-state
function IsRecipientPlayerMinor ()
	-- Loop city-states
	for _, minorPlayer in ipairs(PlayerManager.GetAliveMinors()) do
		-- If found...
		if (recipientPlayer ~= nil and minorPlayer:GetID() == recipientPlayer:GetID()) then
			-- Tell everyone (who wants to know it)
			return true;
		end
	end

	-- If if not is found, tell'em
	return false;
end


--
-- Unneeded whitespace below and above, with a comment inbetween... duh...
--


-- Helper to determine if the unit is giftable, sets all needed data for follow-up functions
function SetUnitGiftableStatus (playerId, unitId, locationX, locationY)
	if (playerId ~= nil and unitId ~= nil) then
		-- Make sure gift-options are available
		if (giftsThisTurn[playerId] < maxGiftsPerTurn) then
			giftingPlayer = Players[playerId];	-- Player who has too much units i assume ;)
			recipientPlayer = GetTerritoryOwnerByCoordinates(locationX, locationY);	-- Poor dude with too less units

			-- Only valid players can be blessed with a gift
			if (giftingPlayer ~= nil and recipientPlayer ~= nil and recipientPlayer:GetID() > -1 and recipientPlayer:GetID() ~= giftingPlayer:GetID()) then
				-- Ofcause the gifting unit must be real
				giftingUnit = giftingPlayer:GetUnits():FindID(unitId);
				giftingUnitX = giftingUnit:GetX();
				giftingUnitY = giftingUnit:GetY();

				-- Really real unit AND not levied! (dude, your parents dont told you not to gift borrowed stuff to others?!)
				if (giftingUnit ~= nil and GetLevyTurnsRemaining(giftingUnit) == -1) then
					-- Check if gifting this unit requires the leader to pay (for example Matthias Corvinus)
					if (not MustPayForGifting() or (MustPayForGifting() and CanPayForGifting())) then
						-- Fetch unit data, not every unit type is giftable, almost all
						local giftingUnitFormationClass = GameInfo.Units[giftingUnit:GetType()].FormationClass;
						local giftingUnitType = GameInfo.Units[giftingUnit:GetType()].UnitType;
						local giftingUnitPurchaseYield = GameInfo.Units[giftingUnit:GetType()].PurchaseYield;
						local giftingUnitReligionType = giftingUnit:GetReligionType();
						local giftingUnitDamage = giftingUnit:GetDamage();
						local giftingUnitMaxDamage = giftingUnit:GetMaxDamage();

						-- Calculate the current damage percentage
						local giftingUnitDamagedPercent = RoundNumber(((giftingUnitMaxDamage / 100) * giftingUnitDamage), 0);

						-- All combat type units, religious units and some civillians
						if ((giftingUnitFormationClass == "FORMATION_CLASS_LAND_COMBAT" and recipientPlayer:IsMajor()) or																			-- Major civs get all kind of combat units
							(giftingUnitFormationClass == "FORMATION_CLASS_LAND_COMBAT" and not recipientPlayer:IsMajor() and giftingUnitReligionType <= 0) or	-- Minor civs get all kinde of combat units except religious ones
							giftingUnitFormationClass == "FORMATION_CLASS_NAVAL" or																																							-- All civs can get all naval units
							giftingUnitFormationClass == "FORMATION_CLASS_AIR" or																																								-- All civs can get all air units
							giftingUnitFormationClass == "FORMATION_CLASS_SUPPORT" or																																						-- All civs can get all support units
							giftingUnitType == "UNIT_BUILDER" or																																																-- All civs can get builders
							(giftingUnitType == "UNIT_SETTLER" and recipientPlayer:IsMajor()) or																																-- Major civs can get settlers
							(giftingUnitType == "UNIT_ARCHAEOLOGIST" and recipientPlayer:IsMajor()) or																													-- Major civs can get Indiana-Jones
							(giftingUnitPurchaseYield == "YIELD_FAITH" and recipientPlayer:IsMajor())) then																											-- Major civs can get religious units
							-- The unit must have high health and the gifting player and recipient must be at peace!
							if (giftingUnitDamagedPercent <= 10 and not giftingPlayer:GetDiplomacy():IsAtWarWith(recipientPlayer:GetID())) then
								unitIsGiftable = true;
							end
							return;
						end
					end
				end
			end
		end
	end

	-- In case the unit is not giftable, reset
	giftingPlayer = nil;
	recipientPlayer = nil;
	giftingUnit = nil;
	giftingUnitX = nil;
	giftingUnitY = nil;
	unitIsGiftable = false;
	giftingInProgress = false;
end

-- Add the gift-button the the secondary action-menu of an unit (the one that hiding behind the "plus")
function AttachGiftButtonToUnitPanelActions ()
	-- Get the existing stack
	local SecondaryActionsStack = ContextPtr:LookUpControl("/InGame/UnitPanel/SecondaryActionsStack");

	-- If it exist, attach our wonderful gift-button
	if SecondaryActionsStack ~= nil then
		-- Get my stack a new parent
		Controls.GiftSecondaryActionsStack:ChangeParent(SecondaryActionsStack);

		-- Make the birth of the child official, iam now a daddy!
		SecondaryActionsStack:AddChildAtIndex(Controls.GiftSecondaryActionsStack, 0);
		SecondaryActionsStack:CalculateSize();
		SecondaryActionsStack:ReprocessAnchoring();
	end
end

-- After the gameplay-script has populated the unit, it will trigger this event
-- This will only get called if the gifted unit is religious (this is a workaroud for a missing "UnitReligionChanged"-Event
function OnUnitTeleported (playerID, unitID, unitX, unitY)
	-- Check if the teleported unit is a result of our gifting-process
	if (recipientPlayer ~= nil and giftingInProgress and playerID == recipientPlayer:GetID() and
		unitX == giftingUnitX and unitY == giftingUnitY) then
		-- Set teleport trigger
		teleportLastUnitId = unitID;
		teleportTriggerUnitFlagUpdate = true;
	elseif (not giftingInProgress and teleportTriggerUnitFlagUpdate and teleportLastUnitId == unitID) then
		-- Trigger the religious unit update
		OnUpdateReligionFlag(playerID, unitID, unitX, unitY);

		-- Reset teleport trigger
		teleportLastUnitId = nil;
		teleportTriggerUnitFlagUpdate = false;
	else
		-- Reset teleport trigger
		teleportLastUnitId = nil;
		teleportTriggerUnitFlagUpdate = false;
	end
end

-- Catch if a new unit has added to game
function OnUnitAddedToMap (playerID, unitID, unitX, unitY)
	-- Check if the new unit is a result of our gifting-process
	if (recipientPlayer ~= nil and giftingInProgress and playerID == recipientPlayer:GetID() and
		unitX == giftingUnitX and unitY == giftingUnitY) then
		-- Empty params for now
		local parameters = {};

		-- This will trigger a unit teleportation on the gameplay-script
		parameters.OnStart = "PopulateUnit";

		-- Call the gameplay script to populate the unit with promotions and religion type (GiftItToMeNow.lua::Initialize)
		UI.RequestPlayerOperation(Game.GetLocalPlayer(), PlayerOperations.EXECUTE_SCRIPT, parameters);
	end
end

-- Memorize a gift has been send
function OnAddGiftThisTurn(giftingPlayerId, recipientPlayerId)
	if (giftingPlayerId ~= nil and recipientPlayerId ~= nil) then
		WriteToLog("OnAddGiftThisTurn - giftsThisTurn: "..giftingPlayerId.." -> "..giftsThisTurn[giftingPlayerId].." + 1")
		WriteToLog("OnAddGiftThisTurn - receivedGiftsThisTurn: "..recipientPlayerId.." -> "..receivedGiftsThisTurn[recipientPlayerId].." + 1")

		-- Add one to the gift-count of the sender and recipient
		giftsThisTurn[giftingPlayerId] = (giftsThisTurn[giftingPlayerId] + 1);
		receivedGiftsThisTurn[recipientPlayerId] = (receivedGiftsThisTurn[recipientPlayerId] + 1);

		-- Also persist the new gift-count value for the gifting player
		PersistGiftsThisTurn(giftsThisTurn);

		-- Also persist the new gift-count value for the recipient
		PersistReceivedGiftsThisTurn(receivedGiftsThisTurn);
	end
end

-- Reset gift-count
function ResetGiftsThisTurn()
	-- Fetch all alive players
	local players = Game.GetPlayers{Alive = true};

	-- Loop em
	for _, player in ipairs(players) do
		giftsThisTurn[player:GetID()] = 0;
	end

	-- Reset each players gifting count
	PersistGiftsThisTurn(giftsThisTurn);
end

-- Persist the gift-count to storage
function PersistGiftsThisTurn(giftsThisTurnPersist)
	-- Logging
	WriteToLog("Persist giftsThisTurn: "..SerializeGiftCounter(giftsThisTurnPersist));

	-- Save in storage (savegame) for this player
	GameConfiguration.SetValue("GTT", SerializeGiftCounter(giftsThisTurnPersist));
end

-- Fetch the gifts-count from persistent storage
function LoadGiftsThisTurn()
	-- Fetch the value from the storage
	local giftsThisTurnLoaded = GameConfiguration.GetValue("GTT");

	-- If a value is present...
	if giftsThisTurnLoaded ~= nil then
		WriteToLog("Loaded giftsThisTurn: "..giftsThisTurnLoaded);

		-- Call the callback which sets the local counter on every player
		OnLoadedGiftsThisTurn(giftsThisTurnLoaded);
	else
		WriteToLog("Loaded giftsThisTurn for player: NIL");
	end
end

-- Callback for gifting-counter has been loaded from persisten storage
function OnLoadedGiftsThisTurn(giftsThisTurnLoaded)
	-- Only real player count
	if (giftsThisTurnLoaded~= nil) then
		-- Assign the loaded value localy
		giftsThisTurn = UnserializeGiftCounter(giftsThisTurnLoaded);

		-- Set the local counter on every player
		LuaEvents.SetGiftsThisTurn(giftsThisTurn);
	end
end

-- Reset received gift-count
function ResetReceivedGiftsThisTurn()
	-- Fetch all alive players
	local players = Game.GetPlayers{Alive = true};

	-- Loop em
	for _, player in ipairs(players) do
		receivedGiftsThisTurn[player:GetID()] = 0;
	end

	-- Reset each players received gift count
	PersistReceivedGiftsThisTurn(receivedGiftsThisTurn);
end

-- Reset received gift count
function ResetReceivedGiftsThisTurnForOne(playerId)
	-- Real players only please
	if playerId ~= nil then
		-- So... um, zeroed
		receivedGiftsThisTurn[playerId] = 0;

		-- Persist to load it after game has been saved
		PersistReceivedGiftsThisTurn(receivedGiftsThisTurn);
	end
end

-- Persist the received gift count to storage
function PersistReceivedGiftsThisTurn(receivedGiftsThisTurnPersist)
	-- Logging
	WriteToLog("Persist receivedGiftsThisTurn for player: "..SerializeGiftCounter(receivedGiftsThisTurnPersist));

	-- Actual storage persistance process
	GameConfiguration.SetValue("RGTT", SerializeGiftCounter(receivedGiftsThisTurnPersist));
end

-- Load the persisted values from storage
function LoadReceivedGiftsThisTurn()
	-- Actial loading
	local receivedGiftsThisTurnLoaded = GameConfiguration.GetValue("RGTT");

	-- Checking if there was something to load
	if receivedGiftsThisTurnLoaded ~= nil then
		-- Logging
		WriteToLog("Loaded receivedGiftsThisTurn:"..receivedGiftsThisTurnLoaded);

		-- Callback to set the loaded value to the current context
		OnLoadedReceivedGiftsThisTurn(receivedGiftsThisTurnLoaded);
	else
		-- Logging
		WriteToLog("Loaded receivedGiftsThisTurn: NIL");
	end
end

-- Load the value to the context of all players
function OnLoadedReceivedGiftsThisTurn(receivedGiftsThisTurnLoaded)
	-- If loaded value are real
	if (receivedGiftsThisTurnLoaded~= nil) then
		-- Set the context value
		receivedGiftsThisTurn = UnserializeGiftCounter(receivedGiftsThisTurnLoaded);

		-- Callback for setting the value on all players
		LuaEvents.SetReceivedGiftsThisTurn(receivedGiftsThisTurn);
	end
end

-- Round numbers helper
function RoundNumber(num, numDecimalPlaces)
  if numDecimalPlaces and numDecimalPlaces>0 then
    local mult = 10^numDecimalPlaces
    return math.ceil(num * mult + 0.5) / mult
  end
  return math.ceil(num + 0.5)
end

-- Set initial player gift-counts
function InitLocalGiftsThisTurn ()
	-- Get alive players
	local players = Game.GetPlayers{Alive = true};

	-- Player is real?
	for _, player in ipairs(players) do
		-- Initialize gifting counters
		local playerId = player:GetID();
		giftsThisTurn[playerId] = 0;
		receivedGiftsThisTurn[playerId] = 0;
	end
end

-- Serialize a table to a string for persistance
function SerializeGiftCounter(giftCounter)
	-- Initialize empty string
	local giftCounterSerialized = "";

	-- Loop the values
	for playerId, giftCount in ipairs(giftCounter) do
		-- Build a string from each value and concat
		giftCounterSerialized = giftCounterSerialized .. playerId .. ":" .. giftCount .. ",";
	end

	-- Return the value-string
	return giftCounterSerialized;
end

-- Unserualize a serialized string to a table from storage
function UnserializeGiftCounter(giftCounterString)
	-- Initiate table
	local giftCounterUnserialized = {};

	-- Loop the split values (split by comma)
	for countCombo in string.gmatch(giftCounterString, "([^,]+)") do
		-- If a value was splitted
		if countCombo ~= nil then
			-- Count loops -> 1 = playerId, 2 = giftCount
			local index = 1;

			-- Temporary data container
			local countData = {};

			-- Split the combo by colon
			for value in string.gmatch(countCombo, "([^:]+)") do
				-- Add the data sorted to the container
				if index == 1 then countData.playerId = value; else countData.giftCount = value; end

				-- Increment the index (data pointer)
				index = (index + 1);
			end

			-- Add it to the unserialized table
			table.insert(giftCounterUnserialized, tonumber(countData.playerId), tonumber(countData.giftCount));
		end
	end

	-- Return table
	return giftCounterUnserialized;
end

-- On diplomatic screen close, reset the skip-variable
function OnDiplomacySessionClosed()
	-- Callback to reset the diplo-screen skip
	LuaEvents.SkipDiplomaticStatement(false);
end

-- Load the gifted units from the storage and call the script
function LoadGiftedUnits()
	-- Loading from persistend storage
	local loadedGiftedUnitsString = GameConfiguration.GetValue("GU");

	-- In case something has been loaded, continue
	if loadedGiftedUnitsString ~= nil then
		-- Logging
		WriteToLog("Loaded giftedUnitsString: "..loadedGiftedUnitsString);

		-- Callback the script with this good news!
		UI.RequestPlayerOperation(Game.GetLocalPlayer(), PlayerOperations.EXECUTE_SCRIPT, {
			OnStart = "LoadedGiftedUnits",
			giftedUnitsString = loadedGiftedUnitsString
		});
	else
		-- Logging
		WriteToLog("Loaded loadedGiftedUnitsString: NIL");
	end
end

-- In case our script wants to persist the units!
function OnPersistGiftedUnits(giftedUnitsString)
	-- Save it to our storage
	GameConfiguration.SetValue("GU", giftedUnitsString);
end

-- Fetch a players resource yields on XP2
function OnFetchResourceYields(playerId, resourceType)
	-- Fetch player
	local player = Players[playerId];

	-- Fetch players resources
	local playerResources	= player:GetResources();

	-- Fetch yields
	local accumulationPerTurn = playerResources:GetResourceAccumulationPerTurn(resourceType);
	local importPerTurn = playerResources:GetResourceImportPerTurn(resourceType);
	local bonusPerTurn = playerResources:GetBonusResourcePerTurn(resourceType);
	local unitConsumptionPerTurn = playerResources:GetUnitResourceDemandPerTurn(resourceType);
	local powerConsumptionPerTurn = playerResources:GetPowerResourceDemandPerTurn(resourceType);

	-- Set values
	ExposedMembers.ResourceYields = {
		accumulationPerTurn = accumulationPerTurn,
		importPerTurn = importPerTurn,
		bonusPerTurn = bonusPerTurn,
		unitConsumptionPerTurn = unitConsumptionPerTurn,
		powerConsumptionPerTurn = powerConsumptionPerTurn
	};
end

-- Debug function for logging
function WriteToLog(message)
	if (debugMode and message ~= nil) then
		print(message);
	end
end

-- Init, uknow...
function Initialize()
	-- Set default (0) value for gifting-counter
	InitLocalGiftsThisTurn();

	-- Game-events we hook into, initial loading
	Events.LoadGameViewStateDone.Add(OnLoadGameViewStateDone);

	-- Game-events we hook into, unit-selection and movement
	Events.UnitSelectionChanged.Add(OnUnitSelectionChanged);
	Events.UnitMoveComplete.Add(OnUnitMoveComplete);

	-- Game-events we also need to know about, unit added and teleported
	Events.UnitAddedToMap.Add(OnUnitAddedToMap);
	Events.UnitTeleported.Add(OnUnitTeleported);

	-- Game-event for triggering all players received gift-count-reset
	Events.TurnEnd.Add(OnTurnEnd);

	-- Game-event for triggering diplo screen close
	Events.DiplomacySessionClosed.Add(OnDiplomacySessionClosed)

	-- Call a lua event for updating gifting-counters
	LuaEvents.SetGiftsThisTurn.Add(OnSetGiftsThisTurn);
	LuaEvents.SetReceivedGiftsThisTurn.Add(OnSetReceivedGiftsThisTurn);

	-- Game-events from gameplay-scripts to fire in UI (here)
	-- CURRENTLY NOT USED! Instead a "PlaceUnit"-Event is used to trigger the flag-update
	GameEvents = ExposedMembers.GameEvents;
	GameEvents.UpdateReligionFlag.Add(OnUpdateReligionFlag);
	GameEvents.PersistedGiftsThisTurn.Add(OnPersistedGiftsThisTurn);
	GameEvents.LoadedGiftsThisTurn.Add(OnLoadedGiftsThisTurn);

	-- These ones are actually used!
	GameEvents.AddGiftThisTurn.Add(OnAddGiftThisTurn);
	GameEvents.HandleGiftReactions.Add(OnHandleGiftReactions);

	-- These are used too!
	GameEvents.PersistGiftedUnits.Add(OnPersistGiftedUnits);
	GameEvents.FetchResourceYields.Add(OnFetchResourceYields);

	-- Init message log
	print("Initialized.");
end

-- Initialize the script
Initialize();
