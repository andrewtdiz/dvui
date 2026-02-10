local SolidLuau = require("solidluau")
local Tag = SolidLuau.ui.Tag
local LoadUI = require("luau/ui/load_ui")

local function App()
  return LoadUI.from_spec(Tag.div({ key = "root", class = "w-full h-full bg-neutral-950 p-8 flex flex-col gap-6" }) {
    Tag.h1({ key = "h1", class = "text-3xl text-white font-ui font-bold" }) { "Heading One" },
    Tag.h2({ key = "h2", class = "text-2xl text-neutral-200 font-render-msdf" }) { "Heading Two" },
    Tag.h3({ key = "h3", class = "text-xl text-neutral-300" }) { "Heading Three" },
    Tag.div({ key = "box", class = "w-[520] bg-neutral-900 border border-neutral-700 p-4 flex flex-col gap-3" }) {
      Tag.p({ key = "p1", class = "text-sm text-neutral-100 text-outline-2 text-outline-black break-words font-mono italic" }) {
        "LongWordWithoutSpaces_0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ",
      },
      Tag.p({ key = "p2", class = "text-sm text-neutral-200 text-nowrap" }) { "This line should not wrap even if it is long." },
      Tag.p({ key = "p3", class = "text-sm text-neutral-200 text-center" }) { "Centered text" },
    },
  })
end

return App
