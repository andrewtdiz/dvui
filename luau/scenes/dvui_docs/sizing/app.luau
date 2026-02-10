local SolidLuau = require("solidluau")
local Tag = SolidLuau.ui.Tag
local LoadUI = require("luau/ui/load_ui")

local function App()
  return LoadUI.from_spec(Tag.div({ key = "root", class = "w-screen h-screen bg-neutral-950 p-8 flex flex-col gap-8" }) {
    Tag.div({ key = "row", class = "flex flex-row gap-8 items-start" }) {
      Tag.div({ key = "px", class = "w-px h-px bg-white" }) {},
      Tag.div({ key = "scaled", class = "w-10 h-6 bg-blue-600" }) {},
      Tag.div({ key = "bracket", class = "w-[13px] h-[17] bg-emerald-600" }) {},
      Tag.div({ key = "base", class = "w-[100] h-[100] bg-neutral-800" }) {},
      Tag.div({ key = "scale50", class = "w-[100] h-[100] bg-neutral-800 scale-50" }) {},
      Tag.div({ key = "scale2", class = "w-[100] h-[100] bg-neutral-800 scale-[2]" }) {},
    },
    Tag.div({ key = "full_box", class = "w-[240] h-[240] bg-neutral-900 border-2 border-neutral-700 p-4" }) {
      Tag.div({ key = "child", class = "w-full h-full bg-cyan-600" }) {},
    },
  })
end

return App
