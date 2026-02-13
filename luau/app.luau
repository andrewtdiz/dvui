local SolidLuau = require("solidluau")

local reactivity = SolidLuau
local animation = SolidLuau.animation
local Tag = SolidLuau.ui.Tag

local UI = require("luau/ui_gen/app_ui")
local LoadUI = require("luau/ui/load_ui")
local hydrate = require("ui/hydrate")
local Toggle = require("luau/components/toggle")
local Checkbox = require("luau/components/checkbox")

local createSignal = reactivity.createSignal

local scale_x_target, set_scale_x_target = createSignal(1)

local function clamp01(n)
  if n < 0 then
    return 0
  end
  if n > 1 then
    return 1
  end
  return n
end

local function App()
  local function scale_value()
    return clamp01(scale_x_target())
  end

  local scaleX = animation.createTween(scale_value, { duration = 0.3, easing = animation.easing.outCubic })
  local toggle_off, set_toggle_off = createSignal(false)
  local toggle_on, set_toggle_on = createSignal(true)
  local checked, set_checked = createSignal(false)

  local root: UI.Node_root = LoadUI.from_json("luau/ui_json/app.json")
  local root_any = root :: any
  local start_menu = root_any.StartMenu
  local card = root.card
  local row = card.row
  local track = row.track

  local toggles = LoadUI.attach(card, Tag.div({ key = "toggles", class = "flex items-center gap-3" }) {
    Toggle({ key = "off", on = toggle_off, onChange = set_toggle_off }),
    Toggle({ key = "on", on = toggle_on, onChange = set_toggle_on }),
    Checkbox({ key = "checkbox", checked = checked, onChange = set_checked }),
  })

  local scroll_demo = LoadUI.attach(start_menu, Tag.div({
    key = "ScrollDemo",
    class = "w-full h-[108] mt-4 bg-transparent border border-neutral-700 rounded-md overflow-y-scroll",
    scroll = { scrollY = 0 },
  }) {
    Tag.div({ key = "content", class = "relative w-full h-[360]" }) {
      Tag.p({ key = "title", class = "absolute left-[12] top-[10] text-sm text-neutral-200" }) { "Scroll Preview" },
      Tag.p({ key = "line1", class = "absolute left-[12] top-[44] text-sm text-neutral-400" }) { "Item 01  Potion" },
      Tag.p({ key = "line2", class = "absolute left-[12] top-[72] text-sm text-neutral-400" }) { "Item 02  Ether" },
      Tag.p({ key = "line3", class = "absolute left-[12] top-[100] text-sm text-neutral-400" }) { "Item 03  Elixir" },
      Tag.p({ key = "line4", class = "absolute left-[12] top-[128] text-sm text-neutral-400" }) { "Item 04  Hi-Potion" },
      Tag.p({ key = "line5", class = "absolute left-[12] top-[156] text-sm text-neutral-400" }) { "Item 05  Remedy" },
      Tag.p({ key = "line6", class = "absolute left-[12] top-[184] text-sm text-neutral-400" }) { "Item 06  Antidote" },
      Tag.p({ key = "line7", class = "absolute left-[12] top-[212] text-sm text-neutral-400" }) { "Item 07  Phoenix Down" },
      Tag.p({ key = "line8", class = "absolute left-[12] top-[240] text-sm text-neutral-400" }) { "Item 08  Tent" },
      Tag.p({ key = "line9", class = "absolute left-[12] top-[268] text-sm text-neutral-400" }) { "Item 09  Gold Needle" },
      Tag.p({ key = "line10", class = "absolute left-[12] top-[296] text-sm text-neutral-400" }) { "Item 10  Smoke Bomb" },
      Tag.p({ key = "line11", class = "absolute left-[12] top-[324] text-sm text-neutral-400" }) { "Item 11  Magic Water" },
    },
  })

  hydrate(card.button){
    onClick = function()
      set_scale_x_target(math.max(scale_x_target() - 0.1, 0))
    end,
  }

  hydrate(track.fill){
    transform = {
      scaleX = scaleX,
      anchorX = 0,
      anchorY = 0,
    },
  }

  hydrate(track.label){
    children = function()
      return string.format("%s/%s", tostring(math.floor(scale_x_target() * 100)), tostring(100))
    end,
  }

  hydrate(card){
    children = {
      card.button,
      card.icon,
      card.row,
      toggles,
    },
  }

  hydrate(start_menu){
    children = {
      start_menu.Subtitle,
      start_menu.StartButton,
      start_menu.OptionsButton,
      start_menu.QuitButton,
      scroll_demo,
    },
  }

  return root
end

return App
