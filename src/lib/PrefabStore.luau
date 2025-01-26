local CollectionService = game:GetService("CollectionService")

local PrefabStore = {}

function PrefabStore.new()
	local allPrefabs: { [string]: { [Instance]: number }} = {}
	
	local prefabAddedSignal = Instance.new("BindableEvent")
	local prefabRemovedSignal = Instance.new("BindableEvent")
	local prefabChangedSignal = Instance.new("BindableEvent")
	
	local function addPrefab(id: string, instance: Instance)
		if not allPrefabs[id] then
			allPrefabs[id] = {}
		end
		
		allPrefabs[id][instance] = (allPrefabs[id][instance] or 0) + 1
		
		if allPrefabs[id][instance] == 1 then
			prefabAddedSignal:Fire(id)
		else
			prefabChangedSignal:Fire(id)
		end
	end
	
	local function delPrefab(id: string, instance: Instance)
		-- print("delPrefab", instance)
		if not allPrefabs[id] then
			-- print("  not exist")
			return
		end
		
		if not allPrefabs[id][instance] then
			-- print("  not exist (2)")
			return
		end
		
		allPrefabs[id][instance] -= 1
		
		-- print("  remaining count", allPrefabs[id][instance])
		
		if allPrefabs[id][instance] <= 0 then
			-- print(   "deleting")
			allPrefabs[id][instance] = nil
			if next(allPrefabs[id]) == nil then
				allPrefabs[id] = nil
			end
			
			prefabRemovedSignal:Fire(id)
		else
			prefabChangedSignal:Fire(id)
		end
	end
	
	local connectedLocations: { [Instance]: { RBXScriptConnection } } = {}
	local function addLocation(location: Instance)
		if connectedLocations[location] then
			return
		end
		
		local items = { location }
		while items[1] do
			local item = table.remove(items)
			assert(item)

			local prefabId = item:GetAttribute("PrefabId") :: string
			if typeof(prefabId) == "string" then
				addPrefab(prefabId, item)
			else
				local children = item:GetChildren()
				table.move(children, 1, #children, #items + 1, items)
			end
		end
		
		local conns = {}
		conns[1] = location.DescendantAdded:Connect(function(item)
			local prefabId = item:GetAttribute("PrefabId")
			if typeof(prefabId) == "string" then
				addPrefab(prefabId, item)
			end
		end)
		conns[2] = location.DescendantRemoving:Connect(function(item)
			-- print("might remove prefab", item)

			-- allow any Added signals on other prefab folders to complete first
			task.defer(function()
				local prefabId = item:GetAttribute("PrefabId")
				if typeof(prefabId) == "string" then
					delPrefab(prefabId, item)
				end
			end)
		end)
		
		connectedLocations[location] = conns
	end
	
	local function delLocation(location: Instance)
		if connectedLocations[location] then
			for _, conn in connectedLocations[location] do
				conn:Disconnect()
			end
			connectedLocations[location] = nil
		end
		
		local items = { location }
		while items[1] do
			local item = table.remove(items)
			assert(item)

			local prefabId = item:GetAttribute("PrefabId") :: string
			if typeof(prefabId) == "string" then
				delPrefab(prefabId, item)
			else
				local children = item:GetChildren()
				table.move(children, 1, #children, #items + 1, items)
			end
		end
	end
	
	local conn1 = CollectionService:GetInstanceAddedSignal("PrefabsLocation"):Connect(addLocation)
	local conn2 = CollectionService:GetInstanceRemovedSignal("PrefabsLocation"):Connect(delLocation)
	
	for _, location in CollectionService:GetTagged("PrefabsLocation") do
		task.spawn(addLocation, location)
	end
	
	local store = {}
	
	store.added = prefabAddedSignal.Event :: RBXScriptSignal<string>
	store.removed = prefabRemovedSignal.Event :: RBXScriptSignal<string>
	store.changed = prefabChangedSignal.Event :: RBXScriptSignal<string>
	
	function store:get(id: string): Instance?
		if not allPrefabs[id] then
			return nil
		end
		
		return (next(allPrefabs[id]))
	end
	
	function store:getAll(): { [string]: Instance }
		local all = {}
		for id, instances in allPrefabs do
			all[id] = (next(instances))
		end
		
		return all :: any
	end

	function store:destroy()
		conn1:Disconnect()
		conn2:Disconnect()

		for _, location in connectedLocations do
			for _, conn in location do
				conn:Disconnect()
			end
		end
	end
	
	return store
end

export type Store = typeof(PrefabStore.new())

return PrefabStore