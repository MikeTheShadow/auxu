local api = require("api")
local utils = require("AUXU/utils")

local list_manager = {}
local canvas
local scroll_children = {}
local list_refresh_counter = 0

local function ClearScrollList()
	for _, widget in ipairs(scroll_children) do
		if widget then
			if widget.Show then
				widget:Show(false)
			end
			if widget.RemoveAllAnchors then
				widget:RemoveAllAnchors()
			end
		end
	end
	scroll_children = {}
end

function list_manager.Init(settings, callbacks)
	canvas = api.Interface:CreateEmptyWindow("listManagerCanvas")
	canvas:AddAnchor("CENTER", "UIParent", 0, 0)
	canvas:SetExtent(700, 350)
	canvas:Show(false)

	canvas.bg = canvas:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
	canvas.bg:SetTextureInfo("bg_quest")
	canvas.bg:SetColor(0, 0, 0, 0.9)
	canvas.bg:AddAnchor("TOPLEFT", canvas, 0, 0)
	canvas.bg:AddAnchor("BOTTOMRIGHT", canvas, 0, 0)

	function canvas:OnDragStart()
		if api.Input:IsShiftKeyDown() then
			canvas:StartMoving()
			api.Cursor:ClearCursor()
			api.Cursor:SetCursorImage(CURSOR_PATH.MOVE, 0, 0)
		end
	end
	canvas:SetHandler("OnDragStart", canvas.OnDragStart)

	function canvas:OnDragStop()
		canvas:StopMovingOrSizing()
		api.Cursor:ClearCursor()
	end
	canvas:SetHandler("OnDragStop", canvas.OnDragStop)
	canvas:EnableDrag(true)

	local close_list_btn = utils.CreateButton(canvas, "close_list_btn", "X")
	close_list_btn:AddAnchor("TOPRIGHT", canvas, -10, 5)
	close_list_btn:SetHandler("OnClick", function()
		canvas:Show(false)
	end)

	local list_name_input = utils.CreateEditBox(canvas, "new_list_name", "New List Name", 130, 30)
	list_name_input:AddAnchor("TOPLEFT", canvas, 20, 40)

	local create_list_btn = utils.CreateButton(canvas, "create_list_btn", "Create")
	create_list_btn:AddAnchor("LEFT", list_name_input, "RIGHT", 5, 0)

	local whitelist_dropdown = utils.CreateComboBox(canvas, nil, 130, 30)
	whitelist_dropdown:AddAnchor("TOPLEFT", list_name_input, "BOTTOMLEFT", 0, 20)

	local delete_list_btn = utils.CreateButton(canvas, "delete_list_btn", "Delete List")
	delete_list_btn:AddAnchor("LEFT", whitelist_dropdown, "RIGHT", 5, 0)

	local blacklist_warning = utils.CreateLabel(
		canvas,
		"blacklist_warn",
		"You are currently editing your blacklist",
		nil,
		nil,
		1,
		0.2,
		0.2,
		1
	)
	blacklist_warning:SetExtent(200, 20)
	blacklist_warning:AddAnchor("TOPLEFT", whitelist_dropdown, "BOTTOMLEFT", 0, 5)
	blacklist_warning:Show(false)

	local member_input = utils.CreateEditBox(canvas, "member_input", "Paste Names Here", 250, 30, 100000)
	member_input:AddAnchor("TOPLEFT", canvas, 260, 40)

	local add_member_btn = utils.CreateButton(canvas, "add_member_btn", "Add")
	add_member_btn:AddAnchor("LEFT", member_input, "RIGHT", 5, 0)

	local member_scroll_wnd = utils.CreateScrollWindow(canvas, "member_scroll_wnd", 0)
	member_scroll_wnd:Show(true)
	member_scroll_wnd:RemoveAllAnchors()
	member_scroll_wnd:AddAnchor("TOPLEFT", member_input, "BOTTOMLEFT", 0, 15)
	member_scroll_wnd:SetExtent(370, 250)

	local scroll_bg = member_scroll_wnd:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
	scroll_bg:SetTextureInfo("bg_quest")
	scroll_bg:SetColor(0, 0, 0, 0.5)
	scroll_bg:AddAnchor("TOPLEFT", member_scroll_wnd, 0, 0)
	scroll_bg:AddAnchor("BOTTOMRIGHT", member_scroll_wnd, 0, 0)

	local function GetListByName(name)
		if name == "Blacklist" then
			return settings.blacklist
		else
			return settings.whitelists[name]
		end
	end

	local function UpdateDisplay(list_name)
		if not list_name or list_name == "" then
			return
		end

		blacklist_warning:Show(list_name == "Blacklist")

		local oldScroll = member_scroll_wnd.scroll.vs:GetValue()
		member_scroll_wnd.scroll.vs:SetValue(0)
		member_scroll_wnd.content:ChangeChildAnchorByScrollValue("vert", 0)

		ClearScrollList()
		list_refresh_counter = list_refresh_counter + 1

		local current_list = GetListByName(list_name) or {}
		local content = member_scroll_wnd.content
		local itemHeight = 45

		for i, name in ipairs(current_list) do
			local yOffset = (i - 1) * itemHeight
			local unique_id = i .. "_" .. list_refresh_counter

			local label = utils.CreateLabel(content, "lbl_" .. unique_id, name, 20, ALIGN.LEFT)
			label:AddAnchor("TOPLEFT", content, 5, yOffset + 25)
			label:Show(true)
			table.insert(scroll_children, label)

			local delBtn = utils.CreateButton(content, "del_" .. unique_id, "X", 25, 20)
			delBtn:AddAnchor("TOPRIGHT", content, -5, yOffset + 10)
			delBtn:Show(true)
			table.insert(scroll_children, delBtn)

			delBtn:SetHandler("OnClick", function()
				table.remove(current_list, i)
				api.SaveSettings()
				if list_name == "Blacklist" and callbacks.OnBlacklistUpdate then
					callbacks.OnBlacklistUpdate()
				end
				UpdateDisplay(list_name)
			end)
		end

		local totalHeight = #current_list * itemHeight
		member_scroll_wnd:ResetScroll(totalHeight)

		local min, max = member_scroll_wnd.scroll.vs:GetMinMaxValues()
		if oldScroll > max then
			oldScroll = max
		end
		member_scroll_wnd.scroll.vs:SetValue(oldScroll)
		member_scroll_wnd.content:ChangeChildAnchorByScrollValue("vert", oldScroll)
	end

	local function RefreshManagerDropdown()
		local names = { "Blacklist" }
		for k, v in pairs(settings.whitelists) do
			table.insert(names, k)
		end
		whitelist_dropdown.dropdownItem = names
		if callbacks.OnWhitelistUpdate then
			callbacks.OnWhitelistUpdate()
		end
	end
	list_manager.RefreshManagerDropdown = RefreshManagerDropdown
	RefreshManagerDropdown()

	function whitelist_dropdown:SelectedProc()
		local idx = whitelist_dropdown:GetSelectedIndex()
		local list_names = whitelist_dropdown.dropdownItem
		if idx > 0 and list_names[idx] then
			UpdateDisplay(list_names[idx])
		end
	end

	create_list_btn:SetHandler("OnClick", function()
		local name = list_name_input:GetText()
		if name and name ~= "" then
			if name:lower() == "blacklist" then
				api.Log:Error("Cannot create a list named Blacklist.")
				return
			end
			if settings.whitelists[name] == nil then
				settings.whitelists[name] = {}
				api.SaveSettings()
				RefreshManagerDropdown()
				list_name_input:SetText("")
				api.Log:Info("Created list: " .. name)
			else
				api.Log:Info("List already exists.")
			end
		end
	end)

	delete_list_btn:SetHandler("OnClick", function()
		local idx = whitelist_dropdown:GetSelectedIndex()
		local list_names = whitelist_dropdown.dropdownItem
		if idx > 0 and list_names[idx] then
			local target = list_names[idx]
			if target == "Blacklist" then
				api.Log:Error("The Blacklist cannot be deleted.")
				return
			end
			settings.whitelists[target] = nil

			-- Clean up main dropdown state if they deleted their active whitelist
			if settings.active_whitelist == target then
				settings.active_whitelist = "Select Whitelist"
			end

			api.SaveSettings()
			RefreshManagerDropdown()
			ClearScrollList()
			blacklist_warning:Show(false)
			api.Log:Info("Deleted list: " .. target)
		end
	end)

	add_member_btn:SetHandler("OnClick", function()
		local idx = whitelist_dropdown:GetSelectedIndex()
		local list_names = whitelist_dropdown.dropdownItem
		if idx > 0 and list_names[idx] then
			local selected_list_name = list_names[idx]
			local raw_text = member_input:GetText()
			if raw_text and raw_text ~= "" then
				local current_list = GetListByName(selected_list_name)
				local function exists(val)
					for _, v in ipairs(current_list) do
						if v == val then
							return true
						end
					end
					return false
				end

				for name in string.gmatch(raw_text, "([^,]+)") do
					name = name:match("^%s*(.-)%s*$")
					if name ~= "" then
						local formatted = utils.FormatName(name)
						if not exists(formatted) then
							table.insert(current_list, formatted)
						end
					end
				end
				api.SaveSettings()
				member_input:SetText("")
				UpdateDisplay(selected_list_name)

				if selected_list_name == "Blacklist" and callbacks.OnBlacklistUpdate then
					callbacks.OnBlacklistUpdate()
				elseif callbacks.OnWhitelistUpdate then
					callbacks.OnWhitelistUpdate()
				end
			end
		else
			api.Log:Error("Select a list first.")
		end
	end)
end

function list_manager.Toggle()
	if canvas then
		canvas:Show(not canvas:IsVisible())
		if canvas:IsVisible() and list_manager.RefreshManagerDropdown then
			list_manager.RefreshManagerDropdown()
		end
	end
end

function list_manager.Free()
	if canvas then
		api.Interface:Free(canvas)
	end
end

return list_manager
