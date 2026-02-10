local SolidLuau = require("solidluau")
local Tag = SolidLuau.ui.Tag
local LoadUI = require("luau/ui/load_ui")

local function App()
  return LoadUI.from_spec(Tag.div({ key = "root", class = "w-full h-full bg-neutral-950 p-8 flex flex-col gap-8" }) {
    Tag.div({ key = "row_between", class = "w-full h-[140] bg-neutral-900 border-2 border-neutral-700 flex flex-row justify-between items-center gap-x-4 p-4" }) {
      Tag.div({ key = "a", class = "w-[80] h-[80] bg-blue-600" }) {},
      Tag.div({ key = "b", class = "w-[80] h-[80] bg-emerald-600" }) {},
      Tag.div({ key = "c", class = "w-[80] h-[80] bg-amber-500" }) {},
    },
    Tag.div({ key = "col_around", class = "w-full h-[220] bg-neutral-900 border-2 border-neutral-700 flex flex-col justify-around items-end content-center gap-y-2 p-4" }) {
      Tag.div({ key = "a", class = "w-[160] h-[30] bg-fuchsia-600" }) {},
      Tag.div({ key = "b", class = "w-[160] h-[30] bg-cyan-600" }) {},
      Tag.div({ key = "c", class = "w-[160] h-[30] bg-lime-600" }) {},
      Tag.div({ key = "d", class = "w-[160] h-[30] bg-rose-600" }) {},
    },
  })
end

return App
