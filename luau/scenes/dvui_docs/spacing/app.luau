local SolidLuau = require("solidluau")
local Tag = SolidLuau.ui.Tag
local LoadUI = require("luau/ui/load_ui")

local function App()
  return LoadUI.from_spec(Tag.div({ key = "root", class = "w-full h-full bg-neutral-950 p-8 flex flex-row gap-8 items-start" }) {
    Tag.div({ key = "panel", class = "bg-neutral-900 border-2 border-neutral-700 p-6 flex flex-col gap-4" }) {
      Tag.div({ key = "m_all", class = "w-[160] h-[48] bg-blue-600 m-4" }) {},
      Tag.div({ key = "m_sides", class = "w-[160] h-[48] bg-emerald-600 mt-6 mr-2 mb-1 ml-0" }) {},
      Tag.div({ key = "padded", class = "w-[220] h-[140] bg-neutral-800 border border-neutral-600 p-4" }) {
        Tag.div({ key = "child", class = "w-full h-full bg-amber-500" }) {},
      },
    },
  })
end

return App
