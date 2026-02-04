local SolidLuau = require("solidluau")
local Bar = require("luau/components/bar")

local dsl = SolidLuau.ui
local reactivity = SolidLuau

local Tag = dsl.Tag

local div = Tag.div
local button = Tag.button
local image = Tag.image

local createSignal = reactivity.createSignal

local scale_x_target, set_scale_x_target = createSignal(1)

local function App()
  return div({
    class = "w-full h-full flex items-center justify-center bg-neutral-950",
  }){
    div({
      class = "px-6 py-3 rounded-xl border-2 border-blue-500 text-lg text-white cursor-pointer flex flex-col gap-2",
    }){
      button({
        class = "bg-neutral-700 hover:bg-neutral-800 text-amber-200",
        onClick = function()
            set_scale_x_target(math.max(scale_x_target() - 0.1, 0))
        end,
      }){ "Hover me" },
      image({
        class = "w-16 h-16",
        src = "assets/sprite.png",
      }),
      div({ class = "flex items-center gap-3" }){
        Bar.Track({ class = "h-6 w-64 rounded-full bg-red-500 border-2 border-black" }){
          Bar.Fill({
            class = "bg-green-500 rounded-full",
            percent = function()
              return scale_x_target() * 100
            end,
          }),
          Bar.Label({
            current = function()
              return math.floor(scale_x_target() * 100)
            end,
            max = 100
          }),
        },
      },
    },
  }
end

return App
