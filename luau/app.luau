local SolidLuau = require("solidluau")
local dsl = SolidLuau.ui
local reactivity = SolidLuau
local animation = SolidLuau.animation

local Tag = dsl.Tag

local div = Tag.div
local button = Tag.button

local createSignal = reactivity.createSignal

local function App()
  local scale_target, set_scale_target = createSignal(1)
  local scale = animation.createSpring(scale_target, { stiffness = 140, damping = 9 })

  return div({
    class = "w-full h-full flex items-center justify-center bg-neutral-950",
  }){
    button({
      class = "px-6 py-3 rounded-xl text-lg text-neutral-900 bg-amber-400 cursor-pointer",
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
    }){ "Hover Me" },
  }
end

return App
