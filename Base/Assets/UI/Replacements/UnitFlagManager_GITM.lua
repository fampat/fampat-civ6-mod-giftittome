-- ==========================================
-- GiftItToMe - Extension for UnitFlagManager
-- ==========================================

-- Check if FortifAI is active (get into compatibility mode)
local isFortifAIActive = Modding.IsModActive("20d1d40c-3085-11e9-b210-d663bd873d93");

-- Including the base-context file
if isFortifAIActive then
	-- FortifAI context (compatibility with FortifAI)
	-- ATTENTION: FortifAI _MUST_ loaded first!
	-- See modinfo <LoadOrder> for this file!
	include("UnitFlagManager_FAI.lua");
else
	-- Basegame context
	include("UnitFlagManager");
end

-- Add a log event for loading this
print("Loading UnitFlagManager_GITM.lua");

-- Update unit flag on demand/event for religious units
function OnUpdateUnitFlagReligious(playerID, unitID, unitX, unitY)
	-- Fetch player and unit
	local pPlayer = Players[playerID];
	local pUnit = pPlayer:GetUnits():FindID(unitID);

	-- If they are also real, continue
	if (pUnit ~= nil and pUnit:GetUnitType() ~= -1 and pUnit:GetReligionType() > 0 and pUnit:GetReligiousStrength() > 0) then
	-- Get current flag instance
		local flagInstance = GetUnitFlag(playerID, unitID);

		-- If its real, destroy the current flag-instance
		if flagInstance ~= nil then
			-- Update the unit instance
			flagInstance:UpdateReligion();
		end
	end
end

-- Our custom initialize
function Initialize_GITM_UniFlagManager()
	-- Log execution
	print("UnitFlagManager_GITM.lua: InitializeNow")

	-- Append our own lua-event
	LuaEvents.UpdateUnitFlagReligious.Add(OnUpdateUnitFlagReligious);
end

-- Our initialize
Initialize_GITM_UniFlagManager();
