local SolidLuau = require("solidluau")

local dsl = SolidLuau.ui
local reactivity = SolidLuau
local animation = SolidLuau.animation

local Tag = dsl.Tag

local div = Tag.div
local button = Tag.button
local p = Tag.p
local image = Tag.image

local createSignal = reactivity.createSignal

local scale_target, set_scale_target = createSignal(1)

local function App()
    local scale = animation.createSpring(scale_target, { stiffness = 340, damping = 20 })

  return div({
    class = "w-full h-full flex items-center justify-center bg-neutral-950",
  }){
    div({
      class = "px-6 py-3 rounded-xl text-lg border-2 border-amber-600 bg-transparent text-white cursor-pointer flex flex-col gap-2",
    }){
      button({ class = "bg-neutral-700 hover:bg-neutral-800 hover:ml-2 ml-0 text-amber-200" }){ "Hover me" },
      image({
        class = "w-40 h-40 rounded-xl border-2 border-amber-600 bg-neutral-900",
        scale = scale,
        props = {
          src = "assets/sprite.png",
        },
        onMouseEnter = function()
          set_scale_target(1.15)
        end,
        onMouseLeave = function()
          set_scale_target(1)
        end,
      })(),
    },
  }
end

return App
