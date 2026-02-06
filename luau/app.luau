local SolidLuau = require("solidluau")

local reactivity = SolidLuau
local animation = SolidLuau.animation

local UI = require("luau/ui_gen/app_ui")
local LoadUI = require("luau/ui/load_ui")
local hydrate = require("ui/hydrate")

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

  local root: UI.Node_root = LoadUI.from_json("luau/ui_json/app.json")
  local card = root.card
  local row = card.row
  local track = row.track
  local tooltip = root.tooltip

  hydrate(card.button){
    onClick = function()
      set_scale_x_target(math.max(scale_x_target() - 0.1, 0))
    end,
  }

  hydrate(tooltip){
    anchor = {
      anchorId = 3,
      side = "top",
      align = "center",
      offset = 10,
    },
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

  return root
end

return App
