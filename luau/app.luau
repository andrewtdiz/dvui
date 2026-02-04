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

local scale_x_target, set_scale_x_target = createSignal(1)

local function App()
    local scale_x = animation.createTween(scale_x_target, { duration = 0.35, easing = animation.easing.outQuad })

  return div({
    class = "w-full h-full flex items-center justify-center bg-neutral-950",
  }){
    div({
      class = "px-6 py-3 rounded-xl text-lg bg-amber-700 text-white cursor-pointer flex flex-col gap-2",
    }){
      button({
        class = "bg-neutral-700 hover:bg-neutral-800 text-amber-200",
        onClick = function()
            set_scale_x_target(math.max(scale_x_target() - 0.1, 0))
        end,
      }){ "Hover me" },
      image({
        class = "w-16 h-16",
        props = {
          src = "assets/sprite.png",
        },
      })(),
      div({ class = "w-64 h-6 p-0.5 bg-red-500 rounded-full border-2 border-black"}) {
          div({
            class = "w-full h-full bg-white rounded-full",
            props = {
              transform = { scaleX = scale_x, anchorX = 0, anchorY = 0 },
            },
          })(),
          p({ class = "absolute left-[50%] top-[50%] anchor-center text-black font-bold"}){ scale_x }
      },
    },
  }
end

return App
