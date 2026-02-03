local SolidLuau = require("solidluau")
local reactivity = SolidLuau
local animation = SolidLuau.animation

local Template = require("luau/ui_gen/app_ui")
local hydrate = require("luau/ui/hydrate")

local createSignal = reactivity.createSignal

local function App()
  local scale_target, set_scale_target = createSignal(1)
  local scale = animation.createSpring(scale_target, { stiffness = 140, damping = 9 })

  local tree = Template.create()

  hydrate(tree.cta) {
    scale = scale,
    onMouseEnter = function()
      set_scale_target(1.1)
    end,
    onMouseLeave = function()
      set_scale_target(1)
    end,
    onMouseDown = function()
      set_scale_target(0.85)
    end,
    onMouseUp = function()
      set_scale_target(1.1)
    end,
  }

  return tree
end

return App
