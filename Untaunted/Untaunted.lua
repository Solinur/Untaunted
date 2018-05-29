local em = GetEventManager()
local _
local db,lastanchor
local dx = 1/GetSetting(SETTING_TYPE_UI, UI_SETTING_CUSTOM_SCALE) --Get UI Scale to draw thin lines correctly
UNTAUNTED_UI_SCALE = dx
local TIMER_UPDATE_RATE = 200
local tauntlist = {}	-- holds all currently registered unitid/abilityid pairs
local tauntdata = {}	-- holds all endtimes of registered effects
local OnTauntEnd

-- Addon Namespace
Untaunted = Untaunted or {}
local Untaunted = Untaunted
Untaunted.name 		= "Untaunted"
Untaunted.version 	= "0.2.12"

--local newapi = GetAPIVersion() > 100022

local ID_ELEDRAIN = 62787
local ID_OFFBALANCE = 62988
local ID_WEAKENING = 17945
local ID_SIPHON = 88575
local ID_WARHORN = 40224

local function Print(message, ...)
	if Untaunted.debug==false then return end
	df("[%s] %s", Untaunted.name, message:format(...))
end

local pool = ZO_ObjectPool:New(function(objectPool)

		return ZO_ObjectPool_CreateNamedControl("$(parent)UnitItem", "Untaunted_UnitItemTemplate", objectPool, Untaunted_TLW)
	
	end, 
	function(olditem, objectPool)  -- Removes an item from the taunt list and redirect the anchors. 
		
		local key = olditem.key
		if key == nil then return end
		
		olditem:SetHidden(true)
		
		local id, abilityId = olditem.id, olditem.abilityId
		
		if id and abilityId then tauntlist[id..","..abilityId] = nil end
		
		olditem.endTime = nil
		olditem.abilityId = nil
		olditem.id = nil
		
		OnTauntEnd(key)
		
		if olditem:GetNamedChild("Bar").timeline then olditem:GetNamedChild("Bar").timeline:PlayInstantlyToStart() end
		
		local _,point,rel,relpoint,x,y = olditem:GetAnchor(0)
		
		if olditem.anchored then 
		
			olditem.anchored:ClearAnchors()
			olditem.anchored:SetAnchor(point,rel,relpoint,x,y)
			rel.anchored = olditem.anchored
			olditem.anchored = nil
			
		else 
		
			rel.anchored = nil
			lastanchor = {point,rel,relpoint,x,y}
			
		end
	end)

local function SetBarAnimation(control, duration) --This creates the bar animation (moving and color change)
	
	duration = duration or 15000
	
	local timeline = ANIMATION_MANAGER:CreateTimeline() 
	
	timeline:SetPlaybackType(ANIMATION_PLAYBACK_ONE_SHOT)
	
	local _,_,rel,_,x,y = control:GetAnchor()
	local anchor = {TOPLEFT,control:GetParent():GetNamedChild("Icon"),TOPRIGHT,UI_SCALE,UI_SCALE}
	
	if db.bardirection == true then anchor = {TOPRIGHT,control:GetParent():GetNamedChild("Bg"),TOPRIGHT,UI_SCALE,UI_SCALE} end
	
	control:ClearAnchors()
	control:SetAnchor(unpack(anchor))
	
	local move = timeline:InsertAnimation(ANIMATION_SIZE, control)
	
	move:SetStartAndEndWidth(control:GetWidth(),0)
	move:SetStartAndEndHeight(control:GetHeight(),control:GetHeight())
	move:SetDuration(duration)
	
	local color1 = timeline:InsertAnimation(ANIMATION_COLOR, control)
	
	color1:SetColorValues(0,.8,0,1,.7,.7,0,1) 
	color1:SetDuration(duration/2)
	
	local color2 = timeline:InsertAnimation(ANIMATION_COLOR, control, duration/2)
	
	color2:SetColorValues(.7,.7,0,1,.8,0,0,1) 
	color2:SetDuration(duration/2)
	
	return timeline
end

local function GetGrowthAnchor(item)

	item = item or lastanchor[2].anchored
	
	local a1 = db.growthdirection and BOTTOMLEFT or TOPLEFT 
	local a2 = db.growthdirection and TOPLEFT or BOTTOMLEFT 	
	
	local sp = db.growthdirection and zo_round(-4/dx)*dx or zo_round(4/dx)*dx
	
	local anchor = {a1, item, a2, 0, sp}
	
	local firstitem = Untaunted_TLW.anchored
	
	firstitem:ClearAnchors()
	firstitem:SetAnchor(a1, Untaunted_TLW, a1, zo_round(4/dx)*dx, sp)
	
	return anchor
	
end 

local function NewItem(unitname, unitId, abilityId)  -- Adds an item to the taunt list,
	
	local item,key = pool:AcquireObject()
	
	item.key = key
	item.id = unitId
	
	item:SetHidden(false)
	item:ClearAnchors()
	item:SetAnchor(unpack(lastanchor))
	
	local label = item:GetNamedChild("Label")
	
	label:SetText(zo_strformat("<<!aC:1>>",unitname))
	label:SetFont("EsoUi/Common/Fonts/Univers57.otf".."|"..db.window.height-(4*dx)..'|soft-shadow-thin')
	
	local bg = item:GetNamedChild("Bg")
	
	bg:SetEdgeTexture("",1,1,dx,1)
	bg:SetEdgeColor(1,1,0,1)
	bg:SetDimensions(db.window.width,db.window.height)
	
	item:GetNamedChild("Bar"):SetDimensions(db.window.width-db.window.height-(zo_round(2/dx)*dx),db.window.height-(zo_round(2/dx)*dx))
	
	local icon = item:GetNamedChild("Icon")
	
	icon:SetDimensions(db.window.height,db.window.height)
	icon:SetTexture(GetAbilityIcon(abilityId))
	
	local timer = item:GetNamedChild("Timer")
	
	timer:SetHeight(db.window.height)
	timer:SetFont("EsoUi/Common/Fonts/Univers57.otf".."|"..db.window.height-(4*dx)..'|soft-shadow-thin')
	timer:SetText("15.0")
	
	lastanchor[2].anchored = item  -- stores a reference to the item at the item it is anchored to. This is needed when redirecting anchors when an item is removed (see below)
	lastanchor = GetGrowthAnchor(item)  -- new anchor for the next item 
	
	return key
end

local function OnTauntStart(key, endTime, abilityId)  -- Prepare Animation, start it and set off the timer. 
	
	if key==nil or endTime==nil then return end
	
	local duration = (endTime-GetGameTimeMilliseconds())
	local item = pool:GetExistingObject(key)
	local unitId = item.id
	
	item.endTime = endTime
	item.abilityId = abilityId
	
	local bar = item:GetNamedChild("Bar")
	
	if bar.timeline then bar.timeline:PlayInstantlyToStart() end
	bar.timeline = SetBarAnimation(bar, duration)  -- setup
	bar.timeline:PlayFromStart()

	local timer = item:GetNamedChild("Timer")
	
	local function TimerUpdate()  --update the timer text
		
		local duration = math.floor((endTime-GetGameTimeMilliseconds())/TIMER_UPDATE_RATE)/5
		
		if duration < -1 then
		
			pool:ReleaseObject(key)
			return 
			
		end 
		
		timer:SetText(string.format("%.1f",duration))
	end
	
	TimerUpdate() -- update the timer text once now
	
	em:RegisterForUpdate("Undaunted_Timer"..key, TIMER_UPDATE_RATE, TimerUpdate) -- keep updating the timer text
	
	return key
end

function OnTauntEnd(key)

	if key == nil then return end
	
	em:UnregisterForUpdate("Undaunted_Timer"..key)
	
	local item = pool:GetExistingObject(key)
	
	if item == nil then return end
	
	item:GetNamedChild("Bg"):SetEdgeColor(1,1,0,0)
	item:GetNamedChild("Timer"):SetText("")
end

local activeitems

local function OnTargetChange()

	if activeitems then
	
		for k,v in pairs(activeitems) do 
		
			local olditem = pool:GetExistingObject(v) 
			if olditem ~= nil then pool:GetExistingObject(v):GetNamedChild("Bg"):SetEdgeColor(1,1,0,0) end
		
		end
	end
	
	if not DoesUnitExist("reticleover") then return end
	
	local endTime, abilityId
	
	activeitems = {}
	
	for i = 1, GetNumBuffs("reticleover") do
	
		_, _, endTime, _, _, _, _, _, _, _, abilityId, _ = GetUnitBuffInfo("reticleover", i)
		
		if tauntdata[endTime] ~= nil and db.trackedabilities[abilityId] then  
		
			local key = tauntdata[endTime]
			
			table.insert(activeitems,key)
			
			-- Print("Found buff: %s, Key: %s",GetAbilityName(abilityId),key)
			
			local item = pool:GetExistingObject(key)
			
			if item ~= nil then item:GetNamedChild("Bg"):SetEdgeColor(1,1,0,1) end
			
		end
	end
end

-- EVENT_EFFECT_CHANGED (eventCode, changeType, effectSlot, effectName, unitTag, beginTime, endTime, stackCount, iconName, buffType, effectType, abilityType, statusEffectType, unitName, unitId, abilityId, sourceType)  
local function onTaunt( _,  changeType,  _,  _,  _, beginTime, endTime,  _,  _,  _,  effectType, _,  _,  unitName, unitId, abilityId, sourceType) 

	--Print("Changetype: %s, Effecttype: %s, Times: %.3f - %.3f Ability: %s (%s)", changeType, effectType, beginTime, endTime, GetAbilityName(abilityId), unitName)
	--Print("Eval: %s and %s",tostring(changeType~=1 and changeType~=2 and changeType~=3),tostring(effectType~=2 and effectType~=1))
	
	if (changeType~=1 and changeType~=2 and changeType~=3 and effectType~=2 and effectType~=1) or (sourceType~=1 and sourceType ~=2 and sourceType~=3 and abilityId~=102771) then return end
	
	local idkey = unitId..","..abilityId
	
	local key = tauntlist[idkey]
	
	if changeType==1 or changeType==3 then 
		
		if pool:GetActiveObjectCount() >= db.maxbars then return end
		
		Print("Key: %s, ID: %s", tostring(key), idkey)
		
		if key == nil then 
		
			key = NewItem(unitName, unitId, abilityId)
			tauntlist[idkey] = key
			
		end
		
		tauntdata[endTime] = key
		
		endTime = math.floor(endTime*1000)
		
		OnTauntStart(key, endTime, abilityId)
		
		OnTargetChange()
		
	elseif changeType==2 and key ~= nil then 
	
		tauntdata[endTime] = nil		
		
		if Untaunted.inCombat == false then 
			
			pool:ReleaseObject(key)			
		
		else 
		
			OnTauntEnd(key)
			
		end
	end
end

--(eventCode, result, isError, abilityName, abilityGraphic, abilityActionSlotType, sourceName, sourceType, targetName, targetType, hitValue, powerType, damageType, log, sourceUnitId, targetUnitId, abilityId) 

local function OnUnitDeath(_, result, _, _, _, _, _, _, targetName, targetType, _, _, _, _, _, targetUnitId, _) 
	
	for k,v in pairs(db.trackedabilities) do 
	
		local key = tauntlist[targetUnitId..","..k]
		
		if key ~= nil then
		
			pool:ReleaseObject(key)
			
		end
	end
end

local function Cleanup()

	if Untaunted.inCombat == false then
	
		Untaunted.ClearItems()
		em:UnregisterForUpdate("Untaunted_Cleanup")
		return
		
	end

	local validIds = {}
	
	local ActiveObjects = pool:GetActiveObjects()

	for key, item in pairs(ActiveObjects) do
	
		local unitId = item.id or 0
		local endTime = item.endTime or 0
		
		local now = GetGameTimeMilliseconds()
		
		if endTime - now > -5000 then validIds[unitId] = true end

	end
	
	for key, item in pairs(ActiveObjects) do
	
		local unitId = item.id	
		local abilityId = item.abilityId	
		
		if not validIds[unitId] then 
		
			pool:ReleaseObject(key)
			
		end
	end
end

local function OnCombatState(event, inCombat)  -- called by Event

  if inCombat ~= Untaunted.inCombat then     -- Check if player state changed
    
	Untaunted.inCombat = inCombat
		
    if inCombat == true then em:RegisterForUpdate("Untaunted_Cleanup", 500, Cleanup) end	
	
  end
end

local function MoveFrames()

	SCENE_MANAGER:Toggle("UNTAUNTED_MOVE_SCENE")
	
end

local function SavePosition(control)

	local x, y1 = control:GetScreenRect()
	local y2 = control:GetBottom() - GuiRoot:GetBottom()
	
	local upwards = db.growthdirection
	
	local y = upwards and y2 or y1

	x = zo_round(x/dx)*dx
	y = zo_round(y/dx)*dx
	
	local anchorside = upwards and BOTTOMLEFT or TOPLEFT
	
	db.window.x=x
	db.window.y=y
	
	control:ClearAnchors()
	control:SetAnchor(anchorside, GuiRoot, anchorside, x, y)
	
	lastanchor = {anchorside, control, anchorside, zo_round(4/dx)*dx, zo_round(4/dx)*dx}

end

local function RegisterAbilities()

	local name = Untaunted.name
	
	for k,v in pairs(db.trackedabilities) do
	
		em:UnregisterForEvent(name.."_ability_"..k)
		
	end
	
	for k,v in pairs(db.trackedabilities) do
	
		if v==true then 
			
			local idstring = name.."_ability_"..k
			
			em:RegisterForEvent(idstring, EVENT_EFFECT_CHANGED, onTaunt)
			
			local addfilter = {}
			
			if db.trackonlyplayer and k~=102771 then
			
				table.insert(addfilter, REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE)
				table.insert(addfilter, COMBAT_UNIT_TYPE_PLAYER)
				
			end
			
			if k==46537 then 
			
				table.insert(addfilter, REGISTER_FILTER_UNIT_TAG)
				table.insert(addfilter, "player")
				
			end
			
			em:AddFilterForEvent(idstring, EVENT_EFFECT_CHANGED, REGISTER_FILTER_ABILITY_ID, k, REGISTER_FILTER_IS_ERROR, false, unpack(addfilter)) -- Taunt: 38541, Elemental Drain: 62795
		end
	end
	
end 

local defaults = {

	["window"] 				= {x=150*dx,y=150*dx,height=zo_round(25/dx)*dx,width=zo_round(300/dx)*dx},
	["showmarker2"] 		= false,
	["growthdirection"] 	= false, --false=down
	["maxbars"] 			= 15, --false=down
	["bardirection"] 		= false, --false=to the left
	["accountwide"] 		= true,
	["trackonlyplayer"]		= true,	
	["trackedabilities"] 	= {
	
		[38541] = true, 
		[ID_ELEDRAIN] = false, 
		[81519]=false, 
		[68359]=false, 
		[88604]=false, 
		[88634]=false, 
		[17906]=false, 
		[46537]=false, 
		[ID_OFFBALANCE]=false, 
		[102771]=false, 
		[ID_WEAKENING]=false, 
	
	}
}

local addonpanel

local function MakeMenu()
    -- load the settings->addons menu library
	local menu = LibStub("LibAddonMenu-2.0")
	local def = defaults 

    -- the panel for the addons menu
	local panel = {
		type = "panel",
		name = "Untaunted",
		displayName = "Untaunted",
		author = "Solinur",
        version = Untaunted.version or "",
		registerForRefresh = false,
	}
	
	addonpanel = menu:RegisterAddonPanel("Untaunted_Options", panel)
	
    --this adds entries in the addon menu
	local options = {
		{
			type = "checkbox",
			name = GetString(SI_UNTAUNTED_MENU_AW_NAME),
			tooltip = GetString(SI_UNTAUNTED_MENU_AW_TOOLTIP),
			default = def.accountwide,
			getFunc = function() return Untaunted_Save.Default[GetDisplayName()]['$AccountWide']["accountwide"] end,
			setFunc = function(value) Untaunted_Save.Default[GetDisplayName()]['$AccountWide']["accountwide"] = value end,
			requiresReload = true,
		},	
		{
			type = "button",
			name = GetString(SI_UNTAUNTED_MENU_MOVE_BUTTON),
			tooltip = GetString(SI_UNTAUNTED_MENU_MOVE_BUTTON_TOOLTIP),
			func = MoveFrames,
		},
		{
			type = "slider",
			name = GetString(SI_UNTAUNTED_MENU_WINDOW_WIDTH),
			tooltip = GetString(SI_UNTAUNTED_MENU_WINDOW_WIDTH_TOOLTIP),
			min = 100,
			max = 500,
			step = 10,
			default = def.window.width,
			getFunc = function() return zo_round(db.window.width) end,
			setFunc = function(value) 
						db.window.width = zo_round(value/dx)*dx
						Untaunted.ShowItems(addonpanel)
					  end,
		},
		{
			type = "slider",
			name = GetString(SI_UNTAUNTED_MENU_WINDOW_HEIGHT),
			tooltip = GetString(SI_UNTAUNTED_MENU_WINDOW_HEIGHT_TOOLTIP),
			min = 15,
			max = 40,
			step = 1,
			default = def.window.height,
			getFunc = function() return zo_round(db.window.height) end,
			setFunc = function(value) 
						db.window.height = zo_round(value/dx)*dx 
						Untaunted.ShowItems(addonpanel)
					  end,
		},
		{
			type = "slider",
			name = GetString(SI_UNTAUNTED_MENU_MAX_BARS),
			tooltip = GetString(SI_UNTAUNTED_MENU_MAX_BARS_TOOLTIP),
			min = 5,
			max = 25,
			step = 1,
			default = def.maxbars,
			getFunc = function() return zo_round(db.maxbars) end,
			setFunc = function(value) 
						db.maxbars = value
						Untaunted.ShowItems(addonpanel)
					  end,
		},
		{
			type = "checkbox",
			name = GetString(SI_UNTAUNTED_MENU_GROWTH_DIRECTION),
			tooltip = GetString(SI_UNTAUNTED_MENU_GROWTH_DIRECTION_TOOLTIP),
			default = def.growthdirection,
			getFunc = function() return db.growthdirection end,
			setFunc = function(value) 
			
						db.growthdirection = value; 
						GetGrowthAnchor()
						
						Untaunted.ShowItems(addonpanel)

						SavePosition(Untaunted_TLW)
						
					  end,
		},
		{
			type = "checkbox",
			name = GetString(SI_UNTAUNTED_MENU_BAR_DIRECTION),
			tooltip = GetString(SI_UNTAUNTED_MENU_BAR_DIRECTION_TOOLTIP),
			default = def.bardirection,
			getFunc = function() return db.bardirection end,
			setFunc = function(value) 
						db.bardirection = value  
					  end,
		},
		{
			type = "checkbox",
			name = GetString(SI_UNTAUNTED_MENU_TRACKONLYPLAYER), -- Taunt: 38541
			tooltip = GetString(SI_UNTAUNTED_MENU_TRACKONLYPLAYER_TOOLTIP),
			default = def.trackonlyplayer,
			getFunc = function() return db.trackonlyplayer end,
			setFunc = function(value) 
						db.trackonlyplayer = value 
						RegisterAbilities()
					  end,
		},
		{
			type = "checkbox",
			name = GetString(SI_UNTAUNTED_MENU_TRACKTAUNT), -- Taunt: 38541
			tooltip = GetString(SI_UNTAUNTED_MENU_TRACKTAUNT_TOOLTIP),
			default = def.trackedabilities[38541],
			getFunc = function() return db.trackedabilities[38541] end,
			setFunc = function(value) 
						db.trackedabilities[38541] = value 
						RegisterAbilities()
					  end,
		},
		{
			type = "checkbox",
			name = GetString(SI_UNTAUNTED_MENU_TRACKELEDRAIN), -- Elemental Drain: 62795
			tooltip = GetString(SI_UNTAUNTED_MENU_TRACKELEDRAIN_TOOLTIP),
			default = def.trackedabilities[ID_ELEDRAIN],
			getFunc = function() return db.trackedabilities[ID_ELEDRAIN] end,
			setFunc = function(value) 
						db.trackedabilities[ID_ELEDRAIN] = value 
						RegisterAbilities()
					  end,
		},
		{
			type = "checkbox",
			name = GetString(SI_UNTAUNTED_MENU_TRACKINFAETHER), -- Infallible Aether: 81519
			tooltip = GetString(SI_UNTAUNTED_MENU_TRACKINFAETHER_TOOLTIP),
			default = def.trackedabilities[81519],
			getFunc = function() return db.trackedabilities[81519] end,
			setFunc = function(value) 
						db.trackedabilities[81519] = value 
						db.trackedabilities[68359] = value 
						RegisterAbilities()
					  end,
		},
		{
			type = "checkbox",
			name = GetString(SI_UNTAUNTED_MENU_TRACKCRUSHER), -- Crusher: 17906
			tooltip = GetString(SI_UNTAUNTED_MENU_TRACKCRUSHER_TOOLTIP),
			default = def.trackedabilities[17906],
			getFunc = function() return db.trackedabilities[17906] end,
			setFunc = function(value) 
						db.trackedabilities[17906] = value 
						RegisterAbilities()
					  end,
		},
		{
			type = "checkbox",
			name = GetString(SI_UNTAUNTED_MENU_TRACKSIPHON),
			tooltip = GetString(SI_UNTAUNTED_MENU_TRACKSIPHON_TOOLTIP),
			default = def.trackedabilities[ID_SIPHON],
			getFunc = function() return db.trackedabilities[ID_SIPHON] end,
			setFunc = function(value) 
						db.trackedabilities[ID_SIPHON] = value 
						RegisterAbilities()
					  end,
		},
		{
			type = "checkbox",
			name = GetString(SI_UNTAUNTED_MENU_TRACKWARHORN),
			tooltip = GetString(SI_UNTAUNTED_MENU_TRACKWARHORN_TOOLTIP),
			default = def.trackedabilities[ID_WARHORN],
			getFunc = function() return db.trackedabilities[ID_WARHORN] end,
			setFunc = function(value) 
						db.trackedabilities[ID_WARHORN] = value 
						RegisterAbilities()
					  end,
		},
		{
			type = "checkbox",
			name = GetString(SI_UNTAUNTED_MENU_OFF_BALANCE), -- Off Balance: 63003
			tooltip = GetString(SI_UNTAUNTED_MENU_OFF_BALANCE_TOOLTIP),
			default = def.trackedabilities[ID_OFFBALANCE],
			getFunc = function() return db.trackedabilities[ID_OFFBALANCE] end,
			setFunc = function(value) 
						db.trackedabilities[ID_OFFBALANCE] = value 
						RegisterAbilities()
					  end,
		},
		{
			type = "checkbox",
			name = GetString(SI_UNTAUNTED_MENU_OFF_BALANCE_IMMUNITY), -- Off Balance Immunity: 102771 (target buff)
			tooltip = GetString(SI_UNTAUNTED_MENU_OFF_BALANCE_IMMUNITY_TOOLTIP),
			default = def.trackedabilities[102771],
			getFunc = function() return db.trackedabilities[102771] end,
			setFunc = function(value) 
						db.trackedabilities[102771] = value 
						RegisterAbilities()
					  end,
		},
		{
			type = "checkbox",
			name = GetString(SI_UNTAUNTED_MENU_WEAKENING),
			tooltip = GetString(SI_UNTAUNTED_MENU_WEAKENING_TOOLTIP),
			default = def.trackedabilities[ID_WEAKENING],
			getFunc = function() return db.trackedabilities[ID_WEAKENING] end,
			setFunc = function(value) 
						db.trackedabilities[ID_WEAKENING] = value 
						RegisterAbilities()
					  end,
		},
	}

	menu:RegisterOptionControls("Untaunted_Options", options)
	
	function Untaunted.ClearItems()
	
		if Untaunted.inCombat or SCENE_MANAGER:IsShowingNext("UNTAUNTED_MOVE_SCENE") then return end
		
		pool:ReleaseAllObjects()
		
		tauntlist = {}
		tauntdata = {}	
	end
	
	function Untaunted.ShowItems(currentpanel)
	
		if currentpanel ~= addonpanel and (not SCENE_MANAGER:IsShowing("UNTAUNTED_MOVE_SCENE")) then return end
		
		Untaunted_TLW:SetHidden(false)
		Untaunted.ClearItems()
		
		for i=1,db.maxbars do
		
			NewItem("Unit"..i, i, 38541)
			
		end
	end
	
	function Untaunted.SceneEnd(oldstate, newstate)
	
		if newstate == "hidden" then
		
			menu:OpenToPanel(addonpanel)
			Untaunted_TLW:SetMovable( false )
			Untaunted_TLW:SetMouseEnabled( false )
			
		elseif newstate == "shown" then
		
			Untaunted_TLW:SetMovable( true )
			Untaunted_TLW:SetMouseEnabled( true )
			
		end
	end	
	
	CALLBACK_MANAGER:RegisterCallback("LAM-PanelOpened", Untaunted.ShowItems )
	CALLBACK_MANAGER:RegisterCallback("LAM-PanelClosed", Untaunted.ClearItems )
	
	return menu
end

-- Initialization
function Untaunted:Initialize(event, addon)

	local name = self.name

	if addon ~= name then return end --Only run if this addon has been loaded
 
	-- load saved variables
	
	local SaveIdString = self.name.."_Save"
 
	db = ZO_SavedVars:NewAccountWide(SaveIdString, 7, nil, defaults) -- taken from Aynatirs guide at http://www.esoui.com/forums/showthread.php?t=6442
	
	if db.accountwide == false then
		db = ZO_SavedVars:NewCharacterIdSettings(SaveIdString, 7, nil, defaults)
		db.accountwide = false
	end
	
	if db.APIversion == nil then 	-- reload abilitytable if upgrading
	
		local newabilitydata = {}
		
		ZO_DeepTableCopy(defaults.trackedabilities, newabilitydata)
		
		db.trackedabilities = newabilitydata
		
		db.APIversion = GetAPIVersion()
		
	end
		
	
	Untaunted.debug = false
	Untaunted.db = db
	
	RegisterAbilities()
	
	--register Events
	em:UnregisterForEvent(name.."_load", EVENT_ADD_ON_LOADED) 
 	 	
	em:RegisterForEvent(name.."_unit", EVENT_COMBAT_EVENT, OnUnitDeath)
	em:AddFilterForEvent(name.."_unit", EVENT_COMBAT_EVENT, REGISTER_FILTER_COMBAT_RESULT, 2260, REGISTER_FILTER_IS_ERROR, false) -- not needed? 
 	 	
	em:RegisterForEvent(name.."_unit2", EVENT_COMBAT_EVENT, OnUnitDeath)
	em:AddFilterForEvent(name.."_unit2", EVENT_COMBAT_EVENT, REGISTER_FILTER_COMBAT_RESULT, 2262, REGISTER_FILTER_IS_ERROR, false)
	 
	em:RegisterForEvent(name.."_combat", EVENT_PLAYER_COMBAT_STATE, OnCombatState)
	em:RegisterForEvent(name.."_target", EVENT_RETICLE_TARGET_CHANGED , OnTargetChange)
		
	self.playername = zo_strformat("<<!aC:1>>",GetUnitName("player"))
	self.inCombat = IsUnitInCombat("player")
	
	MakeMenu()
		
	local window = Untaunted_TLW	
	
	local anchorside = db.growthdirection and BOTTOMLEFT or TOPLEFT
	
	if (db.window) then
		window:ClearAnchors()
		window:SetAnchor(anchorside, GuiRoot, anchorside, db.window.x, db.window.y)
	end
		
	window:SetHandler("OnMoveStop", SavePosition)	
	
	SavePosition(window)
	
	local fragment = ZO_SimpleSceneFragment:New(window)
	HUD_SCENE:AddFragment(fragment)
	HUD_UI_SCENE:AddFragment(fragment)
	
	local scene = ZO_Scene:New("UNTAUNTED_MOVE_SCENE", SCENE_MANAGER)
	scene:AddFragment(fragment)
	scene:RegisterCallback("StateChange", Untaunted.SceneEnd)
	
	Untaunted.ShowItems(addonpanel)
	zo_callLater(Untaunted.ClearItems, 1)
end

-- Finally, we'll register our event handler function to be called when the proper event occurs.
em:RegisterForEvent(Untaunted.name.."_load", EVENT_ADD_ON_LOADED, function(...) Untaunted:Initialize(...) end)