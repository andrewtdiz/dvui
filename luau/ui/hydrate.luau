local Types = require("luau/ui/types")

local function normalize_class_text(v)
  if v == nil then
    return ""
  end
  if type(v) == "string" then
    return v
  end
  return tostring(v)
end

local function join_class_text(a, b)
  if a == "" then
    return b
  end
  if b == "" then
    return a
  end
  return a .. " " .. b
end

local function join_class(base, patch)
  if patch == nil then
    return base
  end
  if base == nil then
    return patch
  end

  if type(base) == "string" and type(patch) == "string" then
    return join_class_text(base, patch)
  end

  if type(base) == "function" or type(patch) == "function" then
    local base_fn = if type(base) == "function" then base else function()
      return base
    end
    local patch_fn = if type(patch) == "function" then patch else function()
      return patch
    end
    return function()
      local a = normalize_class_text(base_fn())
      local b = normalize_class_text(patch_fn())
      return join_class_text(a, b)
    end
  end

  return patch
end

local function merge_props(base, patch)
  if patch == nil then
    return base
  end
  if base == nil then
    return patch
  end
  if type(base) ~= "table" or type(patch) ~= "table" then
    return patch
  end
  for k, v in pairs(patch) do
    base[k] = v
  end
  return base
end

local function apply_patch(node: Types.UINode, patch: Types.NodePatch)
  node.class = join_class(node.class, patch.class)
  node.props = merge_props(node.props, patch.props)

  if patch.scale ~= nil then
    node.scale = patch.scale
  end
  if patch.children ~= nil then
    node.children = patch.children
  end
  if patch.onClick ~= nil then
    node.onClick = patch.onClick
  end
  if patch.onMouseEnter ~= nil then
    node.onMouseEnter = patch.onMouseEnter
  end
  if patch.onMouseLeave ~= nil then
    node.onMouseLeave = patch.onMouseLeave
  end
  if patch.onMouseDown ~= nil then
    node.onMouseDown = patch.onMouseDown
  end
  if patch.onMouseUp ~= nil then
    node.onMouseUp = patch.onMouseUp
  end
  if patch.onInput ~= nil then
    node.onInput = patch.onInput
  end
  if patch.onFocus ~= nil then
    node.onFocus = patch.onFocus
  end
  if patch.onBlur ~= nil then
    node.onBlur = patch.onBlur
  end
  if patch.onEnter ~= nil then
    node.onEnter = patch.onEnter
  end
end

local function hydrate_by_key_inner(node: Types.UINode, patches_by_key: { [string]: Types.NodePatch }, used: { [string]: boolean })
  local key = node.key
  if type(key) == "string" then
    local patch = patches_by_key[key]
    if patch ~= nil then
      used[key] = true
      apply_patch(node, patch)
    end
  end

  local children = node.children
  if type(children) ~= "table" then
    return
  end
  for _, child in ipairs(children) do
    if type(child) == "table" and child.tag ~= nil then
      hydrate_by_key_inner(child, patches_by_key, used)
    end
  end
end

local function hydrate_by_key(root: Types.UINode, patches_by_key: { [string]: Types.NodePatch }?): Types.UINode
  if patches_by_key == nil then
    return root
  end

  local used: { [string]: boolean } = {}
  hydrate_by_key_inner(root, patches_by_key, used)

  for k in pairs(patches_by_key) do
    if type(k) == "string" and not used[k] then
      error("hydrate: unknown key: " .. k, 0)
    end
  end

  return root
end

local function hydrate_children(node: Types.UINode, children: { any })
  node.children = children
  return node
end

local function hydrate(node: Types.UINode)
  return function(spec: any)
    if spec == nil then
      return node
    end

    if type(spec) ~= "table" then
      return hydrate_children(node, { spec })
    end

    local has_named_keys = false
    for k in pairs(spec) do
      if type(k) == "string" then
        has_named_keys = true
        break
      end
    end

    if has_named_keys then
      apply_patch(node, spec)

      local children: { any } = {}
      for _, v in ipairs(spec) do
        children[#children + 1] = v
      end
      if #children > 0 then
        node.children = children
      end

      return node
    end

    local children: { any } = {}
    for _, v in ipairs(spec) do
      children[#children + 1] = v
    end
    node.children = children

    return node
  end
end

local Hydrate = {
  by_key = hydrate_by_key,
}

return setmetatable(Hydrate, {
  __call = function(_, node: Types.UINode)
    return hydrate(node)
  end,
})
