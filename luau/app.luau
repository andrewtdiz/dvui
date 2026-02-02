local SolidLuau = require("solidluau")
local dsl = SolidLuau.ui
local reactivity = SolidLuau
local animation = SolidLuau.animation

local Tag = dsl.Tag
local For = dsl.For

local div = Tag.div
local h1 = Tag.h1
local p = Tag.p
local button = Tag.button

local createSignal = reactivity.createSignal
local selected_label, set_selected_label = createSignal("None")

local menuOptions = { "Play Game", "Load Game", "Settings", "Quit" }
for i = 1, 40 do
  menuOptions[#menuOptions + 1] = string.format("Option %d", i)
end

local function App()
  local menu_scale_target, set_menu_scale_target = createSignal(1)
  local menu_scale = animation.createSpring(menu_scale_target, { stiffness = 100, damping = 5 })

  return div({
    class = "w-full h-full flex flex-col justify-center items-center bg-neutral-950",
  }){
    div({
      class = "w-[220px] flex flex-col anchor-center items-center gap-6 bg-neutral-900 rounded-xl p-6",
      scale = menu_scale,
      onMouseLeave = function()
        set_menu_scale_target(1)
      end,
    }){
      h1({
        class = "text-4xl text-neutral-50 text-center text-nowrap",
        props = {
          visual = {
            fontRenderMode = "msdf",
            textOutlineColor = 0x000000ff,
            textOutlineThickness = 1,
          },
        },
      }){ "Main Menu" },
      div({
        class = "w-full h-px bg-neutral-700 opacity-60",
      })(),
      p({
        class = "text-sm w-full text-neutral-300 text-center",
      }){
        function()
          return string.format("selected: %s", selected_label())
        end,
      },
      div({
        class = "w-full h-[160px] flex flex-col gap-1 items-center overflow-y-scroll",
      }){
        For{
          each = function()
            return menuOptions
          end,
          key = function(label)
            return label
          end,
          children = function(label)
            return button({
              class = "w-full px-6 py-3 rounded-lg text-lg text-neutral-200 hover:text-amber-500 bg-transparent cursor-pointer",
              scale = menu_scale_target,
              props = {
                visual = {
                  fontRenderMode = "msdf",
                  textOutlineColor = 0x000000ff,
                  textOutlineThickness = 1,
                },
              },
              onMouseEnter = function()
                set_selected_label(label)
                set_menu_scale_target(1.15)
              end,
            }){ label }
          end,
        },
      },
      
      
    }
  }
end

return App
