local SolidLuau = require("solidluau")
local Tag = SolidLuau.ui.Tag
local LoadUI = require("luau/ui/load_ui")

local function App()
  return LoadUI.from_spec(Tag.div({ key = "root", class = "w-full h-full bg-neutral-950" }) {
    Tag.div({ key = "base", class = "absolute left-[240] top-[200] w-[360] h-[240] bg-blue-600 z-base" }) {},
    Tag.div({ key = "overlay", class = "absolute left-[320] top-[260] w-[360] h-[240] bg-amber-500 opacity-50 z-modal" }) {},
    Tag.div({ key = "behind", class = "absolute left-[260] top-[220] w-[120] h-[80] bg-fuchsia-600 -z-10" }) {},
  })
end

return App
