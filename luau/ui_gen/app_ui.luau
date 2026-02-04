local Types = require("ui/types")

export type Key = "cta" | "root"

export type Node_cta = Types.UINode & {
  parent: Types.UINode?,
}

export type Node_root = Types.UINode & {
  parent: Types.UINode?,
  cta: Node_cta,
}

export type UI = {
  root: Node_root,
}

export type Patches = { [Types.UINode]: Types.NodePatch }

local function link_parents(node: Types.UINode, parent: Types.UINode?)
  node.parent = parent
  local children = node.children
  if type(children) ~= "table" then
    return
  end
  if children.tag ~= nil then
    link_parents(children, node)
    return
  end
  if children.__kind ~= nil then
    return
  end
  for _, child in ipairs(children) do
    if type(child) == "table" and child.tag ~= nil then
      link_parents(child, node)
    end
  end
end

local function create(): UI
  local node_cta = {
    tag = "div",
    key = "cta",
    class = "h-64 w-64 rounded-xl text-lg hover:scale[1.3] text-neutral-700 bg-amber-400 cursor-pointer",
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
  link_parents(node_root, nil)
  return { root = node_root }
end

local UI = create()
UI.create = create
return UI
