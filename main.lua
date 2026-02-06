local api = require("api")
local auxu = {
    name = "Actually Useable X Up",
    version = "2.0",
    author = "MikeTheShadow",
    desc = "It's actually useable."
}

local blocklist = {}

local recruit_message = ""

local recruit_textfield

local recruit_button

local cancelButton

local filter_dropdown

local is_recruiting = false

local raid_manager

local dms_only

local settings

local function OnLoad()


    settings = api.GetSettings("Actually_Useable_X_Up")

    -- Initialize default settings if they don't exist
    local needs_save = false
    if settings.blocklist == nil then
        settings.blocklist = {}
        settings.hide_cancel = false
        needs_save = true
    end
    if settings.cancel_btn_x == nil then
        settings.cancel_btn_x = (api.Interface:GetScreenWidth() / 2) - 60
        needs_save = true
    end
    if settings.cancel_btn_y == nil then
        settings.cancel_btn_y = 50
        needs_save = true
    end
    if settings.recruit_text == nil then
        settings.recruit_text = ""
        needs_save = true
    end
    if settings.filter_selection == nil then
        settings.filter_selection = 1
        needs_save = true
    end
    if settings.dms_selection == nil then
        settings.dms_selection = 1
        needs_save = true
    end
    if settings.is_recruiting == nil then
        settings.is_recruiting = false
        needs_save = true
    end
    if needs_save then
        api.SaveSettings()
    end

    -- Button position
    local btn_x = settings.cancel_btn_x
    local btn_y = settings.cancel_btn_y

    -- Create draggable toggle button directly on UIParent (always visible)
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

    raid_manager = ADDON:GetContent(UIC.RAID_MANAGER)

    canvas_width = raid_manager:GetWidth()

    raid_manager:SetExtent(canvas_width,440)

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
    recruit_textfield:SetText(settings.recruit_text)
    recruit_textfield:Show(true)

    recruit_textfield:SetHandler("OnTextChanged", function()
        settings.recruit_text = recruit_textfield:GetText()
        api.SaveSettings()
    end)

    -- Recruit filtering
    filter_dropdown = api.Interface:CreateComboBox(raid_manager)
    filter_dropdown:SetExtent(100, 30)
    filter_dropdown:AddAnchor("LEFT", raid_manager, 285, 140)
    filter_dropdown.dropdownItem =  {"Equals","Contains","Starts With"}
    filter_dropdown:Select(settings.filter_selection)
    filter_dropdown:Show(true)

    -- DMs only
    dms_only = api.Interface:CreateComboBox(raid_manager)
    dms_only:SetExtent(100, 30)
    dms_only:AddAnchor("LEFT", raid_manager, 390, 140)
    dms_only.dropdownItem = {"All Chats","Whispers","Guild"}
    dms_only:Select(settings.dms_selection)
    dms_only:Show(true)

    -- Save dropdown selections when raid window closes
    raid_manager:SetHandler("OnHide", function()
        settings.filter_selection = filter_dropdown.selctedIndex
        settings.dms_selection = dms_only.selctedIndex
        api.SaveSettings()
    end)

    -- Restore recruiting state
    is_recruiting = settings.is_recruiting
    if is_recruiting then
        recruit_button:SetText("Stop Recruiting")
        cancelButton:SetText("Stop Recruiting")
        recruit_textfield:Enable(false)
        recruit_message = string.lower(recruit_textfield:GetText())
    end

    recruit_button:SetHandler("OnClick", function()
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
        raid_manager:SetExtent(canvas_width,395)
        cancelButton:Show(false)
        filter_dropdown:Show(false)
        dms_only:Show(false)
    end
end



local show_settings = true

auxu.OnLoad = OnLoad
auxu.OnUnload = OnUnload

local function ResetRecruit()
    is_recruiting = false
    recruit_button:SetText("Start Recruiting")
    recruit_textfield:Enable(true)

end

local function OnChatMessage(channelId, speakerId,_, speakerName, message)

    message = message:lower()

    filter_selection = filter_dropdown.selctedIndex

    is_null = string.find(message, recruit_message, 1, true) == nil

    if not speakerName or recruit_message == "" then
        return
    end

    if not is_recruiting then
        ResetRecruit()
        return
    end

    -- Filter check

    filter_selection = filter_dropdown.selctedIndex

    if filter_selection == 1 and message ~= recruit_message then
        return
    elseif filter_selection == 2 and string.find(message, recruit_message, 1, true) == nil then
        return
    elseif filter_selection == 3 and string.sub(message, 1, #recruit_message) ~= recruit_message then
        return
    end

    recruit_method = dms_only.selctedIndex

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