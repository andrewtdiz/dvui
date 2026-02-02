local dsl = require("scripts/ui_features_decl/dsl")
local reactivity = require("scripts/ui_features_decl/reactivity")
local animation = require("scripts/ui_features_decl/animation")

local Tag = dsl.Tag
local For = dsl.For

local div = Tag.div
local h1 = Tag.h1
local p = Tag.p
local button = Tag.button

local source = reactivity.source
local selected_label = source("None")

local menuOptions = { "Play Game", "Load Game", "Settings", "Quit" }
for i = 1, 40 do
  menuOptions[#menuOptions + 1] = string.format("Option %d", i)
end

local function App()
  local menu_scale_target = source(1)
  local menu_scale = animation.spring(menu_scale_target, 0.2, 1)

  return div({
    class = "w-full h-full flex flex-col justify-center items-center bg-neutral-950",
  }){
    div({
      class = "w-[220px] flex flex-col anchor-center items-center gap-6 bg-neutral-900 rounded-xl p-6",
      scale = menu_scale,
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
      div({
        class = "w-full h-3 bg-amber-500 opacity-80",
        props = {
          transform = {
            translateX = 16,
            translateY = 4,
          },
        },
      })(),
      p({
        class = "text-sm text-neutral-300 text-center",
      }){
        function()
          return string.format("Selected: %s", selected_label())
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
              props = {
                visual = {
                  fontRenderMode = "msdf",
                  textOutlineColor = 0x000000ff,
                  textOutlineThickness = 1,
                },
              },
              onMouseEnter = function()
                selected_label(label)
              end,
            }){ label }
          end,
        },
      },
      
      
    }
  }
end

return App
