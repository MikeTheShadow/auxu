local api = require("api")
local utils = require("AUXU/utils")
local list_manager = require("AUXU/list_manager")

local auxu = {
	name = "Actually Useable X Up",
	version = "3.0",
	author = "MikeTheShadow",
	desc = "A simple raid manager",
}

-- State variables
local settings = nil
local blacklist_lookup = {}
local active_whitelist_lookup = nil
local recruit_message = ""

-- UI references
local recruit_textfield, recruit_button, filter_dropdown, chat_filter_dropdown
local raid_manager, cancelButton
local active_whitelist_dropdown, open_manager_btn, invite_whitelist_btn
local canvas_width, always_visible_checkbox, always_visible_label

-- Populates lookup table for faster chat filtering
local function RebuildBlacklistLookup()
	blacklist_lookup = {}
	if settings and settings.blacklist then
		for _, name in ipairs(settings.blacklist) do
			blacklist_lookup[utils.FormatName(name)] = true
		end
	end
end

-- Evaluates if the floating widget should be on-screen
local function UpdateFloatingButtonVisibility()
	if not cancelButton then
		return
	end
	if settings.is_recruiting then
		cancelButton:Show(true)
	else
		cancelButton:Show(settings.always_visible)
	end
end

-- Disables recruiting state and syncs buttons
local function ResetRecruit()
	settings.is_recruiting = false
	api.SaveSettings()

	recruit_button:SetText("Start Recruiting")
	if cancelButton then
		cancelButton:SetText("Start Recruiting")
	end
	recruit_textfield:Enable(true)
	UpdateFloatingButtonVisibility()
end

local function OnLoad()
	settings = api.GetSettings("AUXU")

	-- Default settings injections
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
	if settings.always_visible == nil then
		settings.always_visible = true
	end
	if settings.cancel_btn_x == nil then
		settings.cancel_btn_x = 100
	end
	if settings.cancel_btn_y == nil then
		settings.cancel_btn_y = 100
	end
	if settings.filter_selection == nil then
		settings.filter_selection = 1
	end
	if settings.dms_selection == nil then
		settings.dms_selection = 1
	end
	if settings.active_whitelist == nil then
		settings.active_whitelist = "Select Whitelist"
	end
	if settings.is_recruiting == nil then
		settings.is_recruiting = false
	end

	api.SaveSettings()
	RebuildBlacklistLookup()

	-- Floating Recruit Button Setup
	cancelButton = utils.CreateButton("UIParent", "cancelAutoRaidBtn", "Start Recruiting", 120, 30)
	cancelButton:AddAnchor("TOPLEFT", "UIParent", settings.cancel_btn_x, settings.cancel_btn_y)

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

	-- Raid Manager Panel Setup
	raid_manager = ADDON:GetContent(UIC.RAID_MANAGER)
	canvas_width = raid_manager:GetWidth()
	raid_manager:SetExtent(canvas_width, 550)

	recruit_button = utils.CreateButton(raid_manager, "raid_setup_button", "Start Recruiting", 300, 60)
	recruit_button:AddAnchor("LEFT", raid_manager, 20, 140)

	recruit_textfield = utils.CreateEditBox(raid_manager, "recruit_message", "X CR", 150, 30, 64)
	recruit_textfield:AddAnchor("LEFT", raid_manager, 131, 140)
	recruit_textfield:Show(true)

	if settings.last_recruit_message ~= nil then
		recruit_textfield:SetText(settings.last_recruit_message)
	end

	-- Chat Matching Dropdown
	filter_dropdown = utils.CreateComboBox(raid_manager, { "Equals", "Contains", "Starts With" }, 100, 30)
	filter_dropdown:AddAnchor("LEFT", raid_manager, 285, 140)
	filter_dropdown:Select(settings.filter_selection)
	function filter_dropdown:SelectedProc()
		settings.filter_selection = self:GetSelectedIndex()
		api.SaveSettings()
	end
	filter_dropdown:Show(true)

	-- Message Scope Dropdown
	chat_filter_dropdown = utils.CreateComboBox(raid_manager, { "All Chats", "Whispers", "Guild" }, 100, 30)
	chat_filter_dropdown:AddAnchor("LEFT", raid_manager, 390, 140)
	chat_filter_dropdown:Select(settings.dms_selection)
	function chat_filter_dropdown:SelectedProc()
		settings.dms_selection = self:GetSelectedIndex()
		api.SaveSettings()
	end
	chat_filter_dropdown:Show(true)

	open_manager_btn = utils.CreateButton(raid_manager, "open_list_manager", "List Manager", 140, 30)
	open_manager_btn:AddAnchor("TOPLEFT", recruit_button, "BOTTOMLEFT", 0, 25)

	invite_whitelist_btn = utils.CreateButton(raid_manager, "invite_whitelist_btn", "Invite Whitelist", 140, 30)
	invite_whitelist_btn:AddAnchor("LEFT", open_manager_btn, "RIGHT", 10, 0)

	active_whitelist_dropdown = utils.CreateComboBox(raid_manager, nil, 150, 30)
	active_whitelist_dropdown:AddAnchor("LEFT", invite_whitelist_btn, "RIGHT", 10, 0)

	always_visible_label = utils.CreateLabel(
		raid_manager,
		"always_visible_label",
		"Always Visible Recruit Button",
		12,
		ALIGN.LEFT,
		0,
		0,
		0,
		1
	)
	always_visible_label:AddAnchor("LEFT", active_whitelist_dropdown, "RIGHT", 25, 0)

	always_visible_checkbox = utils.CreateCheckbox(raid_manager, "always_visible_cb")
	always_visible_checkbox:AddAnchor("RIGHT", always_visible_label, "LEFT", -5, 0)
	always_visible_checkbox:SetChecked(settings.always_visible)

	function always_visible_checkbox:OnCheckChanged()
		settings.always_visible = self:GetChecked()
		api.SaveSettings()
		UpdateFloatingButtonVisibility()
	end
	always_visible_checkbox:SetHandler("OnCheckChanged", always_visible_checkbox.OnCheckChanged)

	-- Dynamic Main Dropdown
	local function RefreshMainDropdown()
		local items = { "Select Whitelist" }
		local target_idx = 1

		for k, _ in pairs(settings.whitelists) do
			table.insert(items, k)
		end
		active_whitelist_dropdown.dropdownItem = items

		for i, v in ipairs(items) do
			if v == settings.active_whitelist then
				target_idx = i
				break
			end
		end

		if target_idx == 1 then
			settings.active_whitelist = "Select Whitelist"
		end
		active_whitelist_dropdown:Select(target_idx)
		if active_whitelist_dropdown.SelectedProc then
			active_whitelist_dropdown:SelectedProc()
		end
	end

	-- Initialize the List Manager sub-module
	list_manager.Init(settings, {
		OnBlacklistUpdate = RebuildBlacklistLookup,
		OnWhitelistUpdate = RefreshMainDropdown,
	})

	function active_whitelist_dropdown:SelectedProc()
		local idx = self:GetSelectedIndex()
		local selected_name = self.dropdownItem[idx]

		settings.active_whitelist = selected_name
		api.SaveSettings()

		if selected_name and selected_name ~= "Select Whitelist" then
			local source_list = settings.whitelists[selected_name]
			if source_list then
				active_whitelist_lookup = {}
				for _, name in ipairs(source_list) do
					active_whitelist_lookup[utils.FormatName(name)] = true
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
					local formatted = utils.FormatName(name)
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

	open_manager_btn:SetHandler("OnClick", list_manager.Toggle)

	-- Restore active recruiting state on load
	if settings.is_recruiting and settings.last_recruit_message ~= nil and #settings.last_recruit_message > 0 then
		recruit_button:SetText("Stop Recruiting")
		cancelButton:SetText("Stop Recruiting")
		recruit_textfield:Enable(false)
		recruit_message = string.lower(settings.last_recruit_message)
	else
		settings.is_recruiting = false
	end

	UpdateFloatingButtonVisibility()

	-- Sync logic between both start/stop buttons
	local function ToggleRecruiting()
		if settings.is_recruiting then
			settings.is_recruiting = false
			recruit_button:SetText("Start Recruiting")
			cancelButton:SetText("Start Recruiting")
			recruit_textfield:Enable(true)
			UpdateFloatingButtonVisibility()
			api.SaveSettings()
		elseif settings.is_recruiting == false and #recruit_textfield:GetText() > 0 then
			settings.is_recruiting = true
			recruit_button:SetText("Stop Recruiting")
			cancelButton:SetText("Stop Recruiting")
			recruit_textfield:Enable(false)
			recruit_message = string.lower(recruit_textfield:GetText())
			settings.last_recruit_message = recruit_message
			api.SaveSettings()
			UpdateFloatingButtonVisibility()
		end
	end

	recruit_button:SetHandler("OnClick", ToggleRecruiting)
	cancelButton:SetHandler("OnClick", ToggleRecruiting)
end

local function OnUnload()
	if recruit_button then
		api.Interface:Free(recruit_button)
	end
	if recruit_textfield then
		api.Interface:Free(recruit_textfield)
	end
	if filter_dropdown then
		api.Interface:Free(filter_dropdown)
	end
	if chat_filter_dropdown then
		api.Interface:Free(chat_filter_dropdown)
	end
	if always_visible_checkbox then
		api.Interface:Free(always_visible_checkbox)
	end
	if always_visible_label then
		api.Interface:Free(always_visible_label)
	end
	if open_manager_btn then
		api.Interface:Free(open_manager_btn)
	end
	if invite_whitelist_btn then
		api.Interface:Free(invite_whitelist_btn)
	end
	if active_whitelist_dropdown then
		api.Interface:Free(active_whitelist_dropdown)
	end
	if cancelButton then
		api.Interface:Free(cancelButton)
	end

	list_manager.Free()

	if raid_manager then
		raid_manager:SetExtent(canvas_width, 395)
	end
end

local function OnChatMessage(channelId, speakerId, _, speakerName, message)
	message = message:lower()
	local filter_selection = filter_dropdown.selctedIndex

	if not speakerName or recruit_message == "" then
		return
	end
	if blacklist_lookup[utils.FormatName(speakerName)] then
		return
	end

	if not settings.is_recruiting then
		ResetRecruit()
		return
	end

	if active_whitelist_lookup ~= nil and not active_whitelist_lookup[utils.FormatName(speakerName)] then
		return
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

auxu.OnLoad = OnLoad
auxu.OnUnload = OnUnload
api.On("CHAT_MESSAGE", OnChatMessage)

return auxu
