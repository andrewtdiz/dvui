local SolidLuau = require("solidluau")
local Tag = SolidLuau.ui.Tag
local LoadUI = require("luau/ui/load_ui")

local function App()
  return LoadUI.from_spec(Tag.div({ key = "root", class = "w-full h-full bg-neutral-950 flex items-center justify-center p-8" }) {
    Tag.div({ key = "card", class = "bg-neutral-900 border-2 border-neutral-700 p-8 flex flex-col gap-6" }) {
      Tag.div({ key = "border1", class = "w-[320] h-[72] bg-neutral-800 border border-blue-500 rounded" }) {},
      Tag.div({ key = "border2", class = "w-[320] h-[72] bg-neutral-800 border-x-4 border-y-2 border-x-emerald-500 border-y-amber-500 rounded-xl" }) {},
      Tag.div({ key = "border3", class = "w-[320] h-[72] bg-neutral-800 border-t-4 border-r-2 border-b-6 border-l-1 border-t-red-500 border-r-cyan-500 border-b-lime-500 border-l-fuchsia-500 rounded-full" }) {},
      Tag.div({ key = "border4", class = "w-[320] h-[72] bg-neutral-800 border-px border-neutral-200 rounded-3xl" }) {},
    },
  })
end

return App
