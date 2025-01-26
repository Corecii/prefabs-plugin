local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")

local lastTimeoutStart: number?
local function manualTimeout()
	if lastTimeoutStart == nil then
		lastTimeoutStart = os.clock()
		task.defer(function()
			lastTimeoutStart = nil
		end)
	elseif os.clock() - lastTimeoutStart > 1 then
		error("TIMEOUT")
	end
end

local QUIT_SEARCHING_FOR_ANCESTOR_TEMPLATES_AFTER_FIRST = true

local parents: { Instance } = {
	game:GetService("ReplicatedStorage"),
	game:GetService("ServerStorage"),
}

local defaultPropertyKeep: { [string]: { string } } = {
	Instance = { "Name" },
	PVInstance = { "WorldPivot" },
	Model = { "Scale" },
	BasePart = { "CFrame" },
	Attachment = { "WorldCFrame" },
	GuiObject = { "Position" },
}

local defaultAttributeKeep = {}

local dynamicKeep = {
	WorldPivot = function(old: PVInstance, new: PVInstance, _property: string)
		new:PivotTo(old:GetPivot())
	end,
	Tags = function(old: Instance, new: Instance, _property: string)
		local newTagsSet = {}
		for _, tag in new:GetTags() do
			newTagsSet[tag] = true
		end
		
		for _, tag in old:GetTags() do
			if newTagsSet[tag] then
				newTagsSet[tag] = nil
			else
				new:AddTag(tag)
			end
		end
		
		for tag, _ in newTagsSet do
			new:RemoveTag(tag)
		end
	end,
	Attributes = function(old: Instance, new: Instance, _property: string)
		for key, value in old:GetAttributes() do
			new:SetAttribute(key, value)
		end
	end,
	Scale = function(old: Instance, new: Instance, _property: string)
		if old:IsA("Model") and new:IsA("Model") then
			new:ScaleTo(old:GetScale())
		else
			(new :: any).Scale = (old :: any).Scale
		end
	end,
}

local function defaultKeep(old: Instance, new: Instance, property: string)
	(new :: any)[property] = (old :: any)[property]
end

local ignoredProps: { [string]: { string } } = {
	Instance = {
		"Parent",
		-- Aliases for Position, Size, and Rotation
		"AbsolutePosition", "AbsoluteSize", "AbsoluteRotation"
	},
	BasePart = {
		-- Local properties
		"LocalTransparencyModifier",
		-- Aliases for CFrame
		"Position", "AssemblyCenterOfMass", "Orientation", "Rotation",
		-- Aliases for Color
		"BrickColor",
	},
	Model = {
		-- Aliases for WorldPivot
		"WorldPivotData", "Pivot Offset", "Origin"
	},
}

local ignoredPropsSet: { [string]: { [string]: boolean }} = {}
for key, props in ignoredProps do
	local propsSet = {}
	for _, prop in props do
		propsSet[prop] = true
	end
	ignoredPropsSet[key] = propsSet
end

local ignoredDescendantClasses = { "TouchTransmitter" }

local Prefab = {}

local PrefabStore = require(script.PrefabStore)

Prefab.PrefabStore = PrefabStore

export type Store = PrefabStore.Store

function Prefab.getPrefabLocations(): { Instance }
	return CollectionService:GetTagged("PrefabsLocation")
end

function Prefab.createDefaultPrefabLocations(): { Instance }
	local locations = {}
	for _, parent in parents do
		local prefabs = parent:FindFirstChild("Prefabs")
		if not prefabs then
			prefabs = Instance.new("Folder")
			assert(prefabs)

			prefabs.Name = "Prefabs"
			prefabs:AddTag("PrefabsLocation")
			prefabs.Parent = parent
		end
		
		table.insert(locations, parent)
	end
	
	return locations
end

function Prefab.getPrefabId(thing: Instance): string?
	return thing:GetAttribute("PrefabId") :: any
end

function Prefab.getCanonicalPrefab(id: string): Instance?
	local locations = Prefab.getPrefabLocations()
	while locations[1] do
		manualTimeout()
		local location = table.remove(locations)
		assert(location)
		for _, child in location:GetChildren() do
			if child:HasTag("Prefab") then
				if child:GetAttribute("PrefabId") == id then
					return child
				end
			else
				table.insert(locations, child)
			end
		end
	end
	
	return nil
end

function Prefab.updateCanonicalPrefabWith(thing: Instance)
	local canonicalParent, canonicalVersion, canonicalName

	local canonical = Prefab.getCanonicalPrefab(thing:GetAttribute("PrefabId") :: any)
	if canonical then
		canonicalParent = canonical.Parent
		canonicalVersion = (canonical:GetAttribute("PrefabVersion") :: any or 1) + 1
		canonicalName = canonical.Name
		canonical.Parent = nil
	else
		if #Prefab.getPrefabLocations() == 0 then
			Prefab.createDefaultPrefabLocations()
		end
		
		canonicalParent = Prefab.getPrefabLocation(thing:GetAttribute("PrefabLocation") :: any or "ServerStorage.<Prefabs>")
		canonicalVersion = thing:GetAttribute("PrefabVersion") or 1
		canonicalName = thing.Name
	end
	
	thing:SetAttribute("PrefabForked", false)
	
	local newPrefab = thing:Clone()
	newPrefab:SetAttribute("PrefabVersion", canonicalVersion)
	newPrefab.Name = canonicalName
	newPrefab.Parent = canonicalParent
	
	thing:SetAttribute("PrefabVersion", canonicalVersion)
end

function Prefab.getCanonicalPrefabsInLocations(locations: { Instance }): { { id: string, prefab: Instance } }
	local prefabs = {}

	local locations = table.clone(locations)
	while locations[1] do
		manualTimeout()
		local location = table.remove(locations)
		assert(location)
		for _, child in location:GetChildren() do
			if child:GetAttribute("PrefabId") then
				table.insert(prefabs, {
					id = child:GetAttribute("PrefabId") :: string,
					prefab = child
				})
			else
				table.insert(locations, child)
			end
		end
	end
	
	return prefabs
end

function Prefab.getAllCanonicalPrefabs()
	return Prefab.getCanonicalPrefabsInLocations(Prefab.getPrefabLocations())
end

function Prefab.getKeepValues(thing: Instance): { properties: { string }, attributes: { string }, tags: { string } }
	
	local function splitTrimmedOrEmpty(full: string?)
		if not full then
			return {}
		end
		
		local fullSplit = string.split(full, ",")
		local values = {}
		for _, valueUntrimmed in fullSplit do
			local value = string.match(valueUntrimmed, "^%s*(.-)%s*$")
			table.insert(values, value)
		end
		
		return values
	end
	
	return {
		properties = splitTrimmedOrEmpty(thing:GetAttribute("PrefabPropertiesToKeep") :: any),
		attributes = splitTrimmedOrEmpty(thing:GetAttribute("PrefabAttributesToKeep") :: any),
		tags = splitTrimmedOrEmpty(thing:GetAttribute("PrefabTagsToKeep") :: any),
	}
end

local function copyArray(from: { any }, to: { any })
	table.move(from, 1, #from, #to + 1, to)
end

function Prefab.replaceItem(thing: Instance, prefab: Instance, keepMode: "target" | "prefab" | "both" | nil): Instance
	local newThing = prefab:Clone()
	
	local keepValues = {
		properties = {},
		attributes = {},
		tags = {},
	}
	
	if keepMode == "target" or keepMode == "both" then
		local keep = Prefab.getKeepValues(thing)
		
		copyArray(keep.properties, keepValues.properties)
		copyArray(keep.attributes, keepValues.attributes)
		copyArray(keep.tags, keepValues.tags)
	end

	if keepMode == "prefab" or keepMode == "both" then
		local keep = Prefab.getKeepValues(prefab)

		copyArray(keep.properties, keepValues.properties)
		copyArray(keep.attributes, keepValues.attributes)
		copyArray(keep.tags, keepValues.tags)
	end
	
	for _, property in keepValues.properties do
		local keepFn = defaultKeep
		if dynamicKeep[property] then
			keepFn = dynamicKeep[property]
		end

		local okay, err = (pcall :: any)(keepFn, thing, newThing, property)
		if not okay then
			warn(`Failed to keep property {property} during prefab replacement: {err}`)
		end
	end
	
	for _, attribute in keepValues.attributes do
		local okay, err = pcall(function()
			newThing:SetAttribute(attribute, thing:GetAttribute(attribute))
		end)
		if not okay then
			warn(`Failed to keep attribute {attribute} during prefab replacement: {err}`)
		end
	end
	
	for _, tag in keepValues.tags do
		if newThing:HasTag(tag) and not thing:HasTag(tag) then
			newThing:RemoveTag(tag)
		elseif not newThing:HasTag(tag) and thing:HasTag(tag) then
			newThing:AddTag(tag)
		end
	end
	
	thing.Parent, newThing.Parent = nil, thing.Parent
	
	newThing:SetAttribute("PrefabForked", false)
	
	return newThing
end

function Prefab.splitLocationString(preference: string): { string }
	local preferenceParts = string.split(preference, ".")

	-- Use \ to escape any character.
	-- Use \. to escape string splitting.
	local outerIndex = 1
	while outerIndex < #preferenceParts do
		manualTimeout()
		local part = preferenceParts[outerIndex]

		local index = 1
		while index <= #part do
			manualTimeout()
			local fStart, fEnd = string.find(part, "\\.?", index)
			if not fStart or not fEnd then
				break
			end

			if fStart == fEnd then
				-- must be at end, escaping . which split removed
				if preferenceParts[outerIndex + 1] then
					part = string.sub(part, 1, fStart - 1) .. "." .. table.remove(preferenceParts, outerIndex + 1) :: string
				end
			else
				part = string.sub(part, 1, fStart - 1) .. string.sub(part, fEnd, #part)
			end

			index = fStart + 1
		end
		
		preferenceParts[outerIndex] = part
		
		outerIndex += 1
	end
	
	return preferenceParts
end

function Prefab.buildLocationString(location: { string }): string
	local parts = table.create(#location)
	for _, part in location do
		part = string.gsub(part, "\\", "\\\\")
		part = string.gsub(part, "%.", "\\.")
		table.insert(parts, part)
	end
	
	return table.concat(parts, ".")
end

function Prefab.getLocationStringFromCurrentLocation(prefab: Instance): string
	local location = {}
	
	local thing = prefab.Parent
	while thing and thing ~= game do
		manualTimeout()
		if thing:HasTag("PrefabsLocation") then
			table.insert(location, 1, `<{thing.Name}>`)
		else
			table.insert(location, 1, thing.Name)
		end
		thing = thing.Parent
	end
	
	return Prefab.buildLocationString(location)
end

function Prefab.getPrefabLocation(preference: string): (Instance?, boolean)
	local locationPref = Prefab.splitLocationString(preference)

	local ancestry, descendants = {}, {}
	local folderName
	for _, value in locationPref do
		if value:sub(1, 1) == "<" and value:sub(-1, -1) == ">" then
			folderName = value:sub(2, -2)
		elseif not folderName then
			table.insert(ancestry, 1, value)
		else
			table.insert(descendants, 1, value)
		end
	end
	
	local locations = Prefab.getPrefabLocations()
	
	local nextBest = locations[1]
	for _, location in locations do
		if location.Name ~= folderName then
			continue
		end

		local failed = false

		local ancestor = assert(location.Parent)
		for _, name in ancestry do
			if ancestor.Name ~= name then
				failed = true
				break
			end
		end
		if failed then
			continue
		end
		
		nextBest = location

		local descendant: Instance? = location
		for _, name in descendants do
			descendant = assert(descendant):FindFirstChild(name)
			if not descendant then
				failed = true
				break
			end
		end
		if failed then
			continue
		end

		return descendant, true
	end
	
	return nextBest, false
end

function Prefab.storePrefab(prefab: Instance)
	local preference = prefab:GetAttribute("PrefabLocation") :: string?
	if typeof(preference) ~= "string" then
		preference = "ServerStorage.<Prefabs>"
	end
	assert(preference)
	
	local location = Prefab.getPrefabLocation(preference)
	
	prefab:SetAttribute("PrefabEditLocation", Prefab.getLocationStringFromCurrentLocation(prefab))
	
	if location then
		prefab.Parent = location
	else
		warn(`No canonical prefab locations exist. Not moving prefab.`)
	end
end

function Prefab.getOrCreateEditLocation(prefab: Instance)
	local preferredEditLocationStr = prefab:GetAttribute("PrefabEditLocation")
	if typeof(preferredEditLocationStr) == "string" then
		local preferredEditLocation, exactMatch = Prefab.getPrefabLocation(preferredEditLocationStr)
		
		local warnMessage = `Could not get preferred edit location, "{preferredEditLocationStr}", using default.`
		if preferredEditLocation then
			if prefab:IsA("Attachment") and not preferredEditLocation:FindFirstAncestorWhichIsA("BasePart") then
				warnMessage = `Preferred edit location for Attachment is invalid: must be in a BasePart. Using Workspace.Terrain instead.`
			elseif exactMatch then
				return preferredEditLocation
			end
		end
		
		warn(warnMessage)
	end

	local requisiteAncestor
	if prefab:IsA("LayerCollector") then
		requisiteAncestor = game:GetService("StarterGui")
	elseif prefab:IsA("Attachment") then
		requisiteAncestor = workspace.Terrain
	else
		requisiteAncestor = game:GetService("Workspace")
	end

	for _, location in Prefab.getPrefabLocations() do
		if location:IsDescendantOf(requisiteAncestor) then
			return location
		end
	end
	
	-- Found no existing locations. Let's make a new one.
	local location = Instance.new("Folder")
	location.Name = "Prefabs"
	location:AddTag("PrefabsLocation")
	location.Parent = requisiteAncestor
	
	return location
end

function Prefab.editPrefab(prefab: Instance)
	local editLocation = Prefab.getOrCreateEditLocation(prefab)
	
	prefab:SetAttribute("PrefabLocation", Prefab.getLocationStringFromCurrentLocation(prefab))
	
	prefab.Parent = editLocation
end

function Prefab.createPrefab(thing: Instance, name: string?)
	local prefabId = HttpService:GenerateGUID()
	
	thing:AddTag("Prefab")
	thing:SetAttribute("PrefabId", prefabId)
	thing:SetAttribute("PrefabVersion", 1)
	thing:SetAttribute("PrefabForked", false)
	
	if thing:GetAttribute("PrefabLocation") == nil then
		thing:SetAttribute("PrefabLocation", "ServerStorage.<Prefabs>")
	end
	
	if thing:GetAttribute("PrefabPropertiesToKeep") == nil then
		local list = {}
		for className, properties in defaultPropertyKeep do
			if thing:IsA(className) then
				table.move(properties, 1, #properties, #list + 1, list)
			end
		end
		
		thing:SetAttribute("PrefabPropertiesToKeep", table.concat(list, ", "))
	end
	if thing:GetAttribute("PrefabAttributesToKeep") == nil then
		thing:SetAttribute("PrefabAttributesToKeep", table.concat(defaultAttributeKeep, ", "))
	end
	if thing:GetAttribute("PrefabTagsToKeep") == nil then
		thing:SetAttribute("PrefabTagsToKeep", "")
	end
	
	if thing:GetAttribute("PrefabLocation") == nil then
		thing:SetAttribute("PrefabLocation", "ServerStorage.<Prefabs>")
	end
	
	local prefab = thing:Clone()
	if name then
		prefab.Name = name
	end
	
	Prefab.storePrefab(prefab)
end

function Prefab.replaceAll(id: string): { [Instance]: Instance }
	local map = {}
	
	local prefab = Prefab.getCanonicalPrefab(id)
	assert(prefab, `Prefab does not exist: {id}`)
	
	for _, item in CollectionService:GetTagged("Prefab") do
		if item == prefab then
			continue
		end
		if item:GetAttribute("PrefabId") == id and not item:GetAttribute("PrefabForked") then
			local newItem = Prefab.replaceItem(item, prefab)
			map[item] = newItem
		end
	end
	
	return map
end

local function diffTags(old: { string }, new: { string }): { [string]: boolean }
	local oldSet = {}
	for _, tag in old do
		oldSet[tag] = true
	end
	
	local changes = {}
	for _, tag in new do
		if oldSet[tag] then
			oldSet[tag] = nil
		else
			changes[tag] = true
		end
	end
	for tag, _ in oldSet do
		changes[tag] = true
	end
	
	return changes
end

local function diffAttributes(old: { [string]: any }, new: { [string]: any })
	local changes = {}
	
	local oldMut = table.clone(old)
	
	for key, value in new do
		if oldMut[key] == value then
			oldMut[key] = nil
		else
			changes[key] = true
		end
	end
	for key, value in oldMut do
		changes[key] = true
	end
	
	return changes
end

function Prefab.watchSelection()
	local allPrefabFns: { [string]: { selected: { [Instance]: boolean }, canonical: Instance? } } = {}
	local allConns: { [Instance]: { RBXScriptConnection } } = {}
	
	local lastUndoRedo = 0
	game:GetService("ChangeHistoryService").OnUndo:Connect(function()
		lastUndoRedo = os.clock()
	end)
	game:GetService("ChangeHistoryService").OnRedo:Connect(function()
		lastUndoRedo = os.clock()
	end)
	
	local function checkUndoRedo()
		local now = os.clock()
		
		task.defer(coroutine.running())
		coroutine.yield()
		
		return lastUndoRedo >= now
	end
	
	local triggerUpdateSignal = Instance.new("BindableEvent")
	
	local function updateSelection(selection: { Instance })
		local selectedPrefabs: { [string]: { [Instance]: boolean } } = {}
		local selectionSet = {}
		local selectionToPrefabAncestor: { [Instance]: Instance | false | nil } = {}

		
		for _, item in selection do
			selectionSet[item] = true

			local check: Instance? = item
			local path: { Instance } = {}
			while check do
				manualTimeout()
				local prefabAncestor: Instance | false | nil = selectionToPrefabAncestor[check]
				local alreadyFound = prefabAncestor ~= nil
				
				local prefabId = check:GetAttribute("PrefabId") :: string?
				if not prefabAncestor and prefabId then
					selectedPrefabs[prefabId] = selectedPrefabs[prefabId] or {}
					selectedPrefabs[prefabId][check] = true
					
					selectionToPrefabAncestor[check] = check
					prefabAncestor = check
				end
				
				if prefabAncestor then
					for _, pathItem in path do
						selectionToPrefabAncestor[pathItem] = prefabAncestor
					end
					table.clear(path)
				else
					selectionToPrefabAncestor[check] = false
					table.insert(path, check)
				end

				check = check.Parent
				
				if alreadyFound then
					break
				end
				
				if QUIT_SEARCHING_FOR_ANCESTOR_TEMPLATES_AFTER_FIRST and prefabAncestor then
					break
				end
			end
		end
		
		for instance, conns in allConns do
			if not selectionSet[instance] then
				for _, conn in conns do
					conn:Disconnect()
				end
				
				allConns[instance] = nil
			end
		end
		
		for id, prefabFns in allPrefabFns do
			if not selectedPrefabs[id] then
				allPrefabFns[id] = nil
			end
		end
		
		for id, items in selectedPrefabs do
			if not allPrefabFns[id] then
				allPrefabFns[id] = {
					selected = items,
					canonical = Prefab.getCanonicalPrefab(id),
				}
			else
				allPrefabFns[id].selected = items
				allPrefabFns[id].canonical = Prefab.getCanonicalPrefab(id)
			end
		end
		
		for instance: Instance, _ in selectionSet do
			local prefabAncestor: Instance | false | nil = selectionToPrefabAncestor[instance]
			if not prefabAncestor then
				continue
			end
			assert(typeof(prefabAncestor) == "Instance")

			local prefabId = prefabAncestor:GetAttribute("PrefabId")
			if not prefabId or not allPrefabFns[prefabId] then
				continue
			end
			if prefabAncestor == allPrefabFns[prefabId].canonical then
				continue
			end
			
			if not allConns[instance] then
				local lastTags, lastAttributes = instance:GetTags(), instance:GetAttributes()
				
				local conns = {}
				table.insert(conns, instance.Changed:Connect(function(propName)
					if checkUndoRedo() then
						return
					end
					
					local keepValues = Prefab.getKeepValues(instance)
					
					if table.find(keepValues.properties, propName) then
						return
					end
					
					if propName == "Tags" then
						local newTags = instance:GetTags()
						local changes = diffTags(lastTags, newTags)
						lastTags = newTags
						
						local noChange = true
						for tag, _ in changes do
							if table.find(keepValues.tags, tag) then
								continue
							end
							
							noChange = false
						end
						if noChange then
							return
						end
					elseif propName == "Attributes" then
						local newAttributes = instance:GetAttributes()
						local changes = diffAttributes(lastAttributes, newAttributes)
						lastAttributes = newAttributes
						
						local noChange = true
						for attribute, _ in changes do
							if table.find(keepValues.attributes, attribute) then
								continue
							end
							if string.match(attribute, "^Prefab") then
								continue
							end
							
							noChange = false
						end
						if noChange then
							return
						end
					else
						for className, props in ignoredPropsSet do
							if instance:IsA(className) and props[propName] then
								return
							end
						end
						
						local readable = pcall(function()
							return (instance :: any)[propName]
						end)
						
						if not readable then
							return
						end
					end
					
					prefabAncestor:SetAttribute("PrefabForked", true)
					triggerUpdateSignal:Fire()
				end))
				table.insert(conns, instance.DescendantAdded:Connect(function(item)
					if checkUndoRedo() then
						return
					end
					
					for _, class in ignoredDescendantClasses do
						if item:IsA(class) then
							return
						end
					end
					
					prefabAncestor:SetAttribute("PrefabForked", true)
					triggerUpdateSignal:Fire()
				end))
				table.insert(conns, instance.DescendantRemoving:Connect(function(item)
					if checkUndoRedo() then
						return
					end

					for _, class in ignoredDescendantClasses do
						if item:IsA(class) then
							return
						end
					end

					prefabAncestor:SetAttribute("PrefabForked", true)
					triggerUpdateSignal:Fire()
				end))
			end
		end
	end
	
	local result = {}
	
	result.updated = triggerUpdateSignal.Event :: RBXScriptSignal<()>
	
	function result.getSelectedPrefabs(): typeof(allPrefabFns)
		return table.clone(allPrefabFns)
	end
	
	function result.update(selection: { Instance })
		updateSelection(selection)
	end
	
	return result
end

return Prefab