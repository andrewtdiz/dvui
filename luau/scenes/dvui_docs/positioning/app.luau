local SolidLuau = require("solidluau")
local Tag = SolidLuau.ui.Tag
local LoadUI = require("luau/ui/load_ui")

local function App()
  return LoadUI.from_spec(Tag.div({ key = "root", class = "w-full h-full bg-neutral-950 flex items-center justify-center" }) {
    Tag.div({ key = "stage", class = "w-[640] h-[360] bg-neutral-900 border-2 border-neutral-700 overflow-hidden" }) {
      Tag.div({ key = "tl", class = "absolute left-0 top-0 w-[96] h-[72] bg-blue-600 anchor-top-left" }) {},
      Tag.div({ key = "br", class = "absolute right-2 bottom-2 w-[96] h-[72] bg-emerald-600 anchor-bottom-right" }) {},
      Tag.div({ key = "center", class = "absolute left-[50%] top-[50%] w-[96] h-[96] bg-amber-500 anchor-center" }) {},
      Tag.div({ key = "neg", class = "absolute left-[-24] top-[80] w-[96] h-[72] bg-fuchsia-600 anchor-top-left" }) {},
      Tag.div({ key = "px", class = "absolute left-px top-px w-px h-px bg-white anchor-top-left" }) {},
      Tag.div({ key = "percent", class = "absolute right-[10%] top-[15%] w-[96] h-[72] bg-cyan-600 anchor-top-right" }) {},
    },
  })
end

return App
