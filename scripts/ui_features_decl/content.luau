local dsl = require("scripts/ui_features_decl/dsl")
local reactivity = require("scripts/ui_features_decl/reactivity")
local animation = require("scripts/ui_features_decl/animation")

local Create = dsl.Create
local For = dsl.For

local source = reactivity.source
local selected_label = source("None")

local menuOptions = { "Play Game", "Load Game", "Settings", "Quit" }
for i = 1, 40 do
  menuOptions[#menuOptions + 1] = string.format("Option %d", i)
end

local function UiFeatures()
  local menu_scale_target = source(1)
  local menu_scale = animation.spring(menu_scale_target, 0.4, 1)

  return Create("div"){
    class = "w-full h-full flex flex-col justify-center items-center bg-neutral-950",
    children = {
      Create("div"){
        class = "w-[320px] flex flex-col items-center gap-6 bg-neutral-900 border border-neutral-700 rounded-xl p-6",
        scale = menu_scale,
        onMouseLeave = function()
          menu_scale_target(1)
        end,
        children = {
          Create("h1"){
            class = "text-4xl text-neutral-50 text-outline-black text-outline-[1px] text-center text-nowrap",
            children = { "Main Menu" },
          },
          Create("div"){
            class = "w-full h-px bg-neutral-700 opacity-60",
          },
          Create("p"){
            class = "text-sm text-neutral-300 text-center",
            children = {
              function()
                return string.format("Selected: %s", selected_label())
              end,
            },
          },
          Create("div"){
            class = "w-full h-[160px] flex flex-col gap-1 items-center overflow-y-scroll",
            children = For{
              each = function()
                return menuOptions
              end,
              key = function(label)
                return label
              end,
              children = function(label)
                return Create("button"){
                  class = "w-full px-6 py-3 rounded-lg text-lg text-neutral-200 hover:text-amber-300 hover:bg-neutral-800 text-outline-black text-outline-[1px] cursor-pointer",
                  onMouseEnter = function()
                    selected_label(label)
                    menu_scale_target(1.13)
                  end,
                  children = { label },
                }
              end,
            },
          },
        },
      },
    },
  }
end

return UiFeatures
