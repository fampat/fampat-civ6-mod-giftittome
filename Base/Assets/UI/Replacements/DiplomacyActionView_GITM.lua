-- ==============================================
-- GiftItToMe - Extension for DiplomacyActionView
-- ==============================================

-- Add a log event for loading this
print("Loading DiplomacyActionView_GITM.lua");

-- Determine which expensions are active
local isExpansion1Active = Modding.IsModActive("1B28771A-C749-434B-9053-D1380C553DE9");
local isExpansion2Active = Modding.IsModActive("4873eb62-8ccc-4574-b784-dda455e74e68");

-- Including the base-context file
if isExpansion2Active then
	-- Expension 2 context
	include("DiplomacyActionView_Expansion2.lua");
elseif isExpansion1Active then
	-- Expension 1 context
	include("DiplomacyActionView_Expansion1.lua");
else
	-- Basegame context
	include("DiplomacyActionView");
end

-- Bind included functions to extend them
ORIGINAL_LateInitialize = LateInitialize;
ORIGINAL_OnDiplomacyStatement = OnDiplomacyStatement;

-- Our local variable for controlling the diplo-view
local b_SkipDiplomaticStatement = false;

-- Wrapper for the original event-function
function OnDiplomacyStatement(fromPlayer : number, toPlayer : number, kVariants : table)
	-- Do we want to skip the diplo-view?
	if not b_SkipDiplomaticStatement then
		-- If not, show the original diplo-view
		ORIGINAL_OnDiplomacyStatement(fromPlayer, toPlayer, kVariants);
	end
end

-- Our event-function for controlling the diplo-view
function OnSkipDiplomaticStatement(skipDiplomaticStatement)
	-- Set the requested value here
	b_SkipDiplomaticStatement = skipDiplomaticStatement;
end

-- Wrapper for the original event-function
function LateInitialize()
	-- Call the original event-function
	ORIGINAL_LateInitialize();
	
	-- Append our own lua-event
	LuaEvents.SkipDiplomaticStatement.Add(OnSkipDiplomaticStatement);
end
