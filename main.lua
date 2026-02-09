local api = require("api")
local auxu = {
	name = "Actually Useable X Up",
	version = "3.0",
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
local raid_manager, RecruitCanvas
local list_manager_canvas, active_whitelist_dropdown, open_manager_btn, invite_whitelist_btn
local canvas_width

-- =========================================================
-- HELPER FUNCTIONS
-- =========================================================

local function FormatName(name)
	if type(name) ~= "string" or name == "" then
		return ""
	end
	-- Capitalize first letter, lowercase the rest
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

-- =========================================================
-- INITIALIZATION
-- =========================================================

local function OnLoad()
	-- Load Settings
	settings = api.GetSettings("AUXU")

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

	api.SaveSettings()

	-- Build Lookup Table for O(1) checks
	RebuildBlacklistLookup()

	-- -----------------------------------------------------
	-- RECRUIT CANVAS UI
	-- -----------------------------------------------------
	RecruitCanvas = api.Interface:CreateEmptyWindow("recruitWindow")
	RecruitCanvas:AddAnchor("CENTER", "UIParent", 0, 50)
	RecruitCanvas:SetExtent(200, 100)
	RecruitCanvas:Show(false)

	RecruitCanvas.bg = RecruitCanvas:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
	RecruitCanvas.bg:SetTextureInfo("bg_quest")
	RecruitCanvas.bg:SetColor(0, 0, 0, 0.5)
	RecruitCanvas.bg:AddAnchor("TOPLEFT", RecruitCanvas, 0, 0)
	RecruitCanvas.bg:AddAnchor("BOTTOMRIGHT", RecruitCanvas, 0, 0)

	local cancelButton = RecruitCanvas:CreateChildWidget("button", "cancel_x", 0, true)
	cancelButton:SetText("Cancel Auto Raid")
	cancelButton:AddAnchor("TOPLEFT", RecruitCanvas, "TOPLEFT", 37, 34)
	api.Interface:ApplyButtonSkin(cancelButton, BUTTON_BASIC.DEFAULT)

	function RecruitCanvas:OnDragStart()
		if api.Input:IsShiftKeyDown() then
			RecruitCanvas:StartMoving()
			api.Cursor:ClearCursor()
			api.Cursor:SetCursorImage(CURSOR_PATH.MOVE, 0, 0)
		end
	end
	RecruitCanvas:SetHandler("OnDragStart", RecruitCanvas.OnDragStart)

	function RecruitCanvas:OnDragStop()
		RecruitCanvas:StopMovingOrSizing()
		api.Cursor:ClearCursor()
	end
	RecruitCanvas:SetHandler("OnDragStop", RecruitCanvas.OnDragStop)
	RecruitCanvas:EnableDrag(true)

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
	recruit_textfield:Show(true)

	if settings.last_recruit_message ~= nil then
		recruit_textfield:SetText(settings.last_recruit_message)
	end

	filter_dropdown = api.Interface:CreateComboBox(raid_manager)
	filter_dropdown:SetExtent(100, 30)
	filter_dropdown:AddAnchor("LEFT", raid_manager, 285, 140)
	filter_dropdown.dropdownItem = { "Equals", "Contains", "Starts With" }
	filter_dropdown:Select(1)
	filter_dropdown:Show(true)

	chat_filter_dropdown = api.Interface:CreateComboBox(raid_manager)
	chat_filter_dropdown:SetExtent(100, 30)
	chat_filter_dropdown:AddAnchor("LEFT", raid_manager, 390, 140)
	chat_filter_dropdown.dropdownItem = { "All Chats", "Whispers", "Guild" }
	chat_filter_dropdown:Select(1)
	chat_filter_dropdown:Show(true)

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
	delete_list_btn:SetText("Delete")
	delete_list_btn:AddAnchor("LEFT", whitelist_dropdown, "RIGHT", 5, 0)
	api.Interface:ApplyButtonSkin(delete_list_btn, BUTTON_BASIC.DEFAULT)

	local blacklist_warning = list_manager_canvas:CreateChildWidget("label", "blacklist_warn", 0, true)
	blacklist_warning:SetExtent(200, 20)
	blacklist_warning:AddAnchor("TOPLEFT", whitelist_dropdown, "BOTTOMLEFT", 0, 5)
	blacklist_warning:SetText("You are currently editing your blacklist")
	blacklist_warning.style:SetColor(1, 0.2, 0.2, 1)
	blacklist_warning:Show(false)

	local member_input = W_CTRL.CreateEdit("member_input", list_manager_canvas)
	member_input:SetExtent(130, 30)
	member_input:AddAnchor("TOPLEFT", list_manager_canvas, 260, 40)
	member_input:CreateGuideText("Name1, Name2")

	local add_member_btn = list_manager_canvas:CreateChildWidget("button", "add_member_btn", 0, true)
	add_member_btn:SetText("Add")
	add_member_btn:AddAnchor("LEFT", member_input, "RIGHT", 5, 0)
	api.Interface:ApplyButtonSkin(add_member_btn, BUTTON_BASIC.DEFAULT)

	local remove_member_btn = list_manager_canvas:CreateChildWidget("button", "remove_member_btn", 0, true)
	remove_member_btn:SetText("Remove")
	remove_member_btn:AddAnchor("LEFT", add_member_btn, "RIGHT", 5, 0)
	api.Interface:ApplyButtonSkin(remove_member_btn, BUTTON_BASIC.DEFAULT)

	local scroll_win = list_manager_canvas:CreateChildWidget("emptywidget", "scroll_win", 0, true)
	scroll_win:SetExtent(240, 210)
	scroll_win:AddAnchor("TOPLEFT", member_input, "BOTTOMLEFT", 0, 15)

	local scroll_bg = scroll_win:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
	scroll_bg:SetTextureInfo("bg_quest")
	scroll_bg:SetColor(0, 0, 0, 0.5)
	scroll_bg:AddAnchor("TOPLEFT", scroll_win, 0, 0)
	scroll_bg:AddAnchor("BOTTOMRIGHT", scroll_win, 0, 0)

	local display_label = scroll_win:CreateChildWidget("label", "display_label", 0, true)
	display_label:SetExtent(230, 210)
	display_label:AddAnchor("TOPLEFT", scroll_win, 5, 5)
	display_label:SetText("Select a list to view members.")
	display_label.style:SetAlign(ALIGN.TOP_LEFT)

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
		local current_list = GetListByName(list_name) or {}
		local display_str = table.concat(current_list, ", ")
		display_label:SetText(display_str)
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
			display_label:SetText("")
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

	remove_member_btn:SetHandler("OnClick", function()
		local idx = whitelist_dropdown:GetSelectedIndex()
		local list_names = whitelist_dropdown.dropdownItem
		if idx > 0 and list_names[idx] then
			local selected_list_name = list_names[idx]
			local raw_text = member_input:GetText()
			if raw_text and raw_text ~= "" then
				local current_list = GetListByName(selected_list_name)
				for name_to_remove in string.gmatch(raw_text, "([^,]+)") do
					name_to_remove = name_to_remove:match("^%s*(.-)%s*$")
					if name_to_remove ~= "" then
						local formatted = FormatName(name_to_remove)
						for i = #current_list, 1, -1 do
							if current_list[i] == formatted then
								table.remove(current_list, i)
							end
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

	recruit_button:SetHandler("OnClick", function()
		if is_recruiting then
			is_recruiting = false
			recruit_button:SetText("Start Recruiting")
			recruit_textfield:Enable(true)
			RecruitCanvas:Show(false)
		elseif is_recruiting == false and #recruit_textfield:GetText() > 0 then
			is_recruiting = true
			recruit_button:SetText("Stop Recruiting")
			recruit_textfield:Enable(false)
			recruit_message = string.lower(recruit_textfield:GetText())
			RecruitCanvas:Show(true)
			settings.last_recruit_message = recruit_message
			api.SaveSettings()
		end
	end)

	cancelButton:SetHandler("OnClick", function()
		if is_recruiting then
			is_recruiting = false
			recruit_button:SetText("Start Recruiting")
			recruit_textfield:Enable(true)
			RecruitCanvas:Show(false)
		else
			is_recruiting = true
			recruit_button:SetText("Stop Recruiting")
			recruit_textfield:Enable(false)
			recruit_message = string.lower(recruit_textfield:GetText())
			RecruitCanvas:Show(true)
		end
	end)
end

local function OnUnload()
	if recruit_button then
		recruit_button:Show(false)
		recruit_textfield:Show(false)
		raid_manager:SetExtent(canvas_width, 395)
		RecruitCanvas:Show(false)
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
