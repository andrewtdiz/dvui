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
      button({ class = "bg-neutral-700 hover:bg-neutral-800 text-amber-200" }){ "Hover me" },
      image({
        class = "w-16 h-16",
        props = {
          src = "assets/sprite.png",
        },
      })(),
    },
  }
end

return App
