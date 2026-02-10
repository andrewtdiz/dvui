local SolidLuau = require("solidluau")
local Tag = SolidLuau.ui.Tag
local LoadUI = require("luau/ui/load_ui")

local function App()
  return LoadUI.from_spec(Tag.div({ key = "root", class = "w-full h-full bg-neutral-950 flex flex-row gap-8 items-center justify-center p-8" }) {
    Tag.div({ key = "clip", class = "w-[360] h-[240] bg-neutral-900 border-2 border-neutral-700 overflow-hidden" }) {
      Tag.div({ key = "child", class = "absolute left-[-60] top-[-40] w-[520] h-[360] bg-blue-600" }) {},
    },
    Tag.div({ key = "scroll", class = "w-[360] h-[240] bg-neutral-900 border-2 border-neutral-700 overflow-scroll" }) {
      Tag.div({ key = "child", class = "absolute left-[-60] top-[-40] w-[520] h-[360] bg-amber-500" }) {},
    },
  })
end

return App
