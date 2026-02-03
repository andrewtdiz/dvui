local SolidLuau = require("solidluau")
local reactivity = SolidLuau
local animation = SolidLuau.animation

local Template = require("luau/ui_gen/app_ui")
local hydrate = SolidLuau.ui.hydrate

local createSignal = reactivity.createSignal

local function App()
  local scale_target, set_scale_target = createSignal(1)
  local scale = animation.createTween(scale_target, {
    duration = 0.3,
    easing = animation.easing.outBack,
  })

  local tree = Template.create()

  hydrate(tree.cta) {
    scale = scale,
    onMouseEnter = function()
      set_scale_target(1.4)
    end,
    onMouseLeave = function()
      set_scale_target(1)
    end,
    onMouseDown = function()
      set_scale_target(0.85)
    end,
    onMouseUp = function()
      set_scale_target(1.4)
    end,
  }

  return tree
end

return App
