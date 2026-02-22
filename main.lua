local api = require("api")
local auxu = {
	name = "Actually Useable X Up",
	version = "3.0", -- Static Version 3.0
	author = "MikeTheShadow",
	desc = "A simple raid manager",
}

-- =========================================================
-- FILE LEVEL VARIABLES
-- =========================================================
local settings = nil
local blacklist_lookup = {}
local active_whitelist_lookup = nil

local recruit_message = ""
local is_recruiting = false

-- UI Elements
local recruit_textfield, recruit_button, filter_dropdown, chat_filter_dropdown
local raid_manager
local list_manager_canvas, active_whitelist_dropdown, open_manager_btn, invite_whitelist_btn
local canvas_width
local cancelButton
local preserve_state_checkbox

-- Scroll Window Elements
local member_scroll_wnd
local scroll_children = {}
local list_refresh_counter = 0

-- =========================================================
-- HELPER FUNCTIONS
-- =========================================================

local function FormatName(name)
	if type(name) ~= "string" or name == "" then
		return ""
	end
	return string.upper(string.sub(name, 1, 1)) .. string.lower(string.sub(name, 2))
end

local function RebuildBlacklistLookup()
	blacklist_lookup = {}
	if settings and settings.blacklist then
		for _, name in ipairs(settings.blacklist) do
			local formatted = FormatName(name)
			blacklist_lookup[formatted] = true
		end
	end
end

-- Ported from Land Demo Tracker Example
local function CreateScrollWindow(parent, ownId, index)
	local frame = parent:CreateChildWidget("emptywidget", ownId, index, true)
	frame:Show(true)

	local content = frame:CreateChildWidget("emptywidget", "content", 0, true)
	content:EnableScroll(true)
	content:Show(true)
	frame.content = content

	local scroll = W_CTRL.CreateScroll("scroll", frame)
	scroll:AddAnchor("TOPRIGHT", frame, 0, 0)
	scroll:AddAnchor("BOTTOMRIGHT", frame, 0, 0)
	scroll:AlwaysScrollShow()
	frame.scroll = scroll

	content:AddAnchor("TOPLEFT", frame, 0, 0)
	content:AddAnchor("BOTTOM", frame, 0, 0)
	content:AddAnchor("RIGHT", scroll, "LEFT", -5, 0)

	function scroll.vs:OnSliderChanged(_value)
		frame.content:ChangeChildAnchorByScrollValue("vert", _value)
		if frame.SliderChangedProc ~= nil then
			frame:SliderChangedProc(_value)
		end
	end
	scroll.vs:SetHandler("OnSliderChanged", scroll.vs.OnSliderChanged)

	function frame:SetEnable(enable)
		self:Enable(enable)
		scroll:SetEnable(enable)
	end

	function frame:ResetScroll(totalHeight)
		scroll.vs:SetMinMaxValues(0, totalHeight)
		local height = frame:GetHeight()
		if totalHeight <= height then
			scroll:SetEnable(false)
		else
			scroll:SetEnable(true)
		end
	end

	return frame
end

local function ClearScrollList()
	-- Hide AND Remove Anchors to prevent layout ghosting
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

-- =========================================================
-- INITIALIZATION
-- =========================================================

local function OnLoad()
	-- Load Settings
	settings = api.GetSettings("Actually_Useable_X_Up")

	if settings.whitelists == nil then
		settings.whitelists = {}
	end
	if settings.blacklist == nil then
		settings.blacklist = {}
	end
	if settings.blocklist ~= nil then
		settings.blocklist = nil
	end
	if settings.hide_cancel == nil then
		settings.hide_cancel = false
	end
	-- Settings persistence
	if settings.cancel_btn_x == nil then
		settings.cancel_btn_x = (api.Interface:GetScreenWidth() / 2) - 60
	end
	if settings.cancel_btn_y == nil then
		settings.cancel_btn_y = 50
	end
	if settings.recruit_text == nil then
		settings.recruit_text = ""
	end
	if settings.filter_selection == nil then
		settings.filter_selection = 1
	end
	if settings.dms_selection == nil then
		settings.dms_selection = 1
	end
	if settings.is_recruiting == nil then
		settings.is_recruiting = false
	end
	if settings.preserve_state == nil then
		settings.preserve_state = true
	end

	api.SaveSettings()
	RebuildBlacklistLookup()

	-- -----------------------------------------------------
	-- ALWAYS-VISIBLE TOGGLE BUTTON
	-- -----------------------------------------------------
	local btn_x = settings.cancel_btn_x
	local btn_y = settings.cancel_btn_y

	cancelButton = api.Interface:CreateWidget("button", "cancelAutoRaidBtn", "UIParent")
	cancelButton:SetText("Start Recruiting")
	cancelButton:SetExtent(120, 30)
	cancelButton:AddAnchor("TOPLEFT", "UIParent", btn_x, btn_y)
	api.Interface:ApplyButtonSkin(cancelButton, BUTTON_BASIC.DEFAULT)
	cancelButton:Show(true)

	function cancelButton:OnDragStart()
		cancelButton:StartMoving()
		api.Cursor:ClearCursor()
		api.Cursor:SetCursorImage(CURSOR_PATH.MOVE, 0, 0)
	end

	function cancelButton:OnDragStop()
		cancelButton:StopMovingOrSizing()
		local current_x, current_y = cancelButton:GetEffectiveOffset()
		settings.cancel_btn_x = current_x
		settings.cancel_btn_y = current_y
		api.SaveSettings()
		api.Cursor:ClearCursor()
	end

	cancelButton:SetHandler("OnDragStart", cancelButton.OnDragStart)
	cancelButton:SetHandler("OnDragStop", cancelButton.OnDragStop)
	if cancelButton.RegisterForDrag ~= nil then
		cancelButton:RegisterForDrag("LeftButton")
	end
	if cancelButton.EnableDrag ~= nil then
		cancelButton:EnableDrag(true)
	end

	-- -----------------------------------------------------
	-- RAID MANAGER UI
	-- -----------------------------------------------------
	raid_manager = ADDON:GetContent(UIC.RAID_MANAGER)
	canvas_width = raid_manager:GetWidth()
	raid_manager:SetExtent(canvas_width, 550)

	recruit_button = raid_manager:CreateChildWidget("button", "raid_setup_button", 0, true)
	recruit_button:SetExtent(300, 60)
	recruit_button:AddAnchor("LEFT", raid_manager, 20, 140)
	recruit_button:SetText("Start Recruiting")
	api.Interface:ApplyButtonSkin(recruit_button, BUTTON_BASIC.DEFAULT)

	recruit_textfield = W_CTRL.CreateEdit("recruit_message", raid_manager)
	recruit_textfield:AddAnchor("LEFT", raid_manager, 131, 140)
	recruit_textfield:SetExtent(150, 30)
	recruit_textfield:SetMaxTextLength(64)
	recruit_textfield:CreateGuideText("X CR")
	if settings.preserve_state and settings.recruit_text ~= "" then
		recruit_textfield:SetText(settings.recruit_text)
	end
	recruit_textfield:Show(true)

	recruit_textfield:SetHandler("OnTextChanged", function()
		settings.recruit_text = recruit_textfield:GetText()
		api.SaveSettings()
	end)

	filter_dropdown = api.Interface:CreateComboBox(raid_manager)
	filter_dropdown:SetExtent(100, 30)
	filter_dropdown:AddAnchor("LEFT", raid_manager, 285, 140)
	filter_dropdown.dropdownItem = { "Equals", "Contains", "Starts With" }
	filter_dropdown:Select(settings.preserve_state and settings.filter_selection or 1)
	filter_dropdown:Show(true)

	chat_filter_dropdown = api.Interface:CreateComboBox(raid_manager)
	chat_filter_dropdown:SetExtent(100, 30)
	chat_filter_dropdown:AddAnchor("LEFT", raid_manager, 390, 140)
	chat_filter_dropdown.dropdownItem = { "All Chats", "Whispers", "Guild" }
	chat_filter_dropdown:Select(settings.preserve_state and settings.dms_selection or 1)
	chat_filter_dropdown:Show(true)

	-- Preserve State checkbox
	preserve_state_checkbox = api.Interface:CreateWidget("checkbutton", "preserve_state_cb", raid_manager)
	preserve_state_checkbox:SetExtent(18, 17)
	preserve_state_checkbox:AddAnchor("LEFT", chat_filter_dropdown, "RIGHT", 10, 0)

	local cb_bg1 = preserve_state_checkbox:CreateImageDrawable("ui/button/check_button.dds", "background")
	cb_bg1:SetExtent(18, 17)
	cb_bg1:AddAnchor("CENTER", preserve_state_checkbox, 0, 0)
	cb_bg1:SetCoords(0, 0, 18, 17)
	preserve_state_checkbox:SetNormalBackground(cb_bg1)

	local cb_bg2 = preserve_state_checkbox:CreateImageDrawable("ui/button/check_button.dds", "background")
	cb_bg2:SetExtent(18, 17)
	cb_bg2:AddAnchor("CENTER", preserve_state_checkbox, 0, 0)
	cb_bg2:SetCoords(0, 0, 18, 17)
	preserve_state_checkbox:SetHighlightBackground(cb_bg2)

	local cb_bg3 = preserve_state_checkbox:CreateImageDrawable("ui/button/check_button.dds", "background")
	cb_bg3:SetExtent(18, 17)
	cb_bg3:AddAnchor("CENTER", preserve_state_checkbox, 0, 0)
	cb_bg3:SetCoords(0, 0, 18, 17)
	preserve_state_checkbox:SetPushedBackground(cb_bg3)

	local cb_bg4 = preserve_state_checkbox:CreateImageDrawable("ui/button/check_button.dds", "background")
	cb_bg4:SetExtent(18, 17)
	cb_bg4:AddAnchor("CENTER", preserve_state_checkbox, 0, 0)
	cb_bg4:SetCoords(0, 17, 18, 17)
	preserve_state_checkbox:SetDisabledBackground(cb_bg4)

	local cb_bg5 = preserve_state_checkbox:CreateImageDrawable("ui/button/check_button.dds", "background")
	cb_bg5:SetExtent(18, 17)
	cb_bg5:AddAnchor("CENTER", preserve_state_checkbox, 0, 0)
	cb_bg5:SetCoords(18, 0, 18, 17)
	preserve_state_checkbox:SetCheckedBackground(cb_bg5)

	local cb_bg6 = preserve_state_checkbox:CreateImageDrawable("ui/button/check_button.dds", "background")
	cb_bg6:SetExtent(18, 17)
	cb_bg6:AddAnchor("CENTER", preserve_state_checkbox, 0, 0)
	cb_bg6:SetCoords(18, 17, 18, 17)
	preserve_state_checkbox:SetDisabledCheckedBackground(cb_bg6)

	preserve_state_checkbox:SetChecked(settings.preserve_state)

	local preserve_label = raid_manager:CreateChildWidget("label", "preserve_state_label", 0, true)
	preserve_label:SetText("Preserve State")
	preserve_label:AddAnchor("LEFT", preserve_state_checkbox, "RIGHT", 4, 0)
	preserve_label.style:SetFontSize(12)
	preserve_label.style:SetAlign(ALIGN.LEFT)
	preserve_label.style:SetColor(0, 0.5, 0, 1)

	function preserve_state_checkbox:OnCheckChanged()
		settings.preserve_state = self:GetChecked()
		api.SaveSettings()
	end
	preserve_state_checkbox:SetHandler("OnCheckChanged", preserve_state_checkbox.OnCheckChanged)

	-- Save dropdown selections when raid window closes
	raid_manager:SetHandler("OnHide", function()
		settings.filter_selection = filter_dropdown.selctedIndex
		settings.dms_selection = chat_filter_dropdown.selctedIndex
		api.SaveSettings()
	end)

	open_manager_btn = raid_manager:CreateChildWidget("button", "open_list_manager", 0, true)
	open_manager_btn:SetExtent(140, 30)
	open_manager_btn:AddAnchor("TOPLEFT", recruit_button, "BOTTOMLEFT", 0, 10)
	open_manager_btn:SetText("List Manager")
	api.Interface:ApplyButtonSkin(open_manager_btn, BUTTON_BASIC.DEFAULT)

	invite_whitelist_btn = raid_manager:CreateChildWidget("button", "invite_whitelist_btn", 0, true)
	invite_whitelist_btn:SetExtent(140, 30)
	invite_whitelist_btn:AddAnchor("LEFT", open_manager_btn, "RIGHT", 10, 0)
	invite_whitelist_btn:SetText("Invite Whitelist")
	api.Interface:ApplyButtonSkin(invite_whitelist_btn, BUTTON_BASIC.DEFAULT)

	active_whitelist_dropdown = api.Interface:CreateComboBox(raid_manager)
	active_whitelist_dropdown:SetExtent(150, 30)
	active_whitelist_dropdown:AddAnchor("LEFT", invite_whitelist_btn, "RIGHT", 10, 0)

	local function RefreshMainDropdown()
		local items = { "Select Whitelist" }
		for k, _ in pairs(settings.whitelists) do
			table.insert(items, k)
		end
		active_whitelist_dropdown.dropdownItem = items
		active_whitelist_dropdown:Select(1)
		active_whitelist_lookup = nil
	end
	RefreshMainDropdown()

	function active_whitelist_dropdown:SelectedProc()
		local idx = active_whitelist_dropdown:GetSelectedIndex()
		local selected_name = active_whitelist_dropdown.dropdownItem[idx]

		if selected_name and selected_name ~= "Select Whitelist" then
			local source_list = settings.whitelists[selected_name]
			if source_list then
				active_whitelist_lookup = {}
				for _, name in ipairs(source_list) do
					local formatted = FormatName(name)
					active_whitelist_lookup[formatted] = true
				end
				api.Log:Info("Whitelist active: " .. selected_name)
			else
				active_whitelist_lookup = nil
			end
		else
			active_whitelist_lookup = nil
			api.Log:Info("Whitelist disabled.")
		end
	end

	invite_whitelist_btn:SetHandler("OnClick", function()
		local idx = active_whitelist_dropdown:GetSelectedIndex()
		local selected_name = active_whitelist_dropdown.dropdownItem[idx]

		if selected_name and selected_name ~= "Select Whitelist" then
			local source_list = settings.whitelists[selected_name]

			if source_list and #source_list > 0 then
				api.Log:Info("Mass inviting list: " .. selected_name)

				for _, name in ipairs(source_list) do
					local formatted = FormatName(name)
					if not blacklist_lookup[formatted] then
						api.Team:InviteToTeam(formatted, false)
					end
				end
			else
				api.Log:Error("Selected list is empty.")
			end
		else
			api.Log:Error("No whitelist selected.")
		end
	end)

	-- -----------------------------------------------------
	-- LIST MANAGER UI
	-- -----------------------------------------------------
	list_manager_canvas = api.Interface:CreateEmptyWindow("listManagerCanvas")
	list_manager_canvas:AddAnchor("CENTER", "UIParent", 0, 0)
	list_manager_canvas:SetExtent(700, 350)
	list_manager_canvas:Show(false)

	list_manager_canvas.bg = list_manager_canvas:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
	list_manager_canvas.bg:SetTextureInfo("bg_quest")
	list_manager_canvas.bg:SetColor(0, 0, 0, 0.9)
	list_manager_canvas.bg:AddAnchor("TOPLEFT", list_manager_canvas, 0, 0)
	list_manager_canvas.bg:AddAnchor("BOTTOMRIGHT", list_manager_canvas, 0, 0)

	function list_manager_canvas:OnDragStart()
		if api.Input:IsShiftKeyDown() then
			list_manager_canvas:StartMoving()
			api.Cursor:ClearCursor()
			api.Cursor:SetCursorImage(CURSOR_PATH.MOVE, 0, 0)
		end
	end
	list_manager_canvas:SetHandler("OnDragStart", list_manager_canvas.OnDragStart)

	function list_manager_canvas:OnDragStop()
		list_manager_canvas:StopMovingOrSizing()
		api.Cursor:ClearCursor()
	end
	list_manager_canvas:SetHandler("OnDragStop", list_manager_canvas.OnDragStop)
	list_manager_canvas:EnableDrag(true)

	local close_list_btn = list_manager_canvas:CreateChildWidget("button", "close_list_btn", 0, true)
	close_list_btn:AddAnchor("TOPRIGHT", list_manager_canvas, -10, 5)
	close_list_btn:SetText("X")
	api.Interface:ApplyButtonSkin(close_list_btn, BUTTON_BASIC.DEFAULT)
	close_list_btn:SetHandler("OnClick", function()
		list_manager_canvas:Show(false)
	end)

	local list_name_input = W_CTRL.CreateEdit("new_list_name", list_manager_canvas)
	list_name_input:SetExtent(130, 30)
	list_name_input:AddAnchor("TOPLEFT", list_manager_canvas, 20, 40)
	list_name_input:CreateGuideText("New List Name")

	local create_list_btn = list_manager_canvas:CreateChildWidget("button", "create_list_btn", 0, true)
	create_list_btn:SetText("Create")
	create_list_btn:AddAnchor("LEFT", list_name_input, "RIGHT", 5, 0)
	api.Interface:ApplyButtonSkin(create_list_btn, BUTTON_BASIC.DEFAULT)

	local whitelist_dropdown = api.Interface:CreateComboBox(list_manager_canvas)
	whitelist_dropdown:SetExtent(130, 30)
	whitelist_dropdown:AddAnchor("TOPLEFT", list_name_input, "BOTTOMLEFT", 0, 20)

	local delete_list_btn = list_manager_canvas:CreateChildWidget("button", "delete_list_btn", 0, true)
	delete_list_btn:SetText("Delete List")
	delete_list_btn:AddAnchor("LEFT", whitelist_dropdown, "RIGHT", 5, 0)
	api.Interface:ApplyButtonSkin(delete_list_btn, BUTTON_BASIC.DEFAULT)

	local blacklist_warning = list_manager_canvas:CreateChildWidget("label", "blacklist_warn", 0, true)
	blacklist_warning:SetExtent(200, 20)
	blacklist_warning:AddAnchor("TOPLEFT", whitelist_dropdown, "BOTTOMLEFT", 0, 5)
	blacklist_warning:SetText("You are currently editing your blacklist")
	blacklist_warning.style:SetColor(1, 0.2, 0.2, 1)
	blacklist_warning:Show(false)

	-- INPUT BOX
	local member_input = W_CTRL.CreateEdit("member_input", list_manager_canvas)
	member_input:SetExtent(250, 30)
	member_input:AddAnchor("TOPLEFT", list_manager_canvas, 260, 40)
	member_input:SetMaxTextLength(100000) -- Increased to effectively infinite
	member_input:CreateGuideText("Paste Names Here")

	local add_member_btn = list_manager_canvas:CreateChildWidget("button", "add_member_btn", 0, true)
	add_member_btn:SetText("Add")
	add_member_btn:AddAnchor("LEFT", member_input, "RIGHT", 5, 0)
	api.Interface:ApplyButtonSkin(add_member_btn, BUTTON_BASIC.DEFAULT)

	-- SCROLL WINDOW SETUP
	member_scroll_wnd = CreateScrollWindow(list_manager_canvas, "member_scroll_wnd", 0)
	member_scroll_wnd:Show(true)
	member_scroll_wnd:RemoveAllAnchors()
	member_scroll_wnd:AddAnchor("TOPLEFT", member_input, "BOTTOMLEFT", 0, 15)
	member_scroll_wnd:SetExtent(370, 250)

	-- Scroll Background
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

		if list_name == "Blacklist" then
			blacklist_warning:Show(true)
		else
			blacklist_warning:Show(false)
		end

		-- 1. SAVE SCROLL POSITION
		local oldScroll = member_scroll_wnd.scroll.vs:GetValue()

		-- 2. FORCE RESET VIEW TO TOP
		member_scroll_wnd.scroll.vs:SetValue(0)
		member_scroll_wnd.content:ChangeChildAnchorByScrollValue("vert", 0)

		-- 3. CLEAR OLD WIDGETS
		ClearScrollList()
		list_refresh_counter = list_refresh_counter + 1

		local current_list = GetListByName(list_name) or {}
		local content = member_scroll_wnd.content

		-- 4. REBUILD LIST
		local itemHeight = 45
		for i, name in ipairs(current_list) do
			local yOffset = (i - 1) * itemHeight
			local unique_id = i .. "_" .. list_refresh_counter

			-- Name Label
			local label = W_CTRL.CreateLabel("lbl_" .. unique_id, content)
			label:AddAnchor("TOPLEFT", content, 5, yOffset + 25)
			label:SetText(name)
			label.style:SetFontSize(20)
			label.style:SetAlign(ALIGN.LEFT)
			label:Show(true)
			table.insert(scroll_children, label)

			-- Individual Delete Button
			local delBtn = content:CreateChildWidget("button", "del_" .. unique_id, 0, true)
			delBtn:AddAnchor("TOPRIGHT", content, -5, yOffset + 10)
			delBtn:SetExtent(25, 20)
			delBtn:SetText("X")
			api.Interface:ApplyButtonSkin(delBtn, BUTTON_BASIC.DEFAULT)
			delBtn:Show(true)
			table.insert(scroll_children, delBtn)

			delBtn:SetHandler("OnClick", function()
				table.remove(current_list, i)
				api.SaveSettings()

				if list_name == "Blacklist" then
					RebuildBlacklistLookup()
				end

				UpdateDisplay(list_name)
			end)
		end

		-- 5. RESET RANGE AND RESTORE SCROLL
		local totalHeight = #current_list * itemHeight
		member_scroll_wnd:ResetScroll(totalHeight)

		-- Clamp old scroll to new max height
		local min, max = member_scroll_wnd.scroll.vs:GetMinMaxValues()
		if oldScroll > max then
			oldScroll = max
		end

		-- Restore visual position
		member_scroll_wnd.scroll.vs:SetValue(oldScroll)
		member_scroll_wnd.content:ChangeChildAnchorByScrollValue("vert", oldScroll)
	end

	local function RefreshManagerDropdown()
		local names = { "Blacklist" }
		for k, v in pairs(settings.whitelists) do
			table.insert(names, k)
		end
		whitelist_dropdown.dropdownItem = names
		RefreshMainDropdown()
	end
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
						local formatted = FormatName(name)
						if not exists(formatted) then
							table.insert(current_list, formatted)
						end
					end
				end
				api.SaveSettings()
				member_input:SetText("")
				UpdateDisplay(selected_list_name)
				if selected_list_name == "Blacklist" then
					RebuildBlacklistLookup()
				elseif active_whitelist_dropdown:GetSelectedIndex() > 0 then
					local active_name =
						active_whitelist_dropdown.dropdownItem[active_whitelist_dropdown:GetSelectedIndex()]
					if active_name == selected_list_name then
						active_whitelist_dropdown:SelectedProc()
					end
				end
			end
		else
			api.Log:Error("Select a list first.")
		end
	end)

	open_manager_btn:SetHandler("OnClick", function()
		list_manager_canvas:Show(not list_manager_canvas:IsVisible())
		if list_manager_canvas:IsVisible() then
			RefreshManagerDropdown()
		end
	end)

	-- Restore recruiting state
	if settings.preserve_state then
		is_recruiting = settings.is_recruiting
		if is_recruiting then
			recruit_button:SetText("Stop Recruiting")
			cancelButton:SetText("Stop Recruiting")
			recruit_textfield:Enable(false)
			recruit_message = string.lower(recruit_textfield:GetText())
		end
	end

	recruit_button:SetHandler("OnClick", function()
		if is_recruiting then
			is_recruiting = false
			recruit_button:SetText("Start Recruiting")
			cancelButton:SetText("Start Recruiting")
			recruit_textfield:Enable(true)
		elseif is_recruiting == false and #recruit_textfield:GetText() > 0 then
			is_recruiting = true
			recruit_button:SetText("Stop Recruiting")
			cancelButton:SetText("Stop Recruiting")
			recruit_textfield:Enable(false)
			recruit_message = string.lower(recruit_textfield:GetText())
			settings.last_recruit_message = recruit_message
		end
		settings.is_recruiting = is_recruiting
		api.SaveSettings()
	end)

	cancelButton:SetHandler("OnClick", function()
		if is_recruiting then
			is_recruiting = false
			recruit_button:SetText("Start Recruiting")
			cancelButton:SetText("Start Recruiting")
			recruit_textfield:Enable(true)
		else
			is_recruiting = true
			recruit_button:SetText("Stop Recruiting")
			cancelButton:SetText("Stop Recruiting")
			recruit_textfield:Enable(false)
			recruit_message = string.lower(recruit_textfield:GetText())
		end
		settings.is_recruiting = is_recruiting
		api.SaveSettings()
	end)
end

local function OnUnload()
	if recruit_button then
		recruit_button:Show(false)
		recruit_textfield:Show(false)
		raid_manager:SetExtent(canvas_width, 395)
		cancelButton:Show(false)
		filter_dropdown:Show(false)
		chat_filter_dropdown:Show(false)
		if list_manager_canvas then
			list_manager_canvas:Show(false)
		end
		if active_whitelist_dropdown then
			active_whitelist_dropdown:Show(false)
		end
		if open_manager_btn then
			open_manager_btn:Show(false)
		end
		if invite_whitelist_btn then
			invite_whitelist_btn:Show(false)
		end
		if preserve_state_checkbox then
			preserve_state_checkbox:Show(false)
		end
	end
end

auxu.OnLoad = OnLoad
auxu.OnUnload = OnUnload

local function ResetRecruit()
	is_recruiting = false
	recruit_button:SetText("Start Recruiting")
	recruit_textfield:Enable(true)
end

-- =========================================================
-- EVENT HANDLERS
-- =========================================================

local function OnChatMessage(channelId, speakerId, _, speakerName, message)
	message = message:lower()
	local filter_selection = filter_dropdown.selctedIndex
	if not speakerName or recruit_message == "" then
		return
	end

	if blacklist_lookup[FormatName(speakerName)] then
		return
	end

	if not is_recruiting then
		ResetRecruit()
		return
	end

	if active_whitelist_lookup ~= nil then
		if not active_whitelist_lookup[FormatName(speakerName)] then
			return
		end
	end

	if filter_selection == 1 and message ~= recruit_message then
		return
	elseif filter_selection == 2 and string.find(message, recruit_message, 1, true) == nil then
		return
	elseif filter_selection == 3 and string.sub(message, 1, #recruit_message) ~= recruit_message then
		return
	end

	local recruit_method = chat_filter_dropdown.selctedIndex
	if recruit_method == 1 then
		api.Log:Info(("Inviting " .. speakerName))
		api.Team:InviteToTeam(speakerName, false)
	elseif recruit_method == 2 and channelId == -3 then
		api.Log:Info(("Inviting " .. speakerName))
		api.Team:InviteToTeam(speakerName, false)
	elseif recruit_method == 3 and channelId == 7 then
		api.Log:Info(("Inviting " .. speakerName))
		api.Team:InviteToTeam(speakerName, false)
	end
end

api.On("CHAT_MESSAGE", OnChatMessage)

return auxu
