local Types = require("luau/ui/types")

export type Key = "cta" | "root"

export type Patches = { [Key]: Types.NodePatch }

local function create(): Types.UINode
  local node_cta = {
    tag = "div",
    key = "cta",
    "class": "h-64 w-64 rounded-xl text-lg hover:scale[1.3] text-neutral-700 bg-amber-400 cursor-pointer",
  }

  local node_root = {
    tag = "div",
    class = "w-full h-full bg-slate-950 text-slate-100 flex items-center justify-center",
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
