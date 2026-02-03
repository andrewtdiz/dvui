local Types = require("luau/ui/types")

export type Key = "cta" | "root"

export type Patches = { [Key]: Types.NodePatch }

local function create(): Types.UINode
  local node_cta = {
    tag = "button",
    key = "cta",
    class = "px-6 py-3 rounded-xl text-lg text-neutral-900 bg-amber-400 cursor-pointer",
    children = {
      "Hover Me",
    },
  }

  local node_root = {
    tag = "div",
    key = "root",
    class = "w-full h-full flex items-center justify-center bg-neutral-950",
    children = {
      node_cta,
    },
  }

  node_root.cta = node_cta
  return node_root
end

return {
  create = create,
}
