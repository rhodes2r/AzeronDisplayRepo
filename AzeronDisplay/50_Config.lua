local ns = _G.AzeronDisplayNS or {}
ns.modules = ns.modules or {}

local Config = ns.modules.Config or {}

function Config.CreateConfigSlider(parent, label, minVal, maxVal, step, fmt, getValue, setValue, yOffset)
  local container = CreateFrame("Frame", nil, parent)
  container:SetSize(340, 40)
  container:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOffset)

  local title = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
  title:SetText(label)

  local valueText = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  valueText:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)

  local slider = CreateFrame("Slider", nil, container, "OptionsSliderTemplate")
  slider:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -14)
  slider:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, -14)
  slider:SetMinMaxValues(minVal, maxVal)
  slider:SetValueStep(step)
  slider:SetObeyStepOnDrag(true)
  if slider.Low then slider.Low:SetText("") end
  if slider.High then slider.High:SetText("") end
  if slider.Text then slider.Text:SetText("") end

  slider:SetScript("OnValueChanged", function(self, val)
    if not self._ready then return end
    local rounded = step < 1 and (math.floor((val / step) + 0.5) * step) or math.floor(val + 0.5)
    valueText:SetText(string.format(fmt, rounded))
    setValue(rounded)
  end)

  local function Refresh()
    local v = getValue()
    slider._ready = false
    slider:SetValue(v)
    valueText:SetText(string.format(fmt, v))
    slider._ready = true
  end
  return container, Refresh
end

function Config.CreateConfigCheckbox(parent, label, getValue, setValue, x, y)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  local text = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
  text:SetText(label)
  cb:SetScript("OnClick", function(self)
    setValue(self:GetChecked() and true or false)
  end)
  local function Refresh()
    cb:SetChecked(getValue() and true or false)
  end
  return cb, Refresh
end

function Config.CreateConfigDropdown(parent, label, options, getValue, setValue, yOffset)
  local container = CreateFrame("Frame", nil, parent)
  container:SetSize(340, 56)
  container:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOffset)

  local title = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
  title:SetText(label)

  local dd = CreateFrame("Frame", nil, container, "UIDropDownMenuTemplate")
  dd:SetPoint("TOPLEFT", container, "TOPLEFT", -16, -16)
  UIDropDownMenu_SetWidth(dd, 180)
  UIDropDownMenu_JustifyText(dd, "LEFT")

  UIDropDownMenu_Initialize(dd, function(self, level)
    for _, opt in ipairs(options) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = opt.text
      info.value = opt.value
      info.checked = (getValue() == opt.value)
      info.func = function()
        UIDropDownMenu_SetSelectedValue(dd, opt.value)
        setValue(opt.value)
      end
      UIDropDownMenu_AddButton(info, level)
    end
  end)

  local function Refresh()
    local v = getValue()
    UIDropDownMenu_SetSelectedValue(dd, v)
    for _, opt in ipairs(options) do
      if opt.value == v then
        UIDropDownMenu_SetText(dd, opt.text)
        break
      end
    end
  end

  return container, Refresh
end

ns.modules.Config = Config
_G.AzeronDisplayNS = ns
