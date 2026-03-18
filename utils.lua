local api = require("api")
local utils = {}

-- Standardizes names for consistent lookup (e.g. "mike" -> "Mike")
function utils.FormatName(name)
	if type(name) ~= "string" or name == "" then
		return ""
	end
	return string.upper(string.sub(name, 1, 1)) .. string.lower(string.sub(name, 2))
end

-- UI Element Wrappers
function utils.CreateButton(parent, id, text, width, height)
	local btn
	if type(parent) == "string" then
		btn = api.Interface:CreateWidget("button", id, parent)
	else
		btn = parent:CreateChildWidget("button", id, 0, true)
	end
	btn:SetText(text)
	if width and height then
		btn:SetExtent(width, height)
	end
	api.Interface:ApplyButtonSkin(btn, BUTTON_BASIC.DEFAULT)
	return btn
end

-- Checkbox with restored ArcheAge background state logic
function utils.CreateCheckbox(parent, id)
	local cb = api.Interface:CreateWidget("checkbutton", id, parent)
	cb:SetExtent(18, 17)

	local function SetBG(state, x, y)
		local bg = cb:CreateImageDrawable("ui/button/check_button.dds", "background")
		bg:SetExtent(18, 17)
		bg:AddAnchor("CENTER", cb, 0, 0)
		bg:SetCoords(x, y, 18, 17)

		if state == "normal" then
			cb:SetNormalBackground(bg)
		elseif state == "highlight" then
			cb:SetHighlightBackground(bg)
		elseif state == "pushed" then
			cb:SetPushedBackground(bg)
		elseif state == "disabled" then
			cb:SetDisabledBackground(bg)
		elseif state == "checked" then
			cb:SetCheckedBackground(bg)
		elseif state == "disabledChecked" then
			cb:SetDisabledCheckedBackground(bg)
		end
	end

	SetBG("normal", 0, 0)
	SetBG("highlight", 0, 0)
	SetBG("pushed", 0, 0)
	SetBG("disabled", 0, 17)
	SetBG("checked", 18, 0)
	SetBG("disabledChecked", 18, 17)

	return cb
end

function utils.CreateLabel(parent, id, text, fontSize, align, r, g, b, a)
	local lbl = parent:CreateChildWidget("label", id, 0, true)
	lbl:SetText(text)
	if fontSize then
		lbl.style:SetFontSize(fontSize)
	end
	if align then
		lbl.style:SetAlign(align)
	end
	if r and g and b and a then
		lbl.style:SetColor(r, g, b, a)
	end
	return lbl
end

function utils.CreateEditBox(parent, id, guideText, width, height, maxLen)
	local edit = W_CTRL.CreateEdit(id, parent)
	if width and height then
		edit:SetExtent(width, height)
	end
	if maxLen then
		edit:SetMaxTextLength(maxLen)
	end
	if guideText then
		edit:CreateGuideText(guideText)
	end
	return edit
end

function utils.CreateComboBox(parent, items, width, height)
	local cb = api.Interface:CreateComboBox(parent)
	if width and height then
		cb:SetExtent(width, height)
	end
	if items then
		cb.dropdownItem = items
	end
	return cb
end

-- Ported scroll window logic
function utils.CreateScrollWindow(parent, ownId, index)
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

return utils
