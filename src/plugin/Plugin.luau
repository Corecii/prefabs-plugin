local Selection = game:GetService("Selection")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local CollectionService = game:GetService("CollectionService")

local Gui = require(script.Parent.Gui)
local Prefab = require(script.Parent.Prefab)
local PrefabStore = Prefab.PrefabStore

local GuiTemplates = script.Parent.GuiTemplates

local Plugin = {}

function Plugin.start(options: {
	plugin: Plugin,
})
	
	local plugin: Plugin = options.plugin
	local store = PrefabStore.new()
	
	local toolbar = plugin:CreateToolbar("Prefabs")
	
	local mainPanel = plugin:CreateDockWidgetPluginGui(
		"PrefabsMainPanel",
		DockWidgetPluginGuiInfo.new(
			Enum.InitialDockState.Right, -- InitialDockState
			true,                       -- InitialEnabled
			false,                      -- InitialEnabledShouldOverrideRestore
			300, 500,                   -- FloatingSize
			120, 90                     -- MinSize
		)
	)
	mainPanel.Title = "Prefabs"
	mainPanel.Name = "PrefabsMainPanel"
	mainPanel.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local statusPanel = plugin:CreateDockWidgetPluginGui(
		"PrefabsStatusPanel",
		DockWidgetPluginGuiInfo.new(
			Enum.InitialDockState.Left, -- InitialDockState
			true,                      -- InitialEnabled
			false,                      -- InitialEnabledShouldOverrideRestore
			200, 60,                    -- FloatingSize
			120, 60                     -- MinSize
		)
	)
	statusPanel.Title = "Prefabs Status"
	statusPanel.Name = "PrefabsStatusPanel"
	mainPanel.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	
	local mainPanelFrame = GuiTemplates.MainPanel:Clone()
	mainPanelFrame.SearchSection:Destroy()
	mainPanelFrame.ContentsSection:Destroy()
	mainPanelFrame.StatusSection:Destroy()
	
	mainPanelFrame.Size = UDim2.fromScale(1, 1)
	mainPanelFrame.Parent = mainPanel
	
	local statusSectionMain = Gui.newStatusSection()
	statusSectionMain.instance.LayoutOrder = 0
	statusSectionMain.instance.Size = UDim2.new(1, 0, 0, 62)
	statusSectionMain.instance.Parent = mainPanelFrame

	local statusSectionStandalone = Gui.newStatusSection()
	statusSectionStandalone.instance.Size = UDim2.fromScale(1, 1)
	statusSectionStandalone.instance.Parent = statusPanel
	
	local function withInstance<R...>(id: string, with: (instance: Instance) -> R..., without: (() -> R...)?): R...
		local instance = store:get(id)
		if instance then
			return with(instance)
		elseif without then
			return without()
		end
	end
	
	local function withWaypointX<T...>(name: string, fn: (T...) -> string?, ...: T...)
		local okay, newName = xpcall(fn, function(err)
			warn(`[Prefabs Plugin] {name} failed:`, err, `\n{debug.traceback(nil, 2)}`)
		end, ...)
		
		if not okay then
			ChangeHistoryService:SetWaypoint(`{name} (failed)`)
		else
			if typeof(newName) == "string" then
				ChangeHistoryService:SetWaypoint(newName)
			else
				ChangeHistoryService:SetWaypoint(name)
			end
		end
	end

	-- Allow calling without an explicit return
	local withWaypoint: typeof(withWaypointX) & <T...>(name: string, fn: (T...) -> (), T...) -> () = withWaypointX :: any
	
	local contentsSection = Gui.newContentsSection({
		store = store,
		events = {
			edit = function(id)
				withWaypoint("Edit Prefab", withInstance, id, function(instance)
					Prefab.editPrefab(instance)
					Selection:Set({ instance })
				end)
			end,
			insert = function(id)
				withWaypoint("Insert Prefab", withInstance, id, function(instance: Instance)
					local new = instance:Clone()
					
					local newParents
					if new:IsA("LayerCollector") then
						newParents = { game:GetService("StarterGui") }
					elseif new:IsA("PostEffect") or new:IsA("Sky") then
						newParents = { game:GerService("Lighting") }
					else
						newParents = { workspace }
					end
					
					local hit = workspace:Raycast(
						workspace.CurrentCamera.CFrame.Position,
						workspace.CurrentCamera.CFrame.LookVector * 500
					)

					local spawnLocation = hit and hit.Position
						or workspace.CurrentCamera.CFrame.Position + workspace.CurrentCamera.CFrame.LookVector * 500

					if new:IsA("PVInstance") then
						new:PivotTo(CFrame.new(spawnLocation))
					else
						local model = Instance.new("Model")
						new.Parent = model
						local _center, bounds = model:GetBoundingBox()

						model:PivotTo(CFrame.new(spawnLocation + Vector3.new(0, bounds.Y / 2, 0)))
					end

					local newInsts = table.create(#newParents)
					for index, newParent in newParents do
						if index ~= #newParents then
							local newInst = new:Clone()
							newInst.Parent = newParent
							newInsts[index] = newInst
						else
							new.Parent = newParent
							newInsts[index] = new
						end
					end

					Selection:Set(newInsts)

					return `Insert Prefab {instance.Name}`
				end)
			end,
			insertInto = function(id)
				withWaypoint("Insert Prefab into Selection", withInstance, id, function(instance: Instance)
					local new = instance:Clone()
					local newParents = Selection:Get()
					
					if not newParents[1] then
						if new:IsA("LayerCollector") then
							newParents = { game:GetService("StarterGui") }
						elseif new:IsA("PostEffect") or new:IsA("Sky") then
							newParents = { game:GerService("Lighting") }
						else
							newParents = { workspace }
						end
					end
					
					local hit = workspace:Raycast(
						workspace.CurrentCamera.CFrame.Position,
						workspace.CurrentCamera.CFrame.LookVector * 500
					)
					
					local spawnLocation = hit and hit.Position
						or workspace.CurrentCamera.CFrame.Position + workspace.CurrentCamera.CFrame.LookVector * 500
					
					if new:IsA("PVInstance") then
						new:PivotTo(CFrame.new(spawnLocation))
					else
						local model = Instance.new("Model")
						new.Parent = model
						local _center, bounds = model:GetBoundingBox()
						
						model:PivotTo(CFrame.new(spawnLocation + Vector3.new(0, bounds.Y / 2, 0)))
					end
					
					local newInsts = table.create(#newParents)
					for index, newParent in newParents do
						if index ~= #newParents then
							local newInst = new:Clone()
							newInst.Parent = newParent
							newInsts[index] = newInst
						else
							new.Parent = newParent
							newInsts[index] = new
						end
					end
					
					Selection:Set(newInsts)
					
					return `Insert Prefab {instance.Name} into Selection`
				end)
			end,
			updateAll = function(id)
				withWaypoint("Update All Prefab Instances", function()
					Prefab.replaceAll(id)

					return
				end)
			end,
			replaceSelection = function(id)
				withWaypoint("Replace Selection with Prefab", withInstance, id, function(instance)
					-- local keepValues = Prefab.getKeepValues(instance)
					
					local selection = Selection:Get()
					local newSelection = table.create(#selection)
					for index, item in selection do
						--local new = instance:Clone()
						--new.Parent = item.Parent
						--newSelection[index] = new
						
						--if item:IsA("PVInstance") and new:IsA("PVInstance") then
						--	if table.find(keepValues.properties, "WorldPivot") then
						--		new:PivotTo(item:GetPivot())
						--	end
						--elseif item:IsA("Attachment") and new:IsA("Attachment") then
						--	if table.find(keepValues.properties, "WorldCFrame") then
						--		new.WorldCFrame = item.WorldCFrame
						--	end
						--elseif item:IsA("GuiObject") and new:IsA("GuiObject") then
						--	if table.find(keepValues.properties, "Position") then
						--		new.Position = item.Position
						--	end
						--end
						
						--if table.find(keepValues.properties, "Name") then
						--	new.Name = item.Name
						--end
						
						--item.Parent = nil
						
						Prefab.replaceItem(item, instance, "both")
					end
					
					Selection:Set(newSelection)
					
					return `Replace Selection with Prefab of {instance.Name}`
				end)
			end,
			delete = function(id)
				withWaypoint("Delete Prefab", withInstance, id, function(instance: Instance)
					instance.Parent = nil
					return `Delete Prefab {instance.Name}`
				end)
			end,
			rename = function(id, name)
				withWaypoint("Rename Prefab", withInstance, id, function(instance: Instance)
					instance.Name = name
					return `Rename Prefab to {name}`
				end)
			end,
			selectAll = function(id)
				local newSelection = {}
				
				local instance = store:get(id)
				for _, item in CollectionService:GetTagged("Prefab") do
					if item:GetAttribute("PrefabId") == id and item ~= instance then
						table.insert(newSelection, item)
					end
				end
				
				Selection:Set(newSelection)
			end,
		},
	})
	contentsSection.instance.LayoutOrder = 20
	contentsSection.instance.Parent = mainPanelFrame

	local searchSection = Gui.newSearchSection({
		events = {
			search = function(text)
				local textFuzzy = string.gsub(
					string.lower(text),
					".",
					function(char)
						if not string.find(char, "%w") then
							return ".*%" .. char
						else
							return ".*" .. char
						end
					end
				)
				
				contentsSection.filter(function(id: string): boolean
					local name = id
					
					local inst = store:get(id)
					if inst then
						name = inst.Name
					end
					
					return string.find(string.lower(name), textFuzzy) ~= nil
				end)	
			end,
			settings = function() end,
		},
	})
	searchSection.instance.LayoutOrder = 10
	searchSection.instance.Parent = mainPanelFrame
	
	local selectionWatch = Prefab.watchSelection()
	
	local updateStatusSignal = Instance.new("BindableEvent")
	
	local buttonUpdateThis = {
		text = "Update this",
		fn = function()
			withWaypoint("Update Selection with Prefab", function()
				local selectedPrefabs = selectionWatch.getSelectedPrefabs()
				
				local selection = Selection:Get()
				for id, selectedPrefab in selectedPrefabs do
					if not selectedPrefab.canonical then
						return
					end
					
					for item, _ in selectedPrefab.selected do
						local newItem = Prefab.replaceItem(item, selectedPrefab.canonical, "both")
						
						local index = table.find(selection, item)
						if index then
							selection[index] = newItem
						end
					end
				end
				
				Selection:Set(selection)
			end)
			
			updateStatusSignal:Fire()
		end,
	}

	local buttonUpdateAll = {
		text = "Update all",
		fn = function()
			withWaypoint("Update All with Prefab", function()
				local selectedPrefabs = selectionWatch.getSelectedPrefabs()

				local selection = Selection:Get()
				for id, selectedPrefab in selectedPrefabs do
					if not selectedPrefab.canonical then
						return
					end

					for item, _ in selectedPrefab.selected do
						local map = Prefab.replaceAll(id)

						local index = table.find(selection, item)
						if index then
							selection[index] = map[item] or item
						end
					end
				end

				Selection:Set(selection)
			end)

			updateStatusSignal:Fire()
		end,
	}
	
	local buttonUpdatePrefab = {
		text = "Update prefab",
		fn = function()
			withWaypoint("Update Prefab with Selection", function()
				local selectedPrefabs = selectionWatch.getSelectedPrefabs()
				
				for id, selectedPrefab in selectedPrefabs do
					local item, _ = next(selectedPrefab.selected)
					if not item then
						continue
					end
					
					Prefab.updateCanonicalPrefabWith(item)
					task.defer(contentsSection.update, id)
				end
			end)

			updateStatusSignal:Fire(true)
		end,
	}
	
	local buttonHidePrefab = {
		text = "Quit editing",
		fn = function()
			withWaypoint("Quit Editing Prefab", function()
				local selectedPrefabs = selectionWatch.getSelectedPrefabs()
				
				local selection = game.Selection:Get()

				for id, selectedPrefab in selectedPrefabs do
					if not selectedPrefab.canonical then
						return
					end

					for item, _ in selectedPrefab.selected do
						if item == selectedPrefab.canonical then
							Prefab.storePrefab(item)
							task.defer(contentsSection.update, id)
							
							local index = table.find(selection, item)
							if index ~= nil then
								table.remove(selection, index)
							end
						end
					end
				end
				
				Selection:Set(selection)
			end)

			updateStatusSignal:Fire()
		end,
	}
	
	local buttonCreatePrefab = {
		text = "New prefab",
		fn = function()
			withWaypoint("New Prefab", function()
				if #Prefab.getPrefabLocations() == 0 then
					Prefab.createDefaultPrefabLocations()
				end
				
				local selection = Selection:Get()
				if #selection > 1 then
					warn("[Prefabs Plugin] Cannot create prefab when more than 1 item is selected.")
				elseif #selection == 0 then
					warn("[Prefabs Plugin] Cannot create prefab when no item is selected.")
				end
				
				local thing = selection[1]
				
				local lastNum
				for id, prefab in store:getAll() do
					if string.sub(prefab.Name, 1, #thing.Name) == thing.Name then
						local numSection = string.sub(prefab.Name, #thing.Name + 1)
						local numStr = numSection:match("^ (%d+)$")
						local num = numStr and tonumber(numStr)
						if not num and prefab.Name == thing.Name then
							num = 1
						end
						if num and (lastNum or 0) < num then
							lastNum = num
						end
					end
				end
				
				local name = thing.Name
				if lastNum then
					name = `{name} {lastNum + 1}`
				end
				
				Prefab.createPrefab(selection[1], name)
			end)

			updateStatusSignal:Fire(true)
		end,
	}
	
	local function updateStatus()
		local selection = Selection:Get()
		local selectedPrefabs = selectionWatch.getSelectedPrefabs()
		
		local count = 0
		for _, _ in selectedPrefabs do
			count += 1
		end
		
		local statusText = ""
		local statusType = ""
		local statusColor = Color3.fromRGB(50, 50, 50)
		local buttons = {}
		if count == 0 then
			mainPanel.Title = "Prefabs"
			
			if #selection == 1 then
				statusText = game.Selection:Get()[1].Name
			elseif #selection > 1 then
				statusText = `{#selection} items`
			end
		elseif count == 1 then
			local selectedPrefabId, selectedPrefab = next(selectedPrefabs)
			assert(selectedPrefabId and selectedPrefab)

			statusText = selectedPrefab.canonical and selectedPrefab.canonical.Name or selectedPrefabId
			
			local anyForked, anyOutdated, anyCanonical = false, false, false
			local itemCount = 0
			for item, _ in selectedPrefab.selected do
				itemCount += 1
				if selectedPrefab.canonical then
					if item == selectedPrefab.canonical then
						anyCanonical = true
					else
						local itemVersion = item:GetAttribute("PrefabVersion") or 0
						local canonicalVersion = selectedPrefab.canonical:GetAttribute("PrefabVersion") or 1
						if itemVersion < canonicalVersion then
							anyOutdated = true
						end
						if item:GetAttribute("PrefabForked") then
							anyForked = true
						end
					end
				end
			end
			
			if not selectedPrefab.canonical then
				statusText = assert(next(selectedPrefab.selected)).Name
				statusType = "Missing"
				
				mainPanel.Title = `Prefabs - {statusText} (missing)`
				statusColor = Color3.fromRGB(191, 132, 55)
				buttons = {
					buttonUpdatePrefab,
				}
				
			elseif anyForked then
				mainPanel.Title = `Prefabs - {statusText} (forked)`
				
				statusType = "Forked"
				statusColor = Color3.fromRGB(191, 132, 55)
				buttons = {
					buttonUpdatePrefab,
					buttonUpdateThis,
				}
			elseif anyOutdated then
				mainPanel.Title = `Prefabs - {statusText} (outdated)`

				statusType = "Outdated"
				statusColor = Color3.fromRGB(220, 63, 63)
				buttons = {
					buttonUpdatePrefab,
					buttonUpdateThis,
					buttonUpdateAll,
				}
			else
				statusColor = Color3.fromRGB(57, 127, 198)
				if anyCanonical then
					mainPanel.Title = `Prefabs - {statusText} (editing)`

					statusType = "Editing"
					buttons = {
						buttonHidePrefab,
						buttonUpdateAll,
					}
				else
					mainPanel.Title = `Prefabs - {statusText}`

					statusType = "Up-to-date"
					buttons = {
						buttonUpdatePrefab,
						buttonUpdateThis,
						buttonUpdateAll,
					}
				end
			end
		else
			mainPanel.Title = "Prefabs"

			statusText = "(multiple selected)"
			buttons = { buttonUpdateThis, buttonUpdateAll }
		end

		if #selection == 1 then
			table.insert(buttons, buttonCreatePrefab)
		end
		
		for _, statusSection in { statusSectionMain, statusSectionStandalone } do
			statusSection.displayName(statusText)
			statusSection.displayType(statusType)
			statusSection.displayColor(statusColor)
			statusSection.displayButtons(buttons)
		end
	end
	
	local function updateSelection()
		local selection = Selection:Get()
		if #selection > 100 then
			selection = table.move(selection, 1, 100, 1, {})
		end

		selectionWatch.update(selection)

		updateStatus()
	end
	
	Selection.SelectionChanged:Connect(updateSelection)
	
	selectionWatch.updated:Connect(updateStatus)
	
	updateStatusSignal.Event:Connect(function(hardUpdate: boolean?)
		if hardUpdate then
			updateSelection()
		else
			updateStatus()
		end
	end)
	
	task.spawn(updateStatus)
	
	local toggleMainPanel = toolbar:CreateButton(
		"Prefabs",
		"Toggle the Prefabs panel",
		""
	)
	toggleMainPanel.Click:Connect(function()
		mainPanel.Enabled = not mainPanel.Enabled
	end)
	mainPanel:GetPropertyChangedSignal("Enabled"):Connect(function()
		toggleMainPanel:SetActive(mainPanel.Enabled)
	end)
	toggleMainPanel:SetActive(mainPanel.Enabled)
	
	local toggleStatusPanel = toolbar:CreateButton(
		"Prefab Status",
		"Toggle the Prefabs Status panel",
		""
	)
	toggleStatusPanel.Click:Connect(function()
		statusPanel.Enabled = not statusPanel.Enabled
	end)
	statusPanel:GetPropertyChangedSignal("Enabled"):Connect(function()
		toggleStatusPanel:SetActive(statusPanel.Enabled)
		statusSectionMain.instance.Visible = not statusPanel.Enabled
	end)
	toggleStatusPanel:SetActive(statusPanel.Enabled)
	statusSectionMain.instance.Visible = not statusPanel.Enabled
	
	local createPrefabButton = toolbar:CreateButton(
		"Create Prefab",
		"Create a prefab from your selection",
		""
	)
	createPrefabButton.Click:Connect(function()
		buttonCreatePrefab.fn()
	end)
	
	local createManyPrefabsButton = toolbar:CreateButton(
		"Create Many Prefabs",
		"Create a prefab for every selected item",
		""
	)
	createManyPrefabsButton.Click:Connect(function()
		withWaypoint("Create Many Prefabs", function()
			local selection = Selection:Get()
			for _, item in selection do
				Prefab.createPrefab(item)
			end
		end)
	end)
	
	plugin:CreatePluginAction(
		"PrefabsUpdateSelection",
		"Update Selection from Prefab",
		"Update the selected prefab-linked instances with the new version of the prefab",
		"",
		true
	).Triggered:Connect(buttonUpdateThis.fn)
	
	plugin:CreatePluginAction(
		"PrefabsUpdatePrefab",
		"Update Prefab from Selection",
		"Update the prefab linked to the selected instances using the instances as the new version",
		"",
		true
	).Triggered:Connect(buttonUpdatePrefab.fn)
	
	plugin:CreatePluginAction(
		"PrefabHidePrefab",
		"Quit Editing Prefab",
		"Places the selected prefabs back in the Prefabs folder",
		"",
		true
	).Triggered:Connect(buttonHidePrefab.fn)
end

return Plugin