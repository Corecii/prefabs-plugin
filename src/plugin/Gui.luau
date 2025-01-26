
local GuiTemplates = script.Parent.GuiTemplates

local Prefab = require(script.Parent.Prefab)

type Store = Prefab.Store

local Gui = {}

function Gui.newStatusSection()
	local statusSection = GuiTemplates.StatusPanel.StatusSection:Clone()
	
	local buttonBase = statusSection.StatusSectionButtons.CreatePrefabButton:Clone()
	
	for _, child in statusSection.StatusSectionButtons:GetChildren() do
		if child:IsA("ImageButton") then
			child:Destroy()
		end
	end
	
	local result = {}
	
	result.instance = statusSection

	local buttons: { { gui: Instance & any, fn: () -> ()? } } = {}
	function result.displayButtons(newButtons: { { text: string, fn: () -> () } })
		for index = 1, math.max(#buttons, #newButtons) do
			if not newButtons[index] then
				buttons[index].gui:Destroy()
				buttons[index] = nil
			else
				if not buttons[index] then
					local buttonTbl = {}
					
					local buttonGui = buttonBase:Clone()
					buttonGui.LayoutOrder = index
					buttonGui.MouseButton1Click:Connect(function()
						local fn = (buttonTbl :: typeof(buttons[1])).fn
						if fn then
							fn()
						end
					end)
					
					buttonTbl.gui = buttonGui
					buttons[index] = buttonTbl :: any
				end
				
				buttons[index].fn = newButtons[index].fn
				buttons[index].gui.TextLabel.Text = newButtons[index].text
				buttons[index].gui.Parent = statusSection.StatusSectionButtons
			end
		end
	end

	function result.displayName(name: string)
		statusSection.StatusSectionText.StatusName.StatusTextLabel.Text = name
	end
	
	function result.displayType(text: string)
		statusSection.StatusSectionText.StatusType.TextLabel.Text = text
		statusSection.StatusSectionText.StatusType.Visible = text ~= ""
	end
	
	function result.displayColor(color: Color3)
		statusSection.BackgroundColor3 = color
	end
	
	return result
end

function Gui.newContentsSection(options: {
	store: Store,
	events: {
		insert: (id: string) -> (),
		insertInto: (id: string) -> (),
		edit: (id: string) -> (),
		updateAll: (id: string) -> (),
		replaceSelection: (id: string) -> (),
		delete: (id: string) -> (),
		rename: (id: string, name: string) -> (),
		selectAll: (id: string) -> (),
	}
})
	local store = options.store
	
	local contentsSection = GuiTemplates.MainPanel.ContentsSection:Clone()
	
	local listItemBase = contentsSection.ContentsList.ContentsListItem:Clone()
	contentsSection.ContentsList.ContentsListItem:Destroy()
	
	contentsSection.ContentsList.Visible = true
	contentsSection.ContentsGrid.Visible = false
	
	local currentFilter = function(id: string)
		return true
	end
	
	local itemGuis: { [string]: typeof(listItemBase) } = {}
	
	local function updateGui(id: string)
		local gui = itemGuis[id]
		if not gui or not gui.Parent then
			return
		end
		
		local name = id
		
		local instance = store:get(id)
		if instance then
			name = instance.Name
		end
		
		gui.Name = name
		
		gui.ContentsListItemDetails.TextLabel.Text = name
		gui.ContentsListItemDetails.DotIcon.Visible = false
		
		local previewFrame = gui.ContentsListItemDetails.Icon.ViewportFrame

		previewFrame.Preview:ClearAllChildren()
		
		if instance then
			local okay, err = (pcall :: any)(function()
				if #instance:GetDescendants() > 200 then
					return
				end
				
				if instance:IsA("LayerCollector") or instance:IsA("GuiObject") then
					local preview
					if instance:IsA("GuiObject") then
						preview = instance:Clone()
					else
						preview = Instance.new("Frame")
						preview.BackgroundTransparency = 1
						preview.Size = UDim2.fromOffset(720, 720)
						for _, child in instance:GetChildren() do
							child:Clone().Parent = preview
						end
					end
					
					previewFrame.UIScale.Scale = 1
					preview.Parent = previewFrame.Preview
					
					local sizeScaleVec = gui.ContentsListItemDetails.Icon.AbsoluteSize / preview.AbsoluteSize
					local sizeScale = math.min(sizeScaleVec.X, sizeScaleVec.Y)
					previewFrame.UIScale.Scale = sizeScale
				elseif instance:IsA("PVInstance") or instance:IsA("Folder") then
					local preview = Instance.new("Model");
					(instance:Clone() :: Model).Parent = preview
					preview:PivotTo(CFrame.new(Vector3.zero))
					
					for _, instance in preview:GetDescendants() do
						if instance:IsA("LuaSourceContainer") then
							instance:Destroy()
						else
							for _, tag in instance:GetTags() do
								instance:RemoveTag(tag)
							end
							for attribute, _ in instance:GetAttributes() do
								instance:SetAttribute(attribute, nil)
							end
						end
					end
					
					preview.Parent = previewFrame.Preview
					
					local center, bounds = preview:GetBoundingBox()
					
					local zoom = bounds.Magnitude * 0.3
					
					previewFrame.Camera.CFrame =
						CFrame.new(center.Position + Vector3.new(-zoom, zoom, -zoom))
						* CFrame.Angles(0, math.rad(-135), 0)
						* CFrame.Angles(math.rad(-45), 0, 0)
					previewFrame.CurrentCamera = previewFrame.Camera
				end
			end)
			if not okay then
				warn("[Prefabs Plugin] Preview icon generation failed:", err)
			end
		end
	end
	
	local function addItem(id: string)
		local gui = listItemBase:Clone()
		itemGuis[id] = gui
		
		gui.Parent = contentsSection.ContentsList
		
		updateGui(id)
		
		gui.Visible = currentFilter(id)
		
		gui.ContentsListItemButtons.EditPrefabButton.MouseButton1Click:Connect(function()
			options.events.edit(id)
		end)
		gui.ContentsListItemButtons.InsertPrefabButton.MouseButton1Click:Connect(function()
			options.events.insert(id)
		end)
		gui.ContentsListItemButtons.InsertIntoPrefabButton.MouseButton1Click:Connect(function()
			options.events.insertInto(id)
		end)
		gui.ContentsListItemButtons.UpdateAllButton.MouseButton1Click:Connect(function()
			options.events.updateAll(id)
		end)
		gui.ContentsListItemButtons.ReplaceSelectionButton.MouseButton1Click:Connect(function()
			options.events.replaceSelection(id)
		end)
		gui.ContentsListItemButtons.DeleteButton.MouseButton1Click:Connect(function()
			options.events.delete(id)
		end)
		gui.ContentsListItemButtons.SelectAllButton.MouseButton1Click:Connect(function()
			options.events.selectAll(id)
		end)
		
		local function rename()
			gui.ContentsListItemDetails.TextLabel.Interactable = true
			gui.ContentsListItemDetails.TextLabel.TextEditable = true
			gui.ContentsListItemDetails.TextLabel:CaptureFocus()
		end
		gui.ContentsListItemButtons.RenameButton.MouseButton1Click:Connect(function()
			rename()
		end)
		
		local lastClick = os.clock()
		gui.MouseButton1Click:Connect(function()
			gui.ContentsListItemButtons.Visible = not gui.ContentsListItemButtons.Visible
			
			if os.clock() - lastClick < 0.5 then
				rename()
			end
		end)
		
		gui.ContentsListItemDetails.TextLabel.FocusLost:Connect(function(enterPressed)
			if enterPressed then
				options.events.rename(id, gui.ContentsListItemDetails.TextLabel.Text)
				
				updateGui(id)
			else
				local name = id

				local instance = store:get(id)
				if instance then
					name = instance.Name
				end
				
				gui.ContentsListItemDetails.TextLabel.Text = name
			end
			
			gui.ContentsListItemDetails.TextLabel.Interactable = false
			gui.ContentsListItemDetails.TextLabel.TextEditable = false
		end)
		
		gui.ContentsListItemButtons.Visible = false
	end
	
	local function delItem(id: string)
		if not itemGuis[id] then
			return
		end
		
		itemGuis[id]:Destroy()
	end
	
	store.added:Connect(addItem)
	store.removed:Connect(delItem)
	store.changed:Connect(updateGui)
	
	for id, _ in store:getAll() do
		task.spawn(addItem, id)
	end
	
	local result = {}
	
	result.instance = contentsSection
	
	function result.filter(fn: (id: string) -> boolean)
		currentFilter = fn
		
		for id, gui in itemGuis do
			gui.Visible = fn(id)
		end
	end
	
	function result.update(id: string)
		updateGui(id)
	end
	
	return result
end

function Gui.newSearchSection(options: {
	events: {
		settings: () -> (),
		search: (search: string) -> (),
	},
})
	local searchSection = GuiTemplates.MainPanel.SearchSection:Clone()
	
	searchSection.FilterButton.Visible = false
	searchSection.SettingsButton.Visible = false
	
	searchSection.SettingsButton.MouseButton1Click:Connect(function()
		options.events.settings()
	end)
	
	searchSection.Search.SearchTextBox:GetPropertyChangedSignal("Text"):Connect(function()
		options.events.search(searchSection.Search.SearchTextBox.Text)
	end)
	
	local result = {}
	
	result.instance = searchSection
	
	return result
end

return Gui