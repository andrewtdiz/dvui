local SolidLuau = require("solidluau")

local reactivity = SolidLuau
local animation = SolidLuau.animation
local Tag = SolidLuau.ui.Tag

local UI = require("luau/ui_gen/app_ui")
local LoadUI = require("luau/ui/load_ui")
local hydrate = require("ui/hydrate")
local Toggle = require("luau/components/toggle")
local Checkbox = require("luau/components/checkbox")

local createSignal = reactivity.createSignal

local scale_x_target, set_scale_x_target = createSignal(1)

local function clamp01(n)
  if n < 0 then
    return 0
  end
  if n > 1 then
    return 1
  end
  return n
end

local function App()
  local function scale_value()
    return clamp01(scale_x_target())
  end

  local scaleX = animation.createTween(scale_value, { duration = 0.3, easing = animation.easing.outCubic })
  local toggle_off, set_toggle_off = createSignal(false)
  local toggle_on, set_toggle_on = createSignal(true)
  local checked, set_checked = createSignal(false)

  local root: UI.Node_root = LoadUI.from_json("luau/ui_json/app.json")
  local card = root.card
  local row = card.row
  local track = row.track

  hydrate(card.button){
    onClick = function()
      set_scale_x_target(math.max(scale_x_target() - 0.1, 0))
    end,
  }

  hydrate(track.fill){
    transform = {
      scaleX = scaleX,
      anchorX = 0,
      anchorY = 0,
    },
  }

  hydrate(track.label){
    children = function()
      return string.format("%s/%s", tostring(math.floor(scale_x_target() * 100)), tostring(100))
    end,
  }

  hydrate(card){
    children = {
      card.button,
      card.icon,
      card.row,
      Tag.div({ class = "flex items-center gap-3 __key=root.card.toggles" }) {
        Toggle({ on = toggle_off, onChange = set_toggle_off, class = "__key=root.card.toggles.off" }),
        Toggle({ on = toggle_on, onChange = set_toggle_on, class = "__key=root.card.toggles.on" }),
        Checkbox({ checked = checked, onChange = set_checked, class = "__key=root.card.toggles.checkbox" }),
      },
    },
  }

  return root
end

return App
